/// Platform utilities for resolving real user paths on macOS.
///
/// On macOS, sandboxed apps get a container home at
/// `~/Library/Containers/<bundle-id>/Data/` instead of the real user home.
/// This module provides helpers to resolve the actual user home directory,
/// patch environment variables for subprocesses, and read files that may
/// be outside the sandbox container.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../utils/app_log.dart';

/// Detect the real user home directory, bypassing the macOS app container.
///
/// On macOS, when running inside a sandbox container, `Platform.environment['HOME']`
/// returns something like `/Users/alice/Library/Containers/com.example.app/Data/`
/// instead of `/Users/alice/`. This function detects that and returns the real home.
///
/// On Linux/Windows, returns `Platform.environment['HOME']` as-is.
String realHome() {
  final envHome = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  // macOS container pattern: /Users/<name>/Library/Containers/<bundle-id>/Data
  final containerPattern = RegExp(r'^(\/Users\/[^/]+)\/Library\/Containers\/');
  final match = containerPattern.firstMatch(envHome);
  if (match != null) {
    return match.group(1)!;
  }
  return envHome;
}

/// Whether the app is running inside a macOS sandbox container.
bool isSandboxed() {
  final envHome = Platform.environment['HOME'] ?? '';
  return envHome.contains('/Library/Containers/');
}

/// Build an environment map with HOME overridden to the real user home.
///
/// Use this when running subprocesses (like `uc`) that need to find config
/// files at `~/.config/uncloud/config.yaml` — passing the container HOME
/// would cause them to look in the wrong directory.
Map<String, String> realHomeEnvironment() {
  final env = Map<String, String>.from(Platform.environment);
  env['HOME'] = realHome();
  return env;
}

/// Read a file, working around macOS sandbox restrictions.
///
/// When running in a sandboxed App Store build, direct `File(path).readAsString()`
/// is blocked for files outside the container. This method tries multiple
/// strategies:
///
/// 1. Direct file read (works in dev/unsandboxed builds)
/// 2. If sandboxed, try `Process.run('/bin/cat', [path])` with real HOME env
///    (subprocess inherits sandbox but `/bin/cat` may have broader read access)
/// 3. Try reading via shell with tilde expansion resolved to real HOME
///
/// Returns `null` if all methods fail (caller should handle gracefully).
Future<String?> readFileSandboxAware(String path) async {
  // Strategy 1: Direct read (works in dev builds and for files inside container)
  try {
    final file = File(path);
    if (await file.exists()) {
      final content = await file.readAsString();
      AppLog.debug('Direct read succeeded for $path');
      return content;
    }
  } catch (e) {
    AppLog.debug('Direct read failed for $path: $e');
  }

  // If not sandboxed, the file truly doesn't exist
  if (!isSandboxed()) {
    AppLog.debug('Not sandboxed and direct read failed — file does not exist: $path');
    return null;
  }

  // Strategy 2: In sandbox, try `cat` with real HOME environment
  try {
    AppLog.info('Trying subprocess read for $path (sandbox workaround)');
    final result = await Process.run(
      '/bin/cat',
      [path],
      environment: realHomeEnvironment(),
    );
    if (result.exitCode == 0) {
      final content = (result.stdout as String).trim();
      if (content.isNotEmpty) {
        AppLog.info('Subprocess read succeeded for $path');
        return content;
      }
    } else {
      AppLog.debug('cat exited ${result.exitCode}: ${(result.stderr as String).trim()}');
    }
  } catch (e) {
    AppLog.debug('Subprocess read failed for $path: $e');
  }

  // Strategy 3: Try shell with tilde expansion resolved to real HOME
  try {
    final home = realHome();
    final expandedPath = path.replaceFirst('~/', '$home/').replaceFirst('~', home);
    if (expandedPath != path) {
      final result = await Process.run(
        '/bin/cat',
        [expandedPath],
        environment: realHomeEnvironment(),
      );
      if (result.exitCode == 0) {
        final content = (result.stdout as String).trim();
        if (content.isNotEmpty) {
          AppLog.info('Expanded path read succeeded: $expandedPath');
          return content;
        }
      }
    }
  } catch (e) {
    AppLog.debug('Expanded path read failed: $e');
  }

  AppLog.warning('All read strategies failed for $path — file may be outside sandbox');
  return null;
}

/// Get the path to the app's support directory for caching config copies.
///
/// When we can read a config file from outside the sandbox, we cache it
/// here so subsequent reads work even if sandbox restrictions tighten.
Future<String> getConfigCachePath(String filename) async {
  final supportDir = await getApplicationSupportDirectory();
  return '${supportDir.path}/config_cache/$filename';
}

/// Cache config content to the app support directory.
///
/// Returns the cache path on success, null on failure.
Future<String?> cacheConfigContent(String filename, String content) async {
  try {
    final cachePath = await getConfigCachePath(filename);
    final file = File(cachePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    AppLog.info('Cached config to $cachePath');
    return cachePath;
  } catch (e) {
    AppLog.warning('Failed to cache config $filename: $e');
    return null;
  }
}

/// Read a cached config from the app support directory.
///
/// Returns the cached content, or null if no cache exists.
Future<String?> readCachedConfig(String filename) async {
  try {
    final cachePath = await getConfigCachePath(filename);
    final file = File(cachePath);
    if (await file.exists()) {
      final content = await file.readAsString();
      AppLog.debug('Read cached config from $cachePath');
      return content;
    }
  } catch (e) {
    AppLog.debug('No cached config for $filename: $e');
  }
  return null;
}
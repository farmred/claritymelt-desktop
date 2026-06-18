/// Platform utilities for resolving real user paths on macOS.
///
/// On macOS, sandboxed apps get a container home at
/// `~/Library/Containers/<bundle-id>/Data/` instead of the real user home.
/// This module provides helpers to resolve the actual user home directory
/// and patch environment variables for subprocesses.
library;

import 'dart:io';

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
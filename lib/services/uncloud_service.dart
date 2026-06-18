/// Uncloud client for ClarityMelt.
///
/// Reads `~/.config/uncloud/config.yaml` for connection details and
/// machine IDs, runs `uc` CLI commands for live cluster data, and matches
/// machines by IP to associate Uncloud IDs back to ClarityMelt machines
/// in the database.
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../database/database.dart';
import '../utils/app_log.dart';
import '../utils/platform_utils.dart';

// ── Config models ───────────────────────────────────────────────────────

/// A single Uncloud context (cluster connection details).
class UncloudContext {
  final String name;
  final List<UncloudConnection> connections;

  UncloudContext({required this.name, required this.connections});

  UncloudConnection? get primary =>
      connections.isNotEmpty ? connections.first : null;

  List<String> get machineIds =>
      connections.where((c) => c.machineId != null).map((c) => c.machineId!).toList();

  List<String> get sshTargets =>
      connections.map((c) => c.sshTarget).toList();
}

/// A single connection within a context.
class UncloudConnection {
  final String? ssh;
  final String? sshGo;
  final String? tcp;
  final String? unix;
  final String? sshKeyFile;
  final String? machineId;

  UncloudConnection({
    this.ssh,
    this.sshGo,
    this.tcp,
    this.unix,
    this.sshKeyFile,
    this.machineId,
  });

  /// The SSH target string (user@host[:port] or host alias).
  String get sshTarget => ssh ?? sshGo ?? tcp ?? unix ?? '';

  /// The connection type label.
  String get typeLabel {
    if (ssh != null) return 'SSH';
    if (sshGo != null) return 'SSH (Go)';
    if (tcp != null) return 'TCP';
    if (unix != null) return 'Unix Socket';
    return 'Unknown';
  }

  /// Whether this connection has a machine ID.
  bool get hasMachineId => machineId != null && machineId!.isNotEmpty;

  /// Extract the host portion from the SSH target (strip user@ prefix).
  String get host {
    final target = sshTarget;
    final atIdx = target.indexOf('@');
    if (atIdx >= 0) return target.substring(atIdx + 1);
    return target;
  }

  /// Resolve the SSH key file path.
  /// If relative (e.g. "id_ed25519"), resolve against ~/.ssh/.
  /// If ~/ prefixed, resolve against home directory.
  /// If absolute, return as-is. Returns null if no key file set.
  String? get resolvedSshKeyFile {
    if (sshKeyFile == null || sshKeyFile!.isEmpty) return null;
    if (sshKeyFile!.startsWith('/')) return sshKeyFile;
    final home = realHome();
    if (sshKeyFile!.startsWith('~/')) {
      return '$home/${sshKeyFile!.substring(2)}';
    }
    // Relative path — resolve against ~/.ssh/
    return '$home/.ssh/$sshKeyFile';
  }
}

/// The full Uncloud config.
class UncloudConfig {
  final String currentContext;
  final Map<String, UncloudContext> contexts;

  UncloudConfig({required this.currentContext, required this.contexts});

  UncloudContext? get activeContext => contexts[currentContext];

  List<String> get allMachineIds =>
      contexts.values.expand((ctx) => ctx.machineIds).toList();

  UncloudContext? contextForMachineId(String machineId) {
    for (final ctx in contexts.values) {
      if (ctx.machineIds.contains(machineId)) return ctx;
    }
    return null;
  }

  UncloudConnection? connectionForMachineId(String machineId) {
    for (final ctx in contexts.values) {
      for (final conn in ctx.connections) {
        if (conn.machineId == machineId) return conn;
      }
    }
    return null;
  }

  List<UncloudConnection> connectionsForHost(String host) {
    final results = <UncloudConnection>[];
    for (final ctx in contexts.values) {
      for (final conn in ctx.connections) {
        if (conn.sshTarget.contains(host)) {
          results.add(conn);
        }
      }
    }
    return results;
  }

  /// Find all connections whose SSH host matches any of the given IPs.
  /// Returns a map of IP → matching connection.
  Map<String, UncloudConnection> connectionsForIps(List<String> ips) {
    final result = <String, UncloudConnection>{};
    for (final ctx in contexts.values) {
      for (final conn in ctx.connections) {
        for (final ip in ips) {
          if (conn.host == ip || conn.sshTarget.contains(ip)) {
            result[ip] = conn;
          }
        }
      }
    }
    return result;
  }
}

// ── Live data models (from `uc` CLI) ───────────────────────────────────

/// A machine reported by `uc machine ls`.
class UncloudRunningMachine {
  final String name;
  final String state;
  final String address;
  final String publicIp;
  final String machineId;

  UncloudRunningMachine({
    required this.name,
    required this.state,
    required this.address,
    required this.publicIp,
    required this.machineId,
  });

  bool get isUp => state.toLowerCase() == 'up';
}

/// A deployed service from `uc ls`.
class UncloudRunningService {
  final String name;
  final String mode;
  final int replicas;
  final String image;
  final String endpoints;

  UncloudRunningService({
    required this.name,
    required this.mode,
    required this.replicas,
    required this.image,
    required this.endpoints,
  });

  bool get isPostgres => image.toLowerCase().startsWith('postgres');
}

/// A container from `uc inspect`.
class UncloudServiceContainer {
  final String containerId;
  final String image;
  final String status;
  final String ipAddress;
  final String machine;

  UncloudServiceContainer({
    required this.containerId,
    required this.image,
    required this.status,
    required this.ipAddress,
    required this.machine,
  });

  bool get isUp => status.toLowerCase().contains('up');
  bool get isPostgres => image.toLowerCase().startsWith('postgres');
  String get shortId =>
      containerId.length > 12 ? containerId.substring(0, 12) : containerId;
}

/// A compose file service definition.
class UncloudServiceDef {
  final String name;
  final String? image;
  final List<String> xMachines;
  final List<String> xPorts;
  final String? xContext;
  final String filePath;

  UncloudServiceDef({
    required this.name,
    this.image,
    required this.xMachines,
    required this.xPorts,
    this.xContext,
    required this.filePath,
  });

  bool get hasMachineRestriction => xMachines.isNotEmpty;
}

class UncloudComposeFile {
  final String filePath;
  final String? xContext;
  final List<UncloudServiceDef> services;

  UncloudComposeFile({
    required this.filePath,
    this.xContext,
    required this.services,
  });
}

// ── UncloudService ──────────────────────────────────────────────────────

/// Central service for all Uncloud integration.
///
/// - Reads `~/.config/uncloud/config.yaml` for static config
/// - Runs `uc` CLI commands for live cluster state
/// - Matches ClarityMelt machines to UC machines by IP
/// - Persists UC machine IDs back to the ClarityMelt DB
class UncloudService {
  final AppDatabase _db;
  final String? _ucPath;

  UncloudService(this._db, {String? ucPath}) : _ucPath = ucPath;

  // ── Config file ───────────────────────────────────────────────────────

  static String configPath() {
    final home = realHome();
    return '$home/.config/uncloud/config.yaml';
  }

  static Future<UncloudConfig?> loadConfig() async {
    final file = File(configPath());
    if (!await file.exists()) {
      AppLog.debug('UC config not found at ${file.path}');
      return null;
    }
    try {
      final config = parseConfig(await file.readAsString());
      if (config != null) {
        AppLog.info('Loaded UC config: ${config.contexts.length} contexts, active=${config.currentContext}');
      } else {
        AppLog.warning('UC config parsed as null');
      }
      return config;
    } catch (e, st) {
      AppLog.error('Failed to parse UC config', e, st);
      return null;
    }
  }

  static UncloudConfig? parseConfig(String yamlContent) {
    try {
      final doc = loadYaml(yamlContent) as YamlMap;
      final currentContext = doc['current_context']?.toString() ?? '';
      final contextsRaw = doc['contexts'] as YamlMap?;
      if (contextsRaw == null) return null;

      final contexts = <String, UncloudContext>{};
      for (final entry in contextsRaw.entries) {
        final name = entry.key.toString();
        final ctxData = entry.value as YamlMap;
        final connectionsRaw = ctxData['connections'] as YamlList?;

        final connections = <UncloudConnection>[];
        if (connectionsRaw != null) {
          for (final connRaw in connectionsRaw) {
            final c = connRaw as YamlMap;
            connections.add(UncloudConnection(
              ssh: c['ssh']?.toString(),
              sshGo: c['ssh_go']?.toString(),
              tcp: c['tcp']?.toString(),
              unix: c['unix']?.toString(),
              sshKeyFile: c['ssh_key_file']?.toString(),
              machineId: c['machine_id']?.toString(),
            ));
          }
        }
        contexts[name] = UncloudContext(name: name, connections: connections);
      }
      return UncloudConfig(currentContext: currentContext, contexts: contexts);
    } catch (e, st) {
      AppLog.error('Failed to parse UC config YAML', e, st);
      return null;
    }
  }

  // ── CLI commands ───────────────────────────────────────────────────────

  String get _uc => _ucPath ?? 'uc';

  Future<String> _run(List<String> args, {String? context}) async {
    final fullArgs = <String>[];
    if (context != null) {
      fullArgs.addAll(['--context', context]);
    }
    fullArgs.addAll(args);
    AppLog.debug('uc ${fullArgs.join(' ')}');
    final stopwatch = Stopwatch()..start();

    final result = await Process.run(_uc, fullArgs,
        environment: realHomeEnvironment());
    stopwatch.stop();

    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      AppLog.error('uc ${args.first} failed (exit ${result.exitCode}) in ${stopwatch.elapsedMilliseconds}ms: $stderr');
      throw Exception('uc ${args.first} failed: $stderr');
    }

    AppLog.debug('uc ${args.first} completed in ${stopwatch.elapsedMilliseconds}ms');
    return result.stdout as String;
  }

  /// Get the cluster domain via `uc dns show`.
  Future<String?> getClusterDomain({String? context}) async {
    try {
      final domain = (await _run(['dns', 'show'], context: context)).trim();
      AppLog.info('UC cluster domain: $domain');
      return domain;
    } catch (e, st) {
      AppLog.warning('uc dns show failed', e, st);
      return null;
    }
  }

  /// List contexts via `uc ctx ls`.
  Future<List<MapEntry<String, bool>>> listContexts() async {
    try {
      final output = await _run(['ctx', 'ls']);
      return _parseCtxLs(output);
    } catch (e, st) {
      AppLog.warning('uc ctx ls failed', e, st);
      return [];
    }
  }

  /// List machines via `uc machine ls`.
  Future<List<UncloudRunningMachine>> listMachines({String? context}) async {
    final output = await _run(['machine', 'ls'], context: context);
    final machines = _parseMachineLs(output);
    AppLog.info('uc machine ls: found ${machines.length} machine(s)');
    return machines;
  }

  /// List services via `uc ls`.
  Future<List<UncloudRunningService>> listServices({String? context}) async {
    final output = await _run(['ls'], context: context);
    final services = _parseUcLs(output);
    AppLog.info('uc ls: found ${services.length} service(s)');
    return services;
  }

  /// Inspect a service via `uc inspect`.
  Future<List<UncloudServiceContainer>> inspectService(String name,
      {String? context}) async {
    final output = await _run(['inspect', name], context: context);
    final containers = _parseUcInspect(output);
    AppLog.debug('uc inspect $name: ${containers.length} container(s)');
    return containers;
  }

  /// Get containers running on a machine identified by public IP.
  Future<List<UncloudServiceContainer>> getContainersForIp(String publicIp,
      {String? context}) async {
    final machines = await listMachines(context: context);
    final matchingMachines =
        machines.where((m) => m.publicIp == publicIp).toList();
    if (matchingMachines.isEmpty) {
      AppLog.debug('No UC machine found for IP $publicIp');
      return [];
    }

    final services = await listServices(context: context);
    final containers = <UncloudServiceContainer>[];
    for (final svc in services) {
      try {
        final svcContainers =
            await inspectService(svc.name, context: context);
        for (final c in svcContainers) {
          if (matchingMachines.any((m) => m.name == c.machine)) {
            containers.add(c);
          }
        }
      } catch (e, st) {
        AppLog.warning('uc inspect ${svc.name} failed, skipping', e, st);
      }
    }
    AppLog.info('Found ${containers.length} container(s) on $publicIp');
    return containers;
  }

  // ── Config-based IP matching ────────────────────────────────────────────

  /// Match ClarityMelt machine IPs against the UC config.
  ///
  /// For each UC connection, extract the host from the SSH target
  /// (e.g. `debian@15.204.253.253` → `15.204.253.253`) and compare
  /// against the ClarityMelt machine's IPs. If a match is found,
  /// return the UC machine ID and context name.
  UncloudMatch? matchMachine(UncloudConfig config, List<String> machineIps) {
    for (final ctx in config.contexts.values) {
      for (final conn in ctx.connections) {
        if (conn.machineId == null) {
          continue;
        }
        final host = conn.host;
        for (final ip in machineIps) {
          if (host == ip) {
            AppLog.debug('UC match: IP $ip → context ${ctx.name}, machine_id ${conn.machineId}');
            return UncloudMatch(
              uncloudMachineId: conn.machineId!,
              contextName: ctx.name,
              isActiveContext: ctx.name == config.currentContext,
              connection: conn,
            );
          }
        }
      }
    }
    return null;
  }

  // ── DB sync ───────────────────────────────────────────────────────────

  /// Sync Uncloud machine IDs into the ClarityMelt DB.
  ///
  /// For every cached machine, check if its IPs match any UC config
  /// connection. If so, persist the UC machine ID and context name.
  /// Also runs `uc machine ls` for live validation.
  Future<int> syncUncloudIds(UncloudConfig config) async {
    final dao = _db.cachedMachineDao;
    final cached = await dao.getAll();
    var updated = 0;

    AppLog.info('Syncing UC machine IDs for ${cached.length} cached machine(s)');

    // Phase 1: config-based matching (always works, no CLI needed)
    for (final m in cached) {
      final ips = _parseIpList(m.ipAddresses);
      final match = matchMachine(config, ips);
      if (match != null) {
        AppLog.info('Config match: ${m.name} (${ips.join(', ')}) → UC ${match.uncloudMachineId} (ctx: ${match.contextName})');
        await dao.setUncloudId(m.id, match.uncloudMachineId, match.contextName);
        updated++;
      } else if (m.uncloudMachineId != null) {
        AppLog.info('Clearing stale UC ID for ${m.name}: was ${m.uncloudMachineId}');
        await dao.setUncloudId(m.id, null, null);
      }
    }

    // Phase 2: live `uc machine ls` validation (per context)
    for (final ctxName in config.contexts.keys) {
      try {
        AppLog.debug('Running uc machine ls --context $ctxName');
        final ucMachines = await listMachines(context: ctxName);
        for (final ucMachine in ucMachines) {
          final cachedMatch = await dao.findByIp(ucMachine.publicIp);
          if (cachedMatch != null && cachedMatch.uncloudMachineId != ucMachine.machineId) {
            AppLog.info('Live match: ${cachedMatch.name} (${ucMachine.publicIp}) → UC ${ucMachine.machineId} (ctx: $ctxName)');
            await dao.setUncloudId(
                cachedMatch.id, ucMachine.machineId, ctxName);
            updated++;
          } else if (cachedMatch == null) {
            AppLog.debug('uc machine ${ucMachine.name} (${ucMachine.publicIp}) has no cached machine match');
          }
        }
      } catch (e, st) {
        AppLog.warning('uc machine ls --context $ctxName failed, skipping live sync', e, st);
      }
    }

    AppLog.info('UC sync complete: $updated machine(s) updated');
    return updated;
  }

  // ── Compose file parsing ──────────────────────────────────────────────

  static Future<List<UncloudComposeFile>> loadComposeFiles(String directory) async {
    final files = <UncloudComposeFile>[];
    final dir = Directory(directory);
    if (!await dir.exists()) return files;

    for (final filename in [
      'uncloud.yml',
      'docker-compose.yml',
      'compose.yml',
      'compose.yaml'
    ]) {
      final file = File('$directory/$filename');
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          final compose = parseCompose(content, filePath: file.path);
          if (compose != null) {
            AppLog.debug('Loaded compose file: ${file.path}');
            files.add(compose);
          }
        } catch (e, st) {
          AppLog.warning('Failed to parse compose file ${file.path}', e, st);
        }
      }
    }
    return files;
  }

  static UncloudComposeFile? parseCompose(String yamlContent,
      {String filePath = ''}) {
    try {
      final doc = loadYaml(yamlContent) as YamlMap;
      final servicesRaw = doc['services'] as YamlMap?;
      final xContext = doc['x-context']?.toString();
      final services = <UncloudServiceDef>[];

      if (servicesRaw != null) {
        for (final entry in servicesRaw.entries) {
          final name = entry.key.toString();
          final svcData = entry.value as YamlMap;

          List<String> machines;
          final xMachines = svcData['x-machines'];
          if (xMachines is List) {
            machines = xMachines.map((m) => m.toString()).toList();
          } else if (xMachines is String) {
            machines = [xMachines];
          } else {
            machines = [];
          }

          List<String> ports;
          final xPorts = svcData['x-ports'];
          if (xPorts is List) {
            ports = xPorts.map((p) => p.toString()).toList();
          } else {
            ports = [];
          }

          services.add(UncloudServiceDef(
            name: name,
            image: svcData['image']?.toString(),
            xMachines: machines,
            xPorts: ports,
            xContext: xContext,
            filePath: filePath,
          ));
        }
      }

      return UncloudComposeFile(
          filePath: filePath, xContext: xContext, services: services);
    } catch (e, st) {
      AppLog.warning('Failed to parse compose YAML from $filePath', e, st);
      return null;
    }
  }

  // ── Parsers ──────────────────────────────────────────────────────────

  List<String> _parseIpList(String jsonArr) {
    try {
      return List<String>.from(jsonDecode(jsonArr));
    } catch (e) {
      AppLog.warning('Failed to parse IP list: $jsonArr', e);
      return [];
    }
  }

  List<UncloudRunningMachine> _parseMachineLs(String output) {
    final lines = output.split('\n');
    final machines = <UncloudRunningMachine>[];
    for (final line in lines) {
      final clean = _stripAnsi(line).trim();
      if (clean.isEmpty ||
          clean.startsWith('NAME') ||
          clean.startsWith('Connecting')) {
        continue;
      }
      final parts = _splitTable(clean);
      if (parts.length >= 5) {
        machines.add(UncloudRunningMachine(
          name: parts[0].trim(),
          state: parts[1].trim(),
          address: parts[2].trim(),
          publicIp: parts[3].trim(),
          machineId: parts.length > 5 ? parts[5].trim() : parts[4].trim(),
        ));
      } else {
        AppLog.warning('uc machine ls: skipping malformed line (${parts.length} cols): $clean');
      }
    }
    return machines;
  }

  List<UncloudRunningService> _parseUcLs(String output) {
    final lines = output.split('\n');
    final services = <UncloudRunningService>[];
    for (final line in lines) {
      final clean = _stripAnsi(line).trim();
      if (clean.isEmpty ||
          clean.startsWith('NAME') ||
          clean.startsWith('Connecting')) {
        continue;
      }
      final parts = _splitTable(clean);
      if (parts.length >= 4) {
        services.add(UncloudRunningService(
          name: parts[0].trim(),
          mode: parts[1].trim(),
          replicas: int.tryParse(parts[2].trim()) ?? 1,
          image: parts[3].trim(),
          endpoints: parts.length > 4 ? parts[4].trim() : '',
        ));
      } else {
        AppLog.warning('uc ls: skipping malformed line (${parts.length} cols): $clean');
      }
    }
    return services;
  }

  List<UncloudServiceContainer> _parseUcInspect(String output) {
    final lines = output.split('\n');
    final containers = <UncloudServiceContainer>[];
    for (final line in lines) {
      final clean = _stripAnsi(line).trim();
      if (clean.isEmpty ||
          clean.startsWith('CONTAINER') ||
          clean.startsWith('Service') ||
          clean.startsWith('Name') ||
          clean.startsWith('Mode') ||
          clean.startsWith('Connecting')) {
        continue;
      }
      final parts = _splitTable(clean);
      if (parts.length >= 5 && _looksLikeContainerId(parts[0].trim())) {
        containers.add(UncloudServiceContainer(
          containerId: parts[0].trim(),
          image: parts[1].trim(),
          status: parts[3].trim(),
          ipAddress: parts.length > 4 ? parts[4].trim() : '',
          machine: parts.length > 5 ? parts[5].trim() : '',
        ));
      }
    }
    return containers;
  }

  List<MapEntry<String, bool>> _parseCtxLs(String output) {
    final lines = output.split('\n');
    final contexts = <MapEntry<String, bool>>[];
    for (final line in lines) {
      final clean = _stripAnsi(line).trim();
      if (clean.isEmpty || clean.startsWith('NAME') || clean.startsWith('Connecting')) {
        continue;
      }
      final parts = _splitTable(clean);
      if (parts.length >= 2) {
        final name = parts[0].trim();
        final isCurrent = parts[1].trim().isNotEmpty && parts[1].trim() != 'false';
        contexts.add(MapEntry(name, isCurrent));
      }
    }
    return contexts;
  }

  List<String> _splitTable(String line) {
    return line
        .split(RegExp(r'\s{2,}'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  bool _looksLikeContainerId(String s) =>
      RegExp(r'^[a-f0-9]{8,}$').hasMatch(s);

  static String _stripAnsi(String input) {
    return input
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '')
        .replaceAll(RegExp(r'\x1B\][^\x07]*\x07'), '')
        .replaceAll(RegExp(r'\x1B[\[\]][0-9;]*[a-zA-Z]'), '')
        .replaceAll(RegExp(r'\[[\d;]*m'), '');
  }
}

// ── Match result ────────────────────────────────────────────────────────

/// Result of matching a ClarityMelt machine to a Uncloud connection.
class UncloudMatch {
  final String uncloudMachineId;
  final String contextName;
  final bool isActiveContext;
  final UncloudConnection connection;

  UncloudMatch({
    required this.uncloudMachineId,
    required this.contextName,
    required this.isActiveContext,
    required this.connection,
  });
}
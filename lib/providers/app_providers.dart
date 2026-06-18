import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../database/database.dart';
import '../models/models.dart';
import '../models/product_models.dart';
import '../services/infrastructure_service.dart';
import '../services/uncloud_service.dart';
import '../utils/app_log.dart';
import '../utils/platform_utils.dart';

/// Database provider (singleton).
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

/// Infrastructure service provider.
final infrastructureProvider = Provider<InfrastructureService>((ref) {
  return InfrastructureService(ref.watch(databaseProvider));
});

// ── Machines ─────────────────────────────────────────────────────────

final machinesProvider =
    AsyncNotifierProvider<MachinesNotifier, List<MachineInfo>>(
      MachinesNotifier.new,
    );

class MachinesNotifier extends AsyncNotifier<List<MachineInfo>> {
  @override
  Future<List<MachineInfo>> build() async {
    // Always fetch live data so VPS/dedicated/instances from all
    // providers are included even if a previous cached run was incomplete.
    final svc = ref.read(infrastructureProvider);
    try {
      return await svc.listMachines();
    } catch (e) {
      // If live fetch fails, fall back to cache
      final cached = await svc.getCachedMachines();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final svc = ref.read(infrastructureProvider);
      final machines = await svc.listMachines();
      state = AsyncData(machines);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> loadCached() async {
    state = const AsyncLoading();
    try {
      final svc = ref.read(infrastructureProvider);
      final cached = await svc.getCachedMachines();
      if (cached.isEmpty) {
        await refresh();
        return;
      }
      state = AsyncData(cached);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

// ── Domains ───────────────────────────────────────────────────────────

final domainsProvider =
    AsyncNotifierProvider<DomainsNotifier, List<DomainInfo>>(
      DomainsNotifier.new,
    );

class DomainsNotifier extends AsyncNotifier<List<DomainInfo>> {
  @override
  Future<List<DomainInfo>> build() async {
    // Always fetch live data to avoid stale duplicates from cache
    final svc = ref.read(infrastructureProvider);
    try {
      return await svc.listDomains();
    } catch (e) {
      // Fall back to cache on error
      final cached = await svc.getCachedDomains();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final svc = ref.read(infrastructureProvider);
      final domains = await svc.listDomains();
      state = AsyncData(domains);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> loadCached() async {
    state = const AsyncLoading();
    try {
      final svc = ref.read(infrastructureProvider);
      final cached = await svc.getCachedDomains();
      if (cached.isEmpty) {
        await refresh();
        return;
      }
      state = AsyncData(cached);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<ProvisionResult> provisionDomain({
    required String domain,
    required String machineIp,
    String? subdomain,
    bool proxied = false,
    bool updateNameservers = true,
  }) async {
    final svc = ref.read(infrastructureProvider);
    final result = await svc.provisionDomain(
      domain: domain,
      machineIp: machineIp,
      subdomain: subdomain,
      proxied: proxied,
      updateNameservers: updateNameservers,
    );
    await refresh();
    return result;
  }
}

// ── DNS Records ───────────────────────────────────────────────────────

/// The currently selected domain for DNS viewing.
final selectedDnsDomainProvider =
    NotifierProvider<SelectedDnsDomainNotifier, DomainInfo?>(
      SelectedDnsDomainNotifier.new,
    );

class SelectedDnsDomainNotifier extends Notifier<DomainInfo?> {
  @override
  DomainInfo? build() => null;

  void set(DomainInfo? domain) {
    state = domain;
  }
}

final dnsRecordsProvider =
    AsyncNotifierProvider<DnsRecordsNotifier, List<DnsRecordInfo>>(
      DnsRecordsNotifier.new,
    );

class DnsRecordsNotifier extends AsyncNotifier<List<DnsRecordInfo>> {
  @override
  Future<List<DnsRecordInfo>> build() async {
    final domain = ref.watch(selectedDnsDomainProvider);
    if (domain == null) return [];

    final svc = ref.watch(infrastructureProvider);

    // Try cached first
    final cached = await svc.getCachedDnsRecords(domain.dnsZoneId);
    if (cached.isNotEmpty) return cached;

    // Fetch live — pass the Cloudflare zone ID for Cloudflare domains
    return await svc.listDnsRecordsForDomain(
      domain.name,
      domain.effectiveDnsProvider,
      zoneId: domain.cfZoneId,
    );
  }

  Future<void> refresh() async {
    final domain = ref.read(selectedDnsDomainProvider);
    if (domain == null) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    try {
      final svc = ref.read(infrastructureProvider);
      final records = await svc.listDnsRecordsForDomain(
        domain.name,
        domain.effectiveDnsProvider,
        zoneId: domain.cfZoneId,
      );
      state = AsyncData(records);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> selectDomain(DomainInfo domain) async {
    ref.read(selectedDnsDomainProvider.notifier).set(domain);
    state = const AsyncLoading();
    try {
      final svc = ref.read(infrastructureProvider);
      final records = await svc.listDnsRecordsForDomain(
        domain.name,
        domain.effectiveDnsProvider,
        zoneId: domain.cfZoneId,
      );
      state = AsyncData(records);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> createRecord({
    required String type,
    required String name,
    required String content,
    int? ttl,
    bool? proxied,
  }) async {
    final domain = ref.read(selectedDnsDomainProvider)!;
    // Only Cloudflare supports record creation via UI for now
    if (domain.effectiveDnsProvider != 'cloudflare') {
      throw Exception(
        'DNS record creation is only supported for Cloudflare-managed domains',
      );
    }
    final svc = ref.read(infrastructureProvider);
    await svc.createDnsRecord(
      domain.cfZoneId!,
      type: type,
      name: name,
      content: content,
      ttl: ttl,
      proxied: proxied,
    );
    await refresh();
  }

  Future<void> deleteRecord(String recordId) async {
    final domain = ref.read(selectedDnsDomainProvider)!;
    if (domain.effectiveDnsProvider != 'cloudflare') {
      throw Exception(
        'DNS record deletion is only supported for Cloudflare-managed domains',
      );
    }
    final svc = ref.read(infrastructureProvider);
    await svc.deleteDnsRecord(domain.cfZoneId!, recordId);
    await refresh();
  }

  Future<void> updateRecord(
    String recordId, {
    required String type,
    required String name,
    required String content,
    int? ttl,
    bool? proxied,
  }) async {
    final domain = ref.read(selectedDnsDomainProvider)!;
    if (domain.effectiveDnsProvider != 'cloudflare') {
      throw Exception(
        'DNS record editing is only supported for Cloudflare-managed domains',
      );
    }
    final svc = ref.read(infrastructureProvider);
    await svc.updateDnsRecord(
      domain.cfZoneId!,
      recordId,
      type: type,
      name: name,
      content: content,
      ttl: ttl,
      proxied: proxied,
    );
    await refresh();
  }
}

/// Legacy provider for backwards compatibility: set zone ID directly
final dnsZoneIdProvider = NotifierProvider<DnsZoneIdNotifier, String?>(
  DnsZoneIdNotifier.new,
);

class DnsZoneIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? zoneId) {
    state = zoneId;
  }
}

// ── Providers (credentials) ───────────────────────────────────────────

final providerCredentialsProvider =
    AsyncNotifierProvider<
      ProviderCredentialsNotifier,
      List<ProviderCredentialInfo>
    >(ProviderCredentialsNotifier.new);

class ProviderCredentialsNotifier
    extends AsyncNotifier<List<ProviderCredentialInfo>> {
  @override
  Future<List<ProviderCredentialInfo>> build() async {
    final svc = ref.watch(infrastructureProvider);
    return await svc.listProviderCredentials();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final svc = ref.read(infrastructureProvider);
      final credentials = await svc.listProviderCredentials();
      state = AsyncData(credentials);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> createCredential({
    required String provider,
    required String label,
    required Map<String, String> credentials,
  }) async {
    final svc = ref.read(infrastructureProvider);
    await svc.createProviderCredential(provider, label, credentials);
    await refresh();
  }

  Future<void> deleteCredential(String id) async {
    final svc = ref.read(infrastructureProvider);
    await svc.deleteProviderCredential(id);
    await refresh();
  }
}

final providerStatusProvider = FutureProvider<Map<String, ProviderStatus>>((
  ref,
) async {
  final svc = ref.watch(infrastructureProvider);
  return await svc.getConfiguredProviders();
});

// ── DNS Map (IP -> DNS records) ───────────────────────────────────────

final dnsMapProvider = FutureProvider<Map<String, List<DnsRecordInfo>>>((
  ref,
) async {
  final svc = ref.watch(infrastructureProvider);
  return await svc.getMachineDnsMap();
});

// ── Cloudflare Workers ───────────────────────────────────────────────

final workersProvider = FutureProvider<List<CloudflareWorkerInfo>>((ref) async {
  final svc = ref.watch(infrastructureProvider);
  return await svc.listWorkers();
});

// ── Cloudflare Pages ───────────────────────────────────────────────────

final pagesProvider = FutureProvider<List<CloudflarePagesInfo>>((ref) async {
  final svc = ref.watch(infrastructureProvider);
  return await svc.listPagesProjects();
});

// ── Products ────────────────────────────────────────────────────────

final productsProvider =
    AsyncNotifierProvider<ProductsNotifier, List<ProductInfo>>(
      ProductsNotifier.new,
    );

class ProductsNotifier extends AsyncNotifier<List<ProductInfo>> {
  @override
  Future<List<ProductInfo>> build() async {
    final svc = ref.read(infrastructureProvider);
    return await svc.listProducts();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final svc = ref.read(infrastructureProvider);
      final products = await svc.listProducts();
      state = AsyncData(products);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<ProductInfo> createProduct({required String name, String? description}) async {
    final svc = ref.read(infrastructureProvider);
    final product = await svc.createProduct(name: name, description: description);
    await refresh();
    return product;
  }

  Future<void> deleteProduct(String id) async {
    final svc = ref.read(infrastructureProvider);
    await svc.deleteProduct(id);
    await refresh();
  }

  Future<ProductResourceInfo> addResource({
    required String productId,
    required String resourceType,
    required String resourceId,
    String role = 'primary',
    Map<String, dynamic>? metadata,
  }) async {
    final svc = ref.read(infrastructureProvider);
    final resource = await svc.addResourceToProduct(
      productId: productId,
      resourceType: resourceType,
      resourceId: resourceId,
      role: role,
      metadata: metadata,
    );
    await refresh();
    return resource;
  }

  Future<void> removeResource(String resourceId) async {
    final svc = ref.read(infrastructureProvider);
    await svc.removeResourceFromProduct(resourceId);
    await refresh();
  }
}

// ── OVH Monitoring ────────────────────────────────────────────────────

final ovhMonitoringProvider = FutureProvider.family<OvhMonitoringInfo?, String>((
  ref,
  serverName,
) async {
  final svc = ref.read(infrastructureProvider);
  return await svc.getOvhDedicatedMonitoring(serverName);
});

final ovhDedicatedServiceProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  serverName,
) async {
  final svc = ref.read(infrastructureProvider);
  return await svc.getOvhDedicatedService(serverName);
});

final ovhVpsServiceProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  vpsName,
) async {
  final svc = ref.read(infrastructureProvider);
  return await svc.getOvhVpsService(vpsName);
});

// ── Machine Specs ─────────────────────────────────────────────────────

/// Fetch hardware specs for an OVH VPS.
final ovhVpsSpecsProvider = FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  vpsName,
) async {
  final svc = ref.read(infrastructureProvider);
  return await svc.getOvhVpsSpecs(vpsName);
});

/// Fetch hardware specs for an OVH Dedicated server.
final ovhDedicatedSpecsProvider = FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  serverName,
) async {
  final svc = ref.read(infrastructureProvider);
  return await svc.getOvhDedicatedSpecs(serverName);
});

// ── OVH Hardware Specs ────────────────────────────────────────────────

/// Fetch detailed hardware specs for an OVH machine.
/// Resolves the provider-specific server name from the machine ID
/// and calls the appropriate OVH API endpoint.
final ovhHardwareSpecsProvider = FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  machineId,
) async {
  final svc = ref.read(infrastructureProvider);

  // Strip provider prefix to get the provider-specific ID
  if (machineId.startsWith('ovh-vps-')) {
    final vpsName = machineId.substring(8);
    return await svc.getOvhVpsSpecs(vpsName);
  } else if (machineId.startsWith('ovh-dedicated-')) {
    final serverName = machineId.substring(15);
    return await svc.getOvhDedicatedSpecs(serverName);
  } else if (machineId.startsWith('ovh-')) {
    // Cloud instance — no dedicated hardware specs API
    return {};
  }
  return {};
});

// ── OVH Monitoring & Metrics ─────────────────────────────────────────────

/// Fetch VPS statistics (CPU, RAM, disk, network).
final ovhVpsStatsProvider = FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  machineId,
) async {
  final svc = ref.read(infrastructureProvider);
  final ovhCreds = await svc.db.providerCredentialDao.getByProvider('ovh');
  if (ovhCreds.isEmpty) return {};
  final decrypted = await svc.decryptCredentials(ovhCreds.first);
  if (decrypted == null) return {};
  final ovhService = svc.buildOvhService(decrypted);
  if (ovhService == null) return {};

  if (machineId.startsWith('ovh-vps-')) {
    final vpsName = machineId.substring(8);
    return await ovhService.getVpsStatistics(vpsName);
  } else if (machineId.startsWith('ovh-dedicated-')) {
    final serverName = machineId.substring(15);
    return await ovhService.getDedicatedServerMrtg(serverName);
  }
  return {};
});

/// Fetch VPS disk usage.
final ovhVpsDiskUsageProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((
  ref,
  machineId,
) async {
  final svc = ref.read(infrastructureProvider);
  final ovhCreds = await svc.db.providerCredentialDao.getByProvider('ovh');
  if (ovhCreds.isEmpty) return [];
  final decrypted = await svc.decryptCredentials(ovhCreds.first);
  if (decrypted == null) return [];
  final ovhService = svc.buildOvhService(decrypted);
  if (ovhService == null) return [];

  if (machineId.startsWith('ovh-vps-')) {
    final vpsName = machineId.substring(8);
    return await ovhService.getVpsDiskUsage(vpsName);
  }
  return [];
});

/// Fetch dedicated server MRTG traffic data.
final ovhDedicatedMrtgProvider = FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  machineId,
) async {
  final svc = ref.read(infrastructureProvider);
  final ovhCreds = await svc.db.providerCredentialDao.getByProvider('ovh');
  if (ovhCreds.isEmpty) return {};
  final decrypted = await svc.decryptCredentials(ovhCreds.first);
  if (decrypted == null) return {};
  final ovhService = svc.buildOvhService(decrypted);
  if (ovhService == null) return {};

  if (machineId.startsWith('ovh-dedicated-')) {
    final serverName = machineId.substring(15);
    return await ovhService.getDedicatedServerMrtg(serverName);
  }
  return {};
});

/// Fetch server tasks (VPS or dedicated).
final ovhServerTasksProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((
  ref,
  machineId,
) async {
  final svc = ref.read(infrastructureProvider);
  final ovhCreds = await svc.db.providerCredentialDao.getByProvider('ovh');
  if (ovhCreds.isEmpty) return [];
  final decrypted = await svc.decryptCredentials(ovhCreds.first);
  if (decrypted == null) return [];
  final ovhService = svc.buildOvhService(decrypted);
  if (ovhService == null) return [];

  if (machineId.startsWith('ovh-vps-')) {
    final vpsName = machineId.substring(8);
    return await ovhService.getVpsTasks(vpsName);
  } else if (machineId.startsWith('ovh-dedicated-')) {
    final serverName = machineId.substring(15);
    return await ovhService.getDedicatedServerTasks(serverName);
  }
  return [];
});

/// Fetch ongoing interventions for a dedicated server.
final ovhInterventionsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((
  ref,
  machineId,
) async {
  final svc = ref.read(infrastructureProvider);
  final ovhCreds = await svc.db.providerCredentialDao.getByProvider('ovh');
  if (ovhCreds.isEmpty) return [];
  final decrypted = await svc.decryptCredentials(ovhCreds.first);
  if (decrypted == null) return [];
  final ovhService = svc.buildOvhService(decrypted);
  if (ovhService == null) return [];

  if (machineId.startsWith('ovh-dedicated-')) {
    final serverName = machineId.substring(15);
    return await ovhService.getDedicatedServerOngoingInterventions(serverName);
  }
  return [];
});

/// Provider to hold machine aliases in memory (not persisted to provider-level).
/// Aliases are persisted in the CachedMachines table.
final machineAliasesProvider = NotifierProvider<MachineAliasesNotifier, Map<String, String>>(
  MachineAliasesNotifier.new,
);

class MachineAliasesNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    // Load aliases from cache on init
    return {};
  }

  Future<void> setAlias(String machineId, String alias) async {
    final current = Map<String, String>.from(state);
    if (alias.isEmpty) {
      current.remove(machineId);
    } else {
      current[machineId] = alias;
    }
    state = current;

    // Persist to DB
    final db = ref.read(databaseProvider);
    final existing = await db.cachedMachineDao.getById(machineId);
    if (existing != null) {
      await db.cachedMachineDao.upsertMachine(
        CachedMachinesCompanion(
          id: Value(machineId),
          alias: Value(alias.isEmpty ? null : alias),
        ),
      );
    }
  }

  Future<void> loadFromCache() async {
    final db = ref.read(databaseProvider);
    final machines = await db.cachedMachineDao.getAll();
    final aliases = <String, String>{};
    for (final m in machines) {
      if (m.alias != null && m.alias!.isNotEmpty) {
        aliases[m.id] = m.alias!;
      }
    }
    state = aliases;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, String>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<String> {
  @override
  String build() => 'system';

  void set(String mode) {
    state = mode;
  }
}

// ── Uncloud ──────────────────────────────────────────────────────────

final uncloudConfigProvider = FutureProvider<UncloudConfig?>((ref) async {
  return UncloudService.loadConfig();
});

/// Provider for the UncloudService instance (DB-aware, runs CLI commands).
final uncloudServiceProvider = Provider<UncloudService>((ref) {
  return UncloudService(ref.read(databaseProvider));
});

/// Match a ClarityMelt machine's IPs against the UC config and return the match.
final uncloudMachineMatchProvider = FutureProvider.family<UncloudMatch?, List<String>>((ref, machineIps) async {
  final config = await ref.watch(uncloudConfigProvider.future);
  if (config == null) return null;
  final svc = ref.read(uncloudServiceProvider);
  return svc.matchMachine(config, machineIps);
});

final uncloudComposeProvider = FutureProvider<List<UncloudComposeFile>>((ref) async {
  final home = realHome();
  final dirs = [
    '$home/.config/uncloud',
    '$home',
  ];
  final allFiles = <UncloudComposeFile>[];
  for (final dir in dirs) {
    allFiles.addAll(await UncloudService.loadComposeFiles(dir));
  }
  return allFiles;
});

/// Sync UC machine IDs into the DB. Triggered on config load and manual refresh.
final uncloudSyncProvider = FutureProvider<int>((ref) async {
  final config = await ref.watch(uncloudConfigProvider.future);
  if (config == null) return 0;
  final svc = ref.read(uncloudServiceProvider);
  try {
    final count = await svc.syncUncloudIds(config);
    AppLog.info('UC sync: $count machine(s) updated');
    return count;
  } catch (e, st) {
    AppLog.error('UC sync failed', e, st);
    return 0;
  }
});

// ── Uncloud CLI (live data) ───────────────────────────────────────────────

/// List running services from `uc ls` for the active context.
final uncloudRunningServicesProvider = FutureProvider<List<UncloudRunningService>>((ref) async {
  final config = await ref.watch(uncloudConfigProvider.future);
  if (config == null) return [];
  final svc = ref.read(uncloudServiceProvider);
  try {
    return await svc.listServices(context: config.currentContext);
  } catch (e, st) {
    AppLog.warning('Failed to list UC services', e, st);
    return [];
  }
});

/// List running machines from `uc machine ls` for the active context.
final uncloudRunningMachinesProvider = FutureProvider<List<UncloudRunningMachine>>((ref) async {
  final config = await ref.watch(uncloudConfigProvider.future);
  if (config == null) return [];
  final svc = ref.read(uncloudServiceProvider);
  try {
    return await svc.listMachines(context: config.currentContext);
  } catch (e, st) {
    AppLog.warning('Failed to list UC machines', e, st);
    return [];
  }
});

/// Get containers running on a specific machine (by public IP).
final uncloudContainersForIpProvider = FutureProvider.family<List<UncloudServiceContainer>, String>((ref, publicIp) async {
  final config = await ref.watch(uncloudConfigProvider.future);
  if (config == null) return [];
  final svc = ref.read(uncloudServiceProvider);
  try {
    return await svc.getContainersForIp(publicIp, context: config.currentContext);
  } catch (e, st) {
    AppLog.warning('Failed to get UC containers for IP $publicIp', e, st);
    return [];
  }
});

/// Get the cluster domain from `uc dns show`.
final uncloudClusterDomainProvider = FutureProvider<String?>((ref) async {
  final config = await ref.watch(uncloudConfigProvider.future);
  if (config == null) return null;
  final svc = ref.read(uncloudServiceProvider);
  try {
    return await svc.getClusterDomain(context: config.currentContext);
  } catch (e, st) {
    AppLog.warning('Failed to get UC cluster domain', e, st);
    return null;
  }
});

// ── Notes & Tasks ──────────────────────────────────────────────────────

final notesProvider = FutureProvider.family<List<Note>, (String, String)>((ref, params) async {
  final db = ref.watch(databaseProvider);
  return db.notesDao.getNotes(params.$1, params.$2);
});

final tasksProvider = FutureProvider.family<List<Task>, (String, String)>((ref, params) async {
  final db = ref.watch(databaseProvider);
  return db.notesDao.getTasks(params.$1, params.$2);
});

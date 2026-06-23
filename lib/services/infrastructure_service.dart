import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/models.dart';
import '../models/product_models.dart';
import '../services/cloudflare_service.dart';
import '../services/hetzner_service.dart';
import '../services/ovh_service.dart';
import '../services/namecheap_service.dart';
import '../services/crypto_service.dart';

/// Central service that orchestrates all infrastructure provider calls,
/// credential resolution, and caching to SQLite.

class InfrastructureService {
  final AppDatabase db;
  final _uuid = const Uuid();

  InfrastructureService(this.db);

  // ── Credential Resolution ──────────────────────────────────────────

  /// Get decrypted credentials for a provider.
  /// Falls back to env var configuration if no DB credentials exist.
  Future<Map<String, String>?> getCredentials(String provider) async {
    // 1. Check DB for stored credentials
    final stored = await db.providerCredentialDao.getByProvider(provider);
    if (stored.isNotEmpty) {
      try {
        final encryptionKey = await db.preferencesDao.getEncryptionKey();
        if (encryptionKey.isEmpty) return null;
        final decrypted = CryptoService.decrypt(stored.first.credentials, encryptionKey);
        return Map<String, String>.from(jsonDecode(decrypted));
      } catch (e) {
        // Fall through to env vars
      }
    }

    // 2. Fall back to env vars
    switch (provider) {
      case 'ovh':
        // OAuth2 credentials take precedence if available
        final clientId = const String.fromEnvironment('OVH_CLIENT_ID');
        if (clientId.isNotEmpty) {
          return {
            'endpoint': const String.fromEnvironment('OVH_ENDPOINT').isNotEmpty
                ? const String.fromEnvironment('OVH_ENDPOINT')
                : 'ovh-eu',
            'clientId': clientId,
            'clientSecret': const String.fromEnvironment('OVH_CLIENT_SECRET'),
          };
        }
        final appKey = const String.fromEnvironment('OVH_APPLICATION_KEY');
        if (appKey.isNotEmpty) {
          return {
            'endpoint': const String.fromEnvironment('OVH_ENDPOINT').isNotEmpty
                ? const String.fromEnvironment('OVH_ENDPOINT')
                : 'ovh-eu',
            'applicationKey': appKey,
            'applicationSecret': const String.fromEnvironment('OVH_APPLICATION_SECRET'),
            'consumerKey': const String.fromEnvironment('OVH_CONSUMER_KEY'),
          };
        }
        return null;
      case 'hetzner':
        final token = const String.fromEnvironment('HETZNER_API_TOKEN');
        if (token.isNotEmpty) return {'apiToken': token};
        return null;
      case 'namecheap':
        final apiUser = const String.fromEnvironment('NAMECHEAP_API_USER');
        if (apiUser.isNotEmpty) {
          return {
            'apiUser': apiUser,
            'apiKey': const String.fromEnvironment('NAMECHEAP_API_KEY'),
            'clientIp': const String.fromEnvironment('NAMECHEAP_CLIENT_IP'),
          };
        }
        return null;
      case 'cloudflare':
        final token = const String.fromEnvironment('CLOUDFLARE_API_TOKEN');
        if (token.isNotEmpty) {
          return {
            'apiToken': token,
            'accountId': const String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID'),
          };
        }
        return null;
      default:
        return null;
    }
  }

  /// Check which providers are configured (DB or env).
  Future<Map<String, ProviderStatus>> getConfiguredProviders() async {
    final providers = ['ovh', 'hetzner', 'namecheap', 'cloudflare'];
    final result = <String, ProviderStatus>{};

    for (final provider in providers) {
      final dbCred = await db.providerCredentialDao.getByProvider(provider);
      bool envAvailable = false;
      switch (provider) {
        case 'ovh':
          envAvailable = const String.fromEnvironment('OVH_APPLICATION_KEY').isNotEmpty ||
              const String.fromEnvironment('OVH_CLIENT_ID').isNotEmpty;
          break;
        case 'hetzner':
          envAvailable = const String.fromEnvironment('HETZNER_API_TOKEN').isNotEmpty;
          break;
        case 'namecheap':
          envAvailable = const String.fromEnvironment('NAMECHEAP_API_USER').isNotEmpty;
          break;
        case 'cloudflare':
          envAvailable = const String.fromEnvironment('CLOUDFLARE_API_TOKEN').isNotEmpty;
          break;
      }

      final source = dbCred.isNotEmpty
          ? 'db'
          : envAvailable
              ? 'env'
              : 'none';

      result[provider] = ProviderStatus(
        db: dbCred.isNotEmpty,
        env: envAvailable,
        source: source,
      );
    }

    return result;
  }

  // ── Provider Credentials CRUD ──────────────────────────────────────

  /// List all stored provider credentials (with masked values).
  Future<List<ProviderCredentialInfo>> listProviderCredentials() async {
    final credentials = await db.providerCredentialDao.getAll();
    final encryptionKey = await db.preferencesDao.getEncryptionKey();

    return credentials.map((c) {
      Map<String, String> maskedFields = {};
      String? ovhEndpoint;
      if (encryptionKey.isNotEmpty) {
        try {
          final decrypted = CryptoService.decryptCredentials(c.credentials, encryptionKey);
          maskedFields = decrypted.map((k, v) => MapEntry(k, CryptoService.maskSecret(v)));
          if (c.provider == 'ovh' && decrypted.containsKey('endpoint')) {
            ovhEndpoint = decrypted['endpoint'];
          }
        } catch (_) {
          maskedFields = {'error': 'Could not decrypt'};
        }
      }

      return ProviderCredentialInfo(
        id: c.id,
        provider: c.provider,
        label: c.label,
        maskedFields: maskedFields,
        createdAt: c.createdAt,
        updatedAt: c.updatedAt,
        ovhEndpoint: ovhEndpoint,
      );
    }).toList();
  }

  /// Add a new provider credential (encrypts before storing).
  Future<ProviderCredentialInfo> createProviderCredential(
    String provider,
    String label,
    Map<String, String> credentials,
  ) async {
    var encryptionKey = await db.preferencesDao.getEncryptionKey();
    if (encryptionKey.isEmpty) {
      encryptionKey = CryptoService.generateKey();
      await db.preferencesDao.setEncryptionKey(encryptionKey);
    }

    final encrypted = CryptoService.encrypt(jsonEncode(credentials), encryptionKey);
    final id = _uuid.v4();

    await db.providerCredentialDao.insertCredential(
      ProviderCredentialsCompanion.insert(
        id: id,
        provider: provider,
        label: label,
        credentials: encrypted,
      ),
    );

    return ProviderCredentialInfo(
      id: id,
      provider: provider,
      label: label,
      maskedFields: credentials.map((k, v) => MapEntry(k, CryptoService.maskSecret(v))),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      ovhEndpoint: provider == 'ovh' ? credentials['endpoint'] : null,
    );
  }

  /// Delete a provider credential.
  Future<void> deleteProviderCredential(String id) async {
    await db.providerCredentialDao.deleteCredential(id);
  }

  // ── Machines ────────────────────────────────────────────────────────

  /// List all machines across configured providers (live data).
  /// Fetches OVH cloud instances, VPS, and dedicated servers,
  /// plus Hetzner cloud servers in one unified list.
  Future<List<MachineInfo>> listMachines() async {
    final machines = <MachineInfo>[];

    // OVH — cloud instances, VPS, and dedicated servers
    final ovhCreds = await getCredentials('ovh');
    final ovh = buildOvhService(ovhCreds);
    if (ovh != null) {

      // Cloud instances
      try {
        final instances = await ovh.listInstances();
        print('[ClarityMelt] OVH cloud instances: ${instances.length} found');
        for (final inst in instances) {
          final id = inst['id']?.toString() ?? 'unknown';
          final name = inst['name']?.toString() ?? 'unnamed';
          final status = inst['status']?.toString() ?? 'unknown';
          final ipAddresses = _extractStringList(inst['ipAddresses']);
          final region = inst['region']?.toString() ?? '';
          final flavor = inst['flavor'] is Map ? inst['flavor']['name']?.toString() : inst['flavor']?.toString();
          final image = inst['image'] is Map ? inst['image']['name']?.toString() : inst['image']?.toString();
          final createdAt = inst['created']?.toString() ?? inst['createdAt']?.toString() ?? '';
          machines.add(MachineInfo(
            id: 'ovh-$id',
            name: name,
            provider: 'ovh',
            status: status,
            ipAddresses: ipAddresses,
            region: region,
            flavor: flavor,
            image: image,
            createdAt: createdAt,
            vcpus: inst['vcpus'] is int ? inst['vcpus'] : (inst['flavor'] is Map ? inst['flavor']['vcpus'] : null)?.toInt(),
            memoryMB: inst['memoryMB'] is int ? inst['memoryMB'] : (inst['flavor'] is Map ? inst['flavor']['ram'] : null)?.toInt(),
            diskGB: inst['diskGB'] is int ? inst['diskGB'] : (inst['flavor'] is Map ? inst['flavor']['disk'] : null)?.toInt(),
            os: inst['os']?.toString() ?? image,
            raw: inst,
            monthlyCost: _extractMonthlyCost(inst),
            currency: _extractCurrency(inst) ?? 'EUR',
          ));
        }
      } catch (e, st) {
        // Log but continue — other OVH categories may still work
        print('[ClarityMelt] OVH cloud instances error: $e\n$st');
      }

      // VPS servers
      try {
        final vpsList = await ovh.listVps();
        print('[ClarityMelt] OVH VPS: ${vpsList.length} found');
        for (final vps in vpsList) {
          final id = vps['id']?.toString() ?? vps['name']?.toString() ?? 'unknown';
          final name = vps['name']?.toString() ?? 'unnamed';
          final status = vps['state']?.toString() ?? vps['status']?.toString() ?? 'unknown';
          final ipAddresses = _extractStringList(vps['ipAddresses']);
          final datacenter = vps['datacenter']?.toString() ?? vps['cluster']?.toString() ?? '';
          final os = vps['os']?.toString() ?? vps['distribution']?.toString() ?? 'unknown';
          final flavor = vps['model']?.toString() ?? vps['offer']?.toString();
          machines.add(MachineInfo(
            id: 'ovh-vps-$id',
            name: name,
            provider: 'ovh-vps',
            status: status,
            ipAddresses: ipAddresses,
            region: datacenter,
            flavor: flavor,
            image: os,
            createdAt: '',
            vcpus: vps['vcpus'] is int ? vps['vcpus'] : vps['cores']?.toInt(),
            memoryMB: vps['memoryMB'] is int ? vps['memoryMB'] : vps['ram']?.toInt(),
            diskGB: vps['diskGB'] is int ? vps['diskGB'] : vps['storage']?.toInt(),
            bandwidth: vps['bandwidth']?.toString(),
            os: os,
            commercialRange: null,
            raw: vps,
            monthlyCost: _extractMonthlyCost(vps),
            currency: _extractCurrency(vps) ?? 'EUR',
          ));
        }
      } catch (e, st) {
        print('[ClarityMelt] OVH VPS error: $e\n$st');
      }

      // Dedicated servers
      try {
        final dedicated = await ovh.listDedicatedServers();
        print('[ClarityMelt] OVH dedicated: ${dedicated.length} found');
        for (final srv in dedicated) {
          final id = srv['id']?.toString() ?? srv['name']?.toString() ?? 'unknown';
          final name = srv['name']?.toString() ?? id;
          final status = srv['state']?.toString() ?? srv['status']?.toString() ?? 'unknown';
          final ipAddresses = _extractStringList(srv['ipAddresses']);
          final datacenter = srv['datacenter']?.toString() ?? 'unknown';
          final os = srv['os']?.toString() ?? srv['operatingSystem']?.toString() ?? 'unknown';
          final commercialRange = srv['commercialRange']?.toString() ?? 'unknown';
          machines.add(MachineInfo(
            id: 'ovh-dedicated-$id',
            name: name,
            provider: 'ovh-dedicated',
            status: status,
            ipAddresses: ipAddresses,
            region: datacenter,
            flavor: commercialRange,
            image: os,
            createdAt: '',
            commercialRange: commercialRange,
            bandwidth: srv['bandwidth']?.toString(),
            os: os,
            raw: srv,
            monthlyCost: _extractMonthlyCost(srv),
            currency: _extractCurrency(srv) ?? 'EUR',
          ));
        }
      } catch (e, st) {
        print('[ClarityMelt] OVH dedicated servers error: $e\n$st');
      }
    }

    // Hetzner servers
    final hetznerCreds = await getCredentials('hetzner');
    if (hetznerCreds != null && hetznerCreds.containsKey('apiToken')) {
      try {
        final hetzner = HetznerService(apiToken: hetznerCreds['apiToken']!);
        final servers = await hetzner.listServers();
        print('[ClarityMelt] Hetzner: ${servers.length} found');
        for (final srv in servers) {
          final id = srv['id']?.toString() ?? 'unknown';
          // Extract monthly cost from Hetzner server_type.prices
          double? monthlyCost;
          String? currency;
          final serverType = srv['server_type'];
          if (serverType is Map) {
            final prices = serverType['prices'];
            if (prices is List && prices.isNotEmpty) {
              // Use the first price entry (usually the default location)
              final priceEntry = prices[0] as Map;
              final monthly = priceEntry['price_monthly'];
              if (monthly is Map) {
                final net = monthly['net'];
                if (net is num) monthlyCost = net.toDouble();
                else if (net is String) monthlyCost = double.tryParse(net);
                final gross = monthly['gross'];
                if (monthlyCost == null && gross is num) monthlyCost = gross.toDouble();
                else if (monthlyCost == null && gross is String) monthlyCost = double.tryParse(gross);
              } else if (monthly is num) {
                monthlyCost = monthly.toDouble();
              } else if (monthly is String) {
                monthlyCost = double.tryParse(monthly);
              }
              // Hetzner prices are always in EUR
              currency = 'EUR';
            }
          }
          machines.add(MachineInfo(
            id: 'hetzner-$id',
            name: srv['name']?.toString() ?? 'unnamed',
            provider: 'hetzner',
            status: srv['status']?.toString() ?? 'unknown',
            ipAddresses: _extractStringList(srv['ipAddresses']),
            region: srv['region']?.toString() ?? '',
            flavor: srv['flavor'] is Map ? srv['flavor']['name']?.toString() : srv['flavor']?.toString(),
            image: srv['image'] is Map ? srv['image']['name']?.toString() : srv['image']?.toString(),
            createdAt: srv['created']?.toString() ?? '',
            vcpus: _parseIntField(srv, 'vcpus', 'server_type', 'cores'),
            memoryMB: _parseIntField(srv, 'memoryMB', 'server_type', 'memory'),
            diskGB: _parseIntField(srv, 'diskGB', 'server_type', 'disk'),
            os: _extractOs(srv),
            raw: srv,
            monthlyCost: monthlyCost,
            currency: currency,
          ));
        }
      } catch (e, st) {
        print('[ClarityMelt] Hetzner servers error: $e\n$st');
      }
    }

    print('[ClarityMelt] Total machines fetched: ${machines.length}');

    // Cache to DB
    await _cacheMachines(machines);

    // Enrich the in-memory list with Uncloud fields from the DB cache.
    // The provider APIs don't return UC associations, so we merge them
    // from the cache after upsert so the returned list is complete.
    final cachedRows = await db.cachedMachineDao.getAll();
    final ucLookup = <String, (String?, String?)>{};
    for (final r in cachedRows) {
      ucLookup[r.id] = (r.uncloudMachineId, r.uncloudContext);
    }
    for (int i = 0; i < machines.length; i++) {
      final m = machines[i];
      final (ucId, ucCtx) = ucLookup[m.id] ?? (null, null);
      if (ucId != null || ucCtx != null) {
        machines[i] = m.copyWith(
          uncloudMachineId: ucId ?? m.uncloudMachineId,
          uncloudContext: ucCtx ?? m.uncloudContext,
        );
      }
    }

    return machines;
  }

  /// Safely extract a List<String> from a dynamic value that may be
  /// a List<String>, List<dynamic>, or null.
  static List<String> _extractStringList(dynamic value) {
    if (value is List) {
      return value.map((e) {
        if (e is String) return e;
        if (e is Map) return (e['ip'] ?? e['value'] ?? e['address'] ?? '').toString();
        return e.toString();
      }).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  /// Safely parse an int field from a nested map structure.
  /// First checks top-level [field], then [nestedKey][subField].
  static int? _parseIntField(Map<String, dynamic> map, String field, String nestedKey, String subField) {
    final topLevel = map[field];
    if (topLevel is int) return topLevel;
    final nested = map[nestedKey];
    if (nested is Map) {
      final val = nested[subField];
      if (val is int) return val;
      if (val != null) return int.tryParse(val.toString());
    }
    return null;
  }

  /// Extract monthly cost from raw API data.
  /// Hetzner: server_type.prices[].price_monthly.net
  /// OVH Cloud: flavor.monthlyPrice or plan.monthlyPrice
  /// OVH VPS/Dedicated: price (from service API or catalog)
  static double? _extractMonthlyCost(Map<String, dynamic> raw) {
    // Hetzner: server_type.prices[].price_monthly
    final serverType = raw['server_type'];
    if (serverType is Map) {
      final prices = serverType['prices'];
      if (prices is List && prices.isNotEmpty) {
        final priceEntry = prices[0];
        if (priceEntry is Map) {
          final monthly = priceEntry['price_monthly'];
          if (monthly is Map) {
            final net = monthly['net'];
            if (net is num) return net.toDouble();
            if (net is String) return double.tryParse(net);
          } else if (monthly is num) {
            return monthly.toDouble();
          } else if (monthly is String) {
            return double.tryParse(monthly);
          }
        }
      }
    }
    // OVH Cloud: flavor.monthlyPrice
    final flavor = raw['flavor'];
    if (flavor is Map) {
      final mp = flavor['monthlyPrice'] ?? flavor['monthly_price'];
      if (mp is num) return mp.toDouble();
      if (mp is String) return double.tryParse(mp);
    }
    // OVH: price field at top level
    final price = raw['price'];
    if (price is Map) {
      final monthly = price['monthly'] ?? price['monthlyPrice'] ?? price['value'];
      if (monthly is num) return monthly.toDouble();
      if (monthly is String) return double.tryParse(monthly);
    } else if (price is num) {
      return price.toDouble();
    } else if (price is String) {
      return double.tryParse(price);
    }
    // OVH: monthlyPrice at top level
    final monthlyPrice = raw['monthlyPrice'] ?? raw['monthly_price'];
    if (monthlyPrice is num) return monthlyPrice.toDouble();
    if (monthlyPrice is String) return double.tryParse(monthlyPrice);
    return null;
  }

  /// Extract currency from raw API data.
  static String? _extractCurrency(Map<String, dynamic> raw) {
    // Hetzner always uses EUR
    if (raw['server_type'] != null) return 'EUR';
    // OVH typically uses EUR
    final price = raw['price'];
    if (price is Map) {
      final cur = price['currency'] ?? price['currencyCode'];
      if (cur is String) return cur;
    }
    final cur = raw['currency'] ?? raw['currencyCode'];
    if (cur is String) return cur;
    return null;
  }

  /// Extract OS name from a server response map.
  static String? _extractOs(Map<String, dynamic> srv) {
    if (srv['os'] != null) return srv['os'].toString();
    final image = srv['image'];
    if (image is Map) {
      final os = image['os'];
      if (os is Map) return os['name']?.toString();
      return image['name']?.toString();
    }
    return null;
  }

  /// Get cached machines from DB (fast, no API calls).
  Future<List<MachineInfo>> getCachedMachines() async {
    final rows = await db.cachedMachineDao.getAll();
    return rows.map((r) {
      final raw = r.raw != null ? jsonDecode(r.raw!) as Map<String, dynamic> : null;
      return MachineInfo(
        id: r.providerId,
        name: r.name,
        provider: r.provider,
        status: r.status,
        ipAddresses: List<String>.from(jsonDecode(r.ipAddresses)),
        region: r.region,
        alias: r.alias,
        flavor: r.flavor,
        image: r.image,
        createdAt: '',
        vcpus: raw?['vcpus'] is int ? raw!['vcpus'] : null,
        memoryMB: raw?['memoryMB'] is int ? raw!['memoryMB'] : null,
        diskGB: raw?['diskGB'] is int ? raw!['diskGB'] : null,
        bandwidth: raw?['bandwidth']?.toString(),
        os: raw?['os']?.toString() ?? r.image,
        commercialRange: raw?['commercialRange']?.toString(),
        raw: raw,
        uncloudMachineId: r.uncloudMachineId,
        uncloudContext: r.uncloudContext,
        monthlyCost: r.monthlyCost,
        currency: r.currency,
      );
    }).toList();
  }

  Future<void> _cacheMachines(List<MachineInfo> machines) async {
    final now = DateTime.now();
    final freshIds = machines.map((m) => m.id).toSet();

    // Read existing UC fields so we don't overwrite them during provider sync
    final existing = await db.cachedMachineDao.getAll();
    final ucFields = <String, (String?, String?)>{};
    for (final e in existing) {
      ucFields[e.id] = (e.uncloudMachineId, e.uncloudContext);
    }

    // Upsert fresh data, preserving Uncloud fields
    await db.cachedMachineDao.upsertMachines(
      machines.map((m) {
        final (existingUcId, existingUcCtx) = ucFields[m.id] ?? (null, null);
        return CachedMachinesCompanion.insert(
          id: m.id,
          providerId: m.id,
          provider: m.provider,
          name: m.name,
          alias: Value(m.alias),
          status: Value(m.status),
          ipAddresses: Value(jsonEncode(m.ipAddresses)),
          region: Value(m.region),
          flavor: Value(m.flavor),
          image: Value(m.image),
          raw: Value(m.raw != null ? jsonEncode(m.raw) : null),
          uncloudMachineId: Value(m.uncloudMachineId ?? existingUcId),
          uncloudContext: Value(m.uncloudContext ?? existingUcCtx),
          monthlyCost: Value(m.monthlyCost),
          currency: Value(m.currency),
          lastSyncedAt: Value(now),
        );
      }).toList(),
    );

    // Remove stale entries
    final staleIds = existing.where((e) => !freshIds.contains(e.id)).map((e) => e.id).toList();
    if (staleIds.isNotEmpty) {
      await db.cachedMachineDao.deleteByIds(staleIds);
    }
  }

  // ── Domains ──────────────────────────────────────────────────────────

  /// List all domains across configured providers (live data).
  Future<List<DomainInfo>> listDomains() async {
    final domains = <DomainInfo>[];

    // Cloudflare zones
    final cfCreds = await getCredentials('cloudflare');
    if (cfCreds != null && cfCreds.containsKey('apiToken')) {
      try {
        final cf = CloudflareService(
          apiToken: cfCreds['apiToken']!,
          accountId: cfCreds['accountId'],
        );
        final zones = await cf.listZones();
        for (final zone in zones) {
          final cfNs = List<String>.from(zone['nameservers'] ?? []);
          domains.add(DomainInfo(
            name: zone['name'] as String,
            provider: 'cloudflare',
            nameservers: cfNs,
            cfZoneId: zone['id'] as String?,
            cfStatus: zone['status'] as String?,
            dnsProvider: 'cloudflare',
            cfNameservers: cfNs,
          ));
        }
      } catch (e) {
        print('[ClarityMelt] Cloudflare zones error: $e');
      }
    }

    // Namecheap domains
    final ncCreds = await getCredentials('namecheap');
    if (ncCreds != null && ncCreds.containsKey('apiUser')) {
      try {
        final nc = NamecheapService(
          apiUser: ncCreds['apiUser']!,
          apiKey: ncCreds['apiKey'] ?? '',
          clientIp: ncCreds['clientIp'] ?? '',
        );
        final ncDomains = await nc.listDomains();
        for (final d in ncDomains) {
          final existingIdx = domains.indexWhere((x) => x.name == d['name']);
          if (existingIdx >= 0) {
            // Merge: Namecheap domain also exists in Cloudflare
            // Keep the CF zone info, add Namecheap as DNS fallback
            final existing = domains[existingIdx];
            if (existing.dnsProvider == null) {
              domains[existingIdx] = DomainInfo(
                name: existing.name,
                provider: existing.provider,
                nameservers: existing.nameservers,
                cfZoneId: existing.cfZoneId,
                cfStatus: existing.cfStatus,
                expires: d['expires'] as String? ?? existing.expires,
                dnsProvider: existing.cfZoneId != null ? 'cloudflare' : 'namecheap',
                cfNameservers: existing.cfNameservers,
              );
            }
          } else {
            domains.add(DomainInfo(
              name: d['name'] as String,
              provider: 'namecheap',
              nameservers: [],
              expires: d['expires'] as String?,
              dnsProvider: 'namecheap',
            ));
          }
        }
      } catch (e) {
        print('[ClarityMelt] Namecheap domains error: $e');
      }
    }

    // OVH domains
    final ovhCreds = await getCredentials('ovh');
    final ovh = buildOvhService(ovhCreds);
    if (ovh != null) {
      try {
        final ovhDomains = await ovh.listDomains();
        for (final d in ovhDomains) {
          final existingIdx = domains.indexWhere((x) => x.name == d['name']);
          if (existingIdx >= 0) {
            // Merge: OVH domain also exists elsewhere — add OVH DNS if not set
            final existing = domains[existingIdx];
            if (existing.dnsProvider == null) {
              domains[existingIdx] = DomainInfo(
                name: existing.name,
                provider: existing.provider,
                nameservers: List<String>.from(d['nameservers'] as List? ?? []),
                cfZoneId: existing.cfZoneId,
                cfStatus: existing.cfStatus,
                expires: d['expiration'] as String? ?? existing.expires,
                dnsProvider: existing.cfZoneId != null ? 'cloudflare' : 'ovh',
                cfNameservers: existing.cfNameservers,
              );
            }
          } else {
            domains.add(DomainInfo(
              name: d['name'] as String,
              provider: 'ovh',
              nameservers: List<String>.from(d['nameservers'] ?? []),
              expires: d['expiration'] as String?,
              dnsProvider: 'ovh',
            ));
          }
        }
      } catch (e) {
        print('[ClarityMelt] OVH domains error: $e');
      }
    }

    // Cache to DB
    await _cacheDomains(domains);

    return domains;
  }

  /// Get cached domains from DB (fast, no API calls).
  Future<List<DomainInfo>> getCachedDomains() async {
    final rows = await db.cachedDomainDao.getAll();
    return rows.map((r) => DomainInfo(
          name: r.name,
          provider: r.provider,
          nameservers: List<String>.from(jsonDecode(r.nameservers)),
          cfZoneId: r.cfZoneId,
          cfStatus: r.cfStatus,
          expires: r.expires,
          dnsProvider: r.dnsProvider,
          cfNameservers: r.cfNameservers != null && r.cfNameservers!.isNotEmpty
              ? List<String>.from(jsonDecode(r.cfNameservers!))
              : [],
          raw: r.raw != null ? jsonDecode(r.raw!) : null,
        )).toList();
  }

  Future<void> _cacheDomains(List<DomainInfo> domains) async {
    final now = DateTime.now();
    final freshNames = domains.map((d) => d.name).toSet();

    // Use deterministic IDs based on provider+name so upserts update existing rows
    // instead of creating duplicates on every sync.
    await db.cachedDomainDao.upsertDomains(
      domains.map((d) {
        final domainId = 'domain-${d.provider}-${d.name}';
        return CachedDomainsCompanion.insert(
          id: domainId,
          name: d.name,
          provider: d.provider,
          nameservers: Value(jsonEncode(d.nameservers)),
          cfZoneId: Value(d.cfZoneId),
          cfStatus: Value(d.cfStatus),
          dnsProvider: Value(d.dnsProvider),
          cfNameservers: Value(jsonEncode(d.cfNameservers)),
          expires: Value(d.expires),
          raw: Value(d.raw != null ? jsonEncode(d.raw) : null),
          lastSyncedAt: Value(now),
        );
      }).toList(),
    );

    // Remove stale entries (domains no longer returned by any provider)
    final existing = await db.cachedDomainDao.getAll();
    final staleIds = existing.where((e) => !freshNames.contains(e.name)).map((e) => e.id).toList();
    if (staleIds.isNotEmpty) {
      await db.cachedDomainDao.deleteByIds(staleIds);
    }
  }

  // ── DNS Records ─────────────────────────────────────────────────────

  /// List DNS records for a domain, routing to the correct provider.
  /// [domainName] is the domain name (e.g. "example.com")
  /// [provider] is which DNS provider to use: "cloudflare", "ovh", "namecheap"
  /// [zoneId] is the Cloudflare zone ID (required for Cloudflare provider)
  Future<List<DnsRecordInfo>> listDnsRecordsForDomain(
    String domainName,
    String provider, {
    String? zoneId,
  }) async {
    switch (provider) {
      case 'cloudflare':
        return await _listCloudflareDnsRecords(zoneId ?? domainName);
      case 'ovh':
        return await _listOvhDnsRecords(domainName);
      case 'namecheap':
        return await _listNamecheapDnsRecords(domainName);
      default:
        throw Exception('Unknown DNS provider: $provider');
    }
  }

  /// List DNS records for a Cloudflare zone (live data).
  Future<List<DnsRecordInfo>> _listCloudflareDnsRecords(String zoneId) async {
    final cfCreds = await getCredentials('cloudflare');
    if (cfCreds == null || !cfCreds.containsKey('apiToken')) {
      throw Exception('Cloudflare API token not configured');
    }

    final cf = CloudflareService(
      apiToken: cfCreds['apiToken']!,
      accountId: cfCreds['accountId'],
    );

    final zone = await cf.getZone(zoneId);
    final records = await cf.listDnsRecords(zoneId);

    final result = records.map((r) => DnsRecordInfo(
          id: r['id'] as String,
          type: r['type'] as String,
          name: r['name'] as String,
          content: r['content'] as String,
          ttl: r['ttl'] as int? ?? 1,
          proxied: r['proxied'] as bool? ?? false,
          zoneId: zoneId,
          zoneName: zone['name'] as String? ?? '',
          provider: 'cloudflare',
        )).toList();

    // Cache to DB
    await _cacheDnsRecords(zoneId, zone['name'] as String? ?? '', result, 'cloudflare');

    return result;
  }

  /// List DNS records for an OVH domain zone (live data).
  Future<List<DnsRecordInfo>> _listOvhDnsRecords(String domainName) async {
    final ovhCreds = await getCredentials('ovh');
    final ovh = buildOvhService(ovhCreds);
    if (ovh == null) {
      throw Exception('OVH credentials not configured');
    }

    final rawRecords = await ovh.listDnsRecords(domainName);
    final result = <DnsRecordInfo>[];
    int idx = 0;
    for (final r in rawRecords) {
      result.add(DnsRecordInfo(
        id: 'ovh-${r['id'] ?? idx}',
        type: (r['fieldType'] ?? r['type'] ?? 'A') as String,
        name: (r['subDomain'] != null && (r['subDomain'] as String).isNotEmpty)
            ? '${r['subDomain']}.$domainName'
            : domainName,
        content: (r['target'] ?? r['content'] ?? '') as String,
        ttl: (r['ttl'] ?? 3600) as int,
        proxied: false,
        priority: r['priority'] as int?,
        zoneId: domainName,
        zoneName: domainName,
        provider: 'ovh',
      ));
      idx++;
    }

    // Cache to DB
    await _cacheDnsRecords(domainName, domainName, result, 'ovh');

    return result;
  }

  /// List DNS records for a Namecheap domain (live data).
  Future<List<DnsRecordInfo>> _listNamecheapDnsRecords(String domainName) async {
    final ncCreds = await getCredentials('namecheap');
    if (ncCreds == null || !ncCreds.containsKey('apiUser')) {
      throw Exception('Namecheap credentials not configured');
    }

    final nc = NamecheapService(
      apiUser: ncCreds['apiUser']!,
      apiKey: ncCreds['apiKey'] ?? '',
      clientIp: ncCreds['clientIp'] ?? '',
    );

    final rawRecords = await nc.listDnsRecords(domainName);
    final result = rawRecords.map((r) => DnsRecordInfo(
          id: r['id']?.toString() ?? '${r['type']}-${r['name']}-${r['content']}',
          type: (r['type'] ?? 'A') as String,
          name: (r['name'] ?? domainName) as String,
          content: (r['content'] ?? r['Address'] ?? '') as String,
          ttl: (r['ttl'] ?? 3600) as int,
          proxied: false,
          priority: r['mxPriority'] != null ? int.tryParse(r['mxPriority'].toString()) : null,
          zoneId: domainName,
          zoneName: domainName,
          provider: 'namecheap',
        )).toList();

    // Cache to DB
    await _cacheDnsRecords(domainName, domainName, result, 'namecheap');

    return result;
  }

  /// Backwards-compatible method: list DNS records for a Cloudflare zone ID.
  Future<List<DnsRecordInfo>> listDnsRecords(String zoneId) async {
    return await _listCloudflareDnsRecords(zoneId);
  }

  /// Get cached DNS records from DB (fast, no API calls).
  Future<List<DnsRecordInfo>> getCachedDnsRecords(String zoneId) async {
    final rows = await db.cachedDnsRecordDao.getByZoneId(zoneId);
    return rows.map((r) => DnsRecordInfo(
          id: r.id,
          type: r.type,
          name: r.name,
          content: r.content,
          ttl: r.ttl,
          proxied: r.proxied,
          priority: r.priority,
          zoneId: r.zoneId,
          zoneName: r.zoneName,
          provider: r.provider,
        )).toList();
  }

  /// Create a DNS record (Cloudflare only for now).
  Future<DnsRecordInfo> createDnsRecord(
    String zoneId, {
    required String type,
    required String name,
    required String content,
    int? ttl,
    bool? proxied,
  }) async {
    final cfCreds = await getCredentials('cloudflare');
    if (cfCreds == null || !cfCreds.containsKey('apiToken')) {
      throw Exception('Cloudflare API token not configured');
    }

    final cf = CloudflareService(
      apiToken: cfCreds['apiToken']!,
      accountId: cfCreds['accountId'],
    );

    final result = await cf.createDnsRecord(
      zoneId,
      type: type,
      name: name,
      content: content,
      ttl: ttl,
      proxied: proxied,
    );

    // Invalidate cache
    await db.cachedDnsRecordDao.deleteByZoneId(zoneId);

    return DnsRecordInfo(
      id: result['id'] as String,
      type: result['type'] as String,
      name: result['name'] as String,
      content: result['content'] as String,
      ttl: result['ttl'] as int? ?? 1,
      proxied: result['proxied'] as bool? ?? false,
      zoneId: zoneId,
      zoneName: '',
      provider: 'cloudflare',
    );
  }

  /// Update a DNS record (Cloudflare only for now).
  Future<DnsRecordInfo> updateDnsRecord(
    String zoneId,
    String recordId, {
    required String type,
    required String name,
    required String content,
    int? ttl,
    bool? proxied,
  }) async {
    final cfCreds = await getCredentials('cloudflare');
    if (cfCreds == null || !cfCreds.containsKey('apiToken')) {
      throw Exception('Cloudflare API token not configured');
    }

    final cf = CloudflareService(
      apiToken: cfCreds['apiToken']!,
      accountId: cfCreds['accountId'],
    );

    final result = await cf.updateDnsRecord(
      zoneId,
      recordId,
      type: type,
      name: name,
      content: content,
      ttl: ttl,
      proxied: proxied,
    );

    // Invalidate cache
    await db.cachedDnsRecordDao.deleteByZoneId(zoneId);

    return DnsRecordInfo(
      id: result['id'] as String,
      type: result['type'] as String,
      name: result['name'] as String,
      content: result['content'] as String,
      ttl: result['ttl'] as int? ?? 1,
      proxied: result['proxied'] as bool? ?? false,
      zoneId: zoneId,
      zoneName: '',
      provider: 'cloudflare',
    );
  }

  /// Delete a DNS record (Cloudflare only for now).
  Future<bool> deleteDnsRecord(String zoneId, String recordId) async {
    final cfCreds = await getCredentials('cloudflare');
    if (cfCreds == null || !cfCreds.containsKey('apiToken')) {
      throw Exception('Cloudflare API token not configured');
    }

    final cf = CloudflareService(
      apiToken: cfCreds['apiToken']!,
      accountId: cfCreds['accountId'],
    );

    final result = await cf.deleteDnsRecord(zoneId, recordId);

    // Invalidate cache
    await db.cachedDnsRecordDao.deleteByZoneId(zoneId);

    return result;
  }

  /// Provision a domain: create Cloudflare zone, add A record, optionally update nameservers.
  Future<ProvisionResult> provisionDomain({
    required String domain,
    required String machineIp,
    String? subdomain,
    bool proxied = false,
    bool updateNameservers = true,
  }) async {
    final cfCreds = await getCredentials('cloudflare');
    if (cfCreds == null || !cfCreds.containsKey('apiToken')) {
      throw Exception('Cloudflare API token not configured');
    }

    final cf = CloudflareService(
      apiToken: cfCreds['apiToken']!,
      accountId: cfCreds['accountId'],
    );

    // 1. Create or find Cloudflare zone
    final zone = await cf.findZoneByName(domain) ?? await cf.createZone(domain);

    // 2. Create A record
    final recordName = subdomain ?? '@';
    final dnsRecord = await cf.createDnsRecord(
      zone['id'] as String,
      type: 'A',
      name: recordName,
      content: machineIp,
      proxied: proxied,
    );

    // 3. Optionally update nameservers at registrar
    bool nameserversUpdated = false;
    if (updateNameservers && (zone['nameservers'] as List?)?.isNotEmpty == true) {
      final ns = (zone['nameservers'] as List).cast<String>();
      final ncCreds = await getCredentials('namecheap');
      if (ncCreds != null && ncCreds.containsKey('apiUser')) {
        try {
          final nc = NamecheapService(
            apiUser: ncCreds['apiUser']!,
            apiKey: ncCreds['apiKey'] ?? '',
            clientIp: ncCreds['clientIp'] ?? '',
          );
          nameserversUpdated = await nc.updateNameservers(domain, ns);
        } catch (e) {
          print('[ClarityMelt] Namecheap nameserver update error: $e');
        }
      }
    }

    // Invalidate domain cache
    await db.cachedDomainDao.deleteByName(domain);

    return ProvisionResult(
      zone: zone,
      dnsRecord: dnsRecord,
      nameserversUpdated: nameserversUpdated,
    );
  }


  /// Get a map of IP -> DNS records for machines.
  Future<Map<String, List<DnsRecordInfo>>> getMachineDnsMap() async {
    final machines = await listMachines();
    final domains = await listDomains();
    final allIps = machines.expand((m) => m.ipAddresses).toList();
    final ipMap = <String, List<DnsRecordInfo>>{};
    for (final ip in allIps) {
      ipMap[ip] = [];
    }

    // Collect DNS records from Cloudflare
    final cfCreds = await getCredentials('cloudflare');
    if (cfCreds != null && cfCreds.containsKey('apiToken')) {
      final cf = CloudflareService(
        apiToken: cfCreds['apiToken']!,
        accountId: cfCreds['accountId'],
      );
      for (final domain in domains) {
        if (domain.cfZoneId == null) continue;
        try {
          final records = await cf.listDnsRecords(domain.cfZoneId!);
          for (final r in records) {
            if (r['type'] == 'A' && ipMap.containsKey(r['content'])) {
              ipMap[r['content']]!.add(DnsRecordInfo(
                id: r['id'] as String,
                type: r['type'] as String,
                name: r['name'] as String,
                content: r['content'] as String,
                ttl: r['ttl'] as int? ?? 1,
                proxied: r['proxied'] as bool? ?? false,
                zoneId: domain.cfZoneId!,
                zoneName: domain.name,
                provider: 'cloudflare',
              ));
            }
          }
        } catch (e) {
          print('[ClarityMelt] Cloudflare DNS map error for ${domain.name}: $e');
        }
      }
    }

    // Also collect from OVH domain DNS
    final ovhCreds = await getCredentials('ovh');
    final ovh = buildOvhService(ovhCreds);
    if (ovh != null) {
      for (final domain in domains.where((d) => d.provider == 'ovh' && d.cfZoneId == null)) {
        try {
          final records = await ovh.listDnsRecords(domain.name);
          for (final r in records) {
            final type = (r['fieldType'] ?? r['type'] ?? '') as String;
            final content = (r['target'] ?? r['content'] ?? '') as String;
            if (type == 'A' && ipMap.containsKey(content)) {
              final subDomain = (r['subDomain'] ?? '') as String;
              final name = subDomain.isNotEmpty ? '$subDomain.${domain.name}' : domain.name;
              ipMap[content]!.add(DnsRecordInfo(
                id: 'ovh-${r['id'] ?? ''}',
                type: type,
                name: name,
                content: content,
                ttl: (r['ttl'] ?? 3600) as int,
                zoneId: domain.name,
                zoneName: domain.name,
                provider: 'ovh',
              ));
            }
          }
        } catch (e) {
          print('[ClarityMelt] OVH DNS map error for ${domain.name}: $e');
        }
      }
    }

    return ipMap;
  }

  // ── Cache helpers ───────────────────────────────────────────────────

  // ── OVH helper ──────────────────────────────────────────────────────

  /// Build an OVHService from credential map, supporting both
  /// application key and OAuth2 authentication, plus endpoint selection.
  OVHService? buildOvhService(Map<String, String>? creds) {
    if (creds == null) return null;

    // OAuth2 authentication
    if (creds.containsKey('clientId') && creds['clientId']!.isNotEmpty) {
      return OVHService(
        endpoint: creds['endpoint'] ?? 'ovh-eu',
        clientId: creds['clientId'],
        clientSecret: creds['clientSecret'] ?? '',
      );
    }

    // Application key authentication
    if (creds.containsKey('applicationKey') && creds['applicationKey']!.isNotEmpty) {
      return OVHService(
        endpoint: creds['endpoint'] ?? 'ovh-eu',
        applicationKey: creds['applicationKey'],
        applicationSecret: creds['applicationSecret'] ?? '',
        consumerKey: creds['consumerKey'] ?? '',
      );
    }

    return null;
  }

  // ── Cloudflare Workers & Pages ────────────────────────────────────

  /// List Cloudflare Workers scripts for all configured Cloudflare credentials.
  Future<List<CloudflareWorkerInfo>> listWorkers() async {
    final allWorkers = <CloudflareWorkerInfo>[];
    final cfCreds = await db.providerCredentialDao.getByProvider('cloudflare');
    for (final cred in cfCreds) {
      try {
        final decrypted = await decryptCredentials(cred);
        if (decrypted == null) continue;
        final svc = CloudflareService(
          apiToken: decrypted['apiToken']!,
          accountId: decrypted['accountId'],
        );
        final raw = await svc.listWorkers();
        for (final w in raw) {
          allWorkers.add(CloudflareWorkerInfo(
            id: w['id']?.toString() ?? '',
            name: w['name']?.toString() ?? w['id']?.toString() ?? '',
            script: w['script']?.toString(),
            status: w['status']?.toString(),
            createdOn: w['createdOn'] is DateTime ? w['createdOn'] as DateTime : null,
            modifiedOn: w['modifiedOn'] is DateTime ? w['modifiedOn'] as DateTime : null,
            raw: w['raw'] as Map<String, dynamic>?,
          ));
        }
      } catch (e) {
        print('[ClarityMelt] listWorkers error for ${cred.label}: $e');
      }
    }
    return allWorkers;
  }

  /// List Cloudflare Pages projects for all configured Cloudflare credentials.
  Future<List<CloudflarePagesInfo>> listPagesProjects() async {
    final allPages = <CloudflarePagesInfo>[];
    final cfCreds = await db.providerCredentialDao.getByProvider('cloudflare');
    for (final cred in cfCreds) {
      try {
        final decrypted = await decryptCredentials(cred);
        if (decrypted == null) continue;
        final svc = CloudflareService(
          apiToken: decrypted['apiToken']!,
          accountId: decrypted['accountId'],
        );
        final raw = await svc.listPagesProjects();
        for (final p in raw) {
          allPages.add(CloudflarePagesInfo(
            id: p['id']?.toString() ?? '',
            name: p['name']?.toString() ?? '',
            subdomain: p['subdomain']?.toString(),
            productionBranch: p['productionBranch']?.toString() ?? p['production_branch']?.toString(),
            createdOn: p['createdOn'] is DateTime ? p['createdOn'] as DateTime : null,
            raw: p['raw'] as Map<String, dynamic>?,
          ));
        }
      } catch (e) {
        print('[ClarityMelt] listPagesProjects error for ${cred.label}: $e');
      }
    }
    return allPages;
  }

  // ── OVH Monitoring ─────────────────────────────────────────────────

  /// Get OVH monitoring details for a dedicated server.
  Future<OvhMonitoringInfo?> getOvhDedicatedMonitoring(String serverName) async {
    final ovhCreds = await db.providerCredentialDao.getByProvider('ovh');
    if (ovhCreds.isEmpty) return null;
    final cred = ovhCreds.first;
    try {
      final decrypted = await decryptCredentials(cred);
      if (decrypted == null) return null;
      final svc = buildOvhService(decrypted);
      if (svc == null) return null;
      final data = await svc.getDedicatedServerMonitoring(serverName);
      return OvhMonitoringInfo(
        state: data['state']?.toString(),
        monitoringPeriod: data['monitoringPeriod']?.toString(),
        ipv4: data['ipv4']?.toString(),
        ipv6: data['ipv6']?.toString(),
        datacenter: data['datacenter']?.toString(),
        professional: data['professional'] == true,
        raw: data,
      );
    } catch (e) {
      print('[ClarityMelt] getOvhDedicatedMonitoring error: $e');
      return null;
    }
  }

  /// Get OVH service details for a dedicated server.
  Future<Map<String, dynamic>?> getOvhDedicatedService(String serverName) async {
    final ovhCreds = await db.providerCredentialDao.getByProvider('ovh');
    if (ovhCreds.isEmpty) return null;
    final cred = ovhCreds.first;
    try {
      final decrypted = await decryptCredentials(cred);
      if (decrypted == null) return null;
      final svc = buildOvhService(decrypted);
      if (svc == null) return null;
      return await svc.getDedicatedServerService(serverName);
    } catch (e) {
      print('[ClarityMelt] getOvhDedicatedService error: $e');
      return null;
    }
  }

  /// Get OVH service details for a VPS.
  Future<Map<String, dynamic>?> getOvhVpsService(String vpsName) async {
    final ovhCreds = await db.providerCredentialDao.getByProvider('ovh');
    if (ovhCreds.isEmpty) return null;
    final cred = ovhCreds.first;
    try {
      final decrypted = await decryptCredentials(cred);
      if (decrypted == null) return null;
      final svc = buildOvhService(decrypted);
      if (svc == null) return null;
      return await svc.getVpsService(vpsName);
    } catch (e) {
      print('[ClarityMelt] getOvhVpsService error: $e');
      return null;
    }
  }

  // ── Products ──────────────────────────────────────────────────────

  /// List all products.
  Future<List<ProductInfo>> listProducts() async {
    final products = await db.productDao.getAll();
    final result = <ProductInfo>[];
    for (final p in products) {
      final resources = await db.productDao.getResourcesForProduct(p.id);
      result.add(ProductInfo(
        id: p.id,
        name: p.name,
        description: p.description,
        createdAt: p.createdAt,
        updatedAt: p.updatedAt,
        resources: resources.map((r) => ProductResourceInfo(
          id: r.id,
          productId: r.productId,
          resourceType: r.resourceType,
          resourceId: r.resourceId,
          role: r.role,
          metadata: r.metadata != null
              ? (r.metadata is String ? jsonDecode(r.metadata as String) as Map<String, dynamic> : r.metadata as Map<String, dynamic>)
              : const {},
          createdAt: r.createdAt,
        )).toList(),
      ));
    }
    return result;
  }

  /// Create a new product.
  Future<ProductInfo> createProduct({
    required String name,
    String? description,
  }) async {
    final id = 'product-${_uuid.v4()}';
    final now = DateTime.now();
    await db.productDao.insertProduct(ProductsCompanion.insert(
      id: id,
      name: name,
      description: description != null ? Value(description) : const Value.absent(),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    return ProductInfo(
      id: id,
      name: name,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Delete a product and its resources.
  Future<void> deleteProduct(String id) async {
    await db.productDao.deleteResourcesForProduct(id);
    await db.productDao.deleteProduct(id);
  }

  /// Add a resource to a product.
  Future<ProductResourceInfo> addResourceToProduct({
    required String productId,
    required String resourceType,
    required String resourceId,
    String role = 'primary',
    Map<String, dynamic>? metadata,
  }) async {
    final id = 'pr-${_uuid.v4()}';
    final now = DateTime.now();
    await db.productDao.insertResource(ProductResourcesCompanion.insert(
      id: id,
      productId: productId,
      resourceType: resourceType,
      resourceId: resourceId,
      role: Value(role),
      metadata: metadata != null ? Value(jsonEncode(metadata)) : const Value.absent(),
      createdAt: Value(now),
    ));
    return ProductResourceInfo(
      id: id,
      productId: productId,
      resourceType: resourceType,
      resourceId: resourceId,
      role: role,
      metadata: metadata ?? const {},
      createdAt: now,
    );
  }

  /// Remove a resource from a product.
  Future<void> removeResourceFromProduct(String resourceId) async {
    await db.productDao.deleteResource(resourceId);
  }

  // ── OVH Instance Specs ──────────────────────────────────────────────────

  /// Fetch detailed hardware specs for an OVH Cloud instance.
  /// The flavor field in listInstances may contain vcpus/ram/disk but
  /// this fetches the full flavor details.
  Future<Map<String, dynamic>> getOvhCloudInstanceSpecs(String machineId) async {
    // machineId format: "ovh-<instanceId>"
    if (!machineId.startsWith('ovh-') || machineId.startsWith('ovh-vps-') || machineId.startsWith('ovh-dedicated-')) {
      return {};
    }
    final instanceId = machineId.substring(4); // remove "ovh-"
    final ovhCreds = await db.providerCredentialDao.getByProvider('ovh');
    if (ovhCreds.isEmpty) return {};
    try {
      final decrypted = await decryptCredentials(ovhCreds.first);
      if (decrypted == null) return {};
      final svc = buildOvhService(decrypted);
      if (svc == null) return {};

      // We need the project ID. List projects to find it.
      final projectIds = await svc.listInstances();
      // The flavor ID is embedded in the instance's raw data.
      // Try fetching specs from the instance's flavorId.
      // Since we don't have the projectId easily, return raw data from the machine.
      // For now, return empty - the specs are already extracted during listMachines.
      return {};
    } catch (e) {
      print('[ClarityMelt] getOvhCloudInstanceSpecs error: $e');
      return {};
    }
  }

  /// Fetch hardware specs for an OVH VPS.
  Future<Map<String, dynamic>> getOvhVpsSpecs(String vpsName) async {
    // Remove 'ovh-vps-' prefix if present
    final name = vpsName.startsWith('ovh-vps-') ? vpsName.substring(8) : vpsName;
    final ovhCreds = await db.providerCredentialDao.getByProvider('ovh');
    if (ovhCreds.isEmpty) return {};
    try {
      final decrypted = await decryptCredentials(ovhCreds.first);
      if (decrypted == null) return {};
      final svc = buildOvhService(decrypted);
      if (svc == null) return {};
      return await svc.getVpsSpecification(name);
    } catch (e) {
      print('[ClarityMelt] getOvhVpsSpecs error: $e');
      return {};
    }
  }

  /// Fetch hardware specs for an OVH Dedicated server.
  Future<Map<String, dynamic>> getOvhDedicatedSpecs(String serverName) async {
    // Remove 'ovh-dedicated-' prefix if present
    final name = serverName.startsWith('ovh-dedicated-') ? serverName.substring(15) : serverName;
    final ovhCreds = await db.providerCredentialDao.getByProvider('ovh');
    if (ovhCreds.isEmpty) return {};
    try {
      final decrypted = await decryptCredentials(ovhCreds.first);
      if (decrypted == null) return {};
      final svc = buildOvhService(decrypted);
      if (svc == null) return {};
      return await svc.getDedicatedServerSpecifications(name);
    } catch (e) {
      print('[ClarityMelt] getOvhDedicatedSpecs error: $e');
      return {};
    }
  }

  // ── Helper: decrypt credentials ─────────────────────────────────────

  Future<Map<String, String>?> decryptCredentials(ProviderCredential cred) async {
    try {
      final encryptionKey = await db.preferencesDao.getEncryptionKey();
      if (encryptionKey.isEmpty) return null;
      final decrypted = CryptoService.decrypt(cred.credentials, encryptionKey);
      return Map<String, String>.from(jsonDecode(decrypted));
    } catch (e) {
      print('[ClarityMelt] decryptCredentials error: $e');
      return null;
    }
  }

  // ── Cache ────────────────────────────────────────────────────────────

  Future<void> _cacheDnsRecords(
    String zoneId,
    String zoneName,
    List<DnsRecordInfo> records, [
    String provider = 'cloudflare',
  ]) async {
    final now = DateTime.now();
    final freshIds = records.map((r) => r.id).toSet();

    await db.cachedDnsRecordDao.upsertRecords(
      records.map((r) => CachedDnsRecordsCompanion.insert(
            id: r.id,
            zoneId: zoneId,
            zoneName: Value(zoneName),
            provider: Value(provider),
            type: r.type,
            name: r.name,
            content: r.content,
            ttl: Value(r.ttl),
            proxied: Value(r.proxied),
            priority: Value(r.priority),
            lastSyncedAt: Value(now),
          )).toList(),
    );

    // Remove stale records for this zone
    final existing = await db.cachedDnsRecordDao.getByZoneId(zoneId);
    final staleIds = existing.where((e) => !freshIds.contains(e.id)).map((e) => e.id).toList();
    if (staleIds.isNotEmpty) {
      await db.cachedDnsRecordDao.deleteByIds(staleIds);
    }
  }
}

/// High-level OVH Cloud service for listing machines, domains, and DNS records.
///
/// Uses [OvhClient] internally for authentication and API calls.

import 'ovh_client.dart';

/// OVH Cloud service providing typed access to OVH API resources.
class OVHService {
  final OvhClient _client;

  OVHService({
    String endpoint = 'ovh-eu',
    String? applicationKey,
    String? applicationSecret,
    String? consumerKey,
    String? clientId,
    String? clientSecret,
  }) : _client = OvhClient(
          endpoint: endpoint,
          applicationKey: applicationKey,
          applicationSecret: applicationSecret,
          consumerKey: consumerKey,
          clientId: clientId,
          clientSecret: clientSecret,
        );

  /// Direct access to the underlying client for custom API calls.
  OvhClient get client => _client;

  // ── Cloud Instances ─────────────────────────────────────────────────

  /// List all Public Cloud instances across all projects.
  ///
  /// Returns a unified list of instance maps with normalized fields:
  /// `id`, `name`, `status`, `ipAddresses`, `flavor`, `image`, `region`,
  /// `createdAt`, `raw`.
  Future<List<Map<String, dynamic>>> listInstances() async {
    List<dynamic> projectIds;
    try {
      projectIds = await _client.get('/cloud/project') as List<dynamic>;
    } on OvhResourceNotFoundError {
      return [];
    } on OvhNotGrantedCallError {
      return [];
    } catch (_) {
      // Re-throw other errors
      rethrow;
    }

    // If the response was null or not a list, return empty
    if (projectIds.isEmpty) return [];

    final allInstances = <Map<String, dynamic>>[];

    for (final projectId in projectIds) {
      final id = projectId is String ? projectId : projectId.toString();
      try {
        final instances = await _client.get('/cloud/project/$id/instance') as List<dynamic>;

        for (final inst in instances) {
          final instMap = inst as Map<String, dynamic>;

          // Extract IP addresses from the list response (already included)
          final ipAddresses = _extractIpAddresses(instMap['ipAddresses']);

          // Flavor can be a map with 'name' or just an id string
          final flavor = instMap['flavor'];
          final flavorName = flavor is Map
              ? flavor['name']?.toString()
              : flavor?.toString();

          // Image can be a map with 'name' or just an id string
          final image = instMap['image'];
          final imageName = image is Map
              ? image['name']?.toString()
              : image?.toString();

          allInstances.add({
            'id': instMap['id'] ?? instMap['instanceId'],
            'name': instMap['name'] ?? instMap['instanceName'] ?? 'unnamed',
            'status': instMap['status'] ?? 'unknown',
            'ipAddresses': ipAddresses,
            'flavor': flavorName,
            'image': imageName,
            'region': instMap['region'] ?? 'unknown',
            'createdAt': instMap['created'] ?? instMap['createdAt'] ?? '',
            'vcpus': flavor is Map ? flavor['vcpus'] : null,
            'memoryMB': flavor is Map ? flavor['ram'] : null,
            'diskGB': flavor is Map ? flavor['disk'] : null,
            'os': imageName,
            'raw': instMap,
          });
        }
      } on OvhResourceNotFoundError {
        // Project not found — skip
      } on OvhNotGrantedCallError {
        // No permission — skip
      } catch (e) {
        print('[OVH] Cloud project $id instance fetch failed: $e');
      }
    }

    return allInstances;
  }

  // ── VPS Servers ─────────────────────────────────────────────────────

  /// List all VPS servers.
  ///
  /// Returns a unified list of VPS maps with normalized fields:
  /// `id`, `name`, `status`, `ipAddresses`, `datacenter`, `os`, `flavor`, `raw`.
  Future<List<Map<String, dynamic>>> listVps() async {
    List<dynamic> vpsNames;
    try {
      vpsNames = await _client.get('/vps') as List<dynamic>;
    } on OvhResourceNotFoundError {
      return [];
    } on OvhNotGrantedCallError {
      return [];
    } catch (_) {
      rethrow;
    }

    final servers = <Map<String, dynamic>>[];

    for (final name in vpsNames) {
      final vpsName = name.toString();
      try {
        final detail = await _client.get('/vps/${Uri.encodeComponent(vpsName)}') as Map<String, dynamic>;

        final ipAddresses = await _fetchVpsIps(vpsName);

        servers.add({
          'id': detail['name'] ?? vpsName,
          'name': detail['name'] ?? vpsName,
          'status': detail['state'] ?? detail['status'] ?? 'unknown',
          'ipAddresses': ipAddresses,
          'datacenter': detail['datacenter'] ?? detail['cluster'] ?? 'unknown',
          'os': detail['os'] ?? detail['distribution'] ?? 'unknown',
          'flavor': detail['model'] ?? detail['offer'],
          'vcpus': detail['vcpus'] ?? detail['cores'],
          'memoryMB': detail['ram'] ?? detail['memory'],
          'diskGB': detail['disk'] ?? detail['storage'],
          'bandwidth': detail['bandwidth']?.toString(),
          'raw': detail,
        });
      } catch (e) {
        // Per-entry errors — add minimal entry so the VPS is still visible
        print('[OVH] VPS detail fetch failed for $vpsName: $e');
        servers.add({
          'id': vpsName,
          'name': vpsName,
          'status': 'unknown',
          'ipAddresses': <String>[],
          'datacenter': 'unknown',
          'os': 'unknown',
          'flavor': null,
        });
      }
    }

    return servers;
  }

  /// Fetch IPs for a VPS server.
  Future<List<String>> _fetchVpsIps(String vpsName) async {
    try {
      final ips = await _client.get('/vps/${Uri.encodeComponent(vpsName)}/ips') as List<dynamic>;
      return ips.map((ipEntry) {
        if (ipEntry is Map) {
          return (ipEntry['ip'] ?? ipEntry['value'] ?? '').toString();
        }
        return ipEntry.toString();
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Dedicated Servers ────────────────────────────────────────────────

  /// List all dedicated servers.
  ///
  /// Returns a unified list of dedicated server maps with normalized fields:
  /// `id`, `name`, `status`, `ipAddresses`, `datacenter`, `os`,
  /// `commercialRange`, `raw`.
  Future<List<Map<String, dynamic>>> listDedicatedServers() async {
    List<dynamic> serverNames;
    try {
      serverNames = await _client.get('/dedicated/server') as List<dynamic>;
    } on OvhResourceNotFoundError {
      return [];
    } on OvhNotGrantedCallError {
      return [];
    } catch (_) {
      rethrow;
    }

    final servers = <Map<String, dynamic>>[];

    for (final name in serverNames) {
      final serverName = name.toString();
      try {
        final detail = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}') as Map<String, dynamic>;

        final ipAddresses = await _fetchDedicatedServerIps(serverName);

        servers.add({
          'id': serverName,
          'name': detail['name'] ?? serverName,
          'status': detail['state'] ?? detail['status'] ?? 'unknown',
          'ipAddresses': ipAddresses,
          'datacenter': detail['datacenter'] ?? 'unknown',
          'os': detail['os'] ?? detail['operatingSystem'] ?? 'unknown',
          'commercialRange': detail['commercialRange'] ?? 'unknown',
          'flavor': detail['commercialRange'] ?? 'unknown',
          'bandwidth': detail['bandwidth']?.toString() ?? detail['network']?['bandwidth']?.toString(),
          'raw': detail,
        });
      } catch (e) {
        print('[OVH] Dedicated server detail fetch failed for $serverName: $e');
        servers.add({
          'id': serverName,
          'name': serverName,
          'status': 'unknown',
          'ipAddresses': <String>[],
          'datacenter': 'unknown',
          'os': 'unknown',
          'commercialRange': 'unknown',
        });
      }
    }

    return servers;
  }

  /// Fetch IPs for a dedicated server.
  Future<List<String>> _fetchDedicatedServerIps(String serverName) async {
    try {
      final ips = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/ips') as List<dynamic>;
      return ips.map((ipEntry) {
        // The /dedicated/server/{name}/ips endpoint returns ipBlock objects
        if (ipEntry is Map) {
          return (ipEntry['ip'] ?? ipEntry['value'] ?? '').toString();
        }
        return ipEntry.toString();
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Domains ──────────────────────────────────────────────────────────

  /// List all domains.
  ///
  /// Returns a list of domain maps with: `name`, `nameservers`, `expiration`,
  /// `status`, `raw`.
  Future<List<Map<String, dynamic>>> listDomains() async {
    List<dynamic> domainNames;
    try {
      domainNames = await _client.get('/domain') as List<dynamic>;
    } on OvhResourceNotFoundError {
      return [];
    } on OvhNotGrantedCallError {
      return [];
    } catch (_) {
      rethrow;
    }

    final domains = <Map<String, dynamic>>[];

    for (final name in domainNames) {
      final domainName = name.toString();
      try {
        final detail = await _client.get('/domain/${Uri.encodeComponent(domainName)}') as Map<String, dynamic>;

        // Extract nameservers from the domain detail or the nameservers sub-endpoint
        List<String> nameservers = [];
        if (detail['nameservers'] is List) {
          nameservers = (detail['nameservers'] as List).map((e) => e.toString()).toList();
        }
        if (nameservers.isEmpty) {
          try {
            final ns = await _client.get('/domain/${Uri.encodeComponent(domainName)}/nameservers') as List<dynamic>;
            nameservers = ns.map((e) {
              if (e is Map) return (e['host'] ?? e['name'] ?? e.toString()).toString();
              return e.toString();
            }).toList();
          } catch (_) {}
        }

        domains.add({
          'name': domainName,
          'nameservers': nameservers,
          'expiration': detail['expiration'] ?? detail['expiryDate'],
          'status': detail['status'] ?? 'unknown',
          'raw': detail,
        });
      } on OvhResourceNotFoundError {
        domains.add({'name': domainName, 'nameservers': <String>[], 'status': 'unknown'});
      } on OvhNotGrantedCallError {
        domains.add({'name': domainName, 'nameservers': <String>[], 'status': 'unknown'});
      } catch (e) {
        print('[OVH] Domain detail fetch failed for $domainName: $e');
        domains.add({'name': domainName, 'nameservers': <String>[], 'status': 'unknown'});
      }
    }

    return domains;
  }

  // ── DNS Records ───────────────────────────────────────────────────────

  /// List DNS records for an OVH domain zone.
  ///
  /// Returns a list of raw record maps from the OVH API.
  Future<List<Map<String, dynamic>>> listDnsRecords(String domainName) async {
    List<dynamic> recordIds;
    try {
      recordIds = await _client.get('/domain/zone/${Uri.encodeComponent(domainName)}/record') as List<dynamic>;
    } on OvhResourceNotFoundError {
      return [];
    } on OvhNotGrantedCallError {
      return [];
    } catch (_) {
      rethrow;
    }

    final records = <Map<String, dynamic>>[];
    for (final id in recordIds) {
      try {
        final detail = await _client.get('/domain/zone/${Uri.encodeComponent(domainName)}/record/$id') as Map<String, dynamic>;
        records.add(detail);
      } catch (_) {
        // Skip individual record failures
      }
    }

    return records;
  }

  // ── Service / Monitoring Details ───────────────────────────────────────

  /// Get detailed service info for a dedicated server.
  /// Includes monitoring config, boot mode, rack, reverse DNS, etc.
  Future<Map<String, dynamic>> getDedicatedServerService(String serverName) async {
    try {
      return await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/serviceInfos') as Map<String, dynamic>;
    } on OvhResourceNotFoundError {
      return {};
    }
  }

  /// Get the service (IP) details for a dedicated server.
  /// Returns list of IP blocks with type, routing, etc.
  Future<List<Map<String, dynamic>>> getDedicatedServerIpDetails(String serverName) async {
    try {
      // Get IP blocks
      final ipBlocks = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/ips') as List<dynamic>;
      final result = <Map<String, dynamic>>[];
      for (final block in ipBlocks) {
        final blockStr = block.toString();
        try {
          final detail = await _client.get('/ip/${Uri.encodeComponent(blockStr)}') as Map<String, dynamic>;
          result.add(detail);
        } catch (_) {
          result.add({'ip': blockStr});
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Get monitoring status for a dedicated server.
  Future<Map<String, dynamic>> getDedicatedServerMonitoring(String serverName) async {
    try {
      return await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/specifications/monitoring') as Map<String, dynamic>;
    } on OvhResourceNotFoundError {
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Get boot mode for a dedicated server.
  /// Get VPS monitoring/service details.
  Future<Map<String, dynamic>> getVpsService(String vpsName) async {
    try {
      return await _client.get('/vps/${Uri.encodeComponent(vpsName)}/serviceInfos') as Map<String, dynamic>;
    } on OvhResourceNotFoundError {
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Get VPS configuration details (autoBackup, snapshot, etc.).
  Future<Map<String, dynamic>> getVpsConfiguration(String vpsName) async {
    try {
      return await _client.get('/vps/${Uri.encodeComponent(vpsName)}/configuration') as Map<String, dynamic>;
    } on OvhResourceNotFoundError {
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Get OVH Cloud instance type/flavor details (vCPUs, RAM, disk) for a
  /// specific instance. Returns the full flavor map from the API.
  Future<Map<String, dynamic>> getCloudInstanceFlavor(String projectId, String flavorId) async {
    try {
      return await _client.get('/cloud/project/${Uri.encodeComponent(projectId)}/flavor/${Uri.encodeComponent(flavorId)}') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Get OVH VPS specification details (vCPUs, RAM, disk, bandwidth).
  Future<Map<String, dynamic>> getVpsSpecification(String vpsName) async {
    try {
      return await _client.get('/vps/${Uri.encodeComponent(vpsName)}/specifications') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Get OVH Dedicated server hardware specifications.
  Future<Map<String, dynamic>> getDedicatedServerSpecifications(String serverName) async {
    try {
      return await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/specifications/hardware') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ── VPS Monitoring & Metrics ───────────────────────────────────────────

  /// Get real-time VPS statistics (CPU, RAM, disk I/O, network).
  ///
  /// Returns a map with keys like:
  /// - `cpu`: {"used": 0.45, "total": 1.0}  (percentage 0–1)
  /// - `memory`: {"used": 1.2, "total": 4.0}  (GB)
  /// - `disk`: [{"id": ..., "used": 8.5, "total": 20.0}]  (GB)
  /// - `network`: {"rx": 1234, "tx": 567}  (bytes/s)
  ///
  /// Only available when the VPS is running.
  Future<Map<String, dynamic>> getVpsStatistics(String vpsName) async {
    try {
      return await _client.get('/vps/${Uri.encodeComponent(vpsName)}/statistics') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Get VPS disk monitoring data (IOPS, throughput, usage).
  ///
  /// First lists disks, then fetches monitoring for each.
  Future<List<Map<String, dynamic>>> getVpsDiskMonitoring(String vpsName) async {
    try {
      final disks = await _client.get('/vps/${Uri.encodeComponent(vpsName)}/disks') as List<dynamic>;
      final results = <Map<String, dynamic>>[];
      for (final diskId in disks) {
        final id = diskId is Map ? (diskId['id'] ?? diskId['name'] ?? '').toString() : diskId.toString();
        if (id.isEmpty) continue;
        try {
          final monitoring = await _client.get('/vps/${Uri.encodeComponent(vpsName)}/disks/${Uri.encodeComponent(id)}/monitoring') as Map<String, dynamic>;
          results.add({'id': id, ...monitoring});
        } catch (_) {
          // Skip individual disk failures
        }
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Get VPS disk usage (used/total/percentage) for each disk.
  Future<List<Map<String, dynamic>>> getVpsDiskUsage(String vpsName) async {
    try {
      final disks = await _client.get('/vps/${Uri.encodeComponent(vpsName)}/disks') as List<dynamic>;
      final results = <Map<String, dynamic>>[];
      for (final diskId in disks) {
        final id = diskId is Map ? (diskId['id'] ?? diskId['name'] ?? '').toString() : diskId.toString();
        if (id.isEmpty) continue;
        try {
          final usage = await _client.get('/vps/${Uri.encodeComponent(vpsName)}/disks/${Uri.encodeComponent(id)}/use') as Map<String, dynamic>;
          results.add({'id': id, ...usage});
        } catch (_) {}
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Get VPS tasks (ongoing operations like reboot, reinstall, snapshot).
  Future<List<Map<String, dynamic>>> getVpsTasks(String vpsName) async {
    try {
      final taskIds = await _client.get('/vps/${Uri.encodeComponent(vpsName)}/tasks') as List<dynamic>;
      final results = <Map<String, dynamic>>[];
      for (final taskId in taskIds) {
        final id = taskId is Map ? (taskId['taskId'] ?? taskId['id'] ?? '').toString() : taskId.toString();
        if (id.isEmpty) continue;
        try {
          final detail = await _client.get('/vps/${Uri.encodeComponent(vpsName)}/tasks/$id') as Map<String, dynamic>;
          results.add(detail);
        } catch (_) {}
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  // ── Dedicated Server Monitoring & Metrics ──────────────────────────────

  /// Get dedicated server MRTG traffic data (network bandwidth graphs).
  ///
  /// Returns traffic data suitable for charting.
  Future<Map<String, dynamic>> getDedicatedServerMrtg(String serverName, {String? period}) async {
    try {
      final params = <String, String>{};
      if (period != null) params['period'] = period;
      return await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/mrtg', queryParams: params) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Get per-NIC MRTG traffic data.
  Future<Map<String, dynamic>> getDedicatedServerNicMrtg(String serverName, String mac, {String? period}) async {
    try {
      final params = <String, String>{};
      if (period != null) params['period'] = period;
      return await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/networkInterfaceController/${Uri.encodeComponent(mac)}/mrtg', queryParams: params) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Get dedicated server bandwidth burst status.
  Future<Map<String, dynamic>> getDedicatedServerBurst(String serverName) async {
    try {
      return await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/burst') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Get dedicated server network interface controllers.
  Future<List<Map<String, dynamic>>> getDedicatedServerNics(String serverName) async {
    try {
      final macs = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/networkInterfaceController') as List<dynamic>;
      final results = <Map<String, dynamic>>[];
      for (final mac in macs) {
        final macStr = mac.toString();
        try {
          final detail = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/networkInterfaceController/${Uri.encodeComponent(macStr)}') as Map<String, dynamic>;
          results.add(detail);
        } catch (_) {}
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Get dedicated server tasks (ongoing operations).
  Future<List<Map<String, dynamic>>> getDedicatedServerTasks(String serverName) async {
    try {
      final taskIds = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/task') as List<dynamic>;
      final results = <Map<String, dynamic>>[];
      for (final taskId in taskIds) {
        final id = taskId is Map ? (taskId['taskId'] ?? taskId['id'] ?? '').toString() : taskId.toString();
        if (id.isEmpty) continue;
        try {
          final detail = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/task/$id') as Map<String, dynamic>;
          results.add(detail);
        } catch (_) {}
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Get dedicated server interventions (hardware actions).
  Future<List<Map<String, dynamic>>> getDedicatedServerInterventions(String serverName) async {
    try {
      final ids = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/intervention') as List<dynamic>;
      final results = <Map<String, dynamic>>[];
      for (final id in ids) {
        final intId = id is Map ? (id['interventionId'] ?? id['id'] ?? '').toString() : id.toString();
        if (intId.isEmpty) continue;
        try {
          final detail = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/intervention/$intId') as Map<String, dynamic>;
          results.add(detail);
        } catch (_) {}
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Get ongoing interventions for a dedicated server.
  Future<List<Map<String, dynamic>>> getDedicatedServerOngoingInterventions(String serverName) async {
    try {
      final ids = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/ongoing') as List<dynamic>;
      return ids.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  /// Get planned interventions for a dedicated server.
  Future<List<Map<String, dynamic>>> getDedicatedServerPlannedInterventions(String serverName) async {
    try {
      final ids = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/plannedIntervention') as List<dynamic>;
      final results = <Map<String, dynamic>>[];
      for (final id in ids) {
        final intId = id is Map ? (id['interventionId'] ?? id['id'] ?? '').toString() : id.toString();
        if (intId.isEmpty) continue;
        try {
          final detail = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/plannedIntervention/$intId') as Map<String, dynamic>;
          results.add(detail);
        } catch (_) {}
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Get boot mode details for a dedicated server.
  Future<Map<String, dynamic>> getDedicatedServerBoot(String serverName) async {
    try {
      final bootId = await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/boot');
      // bootId could be an int or a list; if int, fetch details
      if (bootId is int) {
        return await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/boot/$bootId') as Map<String, dynamic>;
      } else if (bootId is List && bootId.isNotEmpty) {
        final id = bootId.first.toString();
        return await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/boot/${Uri.encodeComponent(id)}') as Map<String, dynamic>;
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Get IPMI/KVM access details for a dedicated server.
  Future<Map<String, dynamic>> getDedicatedServerIpmiAccess(String serverName) async {
    try {
      return await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/features/ipmi/access') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Get network configuration for a dedicated server.
  Future<Map<String, dynamic>> getDedicatedServerNetworking(String serverName) async {
    try {
      return await _client.get('/dedicated/server/${Uri.encodeComponent(serverName)}/networking') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Reboot a dedicated server.
  Future<bool> rebootDedicatedServer(String serverName) async {
    try {
      await _client.post('/dedicated/server/${Uri.encodeComponent(serverName)}/reboot', body: {});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reboot a VPS.
  Future<bool> rebootVps(String vpsName) async {
    try {
      await _client.post('/vps/${Uri.encodeComponent(vpsName)}/reboot', body: {});
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Cloud Project Usage ──────────────────────────────────────────────

  /// Get current cloud project resource usage.
  Future<Map<String, dynamic>> getCloudProjectUsage(String projectId) async {
    try {
      return await _client.get('/cloud/project/${Uri.encodeComponent(projectId)}/usage/current') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Get cloud project usage forecast.
  Future<Map<String, dynamic>> getCloudProjectUsageForecast(String projectId) async {
    try {
      return await _client.get('/cloud/project/${Uri.encodeComponent(projectId)}/usage/forecast') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Get cloud project quota.
  Future<Map<String, dynamic>> getCloudProjectQuota(String projectId) async {
    try {
      return await _client.get('/cloud/project/${Uri.encodeComponent(projectId)}/quota') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Get cloud project alerts.
  Future<List<Map<String, dynamic>>> getCloudProjectAlerts(String projectId) async {
    try {
      final ids = await _client.get('/cloud/project/${Uri.encodeComponent(projectId)}/alerting') as List<dynamic>;
      final results = <Map<String, dynamic>>[];
      for (final id in ids) {
        final alertId = id.toString();
        try {
          final detail = await _client.get('/cloud/project/${Uri.encodeComponent(projectId)}/alerting/${Uri.encodeComponent(alertId)}') as Map<String, dynamic>;
          results.add(detail);
        } catch (_) {}
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Extract IP addresses from various OVH API response formats.
  ///
  /// The `ipAddresses` field can be:
  /// - A list of strings (e.g. ["1.2.3.4", "5.6.7.8"])
  /// - A list of objects with an `ip` key (e.g. [{"ip": "1.2.3.4", "type": "public"}])
  /// - A list of mixed formats
  static List<String> _extractIpAddresses(dynamic ipField) {
    if (ipField is! List) return [];
    return ipField.map((entry) {
      if (entry is Map) {
        return (entry['ip'] ?? entry['value'] ?? '').toString();
      }
      return entry.toString();
    }).where((ip) => ip.isNotEmpty).toList();
  }
}
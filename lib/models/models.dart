/** ClarityMelt data models.
 *
 * These mirror the API response types from the original web app.
 */

class MachineInfo {
  final String id;
  final String name;
  final String? alias; // User-assigned friendly name
  final String provider; // "ovh", "ovh-dedicated", "ovh-vps", "hetzner"
  final String status;
  final List<String> ipAddresses;
  final String region;
  final String? flavor;
  final String? image;
  final String createdAt;
  // Hardware specs (may be null for some providers)
  final int? vcpus;
  final int? memoryMB;
  final int? diskGB;
  final String? bandwidth;
  final String? os;
  final String? commercialRange;
  final Map<String, dynamic>? raw;
  // Uncloud association (persisted in DB)
  final String? uncloudMachineId;
  final String? uncloudContext;
  // Cost (monthly, in the provider's currency)
  final double? monthlyCost;
  final String? currency;

  MachineInfo({
    required this.id,
    required this.name,
    required this.provider,
    required this.status,
    required this.ipAddresses,
    required this.region,
    this.alias,
    this.flavor,
    this.image,
    this.createdAt = '',
    this.vcpus,
    this.memoryMB,
    this.diskGB,
    this.bandwidth,
    this.os,
    this.commercialRange,
    this.raw,
    this.uncloudMachineId,
    this.uncloudContext,
    this.monthlyCost,
    this.currency,
  });

  /// Create a copy with optional field overrides.
  MachineInfo copyWith({
    String? id,
    String? name,
    String? alias,
    String? provider,
    String? status,
    List<String>? ipAddresses,
    String? region,
    String? flavor,
    String? image,
    String? createdAt,
    int? vcpus,
    int? memoryMB,
    int? diskGB,
    String? bandwidth,
    String? os,
    String? commercialRange,
    Map<String, dynamic>? raw,
    String? uncloudMachineId,
    String? uncloudContext,
    double? monthlyCost,
    String? currency,
  }) {
    return MachineInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      alias: alias ?? this.alias,
      provider: provider ?? this.provider,
      status: status ?? this.status,
      ipAddresses: ipAddresses ?? this.ipAddresses,
      region: region ?? this.region,
      flavor: flavor ?? this.flavor,
      image: image ?? this.image,
      createdAt: createdAt ?? this.createdAt,
      vcpus: vcpus ?? this.vcpus,
      memoryMB: memoryMB ?? this.memoryMB,
      diskGB: diskGB ?? this.diskGB,
      bandwidth: bandwidth ?? this.bandwidth,
      os: os ?? this.os,
      commercialRange: commercialRange ?? this.commercialRange,
      raw: raw ?? this.raw,
      uncloudMachineId: uncloudMachineId ?? this.uncloudMachineId,
      uncloudContext: uncloudContext ?? this.uncloudContext,
      monthlyCost: monthlyCost ?? this.monthlyCost,
      currency: currency ?? this.currency,
    );
  }

  /// Display name: alias if set, otherwise the provider name.
  String get displayName => alias != null && alias!.isNotEmpty ? alias! : name;

  String get providerLabel {
    switch (provider) {
      case 'ovh':
        return 'OVH';
      case 'ovh-dedicated':
        return 'OVH Dedicated';
      case 'ovh-vps':
        return 'OVH VPS';
      case 'hetzner':
        return 'Hetzner';
      default:
        return provider.toUpperCase();
    }
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'running':
      case 'active':
        return 'Running';
      case 'stopped':
      case 'off':
        return 'Stopped';
      default:
        return status;
    }
  }

  bool get isRunning =>
      status.toLowerCase() == 'running' || status.toLowerCase() == 'active';

  /// Human-readable label for the type of hosting service.
  /// e.g. "OVH VPS", "OVH Dedicated", "OVH Cloud", "Hetzner Cloud"
  String get serviceTypeLabel {
    switch (provider) {
      case 'ovh':
        return 'OVH Cloud Instance';
      case 'ovh-vps':
        return 'OVH VPS';
      case 'ovh-dedicated':
        return 'OVH Dedicated';
      case 'hetzner':
        return 'Hetzner Cloud';
      default:
        return providerLabel;
    }
  }

  /// Short one-line specs summary, e.g. "2 vCPU · 4 GB · 40 GB SSD"
  String get specsSummary {
    final parts = <String>[];
    if (vcpus != null) parts.add('$vcpus vCPU${vcpus! > 1 ? 's' : ''}');
    if (memoryMB != null) {
      if (memoryMB! >= 1024) {
        parts.add('${(memoryMB! / 1024).toStringAsFixed(memoryMB! % 1024 == 0 ? 0 : 1)} GB RAM');
      } else {
        parts.add('$memoryMB MB RAM');
      }
    }
    if (diskGB != null) parts.add('$diskGB GB');
    return parts.join(' · ');
  }

  /// Whether this machine has any hardware spec data.
  bool get hasSpecs =>
      vcpus != null || memoryMB != null || diskGB != null || bandwidth != null;

  /// Machine type tag derived from provider + specs.
  /// Returns a short descriptive label like "VPS", "Dedicated", "Cloud Instance",
  /// "Hetzner CX", etc. based on provider and flavor/type info.
  String get machineTypeTag {
    switch (provider) {
      case 'ovh-vps':
        if (flavor != null && flavor!.isNotEmpty) return 'VPS ($flavor)';
        return 'VPS';
      case 'ovh-dedicated':
        if (commercialRange != null && commercialRange!.isNotEmpty) return 'Dedicated ($commercialRange)';
        return 'Dedicated';
      case 'ovh':
        if (flavor != null && flavor!.isNotEmpty) return 'Cloud ($flavor)';
        return 'Cloud Instance';
      case 'hetzner':
        if (flavor != null && flavor!.isNotEmpty) return 'Hetzner ($flavor)';
        return 'Hetzner Cloud';
      default:
        return providerLabel;
    }
  }

  /// Short machine type tag without parenthetical details.
  String get machineTypeShort {
    switch (provider) {
      case 'ovh-vps':
        return 'VPS';
      case 'ovh-dedicated':
        return 'Dedicated';
      case 'ovh':
        return 'Cloud';
      case 'hetzner':
        return 'Hetzner';
      default:
        return providerLabel;
    }
  }

  /// Formatted monthly cost string, e.g. "€4.50/mo" or "$3.99/mo".
  String get monthlyCostLabel {
    if (monthlyCost == null) return '';
    final cur = currency ?? 'EUR';
    final symbol = cur == 'USD' ? '\$' : cur == 'GBP' ? '£' : '€';
    return '$symbol${monthlyCost!.toStringAsFixed(monthlyCost! == monthlyCost!.roundToDouble() ? 0 : 2)}/mo';
  }
}

class DomainInfo {
  final String name;
  final String provider; // "namecheap", "cloudflare", "ovh", "external"
  final List<String> nameservers;
  final String? cfZoneId;
  final String? cfStatus;
  final String? expires;
  final String? dnsProvider; // Who manages DNS records: "cloudflare", "ovh", "namecheap"
  /// Cloudflare-assigned nameservers for this zone (e.g. ["bob.ns.cloudflare.com", "zoe.ns.cloudflare.com"])
  final List<String> cfNameservers;
  final Map<String, dynamic>? raw;

  DomainInfo({
    required this.name,
    required this.provider,
    required this.nameservers,
    this.cfZoneId,
    this.cfStatus,
    this.expires,
    this.dnsProvider,
    this.cfNameservers = const [],
    this.raw,
  });

  /// Whether DNS records can be viewed/managed for this domain.
  bool get canManageDns => dnsProvider != null || cfZoneId != null;

  /// Which provider to use for DNS operations.
  String get effectiveDnsProvider {
    if (cfZoneId != null) return 'cloudflare';
    if (dnsProvider != null) return dnsProvider!;
    return provider; // fallback to domain registrar
  }

  /// The identifier for DNS operations (zone ID for CF, domain name for others).
  String get dnsZoneId => cfZoneId ?? name;

  /// Whether the domain's nameservers are correctly pointing to the DNS provider.
  /// For Cloudflare-managed domains, checks if any nameserver ends with cloudflare.com
  /// or matches the assigned CF nameservers.
  bool get nameserverMismatch {
    if (effectiveDnsProvider == 'cloudflare' && cfZoneId != null) {
      if (nameservers.isEmpty) return true; // No nameservers set at all
      // Check if any nameserver looks like a Cloudflare NS
      final hasCloudflareNs = nameservers.any((ns) => ns.toLowerCase().endsWith('.ns.cloudflare.com'));
      if (hasCloudflareNs) return false;
      // Also check if the registrar NS matches any of the CF-assigned ones
      if (cfNameservers.isNotEmpty) {
        final registrarLower = nameservers.map((ns) => ns.toLowerCase()).toSet();
        final cfLower = cfNameservers.map((ns) => ns.toLowerCase()).toSet();
        return !registrarLower.any((ns) => cfLower.contains(ns));
      }
      return true; // No Cloudflare NS found
    }
    return false;
  }

  String get providerLabel {
    switch (provider) {
      case 'namecheap':
        return 'Namecheap';
      case 'cloudflare':
        return 'Cloudflare';
      case 'ovh':
        return 'OVH';
      default:
        return provider.toUpperCase();
    }
  }
}

class DnsRecordInfo {
  final String id;
  final String type;
  final String name;
  final String content;
  final int ttl;
  final bool proxied;
  final int? priority;
  final String zoneId;
  final String zoneName;
  final String provider; // "cloudflare", "ovh", "namecheap"

  DnsRecordInfo({
    required this.id,
    required this.type,
    required this.name,
    required this.content,
    required this.ttl,
    this.proxied = false,
    this.priority,
    required this.zoneId,
    required this.zoneName,
    this.provider = 'cloudflare',
  });

  String get ttlLabel => ttl == 1 ? 'Auto' : ttl.toString();

  String get providerLabel {
    switch (provider) {
      case 'cloudflare':
        return 'Cloudflare';
      case 'ovh':
        return 'OVH';
      case 'namecheap':
        return 'Namecheap';
      default:
        return provider.toUpperCase();
    }
  }
}

/// Named OVH endpoint mappings for display.
const kOvhEndpointLabels = <String, String>{
  'ovh-eu': 'OVH Europe (eu.api.ovh.com)',
  'ovh-us': 'OVH US (api.us.ovhcloud.com)',
  'ovh-ca': 'OVH Canada (ca.api.ovh.com)',
  'kimsufi-eu': 'Kimsufi Europe',
  'kimsufi-ca': 'Kimsufi Canada',
  'soyoustart-eu': 'SoYouStart Europe',
  'soyoustart-ca': 'SoYouStart Canada',
};

class ProviderCredentialInfo {
  final String id;
  final String provider;
  final String label;
  final Map<String, String> maskedFields;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// The OVH endpoint key (e.g. 'ovh-eu', 'ovh-us'), null for non-OVH providers.
  final String? ovhEndpoint;

  ProviderCredentialInfo({
    required this.id,
    required this.provider,
    required this.label,
    required this.maskedFields,
    required this.createdAt,
    required this.updatedAt,
    this.ovhEndpoint,
  });

  String get providerLabel {
    switch (provider) {
      case 'ovh':
        return 'OVH Cloud';
      case 'hetzner':
        return 'Hetzner Cloud';
      case 'namecheap':
        return 'Namecheap';
      case 'cloudflare':
        return 'Cloudflare';
      default:
        return provider.toUpperCase();
    }
  }

  /// Human-readable region label for OVH credentials.
  String get ovhEndpointLabel {
    if (ovhEndpoint == null) return '';
    return kOvhEndpointLabels[ovhEndpoint!] ?? ovhEndpoint!;
  }
}

class ProviderStatus {
  final bool db;
  final bool env;
  final String source; // "db", "env", "none"

  ProviderStatus({
    required this.db,
    required this.env,
    required this.source,
  });
}

class ProvisionResult {
  final Map<String, dynamic> zone;
  final Map<String, dynamic> dnsRecord;
  final bool nameserversUpdated;

  ProvisionResult({
    required this.zone,
    required this.dnsRecord,
    this.nameserversUpdated = false,
  });
}
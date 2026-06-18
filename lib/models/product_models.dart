/// Product and resource models for ClarityMelt.
///
/// Products group infrastructure resources (machines, domains, DNS zones,
/// Cloudflare Workers/Pages) into logical deployed services.

/// A product groups related infrastructure resources.
class ProductInfo {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProductResourceInfo> resources;

  ProductInfo({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.resources = const [],
  });
}

/// A resource linked to a product.
class ProductResourceInfo {
  final String id;
  final String productId;
  final String resourceType; // "machine", "domain", "dns_zone", "cloudflare_worker", "cloudflare_page"
  final String resourceId;
  final String role; // "primary", "secondary", "cdn", etc.
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  ProductResourceInfo({
    required this.id,
    required this.productId,
    required this.resourceType,
    required this.resourceId,
    this.role = 'primary',
    this.metadata = const {},
    required this.createdAt,
  });

  String get resourceTypeLabel {
    switch (resourceType) {
      case 'machine':
        return 'Machine';
      case 'domain':
        return 'Domain';
      case 'dns_zone':
        return 'DNS Zone';
      case 'cloudflare_worker':
        return 'Worker';
      case 'cloudflare_page':
        return 'Pages';
      default:
        return resourceType;
    }
  }
}

/// Cloudflare Worker deployment info.
class CloudflareWorkerInfo {
  final String id;
  final String name;
  final String? script;
  final String? status;
  final DateTime? createdOn;
  final DateTime? modifiedOn;
  final Map<String, dynamic>? raw;

  CloudflareWorkerInfo({
    required this.id,
    required this.name,
    this.script,
    this.status,
    this.createdOn,
    this.modifiedOn,
    this.raw,
  });
}

/// Cloudflare Pages project info.
class CloudflarePagesInfo {
  final String id;
  final String name;
  final String? subdomain;
  final String? productionBranch;
  final DateTime? createdOn;
  final Map<String, dynamic>? raw;

  CloudflarePagesInfo({
    required this.id,
    required this.name,
    this.subdomain,
    this.productionBranch,
    this.createdOn,
    this.raw,
  });
}

/// OVH monitoring/service details for a dedicated server or VPS.
class OvhMonitoringInfo {
  final String? state;
  final String? monitoringPeriod;
  final String? sslUri;
  final String? ipv4;
  final String? ipv6;
  final String? datacenter;
  final String? os;
  final String? commercialRange;
  final String? rack;
  final String? reverse;
  final String? bootId;
  final int? monitoringId;
  final bool? professional;
  final Map<String, dynamic>? raw;

  OvhMonitoringInfo({
    this.state,
    this.monitoringPeriod,
    this.sslUri,
    this.ipv4,
    this.ipv6,
    this.datacenter,
    this.os,
    this.commercialRange,
    this.rack,
    this.reverse,
    this.bootId,
    this.monitoringId,
    this.professional,
    this.raw,
  });
}

/// Uncloud container/machine configuration for provisioning.
class UncloudContainerSpec {
  final String name;
  final String image;
  final List<String> envVars;
  final List<int> ports;
  final int? memoryMB;
  final int? cpuCores;
  final String? domain;
  final String? dnsZoneId;
  final String? machineId;

  UncloudContainerSpec({
    required this.name,
    required this.image,
    this.envVars = const [],
    this.ports = const [],
    this.memoryMB,
    this.cpuCores,
    this.domain,
    this.dnsZoneId,
    this.machineId,
  });
}
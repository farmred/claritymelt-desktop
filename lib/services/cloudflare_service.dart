import 'dart:convert';
import 'package:http/http.dart' as http;

/// Cloudflare API client for DNS management.
/// Docs: https://developers.cloudflare.com/api/

class CloudflareService {
  final String apiToken;
  final String? accountId;
  final String _baseUrl = 'https://api.cloudflare.com/client/v4';

  CloudflareService({required this.apiToken, this.accountId});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiToken',
        'Content-Type': 'application/json',
      };

  /// List all zones in the account.
  Future<List<Map<String, dynamic>>> listZones() async {
    final allZones = <Map<String, dynamic>>[];
    var page = 1;
    var hasMore = true;

    while (hasMore) {
      final res = await http.get(
        Uri.parse('$_baseUrl/zones?page=$page&per_page=50'),
        headers: _headers,
      );
      if (res.statusCode != 200) {
        throw Exception('Cloudflare listZones failed: ${res.statusCode} ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['result'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final z in results) {
        allZones.add({
          'id': z['id'],
          'name': z['name'],
          'status': z['status'],
          'nameservers': z['name_servers'] ?? [],
        });
      }
      final resultInfo = data['result_info'] as Map<String, dynamic>?;
      final totalPages = resultInfo?['total_pages'] ?? 1;
      hasMore = page < totalPages;
      page++;
    }

    return allZones;
  }

  /// Get a specific zone by ID.
  Future<Map<String, dynamic>> getZone(String zoneId) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/zones/$zoneId'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Cloudflare getZone failed: ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final z = data['result'] as Map<String, dynamic>;
    return {
      'id': z['id'],
      'name': z['name'],
      'status': z['status'],
      'nameservers': z['name_servers'] ?? [],
    };
  }

  /// Find a zone by domain name.
  Future<Map<String, dynamic>?> findZoneByName(String domain) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/zones?name=$domain'),
      headers: _headers,
    );
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (data['result'] as List?) ?? [];
    if (results.isEmpty) return null;
    final z = results[0] as Map<String, dynamic>;
    return {
      'id': z['id'],
      'name': z['name'],
      'status': z['status'],
      'nameservers': z['name_servers'] ?? [],
    };
  }

  /// Create a new zone.
  Future<Map<String, dynamic>> createZone(String domain) async {
    final body = <String, dynamic>{
      'name': domain,
      'type': 'full',
    };
    if (accountId != null) {
      body['account'] = {'id': accountId};
    }
    final res = await http.post(
      Uri.parse('$_baseUrl/zones'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('Cloudflare createZone failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final z = data['result'] as Map<String, dynamic>;
    return {
      'id': z['id'],
      'name': z['name'],
      'status': z['status'],
      'nameservers': z['name_servers'] ?? [],
    };
  }

  /// List DNS records for a zone.
  Future<List<Map<String, dynamic>>> listDnsRecords(String zoneId) async {
    final allRecords = <Map<String, dynamic>>[];
    var page = 1;
    var hasMore = true;

    while (hasMore) {
      final res = await http.get(
        Uri.parse('$_baseUrl/zones/$zoneId/dns_records?page=$page&per_page=100'),
        headers: _headers,
      );
      if (res.statusCode != 200) {
        throw Exception('Cloudflare listDnsRecords failed: ${res.statusCode}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['result'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in results) {
        allRecords.add({
          'id': r['id'],
          'type': r['type'],
          'name': r['name'],
          'content': r['content'],
          'ttl': r['ttl'],
          'proxied': r['proxied'] ?? false,
          'priority': r['priority'],
        });
      }
      final resultInfo = data['result_info'] as Map<String, dynamic>?;
      final totalPages = resultInfo?['total_pages'] ?? 1;
      hasMore = page < totalPages;
      page++;
    }

    return allRecords;
  }

  /// Create a DNS record.
  Future<Map<String, dynamic>> createDnsRecord(
    String zoneId, {
    required String type,
    required String name,
    required String content,
    int? ttl,
    bool? proxied,
    int? priority,
  }) async {
    final body = <String, dynamic>{
      'type': type,
      'name': name,
      'content': content,
      'ttl': ttl ?? 1,
      'proxied': proxied ?? false,
    };
    if (priority != null) body['priority'] = priority;

    final res = await http.post(
      Uri.parse('$_baseUrl/zones/$zoneId/dns_records'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('Cloudflare createDnsRecord failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final r = data['result'] as Map<String, dynamic>;
    return {
      'id': r['id'],
      'type': r['type'],
      'name': r['name'],
      'content': r['content'],
      'ttl': r['ttl'],
      'proxied': r['proxied'] ?? false,
    };
  }

  /// Update a DNS record.
  Future<Map<String, dynamic>> updateDnsRecord(
    String zoneId,
    String recordId, {
    required String type,
    required String name,
    required String content,
    int? ttl,
    bool? proxied,
    int? priority,
  }) async {
    final body = <String, dynamic>{
      'type': type,
      'name': name,
      'content': content,
      'ttl': ttl ?? 1,
      'proxied': proxied ?? false,
    };
    if (priority != null) body['priority'] = priority;

    final res = await http.put(
      Uri.parse('$_baseUrl/zones/$zoneId/dns_records/$recordId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('Cloudflare updateDnsRecord failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final r = data['result'] as Map<String, dynamic>;
    return {
      'id': r['id'],
      'type': r['type'],
      'name': r['name'],
      'content': r['content'],
      'ttl': r['ttl'],
      'proxied': r['proxied'] ?? false,
    };
  }

  /// Delete a DNS record.
  Future<bool> deleteDnsRecord(String zoneId, String recordId) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/zones/$zoneId/dns_records/$recordId'),
      headers: _headers,
    );
    return res.statusCode == 200;
  }

  // ── Workers ──────────────────────────────────────────────────────────────

  /// List all Cloudflare Workers scripts.
  Future<List<Map<String, dynamic>>> listWorkers() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/workers/scripts'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      return []; // Workers may not be enabled on all accounts
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (data['result'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return results.map((w) => {
      'id': w['id'],
      'name': w['name'] ?? w['id'],
      'createdOn': w['created_on'] ?? w['createdOn'],
      'modifiedOn': w['modified_on'] ?? w['modifiedOn'],
      'status': w['status'] ?? 'active',
      'raw': w,
    }).toList();
  }

  // ── Pages ──────────────────────────────────────────────────────────────

  /// List all Cloudflare Pages projects.
  Future<List<Map<String, dynamic>>> listPagesProjects() async {
    final allProjects = <Map<String, dynamic>>[];
    var page = 1;
    var hasMore = true;

    while (hasMore) {
      final res = await http.get(
        Uri.parse('$_baseUrl/accounts/${accountId ?? ''}/pages/projects?page=$page&per_page=50'),
        headers: _headers,
      );
      if (res.statusCode != 200) {
        return allProjects; // Pages may not be enabled
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['result'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final p in results) {
        allProjects.add({
          'id': p['id'],
          'name': p['name'],
          'subdomain': p['subdomain'],
          'productionBranch': p['production_branch'],
          'createdOn': p['created_on'],
          'raw': p,
        });
      }
      final resultInfo = data['result_info'] as Map<String, dynamic>?;
      final totalPages = resultInfo?['total_pages'] ?? 1;
      hasMore = page < totalPages;
      page++;
    }

    return allProjects;
  }
}
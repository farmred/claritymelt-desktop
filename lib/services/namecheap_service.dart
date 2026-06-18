import 'package:http/http.dart' as http;

/// Namecheap API client for domain management.
/// Docs: https://www.namecheap.com/support/api/intro/

class NamecheapService {
  final String apiUser;
  final String apiKey;
  final String clientIp;
  final bool sandbox;
  final String _baseUrl;

  NamecheapService({
    required this.apiUser,
    required this.apiKey,
    required this.clientIp,
    this.sandbox = false,
  }) : _baseUrl = sandbox
            ? 'https://api.sandbox.namecheap.com/xml.response'
            : 'https://api.namecheap.com/xml.response';

  String _buildParams(String command, [Map<String, String>? extra]) {
    final params = <String, String>{
      'ApiUser': apiUser,
      'ApiKey': apiKey,
      'UserName': apiUser,
      'ClientIp': clientIp,
      'Command': command,
    };
    if (extra != null) params.addAll(extra);
    return Uri(queryParameters: params).query;
  }

  /// List all domains in the account.
  Future<List<Map<String, dynamic>>> listDomains() async {
    final allDomains = <Map<String, dynamic>>[];
    var page = 1;
    var hasMore = true;

    while (hasMore) {
      final params = _buildParams('namecheap.domains.getList', {
        'Page': page.toString(),
        'PageSize': '100',
      });
      final res = await http.get(Uri.parse('$_baseUrl?$params'));

      if (res.statusCode != 200) {
        throw Exception('Namecheap listDomains failed: ${res.statusCode}');
      }

      final xml = res.body;
      final domains = <Map<String, dynamic>>[];
      final domainRegex = RegExp(r'<Domain[^>]*>([\s\S]*?)<\/Domain>', dotAll: true);
      for (final match in domainRegex.allMatches(xml)) {
        final innerXml = match.group(0)!;
        final nameMatch = RegExp(r'Name="([^"]+)"').firstMatch(innerXml);
        final expiresMatch = RegExp(r'Expires="([^"]*)"', caseSensitive: false).firstMatch(innerXml);
        if (nameMatch == null) continue;

        domains.add({
          'name': nameMatch[1] ?? '',
          'expires': expiresMatch?[1] ?? '',
        });
      }

      allDomains.addAll(domains);

      final totalItemsMatch = RegExp(r'TotalItems="(\d+)"').firstMatch(xml);
      final pageSizeMatch = RegExp(r'PageSize="(\d+)"').firstMatch(xml);
      final totalItems = int.tryParse(totalItemsMatch?[1] ?? '0') ?? 0;
      final pageSize = int.tryParse(pageSizeMatch?[1] ?? '100') ?? 100;
      hasMore = page * pageSize < totalItems;
      page++;
    }

    return allDomains;
  }

  /// Get DNS records for a domain (host records).
  Future<List<Map<String, dynamic>>> listDnsRecords(String domain) async {
    final parts = domain.split('.');
    final sld = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : domain;
    final tld = parts.isNotEmpty ? parts.last : '';

    final allRecords = <Map<String, dynamic>>[];
    var page = 1;
    var hasMore = true;

    while (hasMore) {
      final extra = <String, String>{
        'SLD': sld,
        'TLD': tld,
        'Page': page.toString(),
        'PageSize': '100',
      };
      final params = _buildParams('namecheap.domains.dns.getHosts', extra);
      final res = await http.get(Uri.parse('$_baseUrl?$params'));

      if (res.statusCode != 200) {
        throw Exception('Namecheap listDnsRecords failed: ${res.statusCode}');
      }

      final xml = res.body;
      final hostRegex = RegExp(r'<host\b[^>]*>([\s\S]*?)<\/host>', dotAll: true);
      for (final match in hostRegex.allMatches(xml)) {
        final hostXml = match.group(0)!;
        final attrs = <String, String>{};

        // Parse attributes from the opening tag
        final attrRegex = RegExp(r'(\w+)="([^"]*)"');
        for (final attrMatch in attrRegex.allMatches(hostXml)) {
          attrs[attrMatch[1]!] = attrMatch[2] ?? '';
        }

        allRecords.add({
          'id': attrs['HostId'] ?? attrs['id'] ?? '',
          'type': attrs['Type'] ?? attrs['RecordType'] ?? 'A',
          'name': '${attrs['Name'] ?? attrs['Host'] ?? ''}.$domain',
          'content': attrs['Address'] ?? attrs['Data'] ?? attrs['Value'] ?? '',
          'ttl': int.tryParse(attrs['TTL'] ?? '3600') ?? 3600,
          'mxPriority': attrs['MXPref'] ?? attrs['Priority'],
        });
      }

      // Check pagination
      final totalItemsMatch = RegExp(r'TotalItems="(\d+)"').firstMatch(xml);
      final pageSizeMatch = RegExp(r'PageSize="(\d+)"').firstMatch(xml);
      final totalItems = int.tryParse(totalItemsMatch?[1] ?? '0') ?? 0;
      final pageSize = int.tryParse(pageSizeMatch?[1] ?? '100') ?? 100;
      hasMore = page * pageSize < totalItems;
      page++;
    }

    return allRecords;
  }

  /// Update nameservers for a domain.
  Future<bool> updateNameservers(String domain, List<String> nameservers) async {
    final parts = domain.split('.');
    final sld = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : domain;
    final tld = parts.isNotEmpty ? parts.last : '';

    final extra = <String, String>{
      'SLD': sld,
      'TLD': tld,
    };
    for (var i = 0; i < nameservers.length; i++) {
      extra['Nameserver${i + 1}'] = nameservers[i];
    }

    final params = _buildParams('namecheap.domains.dns.setCustom', extra);
    final res = await http.get(Uri.parse('$_baseUrl?$params'));
    return res.statusCode == 200;
  }
}
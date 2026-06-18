import 'dart:convert';
import 'package:http/http.dart' as http;

/// Hetzner Cloud API client.
/// Docs: https://docs.hetzner.cloud/

class HetznerService {
  final String apiToken;
  final String _baseUrl = 'https://api.hetzner.cloud/v1';

  HetznerService({required this.apiToken});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiToken',
        'Content-Type': 'application/json',
      };

  /// List all servers in the Hetzner Cloud project.
  Future<List<Map<String, dynamic>>> listServers() async {
    final servers = <Map<String, dynamic>>[];
    var page = 1;
    var hasMore = true;

    while (hasMore) {
      final res = await http.get(
        Uri.parse('$_baseUrl/servers?page=$page&per_page=50'),
        headers: _headers,
      );
      if (res.statusCode != 200) {
        throw Exception('Hetzner listServers failed: ${res.statusCode} ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['servers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final srv in results) {
        final ips = <String>[];
        if (srv['public_net']?['ipv4']?['ip'] != null) {
          ips.add(srv['public_net']['ipv4']['ip'] as String);
        }
        if (srv['public_net']?['ipv6']?['ip'] != null) {
          ips.add(srv['public_net']['ipv6']['ip'] as String);
        }
        servers.add({
          'id': srv['id'],
          'name': srv['name'],
          'status': srv['status'],
          'ipAddresses': ips,
          'region':
              '${srv['datacenter']?['location']?['country'] ?? ''} ${srv['datacenter']?['location']?['name'] ?? ''}'.trim(),
          'flavor': srv['server_type']?['name'],
          'image': srv['image']?['name'],
          'created': srv['created'],
          'vcpus': srv['server_type']?['cores'],
          'memoryMB': srv['server_type']?['memory'],
          'diskGB': srv['server_type']?['disk'],
          'os': srv['image']?['os']?['name'] ?? srv['image']?['name'],
          'raw': srv,
        });
      }
      final meta = data['meta']?['pagination'] as Map<String, dynamic>?;
      final lastPage = meta?['last_page'] ?? 1;
      hasMore = page < lastPage;
      page++;
    }

    return servers;
  }
}
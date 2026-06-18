/// OVH API client for Dart/Flutter.
///
/// Ported from python-ovh (https://github.com/ovh/python-ovh).
///
/// Supports:
/// - Application key authentication with SHA1 request signing
/// - OAuth2 Client Credentials flow
/// - Named endpoints (ovh-eu, ovh-us, ovh-ca, kimsufi-eu, etc.)
/// - Automatic server time synchronization (lazy, cached)
/// - Consumer key request flow
/// - Full CRUD operations (GET, POST, PUT, DELETE)
/// - Proper error handling with typed exceptions
/// - /v1 /v2 path prefix handling

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

// ── Named endpoints ────────────────────────────────────────────────────

/// Mapping of named endpoints to their base URLs.
const Map<String, String> kOvhEndpoints = {
  'ovh-eu': 'https://eu.api.ovh.com/1.0',
  'ovh-us': 'https://api.us.ovhcloud.com/1.0',
  'ovh-ca': 'https://ca.api.ovh.com/1.0',
  'kimsufi-eu': 'https://eu.api.kimsufi.com/1.0',
  'kimsufi-ca': 'https://ca.api.kimsufi.com/1.0',
  'soyoustart-eu': 'https://eu.api.soyoustart.com/1.0',
  'soyoustart-ca': 'https://ca.api.soyoustart.com/1.0',
};

/// OAuth2 token provider URLs per endpoint (only some regions support OAuth2).
const Map<String, String> kOvhOAuth2TokenUrls = {
  'ovh-eu': 'https://www.ovh.com/auth/oauth2/token',
  'ovh-ca': 'https://ca.ovh.com/auth/oauth2/token',
  'ovh-us': 'https://us.ovhcloud.com/auth/oauth2/token',
};

// ── Exceptions ─────────────────────────────────────────────────────────

/// Base exception for all OVH API errors.
class OvhError implements Exception {
  final String? message;
  final int? statusCode;
  final String? queryId;

  OvhError([this.message, this.statusCode, this.queryId]);

  @override
  String toString() {
    if (queryId != null) {
      return '$message (queryId: $queryId)';
    }
    return message ?? 'OvhError';
  }
}

/// Network-level error (DNS, connection, etc.).
class OvhNetworkError extends OvhError {
  OvhNetworkError([String? message]) : super(message);
}

/// Invalid application key or consumer key.
class OvhInvalidKeyError extends OvhError {
  OvhInvalidKeyError([String? message]) : super(message);
}

/// Invalid consumer key credentials.
class OvhInvalidCredentialError extends OvhError {
  OvhInvalidCredentialError([String? message, int? statusCode, String? queryId])
      : super(message, statusCode, queryId);
}

/// Invalid configuration (missing keys, conflicting auth, etc.).
class OvhInvalidConfigurationError extends OvhError {
  OvhInvalidConfigurationError([String? message]) : super(message);
}

/// Requested resource does not exist (HTTP 404).
class OvhResourceNotFoundError extends OvhError {
  OvhResourceNotFoundError([String? message, int? statusCode, String? queryId])
      : super(message, statusCode, queryId);
}

/// Bad request parameters (HTTP 400).
class OvhBadParametersError extends OvhError {
  OvhBadParametersError([String? message, int? statusCode, String? queryId])
      : super(message, statusCode, queryId);
}

/// Forbidden access (HTTP 403, errorCode: FORBIDDEN).
class OvhForbiddenError extends OvhError {
  OvhForbiddenError([String? message, int? statusCode, String? queryId])
      : super(message, statusCode, queryId);
}

/// Not granted call (HTTP 403, errorCode: NOT_GRANTED_CALL).
class OvhNotGrantedCallError extends OvhError {
  OvhNotGrantedCallError([String? message, int? statusCode, String? queryId])
      : super(message, statusCode, queryId);
}

/// Not credential (HTTP 403, errorCode: NOT_CREDENTIAL).
class OvhNotCredentialError extends OvhError {
  OvhNotCredentialError([String? message, int? statusCode, String? queryId])
      : super(message, statusCode, queryId);
}

/// Resource conflict (HTTP 409).
class OvhResourceConflictError extends OvhError {
  OvhResourceConflictError([String? message, int? statusCode, String? queryId])
      : super(message, statusCode, queryId);
}

/// Resource expired (HTTP 460).
class OvhResourceExpiredError extends OvhError {
  OvhResourceExpiredError([String? message, int? statusCode, String? queryId])
      : super(message, statusCode, queryId);
}

/// Failed to decode API response.
class OvhInvalidResponseError extends OvhError {
  OvhInvalidResponseError([String? message]) : super(message);
}

/// OAuth2 token acquisition or refresh failure.
class OvhOAuth2Error extends OvhError {
  OvhOAuth2Error([String? message]) : super(message);
}

// ── Access rule helpers ────────────────────────────────────────────────

/// Common access rule method sets for consumer key requests.
class OvhApiMethods {
  static const List<String> readOnly = ['GET'];
  static const List<String> readWrite = ['GET', 'POST', 'PUT', 'DELETE'];
  static const List<String> readWriteSafe = ['GET', 'POST', 'PUT'];
}

// ── Consumer key request ───────────────────────────────────────────────

/// Result of requesting a new consumer key.
class OvhConsumerKeyRequest {
  final String consumerKey;
  final String validationUrl;
  final String state;

  OvhConsumerKeyRequest({
    required this.consumerKey,
    required this.validationUrl,
    required this.state,
  });
}

/// Builder for consumer key access rules.
class OvhConsumerKeyRequestBuilder {
  final OvhClient _client;
  final List<Map<String, String>> _accessRules = [];

  OvhConsumerKeyRequestBuilder(this._client);

  /// Add a single method+path rule.
  OvhConsumerKeyRequestBuilder addRule(String method, String path) {
    _accessRules.add({'method': method.toUpperCase(), 'path': path});
    return this;
  }

  /// Add rules for multiple methods on a path.
  OvhConsumerKeyRequestBuilder addRules(List<String> methods, String path) {
    for (final method in methods) {
      addRule(method, path);
    }
    return this;
  }

  /// Add recursive rules: grants access to [path] and [path]/*.
  OvhConsumerKeyRequestBuilder addRecursiveRules(List<String> methods, String path) {
    path = path.replaceAll(RegExp(r'[*\/\s]+$'), '');
    if (path.isNotEmpty) {
      addRules(methods, path);
    }
    addRules(methods, '$path/*');
    return this;
  }

  /// Submit the consumer key request.
  Future<OvhConsumerKeyRequest> request({String? redirectUrl, List<String>? allowedIPs}) {
    return _client.requestConsumerKey(_accessRules,
        redirectUrl: redirectUrl, allowedIPs: allowedIPs);
  }
}

// ── OAuth2 helper ─────────────────────────────────────────────────────

class _OvhOAuth2 {
  final String clientId;
  final String clientSecret;
  final String tokenUrl;
  String? _accessToken;
  DateTime? _tokenExpiry;

  _OvhOAuth2({
    required this.clientId,
    required this.clientSecret,
    required this.tokenUrl,
  });

  /// Get a valid access token, refreshing if necessary.
  Future<String> getAccessToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken!;
    }
    return _refreshToken();
  }

  Future<String> _refreshToken() async {
    final response = await http.post(
      Uri.parse(tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'client_credentials',
        'client_id': clientId,
        'client_secret': clientSecret,
        'scope': 'all',
      },
    );
    if (response.statusCode != 200) {
      throw OvhOAuth2Error(
          'OAuth2 token request failed: ${response.statusCode} ${response.body}');
    }
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _accessToken = data['access_token'] as String;
      final expiresIn = (data['expires_in'] as int?) ?? 3600;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
      return _accessToken!;
    } catch (e) {
      throw OvhOAuth2Error('Failed to parse OAuth2 token response: $e');
    }
  }

  /// Invalidate cached token (e.g., after a 401).
  void invalidateToken() {
    _accessToken = null;
    _tokenExpiry = null;
  }
}

// ── Client ─────────────────────────────────────────────────────────────

/// Low-level OVH API client, ported from python-ovh.
///
/// Handles authentication (application key signing or OAuth2), request
/// signing, server time synchronization, and error handling.
///
/// Usage:
/// ```dart
/// final client = OvhClient(
///   endpoint: 'ovh-eu',
///   applicationKey: 'your_app_key',
///   applicationSecret: 'your_app_secret',
///   consumerKey: 'your_consumer_key',
/// );
/// final me = await client.get('/me');
/// print(me);
/// ```
class OvhClient {
  /// Named endpoint identifier (e.g. 'ovh-eu') or a full base URL.
  final String endpoint;

  /// Application key for OVH API authentication.
  final String? applicationKey;

  /// Application secret for OVH API authentication.
  final String? applicationSecret;

  /// Consumer key identifying the end user.
  final String? consumerKey;

  /// OAuth2 client ID (alternative to application key auth).
  final String? clientId;

  /// OAuth2 client secret (alternative to application key auth).
  final String? clientSecret;

  /// Resolved base URL for API calls.
  late final String _baseUrl;

  /// Lazy-loaded time delta between local and server clock.
  int? _timeDelta;

  /// OAuth2 helper (only set when using client_id/client_secret auth).
  _OvhOAuth2? _oauth2;

  /// HTTP client for making requests.
  final http.Client _httpClient = http.Client();

  OvhClient({
    String? endpoint,
    this.applicationKey,
    this.applicationSecret,
    this.consumerKey,
    this.clientId,
    this.clientSecret,
  }) : endpoint = endpoint ?? 'ovh-eu' {
    // Resolve base URL from named endpoint or use as-is
    _baseUrl = kOvhEndpoints[this.endpoint] ?? this.endpoint;

    // Validate authentication configuration
    if (clientId != null && applicationKey != null) {
      throw OvhInvalidConfigurationError(
          "Can't use both application_key/application_secret and OAuth2 client_id/client_secret");
    }
    if ((clientId != null) != (clientSecret != null)) {
      throw OvhInvalidConfigurationError(
          'Both client_id and client_secret must be provided for OAuth2');
    }
    if ((applicationKey != null) != (applicationSecret != null)) {
      throw OvhInvalidConfigurationError(
          'Both application_key and application_secret must be provided');
    }
    if (clientId == null && applicationKey == null) {
      throw OvhInvalidConfigurationError(
          'Missing authentication: provide application_key/application_secret or client_id/client_secret');
    }

    // Setup OAuth2 if needed
    if (clientId != null) {
      final tokenUrl = kOvhOAuth2TokenUrls[this.endpoint];
      if (tokenUrl == null) {
        throw OvhInvalidConfigurationError(
            'OAuth2 is only compatible with ovh-eu, ovh-ca, and ovh-us endpoints');
      }
      _oauth2 = _OvhOAuth2(
        clientId: clientId!,
        clientSecret: clientSecret!,
        tokenUrl: tokenUrl,
      );
    }
  }

  /// Convenience factory for backward compatibility — accepts a raw base URL.
  factory OvhClient.withBaseUrl({
    required String baseUrl,
    String? applicationKey,
    String? applicationSecret,
    String? consumerKey,
  }) {
    return OvhClient(
      endpoint: baseUrl,
      applicationKey: applicationKey,
      applicationSecret: applicationSecret,
      consumerKey: consumerKey,
    );
  }

  /// Release the HTTP client.
  void close() {
    _httpClient.close();
  }

  // ── Time synchronization ──────────────────────────────────────────m─

  /// Get the time delta between local and server clock (lazy, cached).
  Future<int> get timeDelta async {
    if (_timeDelta == null) {
      final serverTime = await _fetchServerTime();
      final localTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _timeDelta = serverTime - localTime;
    }
    return _timeDelta!;
  }

  /// Invalidate cached time delta (useful after clock changes).
  void invalidateTimeDelta() {
    _timeDelta = null;
  }

  Future<int> _fetchServerTime() async {
    final target = _buildTarget('/auth/time');
    final response = await _httpClient.get(Uri.parse(target));
    if (response.statusCode != 200) {
      throw OvhNetworkError(
          'Failed to fetch server time: ${response.statusCode}');
    }
    return int.parse(response.body.trim());
  }

  // ── Consumer key request ──────────────────────────────────────────m─

  /// Create a new consumer key request builder.
  OvhConsumerKeyRequestBuilder newConsumerKeyRequest() {
    return OvhConsumerKeyRequestBuilder(this);
  }

  /// Request a new consumer key with the given access rules.
  Future<OvhConsumerKeyRequest> requestConsumerKey(
    List<Map<String, String>> accessRules, {
    String? redirectUrl,
    List<String>? allowedIPs,
  }) async {
    final body = <String, dynamic>{
      'accessRules': accessRules,
    };
    if (redirectUrl != null) {
      body['redirection'] = redirectUrl;
    }
    if (allowedIPs != null) {
      body['allowedIPs'] = allowedIPs;
    }
    final result = await post('/auth/credential', needAuth: false, body: body);
    return OvhConsumerKeyRequest(
      consumerKey: result['consumerKey'] as String,
      validationUrl: result['validationUrl'] as String,
      state: result['state'] as String,
    );
  }

  // ── HTTP method shortcuts ─────────────────────────────────────────m─

  /// Perform a GET request.
  Future<dynamic> get(
    String path, {
    bool needAuth = true,
    Map<String, dynamic>? queryParams,
  }) async {
    var target = path;
    if (queryParams != null && queryParams.isNotEmpty) {
      final qs = _encodeQueryString(queryParams);
      target = target.contains('?') ? '$target&$qs' : '$target?$qs';
    }
    return call('GET', target, null, needAuth);
  }

  /// Perform a POST request.
  Future<dynamic> post(String path,
      {bool needAuth = true, Map<String, dynamic>? body}) async {
    return call('POST', path, body, needAuth);
  }

  /// Perform a PUT request.
  Future<dynamic> put(String path,
      {bool needAuth = true, Map<String, dynamic>? body}) async {
    return call('PUT', path, body, needAuth);
  }

  /// Perform a DELETE request.
  Future<dynamic> delete(
    String path, {
    bool needAuth = true,
    Map<String, dynamic>? queryParams,
  }) async {
    var target = path;
    if (queryParams != null && queryParams.isNotEmpty) {
      final qs = _encodeQueryString(queryParams);
      target = target.contains('?') ? '$target&$qs' : '$target?$qs';
    }
    return call('DELETE', target, null, needAuth);
  }

  // ── Core request ──────────────────────────────────────────────────m─

  /// Low-level API call with signing and error handling.
  Future<dynamic> call(
    String method,
    String path,
    Map<String, dynamic>? data,
    bool needAuth,
  ) async {
    final target = _buildTarget(path);
    final bodyStr = data != null ? jsonEncode(data) : '';

    final headers = <String, String>{};
    if (data != null) {
      headers['Content-Type'] = 'application/json';
    }

    if (needAuth) {
      if (_oauth2 != null) {
        // OAuth2 authentication
        final token = await _oauth2!.getAccessToken();
        headers['Authorization'] = 'Bearer $token';
      } else {
        // Application key authentication with SHA1 signing
        if (applicationSecret == null || applicationSecret!.isEmpty) {
          throw OvhInvalidKeyError('Invalid ApplicationSecret');
        }
        if (consumerKey == null || consumerKey!.isEmpty) {
          throw OvhInvalidKeyError('Invalid ConsumerKey');
        }

        final delta = await timeDelta;
        final now =
            (DateTime.now().millisecondsSinceEpoch ~/ 1000) + delta;

        // Sign: SHA1("applicationSecret+consumerKey+METHOD+target+body+timestamp")
        final toSign =
            '$applicationSecret+$consumerKey+${method.toUpperCase()}+$target+$bodyStr+$now';
        final signature =
            '\$1\$${sha1.convert(utf8.encode(toSign))}';

        headers['X-Ovh-Consumer'] = consumerKey!;
        headers['X-Ovh-Timestamp'] = now.toString();
        headers['X-Ovh-Signature'] = signature;
      }
    }

    // X-Ovh-Application is always sent
    if (applicationKey != null) {
      headers['X-Ovh-Application'] = applicationKey!;
    }

    // Make the request
    http.Response response;
    try {
      final request = http.Request(method.toUpperCase(), Uri.parse(target));
      request.headers.addAll(headers);
      if (bodyStr.isNotEmpty) {
        request.body = bodyStr;
      }
      final streamed = await _httpClient.send(request);
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw OvhNetworkError('HTTP request failed: $e');
    }

    return _handleResponse(response);
  }

  /// Parse response and handle errors, matching python-ovh behavior.
  dynamic _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    final queryId = response.headers['x-ovh-queryid'];

    dynamic jsonResult;
    if (statusCode != 204 && response.body.isNotEmpty) {
      try {
        jsonResult = jsonDecode(response.body);
      } catch (e) {
        throw OvhInvalidResponseError(
            'Failed to decode API response: $e');
      }
    }

    // Success range
    if (statusCode >= 100 && statusCode < 300) {
      return jsonResult;
    }

    // Error handling
    final message = jsonResult is Map ? jsonResult['message'] : null;
    final errorCode = jsonResult is Map ? jsonResult['errorCode'] : null;

    if (statusCode == 403) {
      switch (errorCode) {
        case 'NOT_GRANTED_CALL':
          throw OvhNotGrantedCallError(message, statusCode, queryId);
        case 'NOT_CREDENTIAL':
          throw OvhNotCredentialError(message, statusCode, queryId);
        case 'INVALID_KEY':
          throw OvhInvalidKeyError('$message (queryId: $queryId)');
        case 'INVALID_CREDENTIAL':
          throw OvhInvalidCredentialError(message, statusCode, queryId);
        case 'FORBIDDEN':
          throw OvhForbiddenError(message, statusCode, queryId);
      }
    }

    switch (statusCode) {
      case 400:
        throw OvhBadParametersError(message, statusCode, queryId);
      case 404:
        throw OvhResourceNotFoundError(message, statusCode, queryId);
      case 409:
        throw OvhResourceConflictError(message, statusCode, queryId);
      case 460:
        throw OvhResourceExpiredError(message, statusCode, queryId);
      case 0:
        throw OvhNetworkError();
      default:
        throw OvhError(message?.toString(), statusCode, queryId);
    }
  }

  // ── URL building ─────────────────────────────────────────────────m─

  /// Build the full target URL. Strips /1.0 suffix when path starts with /v1 or /v2.
  String _buildTarget(String path) {
    var base = _baseUrl;
    if (base.endsWith('/1.0') &&
        (path.startsWith('/v1') || path.startsWith('/v2'))) {
      base = base.substring(0, base.length - 4);
    }
    return '$base$path';
  }

  /// Encode query parameters, converting booleans to lowercase strings.
  /// Null values are excluded from the query string.
  String _encodeQueryString(Map<String, dynamic> params) {
    return params.entries
        .where((e) => e.value != null)
        .map((e) {
      final v = e.value is bool
          ? e.value.toString().toLowerCase()
          : e.value.toString();
      return '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(v)}';
    }).join('&');
  }
}
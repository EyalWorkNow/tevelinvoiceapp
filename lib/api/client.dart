import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;

import '../util/errors_he.dart';
import 'environment.dart';

/// Server error mapped to Hebrew. [status] 0 = no HTTP response (network).
class ApiException implements Exception {
  ApiException(this.status, this.code, this.messageHe, {this.serverMessage});

  final int status;
  final String code;
  final String messageHe;
  final String? serverMessage;

  bool get isNetwork => status == 0;

  @override
  String toString() => 'ApiException($status $code)';
}

/// Global auth events. The session controller listens for [sessionExpired];
/// the login flow listens for [mfaRequired] while still on the cookie session;
/// lib/state/business_context.dart listens for [forbidden] (SPEC-v2 §4.6:
/// a 403 means the capabilities changed → refresh /me and rebuild).
enum ApiEvent { sessionExpired, mfaRequired, forbidden }

/// 403 codes that mean "your permissions changed" (§4.6).
const Set<String> capabilityRefreshCodes = {
  'FORBIDDEN',
  'DOCUMENT_ACTION_FORBIDDEN',
};

/// One HTTP client for the whole app.
///
/// Two auth modes:
/// * cookie session (only during sign-in): `tvl_session` captured from
///   Set-Cookie, `X-CSRF-Token` on every non-GET;
/// * device token (everything after sign-in): `Authorization: Bearer inv_…`
///   + `X-Business-Id`. Bearer is CSRF/MFA-exempt on the server.
///
/// The client keeps credentials in memory only; SessionController persists
/// the device token in the Keychain.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: kReleaseMode
        ? 'https://invoice.crm.tevel.space'
        : 'http://127.0.0.1:3031',
  );
  static const Duration timeout = Duration(seconds: 30);

  /// Replaceable in tests (package:http/testing.dart MockClient).
  http.Client httpClient = http.Client();

  String? sessionCookie;
  String? csrfToken;
  String? deviceToken;
  String? businessId;

  final StreamController<ApiEvent> _events =
      StreamController<ApiEvent>.broadcast();
  Stream<ApiEvent> get events => _events.stream;

  bool get hasDeviceToken => deviceToken != null;

  /// Forget every credential (sign-out / expiry).
  void clearCredentials() {
    sessionCookie = null;
    csrfToken = null;
    deviceToken = null;
    businessId = null;
  }

  /// CONTRACT B: trade the (MFA-satisfied) cookie session for a 90-day
  /// device token, then drop the cookie. Returns the token for persistence.
  Future<String> exchangeSessionForDeviceToken(String deviceName) async {
    final json = await post('/auth/device-token', {'deviceName': deviceName});
    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw ApiException(0, 'BAD_RESPONSE', errorMessageHe('BAD_RESPONSE'));
    }
    deviceToken = token;
    sessionCookie = null;
    csrfToken = null;
    return token;
  }

  // ---- JSON helpers -------------------------------------------------------

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _json('GET', path, query: query);

  Future<Map<String, dynamic>> post(
    String path, [
    Object? body,
    String? idempotencyKey,
  ]) => _json(
    'POST',
    path,
    body: body ?? const {},
    idempotencyKey: idempotencyKey,
  );

  /// Business-scoped background registration without mutating the active UI scope.
  Future<Map<String, dynamic>> postForBusiness(
    String business,
    String path,
    Object body,
  ) => _json('POST', path, body: body, businessOverride: business);

  Future<Map<String, dynamic>> getForBusiness(
    String business,
    String path, {
    Map<String, String>? query,
  }) => _json('GET', path, query: query, businessOverride: business);

  Future<Map<String, dynamic>> putForBusiness(
    String business,
    String path,
    Object body,
  ) => _json('PUT', path, body: body, businessOverride: business);

  Future<Map<String, dynamic>> deleteForBusiness(String business, String path) =>
      _json('DELETE', path, businessOverride: business);

  Future<Map<String, dynamic>> put(String path, Object? body) =>
      _json('PUT', path, body: body ?? const {});

  Future<Map<String, dynamic>> patch(String path, Object? body) =>
      _json('PATCH', path, body: body ?? const {});

  Future<Map<String, dynamic>> delete(String path) => _json('DELETE', path);

  /// Raw bytes (PDF download).
  Future<Uint8List> getBytes(String path, {Map<String, String>? query}) async {
    final response = await _send('GET', path, query: query);
    return response.bodyBytes;
  }

  /// POST with a JSON body that answers with bytes (PDF preview).
  Future<Uint8List> postBytes(
    String path,
    Object? body, {
    String accept = 'application/pdf',
  }) async {
    final response = await _send(
      'POST',
      path,
      body: body ?? const {},
      extraHeaders: {'Accept': accept},
    );
    return response.bodyBytes;
  }

  /// Raw body upload (expense bytes). [filename] is percent-encoded into
  /// X-Filename like the web client (header values must be Latin-1).
  Future<Map<String, dynamic>> putBytes(
    String path,
    Uint8List bytes,
    String contentType, {
    String? filename,
  }) async {
    final response = await _send(
      'PUT',
      path,
      bytes: bytes,
      contentType: contentType,
      extraHeaders: {
        if (filename != null) 'X-Filename': Uri.encodeComponent(filename),
      },
    );
    return _decode(response);
  }

  /// Fresh UUID v4 for Idempotency-Key. Callers persist it with the pending
  /// operation so a retry re-sends the SAME key.
  static String newIdempotencyKey() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  // ---- internals ----------------------------------------------------------

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String? idempotencyKey,
    String? businessOverride,
  }) async {
    final response = await _send(
      method,
      path,
      body: body,
      query: query,
      idempotencyKey: idempotencyKey,
      businessOverride: businessOverride,
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return <String, dynamic>{};
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        response.statusCode,
        'BAD_RESPONSE',
        errorMessageHe('BAD_RESPONSE'),
      );
    }
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        response.statusCode,
        'BAD_RESPONSE',
        errorMessageHe('BAD_RESPONSE'),
      );
    }
    // Any csrfToken in a body (login, mfa, rotation) replaces the stored one.
    final csrf = json['csrfToken'];
    if (csrf is String && csrf.isNotEmpty) csrfToken = csrf;
    return json;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Uint8List? bytes,
    String? contentType,
    Map<String, String>? query,
    String? idempotencyKey,
    String? businessOverride,
    Map<String, String> extraHeaders = const {},
  }) async {
    // Defence in depth for interpolated ids ('/documents/$id'): no dot
    // segments, so nothing can climb out of the intended resource.
    final rawPath = path.split('?').first;
    if (rawPath.split('/').any((s) => s == '.' || s == '..') ||
        path.contains('#')) {
      throw ApiException(0, 'INVALID_ID', errorMessageHe('INVALID_ID'));
    }
    final origin = apiOrigin(baseUrl);
    final Uri uri;
    try {
      uri = Uri.parse('$origin$path').replace(
        queryParameters: (query == null || query.isEmpty) ? null : query,
      );
    } on FormatException {
      throw ApiException(0, 'INVALID_ID', errorMessageHe('INVALID_ID'));
    }
    final request = http.Request(method, uri);
    final headers = request.headers..addAll(extraHeaders);
    headers['Accept'] = extraHeaders['Accept'] ?? 'application/json';
    final token = deviceToken;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      final cookie = sessionCookie;
      if (cookie != null) headers['Cookie'] = 'tvl_session=$cookie';
      final csrf = csrfToken;
      if (method != 'GET' && csrf != null) headers['X-CSRF-Token'] = csrf;
    }
    final business = businessOverride ?? businessId;
    if (business != null && sendsBusinessHeader(path)) {
      headers['X-Business-Id'] = business;
    }
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    if (bytes != null) {
      headers['Content-Type'] = contentType ?? 'application/octet-stream';
      request.bodyBytes = bytes;
    } else if (body != null) {
      headers['Content-Type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await httpClient.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw ApiException(0, 'TIMEOUT', errorMessageHe('TIMEOUT'));
    } on SocketException {
      throw ApiException(0, 'NETWORK', errorMessageHe('NETWORK'));
    } on http.ClientException {
      throw ApiException(0, 'NETWORK', errorMessageHe('NETWORK'));
    }

    _captureCookie(response.headers['set-cookie']);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw _error(response, path);
  }

  /// Set-Cookie on login / MFA / rotation overwrites the stored session;
  /// an emptied cookie (logout) clears it.
  void _captureCookie(String? setCookie) {
    if (setCookie == null) return;
    final match = RegExp(
      r'(?:^|[,\s])tvl_session=([^;,]*)',
    ).firstMatch(setCookie);
    if (match == null) return;
    final value = match.group(1)!;
    sessionCookie = value.isEmpty ? null : value;
  }

  ApiException _error(http.Response response, String path) {
    final status = response.statusCode;
    var code = 'ERROR';
    String? message;
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is Map<String, dynamic>) {
        if (json['error'] is String) code = json['error'] as String;
        if (json['message'] is String) message = json['message'] as String;
      }
    } on FormatException {
      // Non-JSON error body (proxy page): fall back on the status.
    }
    if (code == 'ERROR') {
      if (status == 429) code = 'RATE_LIMITED';
      if (status == 502 || status == 503 || status == 504) {
        code = 'SERVICE_UNAVAILABLE';
      }
    }
    // 401 on /auth/* is a login answer (wrong password, bad code), not expiry.
    if (status == 401 && !path.startsWith('/auth/')) {
      _events.add(ApiEvent.sessionExpired);
    }
    if (status == 403 && code == 'MFA_REQUIRED') {
      _events.add(ApiEvent.mfaRequired);
    }
    if (status == 403 &&
        capabilityRefreshCodes.contains(code) &&
        path != '/me') {
      _events.add(ApiEvent.forbidden);
    }
    return ApiException(
      status,
      code,
      errorMessageHe(code, serverMessage: message, status: status),
      serverMessage: message,
    );
  }
}

/// The API origin for [base] (the API_BASE define). A bad define in a release
/// build is a config error shown in Hebrew, never a raw [FormatException].
String apiOrigin(String base, {bool release = kReleaseMode}) {
  if (!release) return base;
  try {
    return productionApiUri(base).toString();
  } on FormatException {
    throw ApiException(
      0,
      'API_CONFIG_INVALID',
      errorMessageHe('API_CONFIG_INVALID'),
    );
  }
}

/// /mobile/* routes that are business-scoped on the server (V2: BE-05 inbox,
/// BE-35 web hand-off). The rest of /mobile/* and /auth/* are account-level
/// and must not carry X-Business-Id (400 BUSINESS_REQUIRED otherwise).
const Set<String> businessScopedMobilePaths = {
  '/mobile/inbox',
  '/mobile/web-handoff',
  '/mobile/push-tokens',
};

bool sendsBusinessHeader(String path) {
  if (path.startsWith('/auth/')) return false;
  if (!path.startsWith('/mobile/')) return true;
  return businessScopedMobilePaths.contains(path.split('?').first);
}

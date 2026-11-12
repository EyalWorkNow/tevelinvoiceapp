// In-memory server for unit/widget tests (INT). Squads build against it before
// the real endpoints exist. See docs/ARCHITECTURE-v2.md "How to add a fake".
//
//   final b = FakeBackend()..install();
//   b.json('GET', '/documents', {'total': 0, 'documents': []});
//   b.on('POST', '/documents/:id/finalize', (r) => FakeResponse(200, {'status': 'FINALIZED'}));
//   b.error('POST', '/documents/:id/credit', 403, 'DOCUMENT_ACTION_FORBIDDEN');
//   ... pump ...
//   expect(b.calls('POST', '/documents/:id/finalize'), hasLength(1));

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/client.dart';

/// One request as the fake saw it.
class FakeRequest {
  FakeRequest(this.raw, this.pattern, this.params);

  final http.Request raw;

  /// The registered pattern that matched, e.g. '/documents/:id/finalize'.
  final String pattern;
  final Map<String, String> params;

  String get method => raw.method;
  String get path => raw.url.path;
  Map<String, String> get query => raw.url.queryParameters;
  Map<String, String> get headers => raw.headers;

  /// Decoded JSON body ({} when empty / not JSON).
  Map<String, dynamic> get body {
    if (raw.body.isEmpty) return const {};
    final v = jsonDecode(raw.body);
    return v is Map<String, dynamic> ? v : const {};
  }

  String? get idempotencyKey => raw.headers['Idempotency-Key'];
}

class FakeResponse {
  const FakeResponse(this.status, [this.body = const {}]);

  /// Server error shape: {error: CODE, message}.
  factory FakeResponse.error(int status, String code, [String? message]) =>
      FakeResponse(status, {'error': code, 'message': ?message});

  final int status;

  /// JSON-encodable body, or raw bytes (`List<int>`) for PDFs.
  final Object body;
}

typedef FakeHandler = FutureOr<FakeResponse> Function(FakeRequest request);

class FakeBackend {
  final Map<String, FakeHandler> _routes = {};

  /// Every request, in order (matched or not).
  final List<FakeRequest> requests = [];

  /// Registers [handler] for "METHOD /path/:param". Later registrations of the
  /// same key replace earlier ones (a test can override a squad default).
  void on(String method, String pattern, FakeHandler handler) =>
      _routes['${method.toUpperCase()} $pattern'] = handler;

  /// Fixed JSON answer.
  void json(String method, String pattern, Object body, {int status = 200}) =>
      on(method, pattern, (_) => FakeResponse(status, body));

  /// Fixed error answer ({error: code}).
  void error(String method, String pattern, int status, String code) =>
      on(method, pattern, (_) => FakeResponse.error(status, code));

  /// Removes a route (next call → 404 NOT_FOUND).
  void off(String method, String pattern) =>
      _routes.remove('${method.toUpperCase()} $pattern');

  /// Requests that matched "METHOD pattern" (pattern as registered).
  List<FakeRequest> calls(String method, String pattern) => [
    for (final r in requests)
      if (r.method == method.toUpperCase() && r.pattern == pattern) r,
  ];

  FakeRequest? last(String method, String pattern) {
    final c = calls(method, pattern);
    return c.isEmpty ? null : c.last;
  }

  /// Plugs this backend into [client] (default: the app-wide ApiClient).
  void install([ApiClient? client]) {
    (client ?? ApiClient.instance).httpClient = MockClient(handle);
  }

  Future<http.Response> handle(http.Request raw) async {
    for (final entry in _routes.entries) {
      final space = entry.key.indexOf(' ');
      final method = entry.key.substring(0, space);
      final pattern = entry.key.substring(space + 1);
      if (method != raw.method) continue;
      final params = matchPath(pattern, raw.url.path);
      if (params == null) continue;
      final req = FakeRequest(raw, pattern, params);
      requests.add(req);
      return _encode(await entry.value(req));
    }
    requests.add(FakeRequest(raw, raw.url.path, const {}));
    return _encode(FakeResponse.error(404, 'NOT_FOUND'));
  }

  static http.Response _encode(FakeResponse r) {
    final body = r.body;
    if (body is List<int>) {
      return http.Response.bytes(
        body,
        r.status,
        headers: {'content-type': 'application/pdf'},
      );
    }
    return http.Response(
      jsonEncode(body),
      r.status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// '/documents/:id' vs '/documents/d1' → {id: d1}; null when no match.
  static Map<String, String>? matchPath(String pattern, String path) {
    final p = pattern.split('/');
    final s = path.split('/');
    if (p.length != s.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < p.length; i++) {
      if (p[i].startsWith(':')) {
        params[p[i].substring(1)] = s[i];
      } else if (p[i] != s[i]) {
        return null;
      }
    }
    return params;
  }
}

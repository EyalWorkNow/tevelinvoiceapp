import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/client.dart';

void main() {
  final api = ApiClient.instance;
  late List<http.Request> sent;

  void respond(
    int status,
    Object? body, {
    Map<String, String> headers = const {},
  }) {
    api.httpClient = MockClient((request) async {
      sent.add(request);
      return http.Response(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          ...headers,
        },
      );
    });
  }

  setUp(() {
    sent = [];
    api.clearCredentials();
  });

  test(
    'login captures cookie + csrf; later POST sends both, no business on /auth',
    () async {
      respond(
        200,
        {'status': 'PASSWORD_OK', 'csrfToken': 'c1', 'businesses': []},
        headers: {
          'set-cookie':
              'tvl_session=abc123; HttpOnly; SameSite=Strict; Path=/; Max-Age=43200',
        },
      );
      await api.post('/auth/login', {'email': 'a@b.co', 'password': 'x'});
      expect(api.sessionCookie, 'abc123');
      expect(api.csrfToken, 'c1');

      api.businessId = 'biz-1';
      respond(201, {
        'token': 'inv_${'a' * 48}',
        'tokenId': 't',
        'expiresAt': '2027-01-01T00:00:00Z',
      });
      final token = await api.exchangeSessionForDeviceToken('iPhone');
      final r = sent.last;
      expect(r.headers['Cookie'], 'tvl_session=abc123');
      expect(r.headers['X-CSRF-Token'], 'c1');
      expect(r.headers.containsKey('X-Business-Id'), isFalse);
      expect(jsonDecode(r.body), {'deviceName': 'iPhone'});
      // Cookie mode is dropped once the device token exists.
      expect(token, startsWith('inv_'));
      expect(api.sessionCookie, isNull);
      expect(api.csrfToken, isNull);
    },
  );

  test(
    'bearer mode: Authorization + X-Business-Id, no cookie/csrf; /mobile has no business',
    () async {
      api.deviceToken = 'inv_tok';
      api.businessId = 'biz-1';
      respond(200, {'documents': [], 'total': 0});
      await api.get('/documents', query: {'unpaid': '1'});
      var r = sent.last;
      expect(r.url.toString(), '${ApiClient.baseUrl}/documents?unpaid=1');
      expect(r.headers['Authorization'], 'Bearer inv_tok');
      expect(r.headers['X-Business-Id'], 'biz-1');
      expect(r.headers.containsKey('Cookie'), isFalse);
      expect(r.headers.containsKey('X-CSRF-Token'), isFalse);

      respond(200, {'status': 'ok'});
      await api.post('/mobile/logout');
      r = sent.last;
      expect(r.headers.containsKey('X-Business-Id'), isFalse);
      expect(r.headers['Authorization'], 'Bearer inv_tok');

      // V2 business-scoped /mobile routes (the server answers 400 BUSINESS_REQUIRED without it).
      respond(200, {'money': null, 'cards': [], 'recent': []});
      await api.get('/mobile/inbox', query: {'limit': '10'});
      expect(sent.last.headers['X-Business-Id'], 'biz-1');
      respond(202, {'sentTo': 'a@b.c'});
      await api.post('/mobile/web-handoff', {'topic': 'TAX_AUTHORITY'});
      expect(sent.last.headers['X-Business-Id'], 'biz-1');
      respond(200, {'businesses': []});
      await api.get('/mobile/session');
      expect(sent.last.headers.containsKey('X-Business-Id'), isFalse);
    },
  );

  test(
    'background push registration uses its business without changing UI scope',
    () async {
      api.deviceToken = 'inv_tok';
      api.businessId = 'active-business';
      respond(200, {'registered': true});
      await api.postForBusiness('other-business', '/mobile/push-tokens', {
        'tokenType': 'liveActivityUpdate',
      });
      expect(sent.last.headers['X-Business-Id'], 'other-business');
      expect(api.businessId, 'active-business');
      await api.get('/documents');
      expect(sent.last.headers['X-Business-Id'], 'active-business');
    },
  );

  test('dot segments in an API path are refused before any request', () async {
    respond(200, {});
    await expectLater(
      api.get('/documents/../business/members'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_ID')),
    );
    await expectLater(
      api.post('/documents/../../x?y=/artifact', {}),
      throwsA(isA<ApiException>()),
    );
    expect(sent, isEmpty);
  });

  test(
    'a bad release API_BASE is an ApiException, never a raw FormatException',
    () {
      expect(
        () => apiOrigin('http://10.0.0.5:3031', release: true),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'API_CONFIG_INVALID',
          ),
        ),
      );
      expect(
        apiOrigin('https://invoice.crm.tevel.space', release: true),
        'https://invoice.crm.tevel.space',
      );
    },
  );

  test('idempotency key header and uuid v4 shape', () async {
    api.deviceToken = 'inv_tok';
    respond(200, {'status': 'FINALIZED'});
    final key = ApiClient.newIdempotencyKey();
    expect(
      key,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(ApiClient.newIdempotencyKey(), isNot(key));
    await api.post('/documents/d1/finalize', {'scopeKey': 'default'}, key);
    expect(sent.last.headers['Idempotency-Key'], key);
  });

  test('cookie rotation overwrites; cleared cookie clears', () async {
    respond(
      200,
      {'status': 'ok', 'csrfToken': 'c2'},
      headers: {'set-cookie': 'tvl_session=rotated; HttpOnly; Path=/'},
    );
    await api.post('/auth/mfa', {'code': '123456'});
    expect(api.sessionCookie, 'rotated');
    expect(api.csrfToken, 'c2');
    respond(
      200,
      {'status': 'ok'},
      headers: {'set-cookie': 'tvl_session=; HttpOnly; Max-Age=0'},
    );
    await api.post('/auth/logout');
    expect(api.sessionCookie, isNull);
  });

  test('errors map to Hebrew ApiException and fire events', () async {
    final events = <ApiEvent>[];
    final sub = api.events.listen(events.add);
    api.deviceToken = 'inv_tok';

    respond(404, {
      'error': 'DOCUMENT_NOT_FOUND',
      'message': 'document not found',
    });
    await expectLater(
      api.get('/documents/x'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.code, 'code', 'DOCUMENT_NOT_FOUND')
            .having((e) => e.messageHe, 'messageHe', 'המסמך לא נמצא'),
      ),
    );

    respond(401, {'error': 'UNAUTHENTICATED'});
    await expectLater(api.get('/dashboard'), throwsA(isA<ApiException>()));
    // 401 from /auth/* (wrong password) is not a session expiry.
    respond(401, {'error': 'INVALID_CREDENTIALS'});
    await expectLater(
      api.post('/auth/login', {}),
      throwsA(isA<ApiException>()),
    );
    respond(403, {'error': 'MFA_REQUIRED'});
    await expectLater(
      api.post('/auth/device-token', {}),
      throwsA(isA<ApiException>()),
    );
    respond(503, '<html>bad gateway</html>');
    await expectLater(
      api.get('/me'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'SERVICE_UNAVAILABLE',
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, [ApiEvent.sessionExpired, ApiEvent.mfaRequired]);
    await sub.cancel();
  });

  test('network failure → NETWORK ApiException', () async {
    api.httpClient = MockClient(
      (_) async => throw const SocketException('down'),
    );
    await expectLater(
      api.get('/me'),
      throwsA(
        isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true),
      ),
    );
    api.httpClient = MockClient(
      (_) async => throw http.ClientException('reset'),
    );
    await expectLater(
      api.get('/me'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')),
    );
  });

  test('bytes up and down', () async {
    api.deviceToken = 'inv_tok';
    api.httpClient = MockClient((request) async {
      sent.add(request);
      if (request.method == 'GET')
        return http.Response.bytes([37, 80, 68, 70], 200);
      return http.Response('{"status":"stored"}', 200);
    });
    expect(await api.getBytes('/documents/d1/pdf'), [37, 80, 68, 70]);
    await api.putBytes(
      '/expenses/uploads/u1/bytes',
      utf8.encode('jpeg'),
      'image/jpeg',
      filename: 'קבלה.jpg',
    );
    expect(sent.last.headers['Content-Type'], 'image/jpeg');
    expect(sent.last.headers['X-Filename'], Uri.encodeComponent('קבלה.jpg'));
    expect(sent.last.body, 'jpeg');
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

const _account = {
  'userId': 'u1',
  'email': 'a@b.c',
  'displayName': null,
  'businesses': [
    {'businessId': 'b1', 'legalName': 'עסק א', 'role': 'OWNER'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late final ApiClient api;
  const storage = FlutterSecureStorage();

  late Directory tmp;

  setUpAll(() async {
    api = ApiClient.instance;
    tmp = await Directory.systemTemp.createTemp('session_test');
    AppCache.directoryProvider = () async => tmp;
    await AppCache.isFirstLaunch(); // the install marker exists from here on
  });

  setUp(() async {
    api.clearCredentials();
    await AppCache.clearAll();
  });

  Future<SessionController> restoreWith(int status) async {
    FlutterSecureStorage.setMockInitialValues({'device_token': 'inv_abc', 'business_id': 'b1'});
    api.httpClient = MockClient((r) async => switch (r.url.path) {
          '/mobile/session' => status == 200 ? _json(200, _account) : _json(status, {'error': 'X'}),
          '/me' => _json(status, {'error': 'X'}),
          _ => _json(404, {'error': 'NOT_FOUND'}),
        });
    final s = SessionController(client: api);
    await s.restore();
    return s;
  }

  test('cold start: 503 / 429 keep the token and run from the cached account', () async {
    await AppCache.write('account', _account);
    for (final status in [500, 503, 429]) {
      final s = await restoreWith(status);
      expect(s.status, SessionStatus.signedIn, reason: '$status');
      expect(s.offline, isTrue);
      expect(s.business?.businessId, 'b1');
      expect(await storage.read(key: 'device_token'), 'inv_abc');
    }
  });

  test('cold start: 401 signs out, but keeps a pending issue for the resume banner', () async {
    await AppCache.write('nd_pending_issue_b1', {'stage': 'finalized'});
    await AppCache.write('pending_payment_d1', {'key': 'k'});
    await AppCache.write('dashboard_b1', {'x': 1});
    final s = await restoreWith(401);
    expect(s.status, SessionStatus.signedOut);
    expect(s.expired, isTrue);
    expect(await storage.read(key: 'device_token'), isNull);
    expect(await AppCache.read('nd_pending_issue_b1'), isNotNull);
    expect(await AppCache.read('pending_payment_d1'), isNotNull);
    expect(await AppCache.read('dashboard_b1'), isNull);
    expect(await AppCache.hasPending(), isTrue);
  });

  test('first launch after (re)install forgets a Keychain token left by the old install', () async {
    File('${tmp.path}/.installed').deleteSync();
    final logouts = <String?>[];
    FlutterSecureStorage.setMockInitialValues({'device_token': 'inv_old', 'business_id': 'b1'});
    api.httpClient = MockClient((r) async {
      if (r.url.path == '/mobile/logout') logouts.add(r.headers['Authorization']);
      return _json(200, {'status': 'ok'});
    });
    final s = SessionController(client: api);
    await s.restore();
    expect(s.status, SessionStatus.signedOut);
    expect(await storage.read(key: 'device_token'), isNull);
    expect(logouts, ['Bearer inv_old']);
    expect(File('${tmp.path}/.installed').existsSync(), isTrue);
  });

  test('explicit sign-out wipes pending operations too', () async {
    await AppCache.write('nd_pending_issue_b1', {'stage': 'finalized'});
    final s = await restoreWith(200);
    expect(s.status, SessionStatus.signedIn);
    await s.signOut();
    expect(await AppCache.read('nd_pending_issue_b1'), isNull);
    expect(await AppCache.hasPending(), isFalse);
  });

  test('refreshBusiness drops a response that lands after a business switch', () async {
    final gate = Completer<void>();
    api.httpClient = MockClient((r) async {
      final bid = r.headers['X-Business-Id'];
      if (bid == 'b1') await gate.future;
      return switch (r.url.path) {
        '/me' => _json(200, {
            'userId': 'u1',
            'role': 'OWNER',
            'onboarding': {'completed': true},
          }),
        '/business/profile' => _json(200, {
            'profile': {'legalName': bid == 'b1' ? 'עסק א' : 'עסק ב', 'businessType': 'OSEK_MURSHE'},
          }),
        _ => _json(404, {'error': 'NOT_FOUND'}),
      };
    });
    FlutterSecureStorage.setMockInitialValues({});
    final s = SessionController(client: api);
    s.business = const Business(businessId: 'b1', legalName: 'עסק א', role: 'OWNER');
    api.businessId = 'b1';
    final stale = s.refreshBusiness();
    await s.selectBusiness(const Business(businessId: 'b2', legalName: 'עסק ב', role: 'OWNER'));
    gate.complete();
    await stale;
    expect(s.profile?.legalName, 'עסק ב');
  });
}

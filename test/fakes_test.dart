import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/util/allowed_urls.dart';

import 'fakes/fake_api.dart';

void main() {
  test('FakeBackend: patterns, params, body, idempotency key, 404 default', () async {
    final b = FakeBackend()..install();
    b.on('POST', '/documents/:id/finalize', (r) => FakeResponse(200, {'id': r.params['id'], 'got': r.body}));
    final res = await ApiClient.instance.post('/documents/d7/finalize', {'scopeKey': 'x'}, 'key-1');
    expect(res, {'id': 'd7', 'got': {'scopeKey': 'x'}});
    expect(b.last('POST', '/documents/:id/finalize')!.idempotencyKey, 'key-1');
    await expectLater(ApiClient.instance.get('/unknown'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NOT_FOUND')));
    b.error('GET', '/me', 403, 'MFA_REQUIRED');
    await expectLater(ApiClient.instance.get('/me'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'MFA_REQUIRED')));
    expect(b.requests, hasLength(3));
  });

  test('domain fakes install defaults', () async {
    final b = FakeBackend()..install();
    installInboxFakes(b);
    installIssueFakes(b);
    installActionsFakes(b);
    installPeopleFakes(b);
    installBusinessFakes(b);
    expect((await ApiClient.instance.get('/documents'))['documents'], isEmpty);
  });

  test('FakeLauncher records; AT-95 allows only wa.me / mailto / tel and the Safari whitelist',
      () async {
    final l = FakeLauncher()..install();
    addTearDown(FakeLauncher.uninstall);
    await launchAllowed(Uri.parse('https://wa.me/972501234567?text=x'));
    await launchAllowed(Uri.parse('mailto:a@b.c'));
    await launchAllowed(Uri.parse('tel:0501234567'));
    expect(l.last.toString(), 'tel:0501234567');
    expect(() => launchAllowed(Uri.parse('https://example.com')), throwsArgumentError);
    // Documented AT-95 exception: iOS Settings after a denied camera permission
    // (UIApplication.openSettingsURLString), from expense capture "פתח הגדרות".
    await launchAllowed(Uri.parse('app-settings:'));
    expect(l.last.toString(), 'app-settings:');
    expect(() => launchAllowed(Uri.parse('app-settings:x')), throwsArgumentError);
    expect(() => launchAllowed(Uri.parse('https://wa.me.evil.example/x')), throwsArgumentError);
    await openSafari(Uri.parse(privacyUrl));
    expect(l.inApp.single.toString(), privacyUrl);
    expect(() => openSafari(Uri.parse('https://example.com/pay')), throwsArgumentError);
  });
}

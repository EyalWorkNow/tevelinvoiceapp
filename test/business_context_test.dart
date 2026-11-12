import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';

import 'fakes/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeBackend backend;
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('bctx_test');
    AppCache.directoryProvider = () async => tmp;
    await AppCache.isFirstLaunch();
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    await AppCache.clearAll();
    backend = FakeBackend()..install();
  });

  test('caps come from /me; business type and display name from /me + profile', () async {
    await signInAs(backend, Preset.employee, businessType: 'OSEK_PATUR');
    expect(businessContext.caps.preset, Preset.employee);
    expect(businessContext.can(Cap.docDraft), isTrue);
    expect(businessContext.can(Cap.moneyView), isFalse);
    expect(businessContext.businessType, 'OSEK_PATUR');
    expect(businessContext.isVatExempt, isTrue);
    expect(businessContext.displayName, 'סטודיו תבל');
    expect(businessContext.hasManyBusinesses, isFalse);
  });

  test('a capability 403 refreshes /me, emits permissionsChanged, caps rebuild (§4.6)', () async {
    await signInAs(backend, Preset.employeeIssuer);
    expect(businessContext.can(Cap.docIssue), isTrue);
    // The owner switched the "מפיק בעצמו" toggle off on another device.
    backend
      ..json('GET', '/me', meJson(Preset.employee))
      ..error('POST', '/documents/:id/finalize', 403, 'DOCUMENT_ACTION_FORBIDDEN');
    final changed = businessContext.permissionsChanged.first;
    await expectLater(ApiClient.instance.post('/documents/d1/finalize'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
    await changed.timeout(const Duration(seconds: 2));
    expect(backend.calls('GET', '/me'), hasLength(2));
    expect(businessContext.can(Cap.docIssue), isFalse);
  });

  test('other 403s (MFA, backdating) do not refresh capabilities', () async {
    await signInAs(backend, Preset.owner);
    backend.error('POST', '/documents', 403, 'BACKDATING_OWNER_ONLY');
    await expectLater(ApiClient.instance.post('/documents'), throwsA(isA<ApiException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(backend.calls('GET', '/me'), hasLength(1));
  });

  test('foreground refresh only after 60 s', () async {
    await signInAs(backend, Preset.owner);
    var now = DateTime.now();
    final ctx = BusinessContext(clock: () => now);
    addTearDown(ctx.dispose);
    await ctx.onResumed();
    expect(backend.calls('GET', '/me'), hasLength(1));
    now = now.add(const Duration(seconds: 61));
    await ctx.onResumed();
    expect(backend.calls('GET', '/me'), hasLength(2));
  });

  test('capabilities older than 24 h are not used', () async {
    await signInAs(backend, Preset.owner);
    session.meFetchedAt = DateTime.now().subtract(const Duration(hours: 25));
    expect(businessContext.caps, same(Caps.none));
    expect(businessContext.can(Cap.docView), isFalse);
  });

  test('offline cold start reads the cached /me (≤ 24 h)', () async {
    await signInAs(backend, Preset.partner);
    await AppCache.write('account', accountJson(role: 'ADMIN'));
    FlutterSecureStorage.setMockInitialValues({'device_token': 'inv_x', 'business_id': 'b1'});
    resetSession();
    backend
      ..error('GET', '/mobile/session', 503, 'SERVICE_UNAVAILABLE')
      ..error('GET', '/me', 503, 'SERVICE_UNAVAILABLE');
    await session.restore();
    expect(session.status, SessionStatus.signedIn);
    expect(businessContext.caps.preset, Preset.partner);
    await session.revalidation; // cache start: the server check runs in the background
    expect(session.offline, isTrue);
    expect(businessContext.caps.preset, Preset.partner);
  });

  test('V1 server (no BE-02): business type falls back on the profile', () async {
    await signInAs(backend, Preset.owner, businessType: 'NONPROFIT', be02: false);
    expect(businessContext.businessType, 'NONPROFIT');
    expect(businessContext.caps.fromFallback, isTrue);
  });
}

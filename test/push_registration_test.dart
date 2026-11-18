// Push registration state machine (prod 2026-11-18: not one phone in
// push_devices / mobile_push_tokens). Native side faked through the
// tevel/system_notices method channel and the token event channel.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/business/system_notice_settings.dart'
    show PushStatusPanel;
import 'package:invoice/state/caps.dart' show Preset;
import 'package:invoice/state/session.dart';
import 'package:invoice/state/system_notices.dart';
import 'package:invoice/util/labels/system_notices_he.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

const _methods = MethodChannel('tevel/system_notices');
const _events = EventChannel('tevel/system_notice_events');
final _alertToken = 'ab' * 32;

class _Native {
  String authorization = 'authorized';
  bool grant = true;
  final calls = <String>[];
  MockStreamHandlerEventSink? sink;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'status':
          return {
            'notifications': authorization == 'authorized',
            'determined': authorization != 'notDetermined',
            'authorization': authorization,
            'liveActivities': false,
          };
        case 'enable':
          authorization = grant ? 'authorized' : 'denied';
          return grant;
      }
      return null;
    });
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (_, events) => sink = events,
        onCancel: (_) => sink = null,
      ),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(_methods, null);
      messenger.setMockStreamHandler(_events, null);
    });
  }

  void alertToken() => sink!.success({
    'type': 'token',
    'tokenType': 'alert',
    'token': _alertToken,
    'environment': 'production',
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('registration', _registration);
  group('"סטטוס התראות" panel', _panel);
}

void _registration() {
  late FakeBackend backend;
  late _Native native;

  setUp(() async {
    backend = await eSetUp();
    await signInAs(backend, Preset.owner);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    native = _Native()..install();
    // Production today: APNs not configured on the server.
    backend
      ..json('GET', '/mobile/push-status', {
        'deliveryConfigured': false,
        'state': 'disabled',
        'registeredTokens': 0,
      })
      ..json('POST', '/mobile/push-tokens', {
        'registered': true,
        'deliveryConfigured': false,
      })
      ..json('POST', '/mobile/push/devices', {'status': 'ok', 'id': 'd1'});
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<SystemNotices> start() async {
    final notices = SystemNotices()..install();
    addTearDown(() {
      session.beforeSignOut.remove(notices.unregisterForSignOut);
      notices.dispose();
    });
    await _settle();
    return notices;
  }

  test('server without APNs: the phone is still registered in BOTH '
      'registries (was: PUSH_SERVICE_NOT_CONFIGURED stopped before '
      '/mobile/push/devices)', () async {
    final notices = await start();
    native.alertToken();
    await _settle();
    expect(backend.calls('POST', '/mobile/push-tokens'), hasLength(1));
    final devices = backend.calls('POST', '/mobile/push/devices');
    expect(devices, hasLength(1));
    expect(devices.single.body['environment'], 'production');
    final d = notices.diagnostics;
    expect(d.osAuthorization, 'authorized');
    expect(d.tokenReceived, isTrue);
    expect(d.registered, isTrue);
    expect(d.serverDeliveryConfigured, isFalse);
    expect(d.lastError, isNull);
    expect(notices.syncError, isNull);
  });

  test('a refused business registration does not keep the catalogue device '
      'from registering, and its code is shown', () async {
    backend.on(
      'POST',
      '/mobile/push-tokens',
      (_) => FakeResponse.error(
        422,
        'VALIDATION',
        'a current device credential is required',
      ),
    );
    final notices = await start();
    native.alertToken();
    await _settle();
    expect(backend.calls('POST', '/mobile/push/devices'), hasLength(1));
    final d = notices.diagnostics;
    expect(d.businessRegistered, isFalse);
    expect(d.catalogueRegistered, isTrue);
    expect(d.lastError, startsWith('PUSH_MFA_REQUIRED'));
    expect(notices.mfaRequired, isTrue);
  });

  test('a failing catalogue registration is no longer silent; '
      '"נסה לרשום שוב" registers again', () async {
    backend.error('POST', '/mobile/push/devices', 503, 'SERVICE_UNAVAILABLE');
    final notices = await start();
    native.alertToken();
    await _settle();
    expect(notices.diagnostics.catalogueRegistered, isFalse);
    expect(
      notices.diagnostics.lastError,
      'CATALOGUE SERVICE_UNAVAILABLE (503)',
    );
    backend.json('POST', '/mobile/push/devices', {'status': 'ok', 'id': 'd1'});
    await notices.retryRegistration();
    await _settle();
    expect(notices.diagnostics.registered, isTrue);
    expect(notices.diagnostics.lastError, isNull);
    // The retry re-sent the business row too and asked iOS again.
    expect(backend.calls('POST', '/mobile/push-tokens'), hasLength(2));
    expect(native.calls.where((m) => m == 'resume').length, greaterThan(1));
  });

  test('APNs refuses (e.g. no aps-environment): the reason is shown, nothing '
      'is sent', () async {
    final notices = await start();
    native.sink!.success({
      'type': 'registrationError',
      'code': 'APNS_REGISTRATION_FAILED',
      'message': 'NSCocoaErrorDomain 3000: no valid aps-environment',
    });
    await _settle();
    final d = notices.diagnostics;
    expect(d.tokenReceived, isFalse);
    expect(d.registered, isFalse);
    expect(d.lastError, contains('aps-environment'));
    expect(backend.calls('POST', '/mobile/push-tokens'), isEmpty);
    // A token later on clears it and registers.
    native.alertToken();
    await _settle();
    expect(notices.diagnostics.registered, isTrue);
  });

  test('fresh install: iOS is asked once; allowed → registered', () async {
    native.authorization = 'notDetermined';
    final notices = await start();
    expect(native.calls.where((m) => m == 'enable'), hasLength(1));
    native.alertToken();
    await _settle();
    expect(notices.enabled, isTrue);
    expect(notices.diagnostics.registered, isTrue);
  });

  test('fresh install, declined: nothing is sent, never asked again in '
      'this launch', () async {
    native
      ..authorization = 'notDetermined'
      ..grant = false;
    final notices = await start();
    await notices.refresh();
    await _settle();
    expect(native.calls.where((m) => m == 'enable'), hasLength(1));
    expect(notices.enabled, isFalse);
    expect(notices.diagnostics.osAuthorization, 'denied');
    expect(backend.calls('POST', '/mobile/push-tokens'), isEmpty);
    expect(backend.calls('POST', '/mobile/push/devices'), isEmpty);
  });

  test('switched off in the app: a token is never sent', () async {
    backend
      ..json('DELETE', '/mobile/push-tokens', {'registered': false})
      ..json('POST', '/mobile/push/devices/unregister', {'status': 'ok'});
    final notices = await start();
    await notices.disable();
    backend.requests.clear();
    native.alertToken();
    await _settle();
    expect(backend.calls('POST', '/mobile/push-tokens'), isEmpty);
    expect(backend.calls('POST', '/mobile/push/devices'), isEmpty);
    expect(notices.enabled, isFalse);
  });
}

void _panel() {
  {
    Future<void> pumpPanel(
      WidgetTester tester,
      PushDiagnostics d, {
      VoidCallback? onRetry,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: PushStatusPanel(
              diagnostics: d,
              busy: false,
              onRetry: onRetry ?? () {},
            ),
          ),
        ),
      ),
    );

    testWidgets('shows permission, token, server and the last error', (
      tester,
    ) async {
      var retried = 0;
      await pumpPanel(
        tester,
        const PushDiagnostics(
          osAuthorization: 'authorized',
          tokenReceived: true,
          businessRegistered: true,
          catalogueRegistered: false,
          serverDeliveryConfigured: false,
          lastError: 'CATALOGUE SERVICE_UNAVAILABLE (503)',
        ),
        onRetry: () => retried++,
      );
      expect(find.text(SystemNoticesHe.status), findsOneWidget);
      expect(find.text(SystemNoticesHe.permissionAllowed), findsOneWidget);
      expect(find.text(SystemNoticesHe.yes), findsOneWidget);
      expect(find.text(SystemNoticesHe.partlyRegistered), findsOneWidget);
      expect(find.text(SystemNoticesHe.deliveryOff), findsOneWidget);
      expect(find.text('CATALOGUE SERVICE_UNAVAILABLE (503)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('push-status-retry')));
      expect(retried, 1);
    });

    testWidgets('never asked / no token / not registered, no error row', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        const PushDiagnostics(
          osAuthorization: 'notDetermined',
          tokenReceived: false,
          businessRegistered: false,
          catalogueRegistered: false,
          lastError: null,
        ),
      );
      expect(find.text(SystemNoticesHe.permissionNotAsked), findsOneWidget);
      expect(find.text(SystemNoticesHe.no), findsOneWidget);
      expect(find.text(SystemNoticesHe.notRegistered), findsOneWidget);
      expect(find.byKey(const Key('push-status-error')), findsNothing);
      expect(find.byKey(const Key('push-status-delivery')), findsNothing);
    });
  }
}

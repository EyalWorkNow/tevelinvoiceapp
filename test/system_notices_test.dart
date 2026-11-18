import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/router.dart' show debugPendingDeepLink;
import 'package:invoice/state/system_notices.dart';
import 'package:invoice/ui/widgets/notch_notice.dart';

void main() {
  test(
    'server event kinds map to distinct in-app motion without revealing amounts',
    () {
      expect(systemNoticePresentation('approved')?.$2, NoticeMotion.approved);
      expect(systemNoticePresentation('payment')?.$2, NoticeMotion.payment);
      expect(systemNoticePresentation('rejected')?.$2, NoticeMotion.error);
      for (final kind in [
        'approved',
        'payment',
        'approvalNeeded',
        'rejected',
        'viewed',
        'expense',
        'reminder',
        'visit',
        'collection',
        'issued',
        'sent',
        'signed',
      ]) {
        final presentation = systemNoticePresentation(kind);
        expect(presentation, isNotNull);
        expect(presentation!.$1, isNot(contains('₪')));
      }
      expect(systemNoticePresentation('arbitrary-remote-event'), isNull);
    },
  );

  test(
    'push refused for a device token without MFA gets its own clear code',
    () {
      final mapped = SystemNotices.pushRegistrationError(
        ApiException(
          400,
          'VALIDATION',
          'x',
          serverMessage: 'a current device credential is required',
        ),
      );
      expect(mapped.code, 'PUSH_MFA_REQUIRED');
      expect(mapped.messageHe, contains('אימות דו-שלבי'));
      final other = ApiException(503, 'SERVICE_UNAVAILABLE', 'x');
      expect(SystemNotices.pushRegistrationError(other), same(other));
    },
  );

  group('push at start-up (tester 2026-11-18: no quote-accepted push)', () {
    test('fresh install / sign-in, iOS never asked → ask once', () {
      expect(
        pushStartup(stored: null, osAuthorized: false, osDetermined: false),
        PushStartup.ask,
      );
    });
    test('iOS already allows, never chosen in the app → on (was: off, '
        'so no token was ever registered and no push could arrive)', () {
      expect(
        pushStartup(stored: null, osAuthorized: true, osDetermined: true),
        PushStartup.on,
      );
    });
    test('reinstall: a "1" left in the Keychain by the previous install '
        'does not stop the one-time question (was: never asked again)', () {
      expect(
        pushStartup(stored: '1', osAuthorized: false, osDetermined: false),
        PushStartup.ask,
      );
    });
    test('switched off in the app stays off, even when iOS allows', () {
      expect(
        pushStartup(stored: '0', osAuthorized: true, osDetermined: true),
        PushStartup.off,
      );
    });
    test('declined in iOS → off, never re-asked', () {
      expect(
        pushStartup(stored: null, osAuthorized: false, osDetermined: true),
        PushStartup.off,
      );
      expect(
        pushStartup(stored: '1', osAuthorized: false, osDetermined: true),
        PushStartup.off,
      );
    });
    test('switched on and allowed → on', () {
      expect(
        pushStartup(stored: '1', osAuthorized: true, osDetermined: true),
        PushStartup.on,
      );
    });
  });

  group('admin/template announcements (invoice#60, kind ANNOUNCEMENT)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('keep the server text: no fixed in-app presentation', () {
      expect(pushOpenOnlyKinds, contains('ANNOUNCEMENT'));
      expect(systemNoticePresentation('ANNOUNCEMENT'), isNull);
    });

    test('a tap opens the allowed link (after sign-in when signed out)', () {
      systemNotices.debugEvent({
        'type': 'opened',
        'kind': 'ANNOUNCEMENT',
        'route': '/business/account',
        'businessId': '',
        'eventID': '',
      });
      expect(debugPendingDeepLink, '/business/account');
    });

    test('a tap with a link outside the route table opens nothing', () {
      for (final route in ['/admin', 'https://evil.example/x', '']) {
        systemNotices.debugEvent({
          'type': 'opened',
          'kind': 'ANNOUNCEMENT',
          'route': route,
          'businessId': '',
        });
      }
      // The previous test's pending link is the only one.
      expect(debugPendingDeepLink, '/business/account');
    });

    test('foreground arrival is not turned into an in-app notice', () {
      // No notch host in this test: a notice attempt would be a no-op, the
      // point is that it returns before needing a presentation.
      systemNotices.debugEvent({
        'type': 'notice',
        'kind': 'ANNOUNCEMENT',
        'route': '/home',
        'businessId': '',
      });
      expect(debugPendingDeepLink, '/business/account');
    });
  });

  test('clearBadge asks the native side to clear the icon badge', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <String>[];
    const channel = MethodChannel('tevel/system_notices');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await systemNotices.clearBadge();
    expect(calls, ['clearBadge']);
  });

  test('clearBadge never throws without the native side', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await systemNotices.clearBadge();
  });
}

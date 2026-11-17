import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
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
}

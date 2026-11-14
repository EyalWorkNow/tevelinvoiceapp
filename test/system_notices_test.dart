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
}

// 0135 "האזור האישי של הלקוח" shots (2026-11-25), MOCKED data (FakeBackend,
// no server), on the customer page harness. Prints SHOT: markers:
//
//   U=<sim udid>; OUT=$PWD/docs/qa/2611-v6
//   ~/flutter/bin/flutter test integration_test/portal_shots_test.dart -d $U 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/screens/debts/reminder_hold_tile.dart';
import 'package:invoice/screens/people/customer_timeline_screen.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/customer_crm_store.dart';

import '../test/business/e_harness.dart';
import '../test/fakes/fake_api.dart';
import 'customer_page_shots_test.dart' as cp;

const _url =
    'https://app.tevel.space/p/k3VqN8wZr2LmT5yHc9XbD4sFg7Jp1QaE6uWn0OiRtYe';

Map<String, dynamic> _link({bool created = false}) => {
  'url': _url,
  'createdAt': '2026-11-20T08:00:00Z',
  'lastLoginAt': created ? null : '2026-11-24T16:42:00Z',
  'canVerify': true,
  'created': created,
  'whatsappText':
      'היי דניאל, כאן סטודיו נורה. זה האזור האישי שלך אצלנו — המסמכים, התשלומים וקביעת פגישה במקום אחד. הכניסה עם קוד שיישלח למייל שלך: $_url',
};

FakeBackend _backend() {
  final b = cp.backendFor()
    ..json('GET', '/customers/:id/portal-link', {'link': _link()})
    ..json('POST', '/customers/:id/portal-link', _link());
  b.json('GET', '/customers/:id/timeline', {
    'nextCursor': null,
    'sources': [
      'documents',
      'quotes',
      'payments',
      'notes',
      'calendar',
      'portal',
    ],
    'items': [
      cp.tl(
        'm1',
        'portal.message',
        0,
        9,
        data: {
          'text': 'היי, אפשר לקבל את החשבונית גם במייל של רואה החשבון? תודה!',
        },
      ),
      cp.tl(
        't3',
        'quote.sent',
        -9,
        12,
        amount: '1250000',
        data: {'quoteNumber': '88', 'channel': 'WHATSAPP'},
        linkType: 'quote',
        linkId: 'q88',
      ),
      cp.tl(
        't5',
        'document.sent',
        -48,
        9,
        amount: '284000',
        data: {
          'documentType': 'TAX_INVOICE',
          'documentNumber': '1057',
          'channel': 'EMAIL',
        },
        linkType: 'document',
        linkId: 'd-open',
      ),
    ],
  });
  return b;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('customer area shots', (tester) async {
    cp.t = tester;
    await eSetUp();
    loadReminderHold = ({customerId, documentId}) async => false;
    final b = _backend();
    await signInAs(b, Preset.owner);
    await CustomerCrmStore.instance.loadForBusiness('b1', force: true);
    await tester.pumpWidget(eApp(const PersonScreen(id: 'c1')));
    await cp.pumpMs(2500);

    await cp.openMore();
    await cp.shot('01-more-sheet');
    await cp.tapIf(find.byKey(const Key('person-more-portal')), waitMs: 1800);
    await cp.shot('02-portal-link-sheet');
    await cp.closeAll();

    if (await cp.tapIf(find.byKey(const Key('person-details')))) {
      await cp.scrollDown(dy: 900);
      await cp.shot('03-details-portal-row');
      if (await cp.tapIf(find.byKey(const Key('person-portal')))) {
        await cp.shot('04-portal-manage-sheet');
        await cp.closeAll();
      }
    }

    await tester.pumpWidget(const SizedBox());
    await cp.pumpMs(200);
    await tester.pumpWidget(
      eApp(
        const CustomerTimelineScreen(
          customerId: 'c1',
          customerName: 'דניאל רוזן',
        ),
      ),
    );
    await cp.pumpMs(2000);
    await cp.shot('05-timeline-customer-message');
    if (await cp.tapIf(find.text('הודעות מהלקוח'))) {
      await cp.shot('06-timeline-portal-chip');
    }
  });
}

// V4 §8 customer groups — screenshots with MOCKED data (the test FakeBackend,
// no server). Prints SHOT: markers (same protocol as customer_page_shots_test):
//
//   U=<sim udid>; OUT=$PWD/docs/qa/2611-v4
//   ~/flutter/bin/flutter test integration_test/groups_shots_test.dart -d $U 2>&1 |
//   while IFS= read -r l; do echo "$l"; if [[ $l == *SHOT:* ]]; then
//     n=${l##*SHOT:}; xcrun simctl io $U screenshot "$OUT/$n.png" >/dev/null 2>&1; fi; done
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/debts/reminder_hold_tile.dart';
import 'package:invoice/screens/groups/group_actions.dart';
import 'package:invoice/screens/groups/group_screen.dart';
import 'package:invoice/screens/people/people_screen.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/state/caps.dart';

import '../test/business/e_harness.dart';
import '../test/fakes/fake_api.dart';

late WidgetTester t;

Future<void> pumpMs(int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  do {
    await t.pump(const Duration(milliseconds: 50));
  } while (DateTime.now().isBefore(end));
}

Future<void> shot(String name) async {
  await pumpMs(1200);
  print('SHOT:$name');
  await pumpMs(1300);
}

Future<bool> tapIf(Finder f, {int waitMs = 1200}) async {
  for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
    await pumpMs(150);
  }
  if (f.evaluate().isEmpty) {
    print('AUDIT: not found: $f');
    return false;
  }
  await t.ensureVisible(f.first);
  await pumpMs(300);
  await t.tap(f.first, warnIfMissed: false);
  await pumpMs(waitMs);
  return true;
}

Future<void> closeAll() async {
  navigatorKey.currentState!.popUntil((r) => r.isFirst);
  await pumpMs(900);
}

Map<String, dynamic> g(
  String id,
  String name, {
  String color = 'blue',
  int members = 0,
  String? smart,
}) => {
  'id': id,
  'name': name,
  'color': color,
  'memberCount': members,
  'smart': smart,
};

Map<String, dynamic> row(
  String id,
  String name, {
  String? phone,
  String balance = '0',
}) => {
  'id': id,
  'name': name,
  'tax_id': null,
  'email': null,
  'phone': phone,
  'archived_at': null,
  'vat_dealer_status': 'PRIVATE',
  'customer_type': 'INDIVIDUAL',
  'balanceMinor': balance,
  'creditMinor': '0',
  'lastDocumentAt': null,
  'isWalkIn': false,
  'consent': {'granted': true},
};

Map<String, dynamic> m(
  String id,
  String name, {
  String? phone,
  String? email,
  String? balance = '0',
  bool archived = false,
}) => {
  'id': id,
  'name': name,
  'phone': phone,
  'email': email,
  'balanceMinor': balance,
  'archived': archived,
  'marketingConsent': false,
};

Map<String, dynamic> detail({bool money = true}) => {
  'group': g('g1', 'ועד בית הרצל 5', color: 'green', members: 7),
  'status': {
    'members': 7,
    'active': 7,
    'owing': 3,
    'owingMinor': money ? '186000' : null,
    'noPhone': 1,
    'noEmail': 3,
    'inactive': 0,
  },
  'members': [
    m('c1', 'דנה כהן', phone: '0501234567', balance: money ? '62000' : null),
    m(
      'c2',
      'אבי לוי',
      email: 'avi@example.com',
      balance: money ? '62000' : null,
    ),
    m(
      'c3',
      'מיכל ברק',
      phone: '0527654321',
      email: 'michal@example.com',
      balance: money ? '62000' : null,
    ),
    m('c4', 'יוסי אברהם', phone: '0541112233', balance: money ? '0' : null),
    m('c5', 'רונית שלום', phone: '0533334444', balance: money ? '0' : null),
    m(
      'c6',
      'עמית גל',
      phone: '0505556666',
      email: 'amit@example.com',
      balance: money ? '0' : null,
    ),
    m(
      'c7',
      'שירה נוי',
      email: 'shira@example.com',
      balance: money ? '0' : null,
    ),
  ],
  'invites': {'runId': 'r9', 'sent': 7, 'booked': 4},
};

FakeBackend backendFor(Preset p) {
  final b = FakeBackend()..install();
  installPeopleFakes(
    b,
    be09: true,
    customers: [
      row('c1', 'דנה כהן', phone: '0501234567', balance: '62000'),
      row('c2', 'אבי לוי', balance: '62000'),
      row('c3', 'מיכל ברק', phone: '0527654321', balance: '62000'),
      row('c4', 'יוסי אברהם', phone: '0541112233'),
      row('c5', 'רונית שלום', phone: '0533334444'),
      row('c6', 'עמית גל', phone: '0505556666'),
      row('c7', 'שירה נוי'),
      row('c8', 'נועם פרץ', phone: '0549998888'),
    ],
  );
  final money = p != Preset.employee;
  b
    ..json('GET', '/customer-groups', {
      'groups': [
        g('g1', 'ועד בית הרצל 5', color: 'green', members: 7),
        g('g2', 'מנויי שנתי', color: 'purple', members: 12),
        g('g3', 'קבוצת שלישי', color: 'orange', members: 8),
      ],
      'smart': [
        g('owes', 'חייבים לי', color: 'red', members: 9, smart: 'OWES'),
        g(
          'no-purchase-90',
          'לא קנו 90 יום',
          color: 'yellow',
          members: 14,
          smart: 'NO_PURCHASE_90',
        ),
        g(
          'inactive',
          'לא פעילים',
          color: 'gray',
          members: 4,
          smart: 'INACTIVE',
        ),
      ],
      'limits': {'maxGroups': 50, 'maxMembers': 500},
    })
    ..json('GET', '/customer-groups/:id', detail(money: money))
    ..json('GET', '/customers/:id/groups', {
      'groups': [
        g('g1', 'ועד בית הרצל 5', color: 'green', members: 7),
        g('g2', 'מנויי שנתי', color: 'purple', members: 12),
      ],
    })
    ..on('POST', '/customer-groups/:id/actions/:kind/preview', (r) {
      if (r.params['kind'] == 'document') {
        return const FakeResponse(200, {
          'kind': 'DOCUMENT',
          'recipients': 7,
          'documents': 7,
          'totalMinor': '175000',
          'perDocumentMinor': '25000',
          'skipped': {},
        });
      }
      return const FakeResponse(200, {
        'kind': 'BROADCAST',
        'recipients': 6,
        'email': 2,
        'whatsapp': 4,
        'skipped': {'noConsent': 1},
      });
    })
    ..json('POST', '/customer-groups/:id/actions/:kind', {
      'run': {
        'id': 'r1',
        'groupId': 'g1',
        'kind': 'BROADCAST',
        'counts': {'email': 2, 'whatsapp': 4, 'skipped': 1},
        'items': [
          for (final (id, name, ph) in [
            ('i1', 'דנה כהן', '0501234567'),
            ('i2', 'יוסי אברהם', '0541112233'),
            ('i3', 'רונית שלום', '0533334444'),
            ('i4', 'מיכל ברק', '0527654321'),
          ])
            {
              'id': id,
              'customerId': id,
              'name': name,
              'channel': 'WHATSAPP',
              'status': 'QUEUED',
              'phone': ph,
              'text':
                  'שלום ${name.split(' ').first}, ביום שלישי הקרוב יתקיים ניקיון חדר המדרגות. תודה, ועד הבית',
            },
        ],
      },
    });
  final s = b;
  s.on('GET', '/customers/:id', (r) {
    return const FakeResponse(200, {
      'customer': {
        'id': 'c1',
        'name': 'דנה כהן',
        'tax_id': null,
        'email': 'dana@example.com',
        'phone': '0501234567',
        'archived_at': null,
        'vat_dealer_status': 'PRIVATE',
        'customer_type': 'INDIVIDUAL',
        'paymentTerms': 'EOM_30',
        'consent': {'granted': true, 'method': null, 'at': null},
        'marketingConsent': {'granted': true, 'at': '2026-11-01T10:00:00Z'},
      },
      'stats': {
        'openMinor': '62000',
        'overdueMinor': '0',
        'creditMinor': '0',
        'documentsCount': 3,
        'lastDocumentAt': null,
      },
    });
  });
  return b;
}

Future<void> open(Preset p, Widget home) async {
  final b = backendFor(p);
  await signInAs(b, p);
  await t.pumpWidget(const SizedBox());
  await pumpMs(200);
  await t.pumpWidget(eApp(home));
  await pumpMs(2500);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('groups shots', (tester) async {
    t = tester;
    await eSetUp();
    loadReminderHold = ({customerId, documentId}) async => false;
    groupVatRate = () async => 1800;
    groupScopeKey = () async => 'default';

    // 1 · customers screen with the groups row.
    await open(Preset.owner, const PeopleScreen());
    await shot('01-customers-groups-row');

    // 2 · multi-select.
    await t.longPress(find.byKey(const Key('person-select-c1')));
    await pumpMs(600);
    await tapIf(find.byKey(const Key('person-c3')), waitMs: 500);
    await tapIf(find.byKey(const Key('person-c4')), waitMs: 500);
    await shot('02-multi-select');
    await tapIf(find.byKey(const Key('people-add-to-group')));
    await shot('03-pick-group');
    await closeAll();

    // 3 · new group sheet.
    await tapIf(find.byKey(const Key('people-selection-cancel')));
    await tapIf(find.byKey(const Key('groups-new')));
    await t.enterText(find.byKey(const Key('group-name')), 'קבוצת שלישי');
    await pumpMs(300);
    await tapIf(find.byKey(const Key('group-color-orange')), waitMs: 400);
    await shot('04-new-group-sheet');
    await closeAll();

    // 4 · group page, owner.
    await open(Preset.owner, const GroupScreen(id: 'g1'));
    await shot('05-group-page-owner');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await pumpMs(800);
    await shot('06-group-page-owner-members');

    // 5 · broadcast sheet → confirm → result → WhatsApp queue.
    await open(Preset.owner, const GroupScreen(id: 'g1'));
    await tapIf(find.byKey(const Key('group-action-broadcast')));
    await tapIf(find.text('מבצע / פרסום'), waitMs: 400);
    await t.enterText(
      find.byKey(const Key('group-broadcast-text')),
      'שלום {שם}, ביום שלישי הקרוב יתקיים ניקיון חדר המדרגות. תודה, ועד הבית',
    );
    await pumpMs(500);
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpMs(600);
    await shot('07-broadcast-sheet');
    await tapIf(find.byKey(const Key('group-broadcast-next')));
    await shot('08-broadcast-confirm');
    await tapIf(find.byKey(const Key('group-confirm-ok')));
    await shot('09-run-result');
    await tapIf(find.byKey(const Key('group-result-queue')));
    await shot('10-whatsapp-queue');
    await closeAll();

    // 6 · document for everyone → preview confirm.
    await open(Preset.owner, const GroupScreen(id: 'g1'));
    await tapIf(find.byKey(const Key('group-action-document')));
    await t.enterText(
      find.byKey(const Key('group-document-description')),
      'דמי ועד — דצמבר',
    );
    await t.enterText(find.byKey(const Key('group-document-amount')), '250');
    await pumpMs(400);
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpMs(600);
    await shot('11-document-sheet');
    await tapIf(find.byKey(const Key('group-document-next')));
    await shot('12-document-confirm');
    await closeAll();

    // 7 · GroupInviteSheet.
    await open(Preset.owner, const GroupScreen(id: 'g1'));
    await tapIf(find.byKey(const Key('group-action-invite')));
    await shot('13-group-invite-sheet');
    await closeAll();

    // 8 · group page, employee.
    await open(Preset.employee, const GroupScreen(id: 'g1'));
    await shot('14-group-page-employee');

    // 9 · customer details: groups + marketing consent.
    await open(Preset.owner, const PersonScreen(id: 'c1'));
    await tapIf(find.byKey(const Key('person-details')));
    await t.drag(find.byType(Scrollable).first, const Offset(0, -1400));
    await pumpMs(900);
    await shot('15-customer-details-groups-consent');
  });
}

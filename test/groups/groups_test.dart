// V4 §8 · קבוצות לקוחות: the pure logic (preview / result lines, {שם},
// permissions, selection, the document line) and every new screen / sheet:
// the customers screen's groups row + multi-select, the group page (owner /
// employee / smart "לא פעילים"), broadcast → preview → confirm → run →
// WhatsApp queue, document-for-all preview, GroupInviteSheet, and the customer
// page's "קבוצות" + "מאשר דיוור" rows.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/customer_groups_api.dart';
import 'package:invoice/api/models/me.dart';
import 'package:invoice/api/customers_api.dart' show resetStatementProbe;
import 'package:invoice/router.dart';
import 'package:invoice/screens/groups/group_actions.dart';
import 'package:invoice/screens/groups/group_invite_sheet.dart';
import 'package:invoice/screens/groups/group_screen.dart';
import 'package:invoice/screens/groups/groups_strip.dart';
import 'package:invoice/screens/people/people_screen.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/groups_he.dart';

import '../fakes/fake_api.dart';

Map<String, dynamic> groupJson(
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

List<Map<String, dynamic>> smartGroups() => [
  groupJson('owes', 'חייבים לי', color: 'red', members: 2, smart: 'OWES'),
  groupJson(
    'no-purchase-90',
    'לא קנו 90 יום',
    color: 'orange',
    members: 1,
    smart: 'NO_PURCHASE_90',
  ),
  groupJson(
    'inactive',
    'לא פעילים',
    color: 'gray',
    members: 1,
    smart: 'INACTIVE',
  ),
];

Map<String, dynamic> memberJson(
  String id,
  String name, {
  String? phone,
  String? email,
  String balance = '0',
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

Map<String, dynamic> detailJson({
  Map<String, dynamic>? group,
  Map<String, dynamic>? invites,
}) => {
  'group': group ?? groupJson('g1', 'ועד בית הרצל 5', members: 3),
  'status': {
    'members': 3,
    'active': 3,
    'owing': 2,
    'owingMinor': '150000',
    'noPhone': 1,
    'noEmail': 2,
    'inactive': 0,
  },
  'members': [
    memberJson('c1', 'דנה כהן', phone: '0501234567', balance: '100000'),
    memberJson('c2', 'אבי לוי', email: 'avi@example.com', balance: '50000'),
    memberJson('c3', 'רון', phone: '0507654321'),
  ],
  'invites': invites,
};

Map<String, dynamic> runJson({List<Map<String, dynamic>>? items}) => {
  'id': 'r1',
  'groupId': 'g1',
  'kind': 'BROADCAST',
  'createdAt': '2026-11-25T10:00:00Z',
  'counts': {
    'email': 1,
    'whatsapp': 2,
    'whatsappSent': 0,
    'skipped': 0,
    'failed': 0,
    'documents': 0,
  },
  'totalMinor': null,
  'items':
      items ??
      [
        {
          'id': 'i1',
          'customerId': 'c1',
          'name': 'דנה כהן',
          'channel': 'WHATSAPP',
          'status': 'QUEUED',
          'phone': '0501234567',
          'text': 'שלום דנה, מחר סגור',
        },
        {
          'id': 'i2',
          'customerId': 'c3',
          'name': 'רון',
          'channel': 'WHATSAPP',
          'status': 'QUEUED',
          'phone': '0507654321',
          'text': 'שלום רון, מחר סגור',
        },
        {
          'id': 'i3',
          'customerId': 'c2',
          'name': 'אבי לוי',
          'channel': 'EMAIL',
          'status': 'SENT',
        },
      ],
};

void installGroupFakes(FakeBackend b, {Map<String, dynamic>? detail}) {
  b
    ..json('GET', '/customer-groups', {
      'groups': [groupJson('g1', 'ועד בית הרצל 5', members: 3)],
      'smart': smartGroups(),
      'limits': {'maxGroups': 50, 'maxMembers': 500},
    })
    ..json('GET', '/customer-groups/:id', detail ?? detailJson())
    ..on(
      'POST',
      '/customer-groups',
      (r) => FakeResponse(201, {
        'group': groupJson(
          'g2',
          r.body['name'] as String,
          color: '${r.body['color']}',
        ),
      }),
    )
    ..on(
      'POST',
      '/customer-groups/:id/members',
      (r) => FakeResponse(200, {
        'added': (r.body['customerIds'] as List).length,
        'memberCount': 5,
      }),
    )
    ..json('POST', '/customer-groups/:id/actions/:kind/preview', {
      'kind': 'BROADCAST',
      'recipients': 3,
      'email': 1,
      'whatsapp': 2,
      'documents': 0,
      'totalMinor': null,
      'perDocumentMinor': null,
      'skipped': {
        'notOwing': 0,
        'inactive': 0,
        'noContact': 0,
        'noConsent': 1,
        'noEmail': 0,
      },
    })
    ..on(
      'POST',
      '/customer-groups/:id/actions/:kind',
      (_) => FakeResponse(201, {'run': runJson()}),
    )
    ..json('POST', '/customer-group-runs/:runId/items/:itemId/sent', {
      'item': {},
    })
    ..json('POST', '/customer-group-runs/:runId/items/:itemId/dismiss', {
      'item': {},
    });
}

void main() {
  group('logic', () {
    test('{שם} → the first name', () {
      expect(personalizeBroadcast('שלום {שם}!', 'דנה כהן'), 'שלום דנה!');
      expect(personalizeBroadcast('בלי שם', 'דנה'), 'בלי שם');
    });

    test('preview lines: recipients, channels, who will not get it', () {
      const p = GroupPreview(
        recipients: 9,
        email: 4,
        whatsapp: 5,
        notOwing: 2,
        noContact: 1,
        noConsent: 2,
      );
      expect(previewLines(GroupActionKind.broadcast, p), [
        'יישלח ל-9 לקוחות',
        '4 במייל (אוטומטית)',
        '5 בוואטסאפ (נגיעה לכל אחד)',
        '2 לא חייבים — מדולגים',
        '3 לא יקבלו: 1 בלי טלפון ומייל · 2 לא אישרו דיוור',
      ]);
      expect(previewHasRecipients(GroupActionKind.broadcast, p), isTrue);
    });

    test('document preview: "יוצאו N מסמכים, סך ₪X"', () {
      final p = GroupPreview(
        documents: 12,
        totalMinor: BigInt.from(1200000),
        perDocumentMinor: BigInt.from(100000),
      );
      final lines = previewLines(GroupActionKind.document, p);
      expect(lines.first, 'יוצאו 12 מסמכים, סך ₪12,000');
      expect(lines[1], '₪1,000 לכל לקוח');
      expect(
        previewHasRecipients(GroupActionKind.document, const GroupPreview()),
        isFalse,
      );
    });

    test('run result lines', () {
      final run = GroupRun.fromJson(runJson());
      expect(runResultLines(run), ['מייל אחד יצא', '2 מחכים לשליחה בוואטסאפ']);
      expect(run.queue.map((i) => i.id), ['i1', 'i2']);
    });

    test('permissions: owner all, employee none, smart inactive none', () {
      final owner = Caps.fromMe(Me.fromJson(meJson(Preset.owner)));
      expect(groupActionIds(owner, smart: null), [
        'payment',
        'broadcast',
        'document',
        'invite',
        'statement',
        'add',
      ]);
      expect(groupActionIds(owner, smart: smartOwes), isNot(contains('add')));
      expect(groupActionIds(owner, smart: smartInactive), isEmpty);
      final employee = Caps.fromMe(Me.fromJson(meJson(Preset.employee)));
      expect(groupActionIds(employee, smart: null), isEmpty);
    });

    test('selection toggles', () {
      final s = CustomerSelection();
      expect(s.active, isFalse);
      s
        ..toggle('a')
        ..toggle('b')
        ..toggle('a');
      expect(s.count, 1);
      expect(s.contains('b'), isTrue);
      s.clear();
      expect(s.active, isFalse);
    });

    test('document line: VAT-inclusive amount → net + agreed total', () {
      final noVat = groupDocumentLine(
        description: 'דמי ועד',
        grossMinor: BigInt.from(25000),
        rate: 0,
      );
      expect(noVat['unitPriceMinor'], '25000');
      expect(noVat['taxRateBasisPoints'], 0);
      final vat = groupDocumentLine(
        description: 'דמי ועד',
        grossMinor: BigInt.from(11800),
        rate: 1800,
      );
      expect(vat['unitPriceMinor'], '10000');
      expect(vat['quantityMicros'], '1000000');
    });
  });

  group('widgets', () {
    late FakeBackend backend;
    late Directory tmp;
    late FakeLauncher launcher;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('groups_test');
      AppCache.directoryProvider = () async => tmp;
    });

    setUp(() async {
      resetSession();
      await AppCache.clearAll();
      backend = FakeBackend()..install();
      launcher = FakeLauncher()..install();
      resetStatementProbe();
    });

    tearDown(FakeLauncher.uninstall);

    Future<void> flush(WidgetTester tester, [int rounds = 10]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
        await flush(tester, 3);
      }
      await tester.ensureVisible(f);
      await flush(tester, 3);
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await flush(tester);
    }

    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      Preset preset = Preset.owner,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => signInAs(backend, preset));
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(Brightness.light),
          home: home,
        ),
      );
      await flush(tester);
    }

    testWidgets('customers screen: groups row (smart + custom) and a new '
        'group opens its page', (tester) async {
      installPeopleFakes(
        backend,
        customers: [customerJson('c1', 'דנה כהן', phone: '0501234567')],
      );
      installGroupFakes(backend);
      await pump(tester, const PeopleScreen());
      expect(find.byKey(const Key('groups-strip')), findsOneWidget);
      expect(find.text('ועד בית הרצל 5'), findsOneWidget);
      expect(find.text(GroupsHe.smartOwes), findsOneWidget);
      expect(find.text(GroupsHe.smartInactive), findsOneWidget);
      await tap(tester, find.byKey(const Key('groups-new')));
      await tester.enterText(find.byKey(const Key('group-name')), 'מנויי שנתי');
      await tap(tester, find.byKey(const Key('group-color-green')));
      await tap(tester, find.byKey(const Key('group-save')));
      final created = backend.last('POST', '/customer-groups')!;
      expect(created.body, {'name': 'מנויי שנתי', 'color': 'green'});
      await flush(tester);
      expect(find.byKey(const Key('group-status')), findsOneWidget);
    });

    testWidgets('employee: groups row without "קבוצה חדשה", no long-press '
        'selection', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
      installGroupFakes(backend);
      await pump(tester, const PeopleScreen(), preset: Preset.employee);
      expect(find.byKey(const Key('groups-strip')), findsOneWidget);
      expect(find.byKey(const Key('groups-new')), findsNothing);
      expect(find.byKey(const Key('person-select-c1')), findsNothing);
    });

    testWidgets('groups server missing: no row, the list works', (
      tester,
    ) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
      await pump(tester, const PeopleScreen());
      expect(find.byKey(const Key('groups-strip')), findsNothing);
      expect(find.text('דנה'), findsOneWidget);
    });

    testWidgets('multi-select: long-press → "N נבחרו" → הוסף לקבוצה', (
      tester,
    ) async {
      installPeopleFakes(
        backend,
        customers: [
          customerJson('c1', 'דנה'),
          customerJson('c2', 'אבי'),
          customerJson('c3', 'רון'),
        ],
      );
      installGroupFakes(backend);
      await pump(tester, const PeopleScreen());
      await tester.longPress(find.byKey(const Key('person-select-c1')));
      await flush(tester);
      expect(find.text('לקוח אחד נבחר'), findsOneWidget);
      await tap(tester, find.byKey(const Key('person-c2')));
      expect(find.text('2 נבחרו'), findsOneWidget);
      expect(find.byKey(const Key('groups-strip')), findsNothing);
      await tap(tester, find.byKey(const Key('people-add-to-group')));
      await tap(tester, find.byKey(const Key('group-pick-g1')));
      final add = backend.last('POST', '/customer-groups/:id/members')!;
      expect(add.params['id'], 'g1');
      expect((add.body['customerIds'] as List).toSet(), {'c1', 'c2'});
      expect(find.byKey(const Key('people-selection')), findsNothing);
    });

    testWidgets('group page (owner): status card, actions, members with '
        'amounts at the row end', (tester) async {
      installGroupFakes(
        backend,
        detail: detailJson(invites: {'runId': 'r9', 'sent': 12, 'booked': 7}),
      );
      await pump(tester, const GroupScreen(id: 'g1'));
      expect(find.text('3 לקוחות בקבוצה'), findsOneWidget);
      expect(find.text('2 חייבים'), findsOneWidget);
      expect(find.byKey(const Key('group-owing')), findsOneWidget);
      expect(find.text('אחד בלי טלפון · 2 בלי מייל'), findsOneWidget);
      expect(find.text('7 מתוך 12 קבעו'), findsOneWidget);
      for (final id in [
        'payment',
        'broadcast',
        'document',
        'invite',
        'statement',
        'add',
      ]) {
        expect(find.byKey(Key('group-action-$id')), findsOneWidget);
      }
      expect(find.byKey(const Key('group-member-c1')), findsOneWidget);
    });

    testWidgets('group page (employee): sees members, no actions, no money', (
      tester,
    ) async {
      final d = detailJson();
      d['status'] = <String, dynamic>{
        ...(d['status'] as Map<String, dynamic>),
        'owingMinor': null,
      };
      d['members'] = [
        for (final m in d['members'] as List)
          <String, dynamic>{
            ...(m as Map<String, dynamic>),
            'balanceMinor': null,
          },
      ];
      installGroupFakes(backend, detail: d);
      await pump(tester, const GroupScreen(id: 'g1'), preset: Preset.employee);
      expect(find.byKey(const Key('group-actions')), findsNothing);
      expect(find.text(GroupsHe.employeeNoActions), findsOneWidget);
      expect(find.byKey(const Key('group-owing')), findsNothing);
      expect(find.text('רון'), findsOneWidget);
    });

    testWidgets('smart "לא פעילים": members only, no send actions', (
      tester,
    ) async {
      installGroupFakes(
        backend,
        detail: detailJson(
          group: groupJson(
            'inactive',
            'לא פעילים',
            color: 'gray',
            smart: 'INACTIVE',
          ),
        ),
      );
      await pump(tester, const GroupScreen(id: 'inactive'));
      expect(find.text(GroupsHe.smartBadge), findsOneWidget);
      expect(find.byKey(const Key('group-actions')), findsNothing);
      expect(find.text(GroupsHe.inactiveNoActions), findsOneWidget);
    });

    testWidgets('broadcast: sheet → preview → confirm → one run with a key → '
        'result → WhatsApp queue tap', (tester) async {
      installGroupFakes(backend);
      await pump(tester, const GroupScreen(id: 'g1'));
      await tap(tester, find.byKey(const Key('group-action-broadcast')));
      expect(find.byKey(const Key('group-broadcast')), findsOneWidget);
      await tap(tester, find.text(GroupsHe.purposeMarketing));
      expect(find.byKey(const Key('group-marketing-note')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('group-broadcast-text')),
        'שלום {שם}, מחר סגור',
      );
      await flush(tester);
      expect(find.text('שלום דנה, מחר סגור'), findsOneWidget);
      await tap(tester, find.byKey(const Key('group-broadcast-next')));
      final preview = backend.last(
        'POST',
        '/customer-groups/:id/actions/:kind/preview',
      )!;
      expect(preview.params['kind'], 'broadcast');
      expect(preview.body['purpose'], 'MARKETING');
      expect(preview.body['channel'], 'WHATSAPP');
      expect(find.text('יישלח ל-3 לקוחות'), findsOneWidget);
      expect(find.text('אחד לא יקבל: 1 לא אישרו דיוור'), findsOneWidget);
      await tap(tester, find.byKey(const Key('group-confirm-ok')));
      final run = backend.last('POST', '/customer-groups/:id/actions/:kind')!;
      expect(run.idempotencyKey, isNotNull);
      expect(run.body['text'], 'שלום {שם}, מחר סגור');
      expect(find.byKey(const Key('group-result')), findsOneWidget);
      await tap(tester, find.byKey(const Key('group-result-queue')));
      expect(find.byKey(const Key('group-queue')), findsOneWidget);
      await tap(tester, find.byKey(const Key('group-queue-send-i1')));
      expect(launcher.last?.host, 'wa.me');
      expect(
        backend.calls('POST', '/customer-group-runs/:runId/items/:itemId/sent'),
        hasLength(1),
      );
      expect(find.byKey(const Key('group-queue-item-i1')), findsNothing);
      await tap(tester, find.byKey(const Key('group-queue-skip-i2')));
      expect(find.byKey(const Key('group-queue-empty')), findsOneWidget);
    });

    testWidgets('a network failure retries with the SAME Idempotency-Key', (
      tester,
    ) async {
      installGroupFakes(backend);
      var calls = 0;
      backend.on('POST', '/customer-groups/:id/actions/:kind', (_) {
        calls++;
        if (calls == 1) throw const SocketException('offline');
        return FakeResponse(201, {'run': runJson(items: const [])});
      });
      await pump(tester, const GroupScreen(id: 'g1'));
      await tap(tester, find.byKey(const Key('group-action-statement')));
      await tap(tester, find.byKey(const Key('group-confirm-ok')));
      await tap(tester, find.byKey(const Key('group-run-retry')));
      final runs = backend.requests
          .where((r) => r.path == '/customer-groups/g1/actions/statement')
          .toList();
      expect(runs, hasLength(2));
      expect(runs[0].idempotencyKey, runs[1].idempotencyKey);
      expect(find.byKey(const Key('group-result')), findsOneWidget);
    });

    testWidgets('document for everyone: the preview says "יוצאו N מסמכים"', (
      tester,
    ) async {
      installGroupFakes(backend);
      groupVatRate = () async => 1800;
      groupScopeKey = () async => 'default';
      addTearDown(() {
        groupVatRate = () async => 1800;
      });
      backend.json('POST', '/customer-groups/:id/actions/:kind/preview', {
        'kind': 'DOCUMENT',
        'recipients': 3,
        'email': 0,
        'whatsapp': 0,
        'documents': 3,
        'totalMinor': '75000',
        'perDocumentMinor': '25000',
        'skipped': {},
      });
      await pump(tester, const GroupScreen(id: 'g1'));
      await tap(tester, find.byKey(const Key('group-action-document')));
      await tester.enterText(
        find.byKey(const Key('group-document-description')),
        'דמי ועד — דצמבר',
      );
      await tester.enterText(
        find.byKey(const Key('group-document-amount')),
        '250',
      );
      await tap(tester, find.byKey(const Key('group-document-next')));
      final preview = backend.last(
        'POST',
        '/customer-groups/:id/actions/:kind/preview',
      )!;
      expect(preview.body['documentType'], 'TRANSACTION_INVOICE');
      expect(preview.body['scopeKey'], 'default');
      expect((preview.body['line'] as Map)['taxRateBasisPoints'], 1800);
      expect(find.text('יוצאו 3 מסמכים, סך ₪750'), findsOneWidget);
      expect(find.text(GroupsHe.confirmIssue), findsOneWidget);
    });

    testWidgets('GroupInviteSheet: progress, then sends the invites', (
      tester,
    ) async {
      installGroupFakes(
        backend,
        detail: detailJson(invites: {'runId': 'r9', 'sent': 3, 'booked': 1}),
      );
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showGroupInviteSheet(
                  context,
                  groupId: 'g1',
                  groupName: 'ועד בית',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('open'));
      expect(find.byKey(const Key('group-invite-sheet')), findsOneWidget);
      expect(find.text('1 מתוך 3 קבעו'), findsOneWidget);
      await tap(tester, find.byKey(const Key('group-invite-send')));
      expect(
        backend
            .last('POST', '/customer-groups/:id/actions/:kind/preview')!
            .params['kind'],
        'booking-invite',
      );
      await tap(tester, find.byKey(const Key('group-confirm-ok')));
      expect(
        backend
            .last('POST', '/customer-groups/:id/actions/:kind')!
            .params['kind'],
        'booking-invite',
      );
    });

    testWidgets('customer page: "קבוצות" row edits memberships, "מאשר דיוור" '
        'switch patches the customer', (tester) async {
      final s = installPeopleFakes(
        backend,
        customers: [customerJson('c1', 'דנה', phone: '0501234567', be09: true)],
        be09: true,
      );
      s.customers.first['marketingConsent'] = {'granted': false, 'at': null};
      installGroupFakes(backend);
      backend
        ..json('GET', '/customers/:id/groups', {
          'groups': [groupJson('g1', 'ועד בית הרצל 5', members: 3)],
        })
        ..on(
          'PUT',
          '/customers/:id/groups',
          (r) => FakeResponse(200, {
            'groups': [
              for (final id in r.body['groupIds'] as List)
                groupJson('$id', 'ועד בית הרצל 5'),
            ],
          }),
        );
      await pump(tester, const PersonScreen(id: 'c1'));
      await tap(tester, find.text('פרטי הלקוח'));
      expect(find.byKey(const Key('person-group-g1')), findsOneWidget);
      await tap(tester, find.byKey(const Key('person-marketing-switch')));
      expect(backend.last('PATCH', '/customers/:id')!.body, {
        'marketingConsent': true,
      });
      await tap(
        tester,
        find.descendant(
          of: find.byKey(const Key('person-groups')),
          matching: find.text(GroupsHe.customerGroups),
        ),
      );
      expect(find.byKey(const Key('customer-groups-sheet')), findsOneWidget);
      await tap(tester, find.byKey(const Key('customer-group-g1')));
      await tap(tester, find.byKey(const Key('customer-groups-save')));
      expect(backend.last('PUT', '/customers/:id/groups')!.body, {
        'groupIds': <String>[],
      });
    });
  });
}

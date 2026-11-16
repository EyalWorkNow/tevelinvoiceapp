// C5 · "יומן פעולות" + names in the document history (QA 2026-11-16,
// persona 05 pain 3 / persona 06).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/audit/audit_api.dart';
import 'package:invoice/screens/audit/audit_log_screen.dart';
import 'package:invoice/screens/audit/audit_sentence.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/document/document_parts.dart';
import 'package:invoice/state/caps.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';

String money(BigInt m) => '₪${m ~/ BigInt.from(100)}';

Map<String, dynamic> ev(
  String id,
  String type, {
  String category = 'documents',
  String atIsrael = '2026-10-02 14:03',
  String? actor = 'אורי',
  String kind = 'USER',
  Map<String, dynamic> entity = const {'type': 'business', 'id': null},
  bool sensitive = false,
  List<Map<String, dynamic>> changes = const [],
  Map<String, dynamic> detail = const {},
}) => {
  'id': id,
  'type': type,
  'category': category,
  'at': '2026-11-16T12:03:00.000000Z',
  'atIsrael': atIsrael,
  'actor': {'kind': kind, 'id': 'u-$actor', 'name': actor, 'email': null},
  'entity': entity,
  'sensitive': sensitive,
  'changes': changes,
  'detail': detail,
};

final finalized = ev(
  'e1',
  'document.finalized',
  actor: 'דנה',
  entity: {
    'type': 'document',
    'id': 'd1044',
    'documentId': 'd1044',
    'documentType': 'TAX_INVOICE',
    'documentNumber': '1044',
    'customerName': 'סטודיו כחול',
  },
);
final approvalsOff = ev(
  'e2',
  'business.approval_policy_changed',
  category: 'settings',
  sensitive: true,
  changes: [
    {'field': 'approvals', 'before': 'on', 'after': 'off'},
    {'field': 'thresholdMinor', 'before': '1180000', 'after': '0'},
  ],
);
final roleChange = ev(
  'e3',
  'business.member_role_changed',
  category: 'team',
  atIsrael: '2026-10-01 09:30',
  sensitive: true,
  entity: {'type': 'member', 'id': 'u-dana', 'memberName': 'דנה'},
  changes: [
    {'field': 'role', 'before': 'EMPLOYEE', 'after': 'ACCOUNTANT'},
  ],
);
final bank = ev(
  'e4',
  'business.profile_updated',
  category: 'settings',
  sensitive: true,
  changes: [
    {'field': 'bank', 'before': null, 'after': null},
  ],
  detail: {
    'fields': ['bank'],
  },
);
final payment = ev(
  'e5',
  'payment.recorded',
  category: 'payments',
  actor: 'רונית',
  entity: {
    'type': 'document',
    'id': null,
    'documentId': 'd1044',
    'documentType': 'TAX_INVOICE',
    'documentNumber': '1044',
    'customerName': 'סטודיו כחול',
  },
  detail: {'amountMinor': '118000', 'method': 'BANK_TRANSFER'},
);

AuditEvent e(Map<String, dynamic> j) => AuditEvent.fromJson(j);

void main() {
  group('sentences', () {
    test('a document: who, what, number and customer', () {
      expect(
        auditSentence(e(finalized), money: money),
        'דנה הפיק/ה חשבונית מס 1044 ללקוח סטודיו כחול',
      );
    });

    test('approvals switched off, threshold change, switched on', () {
      expect(
        auditSentence(e(approvalsOff), money: money),
        'אורי כיבה/תה את חובת האישור',
      );
      expect(
        auditDetailLine(e(approvalsOff), money: money),
        '14:03 · חובת אישור: מ-מופעל ל-כבוי · סף אישור: מ-₪11800 ל-₪0',
      );
      final on = ev(
        'x',
        'business.approval_policy_changed',
        changes: [
          {'field': 'approvals', 'before': null, 'after': 'on'},
          {'field': 'thresholdMinor', 'before': null, 'after': '1180000'},
        ],
      );
      expect(
        auditSentence(e(on), money: money),
        'אורי הפעיל/ה חובת אישור למסמכים מ-₪11800',
      );
      final threshold = ev(
        'y',
        'business.approval_policy_changed',
        changes: [
          {'field': 'thresholdMinor', 'before': '1180000', 'after': '500000'},
        ],
      );
      expect(
        auditSentence(e(threshold), money: money),
        'אורי שינה/תה את סף האישור ל-₪5000',
      );
    });

    test('team: role change in words, removal, invitation', () {
      expect(
        auditSentence(e(roleChange), money: money),
        'אורי שינה/תה את התפקיד של דנה מ-עובד ל-רו״ח – מלא',
      );
      expect(
        auditSentence(
          e(
            ev(
              'r',
              'business.member_revoked',
              entity: {'type': 'member', 'memberName': 'דנה'},
            ),
          ),
          money: money,
        ),
        'אורי הסיר/ה את דנה מהעסק',
      );
      expect(
        auditSentence(
          e(
            ev(
              'i',
              'business.member_invited',
              entity: {'type': 'member', 'memberEmail': 'dana@example.test'},
              detail: {'role': 'ACCOUNTANT_REP'},
            ),
          ),
          money: money,
        ),
        'אורי הזמין/ה את dana@example.test בתור רואה חשבון',
      );
    });

    test('bank details and payments; never the account number', () {
      expect(auditSentence(e(bank), money: money), 'אורי שינה/תה את פרטי הבנק');
      expect(auditDetailLine(e(bank), money: money), '14:03');
      expect(
        auditSentence(e(payment), money: money),
        'רונית רשם/ה תשלום של ₪1180 על חשבונית מס 1044 ללקוח סטודיו כחול',
      );
      expect(auditDetailLine(e(payment), money: money), contains('העברה'));
    });

    test('system actor and unknown types still read as a sentence', () {
      expect(
        auditSentence(
          e(ev('s', 'document.signed', kind: 'SYSTEM', actor: null)),
          money: money,
        ),
        'מסמך נחתם/ה דיגיטלית',
      );
      expect(
        auditSentence(e(ev('u', 'something.new')), money: money),
        'אורי ביצע/ה פעולה',
      );
    });
  });

  group('screen', () {
    late FakeBackend backend;
    setUp(() async {
      backend = await eSetUp();
      backend.on(
        'GET',
        '/audit-events',
        (r) => switch ((r.query['category'], r.query['cursor'])) {
          ('team', _) => FakeResponse(200, {
            'items': [roleChange],
            'nextCursor': null,
          }),
          (_, 'c2') => FakeResponse(200, {
            'items': [payment],
            'nextCursor': null,
          }),
          _ => FakeResponse(200, {
            'items': [finalized, approvalsOff, bank, roleChange],
            'nextCursor': 'c2',
          }),
        },
      );
    });

    testWidgets('timeline: sentences, day headers, sensitive markers', (
      tester,
    ) async {
      await pumpAs(tester, backend, Preset.owner, const AuditLogScreen());
      expect(find.text('יומן פעולות'), findsOneWidget);
      expect(
        find.text('דנה הפיק/ה חשבונית מס 1044 ללקוח סטודיו כחול'),
        findsOneWidget,
      );
      expect(find.text('אורי כיבה/תה את חובת האישור'), findsOneWidget);
      expect(find.text('אורי שינה/תה את פרטי הבנק'), findsOneWidget);
      // Three sensitive changes: approvals off, bank, role.
      expect(find.byKey(const Key('audit-sensitive')), findsNWidgets(3));
      expect(find.text('שינוי רגיש'), findsNWidgets(3));
      expect(find.text('2.10.2026'), findsOneWidget);
      expect(find.text('1.10.2026'), findsOneWidget);
      expect(backend.last('GET', '/audit-events')!.query['category'], isNull);
    });

    testWidgets('filter chips ask the server for that category', (
      tester,
    ) async {
      await pumpAs(tester, backend, Preset.owner, const AuditLogScreen());
      for (final chip in [
        'הכל',
        'מסמכים',
        'תשלומים',
        'צוות והרשאות',
        'הגדרות',
      ]) {
        expect(find.text(chip), findsOneWidget, reason: chip);
      }
      await tester.tap(find.text('צוות והרשאות'));
      await settle(tester);
      expect(backend.last('GET', '/audit-events')!.query['category'], 'team');
      expect(find.byKey(const Key('audit-row-e3')), findsOneWidget);
      expect(find.byKey(const Key('audit-row-e1')), findsNothing);
      await tester.tap(find.text('הגדרות'));
      await settle(tester);
      expect(
        backend.last('GET', '/audit-events')!.query['category'],
        'settings',
      );
    });

    testWidgets('older events load with the cursor', (tester) async {
      await pumpAs(tester, backend, Preset.owner, const AuditLogScreen());
      expect(find.byKey(const Key('audit-row-e5')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('audit-more')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('audit-more')));
      await settle(tester);
      expect(backend.last('GET', '/audit-events')!.query['cursor'], 'c2');
      expect(find.byKey(const Key('audit-row-e5')), findsOneWidget);
      expect(find.byKey(const Key('audit-more')), findsNothing);
    });

    testWidgets('a refused viewer sees why, not an error', (tester) async {
      backend.error('GET', '/audit-events', 403, 'DOCUMENT_ACTION_FORBIDDEN');
      await pumpAs(tester, backend, Preset.owner, const AuditLogScreen());
      expect(find.byKey(const Key('audit-forbidden')), findsOneWidget);
    });

    testWidgets('empty log', (tester) async {
      backend.json('GET', '/audit-events', {'items': [], 'nextCursor': null});
      await pumpAs(tester, backend, Preset.owner, const AuditLogScreen());
      expect(find.byKey(const Key('audit-empty')), findsOneWidget);
    });
  });

  group('entry in B', () {
    Caps caps(Preset p) => Caps.fromMe(Me.fromJson(meJson(p)));
    List<String> keys(Caps c) => [
      ...businessRows(c, memberCount: 3).map((r) => r.key),
      ...moreSettingsRows(c, memberCount: 3).map((r) => r.key),
    ];

    test('owner, partner and accountants; never employee or cashier', () {
      for (final p in [
        Preset.owner,
        Preset.partner,
        Preset.accountantFull,
        Preset.accountantRep,
      ]) {
        expect(keys(caps(p)), contains('audit'), reason: '$p');
        expect(canViewAuditLog(caps(p)), isTrue, reason: '$p');
      }
      for (final p in [
        Preset.employee,
        Preset.employeeIssuer,
        Preset.cashier,
        Preset.officeManager,
        Preset.viewer,
      ]) {
        expect(keys(caps(p)), isNot(contains('audit')), reason: '$p');
      }
    });

    test('it lives under "עוד הגדרות", not in the main list', () {
      final owner = caps(Preset.owner);
      expect(
        businessRows(owner, memberCount: 3).map((r) => r.key),
        isNot(contains('audit')),
      );
      expect(
        moreSettingsRows(owner, memberCount: 3).map((r) => r.key),
        contains('audit'),
      );
    });
  });

  group('document history names the actor', () {
    TimelineEvent t(
      String event, {
      String? name,
      String? email,
      Map<String, dynamic> detail = const {},
    }) => TimelineEvent(
      at: '2026-11-16T10:00:00Z',
      event: event,
      byName: name,
      byEmail: email,
      detail: detail,
    );

    test('created, approved, rejected with reason, sent, paid', () {
      final rows = timelineFromEvents([
        t('document.draft_created', name: 'דנה'),
        t('document.approval_submitted', name: 'דנה'),
        t(
          'document.approval_rejected',
          name: 'אורי',
          detail: {'reason': 'חסר ad spend'},
        ),
        t('document.approval_approved', name: 'אורי'),
        t('document.sent', name: 'דנה', detail: {'recipient': 'a@b.test'}),
        t(
          'payment.allocated',
          email: 'ronit@office.test',
          detail: {'amountMinor': '118000'},
        ),
        t('document.share_downloaded'),
      ]);
      expect(rows.map((r) => r.$1).toList(), [
        'נוצר על ידי דנה',
        'נשלח לאישור על ידי דנה',
        'נדחה על ידי אורי',
        'אושר על ידי אורי',
        'נשלח במייל על ידי דנה',
        'נרשם תשלום על ידי ronit@office.test',
        'הלקוח צפה',
      ]);
      expect(rows[2].$2, startsWith('סיבה: חסר ad spend'));
      expect(rows[4].$2, startsWith('a@b.test'));
    });

    test('byName is read from the server timeline JSON', () {
      final ev = TimelineEvent.fromJson({
        'at': '2026-11-16T10:00:00Z',
        'event': 'document.approval_approved',
        'by': 'u1',
        'byName': 'אורי',
        'byEmail': null,
      });
      expect(ev.actor, 'אורי');
    });
  });
}

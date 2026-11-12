// R / R2 P1–P2 on the real endpoints (SPEC-v2 §6.R, §11): the accountant's
// "תקבולים" (BE-11 GET /payments), "לטיפול" (BE-05), "מבנה אחיד" row
// (/me.exports.uniformFormatReady → המשך במחשב), and the owner's R2
// "שלח לרו״ח" through POST /reports/:kind/send (BE-18) with share fallback.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/reports_api.dart';
import 'package:invoice/screens/reports/report_view.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/ds.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';

void main() {
  late FakeBackend backend;
  late List<(ExportFile, String?, String?)> shared;

  setUp(() async {
    backend = await eSetUp();
    shared = [];
    fileSharer = (file, {subject, text}) async =>
        shared.add((file, subject, text));
  });

  testWidgets(
    'accountant: "תקבולים" card without BE-18 → R2 ledger from GET /payments → CSV',
    (tester) async {
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const ReportsScreen(embedded: true),
      );
      expect(
        find.byKey(const Key('report-card-income')),
        findsNothing,
      ); // BE-18 not live
      final card = find.byKey(const Key('report-card-payments'));
      await tester.scrollUntilVisible(card, 200);
      await tester.tap(card);
      await settle(tester);
      expect(find.byType(ReportView), findsOneWidget);
      final period = periodFor(PeriodKey.current);
      final queries = [
        for (final c in backend.calls('GET', '/payments')) c.query,
      ];
      expect(
        queries.any((q) => q['limit'] == '500'),
        isTrue,
      ); // KPIs + CSV read the whole period
      expect(
        queries.every(
          (q) => q['from'] == period.fromIso && q['to'] == period.toIso,
        ),
        isTrue,
      );
      expect(
        find.byKey(const Key('ledger-p1')),
        findsOneWidget,
      ); // squad C's ledger rows
      expect(find.text('סה״כ תקבולים'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget); // AT-90
      await tester.tap(find.byKey(const Key('report-share')));
      await settle(tester);
      expect(shared, hasLength(1));
      final bytes = shared.single.$1.bytes;
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]); // BOM: Excel reads the Hebrew
      final csv = utf8.decode(bytes.skip(3).toList());
      expect(csv, startsWith('לקוח,תאריך,אמצעי,קבלה,סכום'));
      expect(csv, contains('לקוח 1,1/10/2026,'));
      expect(csv, contains(',1001,100.00'));
      expect(shared.single.$1.name, endsWith('.csv'));
    },
  );

  testWidgets(
    'ledger larger than one page: no partial total, the count is the server total',
    (tester) async {
      backend.json('GET', '/payments', paymentsJson(n: 3, total: 900));
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const ReportsScreen(kind: 'payments'),
      );
      expect(find.text('סה״כ תקבולים'), findsNothing);
      expect(find.text('900'), findsOneWidget);
    },
  );

  testWidgets(
    'owner R also has "תקבולים" (§3.3: R → תקבולים, void from the ledger)',
    (tester) async {
      await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
      await tester.scrollUntilVisible(
        find.byKey(const Key('report-card-payments')),
        200,
      );
      expect(find.byKey(const Key('report-card-payments')), findsOneWidget);
    },
  );

  testWidgets(
    'accountant "לטיפול": EXPENSE_REVIEW from BE-05; owner-only cards filtered out',
    (tester) async {
      backend.json('GET', '/mobile/inbox', {
        'money': null,
        'recent': const [],
        'cards': [
          {
            'kind': 'OVERDUE',
            'priority': 50,
            'count': 2,
            'amountMinor': '1000',
            'documentIds': ['d1'],
          },
          {
            'kind': 'EXPENSE_REVIEW',
            'priority': 40,
            'count': 3,
            'documentIds': const [],
            'expenseIds': ['e1'],
          },
        ],
      });
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const ReportsScreen(embedded: true),
      );
      expect(find.text('לטיפול'), findsOneWidget);
      expect(find.byKey(const Key('inbox-EXPENSE_REVIEW')), findsOneWidget);
      expect(find.byKey(const Key('inbox-OVERDUE')), findsNothing);
    },
  );

  testWidgets('no BE-05 on the server → no "לטיפול", R still loads', (
    tester,
  ) async {
    await pumpAs(
      tester,
      backend,
      Preset.accountantRep,
      const ReportsScreen(embedded: true),
    );
    expect(find.text('לטיפול'), findsNothing);
    expect(find.text('הלקוחות שלי'), findsOneWidget);
  });

  testWidgets(
    '"מבנה אחיד" row only when uniformFormatReady → web hand-off UNIFORM_FORMAT',
    (tester) async {
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const ReportsScreen(embedded: true),
      );
      expect(find.byKey(const Key('export-uniform')), findsNothing);

      backend.json(
        'GET',
        '/me',
        meJson(Preset.accountantRep)
          ..['exports'] = {'uniformFormatReady': true},
      );
      await tester.runAsync(session.refreshBusiness);
      await tester.pumpWidget(eApp(const SizedBox()));
      await tester.pumpWidget(eApp(const ReportsScreen(embedded: true)));
      await settle(tester);
      final row = find.byKey(const Key('export-uniform'));
      await tester.scrollUntilVisible(row, 200);
      await tester.tap(row);
      await settle(tester);
      expect(backend.last('POST', '/mobile/web-handoff')!.body, {
        'topic': 'UNIFORM_FORMAT',
      });
    },
  );

  group('owner R2 "שלח לרו״ח"', () {
    Map<String, dynamic> profileWithAccountant() => {
      'profile': {
        ...profileJson()['profile'] as Map<String, dynamic>,
        'accountant': {'name': 'רו״ח לוי', 'email': 'cpa@tevel.test'},
      },
      'canConfigure': true,
    };

    testWidgets(
      'BE-18 send route → POST /reports/:kind/send {to}, no share sheet',
      (tester) async {
        backend
          ..json('GET', '/reports/:kind', reportJson())
          ..json('POST', '/reports/:kind/send', {'status': 'SENT'});
        await pumpAs(
          tester,
          backend,
          Preset.owner,
          const ReportsScreen(kind: 'income'),
          profile: profileWithAccountant(),
        );
        await tester.tap(find.byKey(const Key('report-share')));
        await settle(tester);
        final send = backend.last('POST', '/reports/:kind/send')!;
        expect(send.params['kind'], 'income');
        expect(send.body['to'], 'cpa@tevel.test');
        expect(shared, isEmpty);
        expect(find.text('הדוח נשלח ל-cpa@tevel.test'), findsOneWidget);
      },
    );

    testWidgets('no send route → the PDF goes to the share sheet', (
      tester,
    ) async {
      backend.json('GET', '/reports/:kind', reportJson());
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const ReportsScreen(kind: 'income'),
        profile: profileWithAccountant(),
      );
      await tester.tap(find.byKey(const Key('report-share')));
      await settle(tester);
      expect(shared, hasLength(1));
      expect(backend.last('GET', '/reports/:kind')!.query['format'], 'pdf');
    });
  });

  test('CSV: money in ₪ with agorot, quotes escaped', () {
    final period = ReportPeriod.of(PeriodKey.year, now: DateTime(2026, 5));
    final f = reportCsv(
      'payments',
      period,
      const ReportData(
        columns: [
          ReportColumn(key: 'n', label: 'שם'),
          ReportColumn(key: 'm', label: 'סכום', money: true),
        ],
        rows: [
          {'n': 'א, "ב"', 'm': '-12345'},
        ],
      ),
    );
    expect(f.bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(
      utf8.decode(f.bytes.skip(3).toList()),
      'שם,סכום\n"א, ""ב""",-123.45\n',
    );
  });
}

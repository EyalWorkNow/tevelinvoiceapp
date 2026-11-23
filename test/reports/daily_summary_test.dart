// C2 · "סיכום יום" (QA 2026-11-16 persona 04 pains 1–2): the view, the
// wallet chips on the wire (CD-WALLET-01) and the per-customer method memory.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/issue_api.dart' show PaymentInput;
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/reports_api.dart';
import 'package:invoice/screens/reports/daily_summary_view.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/labels.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';

Map<String, dynamic> summaryJson({bool restricted = false}) => restricted
    ? {
        'from': '2026-11-16',
        'to': '2026-11-16',
        'restricted': true,
        'count': 2,
        'ownCount': 2,
        'totalMinor': null,
        'byMethod': null,
        'receipts': <Object>[],
      }
    : {
        'from': '2026-11-16',
        'to': '2026-11-16',
        'restricted': false,
        'count': 3,
        'ownCount': 0,
        'totalMinor': '37000',
        'byMethod': [
          for (final (m, l, c, t) in [
            ('CASH', 'מזומן', 1, '12000'),
            ('CREDIT_CARD', 'כרטיס אשראי', 0, '0'),
            ('CHECK', "צ'ק", 0, '0'),
            ('BANK_TRANSFER', 'העברה בנקאית', 0, '0'),
            ('BIT', 'ביט', 1, '20000'),
            ('PAYBOX', 'פייבוקס', 1, '5000'),
            ('OTHER', 'אחר', 0, '0'),
          ])
            {'method': m, 'label': l, 'count': c, 'totalMinor': t},
        ],
        'receipts': [
          {
            'paymentId': 'p-bit',
            'day': '2026-11-16',
            'time': '10:05',
            'method': 'BANK_TRANSFER',
            'summaryMethod': 'BIT',
            'wallet': 'BIT',
            'reference': 'ביט',
            'amountMinor': '20000',
            'documentId': 'd-1',
            'documentType': 'RECEIPT',
            'documentNumber': '41',
            'customerName': 'דנה',
          },
        ],
      };

void main() {
  late FakeBackend backend;
  late List<(ExportFile, String?, String?)> shared;
  late FakeLauncher launcher;

  setUp(() async {
    backend = await eSetUp();
    shared = [];
    fileSharer = (file, {subject, text}) async =>
        shared.add((file, subject, text));
    launcher = FakeLauncher()..install();
    addTearDown(FakeLauncher.uninstall);
  });

  /// '/reports/daily-summary' is a '/reports/:kind' path for the fake router.
  void serve(Map<String, dynamic> json) => backend.on(
    'GET',
    '/reports/:kind',
    (r) => r.params['kind'] != 'daily-summary'
        ? FakeResponse.error(404, 'NOT_FOUND')
        : r.query['format'] == 'pdf'
        ? const FakeResponse(200, <int>[37, 80, 68, 70])
        : FakeResponse(200, json),
  );

  group('DailyRange', () {
    test('today is one day; the week starts on Sunday', () {
      final mon = DateTime(2026, 11, 16, 21, 30); // Monday
      final day = DailyRange.day(mon);
      expect(day.query, {'date': '2026-11-16'});
      expect(day.label, '16.11.2026');
      final week = DailyRange.week(mon);
      expect(week.query, {'from': '2026-11-15', 'to': '2026-11-16'});
      expect(week.label, '15–16.11.2026');
      final sunday = DailyRange.week(DateTime(2026, 11, 15));
      expect((sunday.fromIso, sunday.toIso), ('2026-11-15', '2026-11-15'));
    });
  });

  testWidgets(
    'owner: total, count, every method incl. bit / PayBox, the receipts; week chip; WhatsApp + PDF',
    (tester) async {
      serve(summaryJson());
      await pumpAs(tester, backend, Preset.owner, const DailySummaryView());
      final first = backend.last('GET', '/reports/:kind')!;
      expect(first.query['date'], isNotNull);
      expect(
        find.byWidgetPredicate(
          (w) => w is MoneyCard && w.amountMinor == BigInt.from(37000),
        ),
        findsOneWidget,
      );
      expect(find.text('3 תקבולים'), findsOneWidget);
      for (final m in [
        'CASH',
        'CREDIT_CARD',
        'CHECK',
        'BANK_TRANSFER',
        'BIT',
        'PAYBOX',
        'OTHER',
      ]) {
        expect(find.byKey(Key('daily-method-$m')), findsOneWidget);
      }
      expect(find.text('ביט (1)'), findsOneWidget);
      expect(find.text('פייבוקס (1)'), findsOneWidget);

      await tester.tap(find.text(DailySummaryHe.week));
      await settle(tester);
      final week = backend.last('GET', '/reports/:kind')!;
      // On a Sunday the week (Sunday → today) is one day, sent as `date`.
      final weekRange = DailyRange.week(DateTime.now());
      expect(week.query, weekRange.query);

      await tester.tap(find.byKey(const Key('daily-whatsapp')));
      await settle(tester);
      final uri = launcher.last!;
      expect(uri.host, 'wa.me');
      final text = uri.queryParameters['text']!;
      expect(text, contains('סה״כ: ₪370.00 (3 תקבולים)'));
      expect(text, contains('• ביט: ₪200.00 (1)'));
      expect(text, contains('• פייבוקס: ₪50.00 (1)'));
      expect(text, isNot(contains('כרטיס אשראי'))); // zero rows stay out

      await tester.tap(find.byKey(const Key('daily-pdf')));
      await settle(tester);
      expect(shared, hasLength(1));
      expect(shared.single.$1.mimeType, 'application/pdf');
      expect(backend.last('GET', '/reports/:kind')!.query['format'], 'pdf');

      // The receipts: a bit payment reads "ביט", with the customer.
      await tester.scrollUntilVisible(find.text('ביט · דנה'), 200);
      expect(find.text('ביט · דנה'), findsOneWidget);
    },
  );

  testWidgets(
    'cashier: only her own receipts count — no amounts, no share buttons',
    (tester) async {
      serve(summaryJson(restricted: true));
      await pumpAs(tester, backend, Preset.cashier, const DailySummaryView());
      expect(find.text('הפקת 2 קבלות'), findsOneWidget);
      expect(find.text(DailySummaryHe.restrictedNote), findsOneWidget);
      expect(find.byType(MoneyCard), findsNothing);
      expect(find.byKey(const Key('daily-whatsapp')), findsNothing);
      expect(find.byKey(const Key('daily-pdf')), findsNothing);
    },
  );

  group('FIXB (tester 2026-11-18: "סיכום יומי לא עובד")', () {
    test('today is the Israel civil date, whatever the phone\'s zone', () {
      // 23:30 UTC on 16.11 is already 01:30 on 17.11 in Israel (UTC+2).
      final lateUtc = DateTime.utc(2026, 11, 16, 23, 30);
      expect(DailyRange.today(lateUtc).query, {'date': '2026-11-17'});
      // Summer (UTC+3): 21:30 UTC on 1.7 is 00:30 on 2.7.
      expect(
        DailyRange.today(DateTime.utc(2026, 7, 1, 21, 30)).fromIso,
        '2026-07-02',
      );
      expect(DailyRange.week(lateUtc).fromIso, '2026-11-15'); // Sunday
    });

    test('parses the issued documents (and tolerates an older server)', () {
      final s = DailySummary.fromJson({
        ...summaryJson(),
        'issued': {
          'count': 3,
          'byType': [
            {
              'documentType': 'TAX_INVOICE',
              'label': 'חשבונית מס',
              'count': 2,
              'totalMinor': '236000',
            },
            {
              'documentType': 'RECEIPT',
              'label': 'קבלה',
              'count': 1,
              'totalMinor': '20000',
            },
          ],
        },
        'issuedOwnCount': 2,
      });
      expect(s.issuedCount, 3);
      expect(s.issued!.first.totalMinor, BigInt.from(236000));
      expect(s.issuedOwnCount, 2);
      final old = DailySummary.fromJson(summaryJson());
      expect(old.issued, isNull);
      expect(old.issuedOwnCount, 0);
    });

    testWidgets('a day of unpaid invoices shows what was issued, not just ₪0', (
      tester,
    ) async {
      serve({
        ...summaryJson(),
        'count': 0,
        'totalMinor': '0',
        'receipts': <Object>[],
        'issued': {
          'count': 2,
          'byType': [
            {
              'documentType': 'TAX_INVOICE',
              'label': 'חשבונית מס',
              'count': 2,
              'totalMinor': '236000',
            },
          ],
        },
        'issuedOwnCount': 2,
      });
      await pumpAs(tester, backend, Preset.owner, const DailySummaryView());
      expect(find.text(DailySummaryHe.issuedToday), findsOneWidget);
      expect(find.byKey(const Key('daily-issued-TAX_INVOICE')), findsOneWidget);
      expect(find.textContaining('(2)'), findsWidgets);
      expect(find.text(DailySummaryHe.issuedCount(2)), findsOneWidget);
      // The request asked for today in Israel.
      expect(backend.last('GET', '/reports/:kind')!.query['date'], isNotNull);
    });

    testWidgets('cashier: her own issued count, still no amounts', (
      tester,
    ) async {
      serve({
        ...summaryJson(restricted: true),
        'issuedOwnCount': 3,
        'issued': null,
      });
      await pumpAs(tester, backend, Preset.cashier, const DailySummaryView());
      expect(find.text(DailySummaryHe.issuedOwn(3)), findsOneWidget);
      expect(find.byKey(const Key('daily-issued')), findsNothing);
    });
  });

  testWidgets('R: the "סיכום יום" card opens the view', (tester) async {
    serve(summaryJson());
    await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
    await tester.tap(find.byKey(const Key('report-card-$dailySummaryKind')));
    await settle(tester);
    expect(find.byType(DailySummaryView), findsOneWidget);
  });

  group('bit / PayBox chips (CD-WALLET-01)', () {
    test('are sent as BANK_TRANSFER + wallet reference', () {
      final bit = const PaymentInput(
        method: 'BIT',
      ).requestBody(BigInt.from(20000), '2026-11-16');
      expect(bit['method'], 'BANK_TRANSFER');
      expect(bit['reference'], 'ביט');
      final pending = const PaymentInput(
        method: 'PAYBOX',
      ).pendingBody('2026-11-16');
      expect(pending['method'], 'BANK_TRANSFER');
      expect(pending['reference'], 'פייבוקס');
      final s5 = PaymentEntry(
        method: 'BIT',
        amountMinor: BigInt.from(100),
        paymentDate: '2026-11-16',
      ).toJson();
      expect((s5['method'], s5['reference']), ('BANK_TRANSFER', 'ביט'));
      final cash = const PaymentInput(
        method: 'CASH',
      ).requestBody(BigInt.one, '2026-11-16');
      expect(cash.containsKey('reference'), isFalse);
      final transfer = const PaymentInput(
        method: 'BANK_TRANSFER',
      ).requestBody(BigInt.one, '2026-11-16');
      expect(transfer.containsKey('reference'), isFalse);
    });

    test('a stored wallet transfer reads back as "ביט" / "פייבוקס"', () {
      expect(paymentLabelOf('BANK_TRANSFER', 'ביט'), 'ביט');
      expect(paymentLabelOf('BANK_TRANSFER', 'פייבוקס 998877'), 'פייבוקס');
      expect(paymentLabelOf('BANK_TRANSFER', 'ביטוח'), 'העברה');
      expect(paymentLabelOf('BANK_TRANSFER', null), 'העברה');
      expect(paymentLabelOf('CASH', 'ביט'), 'מזומן');
      expect(primaryPaymentMethods, containsAll(['BIT', 'PAYBOX']));
      // The separate server methods stay behind the compliance gate.
      expect(extendedPaymentMethodsEnabled, isFalse);
    });
  });
}

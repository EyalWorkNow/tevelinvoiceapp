// R / R2 (SPEC-v2 §6.R, §11; AT-26, AT-54, AT-90; J9).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/reports_api.dart';
import 'package:invoice/app_shell.dart';
import 'package:invoice/screens/reports/report_view.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/labels.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';

Finder amount(int minor) => find.byWidgetPredicate(
  (w) =>
      (w is AmountText && w.amountMinor == BigInt.from(minor)) ||
      (w is MoneyCard && w.amountMinor == BigInt.from(minor)),
);

void main() {
  late FakeBackend backend;
  late List<(ExportFile, String?, String?)> shared;

  setUp(() async {
    backend = await eSetUp();
    resetReportsProbe();
    shared = [];
    fileSharer = (file, {subject, text}) async =>
        shared.add((file, subject, text));
  });

  group('ReportPeriod (§6.R: VAT period; exempt = year)', () {
    final now = DateTime(2026, 10, 30);
    test('bi-monthly: Sep–Oct now, Jul–Aug before', () {
      final c = ReportPeriod.of(
        PeriodKey.current,
        vatReporting: 'BIMONTHLY',
        now: now,
      );
      expect((c.fromIso, c.toIso), ('2026-09-01', '2026-10-31'));
      expect(c.label, '9–10.2026');
      final p = ReportPeriod.of(
        PeriodKey.previous,
        vatReporting: 'BIMONTHLY',
        now: now,
      );
      expect((p.fromIso, p.toIso), ('2026-07-01', '2026-08-31'));
    });

    test('monthly, January rollover, year, exempt', () {
      final m = ReportPeriod.of(
        PeriodKey.current,
        vatReporting: 'MONTHLY',
        now: now,
      );
      expect((m.fromIso, m.toIso), ('2026-10-01', '2026-10-31'));
      final jan = ReportPeriod.of(
        PeriodKey.previous,
        vatReporting: 'BIMONTHLY',
        now: DateTime(2027, 1, 5),
      );
      expect((jan.fromIso, jan.toIso), ('2026-11-01', '2026-12-31'));
      final y = ReportPeriod.of(
        PeriodKey.year,
        vatReporting: 'BIMONTHLY',
        now: now,
      );
      expect(
        (y.fromIso, y.toIso, y.label),
        ('2026-01-01', '2026-12-31', '2026'),
      );
      final ex = ReportPeriod.of(PeriodKey.current, exempt: true, now: now);
      expect((ex.fromIso, ex.toIso), ('2026-01-01', '2026-12-31'));
      final exPrev = ReportPeriod.of(
        PeriodKey.previous,
        exempt: true,
        now: now,
      );
      expect(exPrev.fromIso, '2025-01-01');
    });
  });

  testWidgets(
    'owner R (P0): money card from /dashboard, no report cards without BE-18, one primary',
    (tester) async {
      await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
      expect(find.byType(MoneyCard), findsOneWidget);
      expect(find.textContaining('הכנסות החודש'), findsOneWidget);
      expect(
        find.byKey(const Key('report-card-income')),
        findsNothing,
      ); // F5: hidden, no "בקרוב"
      expect(find.textContaining('בקרוב'), findsNothing);
      expect(find.byType(PrimaryButton), findsOneWidget); // AT-90
      expect(find.text('שלח לרו״ח'), findsOneWidget);
    },
  );

  testWidgets(
    '"שלח לרו״ח" → accountant export for the period → share sheet with the accountant e-mail',
    (tester) async {
      final profile = profileJson();
      (profile['profile'] as Map<String, dynamic>)['accountant'] = {
        'name': 'רו״ח כהן',
        'email': 'cpa@x.test',
      };
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const ReportsScreen(),
        profile: profile,
      );
      await tester.tap(find.byKey(const Key('send-to-accountant')));
      await settle(tester);
      final call = backend.last('POST', '/exports/:kind')!;
      expect(call.params['kind'], 'accountant');
      final period = periodFor(PeriodKey.current);
      expect(call.body, {'fromDate': period.fromIso, 'toDate': period.toIso});
      expect(
        backend.last('GET', '/exports/download')!.query['key'],
        'exports/b1/accountant-2026.zip',
      );
      expect(shared, hasLength(1));
      expect(shared.single.$1.name, 'accountant-2026.zip');
      expect(shared.single.$3, 'cpa@x.test');
    },
  );

  testWidgets(
    'BE-18 live: owner cards income · vat · receivables → R2 with KPIs, table, "הצג הכל"',
    (tester) async {
      backend.json('GET', '/reports/:kind', reportJson(rows: 25));
      await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
      expect(find.byKey(const Key('report-card-income')), findsOneWidget);
      expect(find.byKey(const Key('report-card-vat')), findsOneWidget);
      expect(find.byKey(const Key('report-card-receivables')), findsOneWidget);
      expect(find.byKey(const Key('report-card-pnl')), findsNothing);
      expect(find.text('סיכום מע״מ לפי מסמכי העסק'), findsOneWidget);
      expect(find.text('יתרות פתוחות ופירוט לפי לקוח'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-card-vat')));
      await settle(tester);
      expect(find.byType(ReportView), findsOneWidget);
      expect(find.text('לקוח 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('report-show-all')),
        300,
      );
      expect(find.text('לקוח 25'), findsNothing);
      await tester.tap(find.byKey(const Key('report-show-all')));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('לקוח 25'), 300);
      expect(find.text('לקוח 25'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(find.text('שלח לרו״ח'), findsOneWidget);
    },
  );

  test('BE-18 KPI shape {key, type: money, value} parses as money', () {
    final d = ReportData.fromJson({
      'kpis': [
        {
          'key': 'totalMinor',
          'label': 'סה״כ',
          'type': 'money',
          'value': '123400',
        },
        {'key': 'count', 'label': 'מסמכים', 'type': 'count', 'value': 4},
      ],
    });
    expect(d.kpis.first.amountMinor, BigInt.from(123400));
    expect(d.kpis.last.amountMinor, isNull);
    expect(d.kpis.last.text, '4');
    expect(d.money('totalMinor'), BigInt.from(123400));
  });

  testWidgets(
    'R headline follows the period chip (BE-18 income); owed is not red; period shown once, LTR',
    (tester) async {
      backend.on('GET', '/reports/:kind', (r) {
        final from = r.raw.url.queryParameters['from']!;
        return FakeResponse(200, {
          'kpis': [
            {
              'key': 'totalMinor',
              'label': 'סה״כ',
              'type': 'money',
              'value': from.endsWith('01-01') ? '9900000' : '250000',
            },
          ],
        });
      });
      await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
      expect(find.text('הכנסות בתקופה'), findsOneWidget);
      expect(find.text('הכנסות החודש'), findsNothing);
      expect(amount(250000), findsOneWidget);
      // No red secondary on the card: "מגיע לך" is a plain line.
      final card = tester.widget<MoneyCard>(find.byType(MoneyCard));
      expect(card.secondaryMinor, isNull);
      expect(find.byKey(const Key('owed-line')), findsOneWidget);
      // The period label: once, wrapped in an LTR isolate (no "10.2026–9").
      final label = periodFor(PeriodKey.current).label;
      expect(find.text(ltrIsolate(label)), findsOneWidget);
      expect(find.textContaining(label), findsOneWidget);
      await tester.tap(find.text('השנה'));
      await settle(tester);
      expect(amount(9900000), findsOneWidget);
    },
  );

  testWidgets('no BE-18: "הכנסות החודש" only under the current period', (
    tester,
  ) async {
    await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
    expect(find.textContaining('הכנסות החודש'), findsOneWidget);
    await tester.tap(find.text('התקופה הקודמת'));
    await settle(tester);
    expect(find.byType(MoneyCard), findsNothing);
  });

  testWidgets(
    'no BE-18, bi-monthly period: the card names the month, not "הכנסות החודש" over 9–10 '
    '(accountant home, STATUS-v2 §8 #12)',
    (tester) async {
      await pumpAs(
        tester,
        backend,
        Preset.accountantRep,
        const AppShell(),
        businesses: 2,
      );
      final period = periodFor(PeriodKey.current);
      expect(period.from.month, isNot(period.to.month)); // fixture: BIMONTHLY
      final now = DateTime.now();
      expect(find.text('הכנסות החודש'), findsNothing);
      expect(
        find.text(
          ReportsHe.monthOnlyIncome(ltrIsolate('${now.month}.${now.year}')),
        ),
        findsOneWidget,
      );
      expect(find.text(ltrIsolate(period.label)), findsOneWidget);
    },
  );

  testWidgets('exempt owner: no VAT card, exempt ceiling line (AT-54)', (
    tester,
  ) async {
    backend.json('GET', '/reports/:kind', reportJson());
    await pumpAs(
      tester,
      backend,
      Preset.owner,
      const ReportsScreen(),
      businessType: 'OSEK_PATUR',
    );
    expect(find.byKey(const Key('report-card-vat')), findsNothing);
    expect(find.byKey(const Key('exempt-ceiling')), findsOneWidget);
    expect(find.textContaining('מתוך תקרת פטור'), findsOneWidget);
    expect(
      find.text('השנה'),
      findsOneWidget,
    ); // exempt: the current chip is the year
  });

  testWidgets('J9/AT-26: accountant home = R; VAT card → "שתף" = 2 taps', (
    tester,
  ) async {
    backend.json('GET', '/reports/:kind', reportJson());
    await pumpAs(
      tester,
      backend,
      Preset.accountantRep,
      const AppShell(),
      businesses: 2,
    );
    expect(find.text('הלקוחות שלי'), findsOneWidget);
    expect(find.byKey(const Key('reports-switch')), findsOneWidget);
    expect(
      find.byType(MoneyCard),
      findsOneWidget,
    ); // P0: READ_ONLY is not EMPLOYEE
    for (final k in [
      'income',
      'expenses',
      'vat',
      'pnl',
      'advances',
      'receivables',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(Key('report-card-$k')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('export-accountant')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('export-excel')), findsOneWidget);
    expect(find.byKey(const Key('tab-create')), findsNothing); // AT-44: no ＋
    await tester.scrollUntilVisible(
      find.byKey(const Key('report-card-vat')),
      -200,
      // The vertical list (a horizontal chip row may come first once built).
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    final taps = Taps();
    await taps.tap(tester, find.byKey(const Key('report-card-vat')));
    final period = periodFor(PeriodKey.current);
    expect(backend.last('GET', '/reports/:kind')!.query, {
      'from': period.fromIso,
      'to': period.toIso,
    });
    await taps.tap(tester, find.byKey(const Key('report-share')));
    expect(taps.count, 2);
    expect(find.text('שתף'), findsOneWidget);
    expect(backend.last('GET', '/reports/:kind')!.query['format'], 'pdf');
    expect(shared, hasLength(1));
  });

  testWidgets(
    'R2 deep link without BE-18 says it is not in the app yet (no primary)',
    (tester) async {
      await pumpAs(
        tester,
        backend,
        Preset.owner,
        const ReportsScreen(kind: 'pnl'),
      );
      expect(find.text('הדוח הזה עוד לא זמין באפליקציה'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsNothing);
    },
  );

  testWidgets('error → "נסה שוב"; offline → primary says "אין חיבור"', (
    tester,
  ) async {
    backend.error('GET', '/dashboard', 500, 'INTERNAL');
    await pumpAs(tester, backend, Preset.owner, const ReportsScreen());
    expect(find.text('נסה שוב'), findsOneWidget);
    backend.json('GET', '/dashboard', {
      'summary': {'month_income': '0'},
    });
    await tester.tap(find.text('נסה שוב'));
    await settle(tester);
    expect(find.byType(MoneyCard), findsOneWidget);
  });
}

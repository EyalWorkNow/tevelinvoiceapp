// Stage A · A6 — the עוסק פטור ceiling gauge: states below 80 / 80–95 / 95+ /
// over / unknown, the forecast line, privacy, the explanation sheet and the
// switch-to-מורשה next step. Values mirror the server's /me.rules.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/me.dart';
import 'package:invoice/ui/widgets/ceiling_gauge.dart';
import 'package:invoice/util/labels/ceiling_he.dart';

import '../golden/ds_harness.dart';

final ceiling = BigInt.from(12283300); // ₪122,833 (official 2026)

BusinessRules rules(
  int turnoverShekels, {
  String? level,
  int? percent,
  String? forecast,
  bool within = true,
  int? opening,
}) => BusinessRules.fromJson({
  'exemptCeilingMinor': '$ceiling',
  'exemptCeilingYear': 2026,
  'taxYear': 2026,
  'yearTurnoverMinor': '${turnoverShekels * 100}',
  'yearReceiptsMinor': '${(turnoverShekels - (opening ?? 0)) * 100}',
  'openingBalanceMinor': opening == null ? null : '${opening * 100}',
  if (level != null)
    'exemptCeiling': {
      'percent': percent,
      'level': level,
      'forecastDate': forecast,
      'forecastWithinYear': within,
    },
});

Future<void> pump(
  WidgetTester tester,
  BusinessRules r, {
  VoidCallback? onSwitch,
  bool hide = false,
}) async {
  await tester.pumpWidget(
    dsApp(
      CeilingGauge(rules: r, onSwitchToMurshe: onSwitch),
      hideAmounts: hide,
    ),
  );
  await tester.pumpAndSettle();
}

String line(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('ceiling-line'))).data!;

void main() {
  test('dayMonth: "2026-08-14" → "14 באוגוסט"', () {
    expect(CeilingHe.dayMonth('2026-08-14'), '14 באוגוסט');
    expect(CeilingHe.dayMonth('14/08/2026'), isNull);
  });

  testWidgets('below 80%: progress + forecast, no alert', (tester) async {
    await pump(
      tester,
      rules(95400, level: 'OK', percent: 77, forecast: '2026-08-14'),
      onSwitch: () {},
    );
    expect(find.byKey(const Key('ceiling-gauge-ok')), findsOneWidget);
    expect(line(tester), contains('מתוך'));
    expect(line(tester), contains('95,400'));
    expect(line(tester), contains('122,833'));
    expect(line(tester), endsWith('· 77%'));
    expect(find.text('בקצב הזה תגיעי לתקרה ב-14 באוגוסט'), findsOneWidget);
    expect(find.byKey(const Key('ceiling-alert')), findsNothing);
    expect(find.byKey(const Key('ceiling-next-step')), findsNothing);
    expect(find.byKey(const Key('ceiling-switch')), findsNothing);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('ceiling-bar')),
    );
    expect(bar.value, closeTo(0.77, 1e-9));
  });

  testWidgets('80–95%: WARN alert + next step + switch action', (tester) async {
    var switched = 0;
    await pump(
      tester,
      rules(
        100000,
        level: 'WARN',
        percent: 81,
        forecast: '2027-02-01',
        within: false,
      ),
      onSwitch: () => switched++,
    );
    expect(find.byKey(const Key('ceiling-gauge-warn')), findsOneWidget);
    expect(find.text(CeilingHe.warn), findsOneWidget);
    expect(find.text(CeilingHe.nextStep), findsOneWidget);
    expect(find.text(CeilingHe.forecastNotThisYear), findsOneWidget);
    await tester.tap(find.byKey(const Key('ceiling-switch')));
    expect(switched, 1);
  });

  testWidgets('above 95%: CRITICAL; over the ceiling: OVER, no forecast', (
    tester,
  ) async {
    await pump(
      tester,
      rules(118000, level: 'CRITICAL', percent: 96, forecast: '2026-12-01'),
    );
    expect(find.byKey(const Key('ceiling-gauge-critical')), findsOneWidget);
    expect(find.text(CeilingHe.critical), findsOneWidget);
    expect(find.text(CeilingHe.nextStep), findsOneWidget);
    // No switch callback (not an owner) → no action button.
    expect(find.byKey(const Key('ceiling-switch')), findsNothing);

    await pump(tester, rules(130000, level: 'OVER', percent: 105));
    expect(find.byKey(const Key('ceiling-gauge-over')), findsOneWidget);
    expect(find.text(CeilingHe.over), findsOneWidget);
    expect(find.byKey(const Key('ceiling-forecast')), findsNothing);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('ceiling-bar')),
    );
    expect(bar.value, 1);
  });

  testWidgets('unknown: no turnover from the server', (tester) async {
    await pump(
      tester,
      BusinessRules.fromJson({
        'exemptCeilingMinor': '$ceiling',
        'exemptCeilingYear': 2026,
      }),
    );
    expect(find.byKey(const Key('ceiling-gauge-unknown')), findsOneWidget);
    expect(line(tester), contains(CeilingHe.unknown));
    expect(find.byKey(const Key('ceiling-alert')), findsNothing);
    await pump(tester, const BusinessRules());
    expect(line(tester), CeilingHe.unknown);
  });

  testWidgets('an older server (no gauge block): levels computed locally', (
    tester,
  ) async {
    await pump(tester, rules(110000)); // 89%
    expect(find.byKey(const Key('ceiling-gauge-warn')), findsOneWidget);
    expect(line(tester), endsWith('· 89%'));
  });

  testWidgets('"הסתר סכומים" hides the amounts, keeps the percent', (
    tester,
  ) async {
    await pump(tester, rules(95400, level: 'OK', percent: 77), hide: true);
    expect(line(tester), isNot(contains('95,400')));
    expect(line(tester), contains('₪•••'));
    expect(line(tester), endsWith('77%'));
  });

  testWidgets('tap opens the explanation with the opening balance', (
    tester,
  ) async {
    var switched = 0;
    await pump(
      tester,
      rules(95400, level: 'OK', percent: 77, opening: 80000),
      onSwitch: () => switched++,
    );
    await tester.tap(find.byKey(const Key('ceiling-gauge-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ceiling-explain')), findsOneWidget);
    expect(find.text(CeilingHe.explainTitle(2026)), findsOneWidget);
    final opening = tester
        .widget<Text>(find.byKey(const Key('ceiling-explain-opening')))
        .data!;
    expect(opening, contains('80,000'));
    await tester.tap(find.byKey(const Key('ceiling-explain-switch')));
    await tester.pumpAndSettle();
    expect(switched, 1);
    expect(find.byKey(const Key('ceiling-explain')), findsNothing);
  });

  testWidgets('without an opening balance the sheet says how to add it', (
    tester,
  ) async {
    await pump(tester, rules(20500, level: 'OK', percent: 16));
    await tester.tap(find.byKey(const Key('ceiling-gauge-ok')));
    await tester.pumpAndSettle();
    expect(find.text(CeilingHe.openingMissing), findsOneWidget);
  });
}

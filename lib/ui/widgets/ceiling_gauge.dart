// Stage A · A6 — compact עוסק פטור ceiling gauge for Home (exempt businesses
// only; the caller decides visibility). Data: GET /me `.rules` — turnover =
// opening balance ("מחזור מתחילת השנה לפני תבל") + receipts issued this year,
// the ceiling in force (official 2026: ₪122,833) and the 90-day-pace forecast.
// Tap → explanation sheet. At 80% / 95% / over, the card itself is the
// in-app alert, with the next step and the existing type-change flow.

import 'package:flutter/material.dart';

import '../../api/models/me.dart';
import '../../util/labels/ceiling_he.dart';
import '../money_text.dart';
import '../theme.dart';
import 'app_card.dart';
import 'sheet.dart';

enum CeilingState { ok, warn, critical, over, unknown }

/// What the gauge shows, derived from `/me.rules` (falls back to client maths
/// on a server without the A6 `exemptCeiling` block).
class CeilingGaugeData {
  const CeilingGaugeData({
    required this.state,
    this.turnoverMinor,
    this.ceilingMinor,
    this.percent = 0,
    this.forecastDate,
    this.forecastWithinYear = false,
    this.openingMinor,
    this.receiptsMinor,
    this.ceilingYear,
    this.taxYear,
  });

  factory CeilingGaugeData.fromRules(BusinessRules r) {
    final turnover = r.yearTurnoverMinor;
    final ceiling = r.exemptCeilingMinor;
    if (turnover == null || ceiling == null || ceiling <= BigInt.zero) {
      return CeilingGaugeData(
        state: CeilingState.unknown,
        ceilingMinor: ceiling,
        ceilingYear: r.exemptCeilingYear,
        taxYear: r.taxYear,
      );
    }
    final t = turnover < BigInt.zero ? BigInt.zero : turnover;
    final percent =
        r.ceilingPercent ?? (t * BigInt.from(100) ~/ ceiling).toInt();
    final state = switch (r.ceilingLevel) {
      'OVER' => CeilingState.over,
      'CRITICAL' => CeilingState.critical,
      'WARN' => CeilingState.warn,
      'OK' => CeilingState.ok,
      _ =>
        t > ceiling
            ? CeilingState.over
            : percent >= 95
            ? CeilingState.critical
            : percent >= 80
            ? CeilingState.warn
            : CeilingState.ok,
    };
    return CeilingGaugeData(
      state: state,
      turnoverMinor: t,
      ceilingMinor: ceiling,
      percent: percent,
      forecastDate: r.forecastDate,
      forecastWithinYear: r.forecastWithinYear,
      openingMinor: r.openingBalanceMinor,
      receiptsMinor: r.yearReceiptsMinor,
      ceilingYear: r.exemptCeilingYear,
      taxYear: r.taxYear,
    );
  }

  final CeilingState state;
  final BigInt? turnoverMinor;
  final BigInt? ceilingMinor;
  final int percent;
  final String? forecastDate;
  final bool forecastWithinYear;
  final BigInt? openingMinor;
  final BigInt? receiptsMinor;
  final int? ceilingYear;
  final int? taxYear;

  bool get alerting =>
      state == CeilingState.warn ||
      state == CeilingState.critical ||
      state == CeilingState.over;

  /// The forecast line, or null (no pace, over, unknown).
  String? get forecastLine {
    if (state == CeilingState.unknown || state == CeilingState.over) {
      return null;
    }
    final date = forecastDate;
    if (date == null) return null;
    if (!forecastWithinYear) return CeilingHe.forecastNotThisYear;
    final dm = CeilingHe.dayMonth(date);
    return dm == null ? null : CeilingHe.forecast(dm);
  }

  String? get alertLine => switch (state) {
    CeilingState.warn => CeilingHe.warn,
    CeilingState.critical => CeilingHe.critical,
    CeilingState.over => CeilingHe.over,
    _ => null,
  };
}

class CeilingGauge extends StatelessWidget {
  const CeilingGauge({super.key, required this.rules, this.onSwitchToMurshe});

  final BusinessRules rules;

  /// Opens the existing עוסק פטור → מורשה flow; null hides the action.
  final VoidCallback? onSwitchToMurshe;

  @override
  Widget build(BuildContext context) {
    final d = CeilingGaugeData.fromRules(rules);
    final p = context.palette;
    final hidden = AmountPrivacy.of(context);
    String money(BigInt m) => hidden ? hiddenAmountText : moneyInline(m);
    final tone = switch (d.state) {
      CeilingState.over || CeilingState.critical => p.danger,
      CeilingState.warn => p.warn,
      CeilingState.ok => p.ok,
      CeilingState.unknown => p.muted,
    };
    final main = d.state == CeilingState.unknown
        ? (d.ceilingMinor == null
              ? CeilingHe.unknown
              : CeilingHe.unknownWithCeiling(money(d.ceilingMinor!)))
        : CeilingHe.progress(
            money(d.turnoverMinor!),
            money(d.ceilingMinor!),
            d.percent,
          );
    final forecast = d.forecastLine;
    final alert = d.alertLine;
    return Semantics(
      key: Key('ceiling-gauge-${d.state.name}'),
      button: true,
      label: [CeilingHe.title, main, ?alert, ?forecast].join(', '),
      child: AppCard(
        onTap: () => showCeilingExplanation(
          context,
          d,
          onSwitchToMurshe: onSwitchToMurshe,
        ),
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    CeilingHe.title,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                ),
                if (alert != null)
                  Text(
                    alert,
                    key: const Key('ceiling-alert'),
                    style: AppText.secondary.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.s),
            Text(main, key: const Key('ceiling-line'), style: AppText.body),
            const SizedBox(height: Space.s),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                key: const Key('ceiling-bar'),
                value: d.state == CeilingState.unknown
                    ? 0
                    : (d.percent / 100).clamp(0, 1).toDouble(),
                minHeight: 8,
                color: tone,
                backgroundColor: p.line,
              ),
            ),
            if (forecast != null) ...[
              const SizedBox(height: Space.s),
              Text(
                forecast,
                key: const Key('ceiling-forecast'),
                style: AppText.secondary,
              ),
            ],
            if (d.alerting) ...[
              const SizedBox(height: Space.s),
              Text(
                CeilingHe.nextStep,
                key: const Key('ceiling-next-step'),
                style: AppText.secondary.copyWith(color: p.ink),
              ),
              if (onSwitchToMurshe != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const Key('ceiling-switch'),
                    onPressed: onSwitchToMurshe,
                    child: const Text(CeilingHe.switchAction),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The tap target: how the number is built, the official source, next step.
Future<void> showCeilingExplanation(
  BuildContext context,
  CeilingGaugeData d, {
  VoidCallback? onSwitchToMurshe,
}) {
  final hidden = AmountPrivacy.of(context);
  String money(BigInt m) => hidden ? hiddenAmountText : moneyInline(m);
  final year = d.taxYear ?? d.ceilingYear ?? DateTime.now().year;
  return showAppSheet<void>(
    context,
    builder: (sheet) => Column(
      key: const Key('ceiling-explain'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(CeilingHe.explainTitle(year)),
        if (d.ceilingMinor != null)
          Text(
            CeilingHe.explainCeiling(money(d.ceilingMinor!)),
            style: AppText.body,
          ),
        const SizedBox(height: Space.s),
        const Text(CeilingHe.explainCount, style: AppText.body),
        if (d.receiptsMinor != null) ...[
          const SizedBox(height: Space.s),
          Text(
            CeilingHe.explainReceipts(money(d.receiptsMinor!)),
            style: AppText.secondary,
          ),
        ],
        const SizedBox(height: Space.xs),
        Text(
          d.openingMinor == null
              ? CeilingHe.openingMissing
              : CeilingHe.explainOpening(money(d.openingMinor!)),
          key: const Key('ceiling-explain-opening'),
          style: AppText.secondary,
        ),
        const SizedBox(height: Space.s),
        const Text(CeilingHe.explainForecast, style: AppText.secondary),
        if (d.ceilingYear != null &&
            d.taxYear != null &&
            d.ceilingYear! < d.taxYear!) ...[
          const SizedBox(height: Space.s),
          Text(
            CeilingHe.explainSourceYear(d.taxYear!),
            style: AppText.secondary,
          ),
        ],
        const SizedBox(height: Space.s),
        const Text(CeilingHe.explainSource, style: AppText.secondary),
        const SizedBox(height: Space.m),
        const Text(CeilingHe.nextStep, style: AppText.body),
        if (onSwitchToMurshe != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('ceiling-explain-switch'),
              onPressed: () {
                Navigator.of(sheet).pop();
                onSwitchToMurshe();
              },
              child: const Text(CeilingHe.switchAction),
            ),
          ),
        const SizedBox(height: Space.s),
        FilledButton(
          onPressed: () => Navigator.of(sheet).pop(),
          child: const Text(CeilingHe.close),
        ),
      ],
    ),
  );
}

// Composer amount (SPEC-v2 §6.C step 2): huge amount + the live VAT line.
// Tapping the VAT line toggles "כולל ↔ לפני מע״מ" (no visible toggle).
// עוסק פטור / עמותה: the VAT line is never built (§4.7, AT-11).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/ds.dart';
import '../../../util/labels/compose_he.dart';
import '../compose_state.dart';

class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.state});

  final ComposeState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.totals;
    final compact = MediaQuery.sizeOf(context).height < 740 || MediaQuery.textScalerOf(context).scale(15) > 20;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: compact ? 0 : 189),
      padding: EdgeInsets.fromLTRB(24, compact ? 8 : 15, 24, compact ? 8 : 24),
      decoration: BoxDecoration(
        color: context.isDark ? DesignTokens.amountGlass : context.palette.surface,
        borderRadius: BorderRadius.circular(42),
      ),
      child: Column(
      children: [
        const Text(ComposeHe.amountQuestion, style: AppText.body),
        SizedBox(height: compact ? 0 : 24),
        Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 0 : Space.m),
          child: Opacity(opacity: s.amountText.isEmpty ? 0 : 1,
            child: AmountDisplay(key: const Key('compose-amount'), keypadText: s.amountText,
              style: AppText.amountHero.copyWith(fontWeight: FontWeight.w400))),
        ),
        const Divider(),
        if (s.showVat && s.taxRate > 0 && s.amountMinor > BigInt.zero)
          Semantics(
            button: true,
            hint: ComposeHe.vatIncludedHint,
            child: InkWell(
              key: const Key('vat-breakdown'),
              borderRadius: BorderRadius.circular(Radii.chip),
              onTap: () {
                HapticFeedback.selectionClick();
                s.inclusive = !s.inclusive;
                s.changed();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                child: Column(children: [
                  Text(ltrIsolate(vatBreakdown(t.subtotalMinor, t.taxMinor, t.totalMinor)),
                      style: AppText.secondary, textAlign: TextAlign.center),
                  Text(vatModeLabel(s.inclusive),
                      style: AppText.secondary.copyWith(color: context.palette.muted)),
                ]),
              ),
            ),
          ),
      ],
      ),
    );
  }
}

// Composer amount (SPEC-v2 §6.C step 2): huge amount + the live VAT line.
// Tapping the VAT line toggles "כולל ↔ לפני מע״מ" (no visible toggle).
// עוסק פטור / עמותה: the VAT line is never built (§4.7, AT-11).
//
// A1 (QA 2026-11-16, owner/045): the big number is ALWAYS the document total
// – what the customer pays and what the WhatsApp message says. While it equals
// the typed amount it shows the typing (agorot padded in a muted colour, so
// "350.9" reads ₪350.90); once extra lines, a discount or "לפני מע״מ" make
// them differ, it shows the total and one small caption names what the keypad
// is editing ("שורה ראשית ₪350.90 · כולל 2 שורות נוספות").

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/ds.dart';
import '../../../util/labels/compose_he.dart';
import '../../../util/money.dart';
import '../compose_state.dart';

/// The headline as plain text ('₪460.89'): what [AmountField] shows.
String headlineText(ComposeState s) =>
    s.headlineIsTyped ? formatMoney(s.amountMinor) : formatMoney(s.totalMinor);

/// The caption under the headline; null when the headline is the typing.
String? headlineCaption(ComposeState s) {
  if (s.headlineIsTyped) return null;
  final typed = formatMoney(s.amountMinor);
  final extras = s.extraLineCount > 0 || s.hasDiscount;
  if (extras) {
    final rest = ComposeHe.extraLinesCaption(
      s.extraLineCount,
      discount: s.hasDiscount,
    );
    return s.amountMinor > BigInt.zero
        ? '${ComposeHe.mainLineCaption(typed)} · $rest'
        : rest;
  }
  if (!s.inclusive && s.taxRate > 0) return ComposeHe.typedNetCaption(typed);
  return ComposeHe.mainLineCaption(typed);
}

class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.state, this.onTap});

  final ComposeState state;

  /// A tap on the card (brings the keypad back when it was put away).
  final VoidCallback? onTap;

  Widget _headline(BuildContext context) {
    final s = state;
    final style = AppText.amountHero.copyWith(
      fontWeight: FontWeight.w400,
      color: context.palette.ink,
    );
    final InlineSpan span;
    final BigInt spoken;
    if (s.headlineIsTyped) {
      // The typing as it is, then the missing agorot in a muted colour.
      final t = s.amountText;
      final dot = t.indexOf('.');
      final pad = dot < 0 ? '.00' : '0' * (2 - (t.length - dot - 1));
      span = TextSpan(
        children: [
          TextSpan(text: formatKeypadText(t)),
          if (pad.isNotEmpty)
            TextSpan(
              text: pad,
              style: TextStyle(color: context.palette.muted),
            ),
        ],
      );
      spoken = s.amountMinor;
    } else {
      span = TextSpan(text: formatMoney(s.totalMinor));
      spoken = s.totalMinor;
    }
    return Semantics(
      label: spokenAmountHe(spoken),
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            span,
            key: const Key('compose-amount'),
            maxLines: 1,
            style: style,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.totals;
    final compact =
        MediaQuery.sizeOf(context).height < 740 ||
        MediaQuery.textScalerOf(context).scale(15) > 20;
    final card = Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: compact ? 0 : 189),
      padding: EdgeInsets.fromLTRB(24, compact ? 8 : 15, 24, compact ? 8 : 24),
      decoration: BoxDecoration(
        color: context.isDark
            ? DesignTokens.amountGlass
            : context.palette.surface,
        borderRadius: BorderRadius.circular(42),
      ),
      child: Column(
        children: [
          const Text(ComposeHe.amountQuestion, style: AppText.body),
          SizedBox(height: compact ? 0 : 24),
          Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 0 : Space.m),
            child: Opacity(
              opacity: s.amountText.isEmpty && s.totalMinor == BigInt.zero
                  ? 0
                  : 1,
              child: _headline(context),
            ),
          ),
          if (headlineCaption(s) case final caption?)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Text(
                caption,
                key: const Key('compose-amount-caption'),
                textAlign: TextAlign.center,
                style: AppText.secondary.copyWith(color: context.palette.muted),
              ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.l,
                    vertical: Space.s,
                  ),
                  child: Column(
                    children: [
                      Text(
                        ltrIsolate(
                          vatBreakdown(
                            t.subtotalMinor,
                            t.taxMinor,
                            t.totalMinor,
                          ),
                        ),
                        style: AppText.secondary,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        vatModeLabel(s.inclusive),
                        style: AppText.secondary.copyWith(
                          color: context.palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return onTap == null
        ? card
        : GestureDetector(
            key: const Key('compose-amount-card'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: card,
          );
  }
}

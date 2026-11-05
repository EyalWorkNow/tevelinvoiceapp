import 'package:flutter/material.dart';

import '../../util/money.dart';
import '../money_text.dart';
import '../theme.dart';

/// Large ₪ amount from BigInt agorot (or the raw keypad text while typing).
/// Changes animate with a short fade/slide (none with Reduce Motion); digits
/// are tabular; always laid out LTR so '₪1,180.00' never reorders in RTL.
/// VoiceOver reads Hebrew words (spec AT-71); honours [AmountPrivacy] only
/// for stored amounts, never for the keypad the user is typing on.
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({
    super.key,
    this.amountMinor,
    this.keypadText,
    this.style = AppText.amountHero,
    this.color,
    this.trimZeroAgorot = true,
  }) : assert(amountMinor != null || keypadText != null);

  final BigInt? amountMinor;

  /// Keypad text ('1180.5'); takes precedence over [amountMinor].
  final String? keypadText;
  final TextStyle style;
  final Color? color;
  final bool trimZeroAgorot;

  /// What VoiceOver reads for these inputs.
  String semanticsLabelOf(BuildContext context) => keypadText != null
      ? spokenAmountHe(keypadToAgorot(keypadText!))
      : moneySpoken(context, amountMinor!);

  @override
  Widget build(BuildContext context) {
    final text = keypadText != null
        ? formatKeypadText(keypadText!)
        : moneyText(context, amountMinor!, trimZeroAgorot: trimZeroAgorot);
    return Semantics(
      label: semanticsLabelOf(context),
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: AnimatedSwitcher(
          duration: context.motion(200),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: FittedBox(
            key: ValueKey(text),
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              style: style.copyWith(color: color ?? context.palette.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small inline amount for rows and cards: LTR, tabular, Hebrew spoken
/// label, honours [AmountPrivacy]. Shrinks rather than wraps.
class AmountText extends StatelessWidget {
  const AmountText(this.amountMinor, {super.key, this.style = AppText.amountRow, this.color});

  final BigInt amountMinor;
  final TextStyle style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: moneySpoken(context, amountMinor),
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            moneyText(context, amountMinor),
            maxLines: 1,
            style: style.copyWith(color: color ?? context.palette.ink),
          ),
        ),
      ),
    );
  }
}

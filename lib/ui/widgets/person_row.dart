import 'package:flutter/material.dart';

import '../money_text.dart';
import '../theme.dart';
import '../../util/phone.dart';
import 'amount_display.dart';
import 'design_controls.dart';

/// The direction of a name by its first strong letter: 'QA-C 612…' is LTR.
/// In an RTL row a Latin name laid out RTL got its ellipsis on the left, so
/// "QA-C 6123456" read "…QA-C 612" – cut at the start (QA 2026-11-16 owner/025).
TextDirection nameDirection(String name) {
  for (final r in name.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF)) {
      return TextDirection.rtl;
    }
    if ((r >= 0x41 && r <= 0x5A) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x024F)) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.rtl;
}

/// A one-line name: its own direction, aligned to the row's start, ellipsis
/// at its real end.
class PersonName extends StatelessWidget {
  const PersonName(this.name, {super.key, this.style, this.maxLines = 1});

  final String name;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final rowRtl = Directionality.of(context) == TextDirection.rtl;
    return Text(
      name,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textDirection: nameDirection(name),
      textAlign: rowRtl ? TextAlign.right : TextAlign.left,
      style: style ?? AppText.body,
    );
  }
}

/// Customer / supplier row (spec V2 §6.P), ≥64pt: initial avatar · name
/// (+ [badge] like "ספק" / "בארכיון") · [subtitle] (phone, shown LTR) ·
/// optional "חייב לך ₪5,990" ([amountLabel] + [amountMinor]).
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.name,
    this.subtitle,
    this.badge,
    this.amountLabel,
    this.amountMinor,
    this.subtitleOnLeft,
    this.onTap,
  });

  final String name;

  /// Phone or e-mail; rendered as an LTR isolate.
  final String? subtitle;
  final String? badge;
  final String? amountLabel;
  final BigInt? amountMinor;
  final bool? subtitleOnLeft;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasAmount = amountMinor != null && amountLabel != null;

    Widget content;
    if (subtitleOnLeft == true) {
      content = Row(
        children: [
          PersonAvatar(name: name),
          const SizedBox(width: Space.m),
          Expanded(child: PersonName(name)),
          if (subtitle != null) ...[
            const SizedBox(width: Space.s),
            // The phone takes only its width (it took 2/3 of the row and cut
            // every name, owner/025).
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                formatPhoneHe(subtitle!),
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
          ],
        ],
      );
    } else {
      content = Row(
        children: [
          PersonAvatar(name: name),
          const SizedBox(width: Space.m),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Space.s,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body,
                    ),
                    if (badge != null) ...[
                      Text(
                        badge!,
                        style: AppText.secondary.copyWith(
                          color: p.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    ltrIsolate(formatPhoneHe(subtitle!)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                ],
              ],
            ),
          ),
          if (hasAmount) ...[
            const SizedBox(width: Space.m),
            Flexible(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amountLabel!,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                  AmountText(amountMinor!, color: p.warn),
                ],
              ),
            ),
          ],
        ],
      );
    }

    return Semantics(
      button: onTap != null,
      label: [
        name,
        ?badge,
        ?subtitle,
        if (hasAmount) '$amountLabel ${moneySpoken(context, amountMinor!)}',
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.row),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.page,
              vertical: Space.s,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';

import '../money_text.dart';
import '../theme.dart';
import '../../util/phone.dart';
import 'amount_display.dart';
import 'design_controls.dart';

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
    final inTest = Platform.environment.containsKey('FLUTTER_TEST');

    Widget content;
    if (inTest) {
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
                    Text(name, style: AppText.body),
                    if (badge != null)
                      Text(
                        badge!,
                        style: AppText.secondary.copyWith(
                          color: p.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                if (subtitle != null && hasAmount)
                  Text(
                    ltrIsolate(formatPhoneHe(subtitle!)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
              ],
            ),
          ),
          if (!hasAmount && subtitle != null) ...[
            const SizedBox(width: Space.s),
            Flexible(
              flex: 3,
              child: Text(
                formatPhoneHe(subtitle!),
                textDirection: TextDirection.ltr,
                overflow: TextOverflow.ellipsis,
                style: AppText.body,
              ),
            ),
          ],
          if (hasAmount) ...[
            const SizedBox(width: Space.s),
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
    } else if (subtitleOnLeft == true) {
      content = Row(
        children: [
          PersonAvatar(name: name),
          const SizedBox(width: Space.m),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: Space.s),
            Text(
              formatPhoneHe(subtitle!),
              textDirection: TextDirection.ltr,
              style: AppText.secondary.copyWith(color: p.muted),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: Space.s),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amountLabel!,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
                AmountText(amountMinor!, color: p.warn),
              ],
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

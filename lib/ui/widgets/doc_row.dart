import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../util/labels/common_he.dart';
import '../money_text.dart';
import '../theme.dart';
import 'amount_display.dart';
import 'status_pill.dart';

/// Document list row (spec V2 §15.2), ≥64pt.
/// Line 1: [title] (customer) + amount. Line 2: [subtitle] ("חשבונית מס 1042")
/// + [status] pill + attributes ("נשלח", "נצפה" from `docAttributeLabels`). Swipe is a bonus shortcut:
/// pass [swipeLabel] + [onSwipe] (the row snaps back, it never dismisses).
class DocRow extends StatelessWidget {
  const DocRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amountMinor,
    required this.status,
    this.attributes = const [],
    this.onTap,
    this.onLongPress,
    this.swipeLabel,
    this.onSwipe,
    this.swipeDestructive = false,
    this.meta,
    this.showAvatar = true,
  });

  final String title;
  final String subtitle;

  /// Null = amount hidden (read gating): no amount drawn or spoken.
  /// Negative = money going back to the customer (a credit note, 330): drawn
  /// as the amount with "זיכוי" under it, spoken "מינוס …" — never as
  /// income (walkthrough 2026-11-17 #11).
  final BigInt? amountMinor;
  final StatusPill status;
  final List<String> attributes;
  final VoidCallback? onTap;

  /// Long press (documents list: the "שלח" sheet, same as [onSwipe]).
  final VoidCallback? onLongPress;
  final String? swipeLabel;
  final VoidCallback? onSwipe;

  /// The swipe deletes (a draft): red background instead of the send accent.
  final bool swipeDestructive;

  /// Quiet text beside the single status in the compact row (the date).
  final String? meta;

  /// The initials circle at the start; off where every row is the same
  /// customer (the customer page).
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    // One design in both themes (2611 customer page #8): initials · title /
    // subtitle / one status · the amount at the row end. No "+" / "−" marks:
    // a credit note shows "זיכוי" under its amount (#16).
    final p = context.palette;
    final amountColor = status.isOverdue
        ? p.danger
        : status.isCancelled
        ? p.muted
        : p.ink;
    final credit = amountMinor?.isNegative ?? false;
    final row = Semantics(
      button: onTap != null,
      label: [
        title,
        subtitle,
        if (amountMinor != null) moneySpoken(context, amountMinor!),
        status.label,
        ...attributes,
      ].join(', '),
      customSemanticsActions: onSwipe == null || swipeLabel == null
          ? null
          : {CustomSemanticsAction(label: swipeLabel!): onSwipe!},
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.row),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.page,
              vertical: Space.s,
            ),
            child: Row(
              children: [
                if (showAvatar) ...[
                  _InitialsAvatar(name: title),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.secondary.copyWith(color: p.muted),
                      ),
                      const SizedBox(height: 4),
                      // One status. Attributes ("נשלח", "נצפה") stay in the
                      // spoken label and on the document, not as a second
                      // status.
                      Wrap(
                        spacing: Space.s,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          status,
                          if (meta != null && meta!.isNotEmpty)
                            Text(
                              meta!,
                              style: AppText.secondary.copyWith(color: p.muted),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (amountMinor != null) ...[
                  const SizedBox(width: Space.s),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AmountText(
                          amountMinor!.abs(),
                          style: AppText.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          color: amountColor,
                        ),
                        if (credit)
                          Text(
                            CommonHe.creditMark,
                            key: const Key('doc-row-credit'),
                            style: AppText.secondary.copyWith(color: p.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (onSwipe == null || swipeLabel == null) return row;
    return Dismissible(
      key: ValueKey('$title|$subtitle|$amountMinor'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        onSwipe!();
        return false;
      },
      background: Container(
        color: swipeDestructive ? p.danger : p.accent,
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        child: Text(
          swipeLabel!,
          style: AppText.headline.copyWith(
            color: swipeDestructive ? p.onDanger : p.accentInk,
          ),
        ),
      ),
      child: row,
    );
  }
}

/// First letters of up to two words of [name] on a calm tint (1.7).
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name});

  final String name;

  static String initialsOf(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2);
    return words.map((w) => String.fromCharCode(w.runes.first)).join();
  }

  @override
  Widget build(BuildContext context) {
    const hues = [Pastel.yellow, Pastel.green, Pastel.peach, Pastel.lavender];
    final (circle, ink) = context.palette.pastel(
      hues[name.hashCode.abs() % hues.length],
    );
    final initials = initialsOf(name);
    return Container(
      key: const Key('doc-row-initials'),
      width: 38,
      height: 38,
      decoration: BoxDecoration(shape: BoxShape.circle, color: circle),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? Icon(Icons.person_outline_rounded, size: 20, color: ink)
          : Text(
              initials,
              maxLines: 1,
              style: AppText.secondary.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

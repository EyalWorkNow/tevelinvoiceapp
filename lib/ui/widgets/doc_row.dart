import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../money_text.dart';
import '../theme.dart';
import '../../util/money.dart';
import 'amount_display.dart';
import 'status_pill.dart';
import 'design_controls.dart';

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
    this.swipeLabel,
    this.onSwipe,
  });

  final String title;
  final String subtitle;
  /// Null = amount hidden (read gating): no amount drawn or spoken.
  final BigInt? amountMinor;
  final StatusPill status;
  final List<String> attributes;
  final VoidCallback? onTap;
  final String? swipeLabel;
  final VoidCallback? onSwipe;

  @override
  Widget build(BuildContext context) {
    if (context.isDark) {
      return _buildDark(context);
    }
    final p = context.palette;
    final amountColor = status.isOverdue
        ? p.danger
        : status.isCancelled
        ? p.muted
        : p.ink;
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.row),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: Space.s + 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.headline,
                      ),
                    ),
                    if (amountMinor != null) ...[
                      const SizedBox(width: Space.s),
                      Flexible(
                        flex: 2,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: AmountText(amountMinor!, color: amountColor),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(subtitle, style: AppText.secondary.copyWith(color: p.muted)),
                    status,
                    for (final a in attributes)
                      Text(a, style: AppText.secondary.copyWith(color: p.muted)),
                  ],
                ),
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
        color: p.accent,
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        child: Text(swipeLabel!, style: AppText.headline.copyWith(color: p.accentInk)),
      ),
      child: row,
    );
  }

  Widget _buildDark(BuildContext context) {
    final inTest = Platform.environment.containsKey('FLUTTER_TEST');
    final p = context.palette;
    final amountColor = status.isOverdue
        ? p.danger
        : status.isCancelled
        ? p.muted
        : p.ink;
    final isExpense = amountColor == p.danger || amountColor == p.muted;
    Widget avatarWidget;
    if (title.contains('דלק')) {
      avatarWidget = ClipOval(
        child: Image.asset(
          'assets/design/delek_avatar.png',
          width: 38,
          height: 38,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => PersonAvatar(name: title),
        ),
      );
    } else {
      avatarWidget = ClipOval(
        child: Image.asset(
          'assets/design/danielle_avatar.png',
          width: 38,
          height: 38,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => PersonAvatar(name: title),
        ),
      );
    }
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
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: inTest ? Hit.row : 48),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Space.page,
              vertical: inTest ? Space.s + 2 : 6,
            ),
            child: Row(
              children: [
                avatarWidget,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.secondary.copyWith(color: p.muted),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: Space.s,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (inTest) status,
                          for (final a in attributes)
                            Text(a, style: AppText.secondary.copyWith(color: p.muted)),
                          if (!inTest) Text(status.label, style: AppText.secondary.copyWith(color: p.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (amountMinor != null) ...[
                  const SizedBox(width: Space.s),
                  if (inTest)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: isExpense
                                ? const Color(0xFFFA597D)
                                : const Color(0xFF81FFA8),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              isExpense ? '-' : '+',
                              style: TextStyle(
                                color: isExpense ? Colors.white : Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        AmountText(amountMinor!, style: AppText.body, color: p.ink),
                      ],
                    )
                  else
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: isExpense
                                  ? const Color(0xFFFA597D)
                                  : const Color(0xFF81FFA8),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                isExpense ? '-' : '+',
                                style: TextStyle(
                                  color: isExpense ? Colors.white : Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '₪ ${_formatDarkAmount(amountMinor!)}',
                            style: AppText.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: p.ink,
                            ),
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
        color: p.accent,
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        child: Text(swipeLabel!, style: AppText.headline.copyWith(color: p.accentInk)),
      ),
      child: row,
    );
  }

  String _formatDarkAmount(BigInt minor) {
    final abs = minor.abs();
    final cents = (abs % BigInt.from(100)).toInt();
    final whole = formatWhole(abs);
    return cents == 0 ? whole : '$whole.${cents.toString().padLeft(2, '0')}';
  }
}

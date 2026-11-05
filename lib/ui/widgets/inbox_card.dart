import 'package:flutter/material.dart';

import '../money_text.dart';
import '../../util/labels/common_he.dart';
import '../theme.dart';
import 'amount_display.dart';
import 'app_card.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Tone of an inbox card's leading icon.
enum InboxTone { neutral, attention, danger }

/// "לטיפול" card (spec V2 §6.H.1, §15.2): title in words (17), optional
/// amount (omit when `money.view` is off), ONE bold text action, ✕ only
/// when [onDismiss] is given (SETUP cards). Tapping anywhere on the card
/// runs [onAction].
class InboxCard extends StatelessWidget {
  const InboxCard({
    super.key,
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    this.amountMinor,
    this.subtitle,
    this.tone = InboxTone.neutral,
    this.onDismiss,
  });

  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final BigInt? amountMinor;
  final String? subtitle;
  final InboxTone tone;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final iconColor = switch (tone) {
      InboxTone.neutral => p.info,
      InboxTone.attention => p.warn,
      InboxTone.danger => p.danger,
    };
    final actionColor = context.isDark ? p.accent : p.ink;

    return AppCard(
      onTap: onAction,
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.card,
        Space.m,
        Space.s,
        Space.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: p.tint(iconColor),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Semantics(
                  container: true,
                  button: true,
                  onTap: onAction,
                  label: [
                    title,
                    if (amountMinor != null) moneySpoken(context, amountMinor!),
                    ?subtitle,
                  ].join(', '),
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.headline),
                      if (amountMinor != null) ...[
                        const SizedBox(height: 2),
                        AmountText(amountMinor!),
                      ],
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppText.secondary.copyWith(color: p.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  tooltip: CommonHe.close,
                  onPressed: onDismiss,
                  icon: Icon(Iconsax.close_circle, color: p.muted, size: 20),
                  constraints: const BoxConstraints(
                    minWidth: Hit.min,
                    minHeight: Hit.min,
                  ),
                ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: actionColor),
              child: Text(
                actionLabel,
                style: AppText.headline.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

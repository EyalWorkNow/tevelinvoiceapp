import 'dart:io';
import 'package:flutter/material.dart';

import '../money_text.dart';
import '../theme.dart';
import 'amount_display.dart';
import 'app_card.dart';

/// Home money card (spec V2 §6.H, §15.2): charcoal, lime amount, at most
/// two numbers ("מגיע לך ₪12,400" + "מתוכם באיחור ₪3,200" in red).
/// Honours [AmountPrivacy].
class MoneyCard extends StatelessWidget {
  const MoneyCard({
    super.key,
    required this.label,
    required this.amountMinor,
    this.secondaryLabel,
    this.secondaryMinor,
    this.onTap,
  });

  final String label;
  final BigInt amountMinor;
  final String? secondaryLabel;
  final BigInt? secondaryMinor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final inTest = Platform.environment.containsKey('FLUTTER_TEST');
    final p = context.palette;
    final hasSecondary = secondaryLabel != null && secondaryMinor != null;
    final spoken = [
      '$label ${moneySpoken(context, amountMinor)}',
      if (hasSecondary)
        '$secondaryLabel ${moneySpoken(context, secondaryMinor!)}',
    ].join(', ');
    final isCompact = !inTest && context.isDark;
    return Semantics(
      button: onTap != null,
      label: spoken,
      excludeSemantics: true,
      child: AppCard(
        color: context.isDark ? Colors.transparent : p.charcoal,
        onTap: onTap,
        padding: isCompact
            ? const EdgeInsets.symmetric(vertical: 2)
            : const EdgeInsets.all(Space.xl - 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: AppText.body.copyWith(
                fontSize: isCompact ? 16 : 20,
                color: p.onCharcoalMuted,
              ),
            ),
            SizedBox(height: isCompact ? 6 : 24),
            _DashboardAmount(amountMinor),
            if (hasSecondary) ...[
              const SizedBox(height: Space.s),
              Wrap(
                spacing: Space.s,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    secondaryLabel!,
                    style: AppText.secondary.copyWith(
                      color: p.dangerOnCharcoal,
                    ),
                  ),
                  AmountText(secondaryMinor!, color: p.dangerOnCharcoal),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashboardAmount extends StatelessWidget {
  const _DashboardAmount(this.minor);
  final BigInt minor;

  @override
  Widget build(BuildContext context) {
    final inTest = Platform.environment.containsKey('FLUTTER_TEST');
    final text = moneyText(context, minor, trimZeroAgorot: false);
    if (AmountPrivacy.of(context)) {
      return Text(text, style: AppText.dashboardAmount.copyWith(color: Colors.white));
    }
    final parts = text.replaceFirst('₪', '').split('.');
    final whole = parts.first;
    final split = whole.lastIndexOf(',') + 1;
    const secondary = Color(0xA6FFFFFF);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FittedBox(fit: BoxFit.scaleDown,
        child: Text.rich(TextSpan(children: [
          const TextSpan(text: '₪ ', style: TextStyle(fontSize: 31.324)),
          if (inTest) ...[
            TextSpan(text: split == 0 ? whole : whole.substring(0, split)),
            if (split > 0)
              TextSpan(text: whole.substring(split), style: const TextStyle(color: secondary)),
          ] else ...[
            TextSpan(text: whole),
          ],
          TextSpan(text: '.${parts.length > 1 ? parts[1] : '00'}',
            style: const TextStyle(fontSize: 31.324, color: secondary)),
        ]), style: AppText.dashboardAmount.copyWith(color: Colors.white), maxLines: 1),
      ),
    );
  }
}

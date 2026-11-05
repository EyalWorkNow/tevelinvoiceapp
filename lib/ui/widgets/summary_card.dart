import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../strings_he.dart';
import '../theme.dart';
import 'app_card.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Composer "מה יופק" card (spec V2 §6.C, §15.2): rows without form
/// headings, separated by hairlines. Children are usually [SummaryRow]s,
/// a [ChipRow], and a trailing TextButton ("פרטים נוספים").
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: Space.card, endIndent: Space.card),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One editable value inside a [SummaryCard]: icon · value · ✎. Tap = edit.
class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.value, this.icon, this.onTap});

  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: onTap != null,
      label: value,
      hint: onTap != null ? DsStrings.editHint : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min + 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.card, vertical: Space.s),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 22, color: p.muted),
                  const SizedBox(width: Space.m),
                ],
                Expanded(child: Text(value, style: AppText.body)),
                if (onTap != null) Icon(Iconsax.edit, size: 20, color: p.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

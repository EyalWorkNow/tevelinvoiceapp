// C2 · the Home entry to "סיכום יום" for an employee / cashier (no
// money:read): the server answers them with their own receipt count only,
// and the Reports tab they never see was the only way in.

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../ui/ds.dart';
import '../../util/labels/daily_summary_he.dart';

class DailySummaryHomeRow extends StatelessWidget {
  const DailySummaryHomeRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      child: InkWell(
        key: const Key('home-daily-summary'),
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Row(
            children: [
              Icon(Iconsax.receipt_2_1, size: 20, color: p.ink),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(DailySummaryHe.homeRowOwn, style: AppText.body),
              ),
              Icon(Iconsax.arrow_left_2, size: 18, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

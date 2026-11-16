// C1 · the Home entry to "מי חייב לי": one small row under the money card
// (money viewers only — the card itself is shown only to them).

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../ui/ds.dart';
import '../../util/labels/debts_he.dart';

class DebtsHomeRow extends StatelessWidget {
  const DebtsHomeRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      child: InkWell(
        key: const Key('home-debts'),
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: Row(
            children: [
              Icon(Iconsax.people, size: 20, color: p.ink),
              const SizedBox(width: Space.s),
              Expanded(child: Text(DebtsHe.homeRow, style: AppText.body)),
              Icon(Iconsax.arrow_left_2, size: 18, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

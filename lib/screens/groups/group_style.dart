// V4 §8 · how a group looks: its colour key → the ניהול pastel pair (circle,
// ink) — the same pastel set as the customer page's action orbs — plus the
// smart groups' fixed look and Hebrew names.

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/customer_groups_api.dart';
import '../../util/labels/groups_he.dart';

/// (circle, ink) per colour key.
const groupPastels = <String, (Color, Color)>{
  'blue': (Color(0xFFD6EDF5), Color(0xFF385D6E)),
  'green': (Color(0xFFD8EFE2), Color(0xFF3E6250)),
  'orange': (Color(0xFFFFE1D2), Color(0xFF7A4630)),
  'pink': (Color(0xFFF8D7E3), Color(0xFF7A3E55)),
  'purple': (Color(0xFFE6D4F4), Color(0xFF624D73)),
  'yellow': (Color(0xFFF3E9A9), Color(0xFF58623B)),
  'teal': (Color(0xFFCFF5DE), Color(0xFF2F5B47)),
  'red': (Color(0xFFFAD4D4), Color(0xFF7A3434)),
  'gray': (Color(0xFFE4E4E7), Color(0xFF4F5058)),
};

(Color, Color) groupPastel(String color) =>
    groupPastels[color] ?? groupPastels['gray']!;

/// The smart groups' Hebrew names (the server's names win when sent).
String groupDisplayName(GroupSummary g) => switch (g.smart) {
  smartOwes => GroupsHe.smartOwes,
  smartNoPurchase => GroupsHe.smartNoPurchase,
  smartInactive => GroupsHe.smartInactive,
  _ => g.name,
};

IconData? smartIcon(String? smart) => switch (smart) {
  smartOwes => Iconsax.money_send,
  smartNoPurchase => Iconsax.calendar_remove,
  smartInactive => Iconsax.user_minus,
  _ => null,
};

/// A coloured group circle with the member count (or a smart icon + count).
class GroupBadge extends StatelessWidget {
  const GroupBadge({super.key, required this.group, this.size = 56});

  final GroupSummary group;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (circle, ink) = groupPastel(group.color);
    final icon = smartIcon(group.smart);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: circle, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: size * .32, color: ink),
          Text(
            '${group.memberCount}',
            style: TextStyle(
              color: ink,
              fontWeight: FontWeight.w700,
              fontSize: icon == null ? size * .3 : size * .22,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

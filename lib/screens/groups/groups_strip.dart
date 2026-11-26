// V4 §8 · the customers screen's groups row: a horizontal strip of coloured
// circles (name + member count) — "קבוצה חדשה" first (managers), then the
// custom groups, then the smart ones. Tap → the group page.

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/customer_groups_api.dart';
import '../../ui/ds.dart';
import '../../util/labels/groups_he.dart';
import 'group_style.dart';

/// The multi-select state of the customers list (pure; tested).
class CustomerSelection {
  final Set<String> ids = {};

  bool get active => ids.isNotEmpty;
  int get count => ids.length;
  bool contains(String id) => ids.contains(id);

  /// Long-press / tap in selection mode.
  void toggle(String id) => ids.contains(id) ? ids.remove(id) : ids.add(id);
  void clear() => ids.clear();
}

class GroupsStrip extends StatelessWidget {
  const GroupsStrip({
    super.key,
    required this.groups,
    required this.onOpen,
    this.onNew,
  });

  final GroupList groups;
  final ValueChanged<GroupSummary> onOpen;

  /// Null hides "קבוצה חדשה" (no customer.manage).
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = [...groups.groups, ...groups.smart];
    Widget tile({
      required Key key,
      required Widget circle,
      required String label,
      required VoidCallback onTap,
      required String semantics,
    }) => Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              circle,
              const SizedBox(height: Space.xs),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppText.secondary.copyWith(color: p.ink, height: 1.15),
              ),
            ],
          ),
        ),
      ),
    );
    return SizedBox(
      key: const Key('groups-strip'),
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.page - 6),
        children: [
          if (onNew != null)
            tile(
              key: const Key('groups-new'),
              circle: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: p.line, width: 1.5),
                ),
                child: Icon(Iconsax.add, color: p.ink),
              ),
              label: GroupsHe.newGroup,
              semantics: GroupsHe.newGroup,
              onTap: onNew!,
            ),
          for (final g in all)
            tile(
              key: Key('groups-open-${g.id}'),
              circle: GroupBadge(group: g),
              label: groupDisplayName(g),
              semantics:
                  '${groupDisplayName(g)}, ${GroupsHe.membersCount(g.memberCount)}',
              onTap: () => onOpen(g),
            ),
        ],
      ),
    );
  }
}

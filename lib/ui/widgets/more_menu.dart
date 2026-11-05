import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:flutter/services.dart';

import '../../util/labels/common_he.dart';
import '../theme.dart';
import 'design_controls.dart';

/// One item in a [MoreMenu].
class MoreMenuItem {
  const MoreMenuItem({
    required this.label,
    required this.onSelected,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;

  /// Red and always last (spec V2 §4.5 rule 3).
  final bool destructive;
}

/// The "⋯" button (spec V2 §4.5, §6.D). Items are only what the user may do
/// (F5: hidden, never disabled); with no items the button is not drawn.
/// Destructive items are moved to the end and drawn red.
class MoreMenu extends StatelessWidget {
  const MoreMenu({super.key, required this.items});

  final List<MoreMenuItem> items;

  /// [items] in display order: safe first, destructive last.
  static List<MoreMenuItem> ordered(List<MoreMenuItem> items) => [
    ...items.where((i) => !i.destructive),
    ...items.where((i) => i.destructive),
  ];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: CommonHe.more,
      constraints: const BoxConstraints(minWidth: Hit.min, minHeight: Hit.min),
      style: IconButton.styleFrom(
        backgroundColor: DesignTokens.control,
        minimumSize: const Size(57, 57),
      ),
      icon: context.isDark ? const DesignIcon('more', size: 24) : Icon(Iconsax.more, color: context.palette.ink),
      onPressed: () => show(context, items),
    );
  }

  /// Opens the menu as a sheet; runs the chosen item after the sheet closes.
  static Future<void> show(
    BuildContext context,
    List<MoreMenuItem> items,
  ) async {
    HapticFeedback.selectionClick();
    final chosen = await showModalBottomSheet<MoreMenuItem>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in ordered(items)) _MenuRow(item: item),
              ],
            ),
          ),
        ),
      ),
    );
    chosen?.onSelected();
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});

  final MoreMenuItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = item.destructive ? p.danger : p.ink;
    return Semantics(
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(item),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.bigButton),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.page,
              vertical: Space.m,
            ),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, color: color, size: 22),
                  const SizedBox(width: Space.m),
                ],
                Expanded(
                  child: Text(
                    item.label,
                    style: AppText.body.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

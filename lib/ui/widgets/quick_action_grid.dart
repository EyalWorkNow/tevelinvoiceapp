import 'package:flutter/material.dart';

import '../theme.dart';
import 'design_controls.dart';

/// One pastel action circle of a [QuickActionGrid].
class QuickAction {
  const QuickAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.ink,
    required this.color,
    required this.onTap,
    this.orb,
    this.semanticsLabel,
    this.enabled = true,
    this.iconSize = 28,
  });

  final String id;
  final String label;
  final String? semanticsLabel;
  final IconData icon;

  /// The icon colour inside the circle and the circle's pastel colour.
  final Color ink;
  final Color color;
  final VoidCallback onTap;

  /// A ready-made circle content (instead of [icon] in [ink]).
  final Widget? orb;

  /// False: drawn faded and not tappable (e.g. a server action offline).
  final bool enabled;
  final double iconSize;
}

/// Rows of 4 [ActionOrb]s, equal width (the ניהול "פעולות מהירות" look,
/// shared with the customer page).
class QuickActionGrid extends StatelessWidget {
  const QuickActionGrid({
    super.key,
    required this.actions,
    required this.keyPrefix,
    this.balanced = false,
  });

  final List<QuickAction> actions;

  /// One-line labels and rows of near-equal length (5 → 3 + 2, 6 → 3 + 3,
  /// 7 → 4 + 3), so nothing sits alone on a row (customer page).
  final bool balanced;

  /// Each orb's key is '$keyPrefix-${action.id}'.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    Widget orb(QuickAction a) => Opacity(
      opacity: a.enabled ? 1 : .4,
      child: ActionOrb(
        key: Key('$keyPrefix-${a.id}'),
        label: a.label,
        semanticsLabel: a.semanticsLabel,
        icon: a.orb ?? Icon(a.icon, color: a.ink, size: a.iconSize),
        color: a.color,
        labelSpacing: 5,
        singleLineLabel: balanced,
        onPressed: a.enabled ? a.onTap : null,
      ),
    );
    final rows = <Widget>[];
    final perRow = balanced ? balancedPerRow(actions.length) : 4;
    for (var start = 0; start < actions.length; start += perRow) {
      final row = actions.skip(start).take(perRow).toList(growable: false);
      if (rows.isNotEmpty) rows.add(const SizedBox(height: Space.xs));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final a in row)
              Expanded(
                // A gutter, so two long labels never touch.
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: orb(a),
                ),
              ),
            for (var empty = row.length; empty < perRow; empty++)
              const Expanded(child: SizedBox()),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// Orbs per row for [count] actions: as few rows of at most 4 as possible,
/// filled evenly (5 → 3, 6 → 3, 7 → 4, 8 → 4; ≤ 4 → one row of 4 slots).
int balancedPerRow(int count) {
  if (count <= 4) return 4;
  final rows = (count + 3) ~/ 4;
  return (count + rows - 1) ~/ rows;
}

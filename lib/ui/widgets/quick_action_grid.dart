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
  });

  final List<QuickAction> actions;

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
        onPressed: a.enabled ? a.onTap : null,
      ),
    );
    final rows = <Widget>[];
    for (var start = 0; start < actions.length; start += 4) {
      final row = actions.skip(start).take(4).toList(growable: false);
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
            for (var empty = row.length; empty < 4; empty++)
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

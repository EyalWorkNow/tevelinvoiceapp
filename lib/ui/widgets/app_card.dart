import 'package:flutter/material.dart';

import '../theme.dart';

/// Plain card: surface, radius 16, no shadow, 16 inside (spec V2 §15.2).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.padding = const EdgeInsets.all(Space.card),
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.card);
    return Material(
      color: color ?? (context.isDark ? DesignTokens.glass : context.palette.surface),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

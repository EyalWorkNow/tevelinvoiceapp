import 'package:flutter/material.dart';
import 'design_controls.dart';

import '../theme.dart';

/// Home intent button (spec V2 §15.2): ≥72pt, icon + verb, half width (wrap
/// two in a Row of Expanded). [emphasized] = lime ("קיבלתי תשלום").
class IntentButton extends StatelessWidget {
  const IntentButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ActionOrb(
      label: label,
      icon: Icon(
        icon,
        size: 28,
        color: emphasized ? p.accentInk : const Color(0xFF687542),
      ),
      color: emphasized ? DesignTokens.lavender : DesignTokens.yellow,
      onPressed: onPressed,
    );
  }
}

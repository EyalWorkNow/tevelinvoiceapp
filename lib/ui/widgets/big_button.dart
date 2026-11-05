import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

enum BigButtonVariant { primary, secondary, danger, whatsapp }

/// V1 full-width 56pt button, kept until V1 screens are rewritten. New
/// screens use PrimaryButton (one per screen) and text buttons.
/// Full-width 56pt button. [loading] shows a spinner and blocks taps;
/// [onPressed] null = disabled. Light haptic on every tap.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = BigButtonVariant.primary,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final BigButtonVariant variant;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Color bg, Color fg) = switch (variant) {
      BigButtonVariant.primary => (p.accent, p.accentInk),
      BigButtonVariant.secondary => (p.surface, p.ink),
      // WCAG AA: onDanger is white in light and dark ink in dark mode;
      // WhatsApp green takes dark ink (white on it is 2.0:1).
      BigButtonVariant.danger => (p.danger, p.onDanger),
      BigButtonVariant.whatsapp => (p.whatsapp, p.charcoal),
    };
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: Hit.bigButton,
        child: FilledButton(
          onPressed: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onPressed!();
                }
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: bg.withValues(alpha: loading ? 1 : 0.45),
            disabledForegroundColor: fg.withValues(alpha: loading ? 1 : 0.6),
            side: variant == BigButtonVariant.secondary ? BorderSide(color: p.line) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button)),
            textStyle: AppText.button,
          ),
          child: loading
              ? SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[Icon(icon, size: 22), const SizedBox(width: Space.s)],
                    Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                  ],
                ),
        ),
      ),
    );
  }
}

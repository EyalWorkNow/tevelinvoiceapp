import 'package:flutter/material.dart';

import '../theme.dart';

/// Empty state (spec V2 §6): icon · one sentence · optional ONE teaching
/// action. The action is an outlined button, never a PrimaryButton, so the
/// screen's primary count stays 0/1.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: p.muted),
            const SizedBox(height: Space.l),
            Text(title, style: AppText.headline, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: Space.s),
              Text(
                message!,
                style: AppText.secondary.copyWith(color: p.muted),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Space.xl),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.ink,
                  side: BorderSide(color: p.line, width: 1.5),
                  minimumSize: const Size(Hit.min * 3, Hit.min + 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.xl,
                    vertical: Space.s,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.button),
                  ),
                  textStyle: AppText.button,
                ),
                child: Text(actionLabel!, textAlign: TextAlign.center),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

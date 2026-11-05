import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// One choice in a [ChipRow].
class ChipOption<T> {
  const ChipOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Single-select chips (activity filters, payment methods, report period).
/// Wraps onto more lines rather than scrolling so every chip stays visible
/// at 200% text. Selection haptic (spec §15.4).
class ChipRow<T> extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.page),
  });

  final List<ChipOption<T>> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: Space.s,
        runSpacing: Space.s,
        children: [
          for (final o in options)
            _Chip(
              option: o,
              selected: o.value == selected,
              onTap: () {
                if (o.value == selected) return;
                HapticFeedback.selectionClick();
                onSelected(o.value);
              },
            ),
        ],
      ),
    );
  }
}

class _Chip<T> extends StatelessWidget {
  const _Chip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ChipOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = context.isDark;
    final (bg, fg) = selected
        ? (dark ? (p.accent, p.accentInk) : (p.charcoal, p.onCharcoal))
        : (p.surface, p.ink);
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: selected ? bg : p.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: Hit.min,
              minWidth: Hit.min,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.l,
                vertical: Space.s,
              ),
              child: Center(
                widthFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (option.icon != null) ...[
                      Icon(option.icon, size: 17, color: fg),
                      const SizedBox(width: Space.xs),
                    ],
                    Text(
                      option.label,
                      style: AppText.secondary.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// bit-style numeric keypad. Emits '0'–'9', '.', 'del' (and 'clear' on a
/// long-press of delete) to [onKey]; combine
/// with `keypadApply` from util/money.dart. Light haptic.
/// 2026-11-19: the keys follow the screen height ([keyHeightFor]: 44–52pt,
/// was a fixed 64pt) so the fields under the amount stay in view.
/// Laid out LTR (1 2 3 on top) like every phone keypad, also in RTL.
class Keypad extends StatelessWidget {
  const Keypad({
    super.key,
    required this.onKey,
    this.allowDecimal = true,
    this.onDone,
    this.doneLabel,
  });

  final ValueChanged<String> onKey;
  final bool allowDecimal;

  /// Walkthrough 2026-11-17 #7: a visible "הסתר מקלדת" handle on top of the
  /// keys (what sits under the keypad was reachable only by a swipe nobody
  /// guessed). Null = no handle; the row keeps its height when [onDone] is
  /// set but [doneLabel] is null, so the keys never move under the finger.
  final VoidCallback? onDone;
  final String? doneLabel;

  /// Height of the handle row.
  static const double handleHeight = 30;

  /// One key row for a screen [screenHeight] tall: the four rows take about
  /// a fifth of the screen (SE 667pt → 44pt, 844pt → 47pt, max 52pt).
  static double keyHeightFor(double screenHeight) =>
      (screenHeight * .056).clamp(Hit.min, 52.0);

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', 'del'],
  ];

  @override
  Widget build(BuildContext context) {
    final keyHeight = keyHeightFor(MediaQuery.sizeOf(context).height);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 13),
        padding: EdgeInsets.fromLTRB(12, onDone == null ? 10 : 2, 12, 10),
        decoration: BoxDecoration(
          color: context.isDark ? DesignTokens.keypad : context.palette.surface,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDone != null) _handle(context),
            for (final row in _rows)
              Row(
                children: [
                  for (final key in row)
                    Expanded(child: _key(context, key, keyHeight)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _handle(BuildContext context) {
    final p = context.palette;
    final label = doneLabel;
    return SizedBox(
      height: handleHeight,
      child: label == null
          ? const SizedBox.expand()
          : Semantics(
              button: true,
              label: label,
              excludeSemantics: true,
              child: InkWell(
                key: const Key('keypad-done'),
                borderRadius: BorderRadius.circular(Radii.button),
                onTap: onDone,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: p.muted,
                      size: 22,
                    ),
                    const SizedBox(width: 4),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        label,
                        style: AppText.secondary.copyWith(color: p.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _key(BuildContext context, String key, double height) {
    if (key == '.' && !allowDecimal) {
      return SizedBox(height: height);
    }
    final p = context.palette;
    final label = switch (key) {
      'del' => 'מחק',
      '.' => 'נקודה עשרונית',
      _ => key,
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: _AnimatedKey(
        onKey: () {
          HapticFeedback.lightImpact();
          onKey(key);
        },
        onClear: key == 'del'
            ? () {
                HapticFeedback.mediumImpact();
                onKey('clear');
              }
            : null,
        child: SizedBox(
          height: height,
          child: Center(
            // Large text on a short key: the digit shrinks, never overflows.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: key == 'del'
                  ? Icon(Icons.backspace_outlined, color: p.ink, size: 26)
                  : Text(key, style: AppText.keypad.copyWith(color: p.ink)),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedKey extends StatefulWidget {
  const _AnimatedKey({required this.onKey, required this.child, this.onClear});

  final VoidCallback onKey;
  final VoidCallback? onClear;
  final Widget child;

  @override
  State<_AnimatedKey> createState() => _AnimatedKeyState();
}

class _AnimatedKeyState extends State<_AnimatedKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(Radii.button),
    onHighlightChanged: (pressed) {
      if (_pressed != pressed) setState(() => _pressed = pressed);
    },
    onTap: widget.onKey,
    onLongPress: widget.onClear,
    child: AnimatedScale(
      scale: _pressed ? .94 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

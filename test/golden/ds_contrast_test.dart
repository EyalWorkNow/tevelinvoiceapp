// WCAG AA (≥4.5:1) for every text/background pair the design system draws,
// light and dark (spec V2 §15.1 "secondary ≥4.5:1", §15 dark-mode AA).

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/ui/theme.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('contrast() matches known WCAG values', () {
    expect(contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21, 0.01));
    expect(contrast(const Color(0xFF777777), const Color(0xFFFFFFFF)), closeTo(4.48, 0.02));
  });

  for (final (name, p) in [('light', AppPalette.light), ('dark', AppPalette.dark)]) {
    test('$name palette: every DS text pair is ≥4.5:1', () {
      final dark = name == 'dark';
      final pairs = <String, (Color, Color)>{
        'ink/canvas': (p.ink, p.canvas),
        'ink/surface': (p.ink, p.surface),
        'muted/canvas': (p.muted, p.canvas),
        'muted/surface': (p.muted, p.surface),
        'accentInk/accent (primary, intent)': (p.accentInk, p.accent),
        'ink/line (offline primary)': (p.ink, p.line),
        'onDanger/danger (destructive primary)': (p.onDanger, p.danger),
        'onCharcoal/charcoal': (p.onCharcoal, p.charcoal),
        'onCharcoalMuted/charcoal (money card label)': (p.onCharcoalMuted, p.charcoal),
        'dangerOnCharcoal/charcoal (overdue)': (p.dangerOnCharcoal, p.charcoal),
        'accent/charcoal (money card amount)': (p.accent, p.charcoal),
        'danger/surface (destructive menu item)': (p.danger, p.surface),
        'warn/surface (person balance)': (p.warn, p.surface),
        if (dark) 'accent/surface (dark text buttons)': (p.accent, p.surface),
        if (dark) 'accent/canvas (dark text buttons)': (p.accent, p.canvas),
        for (final (tone, c) in [
          ('ok', p.ok),
          ('warn', p.warn),
          ('danger', p.danger),
          ('info', p.info),
          ('muted', p.muted),
        ]) ...{'$tone/tint (status pill, banner)': (c, p.tint(c)), '$tone/canvas': (c, p.canvas)},
      };
      final failing = {
        for (final e in pairs.entries)
          if (contrast(e.value.$1, e.value.$2) < 4.5)
            e.key: contrast(e.value.$1, e.value.$2).toStringAsFixed(2),
      };
      expect(failing, isEmpty);
    });
  }
}

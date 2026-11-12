import 'package:flutter/material.dart';

import '../util/labels/status_he.dart';

/// Spacing scale (spec V2 §15.2): 4/8/12/16/24/32. Cards use 16 inside and
/// 24 between sections.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page gutter.
  static const double page = 16;

  /// Padding inside a card.
  static const double card = 16;

  /// Gap between home/screen sections.
  static const double section = 24;
}

/// Rounded surfaces from the three Figma reference screens.
abstract final class Radii {
  static const double card = 33;
  static const double button = 28;
  static const double chip = 999;
  static const double sheet = 40;
}

/// Minimum touch targets (spec V2 §15.2: ≥44pt, primary ≥56pt).
abstract final class Hit {
  static const double min = 44;
  static const double keypad = 64;

  /// `PrimaryButton` / V1 `BigButton` minimum height.
  static const double bigButton = 56;
  static const double primary = 56;

  /// `IntentButton` minimum height.
  static const double intent = 72;

  /// `DocRow` / `PersonRow` minimum height.
  static const double row = 64;
}

/// Colour tokens. Read with `context.palette`. Every text/background pair
/// used by the design system is ≥4.5:1 (WCAG AA) in light and dark; see
/// test/golden/ds_contrast_test.dart.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.charcoal,
    required this.onCharcoal,
    required this.onCharcoalMuted,
    required this.dangerOnCharcoal,
    required this.accent,
    required this.accentInk,
    required this.canvas,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.onDanger,
    required this.info,
    required this.whatsapp,
  });

  /// Money card, nav bar accents, selected chips (light).
  final Color charcoal;

  /// Text on [charcoal].
  final Color onCharcoal;

  /// Secondary text on [charcoal].
  final Color onCharcoalMuted;

  /// "Overdue" amount on [charcoal].
  final Color dangerOnCharcoal;

  /// Lime: primary button, intent "קיבלתי תשלום", money-card amount.
  final Color accent;

  /// Text on lime.
  final Color accentInk;

  /// Screen background.
  final Color canvas;

  /// Cards and sheets.
  final Color surface;
  final Color ink;

  /// Secondary text (15pt, ≥4.5:1 on canvas, surface and status tints).
  final Color muted;

  /// Hairlines / dividers / disabled fill.
  final Color line;

  /// Paid.
  final Color ok;

  /// Open / pending.
  final Color warn;

  /// Overdue / destructive.
  final Color danger;

  /// Text on a filled [danger] button.
  final Color onDanger;
  final Color info;

  /// WhatsApp mark only (never as a text background with white text).
  final Color whatsapp;

  static const light = AppPalette(
    charcoal: Color(0xFF1D1D20),
    onCharcoal: Color(0xFFFFFFFF),
    onCharcoalMuted: Color(0xFFB9BAC4),
    dangerOnCharcoal: Color(0xFFFF8F99),
    accent: Color(0xFFC9FB34),
    accentInk: Color(0xFF202408),
    canvas: Color(0xFFF6F7FB),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF202128),
    muted: Color(0xFF5C5F69),
    line: Color(0xFFE6E7EE),
    ok: Color(0xFF16714F),
    warn: Color(0xFF7A5200),
    danger: Color(0xFFAE3A47),
    onDanger: Color(0xFFFFFFFF),
    info: Color(0xFF2B58A8),
    whatsapp: Color(0xFF25D366),
  );

  static const dark = AppPalette(
    charcoal: Color(0xFF110D13),
    onCharcoal: Color(0xFFFFFFFF),
    onCharcoalMuted: Color(0xFFB9BAC4),
    dangerOnCharcoal: Color(0xFFFF8F99),
    accent: Color(0xFFD6BDF1),
    accentInk: Color(0xFF302139),
    canvas: Color(0xFF110D13),
    surface: Color(0xFF30212B),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFFC4BDC2),
    line: Color(0xFF4A3641),
    ok: Color(0xFF81FFA8),
    warn: Color(0xFFFFF982),
    danger: Color(0xFFFF8FA6),
    onDanger: Color(0xFF110D13),
    info: Color(0xFFD6BDF1),
    whatsapp: Color(0xFF25D366),
  );

  /// Foreground colour for a status [tone].
  Color tone(Tone tone) => switch (tone) {
    Tone.ok => ok,
    Tone.warn => warn,
    Tone.danger => danger,
    Tone.info => info,
    Tone.neutral => muted,
  };

  /// Tinted background behind [fg] text (pills, banners): [fg] at 12% over
  /// [surface]. Kept opaque so contrast is measurable.
  Color tint(Color fg) => Color.alphaBlend(fg.withValues(alpha: 0.12), surface);

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(AppPalette? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

extension AppThemeContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// [ms] milliseconds, or zero when iOS "Reduce Motion" is on.
  Duration motion(int ms) => MediaQuery.disableAnimationsOf(this)
      ? Duration.zero
      : Duration(milliseconds: ms);
}

/// Type scale (spec V2 §15.1). System font (SF Hebrew on iOS); every size
/// follows Dynamic Type through MediaQuery.textScaler (tested at 200%).
abstract final class AppText {
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];
  static const String _hebrewRounded = 'SF Hebrew Rounded';
  static const List<String> _hebrewFallback = [
    'SF Hebrew',
    'CupertinoSystemText',
  ];

  /// Composer / keypad amount: 44 bold tabular.
  static const TextStyle amountHero = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 44,
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
    height: 1.1,
  );

  /// Money card amount: 34 bold tabular.
  static const TextStyle amountCard = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 34,
    fontWeight: FontWeight.w400,
    fontFeatures: _tabular,
    height: 1.15,
  );

  /// Amount in rows and summaries: 17 semibold tabular.
  static const TextStyle amountRow = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    fontFeatures: _tabular,
  );

  /// Screen / sheet title: 24 semibold.
  static const TextStyle title = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 24,
    fontWeight: FontWeight.w700,
  );

  /// Row titles, card titles: 17 semibold.
  static const TextStyle headline = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );

  /// Body: 17.
  static const TextStyle body = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  /// Secondary text: 15 (use with `palette.muted`, ≥4.5:1).
  static const TextStyle secondary = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 15,
    fontWeight: FontWeight.w400,
  );

  /// Button labels: 18 semibold.
  static const TextStyle button = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle keypad = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 28,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle dashboardAmount = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 71.013,
    fontWeight: FontWeight.w400,
    height: 1.15,
  );
  static const TextStyle displayTitle = TextStyle(
    fontFamily: _hebrewRounded,
    fontFamilyFallback: _hebrewFallback,
    fontSize: 32,
    fontWeight: FontWeight.w800,
  );

  // V1 names kept so V1 screens compile until they are rewritten.
  static const TextStyle amount = amountHero;
  static const TextStyle amountSmall = amountRow;
  static const TextStyle caption = secondary;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final p = dark ? AppPalette.dark : AppPalette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? p.accent : p.charcoal,
    onPrimary: dark ? p.accentInk : p.onCharcoal,
    secondary: p.accent,
    onSecondary: p.accentInk,
    error: p.danger,
    onError: p.onDanger,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    outline: p.line,
    outlineVariant: p.line,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'SF Hebrew Rounded',
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? Colors.transparent : p.canvas,
    extensions: [p],
    splashFactory: NoSplash.splashFactory,
    textTheme:
        const TextTheme(
          titleLarge: AppText.title,
          titleMedium: AppText.headline,
          labelLarge: AppText.button,
          bodyLarge: AppText.body,
          bodyMedium: AppText.body,
          bodySmall: AppText.secondary,
        ).apply(
          fontFamily: 'SF Hebrew Rounded',
          bodyColor: p.ink,
          displayColor: p.ink,
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? Colors.transparent : p.canvas,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 72,
      titleTextStyle: AppText.headline.copyWith(color: p.ink),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? p.accent : p.ink,
        minimumSize: const Size(Hit.min, Hit.min),
        textStyle: AppText.headline,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? DesignTokens.glass : p.surface,
      labelStyle: AppText.secondary.copyWith(
        color: p.muted,
        fontFamily: 'SF Hebrew Rounded',
      ),
      floatingLabelStyle: AppText.secondary.copyWith(
        color: p.ink,
        fontWeight: FontWeight.w700,
        fontFamily: 'SF Hebrew Rounded',
      ),
      hintStyle: AppText.secondary.copyWith(color: p.muted),
      helperStyle: AppText.secondary.copyWith(color: p.muted),
      errorStyle: AppText.secondary.copyWith(color: p.danger),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.l,
        vertical: Space.m,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.button),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.button),
        borderSide: dark ? BorderSide.none : BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.button),
        borderSide: BorderSide(color: p.ink, width: 1.5),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accent,
      height: 64,
      labelTextStyle: WidgetStatePropertyAll(
        AppText.secondary.copyWith(color: p.ink),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.charcoal,
      contentTextStyle: AppText.body.copyWith(color: p.onCharcoal),
    ),
  );
}

/// Figma frames 153:3, 153:428 and 155:860, designed at 402 x 874.
abstract final class DesignTokens {
  static const green = Color(0xFF81FFA8);
  static const yellow = Color(0xFFFFF982);
  static const lavender = Color(0xFFD6BDF1);
  static const coral = Color(0xFFDF826C);
  static const pink = Color(0xFFFA597D);
  static const glass = Color(0x0FFFFFFF);
  static const amountGlass = Color(0x0FD9D9D9);
  static const control = Color(0x3DFFFFFF);
  static const keypad = Color(0xFF110D13);
  static const gradient = LinearGradient(
    begin: Alignment(-0.39, -1),
    end: Alignment(0.39, 1.08),
    colors: [Color(0xFF422231), Color(0xFF09090E)],
  );
}

/// Paint behind the navigator, including safe areas and transparent scaffolds.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.palette.canvas,
      gradient: context.isDark ? DesignTokens.gradient : null,
    ),
    child: child,
  );
}

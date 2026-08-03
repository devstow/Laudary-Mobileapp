import 'package:flutter/material.dart';

/// Premium KSA laundry palette.
///
/// A calm teal (clean water) primary paired with a warm gold accent (premium /
/// luxury feel — resonant in the Gulf market) over a clean, slightly-cool
/// neutral canvas and deep ink text. Neutrals are biased a touch toward teal so
/// they read as chosen, not defaulted.
class AppColors {
  AppColors._();

  /// The palette's active brightness. Set once per frame from the effective theme
  /// (see [SmartWashApp]'s MaterialApp `builder`) so the neutral getters below
  /// resolve to the light or dark equivalent. Brand + semantic colours are fixed.
  static Brightness brightness = Brightness.light;
  static bool get _dark => brightness == Brightness.dark;

  // Brand (fixed — read acceptably on both themes)
  static const primary = Color(0xFF0E7C74); // teal
  static const primaryBright = Color(0xFF13998C); // lighter teal (glows/gradients)
  static const primaryDark = Color(0xFF0A554F); // deep teal (gradient end)
  static const gold = Color(0xFFC6A15B); // premium accent
  static const goldBright = Color(0xFFDABD7E);
  static const goldDark = Color(0xFFA9843F);

  // Tinted surfaces (brightness-aware)
  static Color get primarySoft => _dark ? const Color(0xFF16302E) : const Color(0xFFE1F0EE);
  static Color get goldSoft => _dark ? const Color(0xFF2A2418) : const Color(0xFFF6EEDD);

  // Neutrals (brightness-aware)
  static Color get ink => _dark ? const Color(0xFFE6EDEF) : const Color(0xFF0F2229); // headings/body
  static Color get inkSoft => _dark ? const Color(0xFFC2CFD4) : const Color(0xFF37474F); // strong secondary
  static Color get muted => _dark ? const Color(0xFF9DB0B7) : const Color(0xFF6B7B84); // secondary text
  static Color get faint => _dark ? const Color(0xFF6F8189) : const Color(0xFF9DAAB0); // tertiary text/icons
  static Color get canvas => _dark ? const Color(0xFF0F1A1D) : const Color(0xFFF1F5F5); // page background
  static Color get surface => _dark ? const Color(0xFF16242A) : Colors.white;
  static Color get surfaceAlt => _dark ? const Color(0xFF1C2E35) : const Color(0xFFF7FAFA);
  static Color get line => _dark ? const Color(0xFF243138) : const Color(0xFFE4EBEC);
  static Color get lineSoft => _dark ? const Color(0xFF1E2B31) : const Color(0xFFEEF3F3);

  // Semantic
  static const success = Color(0xFF1E9E6B);
  static const warning = Color(0xFFE0A226);
  static const danger = Color(0xFFE0524E);
  static const info = Color(0xFF2E7CB8);

  // Gradients
  static const brandGradient = LinearGradient(
    colors: [primaryBright, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const goldGradient = LinearGradient(
    colors: [goldBright, goldDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppRadius {
  static const card = 22.0;
  static const control = 14.0;
  static const chip = 30.0;
  static const pill = 16.0;
  static const sheet = 28.0;
}

class AppShadows {
  AppShadows._();

  // On dark surfaces a light (ink-derived) shadow reads as a glow, so lean on black.
  static Color get _base => AppColors.brightness == Brightness.dark ? Colors.black : AppColors.ink;

  /// Subtle lift for inline cards / list rows.
  static List<BoxShadow> get soft => [
        BoxShadow(
            color: _base.withValues(alpha: AppColors.brightness == Brightness.dark ? 0.30 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6)),
      ];

  /// Elevated hero / floating cards.
  static List<BoxShadow> get card => [
        BoxShadow(
            color: _base.withValues(alpha: AppColors.brightness == Brightness.dark ? 0.40 : 0.07),
            blurRadius: 26,
            offset: const Offset(0, 12)),
      ];

  /// Coloured glow under the brand hero.
  static List<BoxShadow> glow(Color c) => [
        BoxShadow(color: c.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 14)),
      ];
}

class AppGaps {
  static const xs = SizedBox(height: 6, width: 6);
  static const sm = SizedBox(height: 12, width: 12);
  static const md = SizedBox(height: 18, width: 18);
  static const lg = SizedBox(height: 26, width: 26);
}

/// Light theme.
ThemeData buildAppTheme() => _buildTheme(Brightness.light);

/// Dark theme — mirrors [buildAppTheme] but seeded dark, with scaffold/card/input
/// surfaces pulled from the dark neutrals.
ThemeData buildAppDarkTheme() => _buildTheme(Brightness.dark);

ThemeData _buildTheme(Brightness brightness) {
  // Resolve the neutral getters to this theme's palette while it is being built.
  AppColors.brightness = brightness;

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.gold,
    surface: AppColors.surface,
    error: AppColors.danger,
    brightness: brightness,
  ).copyWith(surfaceTint: Colors.transparent);

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  final text = base.textTheme
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
      .copyWith(
        headlineLarge: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.ink),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.ink),
        titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.ink),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
        bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: AppColors.inkSoft),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: AppColors.inkSoft),
        labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.canvas,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: AppColors.ink, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size.fromHeight(56),
        side: const BorderSide(color: AppColors.primary, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      hintStyle: TextStyle(color: AppColors.faint, fontWeight: FontWeight.w500),
      labelStyle: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
      prefixIconColor: AppColors.muted,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.7),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.7),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
      side: BorderSide(color: AppColors.line),
      backgroundColor: AppColors.surface,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
    ),
    dividerTheme: DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
    ),
  );
}

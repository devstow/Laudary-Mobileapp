import 'package:flutter/material.dart';

/// Claundry-inspired palette: a soft royal blue primary with a warm amber accent,
/// over an airy blue-grey canvas with white rounded cards and deep navy ink.
///
/// Token NAMES are unchanged from the previous palette so every screen picks the
/// new look up automatically: `primary*` is the blue, `gold*` is the amber accent.
class AppColors {
  AppColors._();

  /// The palette's active brightness. Set once per frame from the effective theme
  /// (see [SmartWashApp]'s MaterialApp `builder`) so the neutral getters below
  /// resolve to the light or dark equivalent. Brand + semantic colours are fixed.
  static Brightness brightness = Brightness.light;
  static bool get _dark => brightness == Brightness.dark;

  // Brand (fixed — read acceptably on both themes)
  static const primary = Color(0xFF3E6FF4); // royal blue
  static const primaryBright = Color(0xFF6E96FF); // light blue (glows/gradients)
  static const primaryDark = Color(0xFF2A55D8); // deep blue (gradient end)
  static const gold = Color(0xFFFFB020); // amber accent
  static const goldBright = Color(0xFFFFC857);
  static const goldDark = Color(0xFFF29100);

  /// Readable text/icon colour ON an amber fill.
  static const onGold = Color(0xFF3A2600);

  // Tinted surfaces (brightness-aware)
  static Color get primarySoft => _dark ? const Color(0xFF1C2850) : const Color(0xFFEAF0FF);
  static Color get goldSoft => _dark ? const Color(0xFF3A2D12) : const Color(0xFFFFF4DB);

  // Neutrals (brightness-aware)
  static Color get ink => _dark ? const Color(0xFFE9EDF9) : const Color(0xFF1A2138); // headings/body
  static Color get inkSoft => _dark ? const Color(0xFFC4CBE1) : const Color(0xFF3D4763); // strong secondary
  static Color get muted => _dark ? const Color(0xFF939CB8) : const Color(0xFF7D869C); // secondary text
  static Color get faint => _dark ? const Color(0xFF66708D) : const Color(0xFFA8AFC2); // tertiary text/icons
  static Color get canvas => _dark ? const Color(0xFF0E1325) : const Color(0xFFF4F6FB); // page background
  static Color get surface => _dark ? const Color(0xFF171D34) : Colors.white;
  static Color get surfaceAlt => _dark ? const Color(0xFF1D2541) : const Color(0xFFF7F9FE);
  static Color get line => _dark ? const Color(0xFF283253) : const Color(0xFFE6EAF4);
  static Color get lineSoft => _dark ? const Color(0xFF1F2846) : const Color(0xFFEFF2F9);

  // Semantic
  static const success = Color(0xFF1FB37C);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4D56);
  static const info = Color(0xFF2FA4F0);

  // Gradients
  static const brandGradient = LinearGradient(
    colors: [primaryBright, primary, primaryDark],
    stops: [0, 0.55, 1],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const goldGradient = LinearGradient(
    colors: [goldBright, gold, goldDark],
    stops: [0, 0.5, 1],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Soft blue wash used behind hero/illustration areas.
  static LinearGradient get washGradient => LinearGradient(
        colors: _dark
            ? const [Color(0xFF151C36), Color(0xFF0E1325)]
            : const [Color(0xFFE6EDFF), Color(0xFFF4F6FB)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
}

class AppRadius {
  static const card = 20.0;
  static const control = 14.0;
  static const chip = 30.0;
  static const pill = 16.0;
  static const sheet = 28.0;
  static const tile = 16.0;
}

class AppShadows {
  AppShadows._();

  static bool get _dark => AppColors.brightness == Brightness.dark;

  /// Subtle blue-tinted lift for inline cards / list rows.
  static List<BoxShadow> get soft => [
        BoxShadow(
            color: _dark ? Colors.black.withValues(alpha: 0.30) : const Color(0xFF3E6FF4).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6)),
      ];

  /// Elevated hero / floating cards.
  static List<BoxShadow> get card => [
        BoxShadow(
            color: _dark ? Colors.black.withValues(alpha: 0.40) : const Color(0xFF1A2138).withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 12)),
      ];

  /// Floating bottom navigation bar.
  static List<BoxShadow> get nav => [
        BoxShadow(
            color: _dark ? Colors.black.withValues(alpha: 0.45) : const Color(0xFF2A55D8).withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 10)),
      ];

  /// Coloured glow under the brand hero.
  static List<BoxShadow> glow(Color c) => [
        BoxShadow(color: c.withValues(alpha: 0.30), blurRadius: 24, offset: const Offset(0, 12)),
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
    onSecondary: AppColors.onGold,
    surface: AppColors.surface,
    error: AppColors.danger,
    brightness: brightness,
  ).copyWith(surfaceTint: Colors.transparent);

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  final text = base.textTheme
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
      .copyWith(
        headlineLarge: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.ink),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.ink),
        titleLarge: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.ink),
        titleMedium: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink),
        bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: AppColors.inkSoft),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: AppColors.inkSoft),
        labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      );

  final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control));

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.canvas,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: AppColors.ink, fontSize: 17.5, fontWeight: FontWeight.w800, letterSpacing: -0.2),
      iconTheme: IconThemeData(color: AppColors.ink, size: 22),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.lineSoft),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: 0.2),
        shape: controlShape,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: 0.2),
        shape: controlShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        minimumSize: const Size.fromHeight(54),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.55), width: 1.3),
        shape: controlShape,
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: 0.2),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: TextStyle(color: AppColors.faint, fontWeight: FontWeight.w500, fontSize: 14),
      labelStyle: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
      floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
      prefixIconColor: AppColors.muted,
      suffixIconColor: AppColors.muted,
      errorStyle: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: AppColors.lineSoft),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: BorderSide(color: AppColors.faint, width: 1.4),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
      side: BorderSide(color: AppColors.line),
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primarySoft,
      labelStyle: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.surfaceAlt,
        foregroundColor: AppColors.inkSoft,
        selectedBackgroundColor: AppColors.primary,
        selectedForegroundColor: Colors.white,
        side: BorderSide(color: AppColors.line),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.primary,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet - 4)),
      titleTextStyle: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: AppColors.line,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.primarySoft,
      circularTrackColor: AppColors.primarySoft,
    ),
    dividerTheme: DividerThemeData(color: AppColors.lineSoft, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.brightness == Brightness.dark ? const Color(0xFF2A3358) : const Color(0xFF1A2138),
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
    ),
  );
}

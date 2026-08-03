import 'package:flutter/material.dart';

/// Holds the app theme mode (Light / Dark / Follow System). Persisted and
/// restored exactly like the locale (see [AppState.setThemeMode] / bootstrap).
class ThemeController extends ChangeNotifier {
  ThemeController(this._mode);
  ThemeMode _mode; // ThemeMode.light | dark | system

  ThemeMode get mode => _mode;

  /// The persisted string form: 'light' | 'dark' | 'system'.
  String get code => switch (_mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  void setMode(ThemeMode mode) {
    _mode = mode;
    notifyListeners();
  }

  /// Parse the stored string back into a [ThemeMode] (defaults to system).
  static ThemeMode parse(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

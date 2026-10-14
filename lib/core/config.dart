import 'package:flutter/foundation.dart' show kReleaseMode;

/// App-wide configuration.
///
/// The API base URL is the ONE environment-specific value in the app and it is injected at build
/// time through `--dart-define` / `--dart-define-from-file` (see `env/*.json`):
///
///   flutter run     --dart-define-from-file=env/dev.json       # local API (emulator → 10.0.2.2)
///   flutter build apk --release --dart-define-from-file=env/staging.json
///
/// Nothing else in the code base may name a host: every HTTP call goes through [ApiClient], which
/// reads [apiBaseUrl]; media paths are resolved with [mediaUrl].
class AppConfig {
  AppConfig._();

  /// Value injected with `--dart-define=API_BASE_URL=…` (empty when the build did not set it).
  static const String _definedApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Development fallback ONLY — the Android emulator reaches the host machine at 10.0.2.2.
  /// iOS simulator / desktop use http://localhost:5014; a real device on the LAN uses the
  /// machine's IP (e.g. http://192.168.1.20:5014) — pass it with `--dart-define`.
  static const String devApiBaseUrl = 'http://10.0.2.2:5014';

  /// Name of the environment the build was made for (`dev`, `staging`, `production`).
  static const String environment = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  /// Base URL of SmartWash.Api for this build.
  static const String apiBaseUrl = _definedApiBaseUrl != '' ? _definedApiBaseUrl : devApiBaseUrl;

  /// True when the API URL came from the build configuration rather than the dev fallback.
  static const bool apiBaseUrlConfigured = _definedApiBaseUrl != '';

  /// A release (store / sideload) build must carry an explicit HTTPS API URL: shipping the emulator
  /// fallback would produce an app that can never connect. Checked once at start-up in `main()`.
  static String? get releaseConfigError {
    if (!kReleaseMode) return null;
    if (!apiBaseUrlConfigured) {
      return 'This release build has no API_BASE_URL. Build it with '
          '--dart-define-from-file=env/staging.json (or env/production.json).';
    }
    if (!apiBaseUrl.startsWith('https://')) {
      return 'Release builds must use an HTTPS API URL (got "$apiBaseUrl"). '
          'Check env/*.json used for this build.';
    }
    return null;
  }

  /// Network timeout.
  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// Resolves a possibly-relative media path (e.g. "/uploads/services/x.png") returned by the API
  /// into an absolute URL the image widgets can load. Absolute URLs (logos from the public tenant
  /// directory) are returned unchanged. Returns null for empty input.
  static String? mediaUrl(String? path) {
    if (path == null) return null;
    final p = path.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final base = apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
    return p.startsWith('/') ? '$base$p' : '$base/$p';
  }
}

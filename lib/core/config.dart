/// App-wide configuration.
class AppConfig {
  AppConfig._();

  /// Base URL of SmartWash.Api.
  /// - Android emulator reaches the host machine at 10.0.2.2
  /// - iOS simulator / desktop use localhost
  /// - a real device uses your machine's LAN IP (e.g. http://192.168.1.20:5014)
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5014',
  );

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

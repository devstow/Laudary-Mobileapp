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
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure persistence for the auth tokens + cached laundry branding (Keychain / Keystore).
///
/// The tenant is NOT stored for request purposes: after login it comes from the JWT (`tid`).
/// The branding values below are only a display cache of the signed-in user's laundry.
class TokenStore {
  TokenStore(this._storage);
  final FlutterSecureStorage _storage;

  // Legacy key from the "pick your laundry before login" era — only ever deleted now.
  static const _kLegacyTenant = 'tenant_identifier';
  static const _kTenantName = 'tenant_name';
  static const _kTenantCurrency = 'tenant_currency';
  static const _kTenantLogo = 'tenant_logo_url';
  static const _kTenantAppName = 'tenant_app_name';
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kLocale = 'locale';
  static const _kThemeMode = 'theme_mode';

  Future<String?> get tenantName => _storage.read(key: _kTenantName);
  Future<String?> get tenantCurrency => _storage.read(key: _kTenantCurrency);
  Future<String?> get tenantLogoUrl => _storage.read(key: _kTenantLogo);
  Future<String?> get tenantAppName => _storage.read(key: _kTenantAppName);
  Future<String?> get accessToken => _storage.read(key: _kAccess);
  Future<String?> get refreshToken => _storage.read(key: _kRefresh);
  Future<String?> get locale => _storage.read(key: _kLocale);
  Future<String?> get themeMode => _storage.read(key: _kThemeMode);

  /// Cache the signed-in user's laundry branding (name / currency / logo / app name).
  Future<void> setBranding({required String name, String currency = 'SAR', String? logoUrl, String? appName}) async {
    await _storage.write(key: _kTenantName, value: name);
    await _storage.write(key: _kTenantCurrency, value: currency);
    await _write(_kTenantLogo, logoUrl);
    await _write(_kTenantAppName, appName);
  }

  Future<void> setTokens(String access, String refresh) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<void> setLocale(String code) => _storage.write(key: _kLocale, value: code);
  Future<void> setThemeMode(String v) => _storage.write(key: _kThemeMode, value: v);

  Future<void> clearTokens() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  /// Drop the cached laundry branding (logout: the next sign-in may be a different business).
  Future<void> clearBranding() async {
    await _storage.delete(key: _kLegacyTenant);
    await _storage.delete(key: _kTenantName);
    await _storage.delete(key: _kTenantCurrency);
    await _storage.delete(key: _kTenantLogo);
    await _storage.delete(key: _kTenantAppName);
  }

  /// Full session reset: tokens + branding.
  Future<void> clearAll() async {
    await clearTokens();
    await clearBranding();
  }

  Future<void> _write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }
}

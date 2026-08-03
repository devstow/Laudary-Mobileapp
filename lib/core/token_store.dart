import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure persistence for the selected tenant + auth tokens (Keychain / Keystore).
class TokenStore {
  TokenStore(this._storage);
  final FlutterSecureStorage _storage;

  static const _kTenant = 'tenant_identifier';
  static const _kTenantName = 'tenant_name';
  static const _kTenantCurrency = 'tenant_currency';
  static const _kTenantLogo = 'tenant_logo_url';
  static const _kTenantAppName = 'tenant_app_name';
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kLocale = 'locale';
  static const _kThemeMode = 'theme_mode';

  Future<String?> get tenant => _storage.read(key: _kTenant);
  Future<String?> get tenantName => _storage.read(key: _kTenantName);
  Future<String?> get tenantCurrency => _storage.read(key: _kTenantCurrency);
  Future<String?> get tenantLogoUrl => _storage.read(key: _kTenantLogo);
  Future<String?> get tenantAppName => _storage.read(key: _kTenantAppName);
  Future<String?> get accessToken => _storage.read(key: _kAccess);
  Future<String?> get refreshToken => _storage.read(key: _kRefresh);
  Future<String?> get locale => _storage.read(key: _kLocale);
  Future<String?> get themeMode => _storage.read(key: _kThemeMode);

  Future<void> setTenant(String identifier, String name,
      {String currency = 'SAR', String? logoUrl, String? appName}) async {
    await _storage.write(key: _kTenant, value: identifier);
    await _storage.write(key: _kTenantName, value: name);
    await _storage.write(key: _kTenantCurrency, value: currency);
    if (logoUrl != null) await _storage.write(key: _kTenantLogo, value: logoUrl);
    if (appName != null) await _storage.write(key: _kTenantAppName, value: appName);
  }

  Future<void> setTokens(String access, String refresh) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<void> setLocale(String code) => _storage.write(key: _kLocale, value: code);
  Future<void> setThemeMode(String v) => _storage.write(key: _kThemeMode, value: v);

  /// Clear tokens on logout — keep the tenant so re-login is fast.
  Future<void> clearTokens() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  /// Full reset (e.g. "change laundry").
  Future<void> clearAll() async {
    await clearTokens();
    await _storage.delete(key: _kTenant);
    await _storage.delete(key: _kTenantName);
    await _storage.delete(key: _kTenantCurrency);
    await _storage.delete(key: _kTenantLogo);
    await _storage.delete(key: _kTenantAppName);
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../core/api_client.dart';
import '../core/token_store.dart';
import '../l10n/l10n.dart';
import '../models/auth.dart';
import '../models/tenant.dart';
import '../services/auth_service.dart';
import 'theme_controller.dart';

enum AppStatus { bootstrapping, tenantNeeded, loggedOut, loggedIn }

/// Central session state: which laundry is selected + who is signed in, and the
/// top-level flow the app should show.
class AppState extends ChangeNotifier {
  AppState({
    required this.api,
    required this.store,
    required this.auth,
    required this.locale,
    required this.theme,
  }) {
    api.onSessionExpired = _onSessionExpired;
  }

  final ApiClient api;
  final TokenStore store;
  final AuthService auth;
  final LocaleController locale;
  final ThemeController theme;

  AppStatus status = AppStatus.bootstrapping;
  String? tenantIdentifier;
  String? tenantName;
  /// Tenant branding (dynamic, from the tenant's Appearance & Branding settings) — shown on the
  /// login/dashboard/profile chrome so each laundry sees its own logo + name.
  String? tenantLogoUrl;
  String? tenantAppName;
  /// The tenant's configured currency (Settings › Currency) — used to format ALL money in the
  /// app, exactly like the web portal's central formatter (symbol/code only, never converted).
  String currency = 'SAR';
  AuthUser? user;

  /// Display name for branding — tenant app name, else business name.
  String get brandName => (tenantAppName != null && tenantAppName!.isNotEmpty) ? tenantAppName! : (tenantName ?? 'SmartWash');
  bool get hasLogo => tenantLogoUrl != null && tenantLogoUrl!.isNotEmpty;

  Future<void> bootstrap() async {
    final savedLocale = await store.locale;
    if (savedLocale != null) locale.setLanguage(savedLocale);

    final savedTheme = await store.themeMode;
    theme.setMode(ThemeController.parse(savedTheme));

    tenantIdentifier = await store.tenant;
    tenantName = await store.tenantName;
    tenantLogoUrl = await store.tenantLogoUrl;
    tenantAppName = await store.tenantAppName;
    currency = await store.tenantCurrency ?? 'SAR';
    if (tenantIdentifier == null) {
      _set(AppStatus.tenantNeeded);
      return;
    }
    final token = await store.accessToken;
    // Restore the signed-in user from the stored token so a resumed session keeps
    // the customer's name/identity (the greeting, etc.) without needing a fresh login.
    if (token != null) user = AuthUser.fromJwt(token);
    _set(token == null ? AppStatus.loggedOut : AppStatus.loggedIn);
    // Refresh the tenant's configured currency from the public directory (best-effort) so the
    // app always formats money in the tenant currency — even for installs that predate this,
    // or if the tenant changed its currency. Mirrors the web's central currency provider.
    unawaited(_refreshTenantCurrency(tenantIdentifier!));
  }

  // Best-effort refresh of the tenant's CURRENT branding + currency from the public directory, so the
  // app always shows the latest logo/app-name/currency even if the tenant changed them after selection.
  Future<void> _refreshTenantCurrency(String identifier) async {
    try {
      final res = await api.dio.get('/api/public/tenants/$identifier');
      if (res.statusCode == 200 && res.data is Map) {
        final d = res.data as Map;
        final cur = (d['defaultCurrency'] as String?)?.trim();
        final logo = (d['logoUrl'] as String?)?.trim();
        final appName = (d['appName'] as String?)?.trim();
        var changed = false;
        if (cur != null && cur.isNotEmpty && cur != currency) { currency = cur; changed = true; }
        if (logo != tenantLogoUrl) { tenantLogoUrl = logo; changed = true; }
        if (appName != tenantAppName) { tenantAppName = appName; changed = true; }
        if (changed) {
          await store.setTenant(identifier, tenantName ?? identifier, currency: currency, logoUrl: logo, appName: appName);
          notifyListeners();
        }
      }
    } catch (_) {/* best-effort */}
  }

  Future<void> selectTenant(TenantDirectoryItem item) async {
    await store.setTenant(item.identifier, item.name,
        currency: item.defaultCurrency, logoUrl: item.logoUrl, appName: item.appName);
    tenantIdentifier = item.identifier;
    tenantName = item.name;
    tenantLogoUrl = item.logoUrl;
    tenantAppName = item.appName;
    currency = item.defaultCurrency;
    _set(AppStatus.loggedOut);
  }

  Future<void> changeLaundry() async {
    await store.clearAll();
    tenantIdentifier = null;
    tenantName = null;
    tenantLogoUrl = null;
    tenantAppName = null;
    currency = 'SAR';
    user = null;
    _set(AppStatus.tenantNeeded);
  }

  Future<void> onAuthenticated(AuthResult result) async {
    await store.setTokens(result.accessToken, result.refreshToken);
    user = result.user;
    _set(AppStatus.loggedIn);
  }

  Future<void> logout() async {
    final rt = await store.refreshToken;
    if (rt != null) await auth.logout(rt);
    await store.clearTokens();
    user = null;
    _set(AppStatus.loggedOut);
  }

  Future<void> setLanguage(String code) async {
    locale.setLanguage(code);
    await store.setLocale(code);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    theme.setMode(mode);
    await store.setThemeMode(theme.code);
  }

  void _onSessionExpired() {
    store.clearTokens();
    user = null;
    _set(AppStatus.loggedOut);
  }

  void _set(AppStatus s) {
    status = s;
    notifyListeners();
  }
}

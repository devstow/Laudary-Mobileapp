import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../core/api_client.dart';
import '../core/token_store.dart';
import '../core/realtime.dart';
import '../l10n/l10n.dart';
import '../models/auth.dart';
import '../models/tenant.dart';
import '../services/auth_service.dart';
import '../services/tenant_service.dart';
import 'theme_controller.dart';

enum AppStatus { bootstrapping, loggedOut, loggedIn }

/// Central session state: who is signed in, their laundry's branding, and the top-level flow
/// the app should show. The laundry (tenant) is never chosen before login — it comes from the
/// signed-in user's JWT (`tid`); the directory is only used to load that laundry's branding.
class AppState extends ChangeNotifier {
  AppState({
    required this.api,
    required this.store,
    required this.auth,
    required this.locale,
    required this.theme,
  }) : _tenants = TenantService(api) {
    api.onSessionExpired = _onSessionExpired;
  }

  final ApiClient api;
  final TokenStore store;
  final AuthService auth;
  final LocaleController locale;
  final ThemeController theme;
  final TenantService _tenants;
  /// Live updates from the API hub (orders/tasks/notifications) — connected for the signed-in session.
  late final RealtimeClient realtime = RealtimeClient(store);

  AppStatus status = AppStatus.bootstrapping;
  String? tenantName;
  /// Tenant branding (dynamic, from the tenant's Appearance & Branding settings) — shown on the
  /// dashboard/profile chrome so each laundry sees its own logo + name. Null → SmartWash default.
  String? tenantLogoUrl;
  String? tenantAppName;
  /// The tenant's configured currency (Settings › Currency) — used to format ALL money in the
  /// app, exactly like the web portal's central formatter (symbol/code only, never converted).
  String currency = 'SAR';
  AuthUser? user;

  /// Display name for branding — tenant app name, else business name, else SmartWash.
  String get brandName => (tenantAppName != null && tenantAppName!.isNotEmpty) ? tenantAppName! : (tenantName ?? 'SmartWash');
  bool get hasLogo => tenantLogoUrl != null && tenantLogoUrl!.isNotEmpty;

  Future<void> bootstrap() async {
    final savedLocale = await store.locale;
    if (savedLocale != null) locale.setLanguage(savedLocale);

    final savedTheme = await store.themeMode;
    theme.setMode(ThemeController.parse(savedTheme));

    final token = await store.accessToken;
    // Restore the signed-in user from the stored token so a resumed session keeps
    // the customer's name/identity (the greeting, etc.) without needing a fresh login.
    if (token != null) user = AuthUser.fromJwt(token);
    if (token == null || user == null) {
      await store.clearAll();
      user = null;
      _set(AppStatus.loggedOut);
      return;
    }
    tenantName = await store.tenantName;
    tenantLogoUrl = await store.tenantLogoUrl;
    tenantAppName = await store.tenantAppName;
    currency = await store.tenantCurrency ?? 'SAR';
    _set(AppStatus.loggedIn);
    unawaited(realtime.connect());
    // Refresh the laundry's CURRENT branding + currency (best-effort, never blocks the UI).
    unawaited(_refreshBranding(user!.tenantId));
  }

  /// Best-effort load of the signed-in laundry's branding + currency from the public directory.
  /// A 404 (platform tenant / not operational) or any error falls back to SmartWash defaults.
  Future<void> _refreshBranding(String tenantId) async {
    if (tenantId.isEmpty) return;
    try {
      final t = await _tenants.get(tenantId);
      if (user?.tenantId != tenantId) return; // signed out / switched meanwhile
      if (t == null) {
        _applyBranding(null, null, null, 'SAR');
        await store.clearBranding();
      } else {
        _applyBranding(t.name, t.logoUrl, t.appName, t.defaultCurrency);
        await store.setBranding(name: t.name, currency: t.defaultCurrency, logoUrl: t.logoUrl, appName: t.appName);
      }
      notifyListeners();
    } catch (_) {/* best-effort: keep cached/default branding */}
  }

  void _applyBranding(String? name, String? logo, String? appName, String cur) {
    tenantName = name;
    tenantLogoUrl = (logo != null && logo.trim().isNotEmpty) ? logo.trim() : null;
    tenantAppName = (appName != null && appName.trim().isNotEmpty) ? appName.trim() : null;
    currency = cur.trim().isEmpty ? 'SAR' : cur.trim();
  }

  /// Signed in (login, business choice or registration). [tenant] — the directory item the user
  /// just registered with — seeds the branding immediately; otherwise it loads in the background.
  Future<void> onAuthenticated(AuthResult result, {TenantDirectoryItem? tenant}) async {
    await store.setTokens(result.accessToken, result.refreshToken);
    user = result.user;
    if (tenant != null && tenant.id == result.user.tenantId) {
      _applyBranding(tenant.name, tenant.logoUrl, tenant.appName, tenant.defaultCurrency);
      await store.setBranding(name: tenant.name, currency: tenant.defaultCurrency, logoUrl: tenant.logoUrl, appName: tenant.appName);
    } else {
      _applyBranding(null, null, null, 'SAR');
      await store.clearBranding();
      unawaited(_refreshBranding(result.user.tenantId));
    }
    _set(AppStatus.loggedIn);
    unawaited(realtime.connect());
  }

  Future<void> logout() async {
    final rt = await store.refreshToken;
    if (rt != null) await auth.logout(rt);
    await _signedOut();
  }

  Future<void> setLanguage(String code) async {
    locale.setLanguage(code);
    await store.setLocale(code);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    theme.setMode(mode);
    await store.setThemeMode(theme.code);
  }

  void _onSessionExpired() => unawaited(_signedOut());

  // The next sign-in may be a different business, so drop the cached branding too.
  Future<void> _signedOut() async {
    await realtime.disconnect();
    await store.clearAll();
    user = null;
    _applyBranding(null, null, null, 'SAR');
    _set(AppStatus.loggedOut);
  }

  void _set(AppStatus s) {
    status = s;
    notifyListeners();
  }
}

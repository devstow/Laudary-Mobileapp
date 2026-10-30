import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/config.dart';
import 'core/token_store.dart';
import 'l10n/l10n.dart';
import 'services/ai_service.dart';
import 'services/auth_service.dart';
import 'services/delivery_service.dart';
import 'services/driver_profile_service.dart';
import 'services/notification_service.dart';
import 'services/order_service.dart';
import 'services/profile_service.dart';
import 'services/tenant_service.dart';
import 'core/realtime.dart';
import 'features/driver/location_tracker.dart';
import 'features/notifications/notification_center.dart';
import 'features/update/app_release.dart';
import 'features/update/update_controller.dart';
import 'state/app_state.dart';
import 'state/theme_controller.dart';

/// This build's versionCode (from APP_VERSION "1.0.6+2015"), null in dev builds.
int? get _buildNumber => int.tryParse(AppConfig.appVersion.split('+').last);

/// Release gate + diagnostics: every Dart error is reported to the server once (stage "dartError"), and "started"
/// is reported after the first frame — the proof tool/publish_apk.ps1 waits for before a build may go public.
void _installStartupReporting() {
  final releases = AppReleaseService();
  final sent = <String>{};
  void report(String stage, Object error, StackTrace? stack) {
    final text = '$error | ${stack ?? ''}';
    if (!sent.add(text.length > 300 ? text.substring(0, 300) : text) || sent.length > 20) return;
    unawaited(releases.report({'fromBuild': _buildNumber, 'toBuild': _buildNumber, 'stage': stage, 'detail': text.length > 3500 ? text.substring(0, 3500) : text}));
  }
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    report('dartError', details.exception, details.stack);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    report('dartError', error, stack);
    return false;
  };
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(releases.report({'fromBuild': _buildNumber, 'toBuild': _buildNumber, 'stage': 'started', 'detail': AppConfig.appVersion}));
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installStartupReporting();

  // A release build without an explicit HTTPS API URL can never reach a server: say so instead of
  // failing every request with a confusing "network error" (see AppConfig.releaseConfigError).
  final configError = AppConfig.releaseConfigError;
  if (configError != null) {
    runApp(_ConfigErrorApp(configError));
    return;
  }

  // Composition root: storage → api client → services → app state.
  final store = TokenStore(const FlutterSecureStorage());
  final api = ApiClient(store);
  final locale = LocaleController(null);
  final theme = ThemeController(ThemeMode.system);
  final auth = AuthService(api);

  final appState = AppState(api: api, store: store, auth: auth, locale: locale, theme: theme)..bootstrap();
  // In-app updates (sideloaded APK): checked before login / normal use, then periodically while open.
  final updates = UpdateController()..startup();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<TenantService>(create: (_) => TenantService(api)),
        Provider<AuthService>.value(value: auth),
        Provider<OrderService>(create: (_) => OrderService(api)),
        Provider<ProfileService>(create: (_) => ProfileService(api)),
        Provider<DeliveryService>(create: (_) => DeliveryService(api)),
        Provider<DriverProfileService>(create: (_) => DriverProfileService(api)),
        Provider<NotificationService>(create: (_) => NotificationService(api)),
        Provider<AiService>(create: (_) => AiService(api)),
        ChangeNotifierProvider<LocaleController>.value(value: locale),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<RealtimeClient>.value(value: appState.realtime),
        ChangeNotifierProvider<LocationTracker>.value(value: appState.tracker),
        ChangeNotifierProvider<UpdateController>.value(value: updates),
        ChangeNotifierProvider<NotificationCenter>.value(value: appState.notifications),
      ],
      child: const SmartWashApp(),
    ),
  );
}

/// Shown instead of the app when a release build was produced without its environment file.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text('Build configuration error', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

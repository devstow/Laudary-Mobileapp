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
import 'state/app_state.dart';
import 'state/theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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

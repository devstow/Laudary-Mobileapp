import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
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

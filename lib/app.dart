import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'features/auth/login_screen.dart';
import 'features/driver/driver_shell.dart';
import 'features/home/home_shell.dart';
import 'features/splash/splash_screen.dart';
import 'l10n/l10n.dart';
import 'state/app_state.dart';
import 'state/theme_controller.dart';
import 'theme/app_theme.dart';

class SmartWashApp extends StatelessWidget {
  const SmartWashApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().locale;
    final themeMode = context.watch<ThemeController>().mode;
    return MaterialApp(
      title: 'Smart Wash',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppDarkTheme(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Point the AppColors getters at the EFFECTIVE brightness before the
      // subtree builds, so direct AppColors.* references resolve correctly.
      builder: (context, child) {
        final brightness = switch (themeMode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
        };
        AppColors.brightness = brightness;
        return child!;
      },
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  // Keep the splash up for a short minimum so it reads as a deliberate brand moment
  // rather than a flash; session restore continues in parallel underneath.
  bool _splashMinElapsed = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _splashMinElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final status = _splashMinElapsed ? app.status : AppStatus.bootstrapping;
    final child = switch (status) {
      AppStatus.bootstrapping => const SplashScreen(),
      AppStatus.loggedOut => const LoginScreen(),
      // Same login, same app: route drivers to the driver experience, everyone else (customers) home.
      AppStatus.loggedIn => (app.user?.isDriver ?? false) ? const DriverShell() : const HomeShell(),
    };
    // Smooth cross-fade between top-level flows.
    return AnimatedSwitcher(duration: const Duration(milliseconds: 450), child: KeyedSubtree(key: ValueKey(status), child: child));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'features/auth/login_screen.dart';
import 'features/driver/driver_shell.dart';
import 'features/home/home_shell.dart';
import 'features/splash/splash_screen.dart';
import 'features/update/update_controller.dart';
import 'features/update/update_screen.dart';
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
      navigatorKey: rootNavigatorKey,
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
        AppStrings.current = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
        return UpdatePromptHost(child: child!);
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
    final updates = context.watch<UpdateController>();
    // The update check runs before login / normal use; the splash stays up until it has an answer (≤ ~8 s).
    final status = _splashMinElapsed && updates.startupResolved ? app.status : AppStatus.bootstrapping;
    if (status != AppStatus.bootstrapping && updates.gate) {
      return const KeyedSubtree(key: ValueKey('update-gate'), child: UpdateScreen());
    }
    final child = switch (status) {
      // While the start-up update check runs, say so (it can take a few seconds on a slow connection).
      AppStatus.bootstrapping => _splashMinElapsed && !updates.startupResolved
          ? Stack(children: [
              const SplashScreen(),
              Positioned(
                left: 0, right: 0, bottom: 48,
                child: Material(
                  type: MaterialType.transparency,
                  child: Text(context.t('Checking for updates…'), textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                ),
              ),
            ])
          : const SplashScreen(),
      AppStatus.loggedOut => const LoginScreen(),
      // Same login, same app: route drivers to the driver experience, everyone else (customers) home.
      AppStatus.loggedIn => (app.user?.isDriver ?? false) ? const DriverShell() : const HomeShell(),
    };
    // Smooth cross-fade between top-level flows.
    return AnimatedSwitcher(duration: const Duration(milliseconds: 450), child: KeyedSubtree(key: ValueKey(status), child: child));
  }
}

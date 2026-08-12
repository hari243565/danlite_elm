import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'constants/framework_locale_fallback.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/dtc_screen.dart';
import 'screens/realtime_screen.dart';
import 'screens/performance_screen.dart';
import 'screens/fuel_screen.dart';
import 'screens/hud_screen.dart';
import 'screens/graph_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vehicle_profile_screen.dart';
import 'screens/trip_history_screen.dart';
import 'screens/about_screen.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/otp_verify_screen.dart';

class DanliteELMApp extends StatelessWidget {
  const DanliteELMApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      // ValueKey forces complete widget tree rebuild when language changes
      key: ValueKey(settings.locale.languageCode),
      title: 'OBD Danlite',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.18)),
        child: child!,
      ),
      // `locale` reflects the user's full 23-language selection (drives our
      // own AppStrings/context.tr() UI text). `supportedLocales` +
      // `localeListResolutionCallback` below constrain what actually reaches
      // MaterialLocalizations/WidgetsLocalizations/CupertinoLocalizations so
      // a language Flutter's framework doesn't ship (e.g. Maithili) can
      // never leave those delegates unresolved and crash the widget tree —
      // see constants/framework_locale_fallback.dart for the fallback map.
      locale: settings.locale,
      supportedLocales: kFrameworkSupportedLocales,
      localeListResolutionCallback: (locales, supportedLocales) {
        final requested =
            (locales != null && locales.isNotEmpty) ? locales.first : settings.locale;
        return resolveFrameworkLocale(requested);
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // The gate shows the existing SplashScreen while auth state resolves,
      // then sends the user to /home, /login or /otp. '/splash' itself is
      // unchanged and still routable.
      initialRoute: '/auth',
      routes: {
        '/auth': (_) => const AuthGate(),
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/otp': (_) => const OtpVerifyScreen(),
        '/splash': (_) => const SplashScreen(),
        '/home': (_) => const HomeScreen(),
        '/connect': (_) => const ConnectionScreen(),
        '/dashboard': (_) => const DashboardScreen(),
        '/dtc': (_) => const DtcScreen(),
        '/realtime': (_) => const RealtimeScreen(),
        '/performance': (_) => const PerformanceScreen(),
        '/fuel': (_) => const FuelScreen(),
        '/hud': (_) => const HudScreen(),
        '/graph': (_) => const GraphScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/vehicles': (_) => const VehicleProfileScreen(),
        '/trips': (_) => const TripHistoryScreen(),
        '/about': (_) => const AboutScreen(),
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'constants/framework_locale_fallback.dart';
import 'providers/entitlement_provider.dart';
import 'providers/settings_provider.dart';
import 'services/entitlement_service.dart';
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
import 'screens/account_screen.dart';
import 'screens/vehicle_profile_screen.dart';
import 'screens/trip_history_screen.dart';
import 'screens/about_screen.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/otp_verify_screen.dart';
import 'screens/paywall_screen.dart';

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
      // The global text scale, plus the bottom reserve for the offline-grace
      // banner. The banner is a root OverlayEntry, so it takes part in no
      // screen's layout and cannot push content out of its own way; without a
      // reserve it floats over scrolled list content on longer screens. Adding
      // the space here means every scrollable's own safe-area maths leaves room
      // for it, with no per-screen change.
      //
      // Selector, not watch(): the entitlement provider notifies on every poll,
      // and `child` (the whole Navigator subtree) is passed straight through so
      // only this MediaQuery wrapper rebuilds — and only when the boolean
      // actually flips, not on each poll.
      builder: (context, child) => Selector<EntitlementProvider, bool>(
        selector: (_, e) => e.status == EntitlementStatus.offlineGraceActive,
        child: child,
        builder: (context, graceActive, inner) {
          final scaled = MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.18));
          // When the banner is not showing the data is returned untouched, so
          // the common case (online, active licence) is byte-identical to the
          // behaviour before this change.
          if (!graceActive) {
            return MediaQuery(data: scaled, child: inner!);
          }
          // `padding` only — deliberately NOT `viewPadding`. _GraceBanner
          // positions itself from `viewPadding.bottom`, and it lives in the
          // root Navigator's Overlay, which is a descendant of this MediaQuery.
          // Inflating viewPadding here would therefore push the banner itself
          // up by the same amount it reserves. `padding` is what a padding-less
          // ListView consumes for its own bottom inset, which is exactly the
          // space we need.
          return MediaQuery(
            data: scaled.copyWith(
              padding: scaled.padding.copyWith(
                bottom: scaled.padding.bottom + kGraceBannerReservedSpace,
              ),
            ),
            child: inner!,
          );
        },
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
        // (Phase 8) The only route added by the paywall phase. The recoverable
        // "connect once to activate" screen deliberately has NO route: it is
        // mounted inside the gate's own private navigator, so nothing can
        // reach it — or walk past it — by name.
        '/paywall': (_) => const PaywallScreen(),
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
        // The single route added by the account-detail task. Reached only from
        // the Settings summary row; it sits inside the gate like every other
        // route here, so it is unreachable without an entitled session.
        '/account': (_) => const AccountScreen(),
        '/vehicles': (_) => const VehicleProfileScreen(),
        '/trips': (_) => const TripHistoryScreen(),
        '/about': (_) => const AboutScreen(),
      },
    );
  }
}

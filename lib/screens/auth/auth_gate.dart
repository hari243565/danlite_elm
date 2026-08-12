import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../splash_screen.dart';

/// The app's entry route. It shows the existing splash while auth state is
/// still unknown, then hands control to exactly one destination.
///
/// The splash is reused as-is — its UI is not duplicated. It is mounted inside
/// a private [Navigator] so that its own 2.4-second
/// `pushReplacementNamed('/home')` timer can never leave the gate: that push
/// is absorbed by the private navigator, which simply shows the splash again.
/// Auth decides where the user goes; a timer does not.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _navigated = false;

  void _routeFor(AuthStatus status, bool isConfigured) {
    if (_navigated || status == AuthStatus.unknown) return;

    // Phase 2 adds no paywall. With no backend configured the diagnostics app
    // must behave exactly as it did before this phase existed.
    // Phase 8 replaces this with a fail-closed entitlement check.
    final String route;
    if (!isConfigured) {
      route = '/home';
    } else {
      switch (status) {
        case AuthStatus.signedIn:
          route = '/home';
        case AuthStatus.awaitingOtp:
          route = '/otp';
        case AuthStatus.signedOut:
        case AuthStatus.unknown:
          route = '/login';
      }
    }

    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushReplacementNamed(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _routeFor(auth.status, auth.isConfigured);

    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => const SplashScreen(),
      ),
    );
  }
}

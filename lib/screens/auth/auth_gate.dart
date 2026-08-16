import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/entitlement_provider.dart';
import '../../services/entitlement_service.dart';
import '../../services/obd_service.dart';
import '../paywall_screen.dart';
import '../splash_screen.dart';

/// The app's entry route, and (Phase 8) the ONLY place in the app where a
/// licence decides what a user may see.
///
/// The splash is reused as-is — its UI is not duplicated. It is mounted inside
/// a private [Navigator] so that its own 2.4-second
/// `pushReplacementNamed('/home')` timer can never leave the gate: that push
/// is absorbed by the private navigator, which simply shows the splash again.
/// Auth decides where the user goes; a timer does not. Phase 8 keeps that
/// mechanism exactly as Phase 2 built it — it is now also what stops the
/// splash timer walking past the paywall.
///
/// ══════════════════════════════════════════════════════════════════════════
/// THE DECISION TABLE (Phase 8)
/// ══════════════════════════════════════════════════════════════════════════
///
///   backend not configured in this build → ALLOW  (pre-Phase-8 behaviour)
///   auth unknown                         → splash (bounded by AuthProvider's
///                                          own 6s fallback)
///   auth signedOut                       → /login
///   auth awaitingOtp                     → /otp
///
///   then, and only for a signed-in user:
///
///   active              → ALLOW
///   offlineGraceActive  → ALLOW, with the grace banner
///   inactive            → BLOCK, /paywall
///   revoked / refunded  → BLOCK, /paywall   (folded into `revoked`)
///   expired             → BLOCK, /paywall, with the distinct "reconnect"
///                         wording — a genuinely more recoverable situation
///   supersededSession   → NOT the paywall. Phase 7 signs the user out and
///                         the gate follows them to /login. Held on the splash
///                         while that lands, then falls to the recoverable
///                         screen rather than hanging forever.
///   unknown             → splash for at most [_kUnknownTimeout], then the
///                         recoverable [ConnectOnceScreen]
///
/// `unknown` is the only status that can mean "we do not know", and — given a
/// signed-in user — it always implies there is no usable cached token:
/// EntitlementService only returns `EntitlementResult.none` when the cache is
/// absent, unreadable, unparseable or fails its own signature. Every network
/// error, timeout, 5xx, relay failure and unparseable body is funnelled
/// through `readCached()`, so with a valid cached token those all arrive here
/// as `offlineGraceActive` — which ALLOWS. No ambiguous condition can block.
/// ══════════════════════════════════════════════════════════════════════════

/// How long the gate will sit on the splash waiting for `unknown` to resolve
/// before it stops waiting and shows the recoverable screen.
///
/// Bounded deliberately. EntitlementService's own network timeout is 15s, so a
/// truly dead connection would otherwise hold the splash for that long with no
/// explanation and no way out. Eight seconds is long enough for a slow garage
/// connection to land a reply and short enough that nobody thinks the app has
/// hung. The wait is not a lockout: it ends in a screen with a Retry button.
const Duration _kUnknownTimeout = Duration(seconds: 8);

/// What the gate decided to do. Exhaustive over the inputs — see [gateDecision].
enum GateDecision {
  /// Hold the splash. Bounded; never terminal.
  wait,

  /// Full app.
  allow,

  /// Full app, plus the offline-grace banner.
  allowWithGrace,

  /// Paywall — the server affirmatively said this account has no licence, or
  /// that it was revoked or refunded.
  blockNoLicence,

  /// Paywall, "reconnect to verify" wording — a cached token ran past its
  /// 14-day window (or the device clock was rolled back behind a time the
  /// server has already attested).
  blockExpired,

  /// The recoverable "connect once to activate" screen. Ambiguity, never a
  /// lockout.
  activate,

  /// Not signed in.
  login,

  /// A code has been sent and not yet entered.
  otp,
}

/// The whole gate, as a pure function. Written this way on purpose: the claim
/// that "no ambiguous condition can block a paying customer" is a claim about
/// this function, and it can be read in one sitting with no widget tree in the
/// way.
///
/// Anything not named below resolves to [GateDecision.allow].
GateDecision gateDecision({
  required AuthStatus auth,
  required bool isConfigured,
  required EntitlementStatus entitlement,
  required bool waitElapsed,
}) {
  if (auth == AuthStatus.unknown) return GateDecision.wait;

  // A build with no backend configured must behave exactly as it did before
  // this phase existed. This is the Phase 2 rule, kept: a packaging fault that
  // loses the .env is a fault in this app, and it must not present itself to a
  // mechanic as "you have not paid".
  if (!isConfigured) return GateDecision.allow;

  switch (auth) {
    case AuthStatus.signedOut:
      return GateDecision.login;
    case AuthStatus.awaitingOtp:
      return GateDecision.otp;
    case AuthStatus.unknown:
    case AuthStatus.signedIn:
      break;
  }

  switch (entitlement) {
    case EntitlementStatus.active:
      return GateDecision.allow;

    case EntitlementStatus.offlineGraceActive:
      // A verified, unexpired, signature-checked token that came off disk
      // because the network was not reachable. This ALLOWS regardless of what
      // the licence string inside it says, and that is a deliberate leniency:
      // blocking here would lock out the customer who paid five minutes ago,
      // drove into a basement garage, and is carrying a token issued before
      // the payment landed. The cost of the other choice is 14 days of use by
      // somebody who never paid and then stayed offline — recoverable. The
      // cost of this choice being wrong is a paying mechanic with a car on the
      // ramp and no diagnostics.
      return GateDecision.allowWithGrace;

    case EntitlementStatus.inactive:
    case EntitlementStatus.revoked:
      // The ONLY two statuses the server can state affirmatively that block.
      // Both require a live, signature-verified reply. Neither is reachable
      // from a failure of any kind.
      return GateDecision.blockNoLicence;

    case EntitlementStatus.expired:
      return GateDecision.blockExpired;

    case EntitlementStatus.supersededSession:
      // Phase 7's business, not the paywall's. It has already called
      // AuthProvider.forceLogoutSuperseded(); auth is about to become
      // signedOut and this gate will send the user to /login. Hold the splash
      // meanwhile — but not forever: if the sign-out somehow never lands, fall
      // through to a screen that has a Retry and a Log out on it rather than
      // spinning indefinitely.
      return waitElapsed ? GateDecision.activate : GateDecision.wait;

    case EntitlementStatus.unknown:
      // "We do not know yet" — never "not entitled".
      //
      // For a signed-in user this always means there is no usable cached
      // token: EntitlementService returns `EntitlementResult.none` only when
      // the cache is absent, unreadable, unparseable or fails its own
      // signature. So there is nothing to fall through TO, and the honest
      // answer is the recoverable screen — after a bounded wait, never
      // instantly, because a gate mounted the instant after an OTP is verified
      // is looking at a refresh that has not started yet.
      return waitElapsed ? GateDecision.activate : GateDecision.wait;
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _navigated = false;
  bool _waitElapsed = false;
  Timer? _waitTimer;

  @override
  void initState() {
    super.initState();
    _waitTimer = Timer(_kUnknownTimeout, () {
      if (!mounted || _waitElapsed) return;
      setState(() => _waitElapsed = true);
    });
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }

  /// Never called from build(). Same post-frame pattern Phase 2 established.
  void _routeFor(GateDecision decision) {
    if (_navigated) return;

    final String route;
    switch (decision) {
      case GateDecision.wait:
      case GateDecision.activate:
        // Rendered by this widget; nothing is pushed and the gate stays
        // mounted so it can keep re-deciding.
        return;
      case GateDecision.allow:
      case GateDecision.allowWithGrace:
        route = '/home';
      case GateDecision.blockNoLicence:
      case GateDecision.blockExpired:
        route = '/paywall';
      case GateDecision.login:
        route = '/login';
      case GateDecision.otp:
        route = '/otp';
    }

    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Install the sentinel BEFORE leaving. Once this route is replaced the
      // gate is gone, and the sentinel is what keeps watching.
      _GateSentinel.ensureInstalled(context);
      Navigator.of(context, rootNavigator: true).pushReplacementNamed(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final entitlement = context.watch<EntitlementProvider>();

    final decision = gateDecision(
      auth: auth.status,
      isConfigured: auth.isConfigured,
      entitlement: entitlement.status,
      waitElapsed: _waitElapsed,
    );

    _routeFor(decision);

    // The recoverable screen is returned DIRECTLY, not through the private
    // navigator below. That navigator builds its route exactly once, via
    // onGenerateRoute, and never rebuilds it — so putting the two screens
    // behind a conditional inside that builder would have left the splash on
    // screen forever when the 8-second timeout fired. A hang on the splash is
    // a lockout by another name.
    //
    // Nothing is lost by returning it plainly: the private navigator exists
    // only to swallow the splash's own timer, and the recoverable screen has
    // no timer to swallow.
    if (decision == GateDecision.activate) return const ConnectOnceScreen();

    // The private navigator is the Phase 2 mechanism and is preserved exactly:
    // whatever the splash pushes is absorbed here and never reaches the root
    // navigator, so a 2.4-second timer can never walk past this gate.
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => const SplashScreen(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// THE SENTINEL — the gate after the gate
//
// AuthGate replaces itself the moment it decides, which is correct (pressing
// back from /home must exit the app, not reveal a splash) but leaves nobody
// watching. Phase 8 needs somebody watching for two reasons:
//
//   1. A revocation or a refund arriving mid-session has to take effect.
//   2. The offline-grace banner has to be visible over the app's own screens,
//      and no screen file may be modified to host it.
//
// It also closes a pre-existing hole. Phase 7's forced sign-out relies on "the
// Phase 2 AuthGate does the redirect", but by then the gate has already been
// replaced by /home and is not mounted — so a superseded device would have
// been signed out at the SDK level while continuing to show the app. The
// sentinel watches AuthProvider too and follows the user to /login.
//
// It lives in a root OverlayEntry, which sits above every route without being
// one, and is wrapped in IgnorePointer so it can never intercept a tap meant
// for a gauge. A language change rebuilds MaterialApp (its ValueKey) and with
// it the Overlay; the gate re-runs from `initialRoute` and installs a fresh
// entry, so the sentinel is self-healing.
// ══════════════════════════════════════════════════════════════════════════

class _GateSentinel {
  _GateSentinel._();

  static OverlayEntry? _entry;
  static OverlayState? _host;

  static void ensureInstalled(BuildContext context) {
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null || !overlay.mounted) return;
    if (_entry != null && identical(_host, overlay)) return;

    // The previous entry, if any, belonged to an Overlay that has already been
    // disposed along with its MaterialApp. It is not removed — removing from a
    // dead overlay is what throws — it is simply dropped.
    final entry = OverlayEntry(builder: (_) => const _SentinelWidget());
    _entry = entry;
    _host = overlay;
    overlay.insert(entry);
  }
}

class _SentinelWidget extends StatefulWidget {
  const _SentinelWidget();

  @override
  State<_SentinelWidget> createState() => _SentinelWidgetState();
}

class _SentinelWidgetState extends State<_SentinelWidget> {
  /// Null until the first build. The first build ADOPTS the current state
  /// without acting on it — the gate has just made that same decision, and
  /// acting again here would double-navigate.
  bool? _wasBlocked;
  AuthStatus? _lastAuth;
  bool _acting = false;

  void _react(GateDecision decision, AuthStatus authStatus, ObdService obd) {
    final blocked = decision == GateDecision.blockNoLicence ||
        decision == GateDecision.blockExpired;

    final previousBlocked = _wasBlocked;
    final previousAuth = _lastAuth;
    _wasBlocked = blocked;
    _lastAuth = authStatus;

    if (previousBlocked == null || previousAuth == null) return;
    if (_acting) return;

    // Signed out while the app was running — ordinary logout from the paywall,
    // or Phase 7's forced one. Either way the user belongs at /login.
    if (authStatus == AuthStatus.signedOut &&
        previousAuth != AuthStatus.signedOut) {
      _schedule(() async => _go('/login'));
      return;
    }

    // Everything below is about a session that was ALREADY running. A user who
    // has just signed in is the gate's business, not the sentinel's — both
    // reacting to the same first decision would push the same route twice.
    if (previousAuth != AuthStatus.signedIn) return;

    // Access withdrawn mid-session.
    if (blocked && !previousBlocked) {
      _schedule(() async {
        // A dangling ELM327 connection is worse than no connection: the
        // adapter stays claimed and the next app cannot open it. Close it
        // cleanly first. ObdService is not modified — only called.
        if (obd.isConnected) {
          try {
            await obd.disconnect();
          } catch (_) {
            // A failed disconnect must not stop the gate from applying.
          }
        }
        _go('/paywall');
      });
      return;
    }

    // Access restored mid-session — a purchase landed, or a refresh on the
    // paywall succeeded. Let the user straight back in.
    if (!blocked &&
        previousBlocked &&
        (decision == GateDecision.allow ||
            decision == GateDecision.allowWithGrace)) {
      _schedule(() async => _go('/home'));
    }
  }

  /// Nothing here may run during build.
  void _schedule(Future<void> Function() action) {
    _acting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        await action();
      } finally {
        _acting = false;
      }
    });
  }

  void _go(String route) {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil(route, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final entitlement = context.watch<EntitlementProvider>();
    final obd = context.read<ObdService>();

    final decision = gateDecision(
      auth: auth.status,
      isConfigured: auth.isConfigured,
      entitlement: entitlement.status,
      // The sentinel only ever runs after the gate has already navigated, so
      // there is no splash left to wait on. It never resolves to `wait`.
      waitElapsed: true,
    );

    _react(decision, auth.status, obd);

    if (decision != GateDecision.allowWithGrace) {
      return const Positioned(width: 0, height: 0, top: 0, left: 0,
          child: SizedBox.shrink());
    }
    return _GraceBanner(days: entitlement.graceDaysRemaining);
  }
}

// ══════════════════════════════════════════════════════════════════════════
// OFFLINE-GRACE BANNER
//
// Placement: floating just BELOW where a standard AppBar ends, horizontally
// centred, inside the root overlay. It is not inside any screen and it changes
// no screen's layout — an overlay does not participate in layout at all — and
// it is wrapped in IgnorePointer so it cannot swallow a tap on the content
// beneath it. No file under lib/screens/ other than this one and the new
// paywall was touched to put it there.
//
// Muted, not red. The point is to stop a mechanic being surprised on day 14,
// not to nag somebody who is working normally in a basement with no signal.
// ══════════════════════════════════════════════════════════════════════════
class _GraceBanner extends StatelessWidget {
  const _GraceBanner({required this.days});

  final int? days;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF131922);
    const border = Color(0xFF1C2A3A);
    const muted = Color(0xFF607080);

    final d = days;
    final String label;
    if (d == null || d <= 0) {
      label = context.tr('grace_banner_last_day');
    } else if (d == 1) {
      // Its own key rather than a substitution, so no language ends up saying
      // "1 days". Only en and hi are authored here; the rest fall back to
      // English through AppStrings.get, exactly as every other new key does.
      label = context.tr('grace_banner_one_day');
    } else {
      label = context.trArgs('grace_banner_days', {'days': '$d'});
    }

    // Anchored to the BOTTOM, not under the app bar. An overlay sits outside
    // every route, so it cannot measure the chrome of the screen it floats
    // over — and "the header" is not one bar but two: /home draws its own
    // AppBar, and the nested Scaffold inside it (dashboard, live data) draws
    // another directly beneath. A top offset that clears one lands on the
    // other, which is exactly what `padding.top + kToolbarHeight` did: it
    // covered "Danlite" and the button beside it. The bottom band is the only
    // strip that is chrome-free on every screen, once three things are
    // cleared: the gesture inset, /home's bottom navigation bar, and the
    // connection ribbon that stacks on top of that bar while an adapter is
    // connected. `viewInsets` keeps it above an open keyboard too.
    const double kNavBar = kBottomNavigationBarHeight;
    const double kRibbon = 28; // connection status ribbon
    const double kGap = 8;
    final mq = MediaQuery.of(context);

    return Positioned(
      bottom: mq.viewInsets.bottom +
          mq.viewPadding.bottom +
          kNavBar +
          kRibbon +
          kGap,
      left: 0,
      right: 0,
      child: IgnorePointer(
        // Aligned to the trailing edge, not centred. The drawer opens from the
        // leading edge and covers ~three quarters of the width with its own
        // rows, so a centred pill sits on top of them. Directional rather than
        // absolute so it stays opposite the drawer in an RTL locale.
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: bg.withValues(alpha: 0.92),
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, color: muted, size: 13),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    // `inherit: false` is the whole fix for the styling. A
                    // root OverlayEntry has no Material and no
                    // DefaultTextStyle ancestor, so an inheriting style merges
                    // into Flutter's fallback and silently keeps every field
                    // this one does not name — the monospace family and the
                    // yellow double underline that shipped in the screenshot.
                    // Not inheriting means the style below is the whole style.
                    style: const TextStyle(
                      inherit: false,
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

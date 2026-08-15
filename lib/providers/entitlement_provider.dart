import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/entitlement_service.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';

/// Danlite ELM — entitlement state (Phase 3)
///
/// Computes and exposes the current entitlement status. It does NOT navigate,
/// block, gate, or alter any UI — Phase 8 owns the paywall. Nothing in the app
/// reads this provider yet; it exists so that when Phase 8 arrives, the state
/// it needs is already correct, already verified, and already offline-capable.
///
/// Refresh triggers:
///   • [init], once, at startup after AuthProvider
///   • app resume (WidgetsBindingObserver — the codebase has no pre-existing
///     lifecycle or connectivity listener to follow, so this is the first)
///   • a 6-hourly timer, only while the app is foregrounded
///   • sign-in / sign-out, via the Supabase auth stream
class EntitlementProvider extends ChangeNotifier with WidgetsBindingObserver {
  EntitlementProvider({EntitlementService? service, SupabaseService? supabase})
      : _service = service ?? EntitlementService(),
        _svc = supabase ?? SupabaseService.instance;

  final EntitlementService _service;
  final SupabaseService _svc;

  /// How often to re-check while the app is open. The token lasts 14 days, so
  /// this is about noticing a revocation or a completed purchase reasonably
  /// promptly, not about staying alive.
  static const Duration _refreshInterval = Duration(hours: 6);

  Timer? _timer;
  StreamSubscription<AuthState>? _authSub;
  bool _disposed = false;

  EntitlementResult _result =
      const EntitlementResult.none('not initialised');

  /// The full verified result, including the raw licence string and expiry.
  EntitlementResult get result => _result;

  /// The current entitlement status. This is what Phase 8 will read.
  EntitlementStatus get status => _result.status;

  /// The licence status exactly as the server stated it ('inactive', 'active',
  /// 'revoked', 'refunded'), or null when nothing is known.
  String? get rawLicence => _result.rawLic;

  /// True while a refresh is in flight.
  bool _busy = false;
  bool get busy => _busy;

  /// Whether the app is currently running on a cached token because the
  /// network was unreachable.
  bool get isOffline => _result.source == EntitlementSource.cache;

  /// Seconds of offline grace remaining, or null when there is no usable
  /// token. Phase 8 may want to warn as this approaches zero.
  int? get remainingGraceSeconds => _result.remainingGraceSeconds(
      DateTime.now().millisecondsSinceEpoch ~/ 1000);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Called from main.dart after AuthProvider.init(). Never throws: a failure
  /// here must not stop the diagnostics app from starting, exactly as with
  /// SupabaseService and AuthProvider.
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);

    // Re-check whenever the user signs in or out. Without this, a user who
    // signs in after launch would carry `unknown` until the 6-hour timer or the
    // next resume, and a signed-out user's token would linger in storage.
    if (_svc.isConfigured) {
      _authSub = _svc.onAuthStateChange.listen(
        _onAuthState,
        onError: (Object e) =>
            debugPrint('[entitlement] auth stream error: ${e.runtimeType}'),
      );
    }

    _startTimer();
    await refresh();
  }

  void _onAuthState(AuthState state) {
    switch (state.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.initialSession:
        unawaited(refresh());
      case AuthChangeEvent.signedOut:
        unawaited(_onSignedOut());
      default:
        break;
    }
  }

  Future<void> _onSignedOut() async {
    // Drop the cached token so the next user on this device can never be shown
    // the previous user's entitlement. The clock watermark deliberately
    // survives — see EntitlementService.clear().
    await _service.clear();
    _set(const EntitlementResult.none('signed out'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      unawaited(refresh());
    } else if (state == AppLifecycleState.paused) {
      // No point burning a timer in the background; it is restarted on resume.
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_refreshInterval, (_) => unawaited(refresh()));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _authSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  /// Fetches and verifies a fresh token, falling back to the verified cache
  /// when the network is unavailable. Safe to call at any time; overlapping
  /// calls are collapsed.
  Future<void> refresh() async {
    if (_busy || _disposed) return;
    _busy = true;
    _notify();

    try {
      // fetchAndVerify already falls through to the cached path internally on
      // any network or verification failure, so there is no second call here.
      final res = await _service.fetchAndVerify();
      _set(res);

      // ══════════════════════════════════════════════════════════════════
      // (Phase 7) The ONE place in the app that acts on a supersession.
      // ══════════════════════════════════════════════════════════════════
      //
      // Reaching this line requires EntitlementService to have received an
      // explicit, successfully-parsed HTTP 409 SESSION_SUPERSEDED from the
      // Edge Function. Every ambiguous outcome — offline, timeout, 5xx,
      // unparseable body, bad signature, a 409 that did not say
      // SESSION_SUPERSEDED — resolves to some OTHER status before it gets
      // here and therefore cannot sign anybody out.
      //
      // The sign-out itself goes through the ordinary Supabase auth path, so
      // the Phase 2 AuthGate does the redirect. There is no navigation code
      // in this phase and no screen was modified.
      if (res.status == EntitlementStatus.supersededSession) {
        debugPrint('[entitlement] superseded — signing out via the auth gate');
        await AuthProvider.forceLogoutSuperseded();
      }
    } catch (e) {
      // Defensive: the service is documented not to throw, but a provider that
      // takes the app down on launch would be a far worse bug than a stale
      // status.
      debugPrint('[entitlement] refresh failed: ${e.runtimeType}');
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _set(EntitlementResult res) {
    _result = res;
    debugPrint('[entitlement] $res');
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}

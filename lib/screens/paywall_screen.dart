import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionsHttpException;

import '../constants/app_strings.dart';
import '../providers/auth_provider.dart';
import '../providers/entitlement_provider.dart';
import '../providers/settings_provider.dart';
import '../services/entitlement_service.dart';
import '../services/supabase_service.dart';

// ══════════════════════════════════════════════════════════════════════════
// [CONFIRM] SUPPORT CONTACT — PLACEHOLDER, NOT THE REAL ADDRESS.
//
// The real support address is a client decision and has not been given. It is
// declared here, once, so there is exactly one line to change. It is rendered
// as selectable text and is deliberately NOT a tappable mailto: link — see the
// hard constraint below.
// ══════════════════════════════════════════════════════════════════════════
const String kPaywallSupportContact = 'support@danlite.example'; // [CONFIRM]

// ══════════════════════════════════════════════════════════════════════════
// HARD CONSTRAINT — THERE IS NO PURCHASE PATH ON THIS SCREEN.
//
// No price, no numeral representing a cost, no URL, no tappable link, no
// "buy" affordance, and no mention of a website or of where to buy. This is
// not a styling preference: an in-app tap that leads to a purchase makes the
// purchase an in-app purchase, which costs 20% and defeats the entire
// architecture Phases 4-6 exist to build. The customer learns how to buy from
// the activation email, outside the app.
//
// Anything added to this file must be checked against that list. The strings
// live in app_strings.dart under the `paywall_` / `activate_` prefixes and are
// quoted verbatim in portal/phase8-report.json so they can be audited by
// reading rather than by trusting.
// ══════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════
// SELF-SERVE ACTIVATION-LINK RESEND — WHICH MECHANISM, AND WHY.
//
// The button added below calls the EXISTING /send-activation Edge Function.
// It creates no second mechanism, mints no token of its own, and sends no
// mail of its own; the entire token-issuing and delivery path is the one
// already proven end to end.
//
// PATH B, NOT PATH A. That function has two callers (see its header):
//
//   Path A — the signup database trigger. Names a user_id outright and
//     authenticates with ACTIVATION_WEBHOOK_SECRET. NOT usable from here: the
//     app would have to carry that secret in the APK, where anyone with
//     `strings` could lift it and mint an activation link for any user_id
//     they liked. The secret stays in Vault, server side, permanently.
//
//   Path B — "a human who did not get the email". Submits an identifier,
//     never a user id, and is rate-limited and enumeration-safe precisely
//     because it is reachable by anyone. That is exactly this button's
//     situation, and it is the path taken.
//
// WHOSE ADDRESS IS SUBMITTED. Only `AuthProvider.user.email` — the address of
// the session this device is already signed in to. There is no text field,
// so this screen cannot be pointed at a third party's inbox at all. The
// enumeration-safe wording is kept anyway because the response genuinely
// cannot distinguish outcomes, so promising more would be a lie.
//
// THROTTLING — REUSED, NOT INVENTED. The authoritative limits already exist
// in /send-activation as MAX_PER_IDENTIFIER_PER_HOUR = 3 and
// MAX_PER_IP_PER_HOUR = 10, counted over a rolling hour in the
// activation_requests ledger, which logs blocked attempts too so hammering
// cannot roll the window forward. Nothing here re-implements or second-
// guesses that. [_kResendCooldownSeconds] below is a UI guard on top of it,
// not a policy of its own — see its note.
// ══════════════════════════════════════════════════════════════════════════

/// Seconds the resend button stays disabled after the server has answered.
///
/// NOT a rate limit. The real limit is the server's three-per-hour budget
/// described above, and this cannot relax it — a patched APK that removed
/// this line would still be refused by /send-activation on the fourth try
/// within an hour. Its only job is to stop an impatient double-tap from
/// spending two of those three attempts in the same second.
///
/// The value is the one the OTP screen already uses for the same purpose
/// (`_kResendCooldownSeconds` in otp_verify_screen.dart), so a customer meets
/// one resend rhythm in this app rather than two.
const int _kResendCooldownSeconds = 30;

/// Ceiling on the resend call. Matches the timeouts the entitlement and
/// session services put on their own function calls.
const Duration _kResendTimeout = Duration(seconds: 20);

/// Unified Telemetry Design System Palette — same values the auth, dashboard,
/// home and DTC screens declare locally.
class _C {
  static const Color bg = Color(0xFF07090E);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color text = Color(0xFFEEF2F8);
  static const Color muted = Color(0xFF607080);
  static const Color cyan = Color(0xFF00CAFF);
  static const Color green = Color(0xFF00E39C);
}

/// The paywall. Reached only from the gate, and only for a state where the
/// server has affirmatively said this account is not entitled, or where a
/// cached token has run past its 14-day offline window.
///
/// It never appears for a network error, a timeout, a 5xx or an unparseable
/// reply — those all resolve to "allow" or to the recoverable
/// [ConnectOnceScreen]. See auth_gate.dart for the decision table.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _checking = false;

  /// AppStrings key for the outcome of the last Refresh, or null before the
  /// first one. Never a server or exception string.
  String? _outcomeKey;

  // ── Resend state ────────────────────────────────────────────────────────

  bool _resending = false;
  Timer? _resendTimer;
  int _resendSecondsLeft = 0;

  /// AppStrings key for the outcome of the last resend. Held separately from
  /// [_outcomeKey] so that a Refresh result and a resend result never
  /// overwrite one another — they answer two different questions and a
  /// customer may reasonably want both on screen at once.
  String? _resendOutcomeKey;

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    _resendSecondsLeft = _kResendCooldownSeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendSecondsLeft--;
        if (_resendSecondsLeft <= 0) t.cancel();
      });
    });
  }

  /// Asks the existing /send-activation function (Path B) to email this
  /// account a fresh activation link. Never throws, and never changes what
  /// this screen decided to show — entitlement is not consulted or altered.
  Future<void> _requestNewLink() async {
    if (_resending || _resendSecondsLeft > 0) return;

    final email = context.read<AuthProvider>().user?.email;
    final svc = SupabaseService.instance;

    // A phone-only account has nothing to email. Path A reports this as
    // `no_email_on_profile`; Path B simply cannot match, and would answer the
    // same generic "on its way" as for a real account — which here would be
    // untrue and would leave the customer waiting for mail that cannot come.
    // Say so plainly instead, and spend none of the hourly budget on it.
    if (email == null || email.isEmpty || !svc.isConfigured) {
      setState(() => _resendOutcomeKey = 'paywall_resend_no_email');
      return;
    }

    setState(() {
      _resending = true;
      _resendOutcomeKey = null;
    });

    // `outcomeKey` is decided here and the cooldown separately, because the
    // two turn on different facts: what to tell the customer, and whether an
    // attempt was actually spent out of the server's hourly budget.
    String outcomeKey;
    bool serverAnswered;

    try {
      await svc.client.functions
          .invoke(
            'send-activation',
            // `identifier`, never `user_id`, and no x-activation-secret
            // header — this is Path B by construction. The SDK attaches the
            // session JWT; the function is deployed --no-verify-jwt and
            // ignores it, so it neither helps nor harms.
            body: {'identifier': email},
          )
          .timeout(_kResendTimeout);

      // 200 here is the function's GENERIC_OK. It means the request was
      // accepted and not rate-limited; it does NOT mean Resend has delivered
      // anything, and the copy for this key is careful not to claim it did.
      outcomeKey = 'paywall_resend_sent';
      serverAnswered = true;
    } on FunctionsHttpException catch (e) {
      // `on FunctionsHttpException` specifically, for the same reason the
      // entitlement service is that precise: only this type means our own
      // function produced the status. A FunctionsFetchException never left
      // the phone and a FunctionsRelayException failed before reaching our
      // code, and neither may be reported as a rate limit.
      outcomeKey = e.status == 429
          ? 'paywall_resend_throttled'
          : 'paywall_resend_failed';
      // Every request that reached the function was written to
      // activation_requests, whether it was served or refused — including
      // this one. The attempt is spent either way, so the cooldown runs.
      serverAnswered = true;
      debugPrint('[paywall] resend http ${e.status}');
    } catch (e) {
      // Offline, DNS, TLS, timeout, malformed reply. Nothing was logged
      // server-side, so no budget was spent and no cooldown is imposed:
      // making somebody with a bad connection wait 30 seconds to retry a
      // request that never arrived would be a punishment for the network.
      outcomeKey = 'paywall_resend_failed';
      serverAnswered = false;
      debugPrint('[paywall] resend failed: ${e.runtimeType}');
    }

    if (!mounted) return;
    setState(() {
      _resending = false;
      _resendOutcomeKey = outcomeKey;
    });
    if (serverAnswered) _startResendCooldown();
  }

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _outcomeKey = null;
    });

    final entitlement = context.read<EntitlementProvider>();
    await entitlement.refresh();
    if (!mounted) return;

    final result = entitlement.result;
    final unlocked = result.status == EntitlementStatus.active ||
        result.status == EntitlementStatus.offlineGraceActive;

    if (unlocked) {
      // The gate's sentinel also watches for this transition and would move
      // the user itself. Doing it here as well is deliberate belt-and-braces:
      // a customer who has just been told their licence is live must not be
      // left staring at the paywall because one mechanism failed. Two
      // pushNamedAndRemoveUntil calls settle on exactly one /home route.
      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/home', (_) => false);
      return;
    }

    setState(() {
      _checking = false;
      // Say which of the two actually happened rather than a vague "try
      // again". `network` means the server answered and the answer has not
      // changed; anything else means we could not reach it, which is the
      // user's connection and is worth saying plainly.
      _outcomeKey = result.source == EntitlementSource.network
          ? 'paywall_refresh_unchanged'
          : 'paywall_refresh_unreachable';
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final entitlement = context.watch<EntitlementProvider>();

    // Two genuinely different situations, and conflating them is what makes a
    // paywall feel like an accusation. "Expired" is a customer whose licence
    // may be perfectly good and who has simply been offline too long.
    final isExpired = entitlement.status == EntitlementStatus.expired;

    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _PaywallLogo(),
                  const SizedBox(height: 22),
                  Text(
                    context.tr(
                        isExpired ? 'paywall_expired_title' : 'paywall_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _C.text, fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context
                        .tr(isExpired ? 'paywall_expired_body' : 'paywall_body'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _C.muted, fontSize: 13, height: 1.55),
                  ),
                  const SizedBox(height: 22),

                  // The single most common real cause of "I paid but it says I
                  // haven't" is being signed in on a second account. Showing
                  // which one resolves it without a support ticket.
                  _AccountCard(identifier: _identifierFor(auth)),
                  const SizedBox(height: 18),

                  _RefreshButton(checking: _checking, onPressed: _refresh),

                  if (_outcomeKey != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: _C.card,
                        border: Border.all(color: _C.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        context.tr(_outcomeKey!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: _C.muted, fontSize: 12.5, height: 1.5),
                      ),
                    ),
                  ],

                  // Secondary to Refresh, and deliberately below it: the
                  // common case is a licence that simply has not synced yet,
                  // and asking for a second email would not help that. This
                  // is for the smaller case where the first email never
                  // arrived at all — previously a support ticket.
                  const SizedBox(height: 12),
                  _ResendLinkButton(
                    sending: _resending,
                    secondsLeft: _resendSecondsLeft,
                    onPressed: _requestNewLink,
                  ),

                  if (_resendOutcomeKey != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: _C.card,
                        border: Border.all(color: _C.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        context.tr(_resendOutcomeKey!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: _C.muted, fontSize: 12.5, height: 1.5),
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),
                  const _SupportBlock(),
                  const SizedBox(height: 18),
                  const _GateFooterActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The recoverable "connect once" screen.
///
/// This is NOT the paywall and must never be confused with it. It is what the
/// gate shows when a signed-in user has no usable cached token AND the server
/// could not be reached — an ambiguous state, which is never allowed to block
/// anybody permanently. It is mounted inside the gate rather than routed,
/// because app.dart may only gain the one `/paywall` route.
class ConnectOnceScreen extends StatefulWidget {
  const ConnectOnceScreen({super.key});

  @override
  State<ConnectOnceScreen> createState() => _ConnectOnceScreenState();
}

class _ConnectOnceScreenState extends State<ConnectOnceScreen> {
  bool _checking = false;
  bool _failedOnce = false;

  Future<void> _retry() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _failedOnce = false;
    });

    final entitlement = context.read<EntitlementProvider>();
    await entitlement.refresh();
    if (!mounted) return;

    // The gate watches the same provider and moves the user itself on any
    // answer at all — this screen only ever shows while the status is still
    // `unknown`. Only claim the retry failed if that is still the case;
    // otherwise the gate is already navigating and saying "still could not
    // reach" for one frame on the way out would be a lie.
    final stillUnknown = entitlement.status == EntitlementStatus.unknown;
    setState(() {
      _checking = false;
      _failedOnce = stillUnknown;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _PaywallLogo(),
                  const SizedBox(height: 22),
                  Text(
                    context.tr('activate_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _C.text, fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('activate_body'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _C.muted, fontSize: 13, height: 1.55),
                  ),
                  const SizedBox(height: 22),
                  _RefreshButton(
                    checking: _checking,
                    onPressed: _retry,
                    labelKey: 'activate_retry_cta',
                  ),
                  if (_failedOnce) ...[
                    const SizedBox(height: 12),
                    Text(
                      context.tr('activate_retry_failed'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _C.muted, fontSize: 12.5, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const _SupportBlock(),
                  const SizedBox(height: 18),
                  const _GateFooterActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared pieces ─────────────────────────────────────────────────────────

String _identifierFor(AuthProvider auth) {
  final user = auth.user;
  final email = user?.email;
  if (email != null && email.isNotEmpty) return email;
  final phone = user?.phone;
  if (phone != null && phone.isNotEmpty) return phone;
  return '—';
}

class _PaywallLogo extends StatelessWidget {
  const _PaywallLogo();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _C.card,
            border: Border.all(color: _C.border),
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(13),
              child:
                  // The circular badge, not the raw brand art: assets/images/logo.png is an
                  // opaque white SQUARE whose artwork fills only 63% of its height, so inside
                  // this ClipOval it renders as a white square rather than a badge. Derived by
                  // tool/make_in_app_badge.dart.
                  Image.asset('assets/images/logo_badge.png', fit: BoxFit.contain),
            ),
          ),
        ),
      );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.identifier});

  final String identifier;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: _C.card,
          border: Border.all(color: _C.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('paywall_account_label').toUpperCase(),
              style: const TextStyle(
                  color: _C.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1),
            ),
            const SizedBox(height: 6),
            SelectableText(
              identifier,
              style: const TextStyle(
                  color: _C.text, fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('paywall_account_hint'),
              style:
                  const TextStyle(color: _C.muted, fontSize: 11.5, height: 1.5),
            ),
          ],
        ),
      );
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({
    required this.checking,
    required this.onPressed,
    this.labelKey = 'paywall_refresh_cta',
  });

  final bool checking;
  final Future<void> Function() onPressed;
  final String labelKey;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: checking ? null : () => onPressed(),
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.green,
            disabledBackgroundColor: _C.border,
            foregroundColor: _C.bg,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: checking
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: _C.muted),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        context.tr('paywall_refresh_checking'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _C.muted,
                            fontSize: 15,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                )
              : Text(
                  context.tr(labelKey),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
        ),
      );
}

/// "Email me a new link".
///
/// An [OutlinedButton], not the filled green of [_RefreshButton]: Refresh is
/// what almost everybody on this screen actually needs, and two equally loud
/// buttons would make the wrong one look like the answer.
///
/// It is a button, not a link — nothing here opens a browser, names a host or
/// carries a URL, so the hard constraint at the top of this file still holds
/// in full. What it does is ask the server to send an email; the customer
/// still leaves the app to act on it, exactly as before.
class _ResendLinkButton extends StatelessWidget {
  const _ResendLinkButton({
    required this.sending,
    required this.secondsLeft,
    required this.onPressed,
  });

  final bool sending;
  final int secondsLeft;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final coolingDown = secondsLeft > 0;
    final disabled = sending || coolingDown;

    // Three labels for three genuinely different states. A countdown that
    // just said "Email me a new link" while refusing to do it would read as a
    // broken button rather than as a deliberate pause.
    final String label = sending
        ? context.tr('paywall_resend_sending')
        : coolingDown
            ? context.trArgs('paywall_resend_in', {'s': '$secondsLeft'})
            : context.tr('paywall_resend_cta');

    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: disabled ? null : () => onPressed(),
        style: OutlinedButton.styleFrom(
          foregroundColor: _C.cyan,
          disabledForegroundColor: _C.muted,
          side: BorderSide(color: disabled ? _C.border : _C.cyan),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: sending
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: _C.muted),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              )
            : Text(
                label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}

class _SupportBlock extends StatelessWidget {
  const _SupportBlock();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            context.tr('paywall_support_label'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _C.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1),
          ),
          const SizedBox(height: 6),
          // Selectable, not tappable. A launcher here would be one tap from a
          // purchase conversation and the constraint above is absolute.
          const SelectableText(
            kPaywallSupportContact,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _C.cyan, fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('paywall_support_hint'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _C.muted, fontSize: 11.5, height: 1.5),
          ),
        ],
      );
}

/// Language + log out. Present on both screens: somebody who cannot read
/// English has to be able to change the language before this text means
/// anything at all, and somebody on the wrong account has to be able to leave
/// it.
class _GateFooterActions extends StatelessWidget {
  const _GateFooterActions();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: TextButton.icon(
            onPressed: () => showPaywallLanguagePicker(context),
            icon: const Icon(Icons.translate_rounded, color: _C.muted, size: 18),
            label: Text(
              settings.currentLanguage.nameNative,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _C.muted, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Flexible(
          child: TextButton(
            // The gate's sentinel watches AuthProvider and routes to /login on
            // the signedOut transition, so there is no navigation here.
            onPressed: () => context.read<AuthProvider>().logout(),
            child: Text(
              context.tr('paywall_logout_cta'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _C.muted, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// LANGUAGE PICKER
//
// home_screen.dart's drawer picker is `_showLanguagePicker` — library-private,
// and home_screen.dart is a file this phase may not modify, so it cannot be
// made visible. This is the same sheet, same SettingsProvider.supportedLanguages
// list, same search, restyled to the auth/paywall palette.
//
// One deliberate difference: it does NOT push '/home' afterwards. The drawer
// version does, which from this screen would walk straight past the gate.
// Changing the language swaps MaterialApp's ValueKey, which rebuilds the tree
// from `initialRoute: '/auth'` — so the gate re-runs and re-decides on its own.
// ══════════════════════════════════════════════════════════════════════════
void showPaywallLanguagePicker(BuildContext context) {
  final settings = context.read<SettingsProvider>();
  final search = ValueNotifier<String>('');
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: _C.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: _C.border),
            left: BorderSide(color: _C.border),
            right: BorderSide(color: _C.border),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: _C.border, borderRadius: BorderRadius.circular(2)),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: _C.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.translate_rounded, color: _C.cyan),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('selectLanguage'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _C.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: _C.muted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                onChanged: (v) => search.value = v.toLowerCase(),
                style: const TextStyle(color: _C.text),
                decoration: InputDecoration(
                  hintText: context.tr('searchLanguage'),
                  hintStyle: const TextStyle(color: _C.muted),
                  prefixIcon: const Icon(Icons.search, color: _C.muted),
                  filled: true,
                  fillColor: _C.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _C.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _C.cyan)),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: search,
                builder: (_, q, __) {
                  final langs = SettingsProvider.supportedLanguages
                      .where((l) =>
                          l.nameEn.toLowerCase().contains(q) ||
                          l.nameNative.toLowerCase().contains(q) ||
                          l.code.contains(q))
                      .toList();
                  return ListView.builder(
                    controller: ctrl,
                    itemCount: langs.length,
                    itemBuilder: (_, i) {
                      final l = langs[i];
                      final active = settings.locale.languageCode == l.code;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: active ? _C.cyan : _C.card,
                          radius: 20,
                          child: Text(
                            l.code.substring(0, 2).toUpperCase(),
                            style: TextStyle(
                                color: active ? Colors.black : _C.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Text(
                          l.nameNative,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: active ? _C.cyan : _C.text),
                        ),
                        subtitle: Text(
                          l.nameEn,
                          style: const TextStyle(color: _C.muted, fontSize: 12),
                        ),
                        trailing: active
                            ? const Icon(Icons.check_circle,
                                color: _C.cyan, size: 22)
                            : null,
                        onTap: () async {
                          await settings.setLanguage(l.code);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

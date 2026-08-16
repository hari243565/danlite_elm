import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../providers/auth_provider.dart';
import '../providers/entitlement_provider.dart';
import '../providers/settings_provider.dart';
import '../services/entitlement_service.dart';

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
                  Image.asset('assets/images/logo.png', fit: BoxFit.contain),
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

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../providers/auth_provider.dart';
import '../providers/entitlement_provider.dart';
import '../services/entitlement_service.dart';
import '../services/supabase_service.dart';
import 'paywall_screen.dart' show kPaywallSupportContact;

// ══════════════════════════════════════════════════════════════════════════
// HARD CONSTRAINT — CARRIED FROM THE PAYWALL, UNCHANGED.
//
// No price, no currency symbol, no numeral representing a cost, and no
// purchase / upgrade / renew wording anywhere on this screen in any language.
// A licence STATUS and a purchase RECORD are facts about what the customer
// already holds; neither is an offer, and neither may become one.
//
// The one deliberate widening: the three /legal/* URLs below. Google Play
// requires an accessible privacy policy, and those pages contain no checkout
// path. That allowance stops there — nothing on this screen may reference
// /checkout or /activate, and see the note on [_kLegalPaths] for why the URLs
// are rendered as copyable text rather than as tappable links.
// ══════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════
// [DRAFT] BILLING DOMAIN — PLACEHOLDER, NOT THE FINAL HOST.
//
// Mirrors the `BILLING_DOMAIN` / `NEXT_PUBLIC_BILLING_DOMAIN` convention the
// send-activation Edge Function and the portal already use, including their
// `http://localhost:3000` default. The three pages it addresses are themselves
// still marked DRAFT (see portal/app/legal/layout.tsx). One line to change
// when the real host is provisioned.
// ══════════════════════════════════════════════════════════════════════════
const String kBillingDomain = 'http://localhost:3000'; // [DRAFT]

// ══════════════════════════════════════════════════════════════════════════
// [CONFIRM] APP VERSION — HAND-MIRRORED FROM pubspec.yaml `version: 1.0.0+1`.
//
// This should be read at runtime, and the intended way was package_info_plus.
// That package is NOT a dependency of this project (contrary to what this
// task assumed) and cannot become one right now: package_info_plus 9.0.1 —
// the newest version that resolves against this SDK constraint — fails
// `:package_info_plus:compileReleaseKotlin` with "Too many arguments for
// 'public constructor(): kotlin/String'" against the Kotlin Gradle plugin
// this project pins. Flutter's own fix is to raise the KGP version in
// android/settings.gradle, and android/ is out of bounds for this task, so
// the fallback is a constant.
//
// Consequence, stated plainly: this line does not follow a version bump on
// its own. It is the third hand-copy of the version in the tree —
// about_screen.dart:47 and settings_screen.dart both say 'Version 1.0.0',
// already dropping the build number. Raising the Kotlin plugin and switching
// all three to package_info_plus is a small, self-contained job for whichever
// phase is allowed to touch android/.
// ══════════════════════════════════════════════════════════════════════════
const String kAppVersionLabel = '1.0.0 (1)'; // [CONFIRM] = pubspec 1.0.0+1

/// Rendered as [SelectableText], never launched.
///
/// `url_launcher` would in fact be safe to add here — the investigation for
/// this task found `url_launcher_android` 6.3.32 already resolved in
/// pubspec.lock (transitive, via supabase_flutter) and already registered in
/// GeneratedPluginRegistrant, so it compiles into every APK today and adding
/// the top-level package would introduce no new native surface and no AGP
/// change. It is still not used, for two reasons that outlive that finding:
/// a tap would open a browser on the billing host, one address-bar edit from
/// /checkout; and while [kBillingDomain] is a localhost placeholder a tappable
/// link is an affordance that cannot work at all. Revisit when the real host
/// lands — the plumbing is already there.
const Map<String, String> _kLegalPaths = {
  'account_legal_privacy': '/legal/privacy',
  'account_legal_terms': '/legal/terms',
  'account_legal_refund': '/legal/refund',
};

/// Country code → display name.
///
/// signup_screen.dart's `_kCountries` is library-private, and that file is not
/// one this task may restructure, so it cannot be imported or lifted out. This
/// is deliberately the *same eight countries* that dropdown offers rather than
/// a new arbitrary list — if the two ever diverge, that dropdown is the source
/// of truth. India is the one name the UI localises, matching what the signup
/// screen already does with `auth_country_in`.
const Map<String, String> _kCountryNames = {
  'IN': 'India',
  'US': 'United States',
  'GB': 'United Kingdom',
  'AE': 'United Arab Emirates',
  'CA': 'Canada',
  'AU': 'Australia',
  'SG': 'Singapore',
  'DE': 'Germany',
};

/// What the two server reads returned. Every field is nullable on purpose:
/// `licences.purchased_at` and `licences.purchase_rail` are nullable columns,
/// and a user who has not purchased through the rail has neither. The screen
/// omits the corresponding line rather than printing an empty one.
class _AccountFacts {
  const _AccountFacts({
    this.countryCode,
    this.accountCreatedAt,
    this.purchasedAt,
    this.purchaseRail,
    this.failed = false,
  });

  final String? countryCode;
  final DateTime? accountCreatedAt;
  final DateTime? purchasedAt;
  final String? purchaseRail;

  /// True when a read could not be completed at all (offline, or the row was
  /// not readable). Distinct from "read fine, the column is null".
  final bool failed;
}

/// The account detail screen, reached from the Settings summary row.
///
/// Light theme throughout, matching settings_screen.dart — its immediate
/// parent — rather than the darker palette the paywall and auth screens use.
/// Read-only: it fetches nothing that is not already the signed-in user's own
/// row under the existing `profiles_select_own` / `licences_select_own`
/// policies, writes nothing, and manages nothing. Device management stays in
/// the portal, which is Phase 7's deliberate design.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  _AccountFacts? _facts;
  String? _deviceModel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Two independent lookups. Neither may take the screen down: the identity
    // header and the licence pill come from providers that are already in
    // memory, so the page is useful even if both fail.
    await Future.wait([_loadFacts(), _loadDevice()]);
  }

  Future<void> _loadFacts() async {
    final uid = context.read<AuthProvider>().user?.id;
    final svc = SupabaseService.instance;
    if (uid == null || !svc.isConfigured) {
      if (mounted) setState(() => _facts = const _AccountFacts(failed: true));
      return;
    }

    try {
      final client = svc.client;
      // The `.eq` is redundant — RLS already restricts both tables to the
      // caller's own row — but it states the intent at the call site and costs
      // nothing.
      final profile = await client
          .from('profiles')
          .select('country_code, created_at')
          .eq('id', uid)
          .maybeSingle();
      final licence = await client
          .from('licences')
          .select('purchased_at, purchase_rail')
          .eq('user_id', uid)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _facts = _AccountFacts(
          countryCode: profile?['country_code'] as String?,
          accountCreatedAt: _parseTs(profile?['created_at']),
          purchasedAt: _parseTs(licence?['purchased_at']),
          purchaseRail: licence?['purchase_rail'] as String?,
        );
      });
      debugPrint('[account] profiles/licences read ok — '
          'country=${profile?['country_code']} '
          'created=${profile?['created_at']} '
          'purchased=${licence?['purchased_at']} '
          'rail=${licence?['purchase_rail']}');
    } catch (e) {
      // Never surface a server or exception string. The affected lines are
      // simply omitted and one muted sentence says so.
      debugPrint('[account] profile/licence read failed: ${e.runtimeType}');
      if (mounted) setState(() => _facts = const _AccountFacts(failed: true));
    }
  }

  Future<void> _loadDevice() async {
    try {
      // Same call and same plugin version auth_provider.dart already uses.
      final info = await DeviceInfoPlugin().androidInfo;
      final manufacturer = info.manufacturer.trim();
      final model = info.model.trim();
      final label = model.toLowerCase().startsWith(manufacturer.toLowerCase())
          ? model
          : '${_capitalise(manufacturer)} $model';
      if (mounted) setState(() => _deviceModel = label);
    } catch (e) {
      debugPrint('[account] device info unavailable: ${e.runtimeType}');
    }
  }

  static DateTime? _parseTs(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final entitlement = context.watch<EntitlementProvider>();
    final user = auth.user;
    final facts = _facts;

    final identifier = accountIdentifierOf(auth);
    final isPhone = (user?.email?.isEmpty ?? true) &&
        (user?.phone?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text(context.tr('account_screen_title')),
        backgroundColor: AppColors.navyMid,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _IdentityHeader(identifier: identifier, isPhone: isPhone),

          // ── Membership ────────────────────────────────────────────────
          _SectionHeader(
              icon: Icons.workspace_premium_outlined,
              title: context.tr('account_section_title')),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccountStatusPill(entitlement: entitlement),
                // Each line appears only if its own column came back non-null.
                // The two are independent in practice: the live active account
                // has `purchased_at` set and `purchase_rail` still null.
                if (facts?.purchasedAt != null) ...[
                  const SizedBox(height: 12),
                  _FactLine(
                    icon: Icons.event_available_outlined,
                    text: context.trArgs('account_member_since',
                        {'date': _formatDate(facts!.purchasedAt!)}),
                  ),
                ],
                if (facts?.purchaseRail != null) ...[
                  const SizedBox(height: 8),
                  _FactLine(
                    icon: Icons.receipt_long_outlined,
                    text: context.trArgs('account_purchased_via',
                        {'rail': _railName(facts!.purchaseRail!)}),
                  ),
                ],
              ],
            ),
          ),

          // ── Account details ───────────────────────────────────────────
          _SectionHeader(
              icon: Icons.badge_outlined,
              title: context.tr('account_details_title')),
          _Card(
            padded: false,
            child: Column(children: [
              _DetailRow(
                label: context.tr(
                    isPhone ? 'account_phone_label' : 'account_email_label'),
                value: identifier,
              ),
              if (facts?.countryCode != null)
                _DetailRow(
                  label: context.tr('account_country_label'),
                  value: _countryName(context, facts!.countryCode!),
                ),
              if (facts?.accountCreatedAt != null)
                _DetailRow(
                  label: context.tr('account_created_label'),
                  value: _formatDate(facts!.accountCreatedAt!),
                  last: true,
                ),
            ]),
          ),
          if (facts?.failed ?? false)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(
                context.tr('account_details_unavailable'),
                style: const TextStyle(
                    fontSize: 11.5, height: 1.4, color: AppColors.textHint),
              ),
            ),

          // ── Account ID ────────────────────────────────────────────────
          if (user != null) _AccountIdCard(id: user.id),

          // ── This device ───────────────────────────────────────────────
          _SectionHeader(
              icon: Icons.smartphone_outlined,
              title: context.tr('account_device_title')),
          _Card(
            padded: false,
            child: Column(children: [
              _DetailRow(
                label: context.tr('account_device_label'),
                value: _deviceModel ?? '—',
              ),
              _DetailRow(
                label: context.tr('account_app_version_label'),
                value: kAppVersionLabel,
                mono: true,
                last: true,
              ),
            ]),
          ),

          // ── Support & legal ───────────────────────────────────────────
          _SectionHeader(
              icon: Icons.help_outline,
              title: context.tr('account_support_title')),
          const _SupportAndLegalCard(),

          const SizedBox(height: 6),
          const _LogoutTile(),
        ],
      ),
    );
  }

  String _countryName(BuildContext context, String code) {
    // India is localised, exactly as on the signup screen; the rest stay in
    // their endonym-free English form there and here, so the two agree.
    if (code == 'IN') return context.tr('auth_country_in');
    return _kCountryNames[code] ?? code;
  }

  /// Both rails are Razorpay — `razorpay_in` and `razorpay_intl` differ only in
  /// which pricing rail took the payment, which is exactly the sort of detail
  /// this screen must not surface. The user is told the processor, not the
  /// rail, and never the amount.
  static String _railName(String rail) =>
      rail.startsWith('razorpay') ? 'Razorpay' : rail;

  /// Same month abbreviations and same `d Mon yyyy` ordering as
  /// trip_history_screen.dart's `_formatDate`, which is the only date
  /// convention in the codebase. The weekday and `· HH:mm` it appends are
  /// dropped here: they are meaningful for a trip and noise on a membership
  /// date.
  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

/// The identifier the user actually signed in with. Shared with
/// settings_screen.dart's summary row so the two can never disagree.
String accountIdentifierOf(AuthProvider auth) {
  final user = auth.user;
  if (user?.email?.isNotEmpty ?? false) return user!.email!;
  if (user?.phone?.isNotEmpty ?? false) return user!.phone!;
  return auth.pendingIdentifier ?? '—';
}

// ── Identity header ─────────────────────────────────────────────────────────

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.identifier, required this.isPhone});

  final String identifier;
  final bool isPhone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
        child: Column(children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppColors.navyMid.withValues(alpha: 0.12), width: 2),
            ),
            alignment: Alignment.center,
            child: isPhone
                ? const Icon(Icons.smartphone_rounded,
                    color: AppColors.navyMid, size: 34)
                : Text(
                    _initials(identifier),
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navyMid),
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            identifier,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: AppColors.navyMid.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(999)),
            child: Text(
              context.tr(isPhone
                  ? 'account_signed_in_via_mobile'
                  : 'account_signed_in_via_email'),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
          ),
        ]),
      );

  /// One letter, or two when the local part is dotted (`first.last@…` → `FL`).
  /// Falls back to a dash rather than to an empty circle.
  static String _initials(String identifier) {
    final local = identifier.split('@').first;
    final parts = local
        .split(RegExp(r'[._\-+]'))
        .where((p) => p.isNotEmpty && RegExp(r'^[A-Za-z]').hasMatch(p))
        .toList();
    if (parts.isEmpty) {
      final alpha = RegExp(r'[A-Za-z]').firstMatch(local)?.group(0);
      return (alpha ?? '—').toUpperCase();
    }
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

// ── Licence status pill ─────────────────────────────────────────────────────

/// The licence state, said plainly — no price, no link, no call to action in
/// any branch.
///
/// Public and living here rather than in settings_screen.dart so that the
/// Settings summary row and this screen render one identical pill from one
/// piece of logic. The status/grace arithmetic is [EntitlementProvider]'s,
/// used as-is.
class AccountStatusPill extends StatelessWidget {
  const AccountStatusPill({super.key, required this.entitlement});

  final EntitlementProvider entitlement;

  @override
  Widget build(BuildContext context) {
    final Color tint;
    final String label;

    switch (entitlement.status) {
      case EntitlementStatus.active:
        tint = AppColors.success;
        label = context.tr('account_status_active');
      case EntitlementStatus.offlineGraceActive:
        tint = AppColors.warning;
        // The three-key split mirrors the gate's own banner so no language
        // says "1 days".
        final d = entitlement.graceDaysRemaining;
        if (d == null || d <= 0) {
          label = context.tr('account_status_offline_grace_last');
        } else if (d == 1) {
          label = context.tr('account_status_offline_grace_one');
        } else {
          label =
              context.trArgs('account_status_offline_grace', {'days': '$d'});
        }
      case EntitlementStatus.unknown:
      case EntitlementStatus.inactive:
      case EntitlementStatus.revoked:
      case EntitlementStatus.expired:
      case EntitlementStatus.supersededSession:
        // Unreachable in practice: the gate routes an unlicensed user to the
        // paywall before Settings — and therefore this screen — can be opened.
        // Handled anyway, and handled honestly: a factual line, never a prompt
        // to pay.
        tint = AppColors.textSecondary;
        label = context.tr('account_status_inactive');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint.withValues(alpha: 0.35))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: tint)),
        ),
      ]),
    );
  }
}

// ── Account ID ──────────────────────────────────────────────────────────────

class _AccountIdCard extends StatelessWidget {
  const _AccountIdCard({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              icon: Icons.tag, title: context.tr('account_id_label')),
          _Card(
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _truncate(id),
                      style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('account_id_hint'),
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: () async {
                  // Clipboard is part of the Flutter SDK (services.dart) — no
                  // dependency was added for this.
                  await Clipboard.setData(ClipboardData(text: id));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text(context.tr('account_id_copied_confirmation')),
                    duration: const Duration(seconds: 2),
                  ));
                },
                icon: const Icon(Icons.copy_rounded,
                    size: 16, color: AppColors.navyMid),
                label: Text(context.tr('account_id_copy_cta'),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navyMid)),
              ),
            ]),
          ),
        ],
      );

  /// Enough to read aloud to support at both ends, short enough not to wrap.
  /// This is a support reference, not a secret: it is the user's own id, it
  /// authorises nothing on its own, and the full value is on the clipboard.
  static String _truncate(String id) =>
      id.length <= 18 ? id : '${id.substring(0, 8)}…${id.substring(id.length - 6)}';
}

// ── Support & legal ─────────────────────────────────────────────────────────

class _SupportAndLegalCard extends StatelessWidget {
  const _SupportAndLegalCard();

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('paywall_support_label'),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            // The same constant the paywall renders — imported, not copied, so
            // there stays exactly one line to change when the real address is
            // confirmed. Selectable, not tappable, for the reason given there.
            const SelectableText(
              kPaywallSupportContact,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navyMid),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: AppColors.divider, height: 1, thickness: 1),
            ),
            for (final entry in _kLegalPaths.entries) ...[
              Text(context.tr(entry.key),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              SelectableText(
                '$kBillingDomain${entry.value}',
                style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary),
              ),
              if (entry.key != _kLegalPaths.keys.last)
                const SizedBox(height: 10),
            ],
          ],
        ),
      );
}

// ── Log out ─────────────────────────────────────────────────────────────────

/// Moved here from settings_screen.dart unchanged: same confirmation dialog,
/// same call to the existing [AuthProvider.logout].
class _LogoutTile extends StatelessWidget {
  const _LogoutTile();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3))),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppColors.error),
            title: Text(context.tr('account_logout_cta'),
                style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            onTap: () => _confirm(context),
          ),
        ),
      );

  Future<void> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('account_logout_confirm_title'),
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        content: Text(context.tr('account_logout_confirm_body'),
            style: const TextStyle(
                fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('account_logout_cta')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    // The existing method, unchanged and uncopied — the same one the paywall
    // and the Settings screen called before it. The gate sentinel sees
    // `signedOut` on the auth stream and returns the user to /login on its
    // own, clearing this route with the rest of the stack, so no navigation
    // belongs here.
    await context.read<AuthProvider>().logout();
  }
}

// ── Shared chrome ───────────────────────────────────────────────────────────
//
// Same section-header and white-card treatment as settings_screen.dart, so the
// two read as one surface.

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.navyMid),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyMid,
                    letterSpacing: 1.2)),
          ),
        ]),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padded = true});

  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: AppColors.navyMid.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: padded
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: child)
            : child,
      );
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary)),
        ),
      ]);
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.last = false,
  });

  final String label, value;
  final bool mono, last;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        decoration: last
            ? null
            : const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.divider, width: 1))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: mono ? 'monospace' : null,
                    color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      );
}

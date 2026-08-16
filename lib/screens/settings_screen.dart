import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../providers/auth_provider.dart';
import '../providers/entitlement_provider.dart';
import '../providers/settings_provider.dart';
import '../services/entitlement_service.dart';
import '../services/obd_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text(context.tr('settings')),
        backgroundColor: AppColors.navyMid,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () => Navigator.pushNamed(context, '/about'),
          ),
        ],
      ),
      body: ListView(children: [
        // Identity first, preferences after. Everything below this point is
        // unchanged.
        _SectionHeader(
            icon: Icons.person_outline,
            title: context.tr('account_section_title')),
        const _AccountTile(),
        const _LogoutTile(),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: Divider(color: AppColors.divider, height: 1, thickness: 1),
        ),
        _SectionHeader(
            icon: Icons.directions_car, title: context.tr('vehicle')),
        _SettingsTile(
          icon: Icons.manage_accounts_outlined,
          title: context.tr('vehicleProfiles'),
          subtitle: context.tr('manageVehicles'),
          onTap: () => Navigator.pushNamed(context, '/vehicles'),
        ),
        _SettingsTile(
          icon: Icons.history_rounded,
          title: context.tr('tripHistory'),
          subtitle: context.tr('viewTrips'),
          onTap: () => Navigator.pushNamed(context, '/trips'),
        ),
        _SectionHeader(icon: Icons.wifi, title: context.tr('obd2Connection')),
        _SettingsTile(
          icon: Icons.link_rounded,
          title: context.tr('adapterSetup'),
          subtitle: context.tr('configureAdapter'),
          onTap: () => Navigator.pushNamed(context, '/connect'),
        ),
        _WifiSettingsTile(),
        _SectionHeader(
            icon: Icons.language, title: context.tr('languageRegion')),
        _LanguageTile(),
        _SectionHeader(icon: Icons.straighten, title: context.tr('units')),
        _UnitsTile(),
        _SectionHeader(
            icon: Icons.dashboard_rounded, title: context.tr('dashboard')),
        _SettingsTile(
          icon: Icons.fullscreen,
          title: context.tr('hudMode'),
          subtitle: 'Heads-up display for windscreen projection',
          onTap: () => Navigator.pushNamed(context, '/hud'),
        ),
        _SectionHeader(
            icon: Icons.notifications_outlined,
            title: context.tr('alarmsWarnings')),
        _AlarmsTile(label: 'Max RPM Alarm', defaultVal: 6000, unit: 'RPM'),
        _AlarmsTile(label: 'Max Coolant Temp', defaultVal: 105, unit: '°C'),
        _AlarmsTile(label: 'Min Fuel Level', defaultVal: 15, unit: '%'),
        _SectionHeader(icon: Icons.info_outline, title: context.tr('about')),
        _SettingsTile(
          icon: Icons.local_fire_department_outlined,
          title: 'About OBD Danlite',
          subtitle: 'Version 1.0.0 · OBD2 Vehicle Diagnostics',
          onTap: () => Navigator.pushNamed(context, '/about'),
        ),
        _DisconnectTile(),
        const SizedBox(height: 40),
      ]),
    );
  }
}

// ── Account (identity + licence status) ──────────────────────────────────────
//
// Read-only. It calls no new backend and adds no state: the identifier comes
// from the session AuthProvider already holds, and the status from the token
// EntitlementProvider already verified. Nothing here can be bought, renewed or
// linked to — this app sells nothing from inside itself, and that constraint
// applies to a status line exactly as it does to the paywall.
class _AccountTile extends StatelessWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final entitlement = context.watch<EntitlementProvider>();
    final user = auth.user;

    // Whichever channel the user actually registered on. Falls back to the
    // pending identifier only so the row is never blank.
    final identifier = (user?.email?.isNotEmpty ?? false)
        ? user!.email!
        : (user?.phone?.isNotEmpty ?? false)
            ? user!.phone!
            : (auth.pendingIdentifier ?? '—');

    return Container(
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          // Circular rather than the rounded square the navigation tiles use:
          // those point somewhere, this identifies somebody. Same tint and
          // same icon colour, so it still reads as one family.
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
                color: AppColors.bgSecondary, shape: BoxShape.circle),
            child: const Icon(Icons.person_rounded,
                color: AppColors.navyMid, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(identifier,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 7),
                _LicencePill(entitlement: entitlement),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// The licence state, said plainly. No price, no link, no call to action in
/// any branch — see [AppStrings] for the literal text of each.
class _LicencePill extends StatelessWidget {
  const _LicencePill({required this.entitlement});

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
        // The grace arithmetic is Phase 8's, used as-is. The three-key split
        // mirrors the gate's own banner so no language says "1 days".
        final d = entitlement.graceDaysRemaining;
        if (d == null || d <= 0) {
          label = context.tr('account_status_offline_grace_last');
        } else if (d == 1) {
          label = context.tr('account_status_offline_grace_one');
        } else {
          label = context
              .trArgs('account_status_offline_grace', {'days': '$d'});
        }
      case EntitlementStatus.unknown:
      case EntitlementStatus.inactive:
      case EntitlementStatus.revoked:
      case EntitlementStatus.expired:
      case EntitlementStatus.supersededSession:
        // Unreachable in practice: the gate routes an unlicensed user to the
        // paywall before Settings can be opened, and the sentinel clears the
        // whole stack if entitlement is withdrawn mid-session. Handled anyway,
        // and handled honestly — a factual line, never a prompt to pay.
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

/// Styled on [_DisconnectTile] — the destructive-action precedent already in
/// this file — and confirmed first, because signing out costs a one-time code
/// to undo.
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
    // Same shape as the delete confirmation on the vehicle screen: cancel on
    // the left as a plain button, the destructive action on the right in the
    // error colour.
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
    // calls. It drops the locally stored session id and signs out through
    // Supabase (the server-side `sessions` row is left for the next login to
    // re-claim, which is Phase 7's design, not this section's business). The
    // gate sentinel then sees `signedOut` on the auth stream and returns the
    // user to /login on its own, so no navigation belongs here.
    await context.read<AuthProvider>().logout();
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.navyMid),
          const SizedBox(width: 8),
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyMid,
                  letterSpacing: 1.2)),
        ]),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  const _SettingsTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap});
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
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: AppColors.bgSecondary,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppColors.navyMid, size: 20),
            ),
            title: Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            subtitle: Text(subtitle,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textHint),
            onTap: onTap,
          ),
        ),
      );
}

class _LanguageTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Container(
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
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(10)),
            child:
                const Icon(Icons.translate, color: AppColors.navyMid, size: 20),
          ),
          title: Text(context.tr('language'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          subtitle: Text(
              '${settings.currentLanguage.nameNative}  (${settings.currentLanguage.nameEn})',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
          onTap: () => _showLanguagePicker(context, settings),
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, SettingsProvider settings) {
    final search = ValueNotifier('');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                  color: AppColors.navyMid,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20))),
              child: Row(children: [
                const Icon(Icons.language, color: AppColors.flameGold),
                const SizedBox(width: 10),
                Text(context.tr('selectLanguage'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                onChanged: (v) => search.value = v.toLowerCase(),
                decoration: InputDecoration(
                  hintText: context.tr('searchLanguage'),
                  prefixIcon: const Icon(Icons.search),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                          backgroundColor: active
                              ? AppColors.navyMid
                              : AppColors.bgSecondary,
                          radius: 20,
                          child: Text(l.code.substring(0, 2).toUpperCase(),
                              style: TextStyle(
                                  color: active
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                        title: Text(l.nameNative,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? AppColors.navyMid
                                    : AppColors.textPrimary)),
                        subtitle: Text(l.nameEn,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        trailing: active
                            ? const Icon(Icons.check_circle,
                                color: AppColors.navyMid, size: 22)
                            : null,
                        onTap: () async {
                          await settings.setLanguage(l.code);
                          if (ctx.mounted) Navigator.pop(ctx);
                          // Navigate to home to trigger full rebuild
                          if (context.mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                                '/home', (route) => false);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _WifiSettingsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Container(
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
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.router_outlined,
                color: AppColors.navyMid, size: 20),
          ),
          title: Text(context.tr('wifiAdapter'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          subtitle: Text('${settings.wifiIp} : ${settings.wifiPort}',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace')),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
          onTap: () => Navigator.pushNamed(context, '/connect'),
        ),
      ),
    );
  }
}

class _UnitsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('measureSystem'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Row(children: [
            _UnitOption(
              label: context.tr('metric'),
              subtitle: context.tr('metricDesc'),
              selected: settings.useMetric,
              onTap: () {
                if (!settings.useMetric) settings.toggleUnits();
              },
            ),
            const SizedBox(width: 10),
            _UnitOption(
              label: context.tr('imperial'),
              subtitle: context.tr('imperialDesc'),
              selected: !settings.useMetric,
              onTap: () {
                if (settings.useMetric) settings.toggleUnits();
              },
            ),
          ]),
        ]),
      ),
    );
  }
}

class _UnitOption extends StatelessWidget {
  final String label, subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _UnitOption(
      {required this.label,
      required this.subtitle,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
                color: selected ? AppColors.navyMid : AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected ? AppColors.navyMid : AppColors.borderLight,
                    width: 1.5)),
            child: Column(children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: selected ? Colors.white : AppColors.textPrimary)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          selected ? Colors.white70 : AppColors.textSecondary)),
            ]),
          ),
        ),
      );
}

class _AlarmsTile extends StatefulWidget {
  final String label, unit;
  final double defaultVal;
  const _AlarmsTile(
      {required this.label, required this.defaultVal, required this.unit});
  @override
  State<_AlarmsTile> createState() => _AlarmsTileState();
}

class _AlarmsTileState extends State<_AlarmsTile> {
  bool _enabled = false;
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
        child: SwitchListTile(
          secondary: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: _enabled
                    ? AppColors.error.withValues(alpha: 0.1)
                    : AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.notifications_outlined,
                color: _enabled ? AppColors.error : AppColors.navyMid,
                size: 20),
          ),
          title: Text(widget.label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          subtitle: Text(
              'Threshold: ${widget.defaultVal.toStringAsFixed(0)} ${widget.unit}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          value: _enabled,
          activeThumbColor: AppColors.navyMid,
          onChanged: (v) => setState(() => _enabled = v),
        ),
      );
}

class _DisconnectTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();
    if (!obd.isConnected) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3))),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: const Icon(Icons.link_off, color: AppColors.error),
          title: Text(context.tr('disconnect'),
              style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          onTap: () async {
            await obd.disconnect();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('disconnect'))));
            }
          },
        ),
      ),
    );
  }
}

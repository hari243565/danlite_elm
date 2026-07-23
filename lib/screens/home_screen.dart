import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_strings.dart';
import '../providers/settings_provider.dart';
import '../services/obd_service.dart';
import '../models/vehicle_data.dart' hide ConnectionType;
import 'dashboard_screen.dart';
import 'realtime_screen.dart';
import 'connection_screen.dart';

// Unified Telemetry Design System Palette
class _NC {
  static const Color bg = Color(0xFF07090E);
  static const Color navBar = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color textOn = Color(0xFF00CAFF);
  static const Color textOff = Color(0xFF607080);
  static const Color textLive = Color(0xFFEEF2F8);
  static const Color stripWifi = Color(0xFF00CAFF);
  static const Color stripBt = Color(0xFF8B5CF6);
  static const Color stripErr = Color(0xFFFF3D3D);
  static const Color flame = Color(0xFFFF8A00);
  static const Color green = Color(0xFF00E39C);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const RealtimeScreen(),
    const ConnectionScreen(),
  ];

  // Keys resolved via the app's AppStrings/tr() localization system.
  static const _tabTitleKeys = ['dashboardTab', 'liveDataTab', 'connectTab'];

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();

    Color statusColor = Colors.transparent;
    if (obd.status == ConnectionStatus.connected) {
      statusColor =
          obd.transport == ConnectionType.wifi ? _NC.stripWifi : _NC.stripBt;
    } else if (obd.status == ConnectionStatus.error ||
        obd.status == ConnectionStatus.connecting) {
      statusColor =
          obd.status == ConnectionStatus.error ? _NC.stripErr : Colors.amber;
    }

    return Scaffold(
      backgroundColor: _NC.bg,
      drawer: _AppDrawer(obd: obd),
      appBar: _buildTopBar(context),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),

          // Persistent Telemetry Connection Status Ribbon
          if (obd.status != ConnectionStatus.disconnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              color: statusColor.withValues(alpha: 0.15),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(
                          color: statusColor.withValues(alpha: 0.4), width: 1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: statusColor),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _ribbonStatusLabel(context, obd).toUpperCase(),
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: _NC.navBar,
          border: Border(top: BorderSide(color: _NC.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: _NC.textOn,
          unselectedItemColor: _NC.textOff,
          selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.3),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
              icon: const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.speed_rounded)),
              label: context.tr('dashboardTab'),
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.analytics_outlined)),
              label: context.tr('liveDataTab'),
            ),
            BottomNavigationBarItem(
              icon: const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.bluetooth_connected)),
              label: context.tr('connectTab'),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTopBar(BuildContext context) {
    return AppBar(
      backgroundColor: _NC.navBar,
      elevation: 0,
      toolbarHeight: 52,
      iconTheme: const IconThemeData(color: _NC.textOn),
      title: Text(
        context.tr(_tabTitleKeys[_currentIndex]),
        style: const TextStyle(
            color: _NC.textLive, fontWeight: FontWeight.w800, fontSize: 15),
      ),
      actions: [
        IconButton(
          tooltip: context.tr('language'),
          icon: const Icon(Icons.translate_rounded),
          onPressed: () => _showLanguagePicker(context),
        ),
        IconButton(
          tooltip: context.tr('settings'),
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _NC.border),
      ),
    );
  }
}

// Localized label for the persistent connection ribbon. Derived from the
// status/transport enums so the ribbon never surfaces the service layer's raw
// English statusMessage. Dynamic detail (IP / device name) stays available on
// the connection screen; the ribbon is a compact, translated status only.
String _ribbonStatusLabel(BuildContext context, ObdService obd) {
  switch (obd.status) {
    case ConnectionStatus.connected:
      return context.tr(obd.transport == ConnectionType.wifi
          ? 'connectedViaWifi'
          : 'connectedViaBt');
    case ConnectionStatus.connecting:
      return context.tr('connecting');
    case ConnectionStatus.scanning:
      return context.tr('statusScanning');
    case ConnectionStatus.error:
      return context.tr('connectionFailed');
    case ConnectionStatus.disconnected:
      return context.tr('notConnected');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// APP DRAWER — restores full app feature reach (Settings, Language, Vehicle
// Profiles, Trip History, Fuel Economy, Live Graphs, Performance, DTC, HUD,
// About) in the same _NC dark telemetry design language.
// ═══════════════════════════════════════════════════════════════════════════
class _AppDrawer extends StatelessWidget {
  final ObdService obd;
  const _AppDrawer({required this.obd});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _NC.navBar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(obd: obd),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerSection(label: context.tr('drawerTools')),
                  _DrawerItem(
                    icon: Icons.warning_amber_rounded,
                    iconAsset: 'assets/icons/fault_code_gold.png',
                    label: context.tr('faultCodes'),
                    color: _NC.stripErr,
                    route: '/dtc',
                  ),
                  _DrawerItem(
                    icon: Icons.show_chart_rounded,
                    label: context.tr('liveGraphs').replaceAll('\n', ' '),
                    color: _NC.textOn,
                    route: '/graph',
                  ),
                  _DrawerItem(
                    icon: Icons.speed_rounded,
                    label: context.tr('performance'),
                    color: _NC.flame,
                    route: '/performance',
                  ),
                  _DrawerItem(
                    icon: Icons.local_gas_station_rounded,
                    label: context.tr('fuelEconomy').replaceAll('\n', ' '),
                    color: _NC.green,
                    route: '/fuel',
                  ),
                  _DrawerItem(
                    icon: Icons.fullscreen_rounded,
                    label: context.tr('hudMode').replaceAll('\n', ' '),
                    color: _NC.stripBt,
                    route: '/hud',
                  ),
                  _DrawerItem(
                    icon: Icons.history_rounded,
                    label: context.tr('tripHistory').replaceAll('\n', ' '),
                    color: _NC.textOff,
                    route: '/trips',
                  ),
                  _DrawerSection(label: context.tr('drawerVehicle')),
                  _DrawerItem(
                    icon: Icons.directions_car_filled_rounded,
                    label: context.tr('vehicleProfiles'),
                    color: _NC.textOn,
                    route: '/vehicles',
                  ),
                  _DrawerSection(label: context.tr('drawerPreferences')),
                  _LanguageDrawerItem(),
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    label: context.tr('settings'),
                    color: _NC.textOff,
                    route: '/settings',
                  ),
                  _DrawerItem(
                    icon: Icons.info_outline_rounded,
                    label: context.tr('about'),
                    color: _NC.textOff,
                    route: '/about',
                  ),
                ],
              ),
            ),
            if (obd.isConnected) _DisconnectFooter(obd: obd),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  final ObdService obd;
  const _DrawerHeader({required this.obd});

  @override
  Widget build(BuildContext context) {
    final connected = obd.isConnected;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: const BoxDecoration(
        color: _NC.card,
        border: Border(bottom: BorderSide(color: _NC.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _NC.flame.withValues(alpha: 0.14),
                ),
                child: const Icon(Icons.local_fire_department,
                    color: _NC.flame, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('OBD Danlite',
                  style: TextStyle(
                      color: _NC.textLive,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (connected ? _NC.green : _NC.textOff).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected ? _NC.green : _NC.textOff),
                ),
                const SizedBox(width: 6),
                Text(
                  obd.statusMessage,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: connected ? _NC.green : _NC.textOff,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerSection extends StatelessWidget {
  final String label;
  const _DrawerSection({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(label,
            style: const TextStyle(
                color: _NC.textOff,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4)),
      );
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String route;
  final String? iconAsset;
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.route,
    this.iconAsset,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
          child: iconAsset != null
              ? Padding(
                  padding: const EdgeInsets.all(7),
                  child: Image.asset(iconAsset!, fit: BoxFit.contain),
                )
              : Icon(icon, color: color, size: 18),
        ),
        title: Text(label,
            style: const TextStyle(
                color: _NC.textLive, fontSize: 13.5, fontWeight: FontWeight.w600)),
        onTap: () {
          Navigator.pop(context);
          Navigator.pushNamed(context, route);
        },
      );
}

class _LanguageDrawerItem extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return ListTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: _NC.textOn.withValues(alpha: 0.12)),
        child: const Icon(Icons.translate_rounded, color: _NC.textOn, size: 18),
      ),
      title: Text(context.tr('language'),
          style: const TextStyle(
              color: _NC.textLive, fontSize: 13.5, fontWeight: FontWeight.w600)),
      subtitle: Text(settings.currentLanguage.nameNative,
          style: const TextStyle(color: _NC.textOff, fontSize: 11.5)),
      onTap: () {
        Navigator.pop(context);
        _showLanguagePicker(context);
      },
    );
  }
}

class _DisconnectFooter extends StatelessWidget {
  final ObdService obd;
  const _DisconnectFooter({required this.obd});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: OutlinedButton.icon(
          onPressed: () async {
            Navigator.pop(context);
            await obd.disconnect();
          },
          icon: const Icon(Icons.link_off_rounded, size: 16, color: _NC.stripErr),
          label: Text(context.tr('disconnect'),
              style: const TextStyle(
                  color: _NC.stripErr, fontWeight: FontWeight.w700, fontSize: 13)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _NC.stripErr.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// QUICK LANGUAGE PICKER — dark-styled to match the _NC telemetry shell
// (mirrors settings_screen.dart's picker, restyled for the dark drawer/appbar
// entry points).
// ═══════════════════════════════════════════════════════════════════════════
void _showLanguagePicker(BuildContext context) {
  final settings = context.read<SettingsProvider>();
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
            color: _NC.navBar,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: _NC.border),
              left: BorderSide(color: _NC.border),
              right: BorderSide(color: _NC.border),
            )),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: _NC.border, borderRadius: BorderRadius.circular(2))),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
                color: _NC.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Row(children: [
              const Icon(Icons.translate_rounded, color: _NC.textOn),
              const SizedBox(width: 10),
              Text(context.tr('selectLanguage'),
                  style: const TextStyle(
                      color: _NC.textLive,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close, color: _NC.textOff),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => search.value = v.toLowerCase(),
              style: const TextStyle(color: _NC.textLive),
              decoration: InputDecoration(
                hintText: context.tr('searchLanguage'),
                hintStyle: const TextStyle(color: _NC.textOff),
                prefixIcon: const Icon(Icons.search, color: _NC.textOff),
                filled: true,
                fillColor: _NC.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _NC.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _NC.textOn)),
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
                        backgroundColor: active ? _NC.textOn : _NC.card,
                        radius: 20,
                        child: Text(l.code.substring(0, 2).toUpperCase(),
                            style: TextStyle(
                                color: active ? Colors.black : _NC.textOff,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                      title: Text(l.nameNative,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: active ? _NC.textOn : _NC.textLive)),
                      subtitle: Text(l.nameEn,
                          style: const TextStyle(color: _NC.textOff, fontSize: 12)),
                      trailing: active
                          ? const Icon(Icons.check_circle,
                              color: _NC.textOn, size: 22)
                          : null,
                      onTap: () async {
                        await settings.setLanguage(l.code);
                        if (ctx.mounted) Navigator.pop(ctx);
                        // Language change swaps MaterialApp's ValueKey, forcing a
                        // full tree rebuild — return to /home to re-anchor cleanly.
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../services/obd_service.dart';
import '../services/bluetooth_classic_service.dart';
import '../providers/settings_provider.dart';
import '../models/vehicle_data.dart' hide ConnectionType;

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});
  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  bool _wifiConnecting = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    final s = context.read<SettingsProvider>();
    _ipCtrl.text = s.wifiIp;
    _portCtrl.text = s.wifiPort.toString();

    // Load paired devices when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothClassicService>().loadBondedDevices();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  // ── WiFi connect ──────────────────────────────────────────────────────────
  Future<void> _connectWifi() async {
    final obd = context.read<ObdService>();
    final settings = context.read<SettingsProvider>();
    final ip = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 35000;

    await settings.saveWifiSettings(ip, port);
    setState(() => _wifiConnecting = true);
    final ok = await obd.connectWifi(ip: ip, port: port);
    if (!mounted) return;
    setState(() => _wifiConnecting = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(ok ? '✅ ${context.tr('connected')}' : '❌ ${obd.statusMessage}'),
      backgroundColor: ok ? AppColors.connected : AppColors.error,
    ));
    if (ok) Navigator.pop(context);
  }

  Future<void> _disconnectWifi() async {
    await context.read<ObdService>().disconnect();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text(context.tr('obd2Connection')),
        backgroundColor: AppColors.navyMid,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.flameOrange,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(icon: const Icon(Icons.wifi), text: context.tr('wifiTab')),
            Tab(
                icon: const Icon(Icons.bluetooth),
                text: context.tr('bluetoothTab')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ── Wi-Fi tab ────────────────────────────────────────────────────
          _WifiTab(
            ipCtrl: _ipCtrl,
            portCtrl: _portCtrl,
            connecting: _wifiConnecting,
            obdStatus: obd.status,
            onConnect: _connectWifi,
            onDisconnect: _disconnectWifi,
          ),
          // ── Bluetooth tab ─────────────────────────────────────────────────
          const _BluetoothTab(),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Wi-Fi Tab
// ══════════════════════════════════════════════════════════════════════════════
class _WifiTab extends StatelessWidget {
  final TextEditingController ipCtrl, portCtrl;
  final bool connecting;
  final ConnectionStatus obdStatus;
  final VoidCallback onConnect, onDisconnect;

  const _WifiTab({
    required this.ipCtrl,
    required this.portCtrl,
    required this.connecting,
    required this.obdStatus,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final isConn = obdStatus == ConnectionStatus.connected;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _StatusCard(status: obdStatus),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight)),
          child: Row(children: [
            const Icon(Icons.info_outline, color: AppColors.navyMid, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(context.tr('wifiInfoText'),
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary))),
          ]),
        ),
        const SizedBox(height: 20),
        Text(context.tr('adapterIpLabel'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextField(
          controller: ipCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              hintText: '192.168.0.10',
              prefixIcon: Icon(Icons.router_outlined)),
        ),
        const SizedBox(height: 16),
        Text(context.tr('portLabel'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextField(
          controller: portCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              hintText: '35000',
              prefixIcon: Icon(Icons.electrical_services_outlined)),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: isConn
              ? OutlinedButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.link_off),
                  label: Text(context.tr('disconnect')),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error)))
              : ElevatedButton.icon(
                  onPressed: connecting ? null : onConnect,
                  icon: connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.link),
                  label: Text(connecting
                      ? context.tr('connecting')
                      : context.tr('connectViaWifi')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyMid)),
        ),
        const SizedBox(height: 28),
        Text(context.tr('commonSettings'),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        ...[
          ('Generic ELM327 Wi-Fi', '192.168.0.10', '35000'),
          ('OBDLink MX+ Wi-Fi', '192.168.0.10', '35000'),
          ('Vgate iCar Wi-Fi', '192.168.1.1', '35000'),
          ('PLX Kiwi 3 Wi-Fi', '192.168.0.10', '8080'),
        ].map((r) => Container(
              margin: const EdgeInsets.only(bottom: 8),
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
                  leading: const Icon(Icons.router, color: AppColors.navyMid),
                  title: Text(r.$1,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('${r.$2} : ${r.$3}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  trailing: TextButton(
                      onPressed: () {
                        ipCtrl.text = r.$2;
                        portCtrl.text = r.$3;
                      },
                      child: const Text('USE')),
                ),
              ),
            )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Bluetooth Tab — Full in-app scan, bond, connect
// ══════════════════════════════════════════════════════════════════════════════
class _BluetoothTab extends StatelessWidget {
  const _BluetoothTab();

  @override
  Widget build(BuildContext context) {
    final bt = context.watch<BluetoothClassicService>();
    final obd = context.watch<ObdService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Connection status ────────────────────────────────────────────────
        _BtStatusCard(state: bt.state, message: bt.statusMessage, obd: obd),
        const SizedBox(height: 14),

        // ── Permission + Scan controls ───────────────────────────────────────
        Row(children: [
          Expanded(
              child: ElevatedButton.icon(
            onPressed: bt.isScanning
                ? () => context.read<BluetoothClassicService>().stopScan()
                : () => context.read<BluetoothClassicService>().startScan(),
            icon: bt.isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.bluetooth_searching, size: 20),
            label: Text(bt.isScanning ? 'Stop Scan' : context.tr('scan')),
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    bt.isScanning ? AppColors.warning : AppColors.navyMid,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () =>
                context.read<BluetoothClassicService>().loadBondedDevices(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navyMid,
                side: const BorderSide(color: AppColors.navyMid),
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16)),
          ),
        ]),
        const SizedBox(height: 6),

        // Info text
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderLight)),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 16, color: AppColors.navyMid),
            const SizedBox(width: 8),
            Expanded(
                child: Text(context.tr('btInfoText'),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary))),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Disconnect button if OBD connected via BT ────────────────────────
        if (obd.isConnected && obd.transport == ConnectionType.bluetooth) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.read<ObdService>().disconnect(),
              icon: const Icon(Icons.link_off),
              label: Text(context.tr('disconnect')),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error)),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Paired devices ───────────────────────────────────────────────────
        if (bt.bondedDevices.isNotEmpty) ...[
          _SectionLabel(
              icon: Icons.bluetooth_connected,
              label: 'Paired Devices (${bt.bondedDevices.length})',
              color: AppColors.success),
          const SizedBox(height: 8),
          ...bt.bondedDevices.map((dev) => _DeviceTile(
                device: dev,
                isCurrentlyConnected: obd.isConnected &&
                    obd.transport == ConnectionType.bluetooth &&
                    bt.connectedDevice?.address == dev.address,
                isConnecting: bt.isConnecting,
                onTap: () => _tapDevice(context, dev, obd, bt),
              )),
          const SizedBox(height: 16),
        ],

        // ── Discovered devices ───────────────────────────────────────────────
        if (bt.isScanning || bt.discoveredDevices.isNotEmpty) ...[
          _SectionLabel(
              icon: Icons.radar,
              label: bt.isScanning
                  ? 'Scanning… (${bt.discoveredDevices.length} found)'
                  : 'Nearby Devices (${bt.discoveredDevices.length})',
              color: bt.isScanning ? AppColors.warning : AppColors.navyMid),
          const SizedBox(height: 8),
          if (bt.discoveredDevices.isEmpty && bt.isScanning)
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const CircularProgressIndicator(color: AppColors.navyMid),
                const SizedBox(height: 12),
                Text('Looking for ELM327 adapters…',
                    style: const TextStyle(color: AppColors.textSecondary)),
              ]),
            ),
          ...bt.discoveredDevices.map((dev) => _DeviceTile(
                device: dev,
                isCurrentlyConnected: false,
                isConnecting: bt.isConnecting,
                onTap: () => _tapDevice(context, dev, obd, bt),
              )),
        ],

        // ── Empty state ──────────────────────────────────────────────────────
        if (!bt.isScanning &&
            bt.bondedDevices.isEmpty &&
            bt.discoveredDevices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(children: [
                const Icon(Icons.bluetooth_disabled,
                    size: 56, color: AppColors.textHint),
                const SizedBox(height: 12),
                Text('No devices found. Tap Scan to discover nearby adapters.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textSecondary, height: 1.5)),
              ]),
            ),
          ),

        const SizedBox(height: 32),
      ]),
    );
  }

  void _tapDevice(BuildContext context, BtDevice device, ObdService obd,
      BluetoothClassicService bt) async {
    if (obd.isConnected && obd.transport == ConnectionType.bluetooth) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Already connected. Disconnect first.'),
          backgroundColor: AppColors.warning));
      return;
    }

    final ok = await obd.connectBluetooth(device);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(ok ? '✅ Connected to ${device.name}' : '❌ ${obd.statusMessage}'),
      backgroundColor: ok ? AppColors.connected : AppColors.error,
    ));

    if (ok) Navigator.pop(context);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ══════════════════════════════════════════════════════════════════════════════

class _DeviceTile extends StatelessWidget {
  final BtDevice device;
  final bool isCurrentlyConnected;
  final bool isConnecting;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.device,
    required this.isCurrentlyConnected,
    required this.isConnecting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCurrentlyConnected
            ? AppColors.connected.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentlyConnected
              ? AppColors.connected
              : AppColors.borderLight,
          width: isCurrentlyConnected ? 1.8 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: AppColors.navyMid.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: isCurrentlyConnected
                    ? AppColors.connected.withValues(alpha: 0.12)
                    : device.bonded
                        ? AppColors.bgSecondary
                        : AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(
              isCurrentlyConnected
                  ? Icons.bluetooth_connected
                  : device.bonded
                      ? Icons.bluetooth
                      : Icons.bluetooth_searching,
              color: isCurrentlyConnected
                  ? AppColors.connected
                  : device.bonded
                      ? AppColors.navyMid
                      : AppColors.textSecondary,
              size: 22,
            ),
          ),
          title: Row(children: [
            Expanded(
                child: Text(device.name,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isCurrentlyConnected
                            ? AppColors.connected
                            : AppColors.textPrimary))),
            if (device.bonded && !isCurrentlyConnected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('PAIRED',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyMid)),
              ),
            if (isCurrentlyConnected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.connected,
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('ACTIVE',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
          ]),
          subtitle: Text(device.address,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textHint,
                  fontFamily: 'monospace')),
          trailing: isConnecting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.navyMid))
              : const Icon(Icons.chevron_right, color: AppColors.textHint),
          onTap: isConnecting ? null : onTap,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionLabel(
      {required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 1.2)),
      ]);
}

class _BtStatusCard extends StatelessWidget {
  final BtState state;
  final String message;
  final ObdService obd;
  const _BtStatusCard(
      {required this.state, required this.message, required this.obd});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    switch (state) {
      case BtState.connected:
        color = AppColors.connected;
        icon = Icons.check_circle;
        break;
      case BtState.connecting:
      case BtState.bonding:
        color = AppColors.warning;
        icon = Icons.sync;
        break;
      case BtState.scanning:
        color = AppColors.info;
        icon = Icons.radar;
        break;
      case BtState.error:
        color = AppColors.error;
        icon = Icons.error_outline;
        break;
      default:
        color = AppColors.textHint;
        icon = Icons.bluetooth_disabled;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 12),
        Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: color))),
      ]),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final ConnectionStatus status;
  const _StatusCard({required this.status});
  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;
    switch (status) {
      case ConnectionStatus.connected:
        color = AppColors.connected;
        label = context.tr('connected');
        icon = Icons.check_circle;
        break;
      case ConnectionStatus.connecting:
        color = AppColors.warning;
        label = context.tr('connecting');
        icon = Icons.sync;
        break;
      case ConnectionStatus.error:
        color = AppColors.error;
        label = context.tr('connectionFailed');
        icon = Icons.error;
        break;
      default:
        color = Colors.grey;
        label = context.tr('notConnected');
        icon = Icons.circle_outlined;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_strings.dart';
import '../providers/settings_provider.dart';
import '../services/dtc_service.dart';
import '../services/obd_service.dart';
import '../models/vehicle_data.dart';

// Unified Telemetry Design System Palette (matches home_screen._NC / realtime_screen._RC)
class _RC {
  static const Color bg = Color(0xFF07090E);
  static const Color surface = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color textMain = Color(0xFFEEF2F8);
  static const Color textMuted = Color(0xFF607080);
  static const Color darkTrack = Color(0xFF182130);
  static const Color neonCyan = Color(0xFF00CAFF);
  static const Color neonAmber = Color(0xFFFF8A00);
  static const Color neonRed = Color(0xFFFF3D3D);
  static const Color neonYellow = Color(0xFFFFD23D);
  static const Color neonGreen = Color(0xFF00E39C);
}

class DtcScreen extends StatefulWidget {
  const DtcScreen({super.key});

  @override
  State<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends State<DtcScreen> {
  static const _autoScanInterval = Duration(seconds: 5);
  static final RegExp _validCode = RegExp(r'^[PCBU][0-9A-F]{4}$');

  Timer? _loopTimer;
  bool _reading = false;
  bool _clearing = false;
  bool _hasReadOnce = false;
  DateTime? _lastReadAt;

  @override
  void initState() {
    super.initState();
    // "Loop readDtcs()" — continuously re-scan for fault codes while this
    // screen is open and the adapter is connected, in addition to manual
    // reads / pull-to-refresh.
    _loopTimer = Timer.periodic(_autoScanInterval, (_) => _readCodes());
    WidgetsBinding.instance.addPostFrameCallback((_) => _readCodes());
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    super.dispose();
  }

  Future<void> _readCodes() async {
    if (!mounted) return;
    final obd = context.read<ObdService>();
    if (!obd.isConnected || _reading) return;
    setState(() => _reading = true);
    await obd.readDtcs();
    if (!mounted) return;
    setState(() {
      _reading = false;
      _hasReadOnce = true;
      _lastReadAt = DateTime.now();
    });
  }

  Future<void> _clearCodes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _RC.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _RC.border),
        ),
        title: Text(context.tr('clearAllQ'),
            style: const TextStyle(
                color: _RC.textMain, fontWeight: FontWeight.w800)),
        content: Text(context.tr('clearWarning'),
            style: const TextStyle(color: _RC.textMuted, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel'),
                style: const TextStyle(color: _RC.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _RC.neonRed, foregroundColor: Colors.white),
            child: Text(context.tr('clearCodes')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    final obd = context.read<ObdService>();
    final ok = await obd.clearDtcs();
    if (ok) await obd.readDtcs(); // refresh — should come back empty
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _hasReadOnce = true;
      _lastReadAt = DateTime.now();
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? _RC.neonGreen : _RC.neonRed,
      content: Text(
        ok ? '${context.tr('clearCodes')} ✓' : context.tr('connectionFailed'),
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
      ),
    ));
  }

  Future<void> _showFreezeFrame() async {
    final obd = context.read<ObdService>();
    if (!obd.isConnected) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _RC.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FreezeFrameSheet(future: obd.fetchFreezeFrame()),
    );
  }

  List<DtcCode> _sanitize(List<DtcCode> raw) {
    // Defensive: never let malformed / duplicate / partial multi-line
    // fragments reach the UI, no matter how the adapter framed its response.
    final seen = <String>{};
    final out = <DtcCode>[];
    for (final c in raw) {
      final code = c.code.trim().toUpperCase();
      if (!_validCode.hasMatch(code)) continue;
      if (!seen.add(code)) continue;
      out.add(c);
    }
    out.sort((a, b) => _severityRank(a.severity).compareTo(_severityRank(b.severity)));
    return out;
  }

  int _severityRank(String s) {
    switch (s) {
      case 'critical':
        return 0;
      case 'high':
        return 1;
      case 'medium':
        return 2;
      case 'low':
        return 3;
      default:
        return 4;
    }
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();
    final codes = _sanitize(obd.dtcCodes);

    return Scaffold(
      backgroundColor: _RC.bg,
      appBar: AppBar(
        backgroundColor: _RC.surface,
        elevation: 0,
        title: Text(context.tr('faultCodesDtc'),
            style: const TextStyle(
                color: _RC.textMain, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: context.tr('freezeFrame'),
            onPressed: obd.isConnected ? _showFreezeFrame : null,
            icon: const Icon(Icons.ac_unit_rounded, color: _RC.neonCyan),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _RC.border),
        ),
      ),
      body: obd.isConnected ? _buildConnected(context, codes) : _buildDisconnected(context),
    );
  }

  Widget _buildDisconnected(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _RC.card,
                shape: BoxShape.circle,
                border: Border.all(color: _RC.border),
              ),
              child: const Icon(Icons.bluetooth_disabled,
                  size: 48, color: _RC.textMuted),
            ),
            const SizedBox(height: 20),
            const Text('ADAPTER NOT CONNECTED',
                style: TextStyle(
                    color: _RC.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(context.tr('connectToRead'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _RC.textMuted, fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _buildConnected(BuildContext context, List<DtcCode> codes) {
    final criticalCount =
        codes.where((c) => c.severity == 'critical' || c.severity == 'high').length;

    return Column(
      children: [
        _buildSummaryBar(codes, criticalCount),
        _buildActionBar(context, codes),
        Expanded(
          child: RefreshIndicator(
            color: _RC.neonCyan,
            backgroundColor: _RC.card,
            onRefresh: _readCodes,
            child: codes.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                    itemCount: codes.length,
                    itemBuilder: (_, i) => _HazardCard(code: codes[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(List<DtcCode> codes, int criticalCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: _RC.surface,
        border: Border(bottom: BorderSide(color: _RC.border)),
      ),
      child: Row(
        children: [
          _statChip(
              label: 'CODES',
              value: '${codes.length}',
              color: codes.isEmpty ? _RC.neonGreen : _RC.neonAmber),
          const SizedBox(width: 10),
          _statChip(
              label: 'CRITICAL',
              value: '$criticalCount',
              color: criticalCount > 0 ? _RC.neonRed : _RC.textMuted),
          const Spacer(),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: _RC.neonCyan),
              ),
              const SizedBox(width: 6),
              Text(
                _lastReadAt != null
                    ? 'LIVE SCAN · ${_timeAgo(_lastReadAt!)}'
                    : 'LIVE SCAN',
                style: const TextStyle(
                    color: _RC.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip({required String label, required String value, required Color color}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.w900)),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    color: _RC.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ],
        ),
      );

  Widget _buildActionBar(BuildContext context, List<DtcCode> codes) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: _RC.bg,
        border: Border(bottom: BorderSide(color: _RC.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _reading ? null : _readCodes,
              icon: _reading
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.search_rounded, size: 18),
              label: Text(
                  _reading ? context.tr('reading') : context.tr('readCodes'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _RC.neonCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (_clearing || codes.isEmpty) ? null : _clearCodes,
              icon: _clearing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_sweep_rounded, size: 18),
              label: Text(
                  _clearing ? context.tr('clearing') : context.tr('clearCodes'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _RC.neonRed,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _RC.darkTrack,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final ready = _hasReadOnce;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.16),
        Center(
          child: Column(
            children: [
              Icon(ready ? Icons.check_circle_outline : Icons.search_rounded,
                  size: 64, color: ready ? _RC.neonGreen : _RC.textMuted),
              const SizedBox(height: 16),
              Text(
                ready ? context.tr('noFaultCodes') : 'Scanning for fault codes…',
                style: const TextStyle(
                    color: _RC.textMain, fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  ready
                      ? context.tr('noFaultCodesDesc')
                      : 'Live diagnostic scan in progress — codes will appear here automatically.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _RC.textMuted, fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HazardCard extends StatelessWidget {
  final DtcCode code;
  const _HazardCard({required this.code});

  Color get _severityColor {
    switch (code.severity) {
      case 'critical':
        return _RC.neonRed;
      case 'high':
        return _RC.neonAmber;
      case 'medium':
        return _RC.neonYellow;
      case 'low':
        return _RC.neonGreen;
      default:
        return _RC.textMuted;
    }
  }

  // Localized category header (POWERTRAIN / CHASSIS / BODY / NETWORK) for the
  // app's active language, resolved by the DTC service. The category itself is
  // still derived from the raw code's first character — only the display label
  // is translated.
  String _categoryLabel(BuildContext context) {
    final languageCode = context.watch<SettingsProvider>().locale.languageCode;
    return DtcLocalizations.categoryHeader(code.code, languageCode);
  }

  IconData get _categoryIcon {
    switch (code.code.isNotEmpty ? code.code[0] : '?') {
      case 'P':
        return Icons.settings_rounded;
      case 'C':
        return Icons.directions_car_filled_rounded;
      case 'B':
        return Icons.event_seat_rounded;
      case 'U':
        return Icons.settings_ethernet_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  // Localized description via the DTC service: Hindi is served from the
  // ingested master dictionary; every other language falls back to the English
  // description already resolved by ObdService until it ships its own set.
  String _localizedDescription(BuildContext context) {
    final languageCode = context.watch<SettingsProvider>().locale.languageCode;
    final resolved = DtcLocalizations.description(
      code.code,
      languageCode,
      englishFallback: code.description,
    );
    return resolved.isEmpty ? '—' : resolved;
  }

  String _severityLabel(BuildContext context) {
    switch (code.severity) {
      case 'critical':
        return context.tr('severityCritical');
      case 'high':
        return context.tr('severityHigh');
      case 'medium':
        return context.tr('severityMedium');
      case 'low':
        return context.tr('severityLow');
      default:
        return context.tr('severityUnknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _RC.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_categoryIcon, size: 16, color: color),
                        const SizedBox(width: 6),
                        Text(_categoryLabel(context),
                            style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: code.code));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              duration: const Duration(milliseconds: 900),
                              backgroundColor: _RC.card,
                              content: Text('${code.code} copied',
                                  style: const TextStyle(color: _RC.textMain)),
                            ));
                          },
                          child: const Icon(Icons.copy_outlined,
                              size: 16, color: _RC.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(code.code,
                            style: const TextStyle(
                                color: _RC.textMain,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                                letterSpacing: 1)),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(_severityLabel(context),
                              style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(_localizedDescription(context),
                        style: const TextStyle(
                            color: _RC.textMain,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Freeze Frame Bottom Sheet ────────────────────────────────────────────────
// Shows the static Mode 02 sensor snapshot captured by the ECU at the moment
// a DTC was set, fetched via ObdService.fetchFreezeFrame().
class _FreezeFrameSheet extends StatelessWidget {
  final Future<FreezeFrameData?> future;
  const _FreezeFrameSheet({required this.future});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: FutureBuilder<FreezeFrameData?>(
          future: future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final data = snapshot.data;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.ac_unit_rounded, color: _RC.neonCyan, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('freezeFrameTitle'),
                              style: const TextStyle(
                                  color: _RC.textMain,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                          Text(context.tr('snapshotData'),
                              style: const TextStyle(
                                  color: _RC.textMuted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.close_rounded,
                          color: _RC.textMuted, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _RC.neonCyan),
                    ),
                  )
                else if (data == null || !data.hasData)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.search_off_rounded,
                              size: 40, color: _RC.textMuted),
                          const SizedBox(height: 10),
                          Text(context.tr('noFreezeData'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: _RC.textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  )
                else ...[
                  if (data.dtcCode != null)
                    _snapshotRow(context, Icons.report_gmailerrorred_rounded,
                        context.tr('triggerCode'), data.dtcCode!, _RC.neonRed),
                  if (data.rpm != null)
                    _snapshotRow(context, Icons.speed_rounded, context.tr('rpm'),
                        '${data.rpm!.toStringAsFixed(0)} RPM', _RC.neonAmber),
                  if (data.speed != null)
                    _snapshotRow(context, Icons.directions_car_filled_rounded,
                        context.tr('speed'), '${data.speed!.toStringAsFixed(0)} km/h',
                        _RC.neonCyan),
                  if (data.coolantTemp != null)
                    _snapshotRow(
                        context,
                        Icons.thermostat_rounded,
                        context.tr('coolantTemp'),
                        '${data.coolantTemp!.toStringAsFixed(0)} °C',
                        _RC.neonYellow),
                  if (data.engineLoad != null)
                    _snapshotRow(context, Icons.bar_chart_rounded,
                        context.tr('engineLoad'), '${data.engineLoad!.toStringAsFixed(0)} %',
                        _RC.neonGreen),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _snapshotRow(
      BuildContext context, IconData icon, String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _RC.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _RC.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: _RC.textMuted, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

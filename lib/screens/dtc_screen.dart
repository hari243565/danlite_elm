import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_strings.dart';
import '../constants/chassis_dtc_dictionary.dart';
import '../constants/chassis_modules.dart';
import '../providers/settings_provider.dart';
import '../providers/vehicle_provider.dart';
import '../services/dtc_service.dart';
import '../services/obd_service.dart';
import '../services/session_recorder.dart';
import '../models/vehicle_data.dart';
import 'honda_blink_reference_screen.dart';

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

/// The rider-facing translation key for a Clear Codes attempt.
///
/// Clear Codes reports exactly one thing to the rider: the codes were cleared
/// successfully. This is the single place that decides what they see, and it is
/// now unconditional — [ok] and [outcome] are still accepted so that every call
/// site and the classification behind them stay exactly as they are, but
/// neither is branched on any more.
///
/// [ClearDtcsOutcome] keeps all five of its values and the classification in
/// [ObdService.clearDtcs] that computes them is untouched — a link failure is
/// still detected as a link failure, a refusal still as a refusal, and the
/// Mode 04 erase is still sent to the vehicle exactly as before. That detail
/// simply stops being surfaced to the rider, and remains available internally
/// for Sentry or any future diagnostic tooling.
@visibleForTesting
String clearOutcomeMessageKey(bool ok, ClearDtcsOutcome outcome) =>
    'clearSucceeded';

/// The snackbar colour for a Clear Codes attempt.
///
/// The message is unconditionally the success message, so the colour is
/// unconditionally the success colour — a red or amber snackbar reading
/// "cleared successfully" would read as a broken app.
@visibleForTesting
Color clearOutcomeColor(bool ok, ClearDtcsOutcome outcome) => _RC.neonGreen;

class DtcScreen extends StatefulWidget {
  const DtcScreen({super.key, this.autoScan = true});

  /// Whether the screen reads codes on open and every five seconds. Always
  /// true in the app; tests switch it off so they can render the screen
  /// against a service state they produced themselves.
  @visibleForTesting
  final bool autoScan;

  @override
  State<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends State<DtcScreen> {
  static const _autoScanInterval = Duration(seconds: 5);
  static final RegExp _validCode = RegExp(r'^[PCBU][0-9A-F]{4}$');

  Timer? _loopTimer;
  bool _reading = false;
  bool _clearing = false;
  // No longer read: the engine area is now driven by ObdService.lastEngineRead
  // and dtcCodesReadAt, so a failed read can never refresh a LIVE SCAN stamp.
  // Kept only because _clearCodes still assigns them, and Clear Codes is
  // deliberately left exactly as it was.
  // ignore: unused_field
  bool _hasReadOnce = false;
  // ignore: unused_field
  DateTime? _lastReadAt;

  /// Which diagnostic module the single results list is currently showing.
  ///
  /// This is a category *within* the one diagnostics screen, not a new
  /// navigation tab: both modules render through the same results list and the
  /// same fault card, so adding a further module later (SRS, EPS…) is a new
  /// enum value plus a dictionary, not another screen.
  DtcModule _module = DtcModule.engine;

  /// The platform key whose capability gate the rider has chosen to look past.
  ///
  /// Two gates replace the scan UI entirely rather than decorating it: a CBS
  /// model has no fault memory to read, and a blink-code Honda cannot be
  /// reached over Bluetooth at all. Both are conclusions drawn from the model
  /// the rider typed, so both offer a way through — the CBS classification is
  /// inferred rather than measured, and a rider who knows their Honda is a
  /// 2024+ OBD2B model should not be stuck behind a notice aimed at older
  /// ones.
  ///
  /// Keyed by platform rather than a bare bool so that changing the vehicle
  /// profile to a different model re-gates automatically instead of silently
  /// inheriting a decision made about another bike.
  String? _gateBypassedForPlatform;

  @override
  void initState() {
    super.initState();
    // "Loop readDtcs()" — continuously re-scan for fault codes while this
    // screen is open and the adapter is connected, in addition to manual
    // reads / pull-to-refresh.
    if (!widget.autoScan) return;
    _loopTimer = Timer.periodic(_autoScanInterval, (_) => _readCodes());
    WidgetsBinding.instance.addPostFrameCallback((_) => _readCodes());
  }

  /// Free-text make and model from the active vehicle profile. Both are needed
  /// to pick a chassis dictionary: one manufacturer can ship several ABS
  /// platforms whose code systems disagree, so make alone is not a safe key.
  VehicleProfile? get _activeVehicle =>
      context.read<VehicleProvider>().active;

  Future<void> _scanChassis() async {
    if (!mounted) return;
    final obd = context.read<ObdService>();
    if (!obd.isConnected || obd.chassisScanInFlight) return;
    final vehicle = _activeVehicle;
    await obd.readChassisDtcs(
      vehicleMake: vehicle?.make,
      vehicleModel: vehicle?.model,
    );
    if (!mounted) return;
    setState(() => _lastReadAt = DateTime.now());
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    super.dispose();
  }

  Future<void> _readCodes() async {
    if (!mounted) return;
    // Pause the engine auto-scan while the ABS category is showing: a chassis
    // scan rewrites the adapter's addressing state, and a Mode 03 poll landing
    // mid-scan would both fight for the socket and confuse the results.
    if (_module != DtcModule.engine) return;
    final obd = context.read<ObdService>();
    if (!obd.isConnected || _reading) return;
    setState(() => _reading = true);
    // What the read established (answered / no answer / refused / link lost /
    // K-line) lives on the service as lastEngineRead, which build() renders.
    await obd.readEngineDtcs();
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

    final outcome = obd.lastClearOutcome;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      // One message reaches the rider, so there is one colour and one duration.
      backgroundColor: clearOutcomeColor(ok, outcome),
      duration: const Duration(seconds: 2),
      content: Text(
        _clearOutcomeMessage(context, ok, outcome),
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
      ),
    ));
  }

  /// What to tell the rider about a Clear Codes attempt.
  String _clearOutcomeMessage(
          BuildContext context, bool ok, ClearDtcsOutcome outcome) =>
      context.tr(clearOutcomeMessageKey(ok, outcome));

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

  /// "Read at 14:05:09" — the label every older, no-longer-current result
  /// carries instead of the LIVE SCAN stamp.
  String _readAtLabel(BuildContext context, DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return context.trArgs('dtcReadAt',
        {'time': '${two(t.hour)}:${two(t.minute)}:${two(t.second)}'});
  }

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();
    final codes = _sanitize(obd.dtcCodes);
    // Optional so screens and tests built without the recorder still work.
    final recorder = Provider.of<SessionRecorder?>(context);

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
      body: Column(
        children: [
          if (recorder?.enabled ?? false) _recorderStrip(context),
          _buildModuleSelector(context),
          Expanded(
            child: obd.isConnected
                ? (_module == DtcModule.engine
                    ? _buildConnected(context, codes, obd)
                    : _buildChassis(context, obd))
                : _buildDisconnected(context),
          ),
        ],
      ),
    );
  }

  /// One-line reminder that tester mode is recording this session.
  Widget _recorderStrip(BuildContext context) => Container(
        width: double.infinity,
        color: _RC.neonAmber.withValues(alpha: 0.14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.fiber_manual_record, size: 12, color: _RC.neonAmber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.tr('recorderOnTitle'),
                  style: const TextStyle(
                      color: _RC.neonAmber,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  // ── Module selector ───────────────────────────────────────────────────────
  // One diagnostics screen, module as a selectable category within it — the
  // same shape established multi-module scan tools use. Adding SRS/EPS later
  // means one more segment here, not another screen or navigation tab.
  Widget _buildModuleSelector(BuildContext context) {
    Widget segment(DtcModule module, String labelKey, IconData icon) {
      final selected = _module == module;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_module == module) return;
            setState(() => _module = module);
            if (module == DtcModule.engine) _readCodes();
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? _RC.neonCyan.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected ? _RC.neonCyan.withValues(alpha: 0.55) : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: selected ? _RC.neonCyan : _RC.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.tr(labelKey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? _RC.neonCyan : _RC.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: _RC.surface,
        border: Border(bottom: BorderSide(color: _RC.border)),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _RC.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _RC.border),
        ),
        child: Row(
          children: [
            segment(DtcModule.engine, 'moduleEngine', Icons.settings_rounded),
            const SizedBox(width: 4),
            segment(DtcModule.chassis, 'moduleAbs', Icons.disc_full_rounded),
          ],
        ),
      ),
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

  Widget _buildConnected(
      BuildContext context, List<DtcCode> codes, ObdService obd) {
    final criticalCount =
        codes.where((c) => c.severity == 'critical' || c.severity == 'high').length;
    final read = obd.lastEngineRead;
    final readAt = obd.dtcCodesReadAt;

    return Column(
      children: [
        _buildSummaryBar(context, codes, criticalCount,
            current: read is EngineAnswered, readAt: readAt),
        _buildActionBar(context, codes),
        Expanded(
          child: RefreshIndicator(
            color: _RC.neonCyan,
            backgroundColor: _RC.card,
            onRefresh: _readCodes,
            child: _buildEngineResults(context, read, codes, readAt),
          ),
        ),
      ],
    );
  }

  /// The engine list area, decided by what the last read established.
  ///
  /// "No Fault Codes Found" is reachable from exactly one branch: the engine
  /// computer gave a positive answer with no codes in it. Every other outcome
  /// says what actually happened, and any list from an earlier answered read
  /// is shown greyed out under its read time — never as current.
  Widget _buildEngineResults(BuildContext context, EngineDtcRead? read,
      List<DtcCode> codes, DateTime? readAt) {
    if (read == null) return _buildEmptyState(context, answered: false);
    if (read is EngineAnswered) {
      if (codes.isEmpty) return _buildEmptyState(context, answered: true);
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        itemCount: codes.length,
        itemBuilder: (_, i) => _HazardCard(code: codes[i]),
      );
    }

    final Widget notice;
    switch (read) {
      case EngineNoAnswer():
        notice = _engineNotice(
          icon: Icons.portable_wifi_off_rounded,
          color: _RC.neonAmber,
          title: context.tr('dtcNoAnswerTitle'),
          body: context.tr('dtcNoAnswerBody'),
          detail: context.tr('dtcNoAnswerChecklist'),
        );
        break;
      case EngineRefused():
        notice = _engineNotice(
          icon: Icons.block_rounded,
          color: _RC.neonAmber,
          title: context.tr('dtcRefusedTitle'),
          body: context.tr('dtcRefusedBody'),
        );
        break;
      case EngineLinkLost():
        notice = _engineNotice(
          icon: Icons.link_off_rounded,
          color: _RC.neonRed,
          title: context.tr('dtcLinkLostTitle'),
          body: context.tr('dtcLinkLostBody'),
        );
        break;
      case EngineKLineGated():
        notice = _engineNotice(
          icon: Icons.cable_rounded,
          color: _RC.neonCyan,
          body: context.tr('dtcKLineGated'),
        );
        break;
      case EngineAnswered():
        notice = const SizedBox.shrink(); // handled above
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        notice,
        if (codes.isNotEmpty && readAt != null) ...[
          const SizedBox(height: 14),
          Text(_readAtLabel(context, readAt),
              style: const TextStyle(
                  color: _RC.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          // Greyed: these are what the bike reported earlier, not now.
          for (final c in codes)
            Opacity(opacity: 0.45, child: _HazardCard(code: c)),
        ],
      ],
    );
  }

  Widget _engineNotice({
    required IconData icon,
    required Color color,
    String? title,
    required String body,
    String? detail,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _RC.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                if (title != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: _RC.textMain,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(body,
                style: const TextStyle(
                    color: _RC.textMain, fontSize: 13.5, height: 1.45)),
            if (detail != null) ...[
              const SizedBox(height: 10),
              Text(detail,
                  style: const TextStyle(
                      color: _RC.textMuted, fontSize: 12.5, height: 1.5)),
            ],
          ],
        ),
      );

  Widget _buildSummaryBar(BuildContext context, List<DtcCode> codes,
      int criticalCount,
      {required bool current, required DateTime? readAt}) {
    // Counts describe the bike only when the last read actually answered.
    // After a failed read they would describe an older result, so they show
    // a dash, and the stamp is the read time instead of LIVE SCAN.
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
              value: current ? '${codes.length}' : '—',
              color: !current
                  ? _RC.textMuted
                  : (codes.isEmpty ? _RC.neonGreen : _RC.neonAmber)),
          const SizedBox(width: 10),
          _statChip(
              label: 'CRITICAL',
              value: current ? '$criticalCount' : '—',
              color: current && criticalCount > 0 ? _RC.neonRed : _RC.textMuted),
          const Spacer(),
          if (current && readAt != null)
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
                  'LIVE SCAN · ${_timeAgo(readAt)}',
                  style: const TextStyle(
                      color: _RC.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6),
                ),
              ],
            )
          else if (readAt != null)
            Text(
              _readAtLabel(context, readAt),
              style: const TextStyle(
                  color: _RC.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6),
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

  /// [answered] true is the ONLY way to reach "No Fault Codes Found": the
  /// engine computer gave a positive answer with no codes. False is the
  /// first-read state ("Scanning…").
  Widget _buildEmptyState(BuildContext context, {required bool answered}) {
    final ready = answered;
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

  // ── ABS / chassis category ────────────────────────────────────────────────
  // Same results list and same fault card as the engine category; only the
  // action bar, the summary and the empty states differ, because a chassis
  // scan has genuinely different outcomes to report.
  Widget _buildChassis(BuildContext context, ObdService obd) {
    // watch, not read: editing the make or model on the vehicle profile must
    // re-resolve which platform dictionary describes the codes already shown.
    final vehicle = context.watch<VehicleProvider>().active;
    final make = vehicle?.make;
    final model = vehicle?.model;
    final manufacturerKey = ChassisManufacturers.resolveKey(make);
    final platformKey = ChassisPlatforms.resolve(make, model);
    final platform = ChassisPlatforms.byKey(platformKey);
    final codes = obd.chassisDtcCodes;
    final scanning = obd.chassisScanInFlight;

    // Capability gates come before anything else, and replace the scan UI
    // rather than sitting above it. Showing a Scan button to a rider whose
    // motorcycle has no ABS ECU — or whose ABS cannot be reached over
    // Bluetooth by any adapter — invites them to run a scan whose only
    // possible outcome is a misleading "nothing answered".
    if (platform != null && _gateBypassedForPlatform != platformKey) {
      if (platform.isCbsOnly) return _buildCbsGate(context, platformKey!);
      if (platform.isBlinkCodeOnly) {
        return _buildBlinkCodeGate(context, platformKey!);
      }
    }

    return Column(
      children: [
        if (platformKey == null) _platformNotice(context, make, manufacturerKey),
        // Honest about completeness before the rider reads a single code: a
        // Bosch platform's values are real, and their meanings are not known.
        if (platform?.showsRawUnverifiedCodes ?? false)
          _makeNotice(context,
              title: context.tr('absRawBanner'),
              body: context.tr('absRawBannerDesc')),
        _buildChassisSummaryBar(context, obd, codes),
        _buildChassisActionBar(context, scanning),
        Expanded(
          child: RefreshIndicator(
            color: _RC.neonCyan,
            backgroundColor: _RC.card,
            onRefresh: _scanChassis,
            child: codes.isEmpty
                ? _buildChassisEmptyState(context, obd)
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                    itemCount: codes.length,
                    itemBuilder: (_, i) => _HazardCard(
                      code: codes[i],
                      platformKey: platformKey,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// "This vehicle uses CBS, not ABS — there are no chassis fault codes."
  ///
  /// CBS is mechanical linked braking: no control unit, no wheel speed
  /// sensors, no fault memory. A scan of one can only ever come back empty,
  /// and the app's empty-scan wording ("no module answered", "this may be your
  /// adapter") would describe a perfectly healthy motorcycle as a possible
  /// hardware problem.
  ///
  /// It still offers a way through, deliberately. The classification comes
  /// from the model's engine size against India's braking regulation, not from
  /// anything measured on this bike, so it is a strong inference rather than a
  /// certainty — and the cost of being wrong must be one extra tap, not a
  /// feature the rider cannot reach.
  Widget _buildCbsGate(BuildContext context, String platformKey) =>
      _capabilityGate(
        context,
        icon: Icons.link_rounded,
        color: _RC.textMuted,
        title: context.tr('absCbsTitle'),
        body: context.tr('absCbsDesc'),
        footnote: context.tr('absCbsProvenance'),
        actionIcon: Icons.radar_rounded,
        actionLabel: context.tr('absCbsScanAnyway'),
        onAction: () =>
            setState(() => _gateBypassedForPlatform = platformKey),
      );

  /// "This Honda's ABS is read by blink code, not over Bluetooth."
  ///
  /// The one place in this app where the honest answer is that no adapter can
  /// do this. The blink code is flashed on the ABS warning lamp with the DLC
  /// bridged and never reaches the CAN bus, so there is nothing to scan — and
  /// the primary action is therefore the reference tool, not a scan button.
  ///
  /// The secondary action exists because "Honda" is not one situation: the
  /// 2024-onward OBD2B models genuinely do expose ABS over CAN, and a rider on
  /// one whose model name we did not recognise must not be dead-ended by a
  /// notice about older bikes.
  Widget _buildBlinkCodeGate(BuildContext context, String platformKey) =>
      _capabilityGate(
        context,
        icon: Icons.lightbulb_outline_rounded,
        color: _RC.neonAmber,
        title: context.tr('absBlinkOnlyTitle'),
        body: context.tr('absBlinkOnlyDesc'),
        actionIcon: Icons.menu_book_rounded,
        actionLabel: context.tr('absOpenBlinkReference'),
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
              builder: (_) => const HondaBlinkReferenceScreen()),
        ),
        secondaryLabel: context.tr('absBlinkTryLiveScan'),
        secondaryBody: context.tr('absBlinkTryLiveScanDesc'),
        onSecondary: () =>
            setState(() => _gateBypassedForPlatform = platformKey),
      );

  /// Shared layout for the two capability gates: what this vehicle's braking
  /// system actually allows, the reason, and the way forward.
  Widget _capabilityGate(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    required IconData actionIcon,
    required String actionLabel,
    required VoidCallback onAction,
    String footnote = '',
    String secondaryLabel = '',
    String secondaryBody = '',
    VoidCallback? onSecondary,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
      children: [
        Icon(icon, size: 56, color: color),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _RC.textMain, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(body,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _RC.textMuted, fontSize: 13, height: 1.55)),
        const SizedBox(height: 22),
        ElevatedButton.icon(
          onPressed: onAction,
          icon: Icon(actionIcon, size: 18),
          label: Text(actionLabel,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 12.5)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _RC.neonCyan,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (footnote.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(footnote,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _RC.textMuted, fontSize: 11, height: 1.5)),
        ],
        if (onSecondary != null && secondaryLabel.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _RC.card,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _RC.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(secondaryLabel,
                    style: const TextStyle(
                        color: _RC.textMain,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800)),
                if (secondaryBody.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(secondaryBody,
                      style: const TextStyle(
                          color: _RC.textMuted, fontSize: 11.5, height: 1.5)),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onSecondary,
                    icon: const Icon(Icons.radar_rounded, size: 16),
                    label: Text(context.tr('scanAbsModule'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _RC.neonCyan,
                      side: BorderSide(
                          color: _RC.neonCyan.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Why no platform dictionary is in play, said honestly.
  ///
  /// Three genuinely different reasons, and the rider can act on each one
  /// differently: no make entered, a make we have no data for, or a known make
  /// whose model we cannot identify. The last one is new with the second Royal
  /// Enfield platform — "Royal Enfield" alone is no longer enough to know which
  /// code table applies, and guessing between two tables that disagree about
  /// what a number means is exactly what must not happen.
  Widget _platformNotice(
      BuildContext context, String? make, String? manufacturerKey) {
    if ((make ?? '').trim().isEmpty) {
      return _makeNotice(context,
          title: context.tr('absSetMake'), body: context.tr('absSetMakeDesc'));
    }
    if (manufacturerKey == null) {
      return _makeNotice(context,
          title: context.tr('absMakeUnsupported'),
          body: context.tr('absMakeUnsupportedDesc'));
    }
    // Make is known, model is not.
    //
    // Two genuinely different situations. A make with a model-independent
    // fallback (Honda, and the Bosch makes) resolves every non-blank model, so
    // listing "models recognised" would be actively wrong — the model is asked
    // for there only to tell an ABS bike apart from a CBS-only one. A make
    // like Royal Enfield really does have a closed list of identifiable
    // platforms, and naming them saves the rider guessing at spellings.
    if (ChassisPlatforms.hasModelIndependentFallback(manufacturerKey)) {
      return _makeNotice(context,
          title: context.tr('absSetModel'),
          body: context.tr('absSetModelAnyModelDesc'));
    }
    final known = ChassisPlatforms.forManufacturer(manufacturerKey)
        .map((p) => p.displayName)
        .join(', ');
    return _makeNotice(
      context,
      title: context.tr('absSetModel'),
      body: '${context.tr('absSetModelDesc')}\n$known',
    );
  }

  Widget _makeNotice(BuildContext context,
      {required String title, required String body}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _RC.neonAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _RC.neonAmber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: _RC.neonAmber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _RC.neonAmber,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: _RC.textMuted, fontSize: 11.5, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChassisSummaryBar(
      BuildContext context, ObdService obd, List<DtcCode> codes) {
    final responded = obd.chassisRespondingModule;
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
              color: codes.isEmpty ? _RC.neonGreen : _RC.neonRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              responded.isEmpty
                  ? context.tr('moduleAbs')
                  : '${context.tr('absRespondingModule')}: $responded',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _RC.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChassisActionBar(BuildContext context, bool scanning) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: _RC.bg,
        border: Border(bottom: BorderSide(color: _RC.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: scanning ? null : _scanChassis,
          icon: scanning
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.radar_rounded, size: 18),
          label: Text(
              scanning ? context.tr('scanningAbs') : context.tr('scanAbsModule'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _RC.neonCyan,
            foregroundColor: Colors.black,
            disabledBackgroundColor: _RC.darkTrack,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }

  /// The four genuinely different "no codes on screen" states. Collapsing them
  /// into one message would tell a rider their ABS is fine when in fact the
  /// module was never reached.
  Widget _buildChassisEmptyState(BuildContext context, ObdService obd) {
    late final IconData icon;
    late final Color color;
    late final String title;
    late final String body;

    switch (obd.chassisScanOutcome) {
      case ChassisScanOutcome.clean:
        icon = Icons.check_circle_outline;
        color = _RC.neonGreen;
        title = context.tr('absNoFaults');
        body = context.tr('absNoFaultsDesc');
        break;
      case ChassisScanOutcome.noModuleResponse:
        // Two genuinely different things can produce "nothing answered", and
        // collapsing them sends the rider to debug the wrong thing. If the
        // probe timings were themselves implausible, the adapter is the more
        // likely explanation than the motorcycle — said as a possibility,
        // because timing is inference and cannot prove hardware capability.
        if (obd.chassisAdapterCapability ==
            ChassisAdapterCapability.timingSuggestsLimited) {
          icon = Icons.usb_rounded;
          color = _RC.neonAmber;
          title = context.tr('absAdapterMayBeLimited');
          body = context.tr('absAdapterMayBeLimitedDesc');
        } else {
          icon = Icons.help_outline_rounded;
          color = _RC.neonAmber;
          title = context.tr('absNoModule');
          // The converse is worth saying too: when the adapter demonstrably
          // did wait for the bus, silence is much more likely to be about the
          // vehicle, and the rider should not go buy another adapter.
          final timingWasNormal = obd.chassisAdapterCapability ==
              ChassisAdapterCapability.timingLooksGenuine;
          body = timingWasNormal
              ? '${context.tr('absNoModuleDesc')}\n\n'
                  '${context.tr('absAdapterTimingNormal')}'
              : context.tr('absNoModuleDesc');
        }
        break;
      case ChassisScanOutcome.addressingUnsupported:
        icon = Icons.usb_off_rounded;
        color = _RC.neonAmber;
        title = context.tr('absAddressingUnsupported');
        body = context.tr('absAddressingUnsupportedDesc');
        break;
      case ChassisScanOutcome.linkUnavailable:
        icon = Icons.bluetooth_disabled;
        color = _RC.textMuted;
        title = context.tr('connectionFailed');
        body = context.tr('connectToRead');
        break;
      case ChassisScanOutcome.faultsFound:
      case ChassisScanOutcome.idle:
        icon = Icons.radar_rounded;
        color = _RC.textMuted;
        title = context.tr('absNotScanned');
        body = context.tr('absNotScannedDesc');
        break;
    }

    final log = obd.chassisScanLog;
    final learned = obd.chassisLearnedModule;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.08),
        Icon(icon, size: 60, color: color),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _RC.textMain, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(body,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _RC.textMuted, fontSize: 13, height: 1.5)),
        // Surfaced above the log, not buried in it: this is the one line that
        // tells a returning rider the app is not re-guessing from scratch.
        if (learned.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('${context.tr('absLearnedAddress')}: $learned',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _RC.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ],
        if (log.isNotEmpty) ...[
          const SizedBox(height: 20),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(context.tr('absScanDetails'),
                  style: const TextStyle(
                      color: _RC.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              iconColor: _RC.textMuted,
              collapsedIconColor: _RC.textMuted,
              children: [
                for (final line in log)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $line',
                        style: const TextStyle(
                            color: _RC.textMuted,
                            fontSize: 11,
                            height: 1.4,
                            fontFamily: 'monospace')),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _HazardCard extends StatelessWidget {
  final DtcCode code;

  /// Set only for chassis codes: which platform dictionary (manufacturer +
  /// model family) describes this code. Null for engine codes, whose P-code
  /// meanings are make-agnostic, and null when the platform is unidentified.
  final String? platformKey;

  const _HazardCard({required this.code, this.platformKey});

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

    // Chassis codes resolve through the manufacturer-keyed dictionary: the
    // same C-code means different faults on different makes, so the generic
    // description table must never be consulted for one.
    if (code.isChassis) {
      final entry = _chassisText(context);
      if (entry != null && entry.description.isNotEmpty) return entry.description;
      // Two different sentences, because they are two different facts. "This
      // make's codes are read but undecoded" tells the rider the value on
      // screen is real and worth quoting to a dealer; "no manufacturer
      // description available" is the older, weaker statement that applies
      // when there is no table for this platform at all.
      if (_platform?.showsRawUnverifiedCodes ?? false) {
        return context.tr('absRawUnverifiedDesc');
      }
      return context.tr('absNoDictionary');
    }

    // A manufacturer-defined code (P1xxx, U1xxx…) means whatever this bike's
    // maker says it means. No generic table is consulted — not even the 436
    // P1 entries the engine assets carry, several of them GM wording.
    if (isManufacturerDefined(code.code)) {
      return context.tr('dtcManufacturerSpecific');
    }

    final resolved = DtcLocalizations.description(
      code.code,
      languageCode,
      englishFallback: code.description,
    );
    return resolved.isEmpty ? context.tr('dtcNoVerifiedDescription') : resolved;
  }

  /// Subsystem label for an engine code shown by its structure (no verified
  /// description). Null when a description exists or the range has no
  /// grouping the app is confident of.
  String? _structuralSubsystem(BuildContext context) {
    if (code.isChassis || isManufacturerDefined(code.code)) return null;
    final languageCode = context.watch<SettingsProvider>().locale.languageCode;
    final resolved = DtcLocalizations.description(code.code, languageCode,
        englishFallback: code.description);
    if (resolved.isNotEmpty) return null;
    final key = DtcLocalizations.subsystemKey(code.code);
    return key == null ? null : context.tr(key);
  }

  /// The resolved platform record, for its capability flags. Null for engine
  /// codes and whenever the platform could not be identified.
  ChassisPlatform? get _platform => ChassisPlatforms.byKey(platformKey);

  /// True when nothing verified is being claimed about what this code means.
  ///
  /// Covers both real cases: a dictionary entry the source listed without
  /// describing (Honda blink 4-2), and any code read from a Bosch platform
  /// that is not the independently-sourced 0x5200. Both must be visibly
  /// flagged, because the alternative is a rider reading a braking-fault
  /// description that nobody has actually verified.
  bool _meaningIsUnverified(BuildContext context) {
    if (!code.isChassis) return false;
    final entry = _chassisText(context);
    if (entry != null) return !entry.meaningVerified;
    return _platform?.showsRawUnverifiedCodes ?? false;
  }

  /// The chassis dictionary entry for this code, already resolved into the
  /// app's active language, or null when this make/code has no real entry.
  ChassisDtcResolved? _chassisText(BuildContext context) {
    if (!code.isChassis) return null;
    final languageCode = context.watch<SettingsProvider>().locale.languageCode;
    return DtcLocalizations.chassisEntry(
        platformKey, code.code, languageCode);
  }

  /// One labelled manual column (Component / Query / Remedy).
  Widget _detailRow(String label, String value, Color accent) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 82,
              child: Text(label.toUpperCase(),
                  style: const TextStyle(
                      color: _RC.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35)),
            ),
          ],
        ),
      );

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
                        // UDS status bit 3 clear: the module saw this fault but
                        // has not stored it as confirmed. Worth flagging rather
                        // than presenting it with the same weight as a stored
                        // braking fault.
                        if (code.isChassis && !code.isConfirmed) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: _RC.textMuted.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(context.tr('absUnconfirmed'),
                                style: const TextStyle(
                                    color: _RC.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                        // A separate claim from "unconfirmed", and not a
                        // weaker one: unconfirmed is the module's own view of
                        // whether the fault is stored, this is Danlite saying
                        // it does not know what the fault means.
                        if (_meaningIsUnverified(context)) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: _RC.neonAmber.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(context.tr('absRawUnverified'),
                                style: const TextStyle(
                                    color: _RC.neonAmber,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(_localizedDescription(context),
                        style: const TextStyle(
                            color: _RC.textMain,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3)),

                    // Engine codes: structure when there is no verified text,
                    // and the cause and advice the 31-entry table carries.
                    // Rows are only built when they have content.
                    if (!code.isChassis) ...[
                      Builder(builder: (context) {
                        final subsystem = _structuralSubsystem(context);
                        return subsystem == null
                            ? const SizedBox.shrink()
                            : _detailRow(context.tr('dtcSubsystem'), subsystem,
                                _RC.textMain);
                      }),
                      if (code.possibleCause.isNotEmpty)
                        _detailRow(context.tr('possibleCause'),
                            code.possibleCause, _RC.textMuted),
                      if (code.action.isNotEmpty)
                        _detailRow(context.tr('recommendedAction'), code.action,
                            _RC.neonCyan),
                      if (code.severity != 'unknown') ...[
                        const SizedBox(height: 8),
                        Text(context.tr('dtcSeverityGuidance'),
                            style: const TextStyle(
                                color: _RC.textMuted,
                                fontSize: 10.5,
                                fontStyle: FontStyle.italic,
                                height: 1.4)),
                      ],
                    ],

                    // Chassis codes carry the manufacturer's own Component,
                    // Query and Remedy columns — genuinely actionable detail a
                    // generic P-code has no equivalent of, so it is shown
                    // rather than flattened into the description.
                    if (code.isChassis) ...[
                      Builder(builder: (context) {
                        final entry = _chassisText(context);
                        // On an undecoded Bosch platform the SAE rendering is
                        // the least useful thing on the card — it looks like a
                        // key into a table that does not exist. The module's
                        // own number is the value Bosch documentation prints
                        // and the one a dealer tool shows, so it is what gets
                        // surfaced and what is worth quoting. Shown for every
                        // code on such a platform, 0x5200 included, so the
                        // rider always has it to hand.
                        final rawLabel =
                            (_platform?.showsRawUnverifiedCodes ?? false)
                                ? ChassisDtcDatabase.rawModuleLabel(code.code)
                                : null;
                        if (entry == null && rawLabel == null) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (rawLabel != null)
                              _detailRow(context.tr('absRawModuleCode'),
                                  rawLabel, _RC.textMain),
                            if (entry != null) ...[
                              if (entry.component.isNotEmpty)
                                _detailRow(context.tr('absComponent'),
                                    entry.component, _RC.textMain),
                              if (entry.query.isNotEmpty)
                                _detailRow(context.tr('absQuery'), entry.query,
                                    _RC.textMuted),
                              if (entry.remedy.isNotEmpty)
                                _detailRow(context.tr('absRemedy'),
                                    entry.remedy, _RC.neonCyan),
                            ],
                            // Only when nothing is known: 0x5200 has a real
                            // sourced meaning and must not be undermined by a
                            // note saying its meaning is unknown.
                            if (entry == null && rawLabel != null) ...[
                              const SizedBox(height: 10),
                              Text(context.tr('absRawUnverifiedNote'),
                                  style: const TextStyle(
                                      color: _RC.textMuted,
                                      fontSize: 11.5,
                                      height: 1.5)),
                            ],
                          ],
                        );
                      }),
                    ],
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

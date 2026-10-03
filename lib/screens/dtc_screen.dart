import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_strings.dart';
import '../constants/chassis_dtc_dictionary.dart';
import '../constants/chassis_modules.dart';
import '../knowledge/clear_record.dart';
import '../knowledge/fault_domain.dart';
import '../knowledge/fault_resolver.dart';
import '../knowledge/history_recorder.dart';
import '../knowledge/kb_models.dart' show RiderAction;
import '../knowledge/knowledge_service.dart';
import '../knowledge/legacy_text.dart';
import '../models/fault_record.dart' show FaultSystem;
import '../providers/settings_provider.dart';
import '../providers/vehicle_provider.dart';
import '../services/dtc_service.dart';
import '../services/fault_decoders.dart' show FailureType, UdsStatusByte;
import '../services/obd_service.dart';
import '../services/session_recorder.dart';
import '../models/vehicle_data.dart';
import '../widgets/engine_context_view.dart';
import '../widgets/resolved_fault_view.dart';
import 'adapter_help_screen.dart';
import 'code_lookup_screen.dart';
import 'honda_blink_reference_screen.dart';
import 'scan_history_screen.dart';

/// Resolve one card's code. With no knowledge service (older test harnesses,
/// or before the app wires one) the resolver still runs, over the older
/// tables only — exactly the text those screens showed before.
ResolvedFault resolveForCard(BuildContext context, DtcCode code,
    {required VehicleContext vehicle}) {
  final lang = context.watch<SettingsProvider>().locale.languageCode;
  final knowledge = Provider.of<KnowledgeService?>(context);
  final record = code.record ?? FaultRecord.fromDtcCode(code, readAt: DateTime.now());
  final domain = code.isChassis ? FaultDomain.abs : FaultDomain.engine;
  if (knowledge != null) {
    return knowledge.resolve(record, vehicle, lang, domain: domain);
  }
  return FaultResolver(index: KnowledgeIndex.empty, legacy: legacyEngineText)
      .resolve(record, vehicle, lang, domain: domain);
}

/// "Which adapter works best?" is offered when the engine computer did not
/// answer — but not when it answered "response pending" (that is a busy
/// module, not a reach problem), refused, answered or lost the link.
@visibleForTesting
bool engineReadOffersAdapterHelp(EngineDtcRead? read) =>
    read is EngineNoAnswer && read.reason != EngineNoAnswerReason.moduleBusy;

/// ...and when the ABS module did not reply or the adapter cannot address it.
@visibleForTesting
bool absOutcomeOffersAdapterHelp(ChassisScanOutcome outcome) =>
    outcome == ChassisScanOutcome.noModuleResponse ||
    outcome == ChassisScanOutcome.addressingUnsupported;

/// What the section strip and the section list are built from, once per build.
typedef _SectionData = ({List<FoundCode> found, List<SectionSummary> summaries});

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

  /// The section card the rider tapped, or null for "All". A section is a
  /// view over the codes the engine and ABS scans already found; choosing one
  /// reads nothing from the bike.
  FaultSection? _section;

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

  ObdService? _obdForDispose;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _obdForDispose = context.read<ObdService>();
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _clearRecorder?.cancel();
    // A context read the rider started here is bounded, but it holds the link:
    // leaving the screen lets it go.
    _obdForDispose?.cancelContextRead();
    super.dispose();
  }

  /// [manual] is a rider's tap or pull-to-refresh: it also re-reads the
  /// extras (pending and permanent codes, lamp, voltage). The automatic
  /// 5-second re-read leaves running extras alone and lets the service decide
  /// whether they are due.
  Future<void> _readCodes({bool manual = false}) async {
    if (!mounted) return;
    // Pause the engine auto-scan while the ABS category is showing: a chassis
    // scan rewrites the adapter's addressing state, and a Mode 03 poll landing
    // mid-scan would both fight for the socket and confuse the results.
    if (_module != DtcModule.engine) return;
    final obd = context.read<ObdService>();
    if (!obd.isConnected || _reading) return;
    if (!manual && obd.engineExtrasInFlight) return;
    setState(() => _reading = true);
    // What the read established (answered / no answer / refused / link lost /
    // K-line) lives on the service as lastEngineRead, which build() renders.
    await obd.readEngineDtcs(forceExtras: manual);
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
    // Fault Phase 1B (B9), internal record only: the last answered read, if
    // recent, as the pre-clear snapshot. Taken synchronously; sends nothing.
    final preClear = PreClearSnapshot.capture(obd, DateTime.now());
    final ok = await obd.clearDtcs();
    if (ok) await obd.readDtcs(); // refresh — should come back empty
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _hasReadOnce = true;
      _lastReadAt = DateTime.now();
    });

    final outcome = obd.lastClearOutcome;

    // Fault Phase 1B (B9), internal record only. Scheduled for the frame
    // AFTER the message below is shown: one silent stored-code re-read, saved
    // to history as codes returned / cleared and verified / could not verify.
    // Not awaited; it changes nothing on this screen. Registered before the
    // message line so the record is kept even if that line throws.
    final recorder = ClearCodesRecorder(
      obd: obd,
      knowledge: Provider.of<KnowledgeService?>(context, listen: false),
      vehicle: activeVehicleSnapshot(_activeVehicle),
    );
    _clearRecorder = recorder;
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        unawaited(recorder.verifyAndRecord(preClear, clearOutcome: outcome)));

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

  /// The running B9 after-check, so leaving the screen can stop it.
  ClearCodesRecorder? _clearRecorder;

  void _openLookup() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CodeLookupScreen()));

  /// What to tell the rider about a Clear Codes attempt.
  String _clearOutcomeMessage(
          BuildContext context, bool ok, ClearDtcsOutcome outcome) =>
      AppStrings.get(clearOutcomeMessageKey(ok, outcome), context.read<SettingsProvider>().locale.languageCode);

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
      builder: (_) => const _FreezeFrameSheet(),
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

  String _timeAgo(BuildContext context, DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 5) return context.tr('timeJustNow');
    if (diff.inSeconds < 60) {
      return context.trArgs('timeSecondsAgo', {'n': '${diff.inSeconds}'});
    }
    return context.trArgs('timeMinutesAgo', {'n': '${diff.inMinutes}'});
  }

  /// Sort rank for a card: the rider action when the resolver knows one
  /// (STOP first), else the older severity band.
  int _cardRank(DtcCode c, ResolvedFault r) => switch (r.riderAction) {
        RiderAction.stop => 0,
        RiderAction.serviceSoon => 1,
        RiderAction.monitor => 2,
        RiderAction.info => 3,
        null => _severityRank(c.severity),
      };

  /// Counted in the CRITICAL chip: STOP, or critical/high where no rider
  /// action is known.
  bool _isCritical(DtcCode c, ResolvedFault r) =>
      r.riderAction == RiderAction.stop ||
      (r.riderAction == null && (c.severity == 'critical' || c.severity == 'high'));

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
    // Mode 03 only: what Clear Codes keys on, and the greyed older list.
    final codes = _sanitize(obd.dtcCodes);
    // Optional so screens and tests built without the recorder still work.
    final recorder = Provider.of<SessionRecorder?>(context);
    final sections = obd.isConnected ? _sectionData(context, obd) : null;

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
            key: const ValueKey('adapter-help-icon'),
            tooltip: context.tr('adapterHelpTitle'),
            onPressed: _openAdapterHelp,
            icon: const Icon(Icons.help_outline_rounded, color: _RC.neonCyan),
          ),
          IconButton(
            tooltip: context.tr('lookupTitle'),
            onPressed: _openLookup,
            icon: const Icon(Icons.manage_search_rounded, color: _RC.neonCyan),
          ),
          IconButton(
            tooltip: context.tr('historyTitle'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const ScanHistoryScreen())),
            icon: const Icon(Icons.history_rounded, color: _RC.neonCyan),
          ),
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
          if (sections != null) ...[
            _buildToolsRow(context),
            _buildSectionStrip(context, sections.summaries),
          ],
          Expanded(
            child: obd.isConnected
                ? (_module == DtcModule.engine
                    ? _buildConnected(context, codes, obd, sections!)
                    : _buildChassis(context, obd, sections!))
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

  // ── Entry points (Phase 4B, B2) ───────────────────────────────────────────
  // The lookup and the scan history already existed behind two unlabelled
  // app-bar icons. These are the same screens, reached by labelled controls.

  void _openHistory() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ScanHistoryScreen()));

  void _openAdapterHelp() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AdapterHelpScreen()));

  /// The link under a "nothing answered" state (Phase 4B, B3).
  Widget _adapterHelpLink(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('adapter-help-link'),
          onPressed: _openAdapterHelp,
          icon: const Icon(Icons.help_outline_rounded, size: 16),
          label: Text(context.tr('adapterHelpTitle'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          style: TextButton.styleFrom(foregroundColor: _RC.neonCyan),
        ),
      );

  Widget _toolChip(
          {required String name,
          required IconData icon,
          required String label,
          required VoidCallback onTap}) =>
      OutlinedButton.icon(
        key: ValueKey('tool-$name'),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label,
            maxLines: 1,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _RC.neonCyan,
          side: BorderSide(color: _RC.neonCyan.withValues(alpha: 0.45)),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      );

  List<Widget> _toolChips(BuildContext context) => [
        _toolChip(
            name: 'lookup',
            icon: Icons.manage_search_rounded,
            label: context.tr('lookupTitle'),
            onTap: _openLookup),
        _toolChip(
            name: 'history',
            icon: Icons.history_rounded,
            label: context.tr('historyTitle'),
            onTap: _openHistory),
      ];

  /// One row of labelled controls above the section cards.
  Widget _buildToolsRow(BuildContext context) => Container(
        height: 48,
        decoration: const BoxDecoration(
          color: _RC.surface,
          border: Border(bottom: BorderSide(color: _RC.border)),
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          children: [
            for (final c in _toolChips(context)) ...[c, const SizedBox(width: 8)],
          ],
        ),
      );

  // ── Domain sections (Phase 4B, B1) ────────────────────────────────────────
  // Six cards over the codes the engine and ABS scans already found. Nothing
  // here scans: a card says what a scan established, or that none has.

  _SectionData _sectionData(BuildContext context, ObdService obd) {
    final read = obd.lastEngineRead;
    final vehicle =
        activeVehicleSnapshot(context.watch<VehicleProvider>().active).context;
    final engineCodes =
        read is EngineAnswered ? _sanitize(obd.engineDisplayCodes) : <DtcCode>[];
    FaultSystem? knowledgeSystemOf(DtcCode c) =>
        resolveForCard(context, c, vehicle: vehicle).structure?.system;
    final found = foundCodes(
      engineRead: read,
      engineCodes: engineCodes,
      absOutcome: obd.chassisScanOutcome,
      absCodes: obd.chassisDtcCodes,
      knowledgeSystemOf: knowledgeSystemOf,
    );
    final summaries = summariseSections(
      engineRead: read,
      engineScanning: _reading,
      engineCodes: engineCodes,
      absOutcome: obd.chassisScanOutcome,
      absScanning: obd.chassisScanInFlight,
      absCodes: obd.chassisDtcCodes,
      knowledgeSystemOf: knowledgeSystemOf,
    );
    return (found: found, summaries: summaries);
  }

  String _sectionName(BuildContext context, FaultSection s) => context.tr(switch (s) {
        FaultSection.engine => 'sectionEngine',
        FaultSection.brakes => 'sectionBrakes',
        FaultSection.body => 'sectionBody',
        FaultSection.network => 'sectionNetwork',
        FaultSection.transmission => 'sectionTransmission',
        FaultSection.other => 'sectionOther',
      });

  /// The one short, honest line a card shows. Engine and Brakes & ABS reuse
  /// the wording of their own scan results; the other four only ever say
  /// "not scanned yet", "none found" or "N found".
  String _sectionState(BuildContext context, SectionSummary s) {
    String count() => s.count == 1
        ? context.tr('sectionFaultOne')
        : context.trArgs('sectionFaultsN', {'n': '${s.count}'});
    switch (s.section) {
      case FaultSection.engine:
        return switch (s.status) {
          SectionStatus.notScanned => context.tr('sectionNotScanned'),
          SectionStatus.scanning => context.tr('sectionScanning'),
          SectionStatus.noAnswer => context.tr('dtcNoAnswerTitle'),
          SectionStatus.moduleBusy => context.tr('sectionEngineBusy'),
          SectionStatus.refused => context.tr('dtcRefusedTitle'),
          SectionStatus.linkLost => context.tr('dtcLinkLostTitle'),
          SectionStatus.notReadable => context.tr('sectionNotReadable'),
          SectionStatus.adapterLimited => context.tr('dtcNoAnswerTitle'),
          SectionStatus.noFaults => context.tr('sectionNoFaults'),
          SectionStatus.found => count(),
        };
      case FaultSection.brakes:
        return switch (s.status) {
          SectionStatus.notScanned => context.tr('sectionNotScanned'),
          SectionStatus.scanning => context.tr('sectionScanning'),
          SectionStatus.noAnswer => context.tr('absNoModule'),
          SectionStatus.moduleBusy => context.tr('absModuleBusyTitle'),
          SectionStatus.refused => context.tr('dtcRefusedTitle'),
          SectionStatus.linkLost => context.tr('dtcLinkLostTitle'),
          SectionStatus.notReadable => context.tr('sectionNotReadable'),
          SectionStatus.adapterLimited => context.tr('absAddressingUnsupported'),
          SectionStatus.noFaults => context.tr('sectionNoFaults'),
          SectionStatus.found => count(),
        };
      default:
        return switch (s.status) {
          SectionStatus.found =>
            context.trArgs('sectionFoundN', {'n': '${s.count}'}),
          SectionStatus.noFaults => context.tr('sectionNoneFound'),
          _ => context.tr('sectionNotScannedYet'),
        };
    }
  }

  /// The small caption under a card's state, when it has something to add.
  String? _sectionCaption(BuildContext context, SectionSummary s) {
    switch (s.section) {
      case FaultSection.engine:
        return null;
      case FaultSection.brakes:
        return s.fromEngineScanOnly ? context.tr('sectionFromEngineScan') : null;
      default:
        return context.tr('sectionBasedOn');
    }
  }

  Widget _buildSectionStrip(
      BuildContext context, List<SectionSummary> summaries) {
    return Container(
      height: 112,
      decoration: const BoxDecoration(
        color: _RC.surface,
        border: Border(bottom: BorderSide(color: _RC.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        children: [
          _sectionCard(
            key: const ValueKey('section-card-all'),
            title: context.tr('sectionAll'),
            selected: _section == null,
            width: 76,
            onTap: () => setState(() => _section = null),
          ),
          for (final s in summaries) ...[
            const SizedBox(width: 8),
            _sectionCard(
              key: ValueKey('section-card-${s.section.name}'),
              title: _sectionName(context, s.section),
              state: _sectionState(context, s),
              caption: _sectionCaption(context, s),
              badge: s.status == SectionStatus.found ? s.count : null,
              selected: _section == s.section,
              width: 152,
              onTap: () => setState(
                  () => _section = _section == s.section ? null : s.section),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard({
    required Key key,
    required String title,
    required bool selected,
    required VoidCallback onTap,
    required double width,
    String? state,
    String? caption,
    int? badge,
  }) {
    final accent = selected ? _RC.neonCyan : _RC.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: selected ? _RC.neonCyan.withValues(alpha: 0.10) : _RC.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
                color: selected
                    ? _RC.neonCyan.withValues(alpha: 0.6)
                    : _RC.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: selected ? _RC.neonCyan : _RC.textMain,
                            fontSize: 11.5,
                            height: 1.2,
                            fontWeight: FontWeight.w800)),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: _RC.neonAmber.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('$badge',
                          style: const TextStyle(
                              color: _RC.neonAmber,
                              fontSize: 11,
                              fontWeight: FontWeight.w900)),
                    ),
                  ],
                ],
              ),
              if (state != null) ...[
                const SizedBox(height: 4),
                Text(state,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: accent, fontSize: 10.5, height: 1.25)),
              ],
              if (caption != null) ...[
                const Spacer(),
                Text(caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: _RC.textMuted, fontSize: 9)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The code list for the chosen section: every code the engine and ABS
  /// scans found that belongs to it. Empty says why, in the card's own words.
  Widget _buildSectionList(BuildContext context, ObdService obd,
      _SectionData data) {
    final section = _section!;
    final items = filterBySection(data.found, section);
    final summary = data.summaries.firstWhere((s) => s.section == section);
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        children: [
          _engineNotice(
            icon: Icons.filter_list_rounded,
            color: _RC.textMuted,
            title: _sectionName(context, section),
            body: _sectionState(context, summary),
            detail: _sectionCaption(context, summary),
          ),
        ],
      );
    }
    final vehicle = _activeVehicle;
    final platformKey =
        ChassisPlatforms.resolve(vehicle?.make, vehicle?.model);
    final snapshot = activeVehicleSnapshot(vehicle).context;
    final engineItems = [for (final f in items) if (!f.fromAbs) f]
      ..sort((a, b) => _cardRank(a.code, resolveForCard(context, a.code, vehicle: snapshot))
          .compareTo(_cardRank(b.code, resolveForCard(context, b.code, vehicle: snapshot))));
    final absItems = [for (final f in items) if (f.fromAbs) f];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        for (final f in engineItems)
          _HazardCard(
              key: ValueKey('section-engine-${f.code.code}'),
              code: f.code,
              lowVoltage: obd.batteryVoltageLow,
              showContext: true),
        for (final f in absItems)
          _HazardCard(
              key: ValueKey('section-abs-${f.code.code}'),
              code: f.code,
              platformKey: platformKey,
              lowVoltage: obd.chassisReadWhileLowVoltage),
      ],
    );
  }

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
            Text(context.tr('dtcAdapterNotConnected'),
                style: const TextStyle(
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
            // The lookup and the history need no adapter: offer them here.
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: _toolChips(context),
            ),
          ],
        ),
      );

  Widget _buildConnected(BuildContext context, List<DtcCode> codes,
      ObdService obd, _SectionData sections) {
    final read = obd.lastEngineRead;
    final readAt = obd.dtcCodesReadAt;
    // Every card for the current answer: Mode 03 plus any pending- or
    // permanent-only code the extras found, each with its status.
    final shown = read is EngineAnswered ? _sanitize(obd.engineDisplayCodes) : codes;
    // Rank and count by the rider action the resolver gives each card, so a
    // STOP card is never counted "0 CRITICAL" because the older table did
    // not know the code.
    final vehicle =
        activeVehicleSnapshot(context.watch<VehicleProvider>().active).context;
    final resolved = {
      for (final c in shown) c.code: resolveForCard(context, c, vehicle: vehicle),
    };
    shown.sort((a, b) => _cardRank(a, resolved[a.code]!)
        .compareTo(_cardRank(b, resolved[b.code]!)));
    final criticalCount =
        shown.where((c) => _isCritical(c, resolved[c.code]!)).length;

    return Column(
      children: [
        _buildSummaryBar(context, shown, criticalCount,
            current: read is EngineAnswered,
            readAt: readAt,
            lampOn: obd.engineReport?.lampOn ?? false),
        // Clear Codes keys on the Mode 03 list, exactly as before.
        _buildActionBar(context, codes),
        if (obd.batteryVoltageLow) _batteryBanner(context, obd),
        if (obd.batteryVoltageHigh) _batteryBanner(context, obd, high: true),
        Expanded(
          child: RefreshIndicator(
            color: _RC.neonCyan,
            backgroundColor: _RC.card,
            onRefresh: () => _readCodes(manual: true),
            child: _section != null
                ? _buildSectionList(context, obd, sections)
                : _buildEngineResults(context, read, shown, readAt, obd),
          ),
        ),
      ],
    );
  }

  /// "Battery voltage is low (11.4 V)…" — or, with [high], "…is high
  /// (15.6 V)…" — shown above the results; it never blocks a scan.
  Widget _batteryBanner(BuildContext context, ObdService obd, {bool high = false}) {
    final v = obd.latestVoltage?.volts;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _RC.neonAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _RC.neonAmber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.battery_alert_rounded, size: 18, color: _RC.neonAmber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.trArgs(high ? 'batteryHighBanner' : 'batteryLowBanner',
                  {'v': v == null ? '—' : v.toStringAsFixed(1)}),
              style: const TextStyle(
                  color: _RC.textMain, fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  /// The engine list area, decided by what the last read established.
  ///
  /// "No Fault Codes Found" is reachable from exactly one branch: the engine
  /// computer gave a positive answer with no codes in it. Every other outcome
  /// says what actually happened, and any list from an earlier answered read
  /// is shown greyed out under its read time — never as current.
  Widget _buildEngineResults(BuildContext context, EngineDtcRead? read,
      List<DtcCode> codes, DateTime? readAt, ObdService obd) {
    if (read == null) return _buildEmptyState(context, answered: false);
    final lowVoltage = obd.batteryVoltageLow;
    if (read is EngineAnswered) {
      if (codes.isEmpty) return _buildEmptyState(context, answered: true);
      final mismatch = obd.engineCountMismatch;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        children: [
          if (mismatch != null) ...[
            Text(
              context.trArgs('dtcCountMismatch', {
                'reported': '${mismatch.reported}',
                'received': '${mismatch.received}',
              }),
              style: const TextStyle(
                  color: _RC.neonAmber, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 10),
          ],
          for (final c in codes)
            _HazardCard(
                key: ValueKey('card-${c.code}'),
                code: c,
                lowVoltage: lowVoltage,
                showContext: true),
        ],
      );
    }

    final Widget notice;
    switch (read) {
      case EngineNoAnswer(:final reason):
        final busy = reason == EngineNoAnswerReason.moduleBusy;
        notice = _engineNotice(
          icon: Icons.portable_wifi_off_rounded,
          color: _RC.neonAmber,
          title: context.tr('dtcNoAnswerTitle'),
          body: context.tr(busy ? 'dtcModuleBusyBody' : 'dtcNoAnswerBody'),
          detail: busy ? null : context.tr('dtcNoAnswerChecklist'),
          action: engineReadOffersAdapterHelp(read)
              ? _adapterHelpLink(context)
              : null,
        );
        break;
      case EngineRefused():
        // "Stop the engine" only when the engine is KNOWN to be running.
        final running =
            obd.engineReport?.engineState == EngineState.running;
        notice = _engineNotice(
          icon: Icons.block_rounded,
          color: _RC.neonAmber,
          title: context.tr('dtcRefusedTitle'),
          body: context.tr('dtcRefusedBody'),
          detail: running ? context.tr('dtcRefusedEngineRunning') : null,
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
    Widget? action,
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
            if (action != null) ...[
              const SizedBox(height: 6),
              action,
            ],
          ],
        ),
      );

  Widget _buildSummaryBar(BuildContext context, List<DtcCode> codes,
      int criticalCount,
      {required bool current, required DateTime? readAt, bool lampOn = false}) {
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
              label: context.tr('dtcCodesChip'),
              value: current ? '${codes.length}' : '—',
              color: !current
                  ? _RC.textMuted
                  : (codes.isEmpty ? _RC.neonGreen : _RC.neonAmber)),
          const SizedBox(width: 10),
          _statChip(
              label: context.tr('dtcCriticalChip'),
              value: current ? '$criticalCount' : '—',
              color: current && criticalCount > 0 ? _RC.neonRed : _RC.textMuted),
          // PID 01 01 says the engine computer has the warning lamp on. Shown
          // only when known ON; unknown shows nothing.
          if (current && lampOn) ...[
            const SizedBox(width: 10),
            Flexible(child: _statusChip(context.tr('dtcEngineLampOn'), _RC.neonAmber)),
          ],
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
                  '${context.tr('dtcLiveScan')} · ${_timeAgo(context, readAt)}',
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

  Widget _statusChip(String text, Color color) => _StatusLabel(text, color);

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
              onPressed: _reading ? null : () => _readCodes(manual: true),
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
                ready ? context.tr('noFaultCodes') : context.tr('dtcScanningTitle'),
                style: const TextStyle(
                    color: _RC.textMain, fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  ready
                      ? context.tr('noFaultCodesDesc')
                      : context.tr('dtcScanningBody'),
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
  Widget _buildChassis(
      BuildContext context, ObdService obd, _SectionData sections) {
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
        if (obd.batteryVoltageLow) _batteryBanner(context, obd),
        if (obd.batteryVoltageHigh) _batteryBanner(context, obd, high: true),
        Expanded(
          child: RefreshIndicator(
            color: _RC.neonCyan,
            backgroundColor: _RC.card,
            onRefresh: _scanChassis,
            child: _section != null
                ? _buildSectionList(context, obd, sections)
                : codes.isEmpty
                ? _buildChassisEmptyState(context, obd)
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                    itemCount: codes.length,
                    itemBuilder: (_, i) => _HazardCard(
                      code: codes[i],
                      platformKey: platformKey,
                      lowVoltage: obd.chassisReadWhileLowVoltage,
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
              label: context.tr('dtcCodesChip'),
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
      case ChassisScanOutcome.moduleBusy:
        // The module is there and alive; it never sent its codes. Never
        // "no module", never "no faults".
        icon = Icons.hourglass_top_rounded;
        color = _RC.neonAmber;
        title = context.tr('absModuleBusyTitle');
        body = context.tr('absModuleBusyDesc');
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
        if (absOutcomeOffersAdapterHelp(obd.chassisScanOutcome)) ...[
          const SizedBox(height: 10),
          Center(child: _adapterHelpLink(context)),
        ],
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

  /// The battery was LOW when this code was read: a network (U) code is
  /// marked as possibly false.
  final bool lowVoltage;

  /// Engine cards of the CURRENT answered read only: a "Show details" button
  /// that reads the snapshot and counters on demand. Never on the greyed
  /// earlier list or an ABS card.
  final bool showContext;

  const _HazardCard(
      {super.key,
      required this.code,
      this.platformKey,
      this.lowVoltage = false,
      this.showContext = false});

  /// Small status labels, only for what is KNOWN to be true — an unknown
  /// flag shows nothing, never "No".
  ///
  /// Engine (OBD) cards: Stored (Mode 03), Pending (Mode 07), Permanent
  /// (Mode 0A), plus Active / Lamp when a UDS status byte says so. ABS cards:
  /// Active, Pending, History and Lamp from the module's status byte; "not
  /// confirmed" keeps its existing chip.
  List<String> _statusLabels(BuildContext context) {
    final out = <String>[];
    if (code.isChassis) {
      final byte = code.statusByte;
      if (byte == null) return out;
      final s = UdsStatusByte(byte);
      if (s.isActive) out.add(context.tr('faultStatusActive'));
      if (s.isPending) out.add(context.tr('faultStatusPending'));
      if (s.isHistory) out.add(context.tr('faultStatusHistory'));
      if (s.isLampRequested) out.add(context.tr('faultStatusLamp'));
      return out;
    }
    final status = code.record?.status;
    if (status == null) return out;
    if (status.active == true) out.add(context.tr('faultStatusActive'));
    if (status.confirmed == true) out.add(context.tr('faultStatusStored'));
    if (status.pending == true) out.add(context.tr('faultStatusPending'));
    if (status.permanent == true) out.add(context.tr('faultStatusPermanent'));
    if (status.lampRequested == true) out.add(context.tr('faultStatusLamp'));
    return out;
  }

  bool get _mayBeFalse => lowVoltage && code.code.startsWith('U');

  /// What the resolver says about this code for the active vehicle. Chassis
  /// cards keep the platform their list was scanned under.
  ResolvedFault _resolved(BuildContext context) {
    final snap = activeVehicleSnapshot(context.watch<VehicleProvider>().active);
    final v = snap.context;
    final vehicle = code.isChassis
        ? VehicleContext(
            profileId: v.profileId,
            make: v.make,
            model: v.model,
            manufacturerKey: v.manufacturerKey,
            platformKey: platformKey)
        : v;
    return resolveForCard(context, code, vehicle: vehicle);
  }

  /// True while the knowledge store is still loading at app start: the card
  /// says so instead of briefly showing a structure-only answer.
  bool _knowledgeLoading(BuildContext context) =>
      Provider.of<KnowledgeService?>(context)?.state == KnowledgeState.loading;

  /// The store may still change this answer: anything from L4 down (generic,
  /// older table, structure, raw) waits for it, so the rider never sees one
  /// text flip to another a moment later. Manual-table answers do not wait.
  bool _awaitingKnowledge(BuildContext context, ResolvedFault r) =>
      _knowledgeLoading(context) &&
      r.level.index >= ResolvedLevel.l4Generic.index;

  /// Card colour: the rider action when the resolver knows one, else the
  /// older severity band.
  Color _cardColor(ResolvedFault r) =>
      r.riderAction != null ? riderActionColor(r.riderAction!) : _severityColor;

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
  /// The card's main line, from the resolver (fault Phase 1B). Every wording
  /// for "no meaning" is the one these cards already used.
  String _localizedDescription(BuildContext context, ResolvedFault r) {
    if (_awaitingKnowledge(context, r)) {
      return context.tr('knowledgeLoading');
    }
    final title = r.title ?? '';
    if (title.isNotEmpty) return title;

    // Chassis codes resolve through the manufacturer-keyed dictionary: the
    // same C-code means different faults on different makes. Two different
    // sentences for "nothing", because they are two different facts: "this
    // make's codes are read but undecoded" says the value on screen is real
    // and worth quoting to a dealer; "no manufacturer description available"
    // applies when there is no table for this platform at all.
    if (code.isChassis) {
      if (_platform?.showsRawUnverifiedCodes ?? false) {
        return context.tr('absRawUnverifiedDesc');
      }
      return context.tr('absNoDictionary');
    }

    // A manufacturer-defined code (P1xxx, U1xxx…) means whatever this bike's
    // maker says it means. The resolver never gives it a generic meaning.
    if (isManufacturerDefined(code.code)) {
      return context.tr('dtcManufacturerSpecific');
    }
    if (r.level == ResolvedLevel.l6Raw) return context.tr('faultRawShowDealer');
    return context.tr('dtcNoVerifiedDescription');
  }

  /// Subsystem label for an engine code shown by its structure (no verified
  /// description). Null when a description exists or the range has no
  /// grouping the app is confident of.
  String? _structuralSubsystem(BuildContext context, ResolvedFault r) {
    if (code.isChassis || r.level != ResolvedLevel.l5Structure) return null;
    if (_awaitingKnowledge(context, r)) return null;
    final key = r.structure?.subsystemKey;
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
    final r = _resolved(context);
    final color = _cardColor(r);
    // The store's guidance replaces the older table's rows; the older rows
    // (cause, action, severity note) stay exactly as they were for an answer
    // that still comes from the older table.
    final waiting = _awaitingKnowledge(context, r);
    final storeGuidance = !waiting && r.provenance == Provenance.aiGuidance;
    final legacyAnswer = !waiting &&
        (r.provenance == Provenance.legacyTable ||
            r.provenance == Provenance.legacyImported);
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
                              content: Text(
                                  context.trArgs('codeCopied', {'code': code.code}),
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
                        // Rider action (icon + word) when the resolver knows
                        // one; the older severity label otherwise.
                        if (r.riderAction != null)
                          RiderActionChip(r.riderAction!)
                        else
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
                    Builder(builder: (context) {
                      final labels = _statusLabels(context);
                      if (labels.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final l in labels) _StatusLabel(l, _RC.neonCyan),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    Text(_localizedDescription(context, r),
                        style: const TextStyle(
                            color: _RC.textMain,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3)),
                    if (_mayBeFalse) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.battery_alert_rounded,
                              size: 14, color: _RC.neonAmber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(context.tr('mayBeFalseLowVoltage'),
                                style: const TextStyle(
                                    color: _RC.neonAmber,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.35)),
                          ),
                        ],
                      ),
                    ],
                    // The ISO 14229 failure type byte, in plain words, when
                    // the module sent one other than "no sub-type".
                    if (code.isChassis &&
                        code.failureTypeByte != null &&
                        code.failureTypeByte != 0)
                      Builder(builder: (context) {
                        final lang = context
                            .watch<SettingsProvider>()
                            .locale
                            .languageCode;
                        final ftb = code.failureTypeByte!;
                        return _detailRow(
                            context.tr('faultFailureType'),
                            '${FailureType.hex(ftb)} · '
                                '${FailureType.describe(ftb, lang)}',
                            _RC.textMain);
                      }),

                    // Engine codes: structure when there is no verified text,
                    // and the cause and advice the 31-entry table carries.
                    // Rows are only built when they have content.
                    if (!code.isChassis) ...[
                      Builder(builder: (context) {
                        final subsystem = _structuralSubsystem(context, r);
                        return subsystem == null
                            ? const SizedBox.shrink()
                            : _detailRow(context.tr('dtcSubsystem'), subsystem,
                                _RC.textMain);
                      }),
                      if (legacyAnswer && code.possibleCause.isNotEmpty)
                        _detailRow(context.tr('possibleCause'),
                            code.possibleCause, _RC.textMuted),
                      if (legacyAnswer && code.action.isNotEmpty)
                        _detailRow(context.tr('recommendedAction'), code.action,
                            _RC.neonCyan),
                      if (legacyAnswer && code.severity != 'unknown') ...[
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
                    // Fault Phase 1B: the knowledge store's guidance (likely
                    // causes, what to do, can-ride line, conditions) for an
                    // answer from the store, on any card; otherwise the
                    // language note and the plain provenance line alone.
                    if (storeGuidance)
                      ResolvedGuidance(r)
                    else if (!_awaitingKnowledge(context, r))
                      ProvenanceLine(r),
                    // Phase A-4: the snapshot and counters, on demand.
                    if (showContext && !code.isChassis)
                      _CardDetails(code: code.code),
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

/// One small status label (Stored, Pending, Permanent, Active, History, Lamp
/// on, Warning lamp ON).
class _StatusLabel extends StatelessWidget {
  const _StatusLabel(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3)),
      );
}

// ── "Show details" on a fault card (fault Phase A-4) ─────────────────────────
// Collapsed by default: nothing is read until the rider taps it. The read is
// the service's one bounded, cancelable context read; the card only shows what
// it established, and only while that is current (this connection, after the
// last Clear Codes, recent).
class _CardDetails extends StatefulWidget {
  const _CardDetails({required this.code});
  final String code;

  @override
  State<_CardDetails> createState() => _CardDetailsState();
}

class _CardDetailsState extends State<_CardDetails> {
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) unawaited(context.read<ObdService>().readEngineContext());
  }

  void _retry() =>
      unawaited(context.read<ObdService>().readEngineContext(force: true));

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();
    final snapshot = obd.freezeFrameResult;
    final counters = obd.contextCounters;
    final inFlight = obd.contextReadInFlight;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            key: const ValueKey('contextToggle'),
            onPressed: _toggle,
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                alignment: Alignment.centerLeft,
                foregroundColor: _RC.neonCyan),
            icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 18),
            label: Text(context.tr(_open ? 'hideDetails' : 'showDetails'),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
          if (_open) ...[
            const SizedBox(height: 6),
            if (inFlight)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _RC.neonCyan)),
              ),
            if (snapshot != null)
              ContextSnapshotView(result: snapshot, cardCode: widget.code),
            if (counters != null) ...[
              const SizedBox(height: 10),
              ContextCountersView(counters: counters, lampOn: obd.contextLampOn),
            ],
            if (!inFlight &&
                (snapshot == null ||
                    contextNeedsRetry(
                        snapshot: snapshot,
                        counters: counters,
                        readiness: obd.readinessRead)))
              TextButton(
                key: const ValueKey('contextRetry'),
                onPressed: _retry,
                child: Text(context.tr('retry'),
                    style: const TextStyle(
                        color: _RC.neonCyan, fontWeight: FontWeight.w800)),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Freeze Frame Bottom Sheet ────────────────────────────────────────────────
// The snapshot recorded when the last fault was set, the lamp and clear-codes
// counters, and the emission self-checks. One bounded, cancelable read that
// starts when the sheet opens (the rider asked for it) and stops when it is
// closed. Nothing here ever shows a silence as "no data".
class _FreezeFrameSheet extends StatefulWidget {
  const _FreezeFrameSheet();

  @override
  State<_FreezeFrameSheet> createState() => _FreezeFrameSheetState();
}

class _FreezeFrameSheetState extends State<_FreezeFrameSheet> {
  ObdService? _obd;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _obd = context.read<ObdService>();
    // After the first frame: the read tells its listeners at once, which is
    // not allowed while the sheet is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed) return;
      unawaited(_obd!.readEngineContext(isCancelled: () => _closed));
    });
  }

  @override
  void dispose() {
    _closed = true;
    _obd?.cancelContextRead();
    super.dispose();
  }

  void _retry() => unawaited(
      _obd!.readEngineContext(force: true, isCancelled: () => _closed));

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();
    final snapshot = obd.freezeFrameResult;
    final counters = obd.contextCounters;
    final readiness = obd.readinessRead;
    final inFlight = obd.contextReadInFlight;
    final nothingYet = snapshot == null && counters == null && readiness == null;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
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
              if (inFlight)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: nothingYet ? 30 : 8),
                  child: const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _RC.neonCyan),
                  ),
                ),
              if (snapshot != null) ContextSnapshotView(result: snapshot),
              if (counters != null) ...[
                const SizedBox(height: 12),
                ContextCountersView(counters: counters, lampOn: obd.contextLampOn),
              ],
              if (readiness != null) ...[
                const SizedBox(height: 14),
                ReadinessView(read: readiness),
              ],
              if (!inFlight &&
                  (nothingYet ||
                      contextNeedsRetry(
                          snapshot: snapshot,
                          counters: counters,
                          readiness: readiness)))
                Center(
                  child: TextButton(
                    key: const ValueKey('contextRetry'),
                    onPressed: _retry,
                    child: Text(context.tr('retry'),
                        style: const TextStyle(
                            color: _RC.neonCyan, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

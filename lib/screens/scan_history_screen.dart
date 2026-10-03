/// Danlite ELM — scan history: what each saved read established, on this
/// phone only. Delete all, and Share as text (built only on the rider's tap).
/// Thin: storage is `scan_history.dart`, meanings are the resolver's.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../knowledge/fault_resolver.dart';
import '../knowledge/history_report.dart';
import '../knowledge/knowledge_service.dart';
import '../knowledge/scan_history.dart';
import '../providers/settings_provider.dart';
import '../providers/vehicle_provider.dart';
import '../widgets/resolved_fault_view.dart';
import 'code_lookup_screen.dart' show describeResolved;
import '../knowledge/history_recorder.dart' show activeVehicleSnapshot;

class _C {
  static const Color bg = Color(0xFF07090E);
  static const Color surface = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color textMain = Color(0xFFEEF2F8);
  static const Color textMuted = Color(0xFF607080);
  static const Color cyan = Color(0xFF00CAFF);
  static const Color red = Color(0xFFFF3D3D);
}

/// The existing share channel (opens the system share sheet only).
@visibleForTesting
MethodChannel historyShareChannel = const MethodChannel('com.danlite.elm/session_recorder');

class ScanHistoryScreen extends StatefulWidget {
  const ScanHistoryScreen({super.key});

  @override
  State<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends State<ScanHistoryScreen> {
  Future<List<ScanSession>>? _sessions;

  KnowledgeService? get _k => Provider.of<KnowledgeService?>(context, listen: false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sessions ??= _load();
  }

  Future<List<ScanSession>> _load() async {
    final k = _k;
    if (k == null) return const <ScanSession>[];
    await k.start();
    // The internal Clear Codes record is listed too (a time-only row; its
    // sentences are in the detail). It is still left out of Share.
    return await k.history?.list(includeInternal: true) ?? const <ScanSession>[];
  }

  void _refresh() => setState(() => _sessions = _load());

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.card,
        title: Text(context.tr('historyDeleteAll'),
            style: const TextStyle(color: _C.textMain, fontWeight: FontWeight.w800)),
        content: Text(context.tr('historyDeleteConfirm'),
            style: const TextStyle(color: _C.textMuted, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('cancel'), style: const TextStyle(color: _C.textMuted))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _C.red, foregroundColor: Colors.white),
              child: Text(context.tr('historyDelete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _k?.history?.deleteAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.tr('historyDeleted'))));
    _refresh();
  }

  Future<void> _share(List<ScanSession> sessions) async {
    final text = buildHistoryReport(
      sessions,
      tr: (k) => AppStrings.get(k, context.read<SettingsProvider>().locale.languageCode),
      meaning: (f, kind) => describeResolved(context, _resolveRow(context, f, kind)),
    );
    try {
      await historyShareChannel.invokeMethod<void>(
          'shareText', <String, String>{'text': text, 'subject': context.tr('historyTitle')});
    } catch (e) {
      debugPrint('[history] share unavailable (${e.runtimeType})');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ScanSession>>(
      future: _sessions,
      builder: (context, snap) {
        final sessions = snap.data ?? const <ScanSession>[];
        final shareable = sessions.any((s) => s.kind != SessionKind.clearCheck);
        return Scaffold(
          backgroundColor: _C.bg,
          appBar: AppBar(
            backgroundColor: _C.surface,
            iconTheme: const IconThemeData(color: _C.textMain),
            title: Text(context.tr('historyTitle'),
                style: const TextStyle(color: _C.textMain, fontWeight: FontWeight.w800)),
            actions: [
              IconButton(
                tooltip: context.tr('historyShare'),
                onPressed: shareable ? () => _share(sessions) : null,
                icon: const Icon(Icons.ios_share_rounded, color: _C.cyan),
              ),
              IconButton(
                tooltip: context.tr('historyDeleteAll'),
                onPressed: sessions.isEmpty ? null : _deleteAll,
                icon: const Icon(Icons.delete_forever_rounded, color: _C.red),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              Text(context.tr('historyPrivacy'),
                  style: const TextStyle(color: _C.textMuted, fontSize: 12, height: 1.45)),
              const SizedBox(height: 12),
              if (snap.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _C.cyan))
              else if (sessions.isEmpty)
                Text(context.tr('historyEmpty'),
                    style: const TextStyle(color: _C.textMain, fontSize: 14, height: 1.5))
              else
                for (final s in sessions) _SessionTile(s),
            ],
          ),
        );
      },
    );
  }
}

/// Re-resolve a saved code in today's language for today's vehicle profile.
ResolvedFault _resolveRow(BuildContext context, ScanFaultRow f, SessionKind kind) {
  final lang = context.read<SettingsProvider>().locale.languageCode;
  final vehicle = activeVehicleSnapshot(context.read<VehicleProvider>().active).context;
  final domain = kind == SessionKind.abs ? FaultDomain.abs : FaultDomain.engine;
  final k = Provider.of<KnowledgeService?>(context, listen: false);
  return k?.resolve(f.toRecord(), vehicle, lang, domain: domain) ??
      FaultResolver(index: KnowledgeIndex.empty).resolve(f.toRecord(), vehicle, lang, domain: domain);
}

/// The Clear Codes record's row: what it is and when. Its outcome is in the
/// detail only.
class _ClearRecordTile extends StatelessWidget {
  const _ClearRecordTile(this.s);
  final ScanSession s;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => _SessionDetail(s))),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _C.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.delete_sweep_rounded, size: 15, color: _C.cyan),
              const SizedBox(width: 6),
              Text(context.tr('clearCodes'),
                  style: const TextStyle(
                      color: _C.cyan, fontSize: 12, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(formatLocal(clearAttemptedAt(s)),
                  style: const TextStyle(color: _C.textMuted, fontSize: 11)),
            ],
          ),
        ),
      );
}

/// "Clear attempted at …. After clearing: …" — neutral wording: what the bike
/// reported afterwards, never a verdict on whether the clear "worked".
String clearRecordSentence(ScanSession s, String Function(String key) tr) {
  final attempt =
      tr('historyClearAttempt').replaceAll('{time}', formatLocal(clearAttemptedAt(s)));
  final after = switch (s.clearOutcome) {
    ClearCheckOutcome.codesReturned =>
      tr('historyClearAfterCodes').replaceAll('{n}', '${s.faults.length}'),
    ClearCheckOutcome.clearedVerified => tr('historyClearAfterNone'),
    ClearCheckOutcome.couldNotVerify || null => tr('historyClearAfterUnknown'),
  };
  return '$attempt $after';
}

class _SessionTile extends StatelessWidget {
  const _SessionTile(this.s);
  final ScanSession s;

  @override
  Widget build(BuildContext context) {
    if (s.kind == SessionKind.clearCheck) return _ClearRecordTile(s);
    final facts = [
      if (s.engineState == 'running') context.tr('historyEngineRunning'),
      if (s.engineState == 'off') context.tr('historyEngineOff'),
      if (s.lampState == 'on') context.tr('dtcEngineLampOn'),
      if (s.voltageBand == 'low') context.tr('historyVoltageLow'),
      if (s.voltageBand == 'high') context.tr('historyVoltageHigh'),
      if (s.repeatCount > 1) context.trArgs('historyRepeat', {'n': '${s.repeatCount}'}),
    ];
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _SessionDetail(s))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(s.kind == SessionKind.abs ? Icons.disc_full_rounded : Icons.settings_rounded,
                    size: 15, color: _C.cyan),
                const SizedBox(width: 6),
                Text(context.tr(s.kind == SessionKind.abs ? 'moduleAbs' : 'moduleEngine'),
                    style: const TextStyle(color: _C.cyan, fontSize: 12, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(formatLocal(s.startedAt),
                    style: const TextStyle(color: _C.textMuted, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 6),
            Text(context.tr('historyReach_${s.reachState}'),
                style: const TextStyle(color: _C.textMain, fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              s.faults.isEmpty
                  ? context.tr('historyNoCodes')
                  : '${context.trArgs('historyCodeCount', {'n': '${s.faults.length}'})}: '
                      '${s.faults.map((f) => f.displayCode).join(', ')}',
              style: const TextStyle(color: _C.textMuted, fontSize: 12),
            ),
            if ((s.vehicleLabel ?? '').trim().isNotEmpty || facts.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                  [
                    if ((s.vehicleLabel ?? '').trim().isNotEmpty) s.vehicleLabel!.trim(),
                    ...facts,
                  ].join(' · '),
                  style: const TextStyle(color: _C.textMuted, fontSize: 11.5)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SessionDetail extends StatelessWidget {
  const _SessionDetail(this.s);
  final ScanSession s;

  @override
  Widget build(BuildContext context) {
    final isClearRecord = s.kind == SessionKind.clearCheck;
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.surface,
        iconTheme: const IconThemeData(color: _C.textMain),
        title: Text(formatLocal(isClearRecord ? clearAttemptedAt(s) : s.startedAt),
            style: const TextStyle(color: _C.textMain, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Text(
              isClearRecord
                  ? clearRecordSentence(s, context.tr)
                  : context.tr('historyReach_${s.reachState}'),
              style: const TextStyle(color: _C.textMain, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (s.faults.isEmpty && !isClearRecord)
            Text(context.tr('historyNoCodes'), style: const TextStyle(color: _C.textMuted)),
          for (final f in s.faults)
            Builder(builder: (context) {
              final r = _resolveRow(context, f, s.kind);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _C.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _C.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(f.displayCode,
                          style: const TextStyle(
                              color: _C.textMain, fontFamily: 'monospace',
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(width: 8),
                      if (r.riderAction != null) FaultActionChip(r),
                    ]),
                    const SizedBox(height: 6),
                    Text(describeResolved(context, r),
                        style: const TextStyle(color: _C.textMain, fontSize: 13, height: 1.35)),
                    ProvenanceLine(r),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

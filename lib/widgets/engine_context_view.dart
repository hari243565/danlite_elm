/// Danlite ELM — how the on-demand context is shown: the snapshot recorded when
/// the fault was set, the lamp and clear-codes counters, and the emission
/// self-checks. Shared by the fault card's "Show details" and the Freeze Frame
/// screen so both say exactly the same thing.
///
/// Thin: every decision (what is known, unsupported, unanswered) was made by
/// the typed results in `engine_context.dart`; this only lays them out. The
/// rules it keeps:
///  * an item the bike does not have is not drawn;
///  * a silence, a refusal or an unreadable reply gets its own sentence — it is
///    never drawn as "none" or as an empty list;
///  * every group carries its "Read at {time}".
library;

import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../services/engine_context.dart';
import '../services/engine_report.dart';
import 'resolved_fault_view.dart' show FaultPalette;

const Color _surface = Color(0xFF0D1117);
const Color _border = Color(0xFF1C2A3A);

/// Does any of what is on screen call for a Retry button? True for a silence,
/// a refusal, or a partial read — never for "no snapshot", "unsupported" or
/// "link lost" (a retry would not change those).
bool contextNeedsRetry({
  FreezeFrameResult? snapshot,
  ContextCounters? counters,
  ReadinessRead? readiness,
}) {
  final s = snapshot;
  if (s is FreezeFrameNoAnswer || s is FreezeFrameRefused) return true;
  if (s is FreezeFrameAnswered && s.snapshot.incomplete) return true;
  if (counters?.anyUnanswered ?? false) return true;
  if (readiness?.result is ExtraNoAnswer<ReadinessReport>) return true;
  return false;
}

String _clock(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

Widget _readAt(BuildContext context, DateTime t) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(context.trArgs('dtcReadAt', {'time': _clock(t)}),
          style: const TextStyle(
              color: FaultPalette.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
    );

Widget _sentence(BuildContext context, String key,
        {Color color = FaultPalette.textMain}) =>
    Text(context.tr(key),
        style: TextStyle(color: color, fontSize: 13, height: 1.4));

TextStyle get _heading => const TextStyle(
    color: FaultPalette.textMain, fontSize: 13.5, fontWeight: FontWeight.w800);

Widget _row(String label, String value, Color color) => Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: FaultPalette.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );

String _fuelStatus(BuildContext context, FuelStatusKind k) =>
    context.tr(k.labelKey);

String _valueText(BuildContext context, SnapshotValue v) {
  switch (v) {
    case SnapshotNumber():
      final n = v.value.toStringAsFixed(v.decimals);
      return v.unit.isEmpty ? n : '$n ${v.unit}';
    case SnapshotFuelSystem():
      return v.system2 == FuelStatusKind.none
          ? _fuelStatus(context, v.system1)
          : '${_fuelStatus(context, v.system1)} / ${_fuelStatus(context, v.system2)}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// The snapshot
// ═══════════════════════════════════════════════════════════════════════════

class ContextSnapshotView extends StatelessWidget {
  const ContextSnapshotView({super.key, required this.result, this.cardCode});

  final FreezeFrameResult result;

  /// The code of the card this is shown on, so a snapshot that belongs to a
  /// DIFFERENT code says so. Null on the Freeze Frame screen.
  final String? cardCode;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final body = <Widget>[];
    switch (r) {
      case FreezeFrameAnswered(:final snapshot):
        body.add(_row(context.tr('triggerCode'), snapshot.triggerCode,
            FaultPalette.red));
        if (cardCode != null && cardCode != snapshot.triggerCode) {
          body.add(Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
                context.trArgs('snapshotOtherFault', {'code': snapshot.triggerCode}),
                style: const TextStyle(
                    color: FaultPalette.amber, fontSize: 12, height: 1.35)),
          ));
        }
        for (final v in snapshot.values) {
          if (v is SnapshotFuelSystem && !v.reportsAnything) continue;
          body.add(_row(context.tr(v.pid.labelKey), _valueText(context, v),
              FaultPalette.cyan));
        }
        if (snapshot.incomplete) {
          body.add(_sentence(context, 'ctxPartial', color: FaultPalette.amber));
        }
        body.add(_readAt(context, snapshot.readAt));
      case FreezeFrameNoSnapshot():
        body.add(_sentence(context, 'snapshotNone'));
        body.add(_readAt(context, r.at));
      case FreezeFrameUnsupported():
        body.add(_sentence(context, 'snapshotUnsupported'));
      case FreezeFrameNoAnswer():
        body.add(_sentence(context, 'snapshotNoAnswer', color: FaultPalette.amber));
        body.add(_readAt(context, r.at));
      case FreezeFrameRefused():
        body.add(_sentence(context, 'snapshotRefused', color: FaultPalette.amber));
        body.add(_readAt(context, r.at));
      case FreezeFrameLinkLost():
        body.add(_sentence(context, 'dtcLinkLostTitle', color: FaultPalette.red));
      case FreezeFrameGated():
        body.add(_sentence(context, 'dtcKLineGated'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('snapshotTitle'), style: _heading),
        const SizedBox(height: 6),
        ...body,
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// The counters
// ═══════════════════════════════════════════════════════════════════════════

class ContextCountersView extends StatelessWidget {
  const ContextCountersView({super.key, required this.counters, required this.lampOn});

  final ContextCounters counters;

  /// From the same read's PID 01 01: null when unknown.
  final bool? lampOn;

  String _n(BuildContext context, CounterValue v) {
    final f = formatCount(v.value);
    return v.atLeast ? context.trArgs('ctxAtLeast', {'n': f}) : f;
  }

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];

    void add(ContextCounter c, String key, {bool lamp = false}) {
      final r = counters.of(c);
      if (r is! ExtraValue<CounterValue>) return; // unsupported: not drawn
      final v = r.value;
      if (lamp && !lampCounterIsShown(v, lampOn: lampOn)) return;
      lines.add(context.trArgs(key, {'n': _n(context, v)}));
    }

    add(ContextCounter.lampDistance, 'ctxLampKm', lamp: true);
    add(ContextCounter.lampTime, 'ctxLampMin', lamp: true);
    add(ContextCounter.clearedDistance, 'ctxClearedKm');
    add(ContextCounter.clearedTime, 'ctxClearedMin');
    add(ContextCounter.warmUps, 'ctxWarmUps');

    if (lines.isEmpty && !counters.anyUnanswered) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(l,
                style: const TextStyle(
                    color: FaultPalette.textMain,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35)),
          ),
        if (counters.anyUnanswered)
          _sentence(context, 'ctxPartial', color: FaultPalette.amber),
        _readAt(context, counters.at),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// The emission self-checks
// ═══════════════════════════════════════════════════════════════════════════

class ReadinessView extends StatelessWidget {
  const ReadinessView({super.key, required this.read});

  final ReadinessRead read;

  @override
  Widget build(BuildContext context) {
    final r = read.result;
    final body = <Widget>[];
    switch (r) {
      case ExtraValue<ReadinessReport>(:final value):
        for (final m in Monitor.values) {
          body.add(_monitorRow(context, m, value.states[m]!));
        }
        body.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(context.tr('readinessHint'),
              style: const TextStyle(
                  color: FaultPalette.textMuted, fontSize: 12, height: 1.4)),
        ));
        body.add(_readAt(context, read.at));
      case ExtraUnsupported<ReadinessReport>():
        body.add(_sentence(context, 'readinessUnavailable'));
      case ExtraNoAnswer<ReadinessReport>():
        body.add(_sentence(context, 'ctxPartial', color: FaultPalette.amber));
        body.add(_readAt(context, read.at));
      case ExtraSkipped<ReadinessReport>():
      case ExtraCancelled<ReadinessReport>():
        return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('readinessTitle'), style: _heading),
        const SizedBox(height: 6),
        ...body,
      ],
    );
  }

  Widget _monitorRow(BuildContext context, Monitor m, MonitorState s) {
    final (icon, color, key) = switch (s) {
      MonitorState.complete =>
        (Icons.check_circle_rounded, const Color(0xFF00E39C), 'readinessComplete'),
      MonitorState.notComplete =>
        (Icons.schedule_rounded, FaultPalette.amber, 'readinessNotComplete'),
      MonitorState.notSupported =>
        (Icons.remove_circle_outline_rounded, FaultPalette.textMuted, 'readinessNotSupported'),
      MonitorState.notApplicable =>
        (Icons.remove_circle_outline_rounded, FaultPalette.textMuted, 'readinessNotApplicable'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(context.tr(m.labelKey),
                style: const TextStyle(
                    color: FaultPalette.textMain,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          // Icon AND word: the state is never carried by colour alone.
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(context.tr(key),
                textAlign: TextAlign.end,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

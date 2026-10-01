/// Danlite ELM — everything an engine read establishes beyond the Mode 03
/// core: pending and permanent codes, lamp state and stored-code count, engine
/// state, battery voltage, and vehicle information.
///
/// The Mode 03 read is the core and is shown on its own the moment it
/// finishes ([EngineDtcRead]). Everything here is an optional extra: read
/// afterwards, each one independently bounded, and a slow, failing or
/// unsupported extra never delays, breaks or blanks the core result.
///
/// Pure Dart: no Flutter imports.
library;

import '../models/fault_record.dart';
import 'fault_decoders.dart';
import 'response_pending.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Named constants
// ═══════════════════════════════════════════════════════════════════════════

/// Worst-case wall-clock time for one engine read, core plus every extra,
/// measured from the moment the read has the adapter to itself. Extras that
/// would not fit are skipped (and say so), never left running past this.
///
/// Not included: an adapter RECOVERY after the core request times out (the
/// existing recovery path, unchanged) — when the core does not answer, no
/// extras run at all.
const Duration kEngineReadBudget = Duration(seconds: 15);

/// How long each extra request may take before it counts as not answered.
const Duration kExtraCommandWindow = Duration(seconds: 2);

/// How old the last extras run may be before the automatic 5-second re-read
/// runs them again. A manual read, a new connection or a changed code list
/// always runs them.
const Duration kEngineExtrasRefresh = Duration(minutes: 2);

/// How long the adapter is given to drain a late reply after a request is
/// abandoned.
const Duration kFlushSettle = Duration(milliseconds: 200);

// ── Engine state and voltage ───────────────────────────────────────────────
// ENGINEERING JUDGEMENT, NOT MEASURED ON A BIKE. Each of these must be
// confirmed at the final live test before it is relied on.

/// At or above this RPM the engine counts as running. A stopped engine reports
/// 0; cranking reaches roughly 200–300; a motorcycle idles near 1,000–1,500.
const double kEngineRunningRpm = 300;

/// Below this, with the engine OFF (or its state unknown), battery voltage is
/// LOW. A rested 12 V lead-acid battery below about 11.8 V is substantially
/// discharged.
const double kLowVoltageEngineOff = 11.8;

/// Below this with the engine RUNNING, voltage is LOW: the charging system
/// should be holding the battery well above 13 V.
const double kLowVoltageEngineRunning = 12.5;

/// Above this, voltage is HIGH (regulator suspect). Recorded; no banner yet.
const double kHighVoltage = 15.0;

/// How recent a voltage reading must be to qualify an ABS scan's network
/// codes as "may be false".
const Duration kVoltageFreshness = Duration(minutes: 5);

/// All fault-read timing in one place, so tests can run the real logic at a
/// fraction of the real durations. Production always uses scale 1.0.
class FaultReadTiming {
  const FaultReadTiming() : scale = 1.0;
  const FaultReadTiming.scaled(this.scale);

  final double scale;

  Duration _s(Duration d) =>
      Duration(microseconds: (d.inMicroseconds * scale).round());

  Duration get pendingPerAttempt => _s(kPendingPerAttemptWindow);
  Duration get pendingOverall => _s(kPendingOverallBound);
  Duration get pendingRetryDelay => _s(kPendingRetryDelay);
  Duration get engineReadBudget => _s(kEngineReadBudget);
  Duration get extraCommandWindow => _s(kExtraCommandWindow);
  Duration get extrasRefresh => _s(kEngineExtrasRefresh);
  Duration get flushSettle => _s(kFlushSettle);

  /// The pending policy for a read, its overall bound clipped to [overall].
  PendingPolicy pendingPolicy({Duration? overall, Duration? perAttempt}) {
    final o = overall == null || overall > pendingOverall ? pendingOverall : overall;
    return PendingPolicy(
      perAttempt: perAttempt ?? pendingPerAttempt,
      overall: o,
      retryDelay: pendingRetryDelay,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Engine state and voltage
// ═══════════════════════════════════════════════════════════════════════════

enum EngineState { running, off, unknown }

/// From PID 01 0C. Null (no reading) is unknown, never "off".
EngineState engineStateFromRpm(double? rpm) {
  if (rpm == null || rpm.isNaN) return EngineState.unknown;
  return rpm >= kEngineRunningRpm ? EngineState.running : EngineState.off;
}

enum VoltageSource {
  /// PID 01 42, the engine computer's own measurement.
  modulePid42,

  /// `ATRV`, the adapter's reading of the connector's battery pin. Clone
  /// adapters' readings can be off by a constant factor; used only when the
  /// module does not report its voltage.
  adapterAtRv,
}

enum VoltageLevel { low, normal, high }

/// LOW below [kLowVoltageEngineRunning] when running, below
/// [kLowVoltageEngineOff] when off or unknown; HIGH above [kHighVoltage].
VoltageLevel classifyVoltage(double volts, EngineState state) {
  if (volts > kHighVoltage) return VoltageLevel.high;
  final floor = state == EngineState.running
      ? kLowVoltageEngineRunning
      : kLowVoltageEngineOff;
  return volts < floor ? VoltageLevel.low : VoltageLevel.normal;
}

class VoltageReading {
  const VoltageReading(
      {required this.volts, required this.source, required this.at});
  final double volts;
  final VoltageSource source;
  final DateTime at;

  VoltageLevel levelFor(EngineState state) => classifyVoltage(volts, state);
}

// ═══════════════════════════════════════════════════════════════════════════
// One extra's outcome
// ═══════════════════════════════════════════════════════════════════════════

sealed class ExtraRead<T> {
  const ExtraRead();

  T? get valueOrNull =>
      switch (this) { ExtraValue<T>(:final value) => value, _ => null };
}

final class ExtraValue<T> extends ExtraRead<T> {
  const ExtraValue(this.value);
  final T value;
}

/// The vehicle does not offer this. Not a failure, and never shown as empty.
final class ExtraUnsupported<T> extends ExtraRead<T> {
  const ExtraUnsupported([this.nrc]);
  final int? nrc;
}

/// Asked, and no usable answer: silence, a refusal, a busy module, or bytes
/// that could not be read.
final class ExtraNoAnswer<T> extends ExtraRead<T> {
  const ExtraNoAnswer(this.reason);
  final String reason;
}

/// Not asked: the time budget ran out, or there was no reason to ask.
final class ExtraSkipped<T> extends ExtraRead<T> {
  const ExtraSkipped(this.reason);
  final String reason;
}

/// Stopped before it finished (disconnect, another operation, or cancel).
final class ExtraCancelled<T> extends ExtraRead<T> {
  const ExtraCancelled();
}

ExtraRead<T> extraFromDecoded<T>(Decoded<T> d) {
  switch (d) {
    case DecodedValue(:final value):
      return ExtraValue<T>(value);
    case DecodedUnsupported(:final nrc):
      return ExtraUnsupported<T>(nrc);
    case DecodedNegative(:final nrc):
      return ExtraNoAnswer<T>(
          'refused (NRC ${FailureType.hex(nrc)})');
    case DecodedNoAnswer(:final reason):
      return ExtraNoAnswer<T>(reason);
    case DecodedUnparseable(:final reason):
      return ExtraNoAnswer<T>('unreadable: $reason');
  }
}

/// PID 01 01 said one number of stored codes; Mode 03 sent another.
class CountMismatch {
  const CountMismatch({required this.reported, required this.received});
  final int reported;
  final int received;
}

// ═══════════════════════════════════════════════════════════════════════════
// The report
// ═══════════════════════════════════════════════════════════════════════════

/// Everything the extras established for one engine read. Immutable; the
/// service replaces it as each extra lands.
class EngineReport {
  const EngineReport({
    required this.startedAt,
    required this.coreCodes,
    this.finishedAt,
    this.inProgress = true,
    this.pending = const ExtraSkipped('not read yet'),
    this.permanent = const ExtraSkipped('not read yet'),
    this.mil = const ExtraSkipped('not read yet'),
    this.rpm = const ExtraSkipped('not read yet'),
    this.voltage = const ExtraSkipped('not read yet'),
    this.vin = const ExtraSkipped('not read yet'),
    this.calibrationIds = const ExtraSkipped('not read yet'),
  });

  final DateTime startedAt;
  final DateTime? finishedAt;
  final bool inProgress;

  /// The Mode 03 codes these extras were read alongside. The merged list only
  /// uses this report while the current Mode 03 list is still the same set.
  final Set<String> coreCodes;

  final ExtraRead<List<FaultRecord>> pending;
  final ExtraRead<List<FaultRecord>> permanent;
  final ExtraRead<MilStatus> mil;
  final ExtraRead<double> rpm;
  final ExtraRead<VoltageReading> voltage;
  final ExtraRead<Vin> vin;
  final ExtraRead<List<String>> calibrationIds;

  EngineState get engineState => engineStateFromRpm(rpm.valueOrNull);

  /// At least one extra was cancelled before it finished (disconnect, another
  /// operation took the link, or a new read). The next read runs them again.
  bool get stoppedEarly => <ExtraRead<Object?>>[
        pending, permanent, mil, rpm, voltage, vin, calibrationIds,
      ].any((r) => r is ExtraCancelled);

  VoltageLevel? get voltageLevel => voltage.valueOrNull?.levelFor(engineState);

  bool get lowVoltage => voltageLevel == VoltageLevel.low;

  /// Engine warning lamp from PID 01 01; null when unknown.
  bool? get lampOn => mil.valueOrNull?.lampOn;

  /// Set when PID 01 01's stored-code count disagrees with the Mode 03 list.
  CountMismatch? get countMismatch {
    final m = mil.valueOrNull;
    if (m == null) return null;
    final received = coreCodes.length;
    return m.storedCount == received
        ? null
        : CountMismatch(reported: m.storedCount, received: received);
  }

  EngineReport copyWith({
    DateTime? finishedAt,
    bool? inProgress,
    ExtraRead<List<FaultRecord>>? pending,
    ExtraRead<List<FaultRecord>>? permanent,
    ExtraRead<MilStatus>? mil,
    ExtraRead<double>? rpm,
    ExtraRead<VoltageReading>? voltage,
    ExtraRead<Vin>? vin,
    ExtraRead<List<String>>? calibrationIds,
  }) =>
      EngineReport(
        startedAt: startedAt,
        coreCodes: coreCodes,
        finishedAt: finishedAt ?? this.finishedAt,
        inProgress: inProgress ?? this.inProgress,
        pending: pending ?? this.pending,
        permanent: permanent ?? this.permanent,
        mil: mil ?? this.mil,
        rpm: rpm ?? this.rpm,
        voltage: voltage ?? this.voltage,
        vin: vin ?? this.vin,
        calibrationIds: calibrationIds ?? this.calibrationIds,
      );
}

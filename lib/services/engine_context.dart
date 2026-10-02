/// Danlite ELM — the on-demand context reads: freeze frame, lamp and
/// clear-codes counters, and the emission self-checks.
///
/// A fault code alone does not say when it happened, how long the warning lamp
/// has been on, or whether the bike's own self-checks have finished. These
/// reads add that. They are asked for by the rider (the Show details button,
/// the Freeze Frame screen) and are never part of a scan.
///
/// Everything here is pure Dart and never throws. The rule that runs through
/// it, as in `fault_decoders.dart`: an unknown is never shown as known, and a
/// silence is never shown as "none".
///
/// Byte layouts: SAE J1979, as published in public references — THEY MUST BE
/// RE-CHECKED against the standard before release.
///   * Mode 01 PID 21 distance with the lamp on, PID 31 distance since codes
///     were cleared: 256A+B km. PID 4D time with the lamp on, PID 4E time since
///     cleared: 256A+B minutes. PID 30 warm-ups since cleared: A.
///   * Mode 02 returns the same PIDs as they were when the last fault was
///     recorded. The request is `02 <pid> <frame>`; the reply is
///     `42 <pid> <frame> <data>`. PID 02 is the code that caused the snapshot;
///     `0000` means there is NO snapshot and every other value is meaningless.
///   * Mode 01 PID 01, `41 01 A B C D`: A bit 7 lamp, bits 0–6 stored count.
///     B bit 0/1/2 misfire / fuel system / components SUPPORTED, bit 3 ignition
///     type (0 spark, 1 compression), bit 4/5/6 the same three NOT complete.
///     C (spark ignition) bits 0–7 catalyst, heated catalyst, evaporative
///     system, secondary air, "other self-check" (bit 4), oxygen sensor, oxygen
///     sensor heater, EGR/VVT SUPPORTED; D the same positions NOT complete
///     (1 = not complete).
///   * Bit 4 of C and D is deliberately NOT named. Editions of SAE J1979 define
///     it differently — older ones "A/C system refrigerant", newer ones
///     "gasoline particulate filter" — and neither exists on a motorcycle, so
///     the app shows only a generic "other self-check" and its state.
library;

import '../constants/obd_pids.dart';
import 'engine_report.dart';
import 'fault_decoders.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Shared plumbing
// ═══════════════════════════════════════════════════════════════════════════

String _hex2(int b) => b.toRadixString(16).toUpperCase().padLeft(2, '0');

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Decoded<B> _then<A, B>(Decoded<A> d, B Function(A) f) {
  switch (d) {
    case DecodedValue(:final value):
      try {
        return DecodedValue<B>(f(value));
      } on FormatException catch (e) {
        return DecodedUnparseable<B>(e.message);
      } catch (e) {
        return DecodedUnparseable<B>('decoder error: ${e.runtimeType}');
      }
    case DecodedUnsupported(:final nrc):
      return DecodedUnsupported<B>(nrc);
    case DecodedNegative(:final nrc):
      return DecodedNegative<B>(nrc);
    case DecodedNoAnswer(:final reason):
      return DecodedNoAnswer<B>(reason);
    case DecodedUnparseable(:final reason):
      return DecodedUnparseable<B>(reason);
  }
}

/// One answer out of every module's reply. [dropFrame] (Mode 02): the first
/// data byte is the frame number — it must be 0, the frame that was asked for,
/// and is removed. [take] bytes are kept (fewer, down to [minTake], when the
/// reply has an optional last byte and the bike left it out). Two modules that
/// give DIFFERENT data give no value at all: which one is right is not
/// something to guess.
Decoded<List<int>> _agreed(Decoded<List<List<int>>> d,
    {required int take, int? minTake, bool dropFrame = false}) {
  final least = minTake ?? take;
  return _then<List<List<int>>, List<int>>(d, (rows) {
    final kept = <List<int>>[];
    for (final r in rows) {
      var data = r;
      if (dropFrame) {
        if (data.isEmpty || data[0] != 0) {
          throw const FormatException('unexpected frame number');
        }
        data = data.sublist(1);
      }
      if (data.length < least) throw const FormatException('reply too short');
      kept.add(data.sublist(0, data.length < take ? data.length : take));
    }
    for (final k in kept.skip(1)) {
      if (!_sameBytes(kept.first, k)) {
        throw const FormatException('modules gave different values');
      }
    }
    return kept.first;
  });
}

/// Does one reply LINE hold `<service+40> <pid>` back to back? Every PID read
/// here answers in a single frame, so the header is never split across lines.
/// The shared frame reassembler will join a stray continuation line onto the
/// line before it; a value built that way is made of two unrelated replies and
/// must not become a number (the fuzz test found `41` / `23 21 00 41 …`).
bool _headerOnOneLine(String raw, int service, int pid) {
  for (final line in replyLines(raw)) {
    final b = lineBytes(line);
    for (var i = 0; i + 1 < b.length; i++) {
      if (b[i] == service + 0x40 && b[i + 1] == pid) return true;
    }
  }
  return false;
}

/// The [take] data bytes of Mode [service] PID [pid]'s reply (a Mode 02 reply
/// has one more byte, the frame number, which [_agreed] checks and drops).
/// [minTake] below [take]: the last bytes are optional.
Decoded<List<int>> _agreedBytes(String? raw,
    {required int service, required int pid, required int take, int? minTake}) {
  final d = decodePidData(raw,
      service: service,
      pid: pid,
      minBytes: (minTake ?? take) + (service == 2 ? 1 : 0));
  if (d is DecodedValue<List<List<int>>> &&
      raw != null &&
      !_headerOnOneLine(raw, service, pid)) {
    return const DecodedUnparseable<List<int>>('reply lines do not hold the answer together');
  }
  return _agreed(d, take: take, minTake: minTake, dropFrame: service == 2);
}

// ═══════════════════════════════════════════════════════════════════════════
// C2 — the counters
// ═══════════════════════════════════════════════════════════════════════════

/// The five context counters, in the order they are read.
enum ContextCounter {
  /// Distance travelled with the warning lamp on (km).
  lampDistance(0x21, 2, 65535),

  /// Distance travelled since the codes were cleared (km).
  clearedDistance(0x31, 2, 65535),

  /// Engine run time with the warning lamp on (minutes).
  lampTime(0x4D, 2, 65535),

  /// Engine run time since the codes were cleared (minutes).
  clearedTime(0x4E, 2, 65535),

  /// Warm-ups since the codes were cleared (one byte, so at most 255).
  warmUps(0x30, 1, 255);

  const ContextCounter(this.pid, this.bytes, this.max);
  final int pid;
  final int bytes;

  /// The largest value the counter can hold. A reading AT the maximum means
  /// "at least this much", not "exactly this much".
  final int max;

  String get request => '01${_hex2(pid)}';
}

class CounterValue {
  const CounterValue(this.value, this.max);
  final int value;
  final int max;

  /// The counter has stopped counting: the true figure is this or more.
  bool get atLeast => value >= max;
}

Decoded<CounterValue> decodeContextCounter(String? raw, ContextCounter c) {
  try {
    final d = _agreedBytes(raw, service: 1, pid: c.pid, take: c.bytes);
    return _then<List<int>, CounterValue>(
        d, (b) => CounterValue(c.bytes == 2 ? b[0] * 256 + b[1] : b[0], c.max));
  } catch (e) {
    return DecodedUnparseable<CounterValue>('decoder error: ${e.runtimeType}');
  }
}

/// The counters as the screen needs them. Each one is its own typed state:
/// a value, "this bike does not have it", "asked and no answer", "not asked"
/// or "stopped".
class ContextCounters {
  const ContextCounters({
    required this.at,
    this.lampDistance = const ExtraSkipped<CounterValue>('not read yet'),
    this.clearedDistance = const ExtraSkipped<CounterValue>('not read yet'),
    this.lampTime = const ExtraSkipped<CounterValue>('not read yet'),
    this.clearedTime = const ExtraSkipped<CounterValue>('not read yet'),
    this.warmUps = const ExtraSkipped<CounterValue>('not read yet'),
  });

  final DateTime at;
  final ExtraRead<CounterValue> lampDistance;
  final ExtraRead<CounterValue> clearedDistance;
  final ExtraRead<CounterValue> lampTime;
  final ExtraRead<CounterValue> clearedTime;
  final ExtraRead<CounterValue> warmUps;

  ExtraRead<CounterValue> of(ContextCounter c) => switch (c) {
        ContextCounter.lampDistance => lampDistance,
        ContextCounter.clearedDistance => clearedDistance,
        ContextCounter.lampTime => lampTime,
        ContextCounter.clearedTime => clearedTime,
        ContextCounter.warmUps => warmUps,
      };

  ContextCounters withCounter(ContextCounter c, ExtraRead<CounterValue> r) =>
      ContextCounters(
        at: at,
        lampDistance: c == ContextCounter.lampDistance ? r : lampDistance,
        clearedDistance: c == ContextCounter.clearedDistance ? r : clearedDistance,
        lampTime: c == ContextCounter.lampTime ? r : lampTime,
        clearedTime: c == ContextCounter.clearedTime ? r : clearedTime,
        warmUps: c == ContextCounter.warmUps ? r : warmUps,
      );

  /// At least one counter was asked for and got no usable answer (silence, a
  /// refusal or unreadable bytes) — not "unsupported", which stays silent.
  bool get anyUnanswered => ContextCounter.values.any((c) => of(c) is ExtraNoAnswer);
}

/// Should a "lamp has been on for …" line be drawn for [v]?
///
/// PID 21 / 4D count from when the lamp came on, and are 0 when it is off — so
/// "the lamp has been on for 0 km" would be untrue. Shown only when the value
/// is above zero AND the lamp is not known to be off ([lampOn] null = unknown).
bool lampCounterIsShown(CounterValue v, {required bool? lampOn}) =>
    v.value > 0 && lampOn != false;

/// `65535` → `65,535`. Latin digits, as the owner's style sheet requires.
String formatCount(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

// ═══════════════════════════════════════════════════════════════════════════
// C3 — emission self-checks (readiness)
// ═══════════════════════════════════════════════════════════════════════════

enum Monitor {
  misfire('monMisfire'),
  fuelSystem('monFuelSystem'),
  components('monComponents'),
  catalyst('monCatalyst'),
  heatedCatalyst('monHeatedCatalyst'),
  evaporative('monEvaporative'),
  secondaryAir('monSecondaryAir'),
  /// Bit 4 of bytes C and D. Different editions of SAE J1979 name it A/C
  /// refrigerant or gasoline particulate filter; neither exists on a
  /// motorcycle, so it is never named.
  otherSelfCheck('monOtherSelfCheck'),
  oxygenSensor('monOxygenSensor'),
  oxygenSensorHeater('monOxygenSensorHeater'),
  egr('monEgr');

  const Monitor(this.labelKey);

  /// The translation key of the monitor's name.
  final String labelKey;
}

enum MonitorState {
  complete,
  notComplete,

  /// This bike does not have the check.
  notSupported,

  /// The check does not exist for this kind of engine (compression ignition).
  notApplicable,
}

class ReadinessReport {
  const ReadinessReport({
    required this.lampOn,
    required this.storedCount,
    required this.compressionIgnition,
    required this.states,
  });

  /// From byte A of the same reply.
  final bool lampOn;
  final int storedCount;
  final bool compressionIgnition;
  final Map<Monitor, MonitorState> states;
}

/// The emission self-check bits, as a pure function of the four bytes of
/// `41 01 A B C D`.
ReadinessReport decodeReadinessBytes(int a, int b, int c, int d) {
  a &= 0xFF;
  b &= 0xFF;
  c &= 0xFF;
  d &= 0xFF;
  MonitorState state(bool supported, bool notComplete) => !supported
      ? MonitorState.notSupported // a stale "not complete" bit says nothing
      : (notComplete ? MonitorState.notComplete : MonitorState.complete);
  bool bit(int v, int n) => (v >> n) & 1 == 1;

  final compression = bit(b, 3);
  const spark = <Monitor>[
    Monitor.catalyst,
    Monitor.heatedCatalyst,
    Monitor.evaporative,
    Monitor.secondaryAir,
    Monitor.otherSelfCheck,
    Monitor.oxygenSensor,
    Monitor.oxygenSensorHeater,
    Monitor.egr,
  ];
  return ReadinessReport(
    lampOn: bit(a, 7),
    storedCount: a & 0x7F,
    compressionIgnition: compression,
    states: <Monitor, MonitorState>{
      Monitor.misfire: state(bit(b, 0), bit(b, 4)),
      Monitor.fuelSystem: state(bit(b, 1), bit(b, 5)),
      Monitor.components: state(bit(b, 2), bit(b, 6)),
      for (var i = 0; i < spark.length; i++)
        spark[i]: compression
            ? MonitorState.notApplicable
            : state(bit(c, i), bit(d, i)),
    },
  );
}

/// What the self-check read established, and when. [result] is its own typed
/// state: a report, "this bike does not have it", "asked and no answer", "not
/// asked".
class ReadinessRead {
  const ReadinessRead(this.at, this.result);
  final DateTime at;
  final ExtraRead<ReadinessReport> result;
}

Decoded<ReadinessReport> decodeReadiness(String? raw) {
  try {
    final d = _agreedBytes(raw, service: 1, pid: 0x01, take: 4);
    return _then<List<int>, ReadinessReport>(
        d, (b) => decodeReadinessBytes(b[0], b[1], b[2], b[3]));
  } catch (e) {
    return DecodedUnparseable<ReadinessReport>('decoder error: ${e.runtimeType}');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// C1 — the freeze frame (Mode 02)
// ═══════════════════════════════════════════════════════════════════════════

/// The code that caused the snapshot. [code] null = PID 02 said `0000`: there
/// is NO snapshot.
class FreezeFrameTrigger {
  const FreezeFrameTrigger(this.code);
  final String? code;
  bool get hasSnapshot => code != null;
}

Decoded<FreezeFrameTrigger> decodeFreezeFrameTrigger(String? raw) {
  try {
    final d = _agreedBytes(raw, service: 2, pid: 0x02, take: 2);
    return _then<List<int>, FreezeFrameTrigger>(d, (b) {
      if (b[0] == 0 && b[1] == 0) return const FreezeFrameTrigger(null);
      final code = ObdParser.decodeDtcPair(b[0], b[1]);
      if (code == null) throw const FormatException('not a code');
      return FreezeFrameTrigger(code);
    });
  } catch (e) {
    return DecodedUnparseable<FreezeFrameTrigger>('decoder error: ${e.runtimeType}');
  }
}

/// The PIDs a module supports in the block starting after [basePid] (0x00 →
/// PIDs 01–20, 0x40 → 41–60). [service] 1 or 2.
Decoded<Set<int>> decodeSupportedPids(String? raw,
    {required int service, required int basePid}) {
  try {
    final d = _agreedBytes(raw, service: service, pid: basePid, take: 4);
    return _then<List<int>, Set<int>>(d, (b) {
      final out = <int>{};
      for (var i = 0; i < 32; i++) {
        if ((b[i ~/ 8] >> (7 - i % 8)) & 1 == 1) out.add(basePid + i + 1);
      }
      return out;
    });
  } catch (e) {
    return DecodedUnparseable<Set<int>>('decoder error: ${e.runtimeType}');
  }
}

/// The fixed set of values read for a snapshot, in this order.
enum SnapshotPid {
  fuelSystem(0x03, 2, 'snapFuelSystem', '', 0),
  engineLoad(0x04, 1, 'engineLoad', '%', 0),
  coolant(0x05, 1, 'coolantTemp', '°C', 0),
  shortTrim(0x06, 1, 'snapShortTrim', '%', 1),
  longTrim(0x07, 1, 'snapLongTrim', '%', 1),
  intakePressure(0x0B, 1, 'snapIntakePressure', 'kPa', 0),
  rpm(0x0C, 2, 'rpm', 'RPM', 0),
  speed(0x0D, 1, 'speed', 'km/h', 0),
  intakeTemp(0x0F, 1, 'snapIntakeAirTemp', '°C', 0),
  throttle(0x11, 1, 'throttle', '%', 0),
  moduleVoltage(0x42, 2, 'snapModuleVoltage', 'V', 2);

  const SnapshotPid(this.pid, this.bytes, this.labelKey, this.unit, this.decimals);
  final int pid;

  /// Data bytes after the frame number.
  final int bytes;
  final String labelKey;

  /// Never translated (see the i18n note on gauge units).
  final String unit;
  final int decimals;

  /// The Mode 02 request, frame 0.
  String get request => '02${_hex2(pid)}00';

  /// PID 02 (the code that caused the snapshot), frame 0 — always the first
  /// request of a snapshot read.
  static const String triggerRequest = '020200';

  /// The PID's supported-list block: `0x00` for PIDs 01–20, `0x40` for 41–60.
  int get supportBlock => (pid - 1) ~/ 0x20 * 0x20;
}

sealed class SnapshotValue {
  const SnapshotValue(this.pid);
  final SnapshotPid pid;
}

final class SnapshotNumber extends SnapshotValue {
  const SnapshotNumber(super.pid, this.value);
  final double value;
  String get unit => pid.unit;
  int get decimals => pid.decimals;
}

enum FuelStatusKind {
  /// There is no such system: the bike left the second byte out, or sent 0
  /// there. Never shown.
  none,

  /// 0 — engine off.
  engineOff,
  openLoopCold,
  closedLoop,
  openLoopLoad,
  openLoopFault,
  closedLoopFault,

  /// A value that is not one of the documented ones.
  unknown;

  /// System 1 (the first byte). 0 is a real state: engine off.
  static FuelStatusKind fromByte(int v) => switch (v) {
        0 => engineOff,
        1 => openLoopCold,
        2 => closedLoop,
        4 => openLoopLoad,
        8 => openLoopFault,
        16 => closedLoopFault,
        _ => unknown,
      };

  /// System 2 (the optional second byte): absent or 0 means there is no second
  /// system, not "engine off".
  static FuelStatusKind fromOptionalByte(int? v) =>
      v == null || v == 0 ? none : fromByte(v);

  String get labelKey => switch (this) {
        none => '',
        engineOff => 'fuelStatusEngineOff',
        openLoopCold => 'fuelStatusOpenCold',
        closedLoop => 'fuelStatusClosed',
        openLoopLoad => 'fuelStatusOpenLoad',
        openLoopFault => 'fuelStatusOpenFault',
        closedLoopFault => 'fuelStatusClosedFault',
        unknown => 'fuelStatusUnknown',
      };
}

final class SnapshotFuelSystem extends SnapshotValue {
  const SnapshotFuelSystem(this.system1, this.system2)
      : super(SnapshotPid.fuelSystem);
  final FuelStatusKind system1;
  final FuelStatusKind system2;

  bool get reportsAnything =>
      system1 != FuelStatusKind.none || system2 != FuelStatusKind.none;
}

/// One snapshot value, scaled with the SAME formula and unit as the live
/// reading of that PID ([ObdParser.parsePid]); fuel-system status has no live
/// equivalent and is decoded here.
Decoded<SnapshotValue> decodeFreezeFrameValue(String? raw, SnapshotPid p) {
  try {
    // Fuel system status is one byte per system; system 2 is optional.
    final d = _agreedBytes(raw,
        service: 2,
        pid: p.pid,
        take: p.bytes,
        minTake: p == SnapshotPid.fuelSystem ? 1 : null);
    return _then<List<int>, SnapshotValue>(d, (b) {
      if (p == SnapshotPid.fuelSystem) {
        return SnapshotFuelSystem(FuelStatusKind.fromByte(b[0]),
            FuelStatusKind.fromOptionalByte(b.length > 1 ? b[1] : null));
      }
      final live = ObdParser.parsePid(
          '01${_hex2(p.pid)}', '41 ${_hex2(p.pid)} ${b.map(_hex2).join(' ')}');
      if (live == null || live.isNaN) throw const FormatException('not a number');
      return SnapshotNumber(p, live);
    });
  } catch (e) {
    return DecodedUnparseable<SnapshotValue>('decoder error: ${e.runtimeType}');
  }
}

/// A snapshot the bike answered with.
class FreezeFrameSnapshot {
  const FreezeFrameSnapshot({
    required this.triggerCode,
    required this.readAt,
    required this.values,
    this.unreadPids = const <int>[],
    this.supportListUnreadable = false,
  });

  /// The code that caused the snapshot.
  final String triggerCode;
  final DateTime readAt;

  /// Values the bike reported, in the fixed order. An item the bike does not
  /// have is simply absent.
  final List<SnapshotValue> values;

  /// PIDs the bike said it has but that gave no usable answer (silence,
  /// unreadable bytes). Shown as "some values could not be read" — never as
  /// absent.
  final List<int> unreadPids;

  /// The bike's list of supported snapshot values could not be read, so no
  /// value was asked for.
  final bool supportListUnreadable;

  bool get incomplete => unreadPids.isNotEmpty || supportListUnreadable;
}

/// What a snapshot read established. Six honest outcomes (plus "not asked" for
/// the K-line gate); a timeout is NEVER the same as "no snapshot".
sealed class FreezeFrameResult {
  const FreezeFrameResult(this.at);
  final DateTime at;
}

/// The bike has a snapshot and gave it.
final class FreezeFrameAnswered extends FreezeFrameResult {
  FreezeFrameAnswered(this.snapshot) : super(snapshot.readAt);
  final FreezeFrameSnapshot snapshot;
}

/// PID 02 answered `0000`: nothing is stored.
final class FreezeFrameNoSnapshot extends FreezeFrameResult {
  const FreezeFrameNoSnapshot(super.at);
}

/// The bike does not offer snapshot data.
final class FreezeFrameUnsupported extends FreezeFrameResult {
  const FreezeFrameUnsupported(super.at);
}

/// Asked, and nothing usable came back — silence, a busy module, unreadable
/// bytes. This says NOTHING about whether a snapshot exists.
final class FreezeFrameNoAnswer extends FreezeFrameResult {
  const FreezeFrameNoAnswer(super.at, this.reason);
  final String reason;
}

final class FreezeFrameLinkLost extends FreezeFrameResult {
  const FreezeFrameLinkLost(super.at);
}

/// The bike answered with a refusal that is not "not supported".
final class FreezeFrameRefused extends FreezeFrameResult {
  const FreezeFrameRefused(super.at, this.nrc);
  final int nrc;
}

/// Not asked: this bike uses the older connection type that stays switched
/// off. "We did not ask" is not "the bike did not answer".
final class FreezeFrameGated extends FreezeFrameResult {
  const FreezeFrameGated(super.at);
}

/// The result that ENDS a snapshot read after the trigger-code request, or
/// null when the read should go on (a real code came back).
///
/// A `NO DATA` is the bike being silent about the request: it only counts as
/// "this bike does not offer snapshots" when the vehicle has already answered
/// something this session ([vehicleAnswered]). A refusal that names "not
/// supported" is the bike saying so.
FreezeFrameResult? freezeFrameEndsHere(
  Decoded<FreezeFrameTrigger> d,
  DateTime at, {
  required bool vehicleAnswered,
}) {
  switch (d) {
    case DecodedValue(:final value):
      return value.hasSnapshot ? null : FreezeFrameNoSnapshot(at);
    case DecodedUnsupported(:final nrc):
      if (nrc != null || vehicleAnswered) return FreezeFrameUnsupported(at);
      return FreezeFrameNoAnswer(at, 'no reply from the vehicle yet');
    case DecodedNegative(:final nrc):
      return FreezeFrameRefused(at, nrc);
    case DecodedNoAnswer(:final reason):
      return FreezeFrameNoAnswer(at, reason);
    case DecodedUnparseable(:final reason):
      return FreezeFrameNoAnswer(at, 'unreadable: $reason');
  }
}

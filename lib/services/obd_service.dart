import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/chassis_dtc_dictionary.dart';
import '../constants/chassis_modules.dart';
import '../constants/dtc_descriptions.dart';
import '../constants/obd_pids.dart';
import '../models/fault_record.dart';
import '../models/vehicle_data.dart';
import 'bluetooth_classic_service.dart';
import 'chassis_address_memory.dart';
import 'dtc_service.dart' show isManufacturerDefined;
import 'engine_dtc_read.dart';
import 'engine_report.dart';
import 'fault_decoders.dart';
import 'response_pending.dart';
import 'session_recorder.dart';
import 'stored_codes_check.dart';

export 'engine_dtc_read.dart';
export 'engine_report.dart';
export 'stored_codes_check.dart';

enum ConnectionType { wifi, bluetooth }

/// What a raw adapter reply proves about the *link*, as opposed to what it
/// says about the *command*.
///
/// These are two different questions and the service used to answer both from
/// the same string. That conflation is what produced false "Connection Failed"
/// reports: a command that did not answer inside its own window was reported
/// to the user as a dead connection, even while the adapter was demonstrably
/// still carrying traffic.
enum ObdReplyClass {
  /// Bytes came back from the adapter, so the link is PROVEN alive.
  ///
  /// The payload may be empty. A bare `>` prompt with nothing before it is the
  /// complete and correct reply to any command the ECU answers with no data —
  /// an unsupported live PID, and notably a Mode 04 flash erase, whose normal
  /// acknowledgement on single-ECU vehicles carries no payload bytes at all.
  /// "Thin" is not "absent".
  answered,

  /// The window elapsed with no reply, but the link has delivered traffic
  /// recently enough that it cannot honestly be called failed. The COMMAND did
  /// not answer; the CONNECTION is fine. Callers must resolve this on the
  /// command's own terms — never by reporting a connection failure.
  noAnswer,

  /// The transport itself reported failure, or nothing has come back for long
  /// enough that the link can no longer be presumed alive. This — and only
  /// this — is a genuine connection failure.
  linkFailure,
}

/// Why a Clear Codes attempt ended the way it did.
///
/// [ObdService.clearDtcs] still answers the only question its caller must act
/// on — did the codes go? — with a bool. This says *why*, because "false" has
/// never meant one thing: a dead Bluetooth link, an ECU that refused the
/// erase, and an erase that probably worked but could not be confirmed are
/// three different events, and the screen was reporting all three to the rider
/// as "Connection Failed". Telling a rider their connection failed when the
/// adapter is sitting there connected sends them to debug the wrong thing.
enum ClearDtcsOutcome {
  /// No attempt has been made in this session.
  idle,

  /// The fault memory was erased, and that is either acknowledged or confirmed.
  cleared,

  /// The link was genuinely gone — the real "Connection Failed".
  linkFailure,

  /// The ECU actively refused the erase (negative response `7F 04`), or
  /// answered with a bus/adapter error. The codes were NOT cleared, and the
  /// connection is not the problem. Most commonly the engine is running or the
  /// module is in a security lockout.
  refused,

  /// The erase went out over a link that was demonstrably alive, but the ECU
  /// never acknowledged it and never answered the follow-up Mode 03 either.
  ///
  /// This is genuinely unknown, not a failure: the codes may well be gone. It
  /// is the state a module that is slow to come back from a flash write lands
  /// in, and it must not be reported as a connection failure.
  unconfirmed,

  /// The link was alive and the ECU answered the follow-up Mode 03 — and its
  /// fault memory still holds codes. The erase demonstrably did not take.
  notCleared,
}

/// Static sensor snapshot captured by the ECU at the moment a DTC was set
/// (OBD2 Mode 02). Any field may be null if that PID isn't supported by the
/// vehicle or its response didn't parse.
class FreezeFrameData {
  final String? dtcCode;
  final double? rpm;
  final double? speed;
  final double? coolantTemp;
  final double? engineLoad;
  final DateTime capturedAt;

  const FreezeFrameData({
    this.dtcCode,
    this.rpm,
    this.speed,
    this.coolantTemp,
    this.engineLoad,
    required this.capturedAt,
  });

  bool get hasData =>
      dtcCode != null || rpm != null || speed != null || coolantTemp != null || engineLoad != null;
}

class ObdService extends ChangeNotifier {
  ObdService(this._btService,
      {ChassisAddressMemory? chassisAddressMemory,
      this.recorder,
      FaultReadTiming? faultTiming})
      : chassisAddressMemory = chassisAddressMemory ?? ChassisAddressMemory(),
        faultTiming = faultTiming ?? const FaultReadTiming() {
    _btService.addListener(_onBtServiceChanged);
  }

  final BluetoothClassicService _btService;

  /// Response-pending, extras and budget timings. Always the real constants
  /// in the app; tests pass a scaled copy to run the same logic faster.
  final FaultReadTiming faultTiming;

  /// Tester-mode session recorder. Null, or switched off, in normal use —
  /// see `session_recorder.dart`. It is the ONLY place raw adapter traffic is
  /// written outside this object's memory.
  final SessionRecorder? recorder;

  /// Which chassis address a given make + model is already known to answer at.
  ///
  /// Injectable so tests can drive the real memory logic against an in-memory
  /// store instead of a platform channel. See `chassis_address_memory.dart`
  /// for what its scope is, and honestly is not.
  final ChassisAddressMemory chassisAddressMemory;

  // ── State ─────────────────────────────────────────────────────────────────
  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionType _transport = ConnectionType.wifi;

  ConnectionStatus get status => _status;
  ConnectionType get transport => _transport;
  bool get isConnected => _status == ConnectionStatus.connected;

  String _statusMessage = 'Not connected';
  String get statusMessage => _statusMessage;

  VehicleData _data = VehicleData.empty();
  VehicleData get data => _data;

  /// Engine codes from the last read the engine computer actually ANSWERED.
  ///
  /// Kept after a later read fails, so the screen can show them greyed out
  /// with [dtcCodesReadAt]; whether they are current is [lastEngineRead]'s
  /// call, never this list's. Cleared when the link drops or a new connection
  /// starts — codes from a previous session may not even be this bike's.
  List<DtcCode> _dtcCodes = [];
  List<DtcCode> get dtcCodes => _dtcCodes;

  /// When [dtcCodes] was read. Null when nothing has answered this session.
  DateTime? _dtcCodesReadAt;
  DateTime? get dtcCodesReadAt => _dtcCodesReadAt;

  /// What the most recent engine read established. Null until one finishes in
  /// this session. See [EngineDtcRead].
  EngineDtcRead? _lastEngineRead;
  EngineDtcRead? get lastEngineRead => _lastEngineRead;

  /// The current adapter session: adapter identity, detected protocol, and
  /// whether the vehicle itself has answered. Null while disconnected.
  ObdSession? _session;
  ObdSession? get session => _session;

  /// True only once the VEHICLE has given a positive reply this session — the
  /// adapter accepting its set-up commands is not enough.
  bool get vehicleAnswered => _session?.vehicleAnswered ?? false;

  /// Status line to show once the vehicle answers, saved at connect time.
  String _connectedStatusMessage = '';

  // ── Engine extras (Mode 07 / 0A, PID 01 01, RPM, voltage, VIN) ────────────
  /// What the optional extras established, for the latest read that ran
  /// them. Null until one has run this session. See [EngineReport].
  EngineReport? _engineReport;
  EngineReport? get engineReport => _engineReport;

  /// True while the extras are still reading, after the core result is out.
  bool get engineExtrasInFlight => _extrasRunning;

  bool _extrasRunning = false;
  bool _extrasCancelRequested = false;
  /// Foreground operations currently waiting for the engine job to hand the
  /// link back. While any is waiting, extras do not start and stop at the
  /// next safe point.
  int _linkWaiters = 0;

  /// The whole engine read job — core, extras and putting the adapter back —
  /// so another foreground operation can wait for the link to be handed back.
  Future<void>? _engineJob;

  /// Completes when the current engine read job — core, extras and putting
  /// the adapter back — has finished. Completes at once when none is running.
  Future<void> whenEngineReadSettled() => _engineJob ?? Future<void>.value();

  /// Stop the extras at the next safe point. The core result is untouched;
  /// unfinished extras end as [ExtraCancelled]. Safe to call at any time.
  void cancelEngineExtras() {
    if (_extrasRunning) _extrasCancelRequested = true;
  }

  /// Every engine code as one record each: Mode 03 merged with the extras'
  /// Mode 07 (pending) and 0A (permanent). The extras are only merged while
  /// the Mode 03 list is still the one they were read alongside — after a
  /// clear or a changed list, only Mode 03 is shown until they are re-read.
  List<FaultRecord> get engineFaultRecords {
    final stored = <FaultRecord>[
      for (final c in _dtcCodes)
        c.record ?? FaultRecord.fromDtcCode(c, readAt: _dtcCodesReadAt ?? DateTime.now()),
    ];
    final report = _engineReport;
    if (report == null || !_sameCodes(report.coreCodes, _dtcCodes)) return stored;
    return mergeEngineRecords(
      stored: stored,
      pending: report.pending.valueOrNull ?? const <FaultRecord>[],
      permanent: report.permanent.valueOrNull ?? const <FaultRecord>[],
    );
  }

  /// The engine cards: [dtcCodes] plus any pending- or permanent-only code,
  /// each carrying its merged [FaultRecord]. [dtcCodes] itself is unchanged
  /// (Clear Codes still keys on it).
  List<DtcCode> get engineDisplayCodes {
    final byCode = {for (final c in _dtcCodes) c.code: c};
    return <DtcCode>[
      for (final r in engineFaultRecords)
        (byCode[r.code] ?? _buildEngineDtc(r.code)).withRecord(r),
    ];
  }

  /// Mode 03's own count byte disagreed with the codes that arrived.
  CountMismatch? _coreCountMismatch;

  /// A code may be missing from the current engine list: the Mode 03 reply's
  /// own count byte, or PID 01 01's stored-code count, says more (or fewer)
  /// codes than were received. Null when nothing disagrees or it is unknown.
  CountMismatch? get engineCountMismatch {
    if (_lastEngineRead is! EngineAnswered) return null;
    final report = _engineReport;
    final fromPid = report != null && _sameCodes(report.coreCodes, _dtcCodes)
        ? report.countMismatch
        : null;
    return _coreCountMismatch ?? fromPid;
  }

  static bool _sameCodes(Set<String> a, List<DtcCode> b) =>
      a.length == b.length && b.every((c) => a.contains(c.code));

  /// The most recent battery voltage reading this session, from the extras.
  VoltageReading? get latestVoltage =>
      _engineReport?.voltage.valueOrNull;

  /// True when the latest voltage reading is LOW for the known engine state.
  bool get batteryVoltageLow => _engineReport?.lowVoltage ?? false;

  /// True when the latest voltage reading is HIGH (above [kHighVoltage]).
  /// Unknown voltage is never high.
  bool get batteryVoltageHigh =>
      _engineReport?.voltageLevel == VoltageLevel.high;

  /// When the last ABS/chassis scan finished.
  DateTime? _chassisReadAt;
  DateTime? get chassisReadAt => _chassisReadAt;

  /// True when the last ABS scan ran within [kVoltageFreshness] of a LOW
  /// voltage reading, so its network (U) codes may be false.
  bool get chassisReadWhileLowVoltage {
    final v = latestVoltage;
    final at = _chassisReadAt;
    if (!batteryVoltageLow || v == null || at == null) return false;
    return at.difference(v.at).abs() <= kVoltageFreshness;
  }

  // ── Chassis / ABS module scan state ───────────────────────────────────────
  // Kept separate from _dtcCodes rather than merged into it: these come from a
  // different module via a different service, and conflating them would make
  // "clear codes" (Mode 04, engine-only) look like it applied to ABS faults
  // when it does not.
  List<DtcCode> _chassisDtcCodes = [];
  List<DtcCode> get chassisDtcCodes => _chassisDtcCodes;

  ChassisScanOutcome _chassisScanOutcome = ChassisScanOutcome.idle;
  ChassisScanOutcome get chassisScanOutcome => _chassisScanOutcome;

  /// Which candidate module address actually answered, for display/support.
  String _chassisRespondingModule = '';
  String get chassisRespondingModule => _chassisRespondingModule;

  /// Human-readable probe trace, surfaced in the UI so a failed scan can be
  /// diagnosed (wrong address vs. adapter refusing the command) instead of
  /// being an opaque "nothing found".
  List<String> _chassisScanLog = [];
  List<String> get chassisScanLog => _chassisScanLog;

  bool _chassisScanInFlight = false;
  bool get chassisScanInFlight => _chassisScanInFlight;

  /// What the last scan's own probe timings suggest about the adapter.
  ///
  /// Inference, not a capability query — see [ChassisAdapterCapability] for
  /// the published numbers the thresholds are derived from, and for why this
  /// is never stated to the rider as a certainty.
  ChassisAdapterCapability _chassisAdapterCapability =
      ChassisAdapterCapability.unknown;
  ChassisAdapterCapability get chassisAdapterCapability =>
      _chassisAdapterCapability;

  /// Median latency, in ms, of the probes the last scan counted as genuine
  /// no-replies. Null when the scan measured none.
  int? _chassisProbeMedianMs;
  int? get chassisProbeMedianMs => _chassisProbeMedianMs;

  /// Label of the remembered address the last scan tried first, or empty when
  /// nothing was remembered for that vehicle.
  String _chassisLearnedModule = '';
  String get chassisLearnedModule => _chassisLearnedModule;

  /// Wall-clock ceiling on the widened address sweep.
  ///
  /// The two originally-shipped candidates and any remembered address are
  /// exempt, so this can only ever cut the addresses that were *added* when
  /// the list was widened — it can never make a scan that used to work stop
  /// working. Settable so tests can exercise the limit without waiting on it.
  @visibleForTesting
  Duration chassisScanBudget = const Duration(seconds: 60);

  /// How many probes in a row may fail to return at all before the sweep is
  /// abandoned.
  ///
  /// A probe that times out has not told us the module is absent — it has told
  /// us the adapter never handed control back. Grinding through another ten
  /// addresses at five seconds each learns nothing and leaves the rider
  /// staring at a spinner for a minute. The protected candidates are exempt,
  /// so this cannot curtail the original probe order.
  static const int _chassisAbortAfterConsecutiveTimeouts = 3;

  String _lastError = '';
  String get lastError => _lastError;

  bool _linkSynced = true;
  bool get linkSynced => _linkSynced;
  bool _adapterWedged = false;
  bool get adapterWedged => _adapterWedged;

  int _consecutiveParseFailures = 0;
  int _recoveryAttempts = 0;
  DateTime? _lastHeaderRepairAt;

  final List<String> _wireLog = <String>[];
  static const int _wireLogMax = 200;
  String _lastWireCommand = '';
  List<String> get wireLog => List.unmodifiable(_wireLog);

  /// Record one adapter exchange line.
  ///
  /// Deliberately NOT printed. Anything passed to `debugPrint` can become a
  /// Sentry breadcrumb in a release build, and raw adapter traffic and fault
  /// bytes must never reach Sentry. The in-memory ring and the tester-mode
  /// recorder (local file, rider-initiated share only) are the only sinks.
  void _logWire(String direction, String data) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    var printable = data.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
    // Mode 09 replies carry the VIN as hex-encoded text: never kept, even in
    // this in-memory ring. The recorder applies the same rule to its file.
    if (direction.startsWith('TX')) {
      _lastWireCommand = data.trim().toUpperCase();
    } else if (_lastWireCommand.startsWith('09')) {
      printable = '[mode 09 reply masked]';
    }
    _wireLog.add('$ts $direction$printable');
    if (_wireLog.length > _wireLogMax) _wireLog.removeAt(0);
    recorder?.recordExchange(direction, data);
  }

  String exportWireLog() => _wireLog.join('\n');

  // Diagnostics — exposed for debugging / status UI
  int _consecutiveTimeouts = 0;
  int get consecutiveTimeouts => _consecutiveTimeouts;

  DateTime? _lastGoodResponseAt;
  DateTime? get lastGoodResponseAt => _lastGoodResponseAt;

  // How many consecutive unanswered commands it takes before the link stops
  // being presumed alive. Shared by _classifyReply() and _pollLoop() so the
  // "is this connection dead?" question has exactly one threshold rather than
  // one per caller.
  static const int _deadLinkTimeouts = 6;

  // How long a delivered reply keeps proving the link is alive. Sized to sit
  // above the largest single-command window in this service
  // (_chassisScanMinTimeout, 5s) so one slow command can never, on its own,
  // age the link out of "proven alive" — while a link that has genuinely gone
  // quiet crosses the line within a second or two of the timeout that
  // announced it.
  static const Duration _linkProofWindow = Duration(seconds: 6);

  // ── Proof-of-life credit, for multi-command foreground sequences ─────────
  // _linkProofWindow is sized for ONE slow command; that is exactly what its
  // comment above claims, and it is true. clearDtcs() is not one command. It
  // is a sequence — wait for the link to go idle, Mode 04 (4s), let the ECU
  // come back, Mode 03 (3s) — whose total wall-clock legitimately exceeds six
  // seconds with the link perfectly healthy throughout. The window then aged
  // the link out mid-sequence and the erase was reported as a dead connection.
  //
  // The fix is NOT to widen _linkProofWindow globally: that would slow the
  // detection of a genuinely dead link for every command in the app. Instead a
  // sequence that has ALREADY proven the link alive on evidence may carry that
  // proof forward for a bounded time.
  //
  // This is a credit, not a forgery. It is only ever granted after
  // _classifyReply has returned something other than linkFailure, i.e. after
  // the link was just judged alive on real evidence; it expires on a wall
  // clock; and it deliberately does NOT override the _deadLinkTimeouts count,
  // which remains the hard backstop. A link that answers nothing still trips
  // that counter and is still declared dead, credit or no credit.
  DateTime? _linkProofCreditUntil;

  void _creditLinkProof(Duration window) =>
      _linkProofCreditUntil = DateTime.now().add(window);

  void _revokeLinkProofCredit() => _linkProofCreditUntil = null;

  bool get _linkProofCredited {
    final until = _linkProofCreditUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  // ── WiFi transport ────────────────────────────────────────────────────────
  Socket? _wifiSocket;
  StreamSubscription<List<int>>? _wifiSub;
  final StringBuffer _wifiBuffer = StringBuffer();
  Completer<String>? _wifiPendingCmd;

  static const Duration _wifiConnectTimeout = Duration(seconds: 10);

  // ── BT transport ──────────────────────────────────────────────────────────
  StreamSubscription<String>? _btDataSub;
  Completer<String>? _btPendingCmd;
  final StringBuffer _btBuffer = StringBuffer();

  // ── Command timeout — adaptive, increases on repeated failure ───────────
  Duration _cmdTimeout = const Duration(seconds: 2);
  static const Duration _cmdTimeoutMin = Duration(seconds: 2);
  static const Duration _cmdTimeoutMax = Duration(seconds: 6);

  // ── Polling ───────────────────────────────────────────────────────────────
  bool _isPolling = false;
  int _pidIndex = 0;
  // Poll every known PID (not just the 7-PID dashboard subset) so screens
  // like Live Data can surface MAF, MAP, timing advance, fuel trims, etc.
  final _pids = ObdPids.allPids;

  // Held while a foreground command (e.g. clearDtcs) needs exclusive access
  // to the serial link, so _pollLoop() never writes a PID request to the
  // socket while that command is in flight and collides with it on the wire.
  int _pollLockDepth = 0;
  bool get _pollLocked => _pollLockDepth > 0;
  void _acquirePollLock() => _pollLockDepth++;
  void _releasePollLock() {
    if (_pollLockDepth > 0) _pollLockDepth--;
  }

  // ECU flash-memory erasure (04) needs more time to respond than a live
  // PID read does.
  static const Duration _clearDtcsMinTimeout = Duration(milliseconds: 4000);

  // How long the whole clear sequence may carry its proof of life. Sized to
  // cover the worst case it actually has to survive — Mode 04 (4s) + the
  // post-erase settle (1.2s) + two confirmation attempts (3s each) + the pause
  // between them (0.8s) ≈ 12s — with headroom, and no more. It is a ceiling on
  // how long a healthy-but-silent link may be presumed alive, not a target.
  static const Duration _clearSequenceProofWindow = Duration(seconds: 15);

  // Breathing room between the erase request and the first confirmation query.
  //
  // A real ECU stops servicing the bus while it writes flash and a fair number
  // reset afterwards. Firing Mode 03 the instant the Mode 04 window expires
  // asks the module a question at the exact moment it is least able to answer,
  // and burns the confirmation's only attempt doing it. The simulated ECU this
  // path was built against answered Mode 03 in about a millisecond, so nothing
  // in the test suite ever exercised the wait a real module needs.
  static const Duration _postEraseSettle = Duration(milliseconds: 1200);

  // Pause before the second and final confirmation attempt. A module that was
  // still booting for the first query is usually back for the second; a module
  // that answers neither leaves the clear honestly unconfirmed.
  static const Duration _confirmRetryDelay = Duration(milliseconds: 800);

  // A Mode 03 read can span several ISO-TP frames (up to ~half a second of
  // wire time on a busy CAN bus), so it needs a longer window than a
  // single-frame live PID read to gather every frame before the '>' prompt.
  static const Duration _readDtcsMinTimeout = Duration(milliseconds: 3000);

  // A chassis/ABS scan is slower again: each candidate address costs a round
  // of ATSH/ATCRA/flow-control setup before the request itself, and a UDS
  // 19 02 reply is routinely multi-frame. Non-engine modules are also simply
  // less prompt than the engine ECU, which is polled continuously and stays
  // warm on the bus.
  static const Duration _chassisScanMinTimeout = Duration(milliseconds: 5000);

  // ══════════════════════════════════════════════════════════════════════════
  // WIFI CONNECTION
  // ══════════════════════════════════════════════════════════════════════════
  Future<bool> connectWifi({
    String ip = '192.168.0.10',
    int port = 35000,
  }) async {
    _setStatus(ConnectionStatus.connecting, 'Connecting to $ip:$port…');
    _resetDiagnostics();
    _beginSession('wifi');

    try {
      _wifiSocket =
          await Socket.connect(ip, port, timeout: _wifiConnectTimeout);
      _wifiSocket!.encoding = latin1;

      _wifiBuffer.clear();
      _wifiSub?.cancel();
      _wifiSub = _wifiSocket!.listen(
        _onWifiRawBytes,
        onError: (e) {
          _lastError = e.toString();
          if (isConnected) _handleTransportDrop('Wi-Fi stream error');
        },
        onDone: () {
          if (isConnected) _handleTransportDrop('Wi-Fi connection closed');
        },
        cancelOnError: false,
      );

      _transport = ConnectionType.wifi;
      _setStatus(ConnectionStatus.connecting, 'Initialising ELM327…');

      final initOk = await _initElm327WithRetry();
      if (!initOk) {
        await disconnect();
        _setStatus(ConnectionStatus.error,
            'ELM327 did not respond. Check adapter power / IP.');
        return false;
      }

      _setConnected('Connected via Wi-Fi · $ip',
          'Adapter connected via Wi-Fi · bike not answering');
      _startPolling();
      return true;
    } on SocketException catch (e) {
      _setStatus(ConnectionStatus.error, 'Wi-Fi connection failed');
      _lastError = e.message;
      return false;
    } catch (e) {
      _setStatus(ConnectionStatus.error, 'Error: $e');
      _lastError = e.toString();
      return false;
    }
  }

  void _onWifiRawBytes(List<int> bytes) {
    try {
      final chunk = latin1.decode(bytes);
      _wifiBuffer.write(chunk);
      _tryResolveBuffer(isWifi: true);
    } catch (e) {
      debugPrint('[ObdService] WiFi decode error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BLUETOOTH CONNECTION
  // ══════════════════════════════════════════════════════════════════════════
  Future<bool> connectBluetooth(BtDevice device) async {
    _setStatus(ConnectionStatus.connecting, 'Connecting via Bluetooth…');
    _resetDiagnostics();
    _beginSession('bluetooth');

    final ok = await _btService.connect(device);
    if (!ok) {
      _setStatus(ConnectionStatus.error, _btService.statusMessage);
      return false;
    }

    _btBuffer.clear();
    _btDataSub?.cancel();
    _btDataSub = _btService.dataStream.listen(
      _onBtRawChunk,
      onError: (e) {
        _lastError = e.toString();
        if (isConnected) _handleTransportDrop('Bluetooth stream error: $e');
      },
      onDone: () {
        if (isConnected) _handleTransportDrop('Bluetooth connection closed');
      },
      cancelOnError: false,
    );

    _transport = ConnectionType.bluetooth;
    _setStatus(ConnectionStatus.connecting, 'Initialising ELM327…');

    final initOk = await _initElm327WithRetry();
    if (!initOk) {
      await disconnect();
      _setStatus(ConnectionStatus.error,
          'ELM327 did not respond over Bluetooth. Try reconnecting.');
      return false;
    }

    _setConnected('Connected via BT · ${device.name}',
        'Adapter connected via BT · bike not answering');
    _startPolling();
    return true;
  }

  /// Start a fresh session: nothing from a previous connection — fault lists,
  /// read results, detected protocol — may carry over to this one.
  void _beginSession(String transport) {
    _session = ObdSession(transport: transport);
    _clearFaultResults();
    recorder?.beginSession(transport: transport);
  }

  /// Forget every fault result. Used whenever the link drops or a new session
  /// starts: an old list shown after a reconnect looks live and may not even
  /// belong to the bike now plugged in.
  void _clearFaultResults() {
    _dtcCodes = [];
    _dtcCodesReadAt = null;
    _lastEngineRead = null;
    _engineReport = null;
    _coreCountMismatch = null;
    cancelEngineExtras();
    _chassisDtcCodes = [];
    _chassisScanOutcome = ChassisScanOutcome.idle;
    _chassisRespondingModule = '';
    _chassisReadAt = null;
  }

  /// Mark the adapter connected. The status line only says "Connected" once
  /// the vehicle itself has answered; until then it says the bike is not
  /// answering, which is the truth with the ignition off.
  void _setConnected(String answeredMessage, String silentMessage) {
    _connectedStatusMessage = answeredMessage;
    _setStatus(ConnectionStatus.connected,
        vehicleAnswered ? answeredMessage : silentMessage);
  }

  /// The vehicle gave a positive reply. Upgrades the status line the first
  /// time it happens (e.g. the rider switched the ignition on after
  /// connecting).
  void _markVehicleAnswered() {
    final s = _session;
    if (s == null || s.vehicleAnswered) return;
    s.vehicleAnswered = true;
    if (_status == ConnectionStatus.connected &&
        _connectedStatusMessage.isNotEmpty) {
      _statusMessage = _connectedStatusMessage;
    }
    notifyListeners();
  }

  void _onBtRawChunk(String chunk) {
    if (chunk.isEmpty) return;
    try {
      _btBuffer.write(chunk);
      _tryResolveBuffer(isWifi: false);
    } catch (e) {
      debugPrint('[ObdService] BT buffer error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UNIFIED TERMINATOR RESOLUTION
  // Dart is the SINGLE source of truth for detecting the ELM327 prompt '>'.
  // Both WiFi and Bluetooth funnel into this exact same logic.
  // ══════════════════════════════════════════════════════════════════════════
  void _tryResolveBuffer({required bool isWifi}) {
    final buffer = isWifi ? _wifiBuffer : _btBuffer;
    final raw = buffer.toString();

    if (!raw.contains('>')) return; // Not yet terminated — wait for more data

    // Extract everything up to (and including) the first '>' prompt.
    final idx = raw.indexOf('>');
    final frame = raw.substring(0, idx);

    // Keep any leftover bytes after '>' for the next command's buffer
    final remainder = raw.substring(idx + 1);
    buffer.clear();
    if (remainder.isNotEmpty) buffer.write(remainder);

    final cleaned = _sanitizeResponse(frame);
    _logWire('RX<', frame);

    final pending = isWifi ? _wifiPendingCmd : _btPendingCmd;
    if (pending != null && !pending.isCompleted) {
      pending.complete(cleaned);
      if (isWifi) {
        _wifiPendingCmd = null;
      } else {
        _btPendingCmd = null;
      }
    }
    // If no pending completer (e.g. stray data), we simply discard the frame.
    // This prevents "ghost" responses from being misattributed to the wrong command.
  }

  /// Strip echoes, CR/LF, excess whitespace. Never throw.
  String _sanitizeResponse(String raw) {
    try {
      final lines = raw.replaceAll('\r', '\n').split('\n');
      final out = <String>[];
      for (final line in lines) {
        final t = line.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
        if (t.isNotEmpty) out.add(t);
      }
      return out.join('\n');
    } catch (_) {
      return '';
    }
  }

  String _stripCanHeaderForLivePid(String response) {
    try {
      if (response.isEmpty) return response;
      final hexToken = RegExp(r'^[0-9A-Fa-f]+$');

      for (final rawLine in response.split(RegExp(r'[\r\n]+'))) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        var tokens = line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

        if (tokens.length == 1 && hexToken.hasMatch(tokens.first)) {
          final h = tokens.first.toUpperCase();
          if (h.length.isOdd && h.length >= 5) {
            tokens = [h.substring(0, 3)];
            for (var i = 3; i + 2 <= h.length; i += 2) {
              tokens.add(h.substring(i, i + 2));
            }
          } else {
            tokens = [for (var i = 0; i + 2 <= h.length; i += 2) h.substring(i, i + 2)];
          }
        }

        if (tokens.length >= 2 && (tokens.first.length == 3 || tokens.first.length == 8) && hexToken.hasMatch(tokens.first)) {
          tokens = tokens.sublist(1);
        }

        if (tokens.length >= 2) {
          final b0 = int.tryParse(tokens.first, radix: 16);
          final b1 = int.tryParse(tokens[1], radix: 16);
          if (b0 != null && b1 != null && (b0 >> 4) == 0x0 && (b1 == 0x41 || b1 == 0x42 || b1 == 0x49)) {
            tokens = tokens.sublist(1);
          }
        }

        if (tokens.isEmpty) continue;
        final head = int.tryParse(tokens.first, radix: 16);
        if (head == null) continue;
        if (head == 0x41 || head == 0x42 || head == 0x49 || head == 0x7F) {
          return tokens.join(' ');
        }
      }
      return response;
    } catch (_) {
      return response;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TRANSPORT DROP HANDLER
  // ══════════════════════════════════════════════════════════════════════════
  void _handleTransportDrop(String reason) {
    _stopPolling();
    _completeAllPending('DISCONNECTED');
    _data = VehicleData.empty();
    _clearFaultResults();
    _session = null;
    recorder?.endSession(reason: 'link dropped');
    _setStatus(ConnectionStatus.disconnected, reason);
  }

  void _onBtServiceChanged() {
    if (_transport == ConnectionType.bluetooth &&
        _status == ConnectionStatus.connected &&
        !_btService.isConnected) {
      _handleTransportDrop('Bluetooth link lost');
    }
  }

  void _completeAllPending(String value) {
    if (_wifiPendingCmd != null && !_wifiPendingCmd!.isCompleted) {
      _wifiPendingCmd!.complete(value);
    }
    _wifiPendingCmd = null;
    if (_btPendingCmd != null && !_btPendingCmd!.isCompleted) {
      _btPendingCmd!.complete(value);
    }
    _btPendingCmd = null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ELM327 INITIALISATION — with adaptive retry
  // ══════════════════════════════════════════════════════════════════════════
  Future<bool> _initElm327WithRetry() async {
    const maxAttempts = 3;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      _cmdTimeout = Duration(
          seconds: (_cmdTimeoutMin.inSeconds +
                  (attempt - 1) *
                      ((_cmdTimeoutMax.inSeconds - _cmdTimeoutMin.inSeconds) /
                              (maxAttempts - 1))
                          .round())
              .clamp(_cmdTimeoutMin.inSeconds, _cmdTimeoutMax.inSeconds));

      _setStatus(ConnectionStatus.connecting,
          'Initialising ELM327 (attempt $attempt/$maxAttempts, timeout ${_cmdTimeout.inSeconds}s)…');

      final ok = await _runInitSequence();
      if (ok) {
        _cmdTimeout = _cmdTimeoutMin; // reset for normal polling
        return true;
      }

      if (attempt < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  Future<bool> _runInitSequence() async {
    try {
      // Init always starts from a clean gate — see _resetDiagnostics().
      _linkSynced = true;
      _adapterWedged = false;
      final banner =
          await _send(ObdPids.reset, delay: const Duration(milliseconds: 300));
      final identity = _adapterIdentityFrom(banner);
      if (identity != null) {
        _session?.adapterIdentity = identity;
        recorder?.recordNote('adapter identity (ATZ): $identity');
      }
      await Future.delayed(const Duration(milliseconds: 500));

      final echo = await _send(ObdPids.echoOff);
      if (_isDeadResponse(echo)) return false;

      await _send(ObdPids.linefeedsOff);
      await _send(ObdPids.spacesOff);
      await _send(ObdPids.headersOff);

      final proto = await _send(ObdPids.autoProtocol);
      if (_isDeadResponse(proto)) return false;

      final at = await _send('ATAT1');
      if (_isDeadResponse(at)) debugPrint('[ObdService] ATAT1 unsupported');
      final st = await _send('ATST32');
      if (_isDeadResponse(st)) debugPrint('[ObdService] ATST32 unsupported');

      // The adapter answering its set-up commands proves nothing about the
      // bike. Only a positive reply to the supported-PIDs request (41 00)
      // does, so that — not "init finished" — is what marks the vehicle as
      // answering. A silent ECU (ignition off, wrong cable, a bike the adapter
      // cannot talk to) leaves the session at vehicleAnswered == false, and no
      // fault read can then pass for an all-clear.
      for (var attempt = 0; attempt < 2; attempt++) {
        final probe = await _send('0100');
        if (_isPositiveSupportedPidsReply(probe)) {
          _markVehicleAnswered();
          break;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final dpn = await _send('ATDPN');
      if (!_isDeadResponse(dpn)) {
        _session?.protocol = ObdProtocol.fromAtdpn(dpn);
        recorder?.recordNote('protocol (ATDPN): ${_session?.protocol}');
      }
      return true;
    } catch (e) {
      debugPrint('[ObdService] Init sequence exception: $e');
      return false;
    }
  }

  /// The adapter's identity line from its `ATZ` banner (e.g. `ELM327 v1.5`),
  /// or null when the reply carried none.
  String? _adapterIdentityFrom(String banner) {
    if (_isDeadResponse(banner)) return null;
    for (final line in banner.split(RegExp(r'[\r\n]+'))) {
      final t = line.trim();
      if (t.isNotEmpty && t.toUpperCase() != 'OK' && t != 'ATZ') return t;
    }
    return null;
  }

  /// Is this a positive reply to `01 00` — the vehicle, not the adapter,
  /// saying which PIDs it supports? Accepts headers on or off, spaces on or
  /// off, and a leading `SEARCHING...` line.
  bool _isPositiveSupportedPidsReply(String reply) {
    final upper = reply.toUpperCase();
    if (upper.contains('NO DATA') ||
        upper.contains('UNABLE') ||
        upper.contains('ERROR') ||
        upper.contains('TIMEOUT') ||
        upper.contains('DISCONNECTED')) {
      return false;
    }
    for (final line in upper.split(RegExp(r'[\r\n]+'))) {
      if (line.contains('SEARCHING')) continue;
      final payload = _stripCanHeaderForLivePid(line.trim());
      final compact = payload.replaceAll(RegExp(r'\s+'), '');
      if (compact.startsWith('4100') && compact.length >= 12) return true;
    }
    return false;
  }

  /// Did this AT command take effect?
  ///
  /// Deliberately stricter than [_classifyReply] and deliberately NOT changed
  /// to match it. This asks a configuration question, not a link question: a
  /// healthy ELM327 always answers an AT command with `OK` or a value, so for
  /// an AT command an empty payload really is anomalous and must not be taken
  /// as "applied". [_classifyReply]'s "empty is still an answer" rule is about
  /// OBD mode replies, where the ECU legitimately has nothing to say.
  bool _isDeadResponse(String r) {
    if (r.isEmpty) return true;
    final upper = r.toUpperCase();
    return upper.contains('TIMEOUT') ||
        upper == 'DISCONNECTED' ||
        upper.contains('ERROR');
  }

  /// The single place that decides what a reply proves about the LINK.
  ///
  /// Every site that needs to know "is the connection still there?" asks this
  /// instead of pattern-matching the reply string itself, so the answer cannot
  /// drift between commands. Three rules, in order:
  ///
  ///  1. A hard transport verdict — the layer below reported the socket gone,
  ///     or the write itself threw — is a link failure. Matched on the whole
  ///     string, not a substring, so an ECU that answers `BUS INIT: ERROR` or
  ///     `CAN ERROR` over a working link is not mistaken for a dead socket;
  ///     that is a command failure and the per-command checks still catch it.
  ///  2. Anything else that came back is proof of life, INCLUDING an empty
  ///     payload. The adapter emitting a bare `>` prompt answered us. This is
  ///     the rule the service previously lacked, and it is general: it holds
  ///     for an unsupported live PID, for a Mode 04 erase acknowledged with no
  ///     payload, and for any future command whose correct reply is silence.
  ///  3. Only a timeout is ambiguous, and it is resolved with evidence rather
  ///     than assumption: if the link has delivered a reply inside
  ///     [_linkProofWindow] and has not missed [_deadLinkTimeouts] in a row,
  ///     the command did not answer but the connection is fine. Otherwise the
  ///     link has stopped proving itself and the failure is real.
  ObdReplyClass _classifyReply(String r) {
    final upper = r.toUpperCase().trim();

    if (upper == 'DISCONNECTED' || upper == 'ERROR') {
      return ObdReplyClass.linkFailure;
    }
    if (upper != 'TIMEOUT') return ObdReplyClass.answered;

    // The hard backstop, checked first and never bypassed: a link that has
    // missed this many replies in a row is dead regardless of any credit a
    // foreground sequence is holding.
    if (_consecutiveTimeouts >= _deadLinkTimeouts) return ObdReplyClass.linkFailure;

    // A foreground sequence that already proved the link alive carries that
    // proof across its own remaining commands — see _linkProofCreditUntil.
    if (_linkProofCredited) return ObdReplyClass.noAnswer;

    final last = _lastGoodResponseAt;
    if (last == null) return ObdReplyClass.linkFailure;
    if (DateTime.now().difference(last) > _linkProofWindow) {
      return ObdReplyClass.linkFailure;
    }
    return ObdReplyClass.noAnswer;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMMAND SEND — routes to correct transport
  // ══════════════════════════════════════════════════════════════════════════
  Future<String> _send(String cmd, {Duration? delay}) async {
    if (!_linkSynced) {
      // A blocked write must still count toward the dead-link detector.
      // Without this, _consecutiveTimeouts freezes and _pollLoop's
      // >= 6 check can never fire, leaving the UI stuck on "Connected".
      _consecutiveTimeouts++;
      // The command itself is not printed: no adapter traffic in logs.
      debugPrint('[ObdService] BLOCKED write — link not synced');
      return 'TIMEOUT';
    }
    if (delay != null) await Future.delayed(delay);
    return await _sendRaw(cmd);
  }

  Future<String> _sendRaw(String cmd) async {
    try {
      if (_transport == ConnectionType.wifi) {
        return await _sendWifi(cmd);
      } else {
        return await _sendBt(cmd);
      }
    } catch (e) {
      return 'ERROR';
    }
  }

  Future<bool> _recoverAdapter() async {
    debugPrint('[ObdService] attempting adapter recovery…');
    _linkSynced = true;
    await Future.delayed(const Duration(milliseconds: 600));

    final saved = _cmdTimeout;
    _cmdTimeout = const Duration(seconds: 2);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final r = await _sendRaw('');
        // A bare CR asks the adapter one question — "are you there?" — and a
        // bare '>' prompt is a complete yes. Judged with _isDeadResponse()
        // this probe could never succeed on a healthy adapter, because that
        // check calls an empty payload dead; the recovery it gates was
        // therefore always forced down the slower ATZ path.
        if (_classifyReply(r) == ObdReplyClass.answered) {
          debugPrint('[ObdService] adapter responded to CR — resynced');
          _adapterWedged = false;
          _linkSynced = true;
          return true;
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }

      _cmdTimeout = const Duration(seconds: 5);
      final z = await _sendRaw(ObdPids.reset);
      await Future.delayed(const Duration(milliseconds: 900));
      if (!_isDeadResponse(z)) {
        debugPrint('[ObdService] adapter reset — re-running init');
        final ok = await _runInitSequence();
        _adapterWedged = !ok;
        _linkSynced = ok;
        return ok;
      }

      debugPrint('[ObdService] adapter unresponsive — power cycle required');
      _adapterWedged = true;
      _linkSynced = false;
      _handleTransportDrop('Adapter stopped responding. Unplug it, wait 5 seconds, plug it back in and reconnect.');
      return false;
    } finally {
      _cmdTimeout = saved;
    }
  }

  Future<bool> _enableDtcHeaders() async {
    if (!_linkSynced) return false;
    final s = await _send('ATS1');
    if (_isDeadResponse(s)) return false;
    final h = await _send('ATH1');
    if (_isDeadResponse(h)) {
      await _send(ObdPids.spacesOff);
      return false;
    }
    return true;
  }

  Future<void> _restoreLiveHeaders() async {
    if (!_linkSynced) return;
    await _send(ObdPids.headersOff);
    await _send(ObdPids.spacesOff);
  }

  Future<void> _repairLiveMode() async {
    final now = DateTime.now();
    if (_lastHeaderRepairAt != null && now.difference(_lastHeaderRepairAt!) < const Duration(seconds: 20)) return;
    _lastHeaderRepairAt = now;
    _consecutiveParseFailures = 0;
    if (!_linkSynced) {
      await _recoverAdapter();
      return;
    }
    await _send(ObdPids.headersOff);
    await _send(ObdPids.spacesOff);
  }

  Future<String> _sendWifi(String cmd) async {
    if (_wifiSocket == null) return 'DISCONNECTED';

    _wifiBuffer.clear();
    _wifiPendingCmd = Completer<String>();

    try {
      _logWire('TX>', cmd);
      _wifiSocket!.write('$cmd\r');
      await _wifiSocket!.flush();
    } catch (e) {
      _wifiPendingCmd = null;
      return 'ERROR';
    }

    final completer = _wifiPendingCmd!;
    return completer.future.timeout(_cmdTimeout, onTimeout: () {
      _consecutiveTimeouts++;
      // Close the write gate only when the link has actually stopped proving
      // itself. Slamming it shut on every single missed reply is what turned
      // one slow command into a cascade: the next _send() was then discarded
      // unsent and returned a synthetic 'TIMEOUT' of its own. The dead-link
      // detector above is untouched, so a link that really is gone still
      // trips it on the same count it always did.
      if (_classifyReply('TIMEOUT') == ObdReplyClass.linkFailure) {
        _linkSynced = false;
      }
      if (_wifiPendingCmd == completer) _wifiPendingCmd = null;
      return 'TIMEOUT';
    }).then((value) {
      // Keyed on whether bytes came back, not on how many. An empty payload
      // is a delivered reply and proves the link as well as a full one does.
      if (_classifyReply(value) == ObdReplyClass.answered) {
        _consecutiveTimeouts = 0;
        _linkSynced = true;
        _adapterWedged = false;
        _lastGoodResponseAt = DateTime.now();
      }
      return value;
    });
  }

  Future<String> _sendBt(String cmd) async {
    if (!_btService.isConnected) return 'DISCONNECTED';

    _btBuffer.clear();
    _btPendingCmd = Completer<String>();

    _logWire('TX>', cmd);
    final ok = await _btService.write(cmd);
    if (!ok) {
      _btPendingCmd = null;
      return 'ERROR';
    }

    final completer = _btPendingCmd!;
    return completer.future.timeout(_cmdTimeout, onTimeout: () {
      _consecutiveTimeouts++;
      // Same rule as the Wi-Fi path — see _sendWifi() for why the write gate
      // is no longer closed on a single missed reply.
      if (_classifyReply('TIMEOUT') == ObdReplyClass.linkFailure) {
        _linkSynced = false;
      }
      if (_btPendingCmd == completer) _btPendingCmd = null;
      return 'TIMEOUT';
    }).then((value) {
      // Keyed on whether bytes came back, not on how many. An empty payload
      // is a delivered reply and proves the link as well as a full one does.
      if (_classifyReply(value) == ObdReplyClass.answered) {
        _consecutiveTimeouts = 0;
        _linkSynced = true;
        _adapterWedged = false;
        _lastGoodResponseAt = DateTime.now();
      }
      return value;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // POLLING LOOP
  // ══════════════════════════════════════════════════════════════════════════
  void _startPolling() {
    if (_isPolling) return;
    _isPolling = true;
    _pidIndex = 0;
    unawaited(_pollLoop());
  }

  void _stopPolling() {
    _isPolling = false;
  }

  Future<void> _pollLoop() async {
    while (_isPolling && isConnected) {
      if (_pollLocked) {
        // A foreground command (e.g. clearDtcs) owns the socket right now —
        // back off instead of writing a PID request on top of it.
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }

      // The link gate closed on a previous timeout. Try to reopen it before
      // writing anything — otherwise every send below is silently discarded
      // and the dashboard freezes while still reporting "Connected".
      if (!_linkSynced) {
        // Bound the retries. A half-wedged adapter can answer a bare CR
        // while never servicing a PID, which would otherwise loop forever
        // with a frozen dashboard still showing "Connected".
        if (_recoveryAttempts >= 3) {
          _handleTransportDrop('Adapter stopped responding');
          return;
        }
        _recoveryAttempts++;
        final recovered = await _recoverAdapter();
        // _recoverAdapter already calls _handleTransportDrop when it gives up.
        if (!recovered) return;
        continue;
      }

      final pid = _pids[_pidIndex % _pids.length];
      _pidIndex++;

      try {
        if (pid.command == ObdPids.voltage.command) {
          await _pollBatteryVoltage();
        } else {
          final response = await _send(pid.command);

          if (_isUsableResponse(response)) {
            final value = ObdParser.parsePid(pid.command, _stripCanHeaderForLivePid(response));
            if (value != null) {
              _markVehicleAnswered();
              _updateData(pid.command, value);
              _consecutiveParseFailures = 0;
              _recoveryAttempts = 0;
            } else {
              _consecutiveParseFailures++;
              if (_consecutiveParseFailures >= 5) await _repairLiveMode();
            }
          }
        }

        // If we've had too many consecutive timeouts, the link is likely dead.
        if (_consecutiveTimeouts >= _deadLinkTimeouts) {
          debugPrint(
              '[ObdService] $_deadLinkTimeouts consecutive timeouts — link considered dead');
          _handleTransportDrop('Lost connection to adapter (no response)');
          return;
        }
      } catch (e) {
        debugPrint('[ObdService] Poll loop exception: $e');
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // ── Battery voltage: Mode 01 PID 0142 primary, AT RV secondary ───────────
  // PID 0142 (Control Module Voltage) comes straight from the ECU's own
  // sense line, bypassing the ELM327's ADC entirely, so it's the source of
  // truth whenever a vehicle implements it. Most don't, so the fallback is
  // the adapter's own "AT RV" Pin-16 read — which on cheap/uncalibrated
  // clone adapters can under-report by a roughly constant factor.
  Future<void> _pollBatteryVoltage() async {
    final pidResponse = await _send(ObdPids.voltage.command);
    if (_isUsableResponse(pidResponse)) {
      final pidValue = ObdParser.parsePid(
          ObdPids.voltage.command, _stripCanHeaderForLivePid(pidResponse));
      // Sanity band, not a narrow "expected normal" band: PID 0142 is
      // ECU-reported, so a low-but-plausible value here is real fault data
      // (dying battery/alternator), not adapter noise — it must not be
      // discarded or handed to the clone-compensation heuristic below.
      if (pidValue != null && pidValue >= _voltageNoiseFloor && pidValue <= _voltageNoiseCeiling) {
        _data = _data.copyWith(batteryVoltage: pidValue);
        notifyListeners();
        return;
      }
    }

    final rvResponse = await _send(ObdPids.readVoltage);
    double? value = ObdParser.parseAtRvVoltage(rvResponse);
    if (value == null) return;

    // Noise guard: implausible readings are line noise, not data.
    if (value < _voltageNoiseFloor || value > _voltageNoiseCeiling) return;

    // Clone ADC compensation: an uncalibrated divider resistor under-reports
    // by a roughly constant factor. Only apply it while the engine is
    // confirmed running (RPM > 500, alternator charging) and the raw reading
    // sits in the "dead battery while running" band that's characteristic of
    // divider miscalibration rather than a real fault. Scale multiplicatively
    // rather than clamp to a fixed "normal" value, so a genuine failing
    // alternator/battery still reads low after correction instead of being
    // masked as healthy.
    final rpm = _data.rpm;
    if (value >= 8.0 && value <= 11.0 && rpm != null && rpm > 500) {
      value = value * 1.35;
    }

    _data = _data.copyWith(batteryVoltage: value);
    notifyListeners();
  }

  static const double _voltageNoiseFloor = 6.0;
  static const double _voltageNoiseCeiling = 18.0;

  bool _isUsableResponse(String r) {
    if (r.isEmpty) return false;
    final upper = r.toUpperCase();
    if (upper.contains('TIMEOUT')) return false;
    if (upper.contains('ERROR')) return false;
    if (upper.contains('NO DATA')) return false;
    if (upper.contains('NODATA')) return false;
    if (upper.contains('UNABLE')) return false;
    if (upper.contains('DISCONNECTED')) return false;
    if (upper.contains('STOPPED')) return false;
    if (upper.contains('SEARCHING')) return false;
    if (upper.contains('BUS INIT')) return false;
    return true;
  }

  bool _isUsableDtcResponse(String r) {
    if (r.isEmpty) return false;
    final upper = r.toUpperCase();

    if (upper.contains('TIMEOUT') || upper.contains('DISCONNECTED') ||
        upper.contains('UNABLE TO CONNECT') || upper.contains('BUS INIT: ERROR') ||
        upper.contains('CAN ERROR')) {
      return false;
    }

    final lines = upper.split(RegExp(r'[\r\n]+'));
    final hasNoData = lines.any((l) => l.trim() == 'NO DATA');
    if (hasNoData && lines.length <= 2) return true;

    final serviceLine = RegExp(r'\b4[37A]\b|4[37A][0-9A-F]{2}');
    return lines.any((l) => serviceLine.hasMatch(l.replaceAll(' ', '')) || serviceLine.hasMatch(l));
  }

  void _updateData(String command, double value) {
    switch (command) {
      case '010C':
        _data = _data.copyWith(rpm: value);
        break;
      case '010D':
        _data = _data.copyWith(speed: value);
        break;
      case '0105':
        _data = _data.copyWith(coolantTemp: value);
        break;
      case '010F':
        _data = _data.copyWith(intakeTemp: value);
        break;
      case '0111':
        _data = _data.copyWith(throttle: value);
        break;
      case '0104':
        _data = _data.copyWith(engineLoad: value);
        break;
      case '012F':
        _data = _data.copyWith(fuelLevel: value);
        break;
      case '010A':
        _data = _data.copyWith(fuelPressure: value);
        break;
      case '0110':
        _data = _data.copyWith(maf: value);
        break;
      case '010B':
        _data = _data.copyWith(manifoldPressure: value);
        break;
      case '010E':
        _data = _data.copyWith(timingAdvance: value);
        break;
      case '0142':
        _data = _data.copyWith(batteryVoltage: value);
        break;
      case '0106':
        _data = _data.copyWith(shortFuelTrim: value);
        break;
      case '0107':
        _data = _data.copyWith(longFuelTrim: value);
        break;
      case '011F':
        _data = _data.copyWith(runTime: value);
        break;
      default:
        break;
    }
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DTC READ / CLEAR
  // ══════════════════════════════════════════════════════════════════════════
  /// Read engine fault codes and return the codes the engine computer
  /// reported — empty unless it actually answered. Prefer [readEngineDtcs],
  /// which says WHY a read produced no codes.
  ///
  /// The Mode 03 core only: the optional extras are not run from here.
  Future<List<DtcCode>> readDtcs() async {
    final result = await readEngineDtcs(withExtras: false);
    return result is EngineAnswered ? result.codes : const <DtcCode>[];
  }

  Future<EngineDtcRead>? _engineReadInFlight;

  /// One engine fault-code read (Mode 03), classified honestly.
  ///
  /// Returns [EngineAnswered] only for a positive `43` response — the one
  /// case in which an empty list means "no stored faults". `NO DATA`,
  /// timeouts, bare prompts, `UNABLE TO CONNECT`, bus errors and `?` are
  /// [EngineNoAnswer]; a module that keeps answering "response pending" is
  /// [EngineNoAnswer] with [EngineNoAnswerReason.moduleBusy]; `7F 03` is
  /// [EngineRefused]; a dead link is [EngineLinkLost]; a K-line bus is
  /// [EngineKLineGated] while [kKLineFaultReadingEnabled] is false.
  ///
  /// A failed read never touches [dtcCodes]: the last answered list stays,
  /// with [dtcCodesReadAt], for the screen to show as an older result.
  ///
  /// The returned future completes with the CORE result as soon as it is
  /// known. When the vehicle answered (or refused) and [withExtras] is true,
  /// the optional extras — Mode 07 and 0A, PID 01 01, RPM, voltage, VIN —
  /// then run on the same job, inside [kEngineReadBudget], and land in
  /// [engineReport]. They re-run only when [forceExtras] (a manual read), on
  /// the first answered read of a connection, when the code list changed, or
  /// after [kEngineExtrasRefresh]; the 5-second auto-read otherwise leaves
  /// them alone. [cancelEngineExtras] stops them.
  ///
  /// A call made while a CORE read is in progress shares that read. A call
  /// made while only the previous read's extras are still running asks them
  /// to hand the link back, then reads afresh — it never gets the previous
  /// result back as if it were new.
  Future<EngineDtcRead> readEngineDtcs(
      {bool withExtras = true, bool forceExtras = false}) async {
    if (!isConnected) return EngineLinkLost(DateTime.now());
    final inFlight = _engineReadInFlight;
    if (inFlight != null) return inFlight;
    if (_engineJob != null) {
      await _yieldEngineExtras();
      if (!isConnected) return EngineLinkLost(DateTime.now());
      final started = _engineReadInFlight;
      if (started != null) return started;
    }
    final core = Completer<EngineDtcRead>();
    _engineReadInFlight = core.future;
    core.future.whenComplete(() {
      if (identical(_engineReadInFlight, core.future)) _engineReadInFlight = null;
    });
    late final Future<void> job;
    job = _runEngineRead(core, withExtras: withExtras, forceExtras: forceExtras)
        .whenComplete(() {
      if (identical(_engineJob, job)) _engineJob = null;
    });
    _engineJob = job;
    return core.future;
  }

  /// Send one request through the shared response-pending helper.
  ///
  /// [recoverySelfHandled]: the caller runs its own adapter recovery after a
  /// timeout (the core read and the ABS sweep do), so the helper only drains
  /// on a busy give-up and does not interrupt the adapter itself.
  Future<PendingResult> _sendWithPending(String request,
      {required PendingPolicy policy,
      bool recoverySelfHandled = false,
      bool Function()? isCancelled}) {
    final serviceId = int.tryParse(request.substring(0, 2), radix: 16) ?? 0;
    return sendWithPendingHandling(
      request: request,
      serviceId: serviceId,
      policy: policy,
      isCancelled: isCancelled,
      send: (cmd, window) async {
        final saved = _cmdTimeout;
        _cmdTimeout = window;
        try {
          return await _send(cmd);
        } finally {
          _cmdTimeout = saved;
        }
      },
      flush: ({required bool afterTimeout}) async {
        if (afterTimeout && recoverySelfHandled) return;
        await _flushAdapter(interrupt: afterTimeout);
      },
      onAdapterPassesPending: () {
        final s = _session;
        if (s == null || s.adapterPassesPending) return;
        s.adapterPassesPending = true;
        recorder?.recordNote('adapter passes response-pending frames through');
      },
    );
  }

  /// Make sure nothing from an abandoned request can reach the next command.
  ///
  /// After a timeout the adapter may still be waiting on the bus; any
  /// character stops an ELM327 mid-request and it answers with a prompt, so a
  /// bare carriage return is sent and its reply consumed. Then a short settle
  /// lets any late bytes arrive, and both buffers are emptied.
  Future<void> _flushAdapter({required bool interrupt}) async {
    if (!isConnected) return;
    if (interrupt && _linkSynced) {
      final saved = _cmdTimeout;
      _cmdTimeout = faultTiming.extraCommandWindow;
      try {
        await _sendRaw('');
      } finally {
        _cmdTimeout = saved;
      }
    }
    await Future<void>.delayed(faultTiming.flushSettle);
    _btBuffer.clear();
    _wifiBuffer.clear();
  }

  /// Ask a running extras job to stop at its next safe point, and wait —
  /// bounded — until it has put the adapter back and released the link.
  /// Called before any other foreground operation takes the link.
  Future<void> _yieldEngineExtras() async {
    final job = _engineJob;
    if (job == null) return;
    _linkWaiters++;
    final cap = faultTiming.extraCommandWindow * 4 + const Duration(seconds: 1);
    try {
      await job.timeout(cap);
    } catch (_) {
      // Bounded on purpose: never let a stuck extra hold another operation.
    } finally {
      _linkWaiters--;
    }
  }

  Future<void> _runEngineRead(Completer<EngineDtcRead> core,
      {required bool withExtras, required bool forceExtras}) async {
    _acquirePollLock();
    await _waitForLinkIdle();

    // The budget runs from the moment this read has the adapter to itself.
    final clock = Stopwatch()..start();
    final previousTimeout = _cmdTimeout;
    var headersOn = false;
    var stWidened = false;

    EngineDtcRead finishCore(EngineDtcRead r) {
      final result = _finishEngineRead(r);
      if (!core.isCompleted) core.complete(result);
      return result;
    }

    try {
      final result = await _runEngineCore(
        finish: finishCore,
        onHeaders: (h) => headersOn = h,
        onStWidened: (w) => stWidened = w,
        clock: clock,
      );
      if (withExtras && _shouldRunExtras(result, force: forceExtras)) {
        await _runEngineExtras(clock);
      }
    } catch (e) {
      debugPrint('[ObdService] engine read failed (${e.runtimeType})');
      if (!core.isCompleted) {
        finishCore(
            EngineNoAnswer(EngineNoAnswerReason.adapterError, DateTime.now()));
      }
    } finally {
      _cmdTimeout = previousTimeout;
      if (stWidened && _linkSynced) await _send('ATST32');
      if (headersOn) await _restoreLiveHeaders();
      _cmdTimeout = previousTimeout;
      _releasePollLock();
      if (!core.isCompleted) {
        core.complete(_lastEngineRead ??
            EngineNoAnswer(EngineNoAnswerReason.adapterError, DateTime.now()));
      }
    }
  }

  /// The Mode 03 core. Returns the result already passed to [finish].
  Future<EngineDtcRead> _runEngineCore({
    required EngineDtcRead Function(EngineDtcRead) finish,
    required void Function(bool) onHeaders,
    required void Function(bool) onStWidened,
    required Stopwatch clock,
  }) async {
      if (!_linkSynced) {
        final recovered = await _recoverAdapter();
        if (!recovered) return finish(EngineLinkLost(DateTime.now()));
      }

      if (_cmdTimeout < _readDtcsMinTimeout) _cmdTimeout = _readDtcsMinTimeout;

      onHeaders(await _enableDtcHeaders());
      final stResp = await _send('ATST7D');
      onStWidened(!_isDeadResponse(stResp));

      // Through the shared response-pending helper: a window long enough for
      // an adapter that waits internally, and a re-send for one that passes
      // the pending frame through. Bounded by the read's own budget, and never
      // by less than one full attempt.
      PendingPolicy corePolicy() {
        final left = faultTiming.engineReadBudget - clock.elapsed;
        return faultTiming.pendingPolicy(
            overall: left < faultTiming.pendingPerAttempt
                ? faultTiming.pendingPerAttempt
                : left);
      }

      final first = await _sendWithPending(ObdPids.readDtcs,
          policy: corePolicy(), recoverySelfHandled: true);
      final busy = first is! PendingAnswered;
      final response = first is PendingAnswered ? first.reply : '';
      final linkFailed =
          !busy && _classifyReply(response) == ObdReplyClass.linkFailure;

      if (response == 'TIMEOUT') {
        // Unchanged: a timed-out read still resyncs the adapter. What changed
        // is that it is now reported as no answer instead of returning the
        // previous list as if it had just been read.
        await _recoverAdapter();
      }

      final upperResponse = response.trim().toUpperCase();
      if (linkFailed ||
          upperResponse == 'DISCONNECTED' ||
          upperResponse == 'ERROR') {
        return finish(EngineLinkLost(DateTime.now()));
      }

      // The protocol is only settled once a request has reached the bus, so
      // ask again now if init could not tell.
      final session = _session;
      if (session != null && !session.protocol.isKnown && _linkSynced) {
        final dpn = await _send('ATDPN');
        if (!_isDeadResponse(dpn)) {
          session.protocol = ObdProtocol.fromAtdpn(dpn);
          recorder?.recordNote('protocol (ATDPN): ${session.protocol}');
        }
      }

      // K-line gate. The reply is deliberately NOT parsed: the parser is
      // confirmed to decode K-line replies into wrong codes. (The raw reply
      // still reaches the tester-mode recorder, which is how real fixtures
      // will be collected.)
      if (!kKLineFaultReadingEnabled &&
          session != null &&
          session.protocol.isKLine) {
        return finish(EngineKLineGated(session.protocol, DateTime.now()));
      }

      if (busy) {
        // The engine computer did reply — every time, "busy". That is the
        // vehicle speaking, and it is not an answer.
        _markVehicleAnswered();
        return finish(
            EngineNoAnswer(EngineNoAnswerReason.moduleBusy, DateTime.now()));
      }

      // On CAN the response byte is always followed by a count of codes.
      final countMode = session?.protocol.family == ObdProtocolFamily.can
          ? DtcCountByteMode.present
          : DtcCountByteMode.auto;
      var verdict = classifyEngineDtcReply(response,
          linkFailed: false, countByteMode: countMode);
      var verdictReply = response;

      if (verdict is ReplyPositive && verdict.parsed.countMismatch) {
        await Future.delayed(const Duration(milliseconds: 300));
        final retry = await _sendWithPending(ObdPids.readDtcs,
            policy: corePolicy(), recoverySelfHandled: true);
        final retryResp = retry is PendingAnswered ? retry.reply : '';
        final retryVerdict = classifyEngineDtcReply(retryResp,
            linkFailed:
                _classifyReply(retryResp) == ObdReplyClass.linkFailure,
            countByteMode: countMode);
        if (retryVerdict is ReplyPositive) {
          final retryParsed = retryVerdict.parsed;
          if (!retryParsed.countMismatch ||
              retryParsed.allCodes.length > verdict.parsed.allCodes.length) {
            verdict = retryVerdict;
            verdictReply = retryResp;
          }
        }
      }

      final now = DateTime.now();
      switch (verdict) {
        case ReplyPositive(:final parsed):
          _markVehicleAnswered();
          // Every system the engine computer reports — P, C, B and U. Only P
          // was kept before, so a network fault (U0100) set by the engine
          // never reached the rider.
          final modules = _respondingModules(verdictReply, session);
          _dtcCodes = [
            for (final code in parsed.allCodes)
              _buildEngineDtc(code).withRecord(FaultRecord.fromObdCode(code,
                  source: ReadSource.mode03, readAt: now, module: modules[code])),
          ];
          _dtcCodesReadAt = now;
          // The reply's own count byte disagreeing with what arrived (after
          // the one retry above) means a code may be missing: say so rather
          // than present a partial list as complete.
          // Only on CAN, where the count byte is certain to be one.
          final reported = countMode == DtcCountByteMode.present
              ? parsed.reportedCount
              : null;
          _coreCountMismatch =
              reported != null && reported != parsed.allCodes.length
                  ? CountMismatch(
                      reported: reported, received: parsed.allCodes.length)
                  : null;
          return finish(EngineAnswered(_dtcCodes, now));
        case ReplyRefused(:final nrc):
          // A refusal is still the vehicle speaking.
          _markVehicleAnswered();
          return finish(EngineRefused(nrc, now));
        case ReplyNoAnswer(:final reason):
          return finish(EngineNoAnswer(reason, now));
        case ReplyLinkLost():
          return finish(EngineLinkLost(now));
      }
  }

  /// Which module (CAN header) reported each code, when headers were on.
  Map<String, String> _respondingModules(String reply, ObdSession? session) {
    final framing =
        session == null ? DtcFraming.unknown : framingFor(session.protocol);
    final decoded = decodeObdDtcReply(reply, service: 0x03, framing: framing);
    return <String, String>{
      if (decoded is ObdDtcCodes)
        for (final c in decoded.codes)
          if (c.ecuId.isNotEmpty) c.code: c.ecuId,
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ENGINE EXTRAS — Mode 07 / 0A, PID 01 01, RPM, voltage, VIN
  // ══════════════════════════════════════════════════════════════════════════

  /// Run the extras for [result]? Only when the vehicle spoke (answered or
  /// refused), and then only on a manual read, the first time this
  /// connection, when the Mode 03 list changed, or when the last run is old.
  bool _shouldRunExtras(EngineDtcRead result, {required bool force}) {
    if (result is! EngineAnswered && result is! EngineRefused) return false;
    if (!isConnected || !_linkSynced || _linkWaiters > 0) return false;
    final last = _engineReport;
    if (force || last == null || last.stoppedEarly) return true;
    if (!_sameCodes(last.coreCodes, _dtcCodes)) return true;
    return DateTime.now().difference(last.startedAt) >= faultTiming.extrasRefresh;
  }

  /// Read the optional extras, in order, each bounded by its own window and
  /// all of them by what is left of [kEngineReadBudget]. Each lands in
  /// [engineReport] as soon as it is known. Stops early — leaving the core
  /// result untouched — on [cancelEngineExtras], on a disconnect, or when
  /// another foreground operation needs the link.
  Future<void> _runEngineExtras(Stopwatch clock) async {
    _extrasRunning = true;
    _extrasCancelRequested = false;
    final session = _session;
    final framing =
        session == null ? DtcFraming.unknown : framingFor(session.protocol);
    var report = EngineReport(
      startedAt: DateTime.now(),
      coreCodes: {for (final c in _dtcCodes) c.code},
    );
    _engineReport = report;
    notifyListeners();

    void publish(EngineReport r) {
      report = r;
      _engineReport = r;
      notifyListeners();
    }

    Duration left() => faultTiming.engineReadBudget - clock.elapsed;
    bool stopped() =>
        _extrasCancelRequested ||
        _linkWaiters > 0 ||
        !isConnected ||
        !_linkSynced;

    /// One extra request: the reply, or null when it was not asked (budget
    /// gone, or stopped), or [_busyMarker] when the module stayed busy.
    var budgetGone = false;
    Future<String?> ask(String request) async {
      if (stopped()) return null;
      final remaining = left();
      if (remaining <= faultTiming.extraCommandWindow ~/ 10) {
        budgetGone = true;
        return null;
      }
      final window = remaining < faultTiming.extraCommandWindow
          ? remaining
          : faultTiming.extraCommandWindow;
      if (request.startsWith('AT')) {
        final saved = _cmdTimeout;
        _cmdTimeout = window;
        try {
          return await _send(request);
        } finally {
          _cmdTimeout = saved;
        }
      }
      final r = await _sendWithPending(request,
          policy: faultTiming.pendingPolicy(overall: remaining, perAttempt: window),
          isCancelled: stopped);
      return switch (r) {
        PendingAnswered(:final reply) => reply,
        PendingBusy() => _busyMarker,
        PendingCancelled() => null,
      };
    }

    ExtraRead<T> notAsked<T>() => budgetGone
        ? ExtraSkipped<T>('time budget used up')
        : (stopped() ? ExtraCancelled<T>() : ExtraSkipped<T>('not asked'));

    ExtraRead<T> fromReply<T>(String? reply, Decoded<T> Function(String) decode) {
      if (reply == null) return notAsked<T>();
      if (reply == _busyMarker) return ExtraNoAnswer<T>('module kept reporting busy');
      return extraFromDecoded(decode(reply));
    }

    ExtraRead<List<FaultRecord>> codesFrom(String? reply, int service, ReadSource source) {
      if (reply == null) return notAsked<List<FaultRecord>>();
      if (reply == _busyMarker) {
        return const ExtraNoAnswer<List<FaultRecord>>('module kept reporting busy');
      }
      // Silence is not "not supported": only NO DATA or a not-supported
      // refusal is.
      if (isSilentReply(reply)) {
        return ExtraNoAnswer<List<FaultRecord>>('no reply (${reply.trim()})');
      }
      final at = DateTime.now();
      final d = decodeObdDtcReply(reply, service: service, framing: framing);
      switch (d) {
        case ObdDtcCodes(:final codes):
          return ExtraValue<List<FaultRecord>>(<FaultRecord>[
            for (final c in codes)
              FaultRecord.fromDecodedObd(c, source: source, readAt: at),
          ]);
        case ObdDtcNoData():
          // The module answered Mode 03 a moment ago; silence to this is
          // "not offered", not a failure and not an empty list.
          return const ExtraUnsupported<List<FaultRecord>>();
        case ObdDtcNegative(:final nrc):
          return isNotSupportedNrc(nrc)
              ? ExtraUnsupported<List<FaultRecord>>(nrc)
              : ExtraNoAnswer<List<FaultRecord>>('refused (NRC ${FailureType.hex(nrc)})');
        case ObdDtcTruncated():
          return const ExtraNoAnswer<List<FaultRecord>>('reply cut short');
        case ObdDtcUnparseable(:final reason):
          return ExtraNoAnswer<List<FaultRecord>>('unreadable: $reason');
      }
    }

    try {
      // 1. Lamp and stored-code count.
      publish(report.copyWith(mil: fromReply(await ask('0101'), decodeMilStatus)));
      final mismatch = report.countMismatch;
      if (mismatch != null) {
        recorder?.recordNote('PID 01 01 count ${mismatch.reported}, '
            'Mode 03 sent ${mismatch.received}');
      }

      // 2. Pending (Mode 07) and 3. permanent (Mode 0A) codes.
      publish(report.copyWith(
          pending: codesFrom(await ask('07'), 0x07, ReadSource.mode07)));
      publish(report.copyWith(
          permanent: codesFrom(await ask('0A'), 0x0A, ReadSource.mode0A)));

      // 4. Engine state.
      publish(report.copyWith(rpm: fromReply(await ask('010C'), decodeRpm)));

      // 5. Battery voltage: the module's own reading, else the adapter's.
      final at = DateTime.now();
      var voltage = _plausibleVoltage(
          fromReply(await ask('0142'), decodeModuleVoltage),
          VoltageSource.modulePid42,
          at);
      if (voltage is! ExtraValue<VoltageReading> && !stopped() && !budgetGone) {
        voltage = _plausibleVoltage(
            fromReply(await ask(ObdPids.readVoltage), decodeAdapterVoltage),
            VoltageSource.adapterAtRv,
            at);
      }
      publish(report.copyWith(voltage: voltage));

      // 6. VIN and calibration IDs, once per connection.
      final s = _session;
      if (s != null && s.vin != null) {
        publish(report.copyWith(
            vin: ExtraValue<Vin>(s.vin!),
            calibrationIds: s.calibrationIds == null
                ? const ExtraSkipped<List<String>>('not offered')
                : ExtraValue<List<String>>(s.calibrationIds!)));
      } else if (s != null && s.vehicleInfoUnsupported) {
        publish(report.copyWith(
            vin: const ExtraUnsupported<Vin>(),
            calibrationIds: const ExtraUnsupported<List<String>>()));
      } else {
        final vin = fromReply(await ask('0902'), decodeVinReply);
        if (vin is ExtraValue<Vin>) s?.vin = vin.value;
        if (vin is ExtraUnsupported<Vin>) s?.vehicleInfoUnsupported = true;
        publish(report.copyWith(vin: vin));
        // Only whether a VIN was read is noted — never the VIN.
        recorder?.recordNote('vin: ${vin is ExtraValue<Vin> ? 'read' : vin.runtimeType}');
        if (vin is! ExtraUnsupported<Vin>) {
          final cal = fromReply(await ask('0904'), decodeCalibrationIds);
          if (cal is ExtraValue<List<String>>) s?.calibrationIds = cal.value;
          publish(report.copyWith(calibrationIds: cal));
        } else {
          publish(report.copyWith(
              calibrationIds: const ExtraUnsupported<List<String>>()));
        }
      }
    } catch (e) {
      debugPrint('[ObdService] engine extras stopped (${e.runtimeType})');
    } finally {
      final cancelled =
          _extrasCancelRequested || _linkWaiters > 0 || !isConnected;
      ExtraRead<T> close<T>(ExtraRead<T> r) =>
          (r is ExtraSkipped<T> && r.reason == 'not read yet')
              ? (cancelled ? ExtraCancelled<T>() : ExtraSkipped<T>('time budget used up'))
              : r;
      if (identical(_engineReport, report) && _session == session) {
        publish(report.copyWith(
          inProgress: false,
          finishedAt: DateTime.now(),
          pending: close(report.pending),
          permanent: close(report.permanent),
          mil: close(report.mil),
          rpm: close(report.rpm),
          voltage: close(report.voltage),
          vin: close(report.vin),
          calibrationIds: close(report.calibrationIds),
        ));
        recorder?.recordNote('engine extras finished'
            '${cancelled ? ' (stopped early)' : ''}');
      }
      _extrasRunning = false;
      _extrasCancelRequested = false;
    }
  }

  static const String _busyMarker = '\u0000BUSY';

  /// Keep a voltage only inside the same sanity band the live dashboard
  /// uses; anything outside it is line noise, not a battery.
  ExtraRead<VoltageReading> _plausibleVoltage(
      ExtraRead<double> v, VoltageSource source, DateTime at) {
    switch (v) {
      case ExtraValue(:final value):
        if (value < _voltageNoiseFloor || value > _voltageNoiseCeiling) {
          return const ExtraNoAnswer<VoltageReading>('implausible voltage');
        }
        return ExtraValue<VoltageReading>(
            VoltageReading(volts: value, source: source, at: at));
      case ExtraUnsupported(:final nrc):
        return ExtraUnsupported<VoltageReading>(nrc);
      case ExtraNoAnswer(:final reason):
        return ExtraNoAnswer<VoltageReading>(reason);
      case ExtraSkipped(:final reason):
        return ExtraSkipped<VoltageReading>(reason);
      case ExtraCancelled():
        return const ExtraCancelled<VoltageReading>();
    }
  }

  EngineDtcRead _finishEngineRead(EngineDtcRead result) {
    _lastEngineRead = result;
    recorder?.recordNote('engine read: ${result.runtimeType}');
    notifyListeners();
    return result;
  }

  /// Build an engine [DtcCode]. The 31-entry `DtcDatabase` supplies text,
  /// cause, severity and action for standard codes; a manufacturer-defined
  /// code never takes text from it (see [isManufacturerDefined]).
  DtcCode _buildEngineDtc(String code) {
    final info = isManufacturerDefined(code)
        ? const <String, String>{
            'desc': '',
            'cause': '',
            'severity': 'unknown',
            'action': '',
          }
        : _dtcInfo(code);
    return DtcCode(
      code: code,
      description: info['desc']!,
      possibleCause: info['cause']!,
      severity: info['severity']!,
      action: info['action']!,
    );
  }

  /// Why the last [clearDtcs] call ended as it did. See [ClearDtcsOutcome].
  ClearDtcsOutcome _lastClearOutcome = ClearDtcsOutcome.idle;
  ClearDtcsOutcome get lastClearOutcome => _lastClearOutcome;

  Future<bool> clearDtcs() async {
    if (!isConnected) {
      _lastClearOutcome = ClearDtcsOutcome.linkFailure;
      return false;
    }

    // Judge the link ONCE, here, before the sequence spends any wall clock.
    //
    // Everything below — waiting for the link to go idle, a 4s erase, the
    // settle, up to two 3s confirmations — takes far longer than the
    // proof-of-life window is sized for, so asking "is the link alive?" again
    // part-way through answers "no" on a perfectly healthy connection purely
    // because this sequence has been running. Ask before starting, when the
    // answer still means something, and act on that one verdict.
    if (_classifyReply('TIMEOUT') == ObdReplyClass.linkFailure) {
      debugPrint('[ObdService] clearDtcs: link already stale — not attempted');
      _lastClearOutcome = ClearDtcsOutcome.linkFailure;
      return false;
    }

    // Lock the poll loop out of the socket, then wait for whatever PID
    // request it may already have in flight to finish, so 04 never lands
    // on the wire concurrently with a live poll (the serial collision that
    // caused "Connection Failed" on real vehicles).
    _acquirePollLock();
    // The link was just proven alive; carry that proof across the sequence.
    _creditLinkProof(_clearSequenceProofWindow);
    await _waitForLinkIdle();

    final previousTimeout = _cmdTimeout;
    try {
      if (_cmdTimeout < _clearDtcsMinTimeout) {
        _cmdTimeout = _clearDtcsMinTimeout;
      }

      final response = await _send(ObdPids.clearDtcs);

      switch (_classifyReply(response)) {
        case ObdReplyClass.linkFailure:
          // The connection really is gone — the credit does not mask this,
          // because the dead-link counter overrides it. This is the path the
          // user must still see when Bluetooth is switched off or the bike is
          // walked away from mid-clear.
          _lastClearOutcome = ClearDtcsOutcome.linkFailure;
          return false;

        case ObdReplyClass.answered:
          // Includes the empty-payload acknowledgement. _isClearDtcsSuccess()
          // still vetoes a genuine ECU refusal (negative response 7F 04).
          if (!_isClearDtcsSuccess(response)) {
            _lastClearOutcome = ClearDtcsOutcome.refused;
            return false;
          }
          _dtcCodes = [];
          _lastClearOutcome = ClearDtcsOutcome.cleared;
          notifyListeners();
          return true;

        case ObdReplyClass.noAnswer:
          // The erase went out on a link that is demonstrably still alive, and
          // the ECU simply did not acknowledge inside the window — routine,
          // because Mode 04 is the one command that stops the ECU servicing
          // the bus while it writes flash. Neither "succeeded" nor "connection
          // failed" is known to be true here, so assume neither: ask the ECU
          // what its fault memory actually holds now.
          return await _confirmDtcsCleared();
      }
    } catch (e) {
      debugPrint('[ObdService] clearDtcs exception: $e');
      _lastClearOutcome = ClearDtcsOutcome.linkFailure;
      return false;
    } finally {
      _cmdTimeout = previousTimeout;
      _revokeLinkProofCredit();
      _releasePollLock();
    }
  }

  /// Resolve an unacknowledged erase by observing the ECU instead of guessing.
  ///
  /// Called only from the [ObdReplyClass.noAnswer] branch, i.e. the link is
  /// known to be alive and the request is known to have gone out. Mode 03 then
  /// answers the only question left — did the fault memory actually empty?
  ///
  /// Nothing here is charitable: the clear is confirmed ONLY on a reply that
  /// is a real, parseable Mode 03 answer reporting no stored codes. An empty
  /// or unparseable reply is not evidence of an empty fault memory and is
  /// reported as failure, so this cannot turn a broken clear into a green tick.
  Future<bool> _confirmDtcsCleared() async {
    final previousTimeout = _cmdTimeout;
    if (_cmdTimeout < _readDtcsMinTimeout) _cmdTimeout = _readDtcsMinTimeout;
    try {
      // Let the module come back before asking it anything. The erase it was
      // just given is the one request that stops it servicing the bus, so the
      // instant the Mode 04 window expires is the worst possible moment to
      // query it — and doing so spends the confirmation's attempt on a module
      // that was never going to answer.
      await Future.delayed(_postEraseSettle);

      for (var attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) await Future.delayed(_confirmRetryDelay);

        final response = await _send(ObdPids.readDtcs);

        // Not answered: the module is still away. Try once more before giving
        // up — a slow module is not a broken one, and it is certainly not a
        // broken connection.
        if (_classifyReply(response) != ObdReplyClass.answered) continue;

        // Answered but unreadable is not evidence of an empty fault memory.
        if (!_isUsableDtcResponse(response)) continue;

        // A real, parseable answer. Nothing here is charitable: this is the
        // one path that can confirm the clear, and it confirms it only on the
        // ECU's own report of an empty fault memory.
        if (ObdParser.parseDetailed(response).allCodes.isNotEmpty) {
          debugPrint('[ObdService] clearDtcs unacknowledged — '
              'Mode 03 reports codes still stored; the erase did not take');
          _lastClearOutcome = ClearDtcsOutcome.notCleared;
          return false;
        }

        debugPrint('[ObdService] clearDtcs unacknowledged — '
            'Mode 03 confirms fault memory is empty');
        _dtcCodes = [];
        _lastClearOutcome = ClearDtcsOutcome.cleared;
        notifyListeners();
        return true;
      }

      // Nothing came back. Before calling this unknown, check the one signal
      // that is still trustworthy here: the missed-reply counter. The elapsed
      // clock is not usable — the poll loop is locked out for the duration of
      // this sequence, so the link has had no opportunity to prove itself
      // either way — but a counter that has run to _deadLinkTimeouts means the
      // adapter has genuinely stopped answering, and that IS a link failure.
      if (_consecutiveTimeouts >= _deadLinkTimeouts) {
        debugPrint('[ObdService] clearDtcs — link stopped answering entirely');
        _lastClearOutcome = ClearDtcsOutcome.linkFailure;
        return false;
      }

      // The erase went out over a link that was alive, and the module never
      // came back to say what happened. That is genuinely unknown — and it is
      // NOT a connection failure, which is what it used to be reported as.
      debugPrint('[ObdService] clearDtcs unacknowledged — '
          'ECU did not answer Mode 03; outcome unconfirmed');
      _lastClearOutcome = ClearDtcsOutcome.unconfirmed;
      return false;
    } catch (e) {
      debugPrint('[ObdService] _confirmDtcsCleared exception: $e');
      _lastClearOutcome = ClearDtcsOutcome.unconfirmed;
      return false;
    } finally {
      _cmdTimeout = previousTimeout;
    }
  }

  // ── Clear Codes: the silent after-check (fault Phase 1B, B9) ─────────────
  /// One Mode 03 read, for the INTERNAL Clear Codes record only.
  ///
  /// Called after the existing Clear Codes flow has finished and its message
  /// is on screen; [clearDtcs] itself is not touched. It changes nothing the
  /// rider sees: no code list, no read result, no status line, no
  /// notification. It waits for any engine read to hand the link back, then
  /// holds the engine job slot (so Clear, the ABS scan and the next read wait
  /// for it, as they do for the extras), and sends `03` once through the
  /// Phase 1A pending helper, bounded by one attempt window. It stops early —
  /// as "unknown" — when [isCancelled] says so, when another operation asks
  /// for the link, or when the link drops.
  Future<StoredCodesCheck> checkStoredCodesSilently(
      {bool Function()? isCancelled}) async {
    if (!isConnected) return StoredCodesUnknown('not connected', DateTime.now());
    _acquirePollLock();
    await _waitForLinkIdle();
    if (_engineJob != null || _engineReadInFlight != null || _chassisScanInFlight) {
      _releasePollLock();
      return StoredCodesUnknown('link busy', DateTime.now());
    }
    final done = Completer<void>();
    _engineJob = done.future;
    final previousTimeout = _cmdTimeout;
    var headersOn = false;
    var stWidened = false;
    bool stop() =>
        (isCancelled?.call() ?? false) || _linkWaiters > 0 || !isConnected;
    try {
      if (!_linkSynced) return StoredCodesUnknown('link not synced', DateTime.now());
      final session = _session;
      if (!kKLineFaultReadingEnabled &&
          session != null &&
          session.protocol.isKLine) {
        return StoredCodesUnknown('k-line not read', DateTime.now());
      }
      if (_cmdTimeout < _readDtcsMinTimeout) _cmdTimeout = _readDtcsMinTimeout;
      headersOn = await _enableDtcHeaders();
      stWidened = !_isDeadResponse(await _send('ATST7D'));
      if (stop()) return StoredCodesUnknown('cancelled', DateTime.now());
      final sent = await _sendWithPending(ObdPids.readDtcs,
          policy: faultTiming.pendingPolicy(overall: faultTiming.pendingPerAttempt),
          isCancelled: stop);
      final now = DateTime.now();
      if (sent is! PendingAnswered) {
        return StoredCodesUnknown(stop() ? 'cancelled' : 'module busy', now);
      }
      final countMode = session?.protocol.family == ObdProtocolFamily.can
          ? DtcCountByteMode.present
          : DtcCountByteMode.auto;
      final verdict = classifyEngineDtcReply(sent.reply,
          linkFailed: _classifyReply(sent.reply) == ObdReplyClass.linkFailure,
          countByteMode: countMode);
      switch (verdict) {
        case ReplyPositive(:final parsed):
          return parsed.allCodes.isEmpty
              ? StoredCodesEmpty(now)
              : StoredCodesPresent(List<String>.unmodifiable(parsed.allCodes), now);
        case ReplyRefused():
          return StoredCodesUnknown('refused', now);
        case ReplyNoAnswer():
          return StoredCodesUnknown('no answer', now);
        case ReplyLinkLost():
          return StoredCodesUnknown('link lost', now);
      }
    } catch (e) {
      debugPrint('[ObdService] silent stored-code check failed (${e.runtimeType})');
      return StoredCodesUnknown('error', DateTime.now());
    } finally {
      _cmdTimeout = previousTimeout;
      if (stWidened && _linkSynced) await _send('ATST32');
      if (headersOn) await _restoreLiveHeaders();
      _cmdTimeout = previousTimeout;
      _releasePollLock();
      if (identical(_engineJob, done.future)) _engineJob = null;
      done.complete();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHASSIS / ABS MODULE SCAN
  // ══════════════════════════════════════════════════════════════════════════
  /// Read stored fault codes from the ABS/chassis module.
  ///
  /// This deliberately does NOT reuse [readDtcs]. Mode 03 goes out on the OBD
  /// functional address, which only emissions ECUs are obliged to answer; an
  /// ABS module is not one, so Mode 03 alone returns nothing from it no matter
  /// how healthy it is. Instead each candidate module address is taken in
  /// turn: `ATSH` retargets the adapter's transmit header at that module,
  /// `ATCRA` filters reception so no other ECU's traffic can be misread as an
  /// ABS reply, flow control is pointed back at the same module, and the UDS
  /// request `19 02 FF` (ReadDTCInformation / reportDTCByStatusMask) is sent.
  /// Plain `03` is then tried against the same physical address, because some
  /// chassis modules implement it once addressed directly.
  ///
  /// Unlike the engine read this is manual-only, never looped: it rewrites the
  /// adapter's addressing state, so it re-runs the init sequence afterwards to
  /// restore known-good live telemetry. Running that every five seconds would
  /// starve the dashboard.
  ///
  /// [vehicleMake] and [vehicleModel] are the free-text fields from the active
  /// vehicle profile. Together they select which platform dictionary the
  /// returned codes are described from, via [ChassisPlatforms.resolve]: the
  /// model is required because one manufacturer can ship several ABS platforms
  /// whose code systems disagree. The make alone still selects the module
  /// probe order, which is a manufacturer-level concern.
  ///
  /// When the platform cannot be identified the scan still runs and still
  /// returns the codes it read — only their descriptions are withheld, because
  /// describing a braking fault from the wrong platform's table is worse than
  /// describing nothing.
  Future<List<DtcCode>> readChassisDtcs({
    String? vehicleMake,
    String? vehicleModel,
  }) async {
    if (!isConnected) {
      _chassisScanOutcome = ChassisScanOutcome.linkUnavailable;
      notifyListeners();
      return _chassisDtcCodes;
    }
    if (_chassisScanInFlight) return _chassisDtcCodes;

    _chassisScanInFlight = true;
    _chassisAdapterCapability = ChassisAdapterCapability.unknown;
    _chassisProbeMedianMs = null;
    _chassisLearnedModule = '';
    notifyListeners();

    // Two different keys, deliberately: the module probe order is a
    // manufacturer-level concern (which CAN address the ABS ECU sits at),
    // while the fault dictionary is a platform-level one (what a given code
    // number means on this specific model family).
    final manufacturerKey = ChassisManufacturers.resolveKey(vehicleMake);
    final platformKey = ChassisPlatforms.resolve(vehicleMake, vehicleModel);
    final log = <String>[];
    final previousTimeout = _cmdTimeout;

    // Adapter-capability evidence, gathered from the probes this scan runs
    // anyway. Only genuine no-reply outcomes are sampled: a module that
    // refuses with an NRC, or answers with something unparseable, has
    // demonstrably been reached, which says nothing about adapter timing.
    final negativeLatenciesMs = <int>[];
    var timedOutProbes = 0;
    var consecutiveTimeouts = 0;

    var headersOn = false;
    var stWidened = false;
    var addressingChanged = false;
    var addressingAccepted = false;
    // A module answered "busy" to the end on at least one request. Only the
    // final outcome label uses it; the sweep itself is unchanged.
    var moduleStayedBusy = false;

    _acquirePollLock();
    await _waitForLinkIdle();

    final scanClock = Stopwatch()..start();

    try {
      if (!_linkSynced) {
        final recovered = await _recoverAdapter();
        if (!recovered) {
          _chassisScanOutcome = ChassisScanOutcome.linkUnavailable;
          log.add('Adapter link could not be resynced.');
          return _chassisDtcCodes;
        }
      }

      // Chassis modules are slower to answer than the engine ECU, and a UDS
      // reply is usually multi-frame. Widen both the app-side and adapter-side
      // timeouts for the duration of the scan.
      if (_cmdTimeout < _chassisScanMinTimeout) _cmdTimeout = _chassisScanMinTimeout;
      headersOn = await _enableDtcHeaders();
      final stResp = await _send('ATST7D');
      stWidened = !_isDeadResponse(stResp);

      // 29-bit candidates are only meaningful on a 29-bit bus. Asking the
      // adapter which protocol it settled on costs one command and saves
      // probing addresses the adapter would simply reject.
      final wide = await _busUsesTwentyNineBitIds();
      if (wide) log.add('Bus reports 29-bit CAN — extended addresses included.');

      // Load whatever a previous successful scan learned for this vehicle, and
      // put that address first. Reordering only: the full sweep still follows.
      try {
        if (!chassisAddressMemory.isLoaded) await chassisAddressMemory.load();
      } catch (e) {
        debugPrint('[ObdService] chassis address memory unavailable: $e');
      }
      final learned =
          chassisAddressMemory.knownTarget(vehicleMake, vehicleModel);

      final candidates = chassisAddressMemory.ordered(
        ChassisModuleProfiles.candidatesFor(manufacturerKey,
            supportsTwentyNineBit: wide),
        make: vehicleMake,
        model: vehicleModel,
      );
      if (learned != null) {
        _chassisLearnedModule = learned.label;
        log.add('Trying remembered address for this make and model first: '
            '${learned.label}.');
      }

      List<DtcCode>? found;

      /// Candidates that must be probed no matter what: the two that shipped
      /// before the list was widened, and the one this vehicle is known to
      /// answer at. Neither the time budget nor the timeout abort may skip
      /// them, so widening the list cannot make a previously-working scan
      /// stop working.
      bool isProtected(ChassisModuleTarget t) =>
          t.core || (learned != null && t.id == learned.id);

      /// Point the adapter at one specific module: CAN priority (29-bit only),
      /// transmit header, receive filter, and flow control. False means the
      /// adapter refused the addressing commands themselves, so this candidate
      /// cannot be probed.
      ///
      /// Extracted so it can be re-applied after an adapter recovery — see the
      /// TIMEOUT branch below for why that is not optional.
      Future<bool> applyAddressing(ChassisModuleTarget target) async {
        for (final cmd in target.priorityCommands) {
          await _send(cmd);
        }

        final shResp = await _send(target.headerCommand);
        if (_isDeadResponse(shResp) || shResp.contains('?')) {
          log.add('${target.label}: adapter rejected ${target.headerCommand}.');
          return false;
        }
        addressingChanged = true;
        addressingAccepted = true;

        final craResp = await _send(target.filterCommand);
        if (_isDeadResponse(craResp) || craResp.contains('?')) {
          // Not fatal: without the filter we may also see other ECUs, but the
          // parser groups by ECU id so the reply is still attributable.
          log.add('${target.label}: ATCRA unsupported — reading unfiltered.');
        }

        // Flow control must point back at the module we are addressing, or a
        // multi-frame UDS reply stalls after the first frame.
        for (final cmd in target.flowControlCommands) {
          await _send(cmd);
        }
        return true;
      }

      for (final target in candidates) {
        if (found != null) break;

        if (!isProtected(target)) {
          // Two independent reasons to stop sweeping, both honest and both
          // reported rather than silent.
          if (consecutiveTimeouts >= _chassisAbortAfterConsecutiveTimeouts) {
            log.add('Sweep stopped after $consecutiveTimeouts consecutive '
                'probes that never returned — the adapter is not handing '
                'control back. Remaining addresses were not tried.');
            break;
          }
          if (scanClock.elapsed >= chassisScanBudget) {
            log.add('Sweep stopped at the '
                '${chassisScanBudget.inSeconds}s scan time limit. Remaining '
                'addresses were not tried.');
            break;
          }
        }

        if (!await applyAddressing(target)) continue;

        for (final request in target.requests) {
          final probeClock = Stopwatch()..start();
          // Through the shared response-pending helper, with this scan's own
          // window per attempt. A module that answers "response pending" is
          // asked again (adapters that pass the frame through lose the real
          // answer otherwise); a pending frame and the answer in one buffer
          // keep the answer. Timeouts still go to the recovery below.
          final sent = await _sendWithPending(request,
              policy: faultTiming.pendingPolicy(perAttempt: _cmdTimeout),
              recoverySelfHandled: true);
          probeClock.stop();
          final elapsedMs = probeClock.elapsedMilliseconds;
          if (sent is! PendingAnswered) {
            // The module is there and alive, and never got to its answer.
            // Not a code list, not "clean", not an adapter-timing sample.
            consecutiveTimeouts = 0;
            moduleStayedBusy = true;
            log.add('${target.label} · $request: module kept reporting busy '
                '(response pending, ${sent.attempts} attempts) — no answer.');
            continue;
          }
          final response = sent.reply;

          if (response == 'TIMEOUT') {
            timedOutProbes++;
            consecutiveTimeouts++;
            log.add('${target.label} · $request: timeout after ${elapsedMs}ms.');

            // _recoverAdapter() may re-run the init sequence, and that restores
            // the adapter's LIVE baseline — which silently wipes the ATSH,
            // ATCRA, flow control and DTC headers this scan just set up.
            //
            // Continuing without re-establishing them sends the next request
            // (the Mode 03 fallback) out on the functional broadcast instead of
            // at this module. On that address the ENGINE ECU answers — and the
            // Mode 03 branch below would accept that reply and file engine
            // faults as ABS faults. That is precisely the outcome
            // ChassisModuleProfiles excludes 0x7E0-0x7E7 to prevent, and it is
            // documented there as worse than returning nothing.
            final recovered = await _recoverAdapter();
            if (!recovered) {
              log.add('${target.label}: adapter did not recover — '
                  'candidate abandoned.');
              break;
            }
            headersOn = await _enableDtcHeaders();
            final stRetry = await _send('ATST7D');
            stWidened = !_isDeadResponse(stRetry);
            if (!await applyAddressing(target)) {
              log.add('${target.label}: addressing could not be restored after '
                  'recovery — candidate abandoned.');
              break;
            }
            continue;
          }
          if (_isChassisNoReply(response)) {
            // The one outcome that carries adapter-timing information: the
            // adapter claims nothing answered, so how long it took to reach
            // that conclusion is meaningful. See ChassisTiming.
            negativeLatenciesMs.add(elapsedMs);
            consecutiveTimeouts = 0;
            log.add('${target.label} · $request: no reply from module '
                '(${elapsedMs}ms).');
            continue;
          }

          // Anything past this point is a reply from something, so the adapter
          // demonstrably reached the bus. Reset the timeout run.
          consecutiveTimeouts = 0;

          if (request.startsWith('19')) {
            final uds = ObdParser.parseUdsDtcDetailed(response);
            if (uds.negativeResponseCode != null) {
              log.add('${target.label} · $request: module refused '
                  '(NRC 0x${uds.negativeResponseCode!.toRadixString(16).toUpperCase()}).');
              continue;
            }
            if (!uds.sawPositiveResponse) {
              log.add('${target.label} · $request: reply not a 59 02 response.');
              continue;
            }
            log.add('${target.label} · $request: answered in ${elapsedMs}ms — '
                '${uds.records.length} code(s).');
            _chassisRespondingModule = target.label;
            await _rememberChassisAddress(
                target: target,
                make: vehicleMake,
                model: vehicleModel,
                log: log);
            final readAt = DateTime.now();
            found = <DtcCode>[
              for (final r in uds.records)
                _buildChassisDtc(
                  code: r.code,
                  platformKey: platformKey,
                  failureTypeByte: r.failureTypeByte,
                  isConfirmed: r.isConfirmed,
                  statusByte: r.statusByte,
                  record: FaultRecord.fromUdsDtcRecord(r,
                      readAt: readAt, module: target.label),
                ),
            ];
            break;
          }

          // Mode 03 fallback against the physically-addressed module.
          if (!_isUsableDtcResponse(response)) {
            log.add('${target.label} · $request: unrecognised reply.');
            continue;
          }
          final parsed = ObdParser.parseDetailed(response);
          log.add('${target.label} · $request (Mode 03): answered in '
              '${elapsedMs}ms — ${parsed.allCodes.length} code(s).');
          _chassisRespondingModule = target.label;
          await _rememberChassisAddress(
              target: target,
              make: vehicleMake,
              model: vehicleModel,
              log: log);
          final readAt = DateTime.now();
          found = <DtcCode>[
            for (final code in parsed.allCodes)
              _buildChassisDtc(
                code: code,
                platformKey: platformKey,
                record: FaultRecord.fromObdCode(code,
                    source: ReadSource.mode03,
                    readAt: readAt,
                    module: target.label),
              ),
          ];
          break;
        }
      }

      // The capability verdict is only about scans that found nothing. When a
      // module answered, the adapter has proved it can reach one, and guessing
      // about its hardware from timing would be noise.
      if (found == null) {
        _chassisProbeMedianMs = ChassisTiming.medianMs(negativeLatenciesMs);
        _chassisAdapterCapability = ChassisTiming.classify(
          negativeLatenciesMs: negativeLatenciesMs,
          timedOut: timedOutProbes,
        );
        log.add(_capabilityLogLine(
          capability: _chassisAdapterCapability,
          medianMs: _chassisProbeMedianMs,
          samples: negativeLatenciesMs.length + timedOutProbes,
        ));

        _chassisDtcCodes = <DtcCode>[];
        // Busy outranks "no module": a module DID answer, and its silence
        // about codes says nothing about whether it has any.
        _chassisScanOutcome = moduleStayedBusy
            ? ChassisScanOutcome.moduleBusy
            : addressingAccepted
                ? ChassisScanOutcome.noModuleResponse
                : ChassisScanOutcome.addressingUnsupported;
      } else {
        _chassisDtcCodes = found;
        _chassisScanOutcome = found.isEmpty
            ? ChassisScanOutcome.clean
            : ChassisScanOutcome.faultsFound;
      }
      return _chassisDtcCodes;
    } catch (e) {
      debugPrint('[ObdService] readChassisDtcs exception: $e');
      log.add('Scan error: $e');
      _chassisScanOutcome = ChassisScanOutcome.noModuleResponse;
      return _chassisDtcCodes;
    } finally {
      _cmdTimeout = previousTimeout;
      // Restoring addressing matters more than saving time here: ATSH/ATCRA
      // persist on the adapter, and leaving them set would silently break
      // every subsequent live PID poll. Re-running the init sequence puts the
      // adapter back to the exact known-good live baseline the rest of the app
      // assumes.
      if (addressingChanged && _linkSynced) {
        await _send(ObdPids.autoReceiveAddress);
        await _send(ObdPids.clearReceiveFilter);
        final restored = await _runInitSequence();
        if (!restored) log.add('Warning: adapter re-init after scan failed.');
      } else {
        if (stWidened && _linkSynced) await _send('ATST32');
        if (headersOn) await _restoreLiveHeaders();
      }
      _chassisScanLog = List<String>.unmodifiable(log);
      _chassisReadAt = DateTime.now();
      _releasePollLock();
      _chassisScanInFlight = false;
      notifyListeners();
    }
  }

  /// Ask the adapter which protocol it actually settled on, and report whether
  /// that protocol uses 29-bit CAN identifiers.
  ///
  /// `ATDPN` answers with the ISO 15765-4 protocol number, optionally prefixed
  /// with `A` when the protocol was reached automatically. Numbers 7 and 9 are
  /// the 29-bit variants (500 kbit and 250 kbit); 6 and 8 are their 11-bit
  /// counterparts. Anything unrecognised — including a silent or wedged
  /// adapter — is treated as 11-bit, which is the conservative answer: it
  /// means the extended candidates are skipped rather than probed with a
  /// header width the bus cannot carry.
  Future<bool> _busUsesTwentyNineBitIds() async {
    final reply = await _send('ATDPN');
    if (_isDeadResponse(reply)) return false;
    final cleaned =
        reply.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (cleaned.isEmpty) return false;
    final number = cleaned.substring(cleaned.length - 1);
    return number == '7' || number == '9';
  }

  /// Write down that [target] genuinely answered for this vehicle, so the next
  /// scan of the same make and model tries it first.
  ///
  /// Called only from the two branches that have decoded a real positive
  /// reply, never on a timeout, a refusal or an unparseable answer — a
  /// remembered address has to mean "this address really produced fault data
  /// on this vehicle", or the memory is worse than no memory at all.
  Future<void> _rememberChassisAddress({
    required ChassisModuleTarget target,
    required String? make,
    required String? model,
    required List<String> log,
  }) async {
    try {
      final stored = await chassisAddressMemory.remember(
        make: make,
        model: model,
        target: target,
      );
      if (stored) {
        log.add('Remembered ${target.label} for this make and model — future '
            'scans will try it first.');
      }
    } catch (e) {
      // Failing to remember must never fail the scan that just succeeded.
      debugPrint('[ObdService] could not remember chassis address: $e');
    }
  }

  /// The scan-log line describing what the probe timings suggest, worded as a
  /// possibility because that is all timing can establish.
  String _capabilityLogLine({
    required ChassisAdapterCapability capability,
    required int? medianMs,
    required int samples,
  }) {
    switch (capability) {
      case ChassisAdapterCapability.unknown:
        return 'Adapter timing: not enough measured probes ($samples) to '
            'judge.';
      case ChassisAdapterCapability.timingLooksGenuine:
        return 'Adapter timing: normal '
            '(${medianMs ?? 0}ms median over $samples probes) — the adapter '
            'waited for the bus, so silence here most likely means no module '
            'at these addresses.';
      case ChassisAdapterCapability.timingSuggestsLimited:
        return 'Adapter timing: unusual '
            '(${medianMs ?? 0}ms median over $samples probes) — replies came '
            'back too fast, or not at all, to be real bus round trips. This '
            'may point at the adapter rather than the motorcycle.';
    }
  }

  /// Build a chassis [DtcCode], filling the manufacturer columns when the
  /// dictionary has a real entry and leaving them empty when it does not.
  ///
  /// Empty is deliberate: the UI renders an undocumented chassis code honestly
  /// as "no manufacturer description available" rather than inventing one for
  /// a braking-system fault.
  DtcCode _buildChassisDtc({
    required String code,
    required String? platformKey,
    int? failureTypeByte,
    bool isConfirmed = true,
    int? statusByte,
    FaultRecord? record,
  }) {
    final entry = ChassisDtcDatabase.lookup(platformKey, code);
    return DtcCode(
      code: code,
      description: entry?.description ?? '',
      possibleCause: entry?.query ?? '',
      severity: entry?.severity ?? 'unknown',
      action: entry?.remedy ?? '',
      module: 'chassis',
      component: entry?.component ?? '',
      query: entry?.query ?? '',
      remedy: entry?.remedy ?? '',
      failureTypeByte: failureTypeByte,
      isConfirmed: isConfirmed,
      statusByte: statusByte,
      record: record,
    );
  }

  /// True when a physically-addressed module produced nothing usable.
  ///
  /// "NO DATA" is treated as no-reply here, unlike the engine path: when the
  /// adapter is addressed at one specific module, NO DATA means that module
  /// did not answer at all — not that a healthy module reported zero faults.
  bool _isChassisNoReply(String r) {
    if (r.isEmpty) return true;
    final upper = r.toUpperCase();
    return upper.contains('NO DATA') ||
        upper.contains('NODATA') ||
        upper.contains('UNABLE TO CONNECT') ||
        upper.contains('CAN ERROR') ||
        upper.contains('BUS INIT') ||
        upper.contains('DISCONNECTED') ||
        upper.trim() == '?' ||
        upper.contains('STOPPED');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FREEZE FRAME (Mode 02) — sensor snapshot captured when a DTC was set
  // ══════════════════════════════════════════════════════════════════════════
  /// Fetches the Mode 02 freeze frame snapshot (DTC, RPM, speed, coolant
  /// temp, engine load) using the same serial-safety mechanism as
  /// clearDtcs(): lock the poll loop out of the socket, wait for any
  /// in-flight live PID request to finish, run the freeze frame batch, then
  /// always release the lock so live telemetry resumes immediately.
  Future<FreezeFrameData?> fetchFreezeFrame() async {
    if (!isConnected) return null;

    _acquirePollLock();
    await _waitForLinkIdle();

    try {
      if (!_linkSynced) {
        final recovered = await _recoverAdapter();
        if (!recovered) return null;
      }

      final responses = <String>[];
      for (final cmd in const [
        ObdPids.freezeFrameDtc,
        ObdPids.freezeFrameRpm,
        ObdPids.freezeFrameSpeed,
        ObdPids.freezeFrameCoolantTemp,
        ObdPids.freezeFrameEngineLoad,
      ]) {
        final r = await _send(cmd);
        if (r == 'TIMEOUT') {
          await _recoverAdapter();
          return null;
        }
        responses.add(r);
      }
      final dtcResponse = responses[0];
      final rpmResponse = responses[1];
      final speedResponse = responses[2];
      final coolantResponse = responses[3];
      final loadResponse = responses[4];

      final dtc = _isUsableResponse(dtcResponse)
          ? ObdParser.parseFreezeFrameDtc(_stripCanHeaderForLivePid(dtcResponse))
          : null;
      final rpm = _isUsableResponse(rpmResponse)
          ? ObdParser.parseFreezeFramePid(
              ObdPids.freezeFrameRpm, _stripCanHeaderForLivePid(rpmResponse))
          : null;
      final speed = _isUsableResponse(speedResponse)
          ? ObdParser.parseFreezeFramePid(
              ObdPids.freezeFrameSpeed, _stripCanHeaderForLivePid(speedResponse))
          : null;
      final coolantTemp = _isUsableResponse(coolantResponse)
          ? ObdParser.parseFreezeFramePid(ObdPids.freezeFrameCoolantTemp,
              _stripCanHeaderForLivePid(coolantResponse))
          : null;
      final engineLoad = _isUsableResponse(loadResponse)
          ? ObdParser.parseFreezeFramePid(
              ObdPids.freezeFrameEngineLoad, _stripCanHeaderForLivePid(loadResponse))
          : null;

      final snapshot = FreezeFrameData(
        dtcCode: dtc,
        rpm: rpm,
        speed: speed,
        coolantTemp: coolantTemp,
        engineLoad: engineLoad,
        capturedAt: DateTime.now(),
      );

      return snapshot.hasData ? snapshot : null;
    } catch (e) {
      debugPrint('[ObdService] fetchFreezeFrame exception: $e');
      return null;
    } finally {
      _releasePollLock();
    }
  }

  /// Wait for any PID request the poll loop already had in flight to
  /// complete, capped so a stuck link can't hang clearDtcs() forever.
  ///
  /// Also hands the link back from a running engine-extras job first, so the
  /// extras — which run after the core result is already on screen — can
  /// never interleave their commands with Clear Codes, an ABS scan or a
  /// freeze-frame read.
  Future<void> _waitForLinkIdle() async {
    await _yieldEngineExtras();
    final deadline = DateTime.now().add(_cmdTimeout + const Duration(seconds: 1));
    while ((_wifiPendingCmd != null && !_wifiPendingCmd!.isCompleted) ||
        (_btPendingCmd != null && !_btPendingCmd!.isCompleted)) {
      if (DateTime.now().isAfter(deadline)) break;
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Decide whether a Mode 04 (clear DTCs) reply indicates success.
  ///
  /// Deliberately permissive: the clear is treated as successful unless the
  /// reply carries a genuine failure signal. Motorcycles and single-ECU
  /// vehicles frequently acknowledge a successful wipe without emitting the
  /// literal "44" positive-response byte a car sends — a bare prompt, an
  /// echoed request, or an empty line are all valid acknowledgements.
  /// Matching only "44"/"OK"/"NO DATA" caused a false "Connection Failed"
  /// on bikes even though the codes were cleared.
  ///
  /// ── Why a `7F 04` anywhere in the reply is NOT enough to call it refused ──
  /// Mode 04 is sent to the OBD **functional** address (0x7DF on ISO 15765-4),
  /// not to one module. Every module on the bus therefore sees it and every
  /// module answers. On this platform that is demonstrably more than one
  /// module — see `ChassisModuleProfiles`, which exists precisely because the
  /// ABS/chassis controller sits on the same CAN bus as the engine ECU.
  ///
  /// A module that holds no emissions fault memory answers the broadcast with
  /// `7F 04 11` (serviceNotSupported) or `7F 04 12`. That is not a refusal of
  /// anything: it is a module correctly saying "Mode 04 is not mine". The
  /// engine ECU on the very same reply answers `44` and really does erase.
  ///
  /// The previous scan returned false on the FIRST line containing `7F 04`,
  /// so this two-line reply
  ///
  ///     44
  ///     7F0411
  ///
  /// — a genuinely successful erase — was classified as
  /// [ClearDtcsOutcome.refused] and the rider was told to stop the engine and
  /// try again, while their codes had in fact just been wiped. The rule is now
  /// the one every scan tool uses: **the erase is refused only if every module
  /// that answered refused it.** One positive acknowledgement outranks another
  /// module's "not my service".
  ///
  /// Still returns false for genuine failures:
  ///   - adapter/bus errors: TIMEOUT, ERROR, UNABLE, DISCONNECTED, STOPPED,
  ///     BUS INIT, BUS BUSY, BUFFER FULL
  ///   - a reply in which every responding module answered `7F 04` — the ECU
  ///     actively refused the clear (engine running, security lockout) and the
  ///     codes were NOT cleared
  ///   - a reply consisting only of "SEARCHING" chatter, which means no ECU
  ///     acknowledgement was ever received
  bool _isClearDtcsSuccess(String r) {
    final upper = r.toUpperCase();

    if (upper.contains('TIMEOUT')) return false;
    if (upper.contains('ERROR')) return false;
    if (upper.contains('UNABLE')) return false;
    if (upper.contains('DISCONNECTED')) return false;
    if (upper.contains('STOPPED')) return false;
    if (upper.contains('BUS INIT')) return false;
    if (upper.contains('BUS BUSY')) return false;
    if (upper.contains('BUFFER FULL')) return false;

    // Judged per line, because one line is one responding module. A line that
    // is only protocol chatter is not a responder, and neither is the adapter
    // echoing the request back at us.
    var sawResponder = false;
    var sawRefusal = false;
    var sawAcknowledgement = false;

    for (final rawLine in upper.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.contains('SEARCHING')) continue; // chatter, not an ack

      final bytes = _responseBytes(line);
      if (bytes.isEmpty) continue; // not a hex data line — proves nothing
      // The adapter echoing "04" back is the request, not an answer to it.
      if (bytes.length == 1 && bytes.first == 0x04) continue;

      sawResponder = true;
      if (_containsNegativeMode04(bytes)) {
        sawRefusal = true;
      } else {
        sawAcknowledgement = true;
      }
    }

    // Every module that answered refused. This is the real refusal, and it
    // must keep reaching the rider as one.
    if (sawRefusal && !sawAcknowledgement) return false;

    // Nothing but SEARCHING chatter — no acknowledgement was received.
    if (!sawResponder && upper.contains('SEARCHING')) return false;

    return true;
  }

  /// Split one adapter response line into its bytes.
  ///
  /// With the live baseline `ATS0` (spaces off) a whole frame arrives as one
  /// unbroken hex run, and with `ATH1` that run is prefixed by an 11-bit CAN
  /// header the ELM327 prints as **three** nibbles — an odd count. Reading
  /// such a line in pairs from index 0 puts every byte after the header one
  /// nibble out of alignment, which both hides a real `7F 04` and can
  /// manufacture a phantom one out of unrelated bytes. This is the same
  /// alignment rule [_stripCanHeaderForLivePid] already applies to live PIDs.
  ///
  /// A 3-nibble header stays a single entry (0x7E8, never 0xFF or below), so
  /// it can never be mistaken for a `7F` service byte. Returns an empty list
  /// for a line that is not hex at all.
  List<int> _responseBytes(String line) {
    var tokens = line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const <int>[];

    final hexToken = RegExp(r'^[0-9A-F]+$');
    if (tokens.length == 1 && hexToken.hasMatch(tokens.first)) {
      final h = tokens.first;
      if (h.length.isOdd && h.length >= 5) {
        tokens = <String>[
          h.substring(0, 3),
          for (var i = 3; i + 2 <= h.length; i += 2) h.substring(i, i + 2),
        ];
      } else {
        tokens = <String>[
          for (var i = 0; i + 2 <= h.length; i += 2) h.substring(i, i + 2),
        ];
      }
    }

    final out = <int>[];
    for (final t in tokens) {
      if (!hexToken.hasMatch(t)) return const <int>[];
      final v = int.tryParse(t, radix: 16);
      if (v == null) return const <int>[];
      out.add(v);
    }
    return out;
  }

  /// Is this line a UDS/OBD negative response to service 0x04?
  ///
  /// Matched on real byte boundaries, so "A7 F0 44" — which contains the
  /// characters `7F04` but no such byte pair — is not a refusal.
  bool _containsNegativeMode04(List<int> bytes) {
    for (var i = 0; i + 1 < bytes.length; i++) {
      if (bytes[i] == 0x7F && bytes[i + 1] == 0x04) return true;
    }
    return false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DISCONNECT
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> disconnect() async {
    _stopPolling();
    _completeAllPending('DISCONNECTED');

    _wifiSub?.cancel();
    _wifiSub = null;
    _btDataSub?.cancel();
    _btDataSub = null;

    if (_transport == ConnectionType.wifi) {
      try {
        await _wifiSocket?.close();
      } catch (_) {}
      _wifiSocket = null;
    } else {
      try {
        await _btService.disconnect();
      } catch (_) {}
    }

    _wifiBuffer.clear();
    _btBuffer.clear();
    _data = VehicleData.empty();
    _clearFaultResults();
    _session = null;
    recorder?.endSession(reason: 'disconnected');
    _resetDiagnostics();
    _setStatus(ConnectionStatus.disconnected, 'Disconnected');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════
  void _resetDiagnostics() {
    _consecutiveTimeouts = 0;
    _recoveryAttempts = 0;
    _lastGoodResponseAt = null;
    _cmdTimeout = _cmdTimeoutMin;
    // A fresh session must never inherit a closed link gate from a previous
    // one. Without this, a single timeout permanently blocks all future
    // connection attempts, because _send() refuses to write while
    // _linkSynced is false and nothing else reopens it.
    _linkSynced = true;
    _adapterWedged = false;
  }

  void _setStatus(ConnectionStatus s, String msg) {
    _status = s;
    _statusMessage = msg;
    notifyListeners();
  }

  Map<String, String> _dtcInfo(String code) => DtcDatabase.lookup(code);

  @override
  void dispose() {
    _btService.removeListener(_onBtServiceChanged);
    _stopPolling();
    _wifiSub?.cancel();
    _btDataSub?.cancel();
    super.dispose();
  }
}

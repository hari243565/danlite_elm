/// Danlite ELM — Diagnostic module targeting (ABS / chassis)
///
/// ── Why engine-code logic cannot simply be reused ────────────────────────
/// `ObdService.readDtcs()` sends OBD-II **Mode 03**. Mode 03 is emissions
/// legislation: on ISO 15765-4 it goes out to the *functional* request ID
/// 0x7DF, and only emissions-related ECUs are obliged to answer it. An ABS
/// module is not an emissions ECU. It sits on the same CAN bus but at its own
/// physical address, and it generally does not answer 0x7DF at all — which is
/// exactly the reported real-world symptom of a scanner reading a Royal
/// Enfield's Keihin engine ECU perfectly while returning nothing whatsoever
/// from the Bosch ABS module on the same motorcycle. Same bus, different
/// module, different request.
///
/// Reaching it therefore needs three things the engine path never does:
///
///   1. **Physical addressing.** `ATSH <id>` retargets the adapter from the
///      functional broadcast to one specific module's request ID, and
///      `ATCRA <id>` filters reception to that module's response ID so another
///      ECU's chatter cannot be misread as an ABS reply. `ATFCSH` points
///      ISO-TP flow-control frames back at the same module, which matters as
///      soon as the reply spans more than one frame.
///
///   2. **A different diagnostic service.** Non-emissions modules speak UDS
///      (ISO 14229), not OBD-II. The stored-fault request is
///      `19 02 <statusMask>` — ReadDTCInformation, subfunction 0x02
///      (reportDTCByStatusMask) — answered with `59 02 …`. Mask 0xFF is used
///      because it matches a DTC with any status bit set, which is the
///      broadest question a scan tool can ask. Some modules answer plain Mode
///      03 once physically addressed, so `03` is kept as a documented second
///      attempt rather than assumed to be useless.
///
///   3. **A different response format.** A UDS `59 02` reply carries 4-byte
///      records (3 DTC bytes + 1 status byte); Mode 03 carries 2-byte pairs.
///      Both are decoded in `ObdParser` — see `parseUdsDtcDetailed`.
///
/// ── Honest note on the addresses below ───────────────────────────────────
/// These are the *conventional* 11-bit chassis-module addresses used across
/// many ISO 15765-4 platforms. They are NOT independently verified Royal
/// Enfield values — no public source carries that detail. That is precisely
/// why this is written as an ordered **probe**: each candidate is addressed in
/// turn and the first one that returns a genuine positive response wins. The
/// code never asserts an address is correct; it asks, and reports honestly
/// when nothing answers.
///
/// The legislated OBD ECU addresses (0x7E0–0x7E7) are deliberately excluded
/// from the probe. The engine ECU at 0x7E0 will usually answer `1902` happily,
/// and accepting that would mean relabelling engine faults as ABS faults —
/// worse than returning nothing.
library;

import 'obd_pids.dart';

/// Whether a candidate is addressed with an 11-bit or a 29-bit CAN identifier.
///
/// This is not cosmetic. The ELM327 takes a three-hex-digit header for 11-bit
/// CAN and a six-hex-digit one for 29-bit (the top priority byte coming from
/// `ATCP` instead), and its receive filter takes three or eight digits to
/// match. Sending the wrong width is rejected by the adapter with `?`.
enum ChassisAddressing {
  /// ISO 15765-4 11-bit CAN. `ATSH` takes 3 hex digits, `ATCRA` takes 3.
  elevenBit,

  /// ISO 15765-4 29-bit ("extended") CAN. `ATSH` takes 6 hex digits and the
  /// 0x18 priority byte comes from `ATCP`; `ATCRA` takes the full 8.
  twentyNineBit,
}

/// Which documented addressing convention a candidate is derived from.
///
/// Recorded per candidate so the probe log can say *why* an address was tried,
/// and so a reader can check the claim against its source rather than take the
/// list on trust. No entry in this file is an invented address: each one is
/// either a published module ID or a direct application of a published rule.
enum ChassisAddressConvention {
  /// ISO 15765-4 11-bit physical addressing. Physical diagnostic request IDs
  /// sit in the 0x700-0x7DF region and the module answers on **request + 8**.
  /// This is the rule the two originally-shipped candidates already use
  /// (0x7B0 to 0x7B8, 0x760 to 0x768).
  isoPhysicalPlus8,

  /// The Volkswagen Group variant of the same 11-bit region, where the module
  /// answers on **request + 0x6A** instead of + 8. Documented as an explicit
  /// exception to the +8 rule, and confirmed arithmetically against a
  /// published VAG UDS ID table (e.g. Brake 1 = 0x713 answering on 0x77D, and
  /// 0x713 + 0x6A = 0x77D).
  vagPlus6A,

  /// ISO 15765-4 29-bit extended addressing: the request goes to
  /// `18DA<target><tester>` and the reply comes back on `18DA<tester><target>`
  /// — note the swap, not a + 8 offset. The tester address is 0xF1 by
  /// convention.
  isoExtended29Bit,
}

/// One addressable diagnostic module: how to point the adapter at it, and what
/// to ask once pointed.
class ChassisModuleTarget {
  /// Human-readable label, used in diagnostics/logging only.
  final String label;

  /// CAN request ID for `ATSH` — 3 hex chars for 11-bit, 6 for 29-bit.
  final String requestHeader;

  /// CAN response ID for `ATCRA` — 3 hex chars for 11-bit, 8 for 29-bit.
  final String responseFilter;

  /// Diagnostic requests to try against this module, in order. The first one
  /// producing a decodable positive response ends the probe.
  final List<String> requests;

  /// Identifier width. Drives the extra `ATCP` step, and is what lets the scan
  /// skip 29-bit candidates outright on an 11-bit bus instead of burning a
  /// round trip having the adapter reject each one.
  final ChassisAddressing addressing;

  /// Which published convention this candidate comes from.
  final ChassisAddressConvention convention;

  /// Probed unconditionally, never dropped for running out of scan time.
  ///
  /// True only for the two candidates that shipped before the list was
  /// widened. Their behaviour — order, requests, and the fact that they are
  /// always attempted — is deliberately unchanged by the widening, so a scan
  /// that worked before still works in exactly the same way.
  final bool core;

  const ChassisModuleTarget({
    required this.label,
    required this.requestHeader,
    required this.responseFilter,
    required this.requests,
    this.addressing = ChassisAddressing.elevenBit,
    this.convention = ChassisAddressConvention.isoPhysicalPlus8,
    this.core = false,
  });

  /// Stable key for this candidate, used by the learned-address memory.
  ///
  /// Built from the wire values rather than the label, so that renaming a
  /// label for display never orphans a stored discovery.
  String get id =>
      '${requestHeader.toUpperCase()}>${responseFilter.toUpperCase()}';

  // ── Wire commands ─────────────────────────────────────────────────────────
  // These are the single source of the bytes `ObdService.readChassisDtcs()`
  // puts on the wire — it calls these accessors rather than rebuilding the
  // strings, so a test asserting on them is asserting on the real request.

  /// `ATCP18` for a 29-bit candidate, empty for an 11-bit one.
  ///
  /// A list rather than a nullable string so it splices into the command
  /// sequence without a conditional, which keeps the 11-bit sequence
  /// byte-for-byte identical to what it was before 29-bit support existed.
  List<String> get priorityCommands =>
      addressing == ChassisAddressing.twentyNineBit
          ? <String>[ObdPids.setCanPriority(ObdPids.canPriorityDiagnostic)]
          : const <String>[];

  /// `ATSH<id>` — retarget the adapter's transmit header at this module.
  String get headerCommand => ObdPids.setHeader(requestHeader);

  /// `ATCRA<id>` — accept only this module's replies.
  String get filterCommand => ObdPids.setReceiveFilter(responseFilter);

  /// Flow-control setup, in send order, so a multi-frame reply is acknowledged
  /// back to this module rather than the adapter's default address.
  List<String> get flowControlCommands => <String>[
        ObdPids.setFlowControlHeader(requestHeader),
        ObdPids.flowControlData,
        ObdPids.flowControlMode,
      ];

  /// The complete ordered command sequence for probing this module: addressing
  /// setup followed by each diagnostic request.
  List<String> get wireSequence => <String>[
        ...priorityCommands,
        headerCommand,
        filterCommand,
        ...flowControlCommands,
        ...requests,
      ];
}

/// Per-manufacturer chassis-module probe order.
class ChassisModuleProfiles {
  ChassisModuleProfiles._();

  /// UDS ReadDTCInformation, subfunction 0x02 (reportDTCByStatusMask),
  /// status mask 0xFF — "report every DTC with any status bit set".
  static const String udsReadDtcByStatusMask = '1902FF';

  /// OBD-II Mode 03, retried against the physically-addressed module. Some
  /// chassis modules implement it even though the functional broadcast does
  /// not reach them.
  static const String obdModeThree = '03';

  /// The two requests the originally-shipped candidates send, in order.
  static const List<String> _udsThenModeThree = <String>[
    udsReadDtcByStatusMask,
    obdModeThree,
  ];

  /// UDS only. Used by the swept addresses added when the list was widened.
  ///
  /// Deliberately narrower than [_udsThenModeThree], for a reason rather than
  /// for speed alone: Mode 03 is emissions legislation. A non-powertrain
  /// module answering it *at a conventional chassis address* is an attested
  /// pattern and stays supported on the two original candidates. A module
  /// answering it at an address being swept precisely because we do not know
  /// what lives there is not attested, and accepting such a reply would be the
  /// same misattribution risk the 0x7E0-0x7E7 exclusion exists to prevent.
  /// A `19 02` request is answered with a `59 02` signature that identifies
  /// the reply as a genuine UDS stored-fault report; a Mode 03 `43` reply
  /// carries no such identification.
  static const List<String> _udsOnly = <String>[udsReadDtcByStatusMask];

  // ── TIER 1 ────────────────────────────────────────────────────────────────
  // The candidates that shipped first and are already confirmed to behave
  // correctly against the supported vehicles. Unchanged, still first, still
  // marked [ChassisModuleTarget.core] so that no amount of list-widening or
  // scan budgeting can stop them being probed.

  static const ChassisModuleTarget _t1_7B0 = ChassisModuleTarget(
    label: 'ABS / chassis (7B0)',
    requestHeader: '7B0',
    responseFilter: '7B8',
    requests: _udsThenModeThree,
    core: true,
  );

  static const ChassisModuleTarget _t1_760 = ChassisModuleTarget(
    label: 'ABS / chassis (760)',
    requestHeader: '760',
    responseFilter: '768',
    requests: _udsThenModeThree,
    core: true,
  );

  // ── TIER 2 ────────────────────────────────────────────────────────────────
  // Named, published brake-system module IDs on the Volkswagen Group +0x6A
  // convention. These are not derived from a rule — they are specific IDs from
  // a published VAG UDS identifier table, and each response filter is that
  // table's own value (which independently checks out against +0x6A).
  //
  // They are included because +0x6A is one of only two request-to-response
  // offsets documented for the 11-bit physical range, and a scan that only
  // ever assumes +8 cannot reach a module using the other one no matter how
  // many request IDs it tries.

  static const ChassisModuleTarget _t2_713 = ChassisModuleTarget(
    label: 'Brake / ABS control unit (713, VAG +6A)',
    requestHeader: '713',
    responseFilter: '77D',
    requests: _udsThenModeThree,
    convention: ChassisAddressConvention.vagPlus6A,
  );

  static const ChassisModuleTarget _t2_762 = ChassisModuleTarget(
    label: 'Brake sensor system (762, VAG +6A)',
    requestHeader: '762',
    responseFilter: '7CC',
    requests: _udsOnly,
    convention: ChassisAddressConvention.vagPlus6A,
  );

  // ── TIER 3 ────────────────────────────────────────────────────────────────
  // A sweep of the documented 11-bit physical-addressing region under the
  // documented +8 response rule.
  //
  // Honesty about what this is and is not: the *region* (0x700-0x7DF for
  // physical diagnostic requests) and the *rule* (the module answers on
  // request + 8) are both published. Which slot inside that region a given
  // manufacturer put its ABS module at is not published for most vehicles —
  // that is exactly the gap this sweep exists to close, and exactly why the
  // learned-address memory exists to remember the answer once a real vehicle
  // gives one.
  //
  // The slots are the conventional 16-address boundaries within the region,
  // which is where module IDs actually cluster in every published table.
  // 0x7E0-0x7E7 is omitted: that is the legislated OBD ECU block, the engine
  // answers `19 02` there, and accepting that reply would file engine faults
  // as braking faults. 0x7DF is omitted for the same reason — it is the OBD
  // functional broadcast.
  //
  // The order below is fixed so that scan behaviour is reproducible and
  // testable. No public source ranks these slots by likelihood, and inventing
  // a ranking would be dressing a guess up as knowledge; they run outward from
  // the two originally-shipped addresses.

  static const List<ChassisModuleTarget> _tier3 = <ChassisModuleTarget>[
    ChassisModuleTarget(
      label: 'Chassis sweep (7A0)',
      requestHeader: '7A0',
      responseFilter: '7A8',
      requests: _udsOnly,
    ),
    ChassisModuleTarget(
      label: 'Chassis sweep (7C0)',
      requestHeader: '7C0',
      responseFilter: '7C8',
      requests: _udsOnly,
    ),
    ChassisModuleTarget(
      label: 'Chassis sweep (770)',
      requestHeader: '770',
      responseFilter: '778',
      requests: _udsOnly,
    ),
    ChassisModuleTarget(
      label: 'Chassis sweep (750)',
      requestHeader: '750',
      responseFilter: '758',
      requests: _udsOnly,
    ),
    ChassisModuleTarget(
      label: 'Chassis sweep (740)',
      requestHeader: '740',
      responseFilter: '748',
      requests: _udsOnly,
    ),
    ChassisModuleTarget(
      label: 'Chassis sweep (730)',
      requestHeader: '730',
      responseFilter: '738',
      requests: _udsOnly,
    ),
    ChassisModuleTarget(
      label: 'Chassis sweep (720)',
      requestHeader: '720',
      responseFilter: '728',
      requests: _udsOnly,
    ),
    ChassisModuleTarget(
      label: 'Chassis sweep (710)',
      requestHeader: '710',
      responseFilter: '718',
      requests: _udsOnly,
    ),
    ChassisModuleTarget(
      label: 'Chassis sweep (700)',
      requestHeader: '700',
      responseFilter: '708',
      requests: _udsOnly,
    ),
    ChassisModuleTarget(
      label: 'Chassis sweep (7D0)',
      requestHeader: '7D0',
      responseFilter: '7D8',
      requests: _udsOnly,
    ),
  ];

  // ── TIER 4 ────────────────────────────────────────────────────────────────
  // ISO 15765-4 29-bit extended addressing. Attempted only when the adapter
  // reports that the vehicle is actually on a 29-bit CAN protocol — see
  // [candidatesFor]'s `supportsTwentyNineBit` flag. On an 11-bit bus these are
  // not merely useless, they are misleading: the adapter rejects the six-digit
  // header with `?`, which the scan log would otherwise have to report as an
  // addressing refusal by an adapter that is in fact behaving correctly.
  //
  // 0x28 is the brake / electronic brake control module target address in the
  // ISO 15765-4 extended scheme; 0xF1 is the conventional external-tester
  // address. Note that the reply ID is NOT request + 8 — extended addressing
  // swaps the target and tester bytes, so 18DA28F1 is answered on 18DAF128.
  //
  // The engine's extended-addressing target (0x10, i.e. 18DA10F1) is excluded
  // for exactly the same reason 0x7E0-0x7E7 is excluded from the 11-bit list.

  static const List<ChassisModuleTarget> extendedCandidates =
      <ChassisModuleTarget>[
    ChassisModuleTarget(
      label: 'Brake control module (29-bit, 18DA28F1)',
      requestHeader: 'DA28F1',
      responseFilter: '18DAF128',
      requests: _udsOnly,
      addressing: ChassisAddressing.twentyNineBit,
      convention: ChassisAddressConvention.isoExtended29Bit,
    ),
  ];

  /// Ordered candidates tried when a manufacturer has no specific profile.
  ///
  /// Tier 1 first and unchanged, then the named +0x6A modules, then the swept
  /// +8 region. 29-bit candidates are not in this list — they are appended by
  /// [candidatesFor] only when the bus is actually 29-bit.
  static const List<ChassisModuleTarget> genericCandidates =
      <ChassisModuleTarget>[
    _t1_7B0,
    _t1_760,
    _t2_713,
    _t2_762,
    ..._tier3,
  ];

  /// Manufacturer-specific probe order. Empty today: no verified per-make
  /// chassis address is available, so every manufacturer uses
  /// [genericCandidates]. When a real address is confirmed for a make (by the
  /// client testing against the vehicle, from a service manual, or promoted
  /// out of the learned-address memory) add one entry here — nothing else
  /// changes.
  static const Map<String, List<ChassisModuleTarget>> byManufacturer =
      <String, List<ChassisModuleTarget>>{};

  /// Every candidate this file knows about, 11-bit and 29-bit alike.
  ///
  /// Used by the learned-address memory to resolve a stored id back to a
  /// target, and by tests that assert list-wide invariants.
  static List<ChassisModuleTarget> get allKnownTargets => <ChassisModuleTarget>[
        for (final list in byManufacturer.values) ...list,
        ...genericCandidates,
        ...extendedCandidates,
      ];

  /// Resolve a stored candidate [id] back to its target, or null when the id
  /// came from an older build whose address is no longer in the list.
  static ChassisModuleTarget? targetById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final t in allKnownTargets) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// The probe order to use for [manufacturerKey].
  ///
  /// [supportsTwentyNineBit] comes from the adapter's own protocol report
  /// (`ATDPN`). When it is false — which is the case on every 11-bit CAN
  /// vehicle, including the supported motorcycles — the 29-bit candidates are
  /// left out entirely rather than probed and rejected.
  static List<ChassisModuleTarget> candidatesFor(
    String? manufacturerKey, {
    bool supportsTwentyNineBit = false,
  }) {
    final base = manufacturerKey == null
        ? genericCandidates
        : (byManufacturer[manufacturerKey] ?? genericCandidates);
    if (!supportsTwentyNineBit) return base;
    return <ChassisModuleTarget>[...base, ...extendedCandidates];
  }
}

/// What the probe's own response timing suggests about the adapter.
///
/// This is inference from timing, never a capability query — no ELM327 command
/// asks "can you reach a non-powertrain module?", so nothing here is stated as
/// a certainty, and the UI copy that renders it must not either.
///
/// ── The reasoning behind the thresholds ──────────────────────────────────
/// Two published numbers bound what a *genuine* negative answer can cost:
///
///   * ISO 14229-2 gives the server (the ECU) a P2 window in which it must
///     send its first response — commonly 50 ms — or send NRC 0x78 to ask for
///     more time. So a module that is present answers, or begins answering,
///     inside tens of milliseconds.
///
///   * The ELM327 datasheet defines `AT ST` as the time the adapter waits for
///     that response, in ~4 ms increments (power-on default 0x32, about
///     205 ms). The chassis scan sets `ATST7D` = 125 x 4 ms, about 500 ms,
///     deliberately wider than the ECU's own window.
///
/// So an honest "nobody answered" costs roughly the ST window: the adapter has
/// to put the frame on the bus and then wait out its own timer before it can
/// know. Two departures from that are meaningful:
///
///   * A negative that comes back far faster than the ECU's own permitted
///     response window means the adapter did not wait — it answered from its
///     own state, which is a documented shortcut in weak clone firmware.
///
///   * A probe that never returns inside the app's own much wider window means
///     the adapter is not honouring `AT ST` at all and is not handing control
///     back.
///
/// Neither proves the adapter is a clone. Both are reasons to consider the
/// hardware as a possible explanation before concluding that the motorcycle
/// has no ABS module.
enum ChassisAdapterCapability {
  /// Not enough measured probes to say anything. The default, and the only
  /// honest answer on a short or successful scan.
  unknown,

  /// Negative replies arrived within a plausible window — the adapter really
  /// did wait for the bus. This says nothing about whether it can reach any
  /// particular module, only that its timing behaviour looks genuine.
  timingLooksGenuine,

  /// Negative replies were consistently implausible: far too fast to be a real
  /// bus round trip, or never returning at all. Consistent with a
  /// low-capability adapter, and worth surfacing as a possibility.
  timingSuggestsLimited,
}

/// Timing constants and the classifier for [ChassisAdapterCapability], kept
/// next to the enum they define so that the reasoning above and the numbers
/// below cannot drift apart.
class ChassisTiming {
  ChassisTiming._();

  /// A negative reply faster than this cannot represent a completed bus round
  /// trip: it is below the ECU's own permitted first-response window under
  /// ISO 14229-2, so the adapter cannot yet have known that nothing answered.
  static const int implausiblyFastNegativeMs = 50;

  /// Fewer measured negative probes than this and the verdict stays
  /// [ChassisAdapterCapability.unknown]. One or two odd timings are noise; a
  /// consistent pattern across several different addresses is a signal.
  static const int minimumSamples = 4;

  /// The share of measured negatives that must be implausible before the
  /// verdict tips. Set well above half, so a mixed picture reads as
  /// inconclusive rather than as an accusation about the customer's hardware.
  static const double suspectShare = 0.7;

  /// Classify a set of measured negative-probe latencies, in milliseconds.
  ///
  /// [timedOut] counts probes that never returned inside the app's own window;
  /// they have no latency to record, so they are passed as a count.
  static ChassisAdapterCapability classify({
    required List<int> negativeLatenciesMs,
    required int timedOut,
  }) {
    final samples = negativeLatenciesMs.length + timedOut;
    if (samples < minimumSamples) return ChassisAdapterCapability.unknown;

    final implausible = timedOut +
        negativeLatenciesMs
            .where((ms) => ms < implausiblyFastNegativeMs)
            .length;
    if (implausible / samples >= suspectShare) {
      return ChassisAdapterCapability.timingSuggestsLimited;
    }
    return ChassisAdapterCapability.timingLooksGenuine;
  }

  /// Median of [values], or null when there is nothing to take a median of.
  ///
  /// Median rather than mean: one five-second timeout in an otherwise fast set
  /// would drag a mean somewhere that describes no probe that actually
  /// happened.
  static int? medianMs(List<int> values) {
    if (values.isEmpty) return null;
    final sorted = List<int>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }
}

/// Which diagnostic module a fault code was read from.
///
/// Kept distinct from the SAE letter category (`DtcCategory`): the letter says
/// what kind of code it is, this says which ECU actually reported it. A `C`
/// code surfacing on the engine ECU's Mode 03 reply is still an engine-module
/// read.
enum DtcModule { engine, chassis }

/// Outcome of a chassis scan, so the UI can tell the three genuinely different
/// failure states apart instead of showing one generic "no codes".
enum ChassisScanOutcome {
  /// Not attempted yet in this session.
  idle,

  /// A module answered and reported no stored faults.
  clean,

  /// A module answered and reported faults.
  faultsFound,

  /// Every candidate address was probed and none produced a usable reply.
  /// This is the state that may be an adapter limitation rather than a healthy
  /// motorcycle — see the ELM327 caveat surfaced in the UI.
  noModuleResponse,

  /// The adapter rejected the physical-addressing commands themselves
  /// (`ATSH`/`ATCRA`), which means this adapter cannot target a non-engine
  /// module at all.
  addressingUnsupported,

  /// Adapter not connected / link dropped mid-scan.
  linkUnavailable,
}

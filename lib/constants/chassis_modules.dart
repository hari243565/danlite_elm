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

/// One addressable diagnostic module: how to point the adapter at it, and what
/// to ask once pointed.
class ChassisModuleTarget {
  /// Human-readable label, used in diagnostics/logging only.
  final String label;

  /// CAN request ID for `ATSH` (11-bit, 3 hex chars).
  final String requestHeader;

  /// CAN response ID for `ATCRA` (11-bit, 3 hex chars).
  final String responseFilter;

  /// Diagnostic requests to try against this module, in order. The first one
  /// producing a decodable positive response ends the probe.
  final List<String> requests;

  const ChassisModuleTarget({
    required this.label,
    required this.requestHeader,
    required this.responseFilter,
    required this.requests,
  });

  // ── Wire commands ─────────────────────────────────────────────────────────
  // These are the single source of the bytes `ObdService.readChassisDtcs()`
  // puts on the wire — it calls these accessors rather than rebuilding the
  // strings, so a test asserting on them is asserting on the real request.

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

  /// Ordered candidates tried when a manufacturer has no specific profile.
  ///
  /// Both pairs are widely-used chassis/ABS conventions on 11-bit CAN. Order
  /// matters only as probe order; neither is claimed to be verified for any
  /// specific make.
  static const List<ChassisModuleTarget> genericCandidates =
      <ChassisModuleTarget>[
    ChassisModuleTarget(
      label: 'ABS / chassis (7B0)',
      requestHeader: '7B0',
      responseFilter: '7B8',
      requests: <String>[udsReadDtcByStatusMask, obdModeThree],
    ),
    ChassisModuleTarget(
      label: 'ABS / chassis (760)',
      requestHeader: '760',
      responseFilter: '768',
      requests: <String>[udsReadDtcByStatusMask, obdModeThree],
    ),
  ];

  /// Manufacturer-specific probe order. Empty today: no verified per-make
  /// chassis address is available, so every manufacturer uses
  /// [genericCandidates]. When a real address is confirmed for a make (by the
  /// client testing against the vehicle, or from a service manual), add one
  /// entry here — nothing else changes.
  static const Map<String, List<ChassisModuleTarget>> byManufacturer =
      <String, List<ChassisModuleTarget>>{};

  /// The probe order to use for [manufacturerKey].
  static List<ChassisModuleTarget> candidatesFor(String? manufacturerKey) {
    if (manufacturerKey == null) return genericCandidates;
    return byManufacturer[manufacturerKey] ?? genericCandidates;
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

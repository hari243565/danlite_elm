/// Danlite ELM — which section of the Fault Codes tab a code belongs to, and
/// what each section card may honestly say.
///
/// Sections are VIEWS over the codes the engine scan and the ABS scan already
/// found. Nothing here reads the bike. A card that nobody scanned says so, and
/// a section no scan covers never claims to have been checked.
///
/// Pure Dart: no Flutter, no adapter. Text is chosen by the screen from the
/// [SectionStatus] this file returns.
library;

import '../constants/chassis_modules.dart' show ChassisScanOutcome;
import '../models/fault_record.dart';
import '../models/vehicle_data.dart';
import '../services/engine_dtc_read.dart';

/// The six sections, in the order the cards are shown.
enum FaultSection { engine, brakes, body, network, transmission, other }

final RegExp _saeShape = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$');

/// The section a record belongs to, by the owner's rules in order:
///
///  (a) a code the ABS module scan returned ([fromAbsScan]) is Brakes & ABS,
///      whatever its number says;
///  (b) otherwise the resolved knowledge entry's system, when it names one
///      ([knowledgeSystem]). Chassis, body and network each name a section.
///      Powertrain does NOT: the section list splits the powertrain letter
///      into Engine and Transmission, so "powertrain" cannot choose between
///      them and the number decides (rule c);
///  (c) otherwise the code's letter and number range.
///
/// Ranges (the last two characters of a group may be any hex digit, so the
/// P06A0 group belongs with P06xx):
///   Engine & emissions        P00xx–P06xx, P1xxx, P20xx–P26xx, P3xxx
///   Transmission & riding aids P07xx–P09xx, P27xx
///   Brakes & ABS              C
///   Body & instruments        B
///   Network                   U
///   Other                     anything else (P0Axx and above, P28xx and
///                             above, malformed input, blink patterns)
FaultSection faultDomainFor(FaultRecord record,
    {bool fromAbsScan = false, FaultSystem? knowledgeSystem}) {
  if (fromAbsScan) return FaultSection.brakes;
  switch (knowledgeSystem) {
    case FaultSystem.chassis:
      return FaultSection.brakes;
    case FaultSystem.body:
      return FaultSection.body;
    case FaultSystem.network:
      return FaultSection.network;
    case FaultSystem.powertrain:
    case null:
      break;
  }
  return _byNumber(record.code);
}

FaultSection _byNumber(String raw) {
  final c = raw.trim().toUpperCase();
  if (!_saeShape.hasMatch(c)) return FaultSection.other;
  switch (c[0]) {
    case 'C':
      return FaultSection.brakes;
    case 'B':
      return FaultSection.body;
    case 'U':
      return FaultSection.network;
  }
  // P
  final second = c[1];
  final third = c[2];
  if (second == '1' || second == '3') return FaultSection.engine;
  const engineGroups = '0123456';
  if (second == '0') {
    if (engineGroups.contains(third)) return FaultSection.engine;
    if ('789'.contains(third)) return FaultSection.transmission;
    return FaultSection.other;
  }
  // second == '2'
  if (engineGroups.contains(third)) return FaultSection.engine;
  if (third == '7') return FaultSection.transmission;
  return FaultSection.other;
}

/// What a card can say. The screen maps each to a plain sentence.
enum SectionStatus {
  /// No scan has covered this section.
  notScanned,

  /// A scan is running and nothing earlier is on screen.
  scanning,

  /// The module never replied. This is not "no faults".
  noAnswer,

  /// The module replied only "response pending".
  moduleBusy,

  /// The module refused the request.
  refused,

  /// The adapter link failed during the read.
  linkLost,

  /// The bike uses a connection type the app does not read yet.
  notReadable,

  /// The adapter cannot address the module.
  adapterLimited,

  /// A scan answered and this section has nothing in it.
  noFaults,

  /// A scan answered and this section has [SectionSummary.count] codes.
  found,
}

class SectionSummary {
  const SectionSummary(this.section, this.status, this.count,
      {this.fromEngineScanOnly = false, this.readAt});

  final FaultSection section;
  final SectionStatus status;

  /// Codes in this section from scans that answered. Zero unless [status] is
  /// [SectionStatus.found].
  final int count;

  /// Brakes & ABS only: its codes came from the ENGINE scan (a C-code in the
  /// engine computer's list) and the ABS module itself has not reported any.
  /// The card says where they came from instead of implying an ABS scan.
  final bool fromEngineScanOnly;

  /// Engine and Brakes & ABS only: when the scan this card describes finished,
  /// so an older result never looks live while the rider is elsewhere. Null
  /// when nothing was scanned yet, or a scan is running (its number is about
  /// to change). The other four cards never carry one: they summarise two
  /// scans and have no read time of their own.
  final DateTime? readAt;
}

/// How the ABS summary chip reads.
enum SummaryTone {
  /// The module answered and has no codes: the only green.
  clean,

  /// The module answered and has codes.
  faults,

  /// No answer, not scanned, or a scan running: no number, no colour claim.
  neutral,
}

class AbsSummary {
  const AbsSummary(this.tone, this.noteKey);

  final SummaryTone tone;

  /// `AppStrings` key for the words beside the chip, or null to keep the
  /// module name. Always an existing ABS outcome string.
  final String? noteKey;

  /// A count is only a fact when the module answered.
  bool get showsCount => tone != SummaryTone.neutral;
}

/// What the ABS summary chip says for [outcome]. A code count of zero is shown
/// as "0" in green only for [ChassisScanOutcome.clean]; every other state that
/// has no codes on screen (never scanned, no reply, busy, adapter limit, link
/// lost, scan running) is neutral, so an unreached module is never shown as a
/// healthy one.
AbsSummary absSummaryFor(ChassisScanOutcome outcome, {required bool scanning}) {
  if (scanning) return const AbsSummary(SummaryTone.neutral, 'sectionScanning');
  switch (outcome) {
    case ChassisScanOutcome.clean:
      return const AbsSummary(SummaryTone.clean, null);
    case ChassisScanOutcome.faultsFound:
      return const AbsSummary(SummaryTone.faults, null);
    case ChassisScanOutcome.idle:
      return const AbsSummary(SummaryTone.neutral, 'sectionNotScanned');
    case ChassisScanOutcome.noModuleResponse:
      return const AbsSummary(SummaryTone.neutral, 'absNoModule');
    case ChassisScanOutcome.moduleBusy:
      return const AbsSummary(SummaryTone.neutral, 'absModuleBusyTitle');
    case ChassisScanOutcome.addressingUnsupported:
      return const AbsSummary(SummaryTone.neutral, 'absAddressingUnsupported');
    case ChassisScanOutcome.linkUnavailable:
      return const AbsSummary(SummaryTone.neutral, 'connectionFailed');
  }
}

/// One code from a scan that answered, with its section and its source.
class FoundCode {
  const FoundCode(this.code, this.fromAbs, this.section);
  final DtcCode code;
  final bool fromAbs;
  final FaultSection section;
}

/// Every code from a scan that ANSWERED, tagged. A read that did not answer
/// contributes nothing — its leftover list from an earlier answer is not
/// current and is not counted.
///
/// [knowledgeSystemOf] supplies rule (b) for a code; omit it for rule (c)
/// alone.
List<FoundCode> foundCodes({
  required EngineDtcRead? engineRead,
  required List<DtcCode> engineCodes,
  required ChassisScanOutcome absOutcome,
  required List<DtcCode> absCodes,
  FaultSystem? Function(DtcCode code)? knowledgeSystemOf,
}) {
  final out = <FoundCode>[];
  if (engineRead is EngineAnswered) {
    for (final c in engineCodes) {
      final r = c.record ?? FaultRecord.fromDtcCode(c, readAt: engineRead.at);
      out.add(FoundCode(
          c, false, faultDomainFor(r, knowledgeSystem: knowledgeSystemOf?.call(c))));
    }
  }
  if (absOutcome == ChassisScanOutcome.faultsFound) {
    for (final c in absCodes) {
      final r = c.record ?? FaultRecord.fromDtcCode(c, readAt: DateTime.now());
      out.add(FoundCode(c, true, faultDomainFor(r, fromAbsScan: true)));
    }
  }
  return List<FoundCode>.unmodifiable(out);
}

/// The codes in [section]; null is "All".
List<FoundCode> filterBySection(List<FoundCode> found, FaultSection? section) =>
    section == null
        ? found
        : <FoundCode>[
            for (final f in found)
              if (f.section == section) f
          ];

/// The six cards, always in [FaultSection.values] order.
///
/// Engine and Brakes & ABS report their own scan. The other four report only
/// what the two scans that did answer found; with neither answered they say
/// "not scanned", and an unanswered scan never turns them into "none found".
List<SectionSummary> summariseSections({
  required EngineDtcRead? engineRead,
  required bool engineScanning,
  required List<DtcCode> engineCodes,
  required ChassisScanOutcome absOutcome,
  required bool absScanning,
  required List<DtcCode> absCodes,
  DateTime? absReadAt,
  FaultSystem? Function(DtcCode code)? knowledgeSystemOf,
}) {
  final found = foundCodes(
    engineRead: engineRead,
    engineCodes: engineCodes,
    absOutcome: absOutcome,
    absCodes: absCodes,
    knowledgeSystemOf: knowledgeSystemOf,
  );
  int countOf(FaultSection s) => found.where((f) => f.section == s).length;

  final engineAnswered = engineRead is EngineAnswered;
  final absAnswered = absOutcome == ChassisScanOutcome.clean ||
      absOutcome == ChassisScanOutcome.faultsFound;
  final anyAnswered = engineAnswered || absAnswered;

  SectionStatus engineStatus() {
    final n = countOf(FaultSection.engine);
    switch (engineRead) {
      case null:
        return engineScanning ? SectionStatus.scanning : SectionStatus.notScanned;
      case EngineAnswered():
        return n > 0 ? SectionStatus.found : SectionStatus.noFaults;
      case EngineNoAnswer(:final reason):
        return reason == EngineNoAnswerReason.moduleBusy
            ? SectionStatus.moduleBusy
            : SectionStatus.noAnswer;
      case EngineRefused():
        return SectionStatus.refused;
      case EngineLinkLost():
        return SectionStatus.linkLost;
      case EngineKLineGated():
        return SectionStatus.notReadable;
    }
  }

  SectionStatus brakesStatus(int n) {
    if (absScanning) return SectionStatus.scanning;
    if (n > 0) return SectionStatus.found;
    switch (absOutcome) {
      case ChassisScanOutcome.idle:
        return SectionStatus.notScanned;
      case ChassisScanOutcome.clean:
      case ChassisScanOutcome.faultsFound:
        return SectionStatus.noFaults;
      case ChassisScanOutcome.noModuleResponse:
        return SectionStatus.noAnswer;
      case ChassisScanOutcome.addressingUnsupported:
        return SectionStatus.adapterLimited;
      case ChassisScanOutcome.linkUnavailable:
        return SectionStatus.linkLost;
      case ChassisScanOutcome.moduleBusy:
        return SectionStatus.moduleBusy;
    }
  }

  return <SectionSummary>[
    for (final s in FaultSection.values)
      switch (s) {
        FaultSection.engine => SectionSummary(
            s,
            engineStatus(),
            engineAnswered ? countOf(s) : 0,
            readAt: engineScanning ? null : engineRead?.at),
        FaultSection.brakes => () {
            final n = countOf(s);
            final fromEngineOnly = n > 0 &&
                !found.any((f) => f.section == s && f.fromAbs) &&
                !absScanning;
            // The time of the scan the card's words describe: the ABS scan
            // when there is one, the engine read when its C codes are all
            // there is.
            final DateTime? at = absScanning
                ? null
                : absOutcome != ChassisScanOutcome.idle
                    ? absReadAt
                    : (fromEngineOnly ? engineRead?.at : null);
            return SectionSummary(s, brakesStatus(n), n,
                fromEngineScanOnly: fromEngineOnly, readAt: at);
          }(),
        _ => SectionSummary(
            s,
            countOf(s) > 0
                ? SectionStatus.found
                : (anyAnswered ? SectionStatus.noFaults : SectionStatus.notScanned),
            countOf(s)),
      },
  ];
}

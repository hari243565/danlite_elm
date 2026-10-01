/// Danlite ELM — the honest Clear Codes record (fault Phase 1B, B9).
///
/// INTERNAL ONLY. What the rider sees when clearing — the dialog, the erase,
/// the one success message, its colour and timing — is exactly as before;
/// nothing here is shown on the Fault Codes screen, in the History list or in
/// Share. Around the existing flow it records:
///
///  1. before the clear: the last ANSWERED engine read, if it is at most
///     [kPreClearSnapshotMaxAge] old, as the pre-clear snapshot — otherwise
///     "no snapshot";
///  2. after the existing flow has finished and its message is shown: ONE
///     silent stored-code re-read (`ObdService.checkStoredCodesSilently`,
///     bounded, cancellable, never awaited by the UI), and its outcome —
///     codes returned, cleared and verified, or could not verify.
///
/// The owner's rule that the rider always reads "Codes cleared successfully"
/// stands; this record is what makes a refused or ineffective clear visible
/// to whoever later looks at the stored history, instead of lost.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/fault_record.dart';
import '../services/obd_service.dart';
import 'history_recorder.dart';
import 'knowledge_service.dart';
import 'scan_history.dart';

/// How old the last answered read may be to count as the pre-clear snapshot.
const Duration kPreClearSnapshotMaxAge = Duration(seconds: 60);

class PreClearSnapshot {
  const PreClearSnapshot._(this.codes, this.readAt);

  /// No answered read within [kPreClearSnapshotMaxAge] before the clear.
  static const PreClearSnapshot none = PreClearSnapshot._(null, null);

  /// Null when there is no snapshot; may be empty (the bike answered "none").
  final List<String>? codes;
  final DateTime? readAt;

  bool get present => codes != null;

  /// Take the snapshot from [obd] at [now] — synchronously, before the clear
  /// sends anything.
  factory PreClearSnapshot.capture(ObdService obd, DateTime now) {
    final read = obd.lastEngineRead;
    if (read is! EngineAnswered) return none;
    final age = now.difference(read.at);
    // A read stamped in the future (clock moved back) is not trusted either.
    if (age.isNegative || age > kPreClearSnapshotMaxAge) return none;
    return PreClearSnapshot._(
        List<String>.unmodifiable(read.codes.map((c) => c.code)), read.at);
  }

  Map<String, Object?> toJson() => present
      ? <String, Object?>{
          'snapshot': true,
          'codes': codes,
          'read_at': readAt!.toUtc().toIso8601String(),
        }
      : <String, Object?>{'snapshot': false};
}

ClearCheckOutcome clearCheckOutcomeOf(StoredCodesCheck c) => switch (c) {
      StoredCodesPresent() => ClearCheckOutcome.codesReturned,
      StoredCodesEmpty() => ClearCheckOutcome.clearedVerified,
      StoredCodesUnknown() => ClearCheckOutcome.couldNotVerify,
    };

class ClearCodesRecorder {
  ClearCodesRecorder({
    required this.obd,
    required this.knowledge,
    required this.vehicle,
  });

  final ObdService obd;
  final KnowledgeService? knowledge;
  final VehicleSnapshot vehicle;

  bool _cancelled = false;

  /// Stop the silent re-read at its next safe point (it records
  /// "could not verify").
  void cancel() => _cancelled = true;

  /// Run the silent re-read and save the record. Never throws; the caller
  /// does not await it.
  Future<ClearCheckOutcome> verifyAndRecord(PreClearSnapshot snapshot,
      {ClearDtcsOutcome? clearOutcome}) async {
    StoredCodesCheck check;
    try {
      check = await obd.checkStoredCodesSilently(isCancelled: () => _cancelled);
    } catch (e) {
      check = StoredCodesUnknown('error', DateTime.now());
    }
    final outcome = clearCheckOutcomeOf(check);
    try {
      final k = knowledge;
      if (k != null) {
        await k.start();
        final history = k.history;
        if (history != null) {
          final s = obd.session;
          await history.save(ScanSessionInput(
            kind: SessionKind.clearCheck,
            startedAt: check.at,
            reachState: outcome.db,
            clearOutcome: outcome,
            connectionId: s == null ? null : '${s.transport}:${s.startedAt.microsecondsSinceEpoch}',
            profileId: vehicle.profileId,
            vehicleLabel: vehicle.label,
            adapterClass: adapterClassOf(obd),
            protocol: s?.protocol.toString(),
            coalesce: false,
            preClear: <String, Object?>{
              ...snapshot.toJson(),
              if (clearOutcome != null) 'clear_service_outcome': clearOutcome.name,
              if (check is StoredCodesUnknown) 'check_reason': check.reason,
            },
            faults: [
              if (check is StoredCodesPresent)
                for (final code in check.codes)
                  ScanFaultInput(FaultRecord.fromObdCode(code,
                      source: ReadSource.mode03, readAt: check.at)),
            ],
          ));
        }
      }
    } catch (e) {
      debugPrint('[clear-record] save failed (${e.runtimeType})');
    }
    return outcome;
  }
}

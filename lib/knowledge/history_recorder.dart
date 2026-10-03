/// Danlite ELM — saves every engine and ABS read to the scan history.
///
/// Listens to [ObdService] from outside, so the read paths themselves are not
/// changed. An engine read is saved once its whole job (core and extras) has
/// settled, so the session carries the lamp, engine state and voltage band of
/// that read. Every outcome is saved — answered, did not answer, busy,
/// refused, link lost, K-line not read — because "the bike did not answer at
/// 09:14" is part of the record. The 5-second automatic re-read would
/// otherwise fill the 50-session cap in four minutes, so identical
/// consecutive reads on one connection are folded into one session
/// (`repeat_count`, `last_seen_at`); any change starts a new one. Each ABS
/// scan is its own session.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/chassis_modules.dart';
import '../models/vehicle_data.dart';
import '../providers/vehicle_provider.dart';
import '../services/obd_service.dart';
import 'fault_resolver.dart';
import 'knowledge_service.dart';
import 'scan_history.dart';

/// Who the scan was for, without anything identifying the rider or the VIN.
class VehicleSnapshot {
  const VehicleSnapshot({this.profileId, this.label, this.context = VehicleContext.generic});
  final String? profileId;

  /// `make model`, as typed on the profile.
  final String? label;
  final VehicleContext context;

  static const VehicleSnapshot none = VehicleSnapshot();
}

/// The vehicle the fault screens resolve against: the active profile's make
/// and model through the exact-alias platform resolution. No profile, an
/// unknown make or an unknown model identifies nothing (generic only). The
/// profile's VIN field is never read.
VehicleSnapshot activeVehicleSnapshot(VehicleProfile? v) => v == null
    ? VehicleSnapshot.none
    : VehicleSnapshot(
        profileId: v.id,
        label: '${v.make} ${v.model}'.trim(),
        context: VehicleContext.fromProfile(
            profileId: v.id, make: v.make, model: v.model, year: v.year),
      );

/// The adapter's own name from its `ATZ` banner, trimmed to plain characters.
/// Never the Bluetooth device name or address.
String? adapterClassOf(ObdService obd) {
  final id = obd.session?.adapterIdentity;
  if (id == null) return null;
  final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9 .\-]'), '').trim();
  if (clean.isEmpty) return null;
  return clean.length > 32 ? clean.substring(0, 32) : clean;
}

String engineReachState(EngineDtcRead read) => switch (read) {
      EngineAnswered() => 'answered',
      EngineNoAnswer(:final reason) =>
        reason == EngineNoAnswerReason.moduleBusy ? 'module_busy' : 'no_answer',
      EngineRefused() => 'refused',
      EngineLinkLost() => 'link_lost',
      EngineKLineGated() => 'kline_not_read',
    };

String? absReachState(ChassisScanOutcome o) => switch (o) {
      ChassisScanOutcome.idle => null,
      ChassisScanOutcome.clean => 'clean',
      ChassisScanOutcome.faultsFound => 'faults_found',
      ChassisScanOutcome.noModuleResponse => 'no_module',
      ChassisScanOutcome.addressingUnsupported => 'addressing_unsupported',
      ChassisScanOutcome.linkUnavailable => 'link_unavailable',
      ChassisScanOutcome.moduleBusy => 'module_busy',
    };

class HistoryRecorder {
  HistoryRecorder({
    required this.obd,
    required this.knowledge,
    required this.vehicle,
    this.settleTimeout = const Duration(seconds: 40),
  });

  final ObdService obd;
  final KnowledgeService knowledge;
  final VehicleSnapshot Function() vehicle;
  final Duration settleTimeout;

  EngineDtcRead? _lastEngine;
  bool _absInFlight = false;
  Future<void> _chain = Future<void>.value();
  bool _attached = false;

  /// Completes when every save asked for so far has finished.
  Future<void> get idle => _chain;

  void attach() {
    if (_attached) return;
    _attached = true;
    _lastEngine = obd.lastEngineRead;
    _absInFlight = obd.chassisScanInFlight;
    obd.addListener(_onChange);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    obd.removeListener(_onChange);
  }

  void _onChange() {
    final read = obd.lastEngineRead;
    if (read != null && !identical(read, _lastEngine)) {
      _lastEngine = read;
      final snap = vehicle();
      _enqueue(() => _saveEngine(read, snap));
    }
    final inFlight = obd.chassisScanInFlight;
    if (_absInFlight && !inFlight) {
      final snap = vehicle();
      _enqueue(() => _saveAbs(snap));
    }
    _absInFlight = inFlight;
  }

  void _enqueue(Future<void> Function() job) {
    _chain = _chain.then((_) async {
      try {
        await job();
      } catch (e) {
        // History must never break a read. Nothing about the bike is printed.
        debugPrint('[history] save failed (${e.runtimeType})');
      }
    });
  }

  Future<void> _saveEngine(EngineDtcRead read, VehicleSnapshot v) async {
    try {
      await obd.whenEngineReadSettled().timeout(settleTimeout);
    } catch (_) {
      // Save what is known.
    }
    await knowledge.start();
    final history = knowledge.history;
    if (history == null) return;
    // The extras belong to this read only while it is still the latest one.
    final report = identical(obd.lastEngineRead, read) ? obd.engineReport : null;
    final records = read is EngineAnswered && identical(obd.lastEngineRead, read)
        ? obd.engineFaultRecords
        : read is EngineAnswered
            ? [for (final c in read.codes) c.record ?? FaultRecord.fromDtcCode(c, readAt: read.at)]
            : const <FaultRecord>[];
    final lamp = report?.lampOn;
    final rpmKnown = report?.rpm.valueOrNull != null;
    await history.save(ScanSessionInput(
      kind: SessionKind.engine,
      startedAt: read.at,
      reachState: engineReachState(read),
      connectionId: _connectionId(),
      profileId: v.profileId,
      vehicleLabel: v.label,
      adapterClass: adapterClassOf(obd),
      protocol: obd.session?.protocol.toString(),
      engineState: rpmKnown ? report!.engineState.name : null,
      voltageBand: report?.voltageLevel?.name,
      lampState: lamp == null ? null : (lamp ? 'on' : 'off'),
      faults: [
        for (final r in records) _resolved(r, v.context, FaultDomain.engine),
      ],
    ));
  }

  Future<void> _saveAbs(VehicleSnapshot v) async {
    final reach = absReachState(obd.chassisScanOutcome);
    if (reach == null) return;
    await knowledge.start();
    final history = knowledge.history;
    if (history == null) return;
    final at = obd.chassisReadAt ?? DateTime.now();
    await history.save(ScanSessionInput(
      kind: SessionKind.abs,
      startedAt: at,
      reachState: reach,
      connectionId: _connectionId(),
      profileId: v.profileId,
      vehicleLabel: v.label,
      adapterClass: adapterClassOf(obd),
      protocol: obd.session?.protocol.toString(),
      voltageBand: obd.chassisReadWhileLowVoltage ? 'low' : null,
      coalesce: false,
      faults: [
        for (final DtcCode c in obd.chassisDtcCodes)
          _resolved(c.record ?? FaultRecord.fromDtcCode(c, readAt: at), v.context,
              FaultDomain.abs),
      ],
    ));
  }

  ScanFaultInput _resolved(FaultRecord r, VehicleContext vehicle, FaultDomain domain) {
    final res = knowledge.resolve(r, vehicle, 'en', domain: domain);
    return ScanFaultInput(r, resolvedLevel: res.level.name, resolvedContentId: res.contentId);
  }

  String? _connectionId() {
    final s = obd.session;
    return s == null ? null : '${s.transport}:${s.startedAt.microsecondsSinceEpoch}';
  }
}

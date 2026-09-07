/// Danlite ELM — learned chassis/ABS module addresses
///
/// ── Why this exists ──────────────────────────────────────────────────────
/// There is no universal database of ABS module CAN addresses, and no
/// professional multi-brand scan tool has one either. What Torque Pro and Car
/// Scanner actually do is combine a broad list of candidate addresses with a
/// way for a *real, confirmed* discovery to be captured and reused instead of
/// re-derived from scratch on every scan. This file is that second half.
///
/// The first time a real motorcycle answers at one of the probe addresses in
/// `ChassisModuleProfiles`, the winning candidate is written down against that
/// vehicle's make and model. Every later scan of that same make and model
/// tries the remembered address first, before the full sweep.
///
/// ── What the scope of a remembered address is, precisely ─────────────────
/// The key is **make + model, normalised** — nothing else. It contains no user
/// id, no device id, no account, no VIN, no timestamp-derived value. Two
/// customers with the same motorcycle produce byte-identical keys. That is the
/// point: the fact being recorded is a property of the *vehicle*, not of the
/// person holding the phone, so it is stored in a form that is meaningful to
/// anyone with that vehicle.
///
/// ── And what it is not: an honest limit ──────────────────────────────────
/// What ships in this build is a local store. A discovery made on one phone
/// makes every later scan on *that* phone faster and more likely to succeed,
/// and because the key is vehicle-shaped it can be read out and promoted into
/// `ChassisModuleProfiles.byManufacturer`, which is the path by which a real
/// discovery reaches every customer with that vehicle — at the next app
/// release, not instantly. There is no live server sync in this build, and
/// this file does not pretend there is. `ChassisAddressStore` is the seam a
/// shared backend would be plugged into if one is added later; nothing above
/// it would change.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/chassis_dtc_dictionary.dart';
import '../constants/chassis_modules.dart';

/// Where learned addresses are kept.
///
/// An interface rather than a direct `SharedPreferences` call so that tests
/// can drive the real memory logic without a platform channel, and so a shared
/// backend can be substituted without touching anything that uses the memory.
abstract class ChassisAddressStore {
  /// Every remembered vehicleKey → candidate id pair. Must never throw;
  /// return an empty map when nothing is stored or storage is unavailable.
  Future<Map<String, String>> load();

  /// Persist the complete map. Must never throw.
  Future<void> save(Map<String, String> entries);
}

/// The shipped store: one JSON blob in `SharedPreferences`.
///
/// A single blob rather than a key per vehicle because the whole map is read
/// once at startup and is tiny (one short string per vehicle the phone has
/// ever scanned), and because it keeps "clear everything" a one-line operation.
class SharedPreferencesChassisAddressStore implements ChassisAddressStore {
  const SharedPreferencesChassisAddressStore();

  /// Versioned so a future format change can be recognised and discarded
  /// rather than misparsed.
  static const String prefsKey = 'chassis_learned_addresses_v1';

  @override
  Future<Map<String, String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return <String, String>{
        for (final e in decoded.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (e) {
      // A corrupt or unreadable store must degrade to "we know nothing",
      // never to a broken scan.
      debugPrint('[ChassisAddressMemory] load failed: $e');
      return <String, String>{};
    }
  }

  @override
  Future<void> save(Map<String, String> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(entries));
    } catch (e) {
      debugPrint('[ChassisAddressMemory] save failed: $e');
    }
  }
}

/// A store that keeps everything in RAM. For tests, and for the case where
/// persistence is deliberately not wanted.
class InMemoryChassisAddressStore implements ChassisAddressStore {
  InMemoryChassisAddressStore([Map<String, String>? seed])
      : _entries = <String, String>{...?seed};

  final Map<String, String> _entries;

  /// Read-only view, so a test can assert on what was actually written.
  Map<String, String> get entries => Map<String, String>.unmodifiable(_entries);

  @override
  Future<Map<String, String>> load() async => Map<String, String>.from(_entries);

  @override
  Future<void> save(Map<String, String> entries) async {
    _entries
      ..clear()
      ..addAll(entries);
  }
}

/// Remembers which candidate address a given make + model actually answered at.
class ChassisAddressMemory {
  ChassisAddressMemory({ChassisAddressStore? store})
      : _store = store ?? const SharedPreferencesChassisAddressStore();

  final ChassisAddressStore _store;

  /// vehicleKey → candidate id. Empty until [load] has run.
  final Map<String, String> _known = <String, String>{};

  bool _loaded = false;

  /// True once the persisted map has been read at least once.
  bool get isLoaded => _loaded;

  /// Everything currently remembered, for support and for the promotion path
  /// described in this file's header.
  Map<String, String> get known => Map<String, String>.unmodifiable(_known);

  /// The storage key for a vehicle: normalised make and model, nothing else.
  ///
  /// Returns null when the make is blank, because a memory keyed on nothing
  /// would apply to every vehicle. A blank *model* is allowed and is part of
  /// the key, so `Royal Enfield` with no model set never collides with
  /// `Royal Enfield / Classic 350`.
  ///
  /// Normalisation is shared with the dictionary lookup
  /// ([ChassisManufacturers.normalise]) so that "Royal Enfield", "royal
  /// enfield" and "ROYAL-ENFIELD" are one vehicle here as well as there.
  static String? vehicleKey(String? make, String? model) {
    final m = ChassisManufacturers.normalise(make ?? '');
    if (m.isEmpty) return null;
    return '$m|${ChassisManufacturers.normalise(model ?? '')}';
  }

  /// Read the persisted map. Safe to call more than once; later calls re-read.
  Future<void> load() async {
    final stored = await _store.load();
    _known
      ..clear()
      ..addAll(stored);
    _loaded = true;
  }

  /// The candidate id remembered for this vehicle, or null.
  String? knownTargetId(String? make, String? model) {
    final key = vehicleKey(make, model);
    if (key == null) return null;
    return _known[key];
  }

  /// The candidate remembered for this vehicle, resolved back to a target.
  ///
  /// Null when nothing is remembered, and also null when the remembered id is
  /// no longer in the candidate list — an address dropped by a later release
  /// must not resurrect itself out of an old phone's storage.
  ChassisModuleTarget? knownTarget(String? make, String? model) =>
      ChassisModuleProfiles.targetById(knownTargetId(make, model));

  /// Record that [target] genuinely answered for this vehicle.
  ///
  /// A no-op when the make is blank (nothing to key on) or when the value is
  /// unchanged, so a repeat scan of an already-learned vehicle does not
  /// rewrite storage on every run.
  Future<bool> remember({
    required String? make,
    required String? model,
    required ChassisModuleTarget target,
  }) async {
    final key = vehicleKey(make, model);
    if (key == null) return false;
    if (_known[key] == target.id) return false;
    _known[key] = target.id;
    await _store.save(_known);
    return true;
  }

  /// Forget what was learned for one vehicle, or for everything when [make] is
  /// null. Exists so a wrong discovery (a module that answered once and never
  /// again) is recoverable without reinstalling.
  Future<void> forget({String? make, String? model}) async {
    if (make == null) {
      _known.clear();
    } else {
      final key = vehicleKey(make, model);
      if (key == null) return;
      _known.remove(key);
    }
    await _store.save(_known);
  }

  /// [candidates] reordered so the remembered address for this vehicle is
  /// probed first.
  ///
  /// Reorder, never replace: if the remembered address has stopped answering —
  /// a repaired module, a different bike with the same make and model, a
  /// discovery that was a fluke — the full sweep still runs behind it and the
  /// scan is no worse off than if nothing had been remembered. The list is
  /// returned unchanged when nothing is remembered, so an unlearned vehicle
  /// probes in exactly the documented tier order.
  List<ChassisModuleTarget> ordered(
    List<ChassisModuleTarget> candidates, {
    required String? make,
    required String? model,
  }) {
    final id = knownTargetId(make, model);
    if (id == null) return candidates;
    final index = candidates.indexWhere((c) => c.id == id);
    if (index <= 0) return candidates; // absent, or already first
    return <ChassisModuleTarget>[
      candidates[index],
      for (var i = 0; i < candidates.length; i++)
        if (i != index) candidates[i],
    ];
  }
}

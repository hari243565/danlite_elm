/// Danlite ELM — the app's handle on the knowledge store and scan history.
///
/// Started once, after the first frame is up (`main.dart` does not await it):
/// it opens the on-phone database, imports the bundled baseline pack when it
/// is newer than the installed one (or none is installed), and loads the
/// active entries into the resolver's index. Until it is [KnowledgeState.ready]
/// the fault screen shows a loading line where the guidance goes; if it fails
/// the resolver still answers every code honestly from the older tables and
/// the code's structure.
///
/// The database lives in Android's no-backup folder: Auto Backup would
/// otherwise copy scan history off the phone. If that folder cannot be
/// reached, the store runs in memory for the session (the baseline still
/// loads; history is not kept) rather than falling back to a backed-up folder.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/fault_record.dart';
import '../services/app_version_service.dart';
import 'fault_resolver.dart';
import 'kb_models.dart';
import 'knowledge_store.dart';
import 'legacy_text.dart';
import 'scan_history.dart';

/// Where the bundled baseline pack lives in the APK.
const String kBundledPackDir = 'assets/knowledge/generic_en';

/// The database file name inside the no-backup folder.
const String kKnowledgeDbName = 'danlite_knowledge.db';

enum KnowledgeState { loading, ready, failed }

class KnowledgeService extends ChangeNotifier {
  KnowledgeService({
    required Future<KnowledgeStore> Function() openStore,
    required Future<List<int>> Function(String assetPath) loadAsset,
    Future<String> Function()? appVersion,
    this.legacy = legacyEngineText,
    DateTime Function()? clock,
  })  : _openStore = openStore,
        _loadAsset = loadAsset,
        _appVersion = appVersion ?? (() async => '1.0.0'),
        _clock = clock ?? DateTime.now;

  /// The production wiring: sqflite, the APK's assets, the real app version.
  factory KnowledgeService.forApp() => KnowledgeService(
        openStore: () async =>
            KnowledgeStore.open(databaseFactory, await _databasePath()),
        loadAsset: (path) async =>
            (await rootBundle.load(path)).buffer.asUint8List(),
        appVersion: () async =>
            AppVersionService.versionOf(await AppVersionService.load()) ?? '1.0.0',
      );

  final Future<KnowledgeStore> Function() _openStore;
  final Future<List<int>> Function(String) _loadAsset;
  final Future<String> Function() _appVersion;
  final DateTime Function() _clock;
  final LegacyTextLookup? legacy;

  KnowledgeState _state = KnowledgeState.loading;
  KnowledgeState get state => _state;

  KnowledgeStore? _store;
  KnowledgeStore? get store => _store;

  ScanHistoryStore? _history;

  /// Null until ready (or when the store could not open).
  ScanHistoryStore? get history => _history;

  /// What the last bundled import did (null when it was not needed).
  ImportOutcome? _bundledImport;
  ImportOutcome? get bundledImport => _bundledImport;

  late FaultResolver _resolver = FaultResolver(index: KnowledgeIndex.empty, legacy: legacy);
  FaultResolver get resolver => _resolver;

  Future<void>? _started;

  /// Open, import if needed, index. Safe to call any number of times.
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    try {
      final store = await _openStore();
      _store = store;
      _history = ScanHistoryStore(store.db, clock: _clock);
      _bundledImport = await _importBundledIfNewer(store);
      if (_bundledImport != null && !_bundledImport!.imported) {
        debugPrint('[knowledge] bundled pack not imported: $_bundledImport');
      }
      await reload();
      _state = KnowledgeState.ready;
    } catch (e) {
      debugPrint('[knowledge] start failed (${e.runtimeType})');
      _state = KnowledgeState.failed;
    }
    notifyListeners();
  }

  Future<ImportOutcome?> _importBundledIfNewer(KnowledgeStore store) async {
    final manifestBytes = await _loadAsset('$kBundledPackDir/manifest.json');
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    final installed = await store.pack(manifest['pack_id'] as String);
    final version = manifest['version'];
    if (installed != null && version is int && version <= installed.version) {
      return null; // installed is current (or newer, e.g. a later download)
    }
    return store.importPack(
      manifestBytes: manifestBytes,
      entriesBytes: await _loadAsset('$kBundledPackDir/entries.jsonl'),
      source: PackSource.bundled,
      appVersion: await _appVersion(),
      now: _clock(),
    );
  }

  /// Rebuild the resolver's index from the store (after any import).
  Future<void> reload() async {
    final store = _store;
    if (store == null) return;
    _resolver = FaultResolver(
        index: KnowledgeIndex(await store.activeEntries()), legacy: legacy);
    notifyListeners();
  }

  ResolvedFault resolve(FaultRecord record, VehicleContext vehicle, String language,
          {FaultDomain domain = FaultDomain.unknown}) =>
      _resolver.resolve(record, vehicle, language, domain: domain);

  @override
  void dispose() {
    _store?.close();
    super.dispose();
  }

  static const MethodChannel _channel = MethodChannel('com.danlite.elm/session_recorder');

  /// The database path: Android's no-backup folder; the platform default
  /// elsewhere; in memory if Android's folder cannot be reached.
  static Future<String> _databasePath() async {
    if (Platform.isAndroid) {
      try {
        final dir = await _channel.invokeMethod<String>('knowledgeDirectory');
        if (dir != null && dir.isNotEmpty) return p.join(dir, kKnowledgeDbName);
      } catch (e) {
        debugPrint('[knowledge] no-backup folder unavailable (${e.runtimeType})');
      }
      return inMemoryDatabasePath;
    }
    return p.join(await getDatabasesPath(), kKnowledgeDbName);
  }
}

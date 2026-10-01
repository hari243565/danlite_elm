/// A real KnowledgeService over a temp SQLite file (desktop SQLite through
/// sqflite_common_ffi), loading the REAL bundled pack from disk.
library;

import 'dart:io';

import 'package:danlite_elm/knowledge/knowledge_service.dart';
import 'package:danlite_elm/knowledge/knowledge_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> tempDbPath() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('danlite_ks_');
  return '${dir.path}${Platform.pathSeparator}kb.db';
}

KnowledgeService knowledgeAt(String path, {DateTime Function()? clock}) =>
    KnowledgeService(
      openStore: () => KnowledgeStore.open(databaseFactoryFfi, path),
      loadAsset: (p) => File(p).readAsBytes(),
      clock: clock,
    );

/// Started and ready.
Future<KnowledgeService> startedKnowledge({DateTime Function()? clock}) async {
  final k = knowledgeAt(await tempDbPath(), clock: clock);
  await k.start();
  return k;
}

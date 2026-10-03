/// Danlite ELM — "Look up a code": type a code or words, read what it means.
/// Works with no adapter, no bike and no network. Thin: the search is
/// `code_lookup.dart`, the meaning is the resolver's.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../knowledge/code_lookup.dart';
import '../knowledge/fault_resolver.dart';
import '../knowledge/knowledge_service.dart';
import '../knowledge/legacy_text.dart';
import '../models/fault_record.dart';
import '../providers/settings_provider.dart';
import '../providers/vehicle_provider.dart';
import '../services/dtc_service.dart';
import '../services/fault_decoders.dart' show FailureType;
import '../widgets/resolved_fault_view.dart';
import '../knowledge/history_recorder.dart' show activeVehicleSnapshot;

class _C {
  static const Color bg = Color(0xFF07090E);
  static const Color surface = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color textMain = Color(0xFFEEF2F8);
  static const Color textMuted = Color(0xFF607080);
  static const Color amber = Color(0xFFFF8A00);
}

/// The resolver for the lookup: the app's knowledge service, or the older
/// tables alone when there is none.
ResolvedFault _resolve(BuildContext context, String code, DtcFormat format) {
  final lang = context.watch<SettingsProvider>().locale.languageCode;
  final vehicle =
      activeVehicleSnapshot(context.watch<VehicleProvider>().active).context;
  final record = lookupRecord(code, format);
  final k = Provider.of<KnowledgeService?>(context);
  return k != null
      ? k.resolve(record, vehicle, lang)
      : FaultResolver(index: KnowledgeIndex.empty, legacy: legacyEngineText)
          .resolve(record, vehicle, lang);
}

String _scopeName(BuildContext context, LookupResult r) => switch (r.scope) {
      LookupScope.generic => context.tr('lookupScopeGeneric'),
      LookupScope.moduleFamily => context.tr('lookupScopeBosch'),
      _ => r.scopeName ?? r.scopeRef,
    };

class CodeLookupScreen extends StatefulWidget {
  const CodeLookupScreen({super.key, this.debounce = const Duration(milliseconds: 250)});

  /// Typing pause before searching; tests pass zero.
  final Duration debounce;

  @override
  State<CodeLookupScreen> createState() => _CodeLookupScreenState();
}

class _CodeLookupScreenState extends State<CodeLookupScreen> {
  final _controller = TextEditingController();
  Timer? _timer;
  LookupQuery _query = const LookupQuery();
  LookupResults _results = LookupResults.empty;
  int _generation = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => _search(text));
  }

  Future<void> _search(String text) async {
    final gen = ++_generation;
    final q = parseLookupQuery(text);
    final lang = context.read<SettingsProvider>().locale.languageCode;
    final k = Provider.of<KnowledgeService?>(context, listen: false);
    final results = await searchCodes(q, store: k?.store, language: lang);
    if (!mounted || gen != _generation) return; // a newer search won
    setState(() {
      _query = q;
      _results = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final k = Provider.of<KnowledgeService?>(context);
    final snap = activeVehicleSnapshot(context.watch<VehicleProvider>().active);
    final typedCode = _query.codes.isEmpty ? null : _query.codes.first;
    final directMissing = typedCode != null &&
        !_results.items.any((r) => _query.codes.contains(r.code));
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.surface,
        title: Text(context.tr('lookupTitle'),
            style: const TextStyle(color: _C.textMain, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: _C.textMain),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: _search,
            style: const TextStyle(color: _C.textMain, fontSize: 16),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: context.tr('lookupHint'),
              hintStyle: const TextStyle(color: _C.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, color: _C.textMuted),
              filled: true,
              fillColor: _C.card,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _C.border)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            snap.context.identifiesVehicle
                ? context.trArgs('lookupForVehicle', {'v': snap.label ?? ''})
                : context.tr('lookupGenericOnly'),
            style: const TextStyle(color: _C.textMuted, fontSize: 12),
          ),
          if (k?.state == KnowledgeState.loading) ...[
            const SizedBox(height: 6),
            Text(context.tr('knowledgeLoading'),
                style: const TextStyle(color: _C.amber, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          if (_query.isEmpty)
            Text(context.tr('lookupIntro'),
                style: const TextStyle(color: _C.textMuted, fontSize: 13, height: 1.5))
          else ...[
            if (directMissing)
              _DirectTile(code: typedCode, format: _query.format),
            for (final r in _results.items) _ResultTile(r),
            if (_results.items.isEmpty && !directMissing)
              Text(context.trArgs('lookupNoResults', {'q': _query.raw}),
                  style: const TextStyle(color: _C.textMuted, fontSize: 13, height: 1.5)),
            if (_results.capped)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(context.tr('lookupCapped'),
                    style: const TextStyle(color: _C.textMuted, fontSize: 12)),
              ),
          ],
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile(this.r);
  final LookupResult r;

  @override
  Widget build(BuildContext context) => _Tile(
        code: r.code,
        subtitle: _scopeName(context, r),
        title: r.title,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CodeLookupDetailScreen(
                code: r.code, format: r.format, listedIn: r))),
      );
}

/// A well-formed typed code with no listed meaning: still opens the
/// resolver's honest answer (structure, or "manufacturer-specific").
class _DirectTile extends StatelessWidget {
  const _DirectTile({required this.code, required this.format});
  final String code;
  final DtcFormat format;

  @override
  Widget build(BuildContext context) {
    final r = _resolve(context, code, format);
    return _Tile(
      code: code,
      subtitle: context.tr(r.provenance.labelKey),
      title: describeResolved(context, r),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CodeLookupDetailScreen(code: code, format: format))),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.code, required this.subtitle, required this.title, required this.onTap});
  final String code;
  final String subtitle;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _C.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(code,
                    style: const TextStyle(
                        color: _C.textMain,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        fontSize: 15)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _C.textMain, fontSize: 13, height: 1.3)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(color: _C.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _C.textMuted),
            ],
          ),
        ),
      );
}

/// The main line for a resolved code: its title, or the honest "no meaning"
/// wording for its level.
String describeResolved(BuildContext context, ResolvedFault r) {
  final t = r.title ?? '';
  if (t.isNotEmpty) return t;
  if (r.structure?.manufacturerDefined ?? false) {
    return context.tr('dtcManufacturerSpecific');
  }
  // A standard code none of the content describes (L5), or no code at all (L6).
  return context.tr('faultRawShowDealer');
}

/// What one code means for the rider's vehicle — the resolver's answer.
class CodeLookupDetailScreen extends StatelessWidget {
  const CodeLookupDetailScreen(
      {super.key, required this.code, required this.format, this.listedIn});
  final String code;
  final DtcFormat format;

  /// The search result the rider tapped, when there was one.
  final LookupResult? listedIn;

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(label.toUpperCase(),
                  style: const TextStyle(
                      color: _C.textMuted, fontSize: 9.5, fontWeight: FontWeight.w800)),
            ),
            Expanded(
                child: Text(value,
                    style: const TextStyle(color: _C.textMain, fontSize: 12.5, height: 1.35))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = _resolve(context, code, format);
    final lang = context.watch<SettingsProvider>().locale.languageCode;
    final listed = listedIn;
    // The tapped result named a table that did not answer for this vehicle.
    final otherScope = listed != null &&
        listed.scope != LookupScope.generic &&
        !(r.level == ResolvedLevel.l2Platform || r.level == ResolvedLevel.l3ModuleFamily);
    final structure = r.structure;
    final detail = r.platformDetail;
    final legacy = r.provenance == Provenance.legacyTable;
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.surface,
        title: Text(r.displayCode,
            style: const TextStyle(
                color: _C.textMain, fontFamily: 'monospace', fontWeight: FontWeight.w900)),
        iconTheme: const IconThemeData(color: _C.textMain),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (r.riderAction != null)
            Align(alignment: Alignment.centerLeft, child: FaultActionChip(r)),
          const SizedBox(height: 8),
          Text(describeResolved(context, r),
              style: const TextStyle(
                  color: _C.textMain, fontSize: 17, fontWeight: FontWeight.w800, height: 1.3)),
          if (structure != null) ...[
            if (structure.system != null)
              _row(context.tr('dtcSubsystem'),
                  [
                    DtcLocalizations.categoryHeader(code, lang),
                    if (structure.subsystemKey != null) context.tr(structure.subsystemKey!),
                  ].join(' · ')),
            if (structure.failureType != null)
              _row(context.tr('faultFailureType'),
                  '${FailureType.hex(structure.failureType!)} · ${FailureType.describe(structure.failureType!, lang)}'),
          ],
          if (r.rawModuleLabel != null) _row(context.tr('absRawModuleCode'), r.rawModuleLabel!),
          if (detail != null) ...[
            if (detail.component.isNotEmpty) _row(context.tr('absComponent'), detail.component),
            if (detail.query.isNotEmpty) _row(context.tr('absQuery'), detail.query),
            if (detail.remedy.isNotEmpty) _row(context.tr('absRemedy'), detail.remedy),
          ],
          if (legacy) ...[
            for (final c in r.causes) _row(context.tr('possibleCause'), c),
            if ((r.riderAdvice ?? '').isNotEmpty)
              _row(context.tr('recommendedAction'), r.riderAdvice!),
          ],
          if (r.provenance.isStoreGuidance)
            ResolvedGuidance(r, showHints: true)
          else
            ProvenanceLine(r),
          if (otherScope) ...[
            const SizedBox(height: 14),
            Text(context.trArgs('lookupOtherScope', {'scope': _scopeName(context, listed)}),
                style: const TextStyle(color: _C.amber, fontSize: 12, height: 1.45)),
          ],
          const SizedBox(height: 14),
          Text(context.tr('lookupNotReadNote'),
              style: const TextStyle(color: _C.textMuted, fontSize: 11.5, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

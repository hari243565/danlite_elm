/// Danlite ELM — Honda ABS Blink Code Reference (manual lookup, NOT a scan)
///
/// ── What this screen is, and what it deliberately is not ─────────────────
/// Every other diagnostic surface in this app reads something off the vehicle.
/// This one reads nothing. It cannot: on the majority of Honda's ABS lineup
/// the stored ABS fault is retrieved by bridging the DLC connector and
/// counting flashes of the ABS warning lamp, and that code never travels over
/// the CAN bus at all. There is no electrical path from a Bluetooth OBD
/// adapter to it — not a missing feature, not an adapter limitation, simply a
/// different mechanism.
///
/// So the honest product is a lookup table: the rider counts the flashes on
/// the motorcycle, enters the pattern here, and gets Honda's own published
/// description and remedy guidance. That framing is load-bearing rather than
/// cosmetic, which is why the "manual reference — not a live scan" statement is
/// the first thing on the screen, is repeated in the intro copy, and why there
/// is no scan button anywhere on it.
///
/// ── Where the data comes from ────────────────────────────────────────────
/// Nowhere in this file. Every string a rider reads about a fault comes from
/// [ChassisDtcDatabase] via [DtcLocalizations.chassisEntry], exactly as the
/// live fault cards do, so the reference tool and a scan can never disagree
/// about what a code means, and Hindi resolution is the same single code path.
/// The pattern pickers derive their available digits from the table's own keys
/// rather than from hardcoded ranges, so adding or removing a documented code
/// is still a data-only change.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../constants/chassis_dtc_dictionary.dart';
import '../providers/settings_provider.dart';
import '../services/dtc_service.dart';

// Unified Telemetry Design System palette, matching dtc_screen._RC.
class _BC {
  static const Color bg = Color(0xFF07090E);
  static const Color surface = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color textMain = Color(0xFFEEF2F8);
  static const Color textMuted = Color(0xFF607080);
  static const Color neonCyan = Color(0xFF00CAFF);
  static const Color neonAmber = Color(0xFFFF8A00);
  static const Color neonRed = Color(0xFFFF3D3D);
}

class HondaBlinkReferenceScreen extends StatefulWidget {
  const HondaBlinkReferenceScreen({super.key});

  /// The two flash-count picker rows. Named rather than found by content
  /// because their digit sets overlap: "3" is both a valid long-flash count
  /// and a valid short-flash count, so a test that searched for the digit
  /// alone would silently drive the wrong half of the pattern.
  static const Key longFlashRowKey = ValueKey<String>('blinkRefLongFlashes');
  static const Key shortFlashRowKey = ValueKey<String>('blinkRefShortFlashes');

  @override
  State<HondaBlinkReferenceScreen> createState() =>
      _HondaBlinkReferenceScreenState();
}

class _HondaBlinkReferenceScreenState extends State<HondaBlinkReferenceScreen> {
  /// The platform whose table this screen lists. Fixed: this screen exists for
  /// exactly one dataset, and pointing it at another would make its
  /// blink-count UI describe something that is not counted in blinks.
  static const String _platform = ChassisPlatforms.hondaAbsBlink;

  /// The documented codes, in the table's own order.
  static final List<String> _codes =
      ChassisDtcDatabase.byPlatform[_platform]!.keys.toList(growable: false);

  /// The digits that actually appear in the table, derived from it rather than
  /// assumed, so the pickers can never offer a combination the data has no
  /// concept of — or hide one it does.
  static final List<int> _longFlashOptions = _digitsAt(0);
  static final List<int> _shortFlashOptions = _digitsAt(1);

  static List<int> _digitsAt(int position) {
    final values = <int>{};
    for (final code in _codes) {
      final parts = code.split('-');
      if (parts.length != 2) continue;
      final n = int.tryParse(parts[position]);
      if (n != null) values.add(n);
    }
    final sorted = values.toList()..sort();
    return List<int>.unmodifiable(sorted);
  }

  late int _long = _longFlashOptions.first;
  late int _short = _shortFlashOptions.first;

  String get _pattern => '$_long-$_short';

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().locale.languageCode;
    final selected =
        DtcLocalizations.chassisEntry(_platform, _pattern, lang);

    return Scaffold(
      backgroundColor: _BC.bg,
      appBar: AppBar(
        backgroundColor: _BC.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: _BC.textMain),
        title: Text(context.tr('blinkRefTitle'),
            style: const TextStyle(
                color: _BC.textMain, fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _BC.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          _manualOnlyBanner(context),
          const SizedBox(height: 14),
          _howToSection(context),
          const SizedBox(height: 14),
          _patternPicker(context),
          const SizedBox(height: 12),
          _resultCard(context, selected),
          const SizedBox(height: 22),
          _fullTable(context, lang),
          const SizedBox(height: 18),
          Text(context.tr('blinkRefSource'),
              style: const TextStyle(
                  color: _BC.textMuted, fontSize: 11, height: 1.5)),
        ],
      ),
    );
  }

  /// The screen's most important element. A rider who takes this for a live
  /// readout of their own motorcycle has been actively misinformed, so the
  /// statement is placed above everything else and worded without hedging.
  Widget _manualOnlyBanner(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _BC.neonAmber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _BC.neonAmber.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_rounded,
                    size: 16, color: _BC.neonAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr('blinkRefManualBadge'),
                      style: const TextStyle(
                          color: _BC.neonAmber,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.tr('blinkRefIntro'),
                style: const TextStyle(
                    color: _BC.textMuted, fontSize: 12, height: 1.5)),
          ],
        ),
      );

  Widget _howToSection(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _BC.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _BC.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('blinkRefHowTo'),
                style: const TextStyle(
                    color: _BC.textMain,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text(context.tr('blinkRefHowToBody'),
                style: const TextStyle(
                    color: _BC.textMuted, fontSize: 12, height: 1.55)),
          ],
        ),
      );

  Widget _patternPicker(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 15),
        decoration: BoxDecoration(
          color: _BC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _BC.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _digitRow(
              context,
              // Both rows offer overlapping digits — 3 is a valid long-flash
              // count and a valid short-flash count — so the rows carry keys
              // rather than relying on their contents to tell them apart.
              key: HondaBlinkReferenceScreen.longFlashRowKey,
              label: context.tr('blinkRefLongFlashes'),
              options: _longFlashOptions,
              value: _long,
              onPick: (v) => setState(() => _long = v),
            ),
            const SizedBox(height: 14),
            _digitRow(
              context,
              key: HondaBlinkReferenceScreen.shortFlashRowKey,
              label: context.tr('blinkRefShortFlashes'),
              options: _shortFlashOptions,
              value: _short,
              onPick: (v) => setState(() => _short = v),
            ),
          ],
        ),
      );

  Widget _digitRow(
    BuildContext context, {
    required Key key,
    required String label,
    required List<int> options,
    required int value,
    required ValueChanged<int> onPick,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                color: _BC.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              GestureDetector(
                onTap: () => onPick(option),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 42,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option == value
                        ? _BC.neonCyan.withValues(alpha: 0.16)
                        : _BC.bg,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: option == value
                            ? _BC.neonCyan.withValues(alpha: 0.65)
                            : _BC.border),
                  ),
                  child: Text('$option',
                      style: TextStyle(
                          color: option == value ? _BC.neonCyan : _BC.textMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace')),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The looked-up entry, or an honest "this pattern is not in the table".
  ///
  /// The pickers offer every digit the table uses, so plenty of combinations
  /// of them (2-2, 5-3…) have no documented code. Saying so is the correct
  /// answer; inventing a fault for an undocumented pattern is exactly what the
  /// dictionary's own rules forbid.
  Widget _resultCard(BuildContext context, ChassisDtcResolved? entry) {
    if (entry == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _BC.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _BC.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _patternHeader(context, _BC.textMuted),
            const SizedBox(height: 10),
            Text(context.tr('blinkRefNoMatch'),
                style: const TextStyle(
                    color: _BC.textMain,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(context.tr('blinkRefNoMatchDesc'),
                style: const TextStyle(
                    color: _BC.textMuted, fontSize: 12, height: 1.5)),
          ],
        ),
      );
    }

    // Every documented entry in this table is a braking-system fault, which is
    // why the dictionary bands them all as critical; the card colour follows
    // that rather than deciding severity for itself.
    final accent =
        entry.meaningVerified ? _BC.neonRed : _BC.neonAmber;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _BC.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _patternHeader(context, accent),
              const Spacer(),
              if (!entry.meaningVerified)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _BC.neonAmber.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(context.tr('absRawUnverified'),
                      style: const TextStyle(
                          color: _BC.neonAmber,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(entry.description,
              style: const TextStyle(
                  color: _BC.textMain,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.35)),
          if (entry.remedy.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(context.tr('absRemedy').toUpperCase(),
                style: const TextStyle(
                    color: _BC.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
            const SizedBox(height: 5),
            Text(entry.remedy,
                style: const TextStyle(
                    color: _BC.neonCyan, fontSize: 12.5, height: 1.5)),
          ],
        ],
      ),
    );
  }

  Widget _patternHeader(BuildContext context, Color accent) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${context.tr('blinkRefPattern').toUpperCase()}  ',
              style: const TextStyle(
                  color: _BC.textMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          Text(_pattern,
              style: TextStyle(
                  color: accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: 1)),
        ],
      );

  /// The whole documented table, so a rider can scan it rather than hunt for a
  /// pattern one combination at a time — and so the coverage of the built-in
  /// data is visible instead of having to be trusted.
  Widget _fullTable(BuildContext context, String lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('blinkRefFullTable').toUpperCase(),
            style: const TextStyle(
                color: _BC.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9)),
        const SizedBox(height: 10),
        for (final code in _codes)
          Builder(builder: (context) {
            final entry = DtcLocalizations.chassisEntry(_platform, code, lang);
            if (entry == null) return const SizedBox.shrink();
            final isSelected = code == _pattern;
            return GestureDetector(
              onTap: () {
                final parts = code.split('-');
                setState(() {
                  _long = int.parse(parts[0]);
                  _short = int.parse(parts[1]);
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _BC.neonCyan.withValues(alpha: 0.08)
                      : _BC.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: isSelected
                          ? _BC.neonCyan.withValues(alpha: 0.45)
                          : _BC.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(code,
                          style: const TextStyle(
                              color: _BC.textMain,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace')),
                    ),
                    Expanded(
                      child: Text(entry.description,
                          style: TextStyle(
                              color: entry.meaningVerified
                                  ? _BC.textMuted
                                  : _BC.neonAmber,
                              fontSize: 12,
                              height: 1.4)),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

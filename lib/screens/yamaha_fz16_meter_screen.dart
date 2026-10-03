/// Danlite ELM — Yamaha FZ-16 FI meter-code reference (manual look-up, NOT a
/// scan).
///
/// Follows the Royal Enfield blink reference's pattern: the first thing on the
/// screen says this reads nothing from the bike and there is no scan button.
///
/// Differences, on purpose:
///  * the code is a NUMBER on the meter, not a flash count, so the rider types
///    it instead of choosing two counts;
///  * it says which bike it is for (the older FZ-16 FI) and that it has not
///    been confirmed for newer FZ-S FI models;
///  * only two codes are verified; the screen says plainly that other codes
///    exist and are not listed, always, and again when a number is not found;
///  * nothing is pre-selected.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_strings.dart';
import '../constants/yamaha_fz16_meter.dart';

// Unified Telemetry Design System palette, matching dtc_screen._RC.
class _YC {
  static const Color bg = Color(0xFF07090E);
  static const Color surface = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color textMain = Color(0xFFEEF2F8);
  static const Color textMuted = Color(0xFF607080);
  static const Color neonCyan = Color(0xFF00CAFF);
  static const Color neonAmber = Color(0xFFFF8A00);
}

class YamahaFz16MeterScreen extends StatefulWidget {
  const YamahaFz16MeterScreen({super.key});

  /// The number field.
  static const Key inputKey = ValueKey<String>('fz16Input');

  @override
  State<YamahaFz16MeterScreen> createState() => _YamahaFz16MeterScreenState();
}

class _YamahaFz16MeterScreenState extends State<YamahaFz16MeterScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final number = parseFz16Code(_controller.text);
    return Scaffold(
      backgroundColor: _YC.bg,
      appBar: AppBar(
        backgroundColor: _YC.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: _YC.textMain),
        title: Text(context.tr('fz16Title'),
            style: const TextStyle(color: _YC.textMain, fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _YC.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          _banner(context),
          const SizedBox(height: 12),
          _card(context.tr('fz16Applies'), border: _YC.neonAmber.withValues(alpha: 0.45)),
          const SizedBox(height: 14),
          _input(context),
          const SizedBox(height: 12),
          _result(context, number),
          const SizedBox(height: 12),
          _card(context.tr('fz16Others')),
          const SizedBox(height: 22),
          _table(context),
          const SizedBox(height: 18),
          Text(context.tr('provenanceManual'),
              style: const TextStyle(
                  color: _YC.neonCyan, fontSize: 11.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(context.tr('fz16Source'),
              style: const TextStyle(color: _YC.textMuted, fontSize: 11, height: 1.5)),
        ],
      ),
    );
  }

  Widget _banner(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _YC.neonAmber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _YC.neonAmber.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_rounded, size: 16, color: _YC.neonAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr('blinkRefManualBadge'),
                      style: const TextStyle(
                          color: _YC.neonAmber,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.tr('fz16Intro'),
                style: const TextStyle(color: _YC.textMuted, fontSize: 12, height: 1.5)),
          ],
        ),
      );

  Widget _card(String text, {Color border = _YC.border}) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _YC.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Text(text,
            style: const TextStyle(color: _YC.textMain, fontSize: 12.5, height: 1.5)),
      );

  Widget _input(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 15),
        decoration: BoxDecoration(
          color: _YC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _YC.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('fz16Field').toUpperCase(),
                style: const TextStyle(
                    color: _YC.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            TextField(
              key: YamahaFz16MeterScreen.inputKey,
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
              maxLength: 2,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                  color: _YC.textMain,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace'),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: _YC.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: _YC.border)),
              ),
            ),
          ],
        ),
      );

  /// A prompt until a number is typed; then the match, or an honest "not in
  /// the verified list".
  Widget _result(BuildContext context, int? number) {
    if (number == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(context.tr('fz16Choose'),
            style: const TextStyle(color: _YC.textMuted, fontSize: 12.5, height: 1.5)),
      );
    }
    final entry = lookupFz16Meter(number);
    if (entry == null) {
      return Container(
        key: const ValueKey('fz16NoMatch'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _YC.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _YC.border),
        ),
        child: Text(context.tr('fz16NoMatch'),
            style: const TextStyle(
                color: _YC.textMain, fontSize: 14, fontWeight: FontWeight.w700)),
      );
    }
    return Container(
      key: const ValueKey('fz16Result'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _YC.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _YC.neonAmber.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${entry.code}',
              style: const TextStyle(
                  color: _YC.neonAmber,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Text(context.tr(entry.meaningKey),
              style: const TextStyle(
                  color: _YC.textMain,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.35)),
          const SizedBox(height: 10),
          Text(context.tr('provenanceManual'),
              style: const TextStyle(color: _YC.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _table(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('blinkRefFullTable').toUpperCase(),
              style: const TextStyle(
                  color: _YC.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9)),
          const SizedBox(height: 10),
          for (final e in kFz16MeterTable)
            GestureDetector(
              key: ValueKey('fz16Row-${e.code}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _controller.text = '${e.code}'),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: parseFz16Code(_controller.text) == e.code
                      ? _YC.neonCyan.withValues(alpha: 0.08)
                      : _YC.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: parseFz16Code(_controller.text) == e.code
                          ? _YC.neonCyan.withValues(alpha: 0.45)
                          : _YC.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text('${e.code}',
                          style: const TextStyle(
                              color: _YC.textMain,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace')),
                    ),
                    Expanded(
                      child: Text(context.tr(e.meaningKey),
                          style: const TextStyle(
                              color: _YC.textMain, fontSize: 12, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
}

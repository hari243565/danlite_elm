/// Danlite ELM — Royal Enfield older-EFI blink-code reference (manual lookup,
/// NOT a scan).
///
/// Follows the Honda blink reference's pattern: the first thing on the screen
/// says this reads nothing from the bike, there is no scan button, and the data
/// is the maker's own published table ([kRoyalEnfieldBlinkTable]).
///
/// What is different, on purpose:
///  * It says which bikes it is for and which it is NOT for (the BS6 Classic
///    350, Meteor and Hunter use a different system), because a rider can reach
///    it from any Royal Enfield profile.
///  * Nothing is pre-selected. Showing a "match" the rider never entered would
///    read as their bike's fault.
///  * It states what the manual pages do not give (blink durations, how to
///    clear the codes) instead of guessing.
library;

import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../constants/royal_enfield_blink.dart';

// Unified Telemetry Design System palette, matching dtc_screen._RC.
class _EC {
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

class RoyalEnfieldBlinkReferenceScreen extends StatefulWidget {
  const RoyalEnfieldBlinkReferenceScreen({super.key});

  /// The two count rows. Named because their digits are the same 0 to 9.
  static const Key longRowKey = ValueKey<String>('reBlinkLongRow');
  static const Key shortRowKey = ValueKey<String>('reBlinkShortRow');

  @override
  State<RoyalEnfieldBlinkReferenceScreen> createState() =>
      _RoyalEnfieldBlinkReferenceScreenState();
}

class _RoyalEnfieldBlinkReferenceScreenState
    extends State<RoyalEnfieldBlinkReferenceScreen> {
  int? _long;
  int? _short;

  @override
  Widget build(BuildContext context) {
    final entry = (_long != null && _short != null)
        ? lookupRoyalEnfieldBlink(_long!, _short!)
        : null;
    return Scaffold(
      backgroundColor: _EC.bg,
      appBar: AppBar(
        backgroundColor: _EC.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: _EC.textMain),
        title: Text(context.tr('reBlinkTitle'),
            style: const TextStyle(
                color: _EC.textMain, fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _EC.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          _manualBanner(context),
          const SizedBox(height: 12),
          _appliesCard(context),
          const SizedBox(height: 12),
          _howToCard(context),
          const SizedBox(height: 14),
          _picker(context),
          const SizedBox(height: 12),
          _result(context, entry),
          const SizedBox(height: 22),
          _fullTable(context),
          const SizedBox(height: 18),
          Text(context.tr('provenanceManual'),
              style: const TextStyle(
                  color: _EC.neonCyan,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(context.tr('reBlinkSource'),
              style: const TextStyle(
                  color: _EC.textMuted, fontSize: 11, height: 1.5)),
        ],
      ),
    );
  }

  Widget _manualBanner(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _EC.neonAmber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _EC.neonAmber.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_rounded,
                    size: 16, color: _EC.neonAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr('blinkRefManualBadge'),
                      style: const TextStyle(
                          color: _EC.neonAmber,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.tr('reBlinkIntro'),
                style: const TextStyle(
                    color: _EC.textMuted, fontSize: 12, height: 1.5)),
          ],
        ),
      );

  /// Which bikes this is for, and which it is not. Placed before the
  /// procedure so a Meteor or Hunter owner stops here.
  Widget _appliesCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _EC.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _EC.neonRed.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('reBlinkAppliesTitle'),
                style: const TextStyle(
                    color: _EC.textMain,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text(context.tr('reBlinkApplies'),
                style: const TextStyle(
                    color: _EC.textMain, fontSize: 12.5, height: 1.5)),
          ],
        ),
      );

  Widget _howToCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _EC.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _EC.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('reBlinkHowTo'),
                style: const TextStyle(
                    color: _EC.textMain,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text(context.tr('reBlinkHowToBody'),
                style: const TextStyle(
                    color: _EC.textMuted, fontSize: 12, height: 1.55)),
            const SizedBox(height: 9),
            Text(context.tr('reBlinkNotGiven'),
                style: const TextStyle(
                    color: _EC.textMuted, fontSize: 12, height: 1.55)),
          ],
        ),
      );

  Widget _picker(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 15),
        decoration: BoxDecoration(
          color: _EC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _EC.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _countRow(
              key: RoyalEnfieldBlinkReferenceScreen.longRowKey,
              label: context.tr('blinkRefLongFlashes'),
              value: _long,
              onPick: (v) => setState(() => _long = v),
            ),
            const SizedBox(height: 14),
            _countRow(
              key: RoyalEnfieldBlinkReferenceScreen.shortRowKey,
              label: context.tr('blinkRefShortFlashes'),
              value: _short,
              onPick: (v) => setState(() => _short = v),
            ),
          ],
        ),
      );

  Widget _countRow({
    required Key key,
    required String label,
    required int? value,
    required ValueChanged<int> onPick,
  }) =>
      Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: _EC.textMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var n = 0; n <= kReBlinkMaxCount; n++)
                GestureDetector(
                  onTap: () => onPick(n),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 42,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: n == value
                          ? _EC.neonCyan.withValues(alpha: 0.16)
                          : _EC.bg,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: n == value
                              ? _EC.neonCyan.withValues(alpha: 0.65)
                              : _EC.border),
                    ),
                    child: Text('$n',
                        style: TextStyle(
                            color: n == value ? _EC.neonCyan : _EC.textMuted,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace')),
                  ),
                ),
            ],
          ),
        ],
      );

  /// A prompt until both counts are chosen; then the match, or an honest
  /// "not in the table".
  Widget _result(BuildContext context, ReBlinkEntry? entry) {
    if (_long == null || _short == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(context.tr('reBlinkChoose'),
            style: const TextStyle(
                color: _EC.textMuted, fontSize: 12.5, height: 1.5)),
      );
    }
    if (entry == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _EC.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _EC.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _patternHeader(context, '$_long-$_short', _EC.textMuted),
            const SizedBox(height: 10),
            Text(context.tr('reBlinkNoMatch'),
                style: const TextStyle(
                    color: _EC.textMain,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(context.tr('reBlinkNoMatchDesc'),
                style: const TextStyle(
                    color: _EC.textMuted, fontSize: 12, height: 1.5)),
          ],
        ),
      );
    }
    final accent = _effectColor(entry.effect);
    return Container(
      key: const ValueKey('reBlinkResult'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _EC.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _patternHeader(context, entry.pattern, accent),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('${context.tr('reBlinkDealerCode').toUpperCase()}  ',
                  style: const TextStyle(
                      color: _EC.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8)),
              Text(entry.dealerCode,
                  style: const TextStyle(
                      color: _EC.textMain,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace')),
              if (entry.manufacturerCode) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _EC.neonAmber.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(context.tr('reBlinkMfrCode'),
                      style: const TextStyle(
                          color: _EC.neonAmber,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(context.tr(entry.meaningKey),
              style: const TextStyle(
                  color: _EC.textMain,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.35)),
          const SizedBox(height: 8),
          Text(context.tr(entry.effect.labelKey),
              style: TextStyle(
                  color: accent, fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(context.tr('provenanceManual'),
              style: const TextStyle(color: _EC.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Color _effectColor(ReBlinkEffect e) =>
      e == ReBlinkEffect.cranksNoStart ? _EC.neonRed : _EC.neonAmber;

  Widget _patternHeader(BuildContext context, String pattern, Color accent) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${context.tr('blinkRefPattern').toUpperCase()}  ',
              style: const TextStyle(
                  color: _EC.textMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          Text(pattern,
              style: TextStyle(
                  color: accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: 1)),
        ],
      );

  Widget _fullTable(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('blinkRefFullTable').toUpperCase(),
              style: const TextStyle(
                  color: _EC.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9)),
          const SizedBox(height: 10),
          for (final e in kRoyalEnfieldBlinkTable)
            GestureDetector(
              key: ValueKey('reBlinkRow-${e.longFlashes}-${e.shortFlashes}'),
              onTap: () => setState(() {
                _long = e.longFlashes;
                _short = e.shortFlashes;
              }),
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: (e.longFlashes == _long && e.shortFlashes == _short)
                      ? _EC.neonCyan.withValues(alpha: 0.08)
                      : _EC.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: (e.longFlashes == _long && e.shortFlashes == _short)
                          ? _EC.neonCyan.withValues(alpha: 0.45)
                          : _EC.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(e.pattern,
                          style: const TextStyle(
                              color: _EC.textMain,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace')),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr(e.meaningKey),
                              style: const TextStyle(
                                  color: _EC.textMain,
                                  fontSize: 12,
                                  height: 1.4)),
                          const SizedBox(height: 2),
                          Text(context.tr(e.effect.labelKey),
                              style: TextStyle(
                                  color: _effectColor(e.effect),
                                  fontSize: 11,
                                  height: 1.3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(e.dealerCode,
                        style: const TextStyle(
                            color: _EC.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
        ],
      );
}

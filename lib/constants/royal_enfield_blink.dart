/// Danlite ELM — Royal Enfield older-EFI blink codes (manual look-up, NOT a scan).
///
/// Source: Royal Enfield Bullet Classic EFI service manual, pages 163 to 164,
/// read in full by the owner's assistant on 2026-10-01. The table applies ONLY
/// to the Bullet Classic EFI and Bullet Electra EFI of the UCE era. It does not
/// apply to the BS6 Classic 350, the Meteor or the Hunter, and the screen says
/// so.
///
/// The manual pages read do not give flash durations or how to clear the
/// codes; neither is invented here.
///
/// Pure Dart. Meanings are `AppStrings` keys so English and Hindi resolve in
/// one place; the dealer-tool codes are the manual's own and never translated.
library;

/// What the manual says the bike does with the fault.
enum ReBlinkEffect {
  /// The bike runs but under-performs.
  runsUnderperforms('reBlinkEffectRuns'),

  /// The engine cranks but will not start.
  cranksNoStart('reBlinkEffectNoStart');

  const ReBlinkEffect(this.labelKey);

  /// `AppStrings` key of the plain-language effect.
  final String labelKey;
}

class ReBlinkEntry {
  const ReBlinkEntry(
    this.longFlashes,
    this.shortFlashes,
    this.dealerCode,
    this.meaningKey,
    this.effect, {
    this.manufacturerCode = false,
  });

  /// The LONG count, then the SHORT count, as the warning lamp blinks them.
  final int longFlashes;
  final int shortFlashes;

  /// The code a dealer tool shows for the same fault.
  final String dealerCode;

  /// `AppStrings` key of the meaning.
  final String meaningKey;

  final ReBlinkEffect effect;

  /// The dealer-tool code is a manufacturer-defined one (P1xxx), not SAE's.
  final bool manufacturerCode;

  /// `long-short`, e.g. `1-5`.
  String get pattern => '$longFlashes-$shortFlashes';
}

/// The largest count the screen accepts for either number. The manual's
/// largest is 6; the pickers go to 9 so that an unlisted pattern can be
/// entered and answered "not in the table" instead of being impossible.
const int kReBlinkMaxCount = 9;

/// Every row of the manual's table, in the order the owner listed them.
const List<ReBlinkEntry> kRoyalEnfieldBlinkTable = <ReBlinkEntry>[
  ReBlinkEntry(0, 6, 'P0120', 'reBlinkMeaningTps', ReBlinkEffect.runsUnderperforms),
  ReBlinkEntry(0, 9, 'P0105', 'reBlinkMeaningMap', ReBlinkEffect.runsUnderperforms),
  ReBlinkEntry(1, 1, 'P0195', 'reBlinkMeaningEot', ReBlinkEffect.runsUnderperforms),
  ReBlinkEntry(1, 7, 'P0130', 'reBlinkMeaningO2', ReBlinkEffect.runsUnderperforms),
  ReBlinkEntry(4, 5, 'P0135', 'reBlinkMeaningO2Heater', ReBlinkEffect.runsUnderperforms),
  ReBlinkEntry(1, 5, 'P1630', 'reBlinkMeaningRollover', ReBlinkEffect.cranksNoStart,
      manufacturerCode: true),
  ReBlinkEntry(3, 3, 'P0201', 'reBlinkMeaningInjector', ReBlinkEffect.cranksNoStart),
  ReBlinkEntry(3, 7, 'P0351', 'reBlinkMeaningCoil', ReBlinkEffect.cranksNoStart),
  ReBlinkEntry(4, 1, 'P0230', 'reBlinkMeaningFuelPump', ReBlinkEffect.cranksNoStart),
  ReBlinkEntry(6, 6, 'P0335', 'reBlinkMeaningCrank', ReBlinkEffect.cranksNoStart),
];

/// The row for [longFlashes] long and [shortFlashes] short blinks, or null:
/// the pattern is not in the manual's table, or either count is outside
/// 0 to [kReBlinkMaxCount].
ReBlinkEntry? lookupRoyalEnfieldBlink(int longFlashes, int shortFlashes) {
  if (longFlashes < 0 || longFlashes > kReBlinkMaxCount) return null;
  if (shortFlashes < 0 || shortFlashes > kReBlinkMaxCount) return null;
  for (final e in kRoyalEnfieldBlinkTable) {
    if (e.longFlashes == longFlashes && e.shortFlashes == shortFlashes) return e;
  }
  return null;
}

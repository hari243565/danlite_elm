/// Danlite ELM — Yamaha FZ-16 FI meter fault codes (manual look-up, NOT a scan).
///
/// Source: Yamaha FZ-16 service manual, manual page 7-24. On the older FZ-16
/// FI the warning lamp lights for 3 seconds at key ON and the fault code
/// NUMBER shows on the meter. The manual lists many codes; only the two below
/// have been verified, so only they are here. The screen says plainly that
/// other codes exist and are not listed, and that this has not been confirmed
/// for the newer FZ-S FI models.
///
/// Pure Dart. Meanings are `AppStrings` keys so English and Hindi resolve in
/// one place.
library;

class Fz16MeterEntry {
  const Fz16MeterEntry(this.code, this.meaningKey);

  /// The number the meter shows.
  final int code;

  /// `AppStrings` key of the meaning.
  final String meaningKey;
}

/// The verified rows, and only those.
const List<Fz16MeterEntry> kFz16MeterTable = <Fz16MeterEntry>[
  Fz16MeterEntry(15, 'fz16Code15'),
  Fz16MeterEntry(16, 'fz16Code16'),
];

/// The row for a meter number, or null when it is not one of the verified rows.
Fz16MeterEntry? lookupFz16Meter(int code) {
  for (final e in kFz16MeterTable) {
    if (e.code == code) return e;
  }
  return null;
}

final RegExp _plainDigits = RegExp(r'^[0-9]{1,2}$');

/// What the rider typed as a meter number: one or two plain digits, with
/// spaces around allowed. Anything else (letters, a sign, three digits, other
/// scripts' digits) is not a number here, and the screen shows no answer.
int? parseFz16Code(String input) {
  final s = input.trim();
  if (!_plainDigits.hasMatch(s)) return null;
  return int.parse(s);
}

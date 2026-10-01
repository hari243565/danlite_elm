/// Danlite ELM — what a fault code's NUMBER says on its own, before any
/// knowledge source is consulted: whether the range is standard or set by the
/// maker, and which standard subsystem it belongs to.
///
/// Pure Dart, so the resolver (`lib/knowledge/fault_resolver.dart`) can use the
/// same rules as the screen. `dtc_service.dart` re-exports
/// [isManufacturerDefined] and delegates `DtcLocalizations.subsystemKey` here,
/// so every existing caller is unchanged.
library;

final RegExp _saeCode = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$');

/// True when [code]'s meaning is set by the vehicle manufacturer, not by the
/// SAE standard, so a generic table cannot say what it means on this bike.
///
/// Follows the SAE J2012 code-range convention AS UNDERSTOOD here, and must
/// be re-checked against the standard text:
///   * P: second digit 1 (P1xxx), or second digit 3 with third digit 0–3
///     (P30xx–P33xx). P0xxx, P2xxx and P34xx–P39xx are SAE-defined.
///   * B, C, U: second digit 1 or 2 (B1xxx/B2xxx, C1xxx/C2xxx, U1xxx/U2xxx).
///     Second digit 0 (and 3) are SAE-defined.
/// Anything that is not a well-formed five-character code returns false.
bool isManufacturerDefined(String code) {
  final c = code.trim().toUpperCase();
  if (!_saeCode.hasMatch(c)) return false;
  final second = c[1];
  if (c[0] == 'P') {
    if (second == '1') return true;
    return second == '3' && '0123'.contains(c[2]);
  }
  return second == '1' || second == '2';
}

/// `AppStrings` key naming the subsystem a STANDARD code belongs to, or null
/// when the code's range has no subsystem grouping this app is confident of.
///
/// From the SAE J2012 grouping AS UNDERSTOOD here (third character of the
/// code); re-check against the standard text before extending it. Only
/// P0/P2 groups 0–7 and U0 groups 0–4 are mapped. Manufacturer-defined codes
/// return null: their grouping is the maker's too.
String? subsystemKeyFor(String code) {
  final c = code.trim().toUpperCase();
  if (!_saeCode.hasMatch(c)) return null;
  if (isManufacturerDefined(c)) return null;
  final group = c[2];
  if (c[0] == 'P' && (c[1] == '0' || c[1] == '2')) {
    switch (group) {
      case '0':
      case '1':
      case '2':
        return 'dtcSubFuelAir';
      case '3':
        return 'dtcSubIgnition';
      case '4':
        return 'dtcSubEmission';
      case '5':
        return 'dtcSubSpeedIdle';
      case '6':
        return 'dtcSubComputer';
      case '7':
        return 'dtcSubTransmission';
    }
    if (c[1] == '0' && (group == '8' || group == '9')) {
      return 'dtcSubTransmission';
    }
    return null;
  }
  if (c[0] == 'U' && c[1] == '0') {
    switch (group) {
      case '0':
        return 'dtcSubNetworkElectrical';
      case '1':
      case '2':
        return 'dtcSubNetworkComms';
      case '3':
        return 'dtcSubNetworkSoftware';
      case '4':
        return 'dtcSubNetworkData';
    }
  }
  return null;
}

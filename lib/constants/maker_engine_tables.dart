/// Danlite ELM — manufacturer ENGINE tables that belong to one bike.
///
/// A maker table is what the manufacturer's own service manual says a standard
/// P-code means ON THAT BIKE, with the maker's fail-safe columns (does the
/// engine start, can the bike be driven). It is kept as static code beside the
/// Royal Enfield ABS tables, not as a knowledge pack, because the pack format
/// only describes AI-written guidance: it has no manufacturer-manual
/// verification, no model-year rule and no fail-safe columns, and widening the
/// importer for one table would touch a signed, hashed path.
///
/// Scope is deliberately narrow and exact:
///  * the make must resolve to the table's make, AND the normalised model must
///    EXACTLY match one of the table's aliases (never a substring — "R15 V3"
///    and "R15S" are other bikes and are not in the list);
///  * the source manual covers one model generation, so a model year before
///    [MakerEngineTable.firstModelYear] never gets the table, and a missing
///    year gets it with a "check your model year" note.
///
/// Pure Dart: no Flutter. Rider text here is the maker's meaning only; every
/// fixed sentence around it is an `AppStrings` key, rendered by the screens.
library;

import 'chassis_dtc_dictionary.dart' show ChassisManufacturers;

/// The key of the Yamaha R15 / R15M / YZF155-A table. Also the
/// `VehicleContext.vehicleKey` of a bike it applies to.
const String kYamahaR15TableKey = 'yamaha_r15';

/// How sure the transcription of one row is.
enum MakerRowCheck {
  /// Read straight from the manual page.
  none,

  /// Rebuilt from the page, not read from it: to be checked.
  reconstructed,

  /// The row's alignment with its code was worked out, not read: to be checked.
  inferred,
}

/// One row: a standard P-code and what the maker says about it.
class MakerEngineRow {
  const MakerEngineRow(
    this.code,
    this.meaningEn,
    this.meaningHi, {
    this.engineStarts = true,
    this.canDrive = true,
    this.dealerItem,
    this.check = MakerRowCheck.none,
  });

  final String code;

  /// The maker's meaning, English and Hindi (the Hindi is machine-translated).
  final String meaningEn;
  final String meaningHi;

  /// The fail-safe columns of the manual.
  final bool engineStarts;
  final bool canDrive;

  /// The maker's dealer-tool item number. For the mechanic section only.
  final String? dealerItem;

  final MakerRowCheck check;

  /// The app's judgement from the fail-safe columns: Stop when the maker says
  /// the engine will not start or the bike cannot be driven.
  bool get isStop => !engineStarts || !canDrive;
}

/// One maker table, for one family of bikes.
class MakerEngineTable {
  const MakerEngineTable({
    required this.key,
    required this.manufacturerKey,
    required this.modelAliases,
    required this.firstModelYear,
    required this.makerName,
    required this.makerNameHi,
    required this.sourcePage,
    required this.rows,
  });

  final String key;
  final String manufacturerKey;

  /// Normalised model spellings (lowercase letters and digits only). Exact
  /// match only.
  final List<String> modelAliases;

  /// The first model year the source manual covers.
  final int firstModelYear;

  final String makerName;
  final String makerNameHi;

  /// The manual page the rows come from, e.g. `8-47`.
  final String sourcePage;

  final List<MakerEngineRow> rows;

  MakerEngineRow? row(String code) {
    for (final r in rows) {
      if (r.code == code) return r;
    }
    return null;
  }
}

class MakerEngineTables {
  MakerEngineTables._();

  static const List<MakerEngineTable> all = <MakerEngineTable>[_yamahaR15];

  static MakerEngineTable? byKey(String? key) {
    if (key == null) return null;
    for (final t in all) {
      if (t.key == key) return t;
    }
    return null;
  }

  static List<MakerEngineRow> rowsFor(String key) =>
      byKey(key)?.rows ?? const <MakerEngineRow>[];

  /// The table that applies to a typed make and model, or null. Unknown or
  /// blank make, blank model, another make's "R15": nothing.
  static String? vehicleKeyFor(String? make, String? model) {
    final m = ChassisManufacturers.resolveKey(make);
    if (m == null || model == null) return null;
    final n = ChassisManufacturers.normalise(model);
    if (n.isEmpty) return null;
    for (final t in all) {
      if (t.manufacturerKey == m && t.modelAliases.contains(n)) return t.key;
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════════════════
  // Yamaha R15 (2022) — service manual, page 8-47 (also covers R15M 2022 and
  // YZF155-A). Read by the owner's assistant on 2026-10-03: 21 rows of
  // standard P-codes with the maker's fail-safe columns.
  //
  // Three rows are NOT read straight from the page and carry a check mark;
  // their rows show the "Draft" line, and the mechanic section says they are
  // to be checked against the manual page:
  //   P00D1  reconstructed
  //   P2195  reconstructed
  //   P0132  row alignment inferred
  // (For P2195 and P00D1 the standard's own name differs from this meaning —
  // one more reason they are to be checked.)
  // ════════════════════════════════════════════════════════════════════════
  static const MakerEngineTable _yamahaR15 = MakerEngineTable(
    key: kYamahaR15TableKey,
    manufacturerKey: ChassisManufacturers.yamaha,
    // Exact aliases only. R15 V3 / R15S / R15 V2 are other generations and are
    // deliberately absent.
    modelAliases: <String>[
      'r15',
      'r15m',
      'r15v4',
      'yzfr15',
      'yzfr15m',
      'yzfr15v4',
      'yzf155',
      'yzf155a',
      'yamahar15',
      'yamahar15m',
    ],
    firstModelYear: 2022,
    makerName: 'Yamaha',
    makerNameHi: 'यामाहा',
    sourcePage: '8-47',
    rows: <MakerEngineRow>[
      MakerEngineRow(
        'P0030',
        'O2 sensor heater faulty or heater command and feedback do not match',
        'O2 सेंसर का हीटर खराब है, या हीटर का कमांड और फ़ीडबैक आपस में मेल नहीं खाते',
      ),
      MakerEngineRow(
        'P00D1',
        'O2 sensor, no normal signal while driving',
        'O2 सेंसर, चलते समय सामान्य सिग्नल नहीं मिल रहा',
        check: MakerRowCheck.reconstructed,
      ),
      MakerEngineRow(
        'P2195',
        'O2 sensor, open circuit',
        'O2 सेंसर, ओपन सर्किट',
        check: MakerRowCheck.reconstructed,
      ),
      MakerEngineRow(
        'P0106',
        'Intake air pressure sensor, hole clogged or sensor installed wrongly',
        'इनटेक एयर प्रेशर सेंसर, छेद बंद है या सेंसर गलत लगा है',
        dealerItem: '03',
      ),
      MakerEngineRow(
        'P0107',
        'Intake air pressure sensor, open circuit or short to ground',
        'इनटेक एयर प्रेशर सेंसर, ओपन सर्किट या ग्राउंड से शॉर्ट',
        dealerItem: '03',
      ),
      MakerEngineRow(
        'P0108',
        'Intake air pressure sensor, short to power',
        'इनटेक एयर प्रेशर सेंसर, पावर से शॉर्ट',
        dealerItem: '03',
      ),
      MakerEngineRow(
        'P0112',
        'Intake air temperature sensor, short to ground',
        'इनटेक एयर टेम्परेचर सेंसर, ग्राउंड से शॉर्ट',
        dealerItem: '05',
      ),
      MakerEngineRow(
        'P0113',
        'Intake air temperature sensor, open circuit or short to power',
        'इनटेक एयर टेम्परेचर सेंसर, ओपन सर्किट या पावर से शॉर्ट',
        dealerItem: '05',
      ),
      MakerEngineRow(
        'P0117',
        'Coolant temperature sensor, short to ground',
        'कूलेंट टेम्परेचर सेंसर, ग्राउंड से शॉर्ट',
        dealerItem: '06',
      ),
      MakerEngineRow(
        'P0118',
        'Coolant temperature sensor, open circuit or short to power',
        'कूलेंट टेम्परेचर सेंसर, ओपन सर्किट या पावर से शॉर्ट',
        dealerItem: '06',
      ),
      MakerEngineRow(
        'P0122',
        'Throttle position sensor, open circuit or short to ground',
        'थ्रॉटल पोज़ीशन सेंसर, ओपन सर्किट या ग्राउंड से शॉर्ट',
        dealerItem: '01',
      ),
      MakerEngineRow(
        'P0123',
        'Throttle position sensor, short to power',
        'थ्रॉटल पोज़ीशन सेंसर, पावर से शॉर्ट',
        dealerItem: '01',
      ),
      MakerEngineRow(
        'P0132',
        'O2 sensor, short to power',
        'O2 सेंसर, पावर से शॉर्ट',
        check: MakerRowCheck.inferred,
      ),
      MakerEngineRow(
        'P0201',
        'Fuel injector fault',
        'फ़्यूल इंजेक्टर में खराबी',
        canDrive: false,
        dealerItem: '36',
      ),
      MakerEngineRow(
        'P0335',
        'Crankshaft position sensor, no normal signal',
        'क्रैंकशाफ़्ट पोज़ीशन सेंसर, सामान्य सिग्नल नहीं मिल रहा',
        engineStarts: false,
        canDrive: false,
      ),
      MakerEngineRow(
        'P0351',
        'Ignition coil, no normal signal from the ignition circuit',
        'इग्निशन कॉइल, इग्निशन सर्किट से सामान्य सिग्नल नहीं मिल रहा',
        engineStarts: false,
        canDrive: false,
        dealerItem: '30',
      ),
      MakerEngineRow(
        'P0480',
        'Radiator fan motor relay, no normal signal',
        'रेडिएटर फ़ैन मोटर रिले, सामान्य सिग्नल नहीं मिल रहा',
        dealerItem: '51',
      ),
      MakerEngineRow(
        'P0500',
        'Front wheel (speed) sensor, no normal signal',
        'फ़्रंट व्हील (स्पीड) सेंसर, सामान्य सिग्नल नहीं मिल रहा',
        dealerItem: '07',
      ),
      MakerEngineRow(
        'P0511',
        'Fast-idle (FID) solenoid valve, open or short between valve and ECU',
        'फ़ास्ट-आइडल (FID) सोलेनॉइड वाल्व, वाल्व और ECU के बीच ओपन या शॉर्ट',
        dealerItem: '54',
      ),
      MakerEngineRow(
        'P0560',
        'Battery charging voltage abnormal, discharged',
        'बैटरी चार्जिंग वोल्टेज असामान्य, बैटरी डिस्चार्ज',
      ),
      MakerEngineRow(
        'P0563',
        'Battery charging voltage abnormal, overcharged',
        'बैटरी चार्जिंग वोल्टेज असामान्य, ओवरचार्ज',
      ),
    ],
  );
}

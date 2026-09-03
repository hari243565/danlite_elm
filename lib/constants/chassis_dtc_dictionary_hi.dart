/// Danlite ELM — Chassis / ABS DTC Dictionary (Hindi parallel)
///
/// Hindi counterpart to `chassis_dtc_dictionary.dart`, keyed by the same
/// platform key and the same code, exactly as `dtc_dictionary_hi.dart`
/// parallels `dtc_descriptions.dart` for engine codes.
///
/// Structural note: the engine-code Hindi map carries a description only,
/// because that is all the engine card renders in Hindi. A chassis card renders
/// three translatable columns (Description, Query, Remedy), so each entry here
/// is a small record of those three rather than a bare string. The convention
/// it is matching is the one that matters — English master in one file, Hindi
/// parallel in another keyed identically, both resolved through the single
/// langCode-aware entry point in `DtcLocalizations`.
///
/// "Failure Component" is deliberately absent: it is a manufacturer identifier
/// token (`RFP/RFP_HW`, `WSS_GENERIC`) that a technician matches against the
/// manual verbatim, so it is never translated — the same rule that keeps gauge
/// units untranslated elsewhere in this app.
///
/// Where the English master has an empty Query or Remedy (the source printed
/// "N/A"), the Hindi entry leaves it empty too — there is nothing to translate.
/// Any genuinely missing entry falls back to English through
/// [DtcLocalizations], so an untranslated code still renders its real English
/// meaning rather than an empty card.
///
/// Technical initialisms (ABS, ECU, WSS, CAN, EEPROM, EV, AV, POT, Uz) are kept
/// in Latin script: they appear that way on the vehicle, in the manuals, and in
/// Indian workshop usage, so transliterating them would make a card harder to
/// act on, not easier.
library;

import 'chassis_dtc_dictionary.dart';

/// The translatable columns of one chassis DTC entry.
class ChassisDtcText {
  final String description;
  final String query;
  final String remedy;

  const ChassisDtcText({
    required this.description,
    this.query = '',
    this.remedy = '',
  });
}

class ChassisDtcDictionaryHi {
  ChassisDtcDictionaryHi._();

  /// Hindi rendering of [ChassisDtcDatabase.bulletEfiGenericRemedy].
  static const String bulletEfiGenericRemedyHi =
      'इसकी जाँच किसी अधिकृत Royal Enfield सर्विस सेंटर से कराएँ';

  static const Map<String, Map<String, ChassisDtcText>> byPlatform =
      <String, Map<String, ChassisDtcText>>{
    // ══════════════════════════════════════════════════════════════════════
    // Royal Enfield Classic 350
    // ══════════════════════════════════════════════════════════════════════
    ChassisPlatforms.royalEnfieldClassic350: <String, ChassisDtcText>{
      'C1015': ChassisDtcText(
        description: 'ABS पंप/मोटर की खराबी',
        query: 'ABS पंप मोटर में खराबी',
        remedy: 'ABS यूनिट बदलें',
      ),
      'C1019': ChassisDtcText(
        description: 'ABS ECU रिले की खराबी',
        query: 'ABS वाल्व रिले में खराबी',
        remedy: 'ABS यूनिट बदलें',
      ),
      'C1021': ChassisDtcText(
        description: 'ABS ECU आंतरिक खराबी',
        query: 'ABS माइक्रोकंट्रोलर की खराबी',
        remedy: 'ABS यूनिट बदलें',
      ),
      'C1024': ChassisDtcText(
        description: '(जेनेरिक) ABS व्हील स्पीड का अंतर बहुत अधिक',
        query: 'आगे/पीछे के WSS से सिग्नल की गुणवत्ता ठीक नहीं है',
        remedy: 'फ्रंट टोनर व्हील / एयरगैप की जाँच करें',
      ),
      'C1031': ChassisDtcText(
        description: 'ABS व्हील स्पीड सर्किट खुला या शॉर्ट (पिछला)',
        query: 'पिछले WSS में खराबी (इलेक्ट्रिकल)',
        remedy: 'पिछला WSS बदलें या WSS से ABS तक की वायरिंग जाँचें',
      ),
      'C1032': ChassisDtcText(
        description: 'ABS व्हील स्पीड रुक-रुक कर (पिछला)',
        query: 'पिछले WSS से सिग्नल की गुणवत्ता ठीक नहीं है',
        remedy: 'पिछला टोनर व्हील / एयरगैप की एकरूपता / WSS ब्रैकेट जाँचें',
      ),
      'C1033': ChassisDtcText(
        description: 'ABS व्हील स्पीड सर्किट खुला या शॉर्ट (अगला)',
        query: 'अगले WSS में खराबी (इलेक्ट्रिकल)',
        remedy: 'अगला WSS बदलें या WSS से ABS तक की वायरिंग जाँचें',
      ),
      'C1034': ChassisDtcText(
        description: 'ABS व्हील स्पीड रुक-रुक कर (अगला)',
        query: 'अगले WSS से सिग्नल की गुणवत्ता ठीक नहीं है',
        remedy: 'अगला टोनर व्हील / एयरगैप की एकरूपता / WSS ब्रैकेट जाँचें',
      ),
      'C1048': ChassisDtcText(
        description: '(AV) ABS रिलीज़ सोलेनॉइड सर्किट खुला या उच्च प्रतिरोध (पिछला)',
        query: 'पिछले आउटलेट वाल्व में खराबी',
        remedy: 'ABS यूनिट बदलें',
      ),
      'C1049': ChassisDtcText(
        description: '(AV) ABS रिलीज़ सोलेनॉइड सर्किट खुला या उच्च प्रतिरोध (अगला)',
        query: 'अगले आउटलेट वाल्व में खराबी',
        remedy: 'ABS यूनिट बदलें',
      ),
      'C1052': ChassisDtcText(
        description: '(EV) ABS अप्लाई सोलेनॉइड सर्किट खुला या उच्च प्रतिरोध (पिछला)',
        query: 'पिछले इनलेट वाल्व में खराबी',
        remedy: 'ABS यूनिट बदलें',
      ),
      'C1054': ChassisDtcText(
        description: '(EV) ABS अप्लाई सोलेनॉइड सर्किट खुला या उच्च प्रतिरोध (अगला)',
        query: 'अगले इनलेट वाल्व में खराबी',
        remedy: 'ABS यूनिट बदलें',
      ),
      'C1058': ChassisDtcText(
        description: 'ABS वोल्टेज कम',
        query: 'बैटरी वोल्टेज बहुत कम',
        remedy: 'बैटरी जाँचें',
      ),
      'C1059': ChassisDtcText(
        description: 'ABS वोल्टेज अधिक',
        query: 'बैटरी वोल्टेज बहुत अधिक',
        remedy: 'वोल्टेज रेगुलेटर / बैटरी जाँचें',
      ),
      // Query/Remedy are "N/A" in the source — nothing to translate.
      'C1334': ChassisDtcText(
        description: 'EEPROM में वेरिएंट कॉन्फ़िगर नहीं है',
      ),
      'C1335': ChassisDtcText(
        description: 'वेरिएंट जानकारी त्रुटि',
      ),
      'U2921': ChassisDtcText(
        description: 'CAN जेनेरिक मॉनिटरिंग',
        query: 'CAN कंट्रोलर की खराबी। इस स्थिति में टेस्टर से जाँच संभव नहीं है।',
        remedy: 'ABS यूनिट बदलें',
      ),
      'U2922': ChassisDtcText(
        description: 'हाई स्पीड CAN कम्युनिकेशन बस में खराबी',
        query: 'CAN BusOff खराबी',
        remedy: 'CAN लाइनों का कनेक्शन जाँचें',
      ),
      'U2926': ChassisDtcText(
        description: 'क्लस्टर DLC / टाइमआउट खराबी',
      ),
    },

    // ══════════════════════════════════════════════════════════════════════
    // Royal Enfield Bullet EFI / Bullet Classic EFI / Continental GT
    // No Query column in the source; every remedy is the shared generic one.
    // ══════════════════════════════════════════════════════════════════════
    ChassisPlatforms.royalEnfieldBulletEfi: <String, ChassisDtcText>{
      '5013H': ChassisDtcText(
        description: 'पिछले इनलेट वाल्व की खराबी (EV)',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5014H': ChassisDtcText(
        description: 'पिछले आउटलेट वाल्व की खराबी (AV)',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5017H': ChassisDtcText(
        description: 'अगले इनलेट वाल्व की खराबी (EV)',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5018H': ChassisDtcText(
        description: 'अगले आउटलेट वाल्व की खराबी (AV)',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5019H': ChassisDtcText(
        description: 'वाल्व रिले की खराबी (फेलसेफ़ रिले)',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5025H': ChassisDtcText(
        description: 'व्हील स्पीड के बीच अंतर (WSS_GENERIC)',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5035H': ChassisDtcText(
        description: 'पंप मोटर की खराबी',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5042H': ChassisDtcText(
        description: 'अगला व्हील स्पीड सेंसर खराबी — प्लॉज़िबिलिटी',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5043H': ChassisDtcText(
        description: 'अगला व्हील स्पीड सेंसर — कनेक्शन टूटा / ग्राउंड शॉर्ट / Uz शॉर्ट',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5044H': ChassisDtcText(
        description: 'पिछला व्हील स्पीड सेंसर खराबी — प्लॉज़िबिलिटी',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5045H': ChassisDtcText(
        description: 'पिछला व्हील स्पीड सेंसर — कनेक्शन टूटा / ग्राउंड शॉर्ट / Uz शॉर्ट',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5052H': ChassisDtcText(
        description: 'पावर सप्लाई की खराबी (कम वोल्टेज)',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5053H': ChassisDtcText(
        description: 'पावर सप्लाई की खराबी (अधिक वोल्टेज)',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5055H': ChassisDtcText(
        description: 'ECU की खराबी',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5122H': ChassisDtcText(
        description: 'Varcode EEPROM रीड त्रुटि',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5223H': ChassisDtcText(
        description: 'VarCode EEPROM रेंज से बाहर',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5331H': ChassisDtcText(
        description: 'अगले व्हील प्रेशर सेंसर में ओमिक खराबी',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5332H': ChassisDtcText(
        description: 'अगला व्हील प्रेशर सेंसर — ऑफसेट / टेस्ट पल्स / POT खराबी',
        remedy: bulletEfiGenericRemedyHi,
      ),
      '5333H': ChassisDtcText(
        description: 'प्रेशर सेंसर की बाहरी सप्लाई में खराबी',
        remedy: bulletEfiGenericRemedyHi,
      ),
    },
  };

  /// Hindi entry for [code] under [platformKey], or null when untranslated.
  ///
  /// [code] is canonicalised through the English master first, so a scanned
  /// SAE-format code resolves to the same entry its hex-notation key holds.
  static ChassisDtcText? lookup(String? platformKey, String code) {
    final canonical = ChassisDtcDatabase.canonicalCode(platformKey, code);
    if (canonical == null) return null;
    return byPlatform[platformKey]?[canonical];
  }
}

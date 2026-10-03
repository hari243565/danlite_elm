# Hindi glossary for the seed (technician register, aim A4 Phase 2)

Hindi form of every term in `docs/content/GLOSSARY_EN.md`, plus the extra terms the 308 shipped entries use. It
follows the app's register: workshop loanwords for parts (सेंसर, सर्किट, इंजेक्टर, थ्रॉटल, बैटरी, इग्निशन), **ABS and
ECU stay in Latin script**, Latin digits, units never translated, native verbs for actions (रुकें, जाँचें, कराएँ),
"एडेप्टर" and "फ़ॉल्ट कोड" with the nukta, and "workshop" written वर्कशॉप. Stop wording is रुकें; do-not-ride wording is
न चलाएँ; the engine stopping by itself is always "बंद हो" (never "रुक"). See `CANONICAL_HI.md` for the fixed sentences.

`validate_hi.py` reads the table below. For every row, **if the English entry uses the English term (whole word, a
plural "s" allowed, any of the " / " alternatives), the Hindi field must contain at least one of the "Must contain"
forms** (alternatives separated by " / "). Keep four columns and no pipe character inside a cell.

## Terms from GLOSSARY_EN.md

| English | Hindi | Must contain | Note |
|---|---|---|---|
| bike's computer | बाइक का कंप्यूटर (ECU) | कंप्यूटर | first mention in an entry's meaning; later just "ECU" |
| engine computer | इंजन कंप्यूटर (ECU) | कंप्यूटर | titles of U0100-style entries |
| ECU | ECU | ECU | Latin script |
| control unit | कंट्रोल यूनिट | कंट्रोल यूनिट | any electronic unit |
| warning lamp / warning light | चेतावनी लैंप | चेतावनी लैंप | MIL = चेतावनी लैंप (MIL) |
| MIL | MIL | MIL | Latin script |
| fault code | फ़ॉल्ट कोड | फ़ॉल्ट कोड | nukta spelling fixed |
| scan tool | स्कैन टूल | स्कैन टूल | technician hints only |
| sensor | सेंसर | सेंसर | |
| circuit | सर्किट | सर्किट | |
| wiring | वायरिंग | वायरिंग | |
| harness | हार्नेस | हार्नेस | technician hints only |
| connector | कनेक्टर | कनेक्टर | |
| ground | ग्राउंड | ग्राउंड | |
| battery supply | बैटरी सप्लाई | बैटरी सप्लाई | |
| sensor supply | सेंसर सप्लाई | सेंसर सप्लाई | |
| supply | सप्लाई | सप्लाई | |
| signal | सिग्नल | सिग्नल | |
| range | रेंज | रेंज | |
| plausibility | प्लॉज़िबिलिटी | प्लॉज़िबिलिटी | |
| intermittent | बीच-बीच में | बीच-बीच में | comes and goes |
| threshold | सीमा | सीमा | the limit the ECU compares against |
| stall / stalls / stalled / stalling | इंजन बंद हो | बंद हो | the engine stops by itself |
| reduced power mode | कम पावर मोड | कम पावर | |
| freeze-frame | फ़्रीज़-फ़्रेम | फ़्रीज़-फ़्रेम | freeze-frame data = फ़्रीज़-फ़्रेम डेटा |
| live data | लाइव डेटा | लाइव डेटा | |
| key-on | इग्निशन चालू | इग्निशन चालू | |
| intake air leak | इनटेक में हवा का रिसाव | रिसाव | vacuum leak = वैक्यूम लीक |
| vacuum leak | वैक्यूम लीक | वैक्यूम लीक | |
| mixture | मिक्सचर | मिक्सचर | |
| lean | लीन | लीन | too lean = बहुत लीन |
| rich | रिच | रिच | too rich = बहुत रिच |
| fuel trim | फ़्यूल ट्रिम | फ़्यूल ट्रिम | |
| oxygen | ऑक्सीजन | ऑक्सीजन | oxygen (O2) sensor = ऑक्सीजन (O2) सेंसर |
| upstream | अपस्ट्रीम | अपस्ट्रीम | |
| downstream | डाउनस्ट्रीम | डाउनस्ट्रीम | |
| catalytic converter | कैटेलिटिक कन्वर्टर | कैटेलिटिक कन्वर्टर | |
| emission / emissions | उत्सर्जन | उत्सर्जन | emission system = उत्सर्जन सिस्टम (the app's own word) |
| throttle | थ्रॉटल | थ्रॉटल | |
| twist grip | ट्विस्ट ग्रिप | ट्विस्ट ग्रिप | |
| intake | इनटेक | इनटेक | |
| pressure | प्रेशर | प्रेशर | |
| MAP | MAP | MAP | Latin script |
| temperature | तापमान | तापमान | |
| coolant | कूलेंट | कूलेंट | |
| crankshaft | क्रैंकशाफ़्ट | क्रैंकशाफ़्ट | |
| camshaft | कैमशाफ़्ट | कैमशाफ़्ट | |
| reluctor ring | रिलक्टर रिंग | रिलक्टर रिंग | |
| tone ring | टोन रिंग | टोन रिंग | |
| toothed ring | दाँतेदार रिंग | दाँतेदार रिंग | give the workshop word in brackets once |
| ignition coil | इग्निशन कॉइल | इग्निशन कॉइल | |
| ignition | इग्निशन | इग्निशन | |
| injector | इंजेक्टर | इंजेक्टर | |
| idle air control valve | आइडल एयर कंट्रोल वाल्व | आइडल एयर कंट्रोल वाल्व | |
| idle | आइडल | आइडल | |
| valve | वाल्व | वाल्व | |
| neutral | न्यूट्रल | न्यूट्रल | |
| immobiliser | इम्मोबिलाइज़र | इम्मोबिलाइज़र | gloss: चाबी-कोड वाला एंटी-थेफ़्ट स्टार्ट लॉक |
| ABS | ABS | ABS | Latin script |
| wheel speed sensor | व्हील स्पीड सेंसर | व्हील स्पीड सेंसर | |
| wheel | व्हील | व्हील | |
| instrument cluster | इंस्ट्रूमेंट क्लस्टर | इंस्ट्रूमेंट क्लस्टर | |
| CAN | CAN | CAN | Latin script; CAN bus = CAN बस |
| bus | बस | बस | |
| regulator | रेगुलेटर | रेगुलेटर | |
| alternator | अल्टरनेटर | अल्टरनेटर | |
| generator | जनरेटर | जनरेटर | |
| mechanic | मैकेनिक | मैकेनिक | for the rider text |
| technician | टेक्नीशियन | टेक्नीशियन | for the technician hints |
| workshop | वर्कशॉप | वर्कशॉप | |
| bike | बाइक | बाइक | |

## Failure phrases (shared with the app's failure-type table)

| English | Hindi | Must contain | Note |
|---|---|---|---|
| short to ground | ग्राउंड से शॉर्ट | ग्राउंड से शॉर्ट | |
| short to battery supply | बैटरी सप्लाई से शॉर्ट | बैटरी सप्लाई से शॉर्ट | |
| open circuit | ओपन सर्किट | ओपन सर्किट | |
| voltage below threshold | वोल्टेज सीमा से कम | सीमा से कम | |
| voltage above threshold | वोल्टेज सीमा से ज़्यादा | सीमा से ज़्यादा | |
| current below threshold | करंट सीमा से कम | सीमा से कम | |
| current above threshold | करंट सीमा से ज़्यादा | सीमा से ज़्यादा | |
| resistance above threshold | रेज़िस्टेंस सीमा से ज़्यादा | सीमा से ज़्यादा | |
| signal out of range | सिग्नल रेंज से बाहर | रेंज से बाहर | |
| signal plausibility fault | सिग्नल प्लॉज़िबिलिटी फ़ॉल्ट | प्लॉज़िबिलिटी | |
| performance or incorrect operation | परफ़ॉर्मेंस या गलत कामकाज | परफ़ॉर्मेंस | |
| internal fault of the control unit | कंट्रोल यूनिट के अंदर खराबी | कंट्रोल यूनिट | |
| communication lost | संचार टूट गया | संचार टूट | |
| circuit fault | सर्किट में खराबी | सर्किट | |

## Extra terms the entries use

| English | Hindi | Must contain | Note |
|---|---|---|---|
| voltage | वोल्टेज | वोल्टेज | |
| resistance | रेज़िस्टेंस | रेज़िस्टेंस | |
| battery | बैटरी | बैटरी | |
| fuse | फ़्यूज़ | फ़्यूज़ | |
| relay | रिले | रिले | |
| fuel pump | फ़्यूल पंप | फ़्यूल पंप | |
| pump | पंप | पंप | |
| fuel | ईंधन / फ़्यूल | ईंधन / फ़्यूल | "ईंधन" for the substance, "फ़्यूल" in part names (फ़्यूल पंप, फ़्यूल टैंक, फ़्यूल ट्रिम, फ़्यूल कैप) |
| petrol | पेट्रोल | पेट्रोल | |
| engine | इंजन | इंजन | |
| oil | ऑयल | ऑयल | |
| cylinder | सिलेंडर | सिलेंडर | |
| misfire / misfires / misfired | मिसफ़ायर | मिसफ़ायर | |
| spark plug | स्पार्क प्लग | स्पार्क प्लग | |
| spark | स्पार्क | स्पार्क | |
| starter | स्टार्टर | स्टार्टर | |
| speedometer | स्पीडोमीटर | स्पीडोमीटर | |
| speed | स्पीड | स्पीड | |
| clutch | क्लच | क्लच | |
| brake / brakes / braking | ब्रेक | ब्रेक | |
| software | सॉफ़्टवेयर | सॉफ़्टवेयर | |
| exhaust | एग्ज़ॉस्ट | एग्ज़ॉस्ट | |
| radiator | रेडिएटर | रेडिएटर | |
| cooling fan | कूलिंग फ़ैन | कूलिंग फ़ैन | |
| hose | होज़ | होज़ | |
| knock sensor | नॉक सेंसर | नॉक सेंसर | |
| throttle body | थ्रॉटल बॉडी | थ्रॉटल बॉडी | |
| fuel cap | फ़्यूल कैप | फ़्यूल कैप | |
| headlight | हेडलाइट | हेडलाइट | |
| purge valve | पर्ज वाल्व | पर्ज वाल्व | |
| vent valve | वेंट वाल्व | वेंट वाल्व | |
| vapour | वेपर | वेपर | fuel vapour = फ़्यूल वेपर |
| evaporative | इवेपोरेटिव | इवेपोरेटिव | |
| secondary air | सेकंडरी एयर | सेकंडरी एयर | |
| knock control | नॉक कंट्रोल | नॉक कंट्रोल | |
| coolant | कूलेंट | कूलेंट | |

# Fault-code asset inventory (D1–D7)

Audit branch `chore/fault-audit`, based on `main` @ `71e2783`. Read-only audit: no source, asset, test or
configuration file was changed. Every number below was produced by a script run against the files at that
commit (Node 24 scripts kept in the auditor's scratch folder, outside the repository). Where something could not
be measured it says **UNKNOWN**.

External comparison dataset: **OBDex** (github.com/foerbsnavi/OBDex, commit `bc58b0e`, 2026-08-22; data licence
CC0 1.0, tooling MIT). Cloned to `C:\Users\a\Downloads\obdex_scratch\` — outside the repository, never committed.
No OBDex text is reproduced in this document; only code identifiers and counts.

---

## D1. Every place fault-code knowledge lives

### D1.1 Exact counts

| # | Asset | Path | Purpose | Language | Entries (script-counted) | Code letters | Fields per entry | Size |
|---|---|---|---|---|---|---|---|---|
| 1 | `DtcDatabase.codes` | `lib/constants/dtc_descriptions.dart` | Engine English description **plus** cause, severity, action | English | **31** (31 unique) | P 27, B 1, C 1, U 2 | 4: `desc`, `cause`, `severity`, `action` (128 field occurrences = 31×4 + 4 in the fallback map) | 8,785 B |
| 2 | `DtcDictionaryHi.descriptions` | `lib/constants/dtc_dictionary_hi.dart` | Engine Hindi description (generated file) | Hindi (corrupted, see D4) | **999** (999 unique, 0 empty, 0 malformed keys) | P only: P0 578, P1 391, P2 30 | 1 (description string) | 117,342 B |
| 3 | `assets/dtc_translations.json` → `en` | `assets/dtc_translations.json` | Engine English description, gap-filler | English | **1,709** | P only: P0 895, P1 436, P2 314, P3 64 | 1 | 313,257 B (whole file) |
| 4 | `assets/dtc_translations.json` → `hi` | same file | Engine Hindi description, second-choice | Hindi (clean) | **1,709** (same key set as `en`: 0 codes in one and not the other) | P only (same split) | 1 | (same file) |
| 5 | `ChassisDtcDatabase.byPlatform` — Royal Enfield Classic 350 | `lib/constants/chassis_dtc_dictionary.dart` | ABS codes, manual-transcribed | English | **19** (C 16, U 3) | C, U | component, description, query, remedy, severity, meaningVerified | 53,195 B (file) |
| 6 | … Royal Enfield Bullet EFI / Continental GT | same | ABS codes in manual hex-H notation (`5043H`) | English | **19** | hex-H keys → decode to C1xxx | description, remedy (one shared generic remedy) | |
| 7 | … Honda ABS blink table | same | Blink patterns (`L-S`), manual reference only | English | **20** (1 flagged `meaningVerified: false`: 4-2) | blink keys, not DTCs | description, remedy (one shared table-level remedy) | |
| 8 | … `boschSharedCodes` | same | The one Bosch module-level code | English | **1** (`5200H` → C1200) — aliased by 4 platforms (Bajaj, Yamaha, Suzuki, KTM) | hex-H | description only | |
| 9 | `ChassisDtcDictionaryHi` | `lib/constants/chassis_dtc_dictionary_hi.dart` | Hindi parallel of 5–8 | Hindi (clean) | **19 / 19 / 20 / 1** — identical key sets to the English master per platform | as above | description, query, remedy (component never translated) | 21,044 B |
| 10 | Category headers | `lib/services/dtc_service.dart:170-241` | POWERTRAIN/CHASSIS/BODY/NETWORK/UNKNOWN labels | 10 languages (en hi bn te mr ta gu kn ml pa) | 5 × 10 = 50 strings | — | — | — |
| 11 | Severity / card labels | `lib/constants/app_strings.dart` | `severityCritical…Unknown`, `possibleCause`, `recommendedAction`, ABS copy | 23 languages (coverage in E6) | 82 keys used by the fault screens | — | — | 260,425 B (whole table) |
| 12 | `ChassisPlatforms.all` | `chassis_dtc_dictionary.dart` | Make/model → platform registry | English | 10 platforms, 6 manufacturers | — | key, make, display name, aliases, brake system, read method, dictionary kind, provenance | |
| 13 | `ChassisModuleProfiles` | `lib/constants/chassis_modules.dart` | ABS probe addresses | — | 15 candidates (2 core + 2 VAG + 10 swept + 1 × 29-bit) | — | label, request/response IDs, requests, width, convention, core | 26,514 B |
| 14 | Test fixtures | `test/chassis_*.dart` | Assert exact code sets and texts | en/hi | Not a knowledge source; mirror assets 5–9 | | | |
| 15 | `hindi_dtcs_raw.txt` and `scratchpad/gen_hi_dtc.dart` | — | Named as the source / generator of asset 2 | — | **NOT PRESENT** — not in the repo, not in any commit (`git log --all` on both names returns nothing), not among the owner folder's ignored files | | | |

Also searched and **not present**: any other JSON/CSV/YAML/SQLite DTC asset, any server-side (Supabase) DTC table,
any DTC text in `admin/`, `portal/` or `supabase/`.

### D1.2 What the engine path can describe, as a union

| Measure | Count |
|---|---|
| Distinct codes with an English description (assets 1 ∪ 3) | **1,713** (P 1,709 + B 1 + C 1 + U 2) |
| Distinct codes with a Hindi description (assets 2 ∪ 4) | **1,709** (P only) |
| Codes with English but no Hindi | 4: `B0001, C0035, U0001, U0100` (all DtcDatabase-only) |
| Codes with cause and action text | **31** (DtcDatabase only) — and see E5: never displayed |
| Codes with a severity other than `unknown` | 30 (DtcDatabase; one entry is itself `unknown`) |

Severity split in DtcDatabase: high 17, medium 10, low 3, critical 1.

---

## D2. Resolution path (summary — full trace in FAULT_SYSTEM_AUDIT.md §D2)

Engine card (`dtc_screen.dart:1144-1170` → `DtcLocalizations.description`, `dtc_service.dart:103-119`):

| UI language | 1st | 2nd | 3rd | 4th | If nothing |
|---|---|---|---|---|---|
| `hi` | `DtcDictionaryHi` (corrupted) | JSON `hi` (clean) | English already on the code (from DtcDatabase) | JSON `en` | `—` |
| any other of the 23 | English on the code (DtcDatabase) | JSON `en` | — | — | `—` |

Severity/cause/action come **only** from DtcDatabase (`obd_service.dart:1175-1184`, `2116`); a code absent there
gets `severity: 'unknown'`, empty cause and action.

Chassis card: `ChassisDtcDatabase.lookup(platformKey, code)` (with hex-H alias) → Hindi parallel if `hi` → English
master; if no entry: "Meaning not independently verified for this make." (Bosch makes) or "No manufacturer
description available for this code."

**Consequence measured:** all 999 Hindi-dictionary codes also exist in the clean JSON `hi`. The Hindi text is
identical in only **6** of them; in **993** the corrupted text wins because it is tried first. The clean JSON
Hindi is reached only for the other **710** codes.

---

## D3. Coverage against the open generic layer (OBDex, 9,533 generic codes)

### D3.1 Totals

| Measure | Count | Share of OBDex |
|---|---|---|
| OBDex generic codes | 9,533 (B0 323, C0 626, P0 3,705, P2 3,495, P3 155, U0 1,055, U3 174) | 100% |
| …with an app English description | **1,277** | **13.4%** |
| …with an app Hindi description | **1,273** | 13.4% |
| …with app cause + action | **31** | 0.3% |
| App English codes **outside** the generic set | **436**, all `P1xxx` (manufacturer-controlled range) | — |

### D3.2 By family

| Family | OBDex codes | App EN | App HI | App cause+action |
|---|---|---|---|---|
| P0 | 3,705 | 895 | 895 | 27 |
| P2 | 3,495 | 314 | 314 | 0 |
| P3 | 155 | 64 | 64 | 0 |
| B0 | 323 | 1 | 0 | 1 |
| C0 | 626 | 1 | 0 | 1 |
| U0 | 1,055 | 2 | 0 | 2 |
| U3 | 174 | 0 | 0 | 0 |

### D3.3 Ranges with zero app coverage (3-character blocks, app/OBDex)

- **P0:** `P0A`–`P0F` entirely (0 of 1,280 — hybrid/EV and newer P0 extensions). Partial elsewhere: P00 82/255,
  P01 100/256, P02 100/256, P03 91/253, P04 99/256, **P05 55/256**, P06 77/256, P07 100/256, P08 91/234, P09 100/147.
- **P2:** `P28`, `P2A`–`P2E` entirely (0 of 1,447). Thin: P23 24/256, P24 31/256, P25 7/256, P26 5/256, P27 12/242.
- **P3:** P34 64/155 (only the cylinder-deactivation block exists in OBDex).
- **B, C, U:** every block except `B00` (1/152), `C00` (1/116), `U00` (1/116), `U01` (1/182) is at zero.

### D3.4 Agreement on overlapping codes

For the 1,273 codes both sources describe, 44 have English titles sharing under 20% of content words
(script: Jaccard on content words). Spot-checking those against SAE J2012 wording shows **errors on both sides**:
the app's JSON English carries manufacturer-specific (GM-style) wording for some generic codes (e.g. P0322, P0382
describe different faults from the SAE meaning), while OBDex is itself wrong for others (e.g. P0139, P0142, P0260,
where the app's wording is the SAE one). **Neither source can be imported as ground truth without review.**

### D3.5 The 100 most relevant missing codes for small single/twin-cylinder fuel-injected motorcycles

Method: candidate families chosen for a 1–2 cylinder, single-bank, port-injected engine with 1–2 O2 sensors, no
turbo/EGR/diesel/transmission ECU (crank/cam, coil, injector, fuel pump, O2, throttle/idle, MAP/IAT/ECT/baro,
speed, neutral/clutch, charging, ECM internal, evap/secondary air, CAN, generic C0 ABS). Each candidate was kept only
if it exists in OBDex and has **no English description anywhere in the app**; titles mentioning bank 2, sensor 3,
HVAC, TCM, body-control or vehicle-dynamics modules were dropped. That yields **84**; the remaining **16** come from
a wider keyword pass and are marked lower-confidence. Titles are deliberately omitted (no dataset text is copied);
look them up by code.

Notable result: the app already describes most of the mainstream motorcycle P0 codes in English (e.g. every
candidate in the neutral/clutch/gear, fuel-trim/misfire/knock, oil/fan/sensor-reference groups is present). The
real gaps are **U (network) codes, C0 codes, newer O2 response codes (P013x–P015x), throttle-actuator B,
barometric sensor B, ECM-internal P06xx** — and, independently, the engine path cannot show U/C/B codes at all
(see FAULT_SYSTEM_AUDIT §C2), so adding U-code text alone would change nothing on screen.

| Group | n | Codes (rank order within group) |
|---|---|---|
| Crank / cam position | 1 | P0017 |
| Ignition coil / ignition | 2 | P2302, P2305 |
| Injector / fuel delivery | 5 | P062B, P0627, P2635, P064A, P069E |
| O2 / air-fuel sensor (bank 1) | 13 | P013A, P013B, P013E, P013F, P0053, P0054, P014C, P014D, P015A, P015B, P2A00, P2A01, P064D |
| Throttle / idle control | 13 | P050A, P050B, P050C, P050D, P0519, P210A, P210B, P210C, P210D, P210E, P210F, P060E, P061F |
| MAP / baro / IAT / ECT / oil temp | 7 | P222A, P222B, P222C, P222D, P222E, P222F, P011B |
| Vehicle / wheel speed | 1 | P062C |
| Charging / system voltage / starter | 2 | P2502, P2505 |
| ECM internal / immobiliser | 6 | P060A, P060B, P060C, P060D, P062F, P06D1 |
| Evap / secondary air (BS-VI) | 2 | P041F, P044F |
| ABS generic C0 (engine-side visibility) ¹ | 18 | C0036, C0040, C0041, C0045, C0046, C0050, C0051, C0060, C0065, C0110, C0121, C0161, C0245, C0265, C0266, C0550, C0561, C0800 |
| Network (CAN) | 14 | U0002, U0003, U0073, U0121, U0155, U0167, U0168, U0401, U0415, U0426, U0300, U0301, U0107, U0109 |
| Tier 2 — lower-confidence relevance (cam/crank response, temperature correlation, idle, starter, clutch) | 16 | P000A, P000B, P009A, P011A, P012F, P01F0, P034A, P034B, P0518, P054E, P060F, P062A, P063F, P06E9, P080A, P081A |
| **Total** | **100** | |

¹ Generic C0 definitions are car-oriented (four wheels, steering, brake booster). Motorcycle ABS modules seen so far
report manufacturer-range C1xxx codes (Classic 350 table). Several C0 entries (e.g. C0051, C0266) are unlikely to
ever appear on a motorcycle; they are listed because the brief asked for 100, and ranked last within their tier.

**Tip-over / bank-angle sensor:** OBDex's generic set has no code for it — on motorcycles it is manufacturer-specific
(P1xxx or blink code). It cannot be covered from a generic dataset at all.

---

## D4. Hindi text quality — measured

### D4.1 Per-asset results

Heuristics (all counted by script over Devanagari tokens): a token that **starts with a combining mark**
(dependent vowel sign, virama, nukta or anusvara — invalid at word start); **two dependent vowel signs in a row**;
a word **ending in a bare virama** (the `र्` pattern); or one of 19 observed recurring broken patterns
(`सतकि`, `तसस्टम`, `^िापमान`, `ररले`, `कै`, `कं`, `ोल`, `प्रदशिन`, `अतिक`…).

| Asset | Entries | Entries with ≥1 flagged token | Devanagari tokens | Flagged tokens | Distinct flagged |
|---|---|---|---|---|---|
| `DtcDictionaryHi` (engine) | 999 | **882 (88.3%)** | 6,673 | **1,778 (26.6%)** | 80 |
| JSON `hi` (engine) | 1,709 | 0 | 9,922 | 0 | 0 |
| `ChassisDtcDictionaryHi` (all Devanagari strings) | 98 strings | 0 | 512 | 0 | 0 |
| `app_strings.dart` Hindi block | 403 strings | 0 | 1,654 | 0 | 0 |
| `l10n/app_hi.arb` | 117 strings | 0 | 238 | 0 | 0 |

A second, independent measure: taking every Devanagari token that appears in the four clean Hindi assets as a
reference vocabulary, **990 of 999** dictionary entries (99.1%) contain at least one token that never occurs in any
clean asset, and **57.1%** of all dictionary tokens (3,811 of 6,673) are out-of-vocabulary. This is an upper bound
(the dictionary also uses legitimate native words such as `स्थिति`, `नियंत्रण` where the JSON uses loanwords
`पोजिशन`, `कंट्रोल`), but both measures agree the corruption is systemic.

Other checks on the dictionary: 0 zero-width/NBSP characters, 0 non-NFC strings (the corruption is in the
characters themselves, not in normalisation). JSON Hindi: 0 non-NFC.

**Words beginning with a dependent sign:** 273 tokens across 244 entries, 26 distinct forms. Most frequent:
`ोल`×146, `िापमान`×42, `ांसतमशन`×20, `ाइवर`×17, `ॉतनक`×5, `िीमी`×4, `िक`×4, `ैक्शन`×4.
**Words ending in a bare virama:** 218 (`वोल्टेर्`×176, `रेंर्`×31, `क्रूर्`×9, `गेर्`×2).

### D4.2 The 50 most frequent broken tokens and their likely correct forms

Counts are occurrences in the 999-entry dictionary. "Likely correct" is the auditor's reading, cross-checked
against the English meaning of the entry and against the clean JSON Hindi for the same code.

| # | Broken | × | Likely correct | Pattern |
|---|---|---|---|---|
| 1 | सतकि ट | 550 | सर्किट | reph + pre-base ि misplaced, word split |
| 2 | वोल्टेर् | 176 | वोल्टेज | ज → र् |
| 3 | कं टर ोल | 151/176/146 | कंट्रोल | ट्र conjunct broken into three tokens |
| 4 | तनयंत्रण | 105 | नियंत्रण | ि → त placed before consonant |
| 5 | ऑक्सीर्न | 73 | ऑक्सीजन | ज → र् |
| 6 | तसस्टम | 71 | सिस्टम | ि → त |
| 7 | प्रदशिन | 70 | प्रदर्शन | reph lost, ि inserted |
| 8 | तसलेंडर | 63 | सिलेंडर | ि → त |
| 9 | इंर्ेक्टर | 62 | इंजेक्टर | ज → र् |
| 10 | तशफ्ट | 54 | शिफ्ट | ि → त |
| 11 | इंर्न | 51 | इंजन | ज → र् |
| 12 | िापमान | 42 | तापमान | त → ि (word-initial matra) |
| 13 | ईंिन | 41 | ईंधन | ध → ि |
| 14 | स्िच | 40 | स्विच | व lost, ि misplaced |
| 15 | तसिल | 36 | सिग्नल | ि → त, ग्न lost |
| 16 | कै मशाफ्ट | 35 | कैमशाफ्ट | word split |
| 17 | रेंर् | 31 | रेंज | ज → र् |
| 18 | इतिशन | 31 | इग्निशन | ग्नि → ति |
| 19 | पिा | 30 | पता | त → ि |
| 20 | पोर्ीशन | 29 | पोजीशन | ज → र् |
| 21 | इंर्ेक्शन | 26 | इंजेक्शन | ज → र् |
| 22 | ररले | 23 | रिले | ि → र |
| 23 | पोतर्शन | 22 | पोजिशन / कंपोज़िशन | ि → त, ज → र् |
| 24 | इंटरतमटेंट | 22 | इंटरमिटेंट | ि → त |
| 25 | टर ांसतमशन | 20 | ट्रांसमिशन | ट्र broken, ि → त |
| 26 | संदिि | 19 | संदर्भ | र्भ lost |
| 27 | डर ाइव / डर ाइवर | 19/17 | ड्राइव / ड्राइवर | ड्र broken |
| 28 | कू तलंग | 18 | कूलिंग | split, ि → त |
| 29 | टबोचार्िर | 17 | टर्बोचार्जर | reph lost, ज → ि |
| 30 | फै न | 17 | फैन | split |
| 31 | अतिक | 16 | अधिक | ध → त |
| 32 | तमसफायर | 16 | मिसफायर | ि → त |
| 33 | सीररयल | 16 | सीरियल | ि → र |
| 34 | टाइतमंग | 15 | टाइमिंग | ि → त |
| 35 | बहुि | 15 | बहुत | त → ि |
| 36 | अपयािप्त | 14 | अपर्याप्त | reph lost |
| 37 | रीसर्क्ुिलेशन | 14 | रीसर्कुलेशन | extra glyphs |
| 38 | उत्सर्िन | 14 | उत्सर्जन | ज → ि |
| 39 | टॉकि | 14 | टॉर्क | reph misplaced |
| 40 | मैतनफोल्ड | 13 | मैनिफोल्ड | ि → त |
| 41 | पर्ि | 12 | पर्ज | ज → ि |
| 42 | इलेस्क्टरकल | 12 | इलेक्ट्रिकल | conjuncts scrambled |
| 43 | तगयर | 12 | गियर | ि → त |
| 44 | तटरम | 11 | ट्रिम | ि → त, ट्र broken |
| 45 | कै टेतलस्ट | 11 | कैटेलिस्ट | split, ि → त |
| 46 | गलि | 11 | गलत | त → ि |
| 47 | अनुपाि | 11 | अनुपात | त → ि |
| 48 | तनकास | 10 | निकास | ि → त |
| 49 | मीटररंग | 10 | मीटरिंग | ि → र |
| 50 | हातन | 10 | हानि | ि → त |

Further patterns seen below the top 50: `सहसंबंि`→सहसंबंध, `गतितवति`→गतिविधि, `प्रतितक्रया`→प्रतिक्रिया,
`दक्षिा`→दक्षता, `टतमिनल`→टर्मिनल, `सतक्रय`→सक्रिय, `क्रूर्`→क्रूज़, `र्ेनरेटर`→जेनरेटर.

### D4.3 Is it a consistent mapping a rule could reverse?

**Partly consistent, not reliably reversible.** Character frequencies against the clean JSON Hindi (per thousand
Devanagari characters) show the signature of a PDF text-extraction glyph mix-up:

| Character | Dictionary ‰ | Clean JSON ‰ | Reading |
|---|---|---|---|
| त U+0924 | 52.5 | 4.7 | 11× over — displaced pre-base `ि` is emitted as `त` |
| ज U+091C | 2.2 | 17.1 | 8× under — `ज` is mostly emitted as `र्` (65 survive vs 936 in JSON) |
| ध U+0927 | 3 total | 78 total | lost, emitted as `ि` or `त` |
| ि U+093F | 46.8 | 54.2 | under, partly moved |

Why a rule-based repair is not safe:
1. **Many-to-one:** `त` in the output is sometimes a real `त` (`स्थिति`, `प्रति` are correct) and sometimes a
   displaced `ि`; `ि` is sometimes real and sometimes a displaced `त`, `ध`, or `ज`.
2. **Context-dependent:** the same source cluster is broken in some words and intact in others (`ज` survives 65 times).
3. **Information is lost:** conjuncts and letters disappear (`ट्रांसमिशन`→`ांसतमशन`, `सिग्नल`→`तसिल`), and spaces are
   inserted mid-word (`कं टर ोल`), so no mapping can restore them.
4. **Content also differs, not just spelling:** 33 entries carry a Latin qualifier absent from the English (e.g.
   P0562/P0563 add "(TCM)"); some entries describe a different vendor's meaning from the English (e.g. P0371).

**Conclusion:** fresh text is required — but it already exists for every one of these 999 codes in the clean JSON
Hindi, which the app currently ranks second. Whether to prefer the JSON Hindi (loanword register: `पोजिशन`,
`कंट्रोल`) or commission a new translation in a more native register is an owner decision (see REUSE_MAP).

**Chassis Hindi and all other Hindi assets:** 0 flagged tokens by every measure above. Two chassis tests assert
"Hindi is really Hindi" (script presence), which the engine dictionary would also pass — the engine Hindi test
(`chassis_dtc_test.dart:208`) only asserts `isNotEmpty`, so it passes on corrupted text.

---

## D5. Provenance and licence

| Asset | What the file/commit says | Licence/permission recorded | First commit |
|---|---|---|---|
| `DtcDatabase` (31, English) | Header: "Comprehensive descriptions for P, C, B, U codes". No source named. | **None** | `1f474fc` 2026-07-23 "Stable backup: Pre-Directive 26" (arrived fully formed; no earlier history) |
| `DtcDictionaryHi` (999, Hindi) | `// Source: hindi_dtcs_raw.txt (Torque Pro Hindi DTC dictionary)`; "Regenerate via scratchpad/gen_hi_dtc.dart". `dtc_service.dart:11-18` repeats "Torque Pro master text file". | **None.** No licence, permission, or attribution anywhere in the repo. The raw file and generator are absent from the repo and all history. | `1f474fc` 2026-07-23 |
| `dtc_translations.json` (1,709 ×2) | `dtc_service.dart:52-54`: "generated from a verified Torque Pro P-code export (… 999 entries)". The 999 is stale: at `1f474fc` the file held 999 codes in a `{code:{en,hi}}` shape; `f27573a` (2026-07-23, "Complete 1700+ DTC translation dictionary") restructured it to `{en:{…},hi:{…}}` with 1,709 each. Where the extra 710 codes and the clean Hindi came from is not recorded. | **None** | `1f474fc`, rewritten `f27573a` |
| Chassis EN/HI | Per-platform provenance in comments: Classic 350 = owner's photographs of the service manual §9.3.11; Bullet EFI = publicly hosted service manual p.167; Honda blink = Honda service manuals; Bosch 0x5200 = "a real dealer-tool readout". Hindi = Danlite translation. | Manufacturer manuals are copyrighted; **no permission recorded**. Transcribing short factual code tables is a lower risk than copying prose, but this is a legal question, not an engineering one. | `e5c7c63` 2026-09-03, `71e2783` 2026-09-30 |
| Category headers | Written in-house (comment `dtc_service.dart:165-169`). | n/a | `1f474fc` |

Commit author on all of these is the placeholder identity `Your Name <your_github_email@example.com>`, so authorship
cannot be established from history.

**Risk:** the two largest assets (4,417 of the 4,566 fault-description strings in the app: 999 + 1,709×2, against
31 DtcDatabase + 59 English + 59 Hindi chassis entries) name Torque Pro, a commercial product, as their
source, with no record of permission. If that is accurate, redistributing them in a paid app is a licensing exposure.
If it is inaccurate, the provenance is simply UNKNOWN. Either way it needs an owner answer before any of this data is
carried into a remote knowledge source.

---

## D6. Conflicts and duplicates

| Check | Result |
|---|---|
| Duplicate keys inside any single asset | **0** (checked raw JSON text too, where `JSON.parse` would silently drop duplicates) |
| DtcDatabase English vs JSON English, same code | 27 codes overlap; **19** worded differently (e.g. P0120: DtcDatabase = SAE "Throttle/Pedal Position Sensor A Circuit…"; JSON = a performance-fault wording). DtcDatabase wins (it is tried first). |
| DtcDatabase codes absent from JSON | 4: B0001, C0035, U0001, U0100 → no Hindi for them |
| Hindi dictionary vs JSON Hindi, same code | 999 overlap; identical **6** (P0101, P0607, P1191, P1636, P1690, P2066); different **993**; the corrupted one wins |
| Codes in one language only | English-only: 4 (above). Hindi-only: 0 |
| Chassis EN vs HI | identical key sets per platform (19/19/20/1) |
| Same number, different meaning across platforms | **By design:** C1052 = rear inlet valve (Classic 350) vs derived from 5052H = low supply voltage (Bullet EFI). Resolution is platform-keyed so they never mix (tests enforce this). |
| Engine table vs chassis tables | Engine `C0035` (DtcDatabase) is never consulted for chassis cards (`dtc_screen.dart:1150`); no conflict in practice. |
| `P1xxx` in engine assets | 436 English (+391 in the Hindi dictionary) manufacturer-range codes carry one fixed meaning each (several are GM terms: SDM, Active Banking Control, Park/Neutral to Drive). A `P1xxx` from a Royal Enfield/Bajaj/Honda ECU would be shown with another manufacturer's meaning, with no warning. |

---

## D7. Sizes and load behaviour

| Asset | How loaded | When | Memory/start-up effect |
|---|---|---|---|
| `dtc_translations.json` 313,257 B | `rootBundle.loadString` + `json.decode` into `Map<String, Map<String,String>>` (`dtc_service.dart:59-69`) | `main.dart:71`, **awaited before `runApp`**, on the UI isolate | Whole file decoded synchronously before first frame. Decode time on a phone: **UNKNOWN** (not measured on device). Failure is swallowed (prints, leaves map empty). |
| `DtcDictionaryHi` 117 KB source | `const Map` compiled into the AOT snapshot | Always resident | Part of app binary; no I/O |
| Chassis tables, DtcDatabase | `const` maps | Always resident | Negligible |

**Would tens of thousands of entries per language work in this design?** Not as is. At the measured ~92 bytes per
key-and-text line, 30,000 codes × 2 languages is ~5.5 MB of JSON (estimate, not measured) decoded on the UI isolate
before the first frame, fully resident, with no versioning, no partial loading and no way to update without an app
release. A larger dataset needs lazy or indexed storage (e.g. an on-device database or per-range shards), decoding off
the UI isolate, and a version stamp — none of which exist today.

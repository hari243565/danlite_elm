# Basic tier report (Phase 3A): a standard name for every agreed standard code, English and Hindi

Branch `content/seed-20261001`. `main` was not touched. Nothing here has been run in the app.

## In one paragraph

**7,672 standard codes** that are not yet shipped now have a short, honest "basic" entry in English and in Hindi: the
standard's name for the code and nothing else. They live in two new packs, `data/content/generic_basic_en.jsonl` and
`generic_basic_hi.jsonl` (about 9.1 MB and 10.0 MB, that is 8.7 and 9.5 MiB, both under the 12 MB limit), with manifests. The entries say what the
code is called, add one fixed sentence ("This code has a standard name only. We have no further guidance for it yet.
If the warning lamp is on or the bike runs badly, have it checked soon."), and make **no** claim about whether the bike
can be ridden. 1,861 codes were left out and are counted below by reason. The validator passes the whole set and
rejects all 47 deliberately broken entries.

**Important, read before bundling: the app's importer would refuse these packs as they are** (see "What the app's
importer needs" below). That is not a content fault; it is the open owner decision 4 of the Phase 4A report.

## Which codes were included and which were left out

All 9,533 codes of the OBDex list (commit `bc58b0eb7273`) were judged. The title for each code is the OBDex title
(or the owner-checked title in `title_overrides.csv` where the code is there), and it must AGREE with the Wal33D title
(commit `04c43d72e7db`) under the existing normaliser of `title_agreement.py`. That script now has an `--all` mode
(`title_agreement_all.csv`): 8,469 AGREE, 780 DISAGREE, 284 MISSING. A code is counted under the **first** reason that
applies, in this order.

| Reason | P | C | B | U | Total |
|---|---:|---:|---:|---:|---:|
| shipped (the 308 entries already in the seed) | 281 | 2 | 0 | 25 | 308 |
| held out (`held_entries_v5.jsonl`) | 12 | 9 | 0 | 0 | 21 |
| chassis wheel speed or wheel position (see below) | 0 | 117 | 0 | 0 | 117 |
| missing from Wal33D | 1 | 130 | 134 | 1 | 266 |
| the two sources disagree | 530 | 28 | 63 | 122 | 743 |
| other: title longer than 70 characters (importer limit) | 266 | 6 | 0 | 62 | 334 |
| other: the same title sits on two or more codes | 8 | 0 | 0 | 2 | 10 |
| other: "agree" but not the same words (see sceptic pass) | 53 | 0 | 1 | 5 | 59 |
| other: a word glued to itself in the title (`CircuitCircuit`) | 3 | 0 | 0 | 0 | 3 |
| **Left out** | **1,154** | **292** | **198** | **217** | **1,861** |
| **Included** | **6,201** | **334** | **125** | **1,012** | **7,672** |
| All OBDex codes | 7,355 | 626 | 323 | 1,229 | 9,533 |

"Chassis wheel speed" covers every C code whose title names a wheel speed sensor or tone wheel (95 at first) **and**
every C code that names a wheel position ("Left Front Inlet Control", 12 more). A bike has a front and a rear wheel,
and the sources and the makers disagree on what a left or right position means. Because this reason comes before "missing", 10 C codes that would otherwise be counted as missing from Wal33D
are counted here.

## Batches

Code ranges of about 500, one commit and push each. The plan is deterministic (`basic_classification.csv`), and a
batch is "done" when all its included codes are in both packs, so the script resumes by itself.

| Batch | Codes in range | Range |
|---|---:|---|
| P01 | 491 | P0001 to P01EB |
| P02 | 491 | P01EC to P03D9 |
| P03 | 491 | P03DA to P05C4 |
| P04 | 491 | P05C5 to P07AF |
| P05 | 491 | P07B0 to P0A1D |
| P06 | 491 | P0A1E to P0C08 |
| P07 | 491 | P0C09 to P0DF3 |
| P08 | 491 | P0DF4 to P20DE |
| P09 | 491 | P20DF to P22C9 |
| P10 | 491 | P22CA to P24B4 |
| P11 | 491 | P24B5 to P269F |
| P12 | 491 | P26A0 to P289C |
| P13 | 491 | P289D to P2B8C |
| P14 | 491 | P2B8D to P2D77 |
| P15 | 481 | P2D78 to P34C8 |
| C01 | 626 | C0001 to C0960 |
| B01 | 323 | B0001 to B0990 |
| U01 | 615 | U0001 to U043E |
| U02 | 614 | U043F to U3576 |

**All 19 batches are done.** Nothing is left to resume. To rebuild after any change: `py build_basic.py --refresh`
then `py validate_basic.py --complete`.

## What an entry looks like

English (`generic:P0001:en`): title and `standard_title_en` are the agreed title; `meaning_en` is "Standard name: *title*.";
`rider_advice_en` is the fixed sentence; `rider_action_level` INFO; `rider_action_basis` "Draft: standard name only";
`confidence` low; `verification` `standard_title_only`; `needs_independent_review` true; no causes, no hints; `system`
from the code letter; `derived_from` records the OBDex entry hash and, when the title's ending clearly says it, a
`failure_type` (open circuit, voltage below or above threshold, performance or incorrect operation, intermittent,
circuit fault, communication lost). 3,704 entries have no failure type because their title does not clearly state one.

Hindi (`generic:P0001:hi`): `title_hi`, `meaning_hi` "मानक नाम: *title*।", the fixed Hindi advice (translated once and stored in
`CANONICAL_HI.md`, section "Basic tier"), `hi_status` machine, `needs_independent_review` true.

## How the Hindi was made (a change of method, said plainly)

The brief asked for batches of about 150 unique **titles**. The standard's titles are built from a small vocabulary:
the included titles use only about 740 distinct words. So I translated the **vocabulary**, in nine rounds of 56 to 145
words or phrases, and a program composes every title from it (`basic_hi.py`). Result: the same English word is the same
Hindi word in every title, and identical English is always identical Hindi (the validator re-derives every Hindi title
and fails on any difference, which it did when I changed a word and forgot to rebuild: that is the check working).

**Hindi translation memory size:** 786 entries in `basic_hi_vocab.tsv` (734 words, 52 multi-word phrases such as "out of
range" or "state of charge"), 11 whole-title overrides in `basic_hi_titles.tsv` where word order would read wrongly
(for example "Air Leak Between MAF and Throttle Body"), and 8 sentence frames and 1 mid-title rule in `basic_hi.py`
("Lost Communication With X" becomes "X से संचार टूट गया"). The glossary choices follow `GLOSSARY_HI.md` (संचार टूट गया, सीमा से कम,
चेतावनी लैंप, सर्किट में खराबी and so on). ABS-style acronyms, sensor letters and numbers stay in Latin script.

## Validator and self-tests

* `validate_basic.py --complete`: **7,672 English rows, 7,672 Hindi rows, English 9,079,796 bytes, Hindi 9,956,640 bytes: all checks
  pass.** Rule list in its header (E1 to E10 for English and packs, H1 to H7 for Hindi).
* `validator_basic_selftest.py`: **47 deliberately broken entries are all rejected**, each by the rule that should catch it
  (not the agreed title, a code the sources disagree on, a shipped code, a held code, a wheel-speed code, a wheel-position
  code, a manufacturer range, extra text, an invented cause, a "stop riding" claim, a can-ride claim, level other than INFO,
  English left in Hindi, an old Hindi spelling, a Devanagari digit, a missing or unfilled placeholder, a duplicate content
  id, a pack over 12 MB, a wrong manifest hash, and more). The same run checks that every rule is exercised by at least one
  test, and that the real rows pass.
* The old checks still pass: `validate_hi.py` (308 rows, 0 errors) and `validator_hi_selftest.py` (56 of 56).

## Pack sizes

| Pack | Entries | Raw bytes | Gzipped | Limit |
|---|---:|---:|---:|---|
| `generic_basic_en.jsonl` | 7,672 | 9,079,796 (8.7 MB) | about 0.54 MB | 12 MB |
| `generic_basic_hi.jsonl` | 7,672 | 9,956,640 (9.5 MB) | about 0.20 MB | 12 MB |

To stay under 12 MB the Hindi rows carry a lean `derived_from` (source, licence, mode); the English row of the same code
has the full record. Both packs are scope `generic`, review state `draft`, unsigned, bundled.

## Ten example entries (English and Hindi titles)

| Code | English title | Hindi title | Failure type stored |
|---|---|---|---|
| P0001 | Fuel Volume Regulator A Control Circuit/Open | फ़्यूल वॉल्यूम रेगुलेटर A कंट्रोल सर्किट/ओपन | open circuit |
| P0181 | Fuel Temperature Sensor A Circuit Range / Performance | फ़्यूल तापमान सेंसर A सर्किट रेंज / परफ़ॉर्मेंस | performance or incorrect operation |
| P0C61 | Drive Motor B Position Sensor Circuit B Circuit Low | ड्राइव मोटर B पोज़ीशन सेंसर सर्किट B सर्किट लो | voltage below threshold |
| P0C8B | Hybrid/EV Battery Temperature Sensor I Circuit High | हाइब्रिड/EV बैटरी तापमान सेंसर I सर्किट हाई | voltage above threshold |
| P2B8D | Intake Air O2 Sensor Heater Control Circuit Low Bank 1 | इनटेक एयर O2 सेंसर हीटर कंट्रोल सर्किट लो बैंक 1 | (none) |
| C05E9 | 4WD/AWD Clutch B Actuator Control Circuit Low | 4WD/AWD क्लच B एक्चुएटर कंट्रोल सर्किट लो | voltage below threshold |
| B0001 | Driver Frontal Stage 1 Deployment Control | ड्राइवर फ्रंटल स्टेज 1 डिप्लॉयमेंट कंट्रोल | (none) |
| U0101 | Lost Communication with TCM | TCM से संचार टूट गया | communication lost |
| U0331 | Software Incompatibility With Body Control Module A | बॉडी कंट्रोल मॉड्यूल A के साथ सॉफ़्टवेयर असंगति | (none) |
| U0036 | Vehicle Communication Bus A (-) shorted to Bus A (+) | वाहन संचार बस A (-) का बस A (+) से शॉर्ट | (none) |

Every one of them has the same meaning pattern ("Standard name: …." / "मानक नाम: …।"), the same fixed advice in each language,
level INFO and the label "Draft: standard name only" / "ड्राफ़्ट: सिर्फ़ मानक नाम".

## What the app's importer needs (owner decision, not a content fault)

I read `lib/knowledge/kb_validator.dart` on `feat/fault-4a`. It already accepts `verification: standard_title_only`,
but it still requires, in every **English** line: two to four likely causes, one to three technician hints, a
`can_ride_reason`, and a `can_ride_to_workshop` of yes, with care or no (and INFO may only be "yes"). The brief says no
invented causes and no claim that the bike can be ridden, so these entries have **empty** cause and hint lists and **no**
can-ride answer. With the importer as it is, **the first line would be refused and the whole pack with it** (the importer
is all-or-nothing). Before the packs are bundled, the importer must allow, for `standard_title_only` lines only:
empty `likely_causes_en` and `technician_hints_en`; `can_ride_to_workshop` and `can_ride_reason` unset (the screen
already hides the can-ride line when it is unset); the `derived_from` keys `title_basis`, `failure_type` (it ignores
extra keys); and the English `title` limit stays 70 (I left out the 334 longer titles for this reason; if the limit
is raised for title-only lines they can be added). The flags are `false/false/false` because the importer demands three
booleans; they are placeholders and not shown anywhere. I did not change any Dart file.

## Sceptic pass: what I looked for and what I found

* **The two title sources are almost the same list.** Of the 8,469 AGREE codes, 7,280 have word-for-word identical titles
  and most of the rest differ only in punctuation, quotes, spacing or an added "Bank 1". "Two sources agree" therefore may mean "one source copied the other".
* **Agreement is lenient.** The normaliser drops filler words. Comparing the normalised word sets, 56 AGREE codes still
  differed by a word (for example P2BA9 "Insufficient Reagent" against "Insufficient Reagent Quality", U0196 "Rear Seat
  Entertainment" against "Entertainment Control Module - Rear A"). I did not trust those: they are excluded
  ("agree but not the same words": 59 codes including 3 that moved down from the length rule).
* **Source typos and duplicates:** three titles with `CircuitCircuit` and five titles shared by two codes each are left out.
* **The validator caught two of my own mistakes:** U065E "Ram Air Actuator" was translated with the memory word RAM (rule H4,
  fixed with a "ram air" phrase), and changed vocabulary left old rows stale (rule H2, fixed by `--refresh`).
  One intermediate commit (`bc7c65c`, batch U02) was pushed with that single H4 failure; the next commit (`e6ae47c`) fixes it.
  My commit helper did not stop on a validator failure; I checked by hand after that.
* **Hindi read-through:** I read about 200 composed Hindi titles across all prefixes and corrected the patterns that read
  wrongly (over-temperature, state of charge, "X to Y", closed loop, shorted to, per-wheel positions).

## What is NOT checked

* **No human has read the Hindi.** It is composed from a vocabulary I translated; word order follows English; some
  titles read stiffly. All rows are `hi_status: machine` and `needs_independent_review: true`.
* **No human has checked the English titles against the real SAE standard.** The two sources may share an origin.
* **A code in a car-only range** (diesel, hybrid, airbag, hydrogen) is included if the two sources agree; its name
  says nothing about whether a bike can have it. Nothing in the entry claims it can.
* **The failure type is read from the end of the title by a rule**, not by a person. 3,704 titles have none.
* **The packs have not been imported by the app** (see above), and nothing was run on a phone.
* The only Python run was the repository's own scripts and the ones added here; no code from the cloned repositories
  was executed (the OBDex and Wal33D data files were only read).

## Additions beyond the brief

* `title_agreement.py --all` (all 9,533 codes) and `title_agreement_all.csv`.
* The stricter "same words" gate, the wheel-position rule, the glued-word rule and the shared-title rule (counts above).
* `basic_classification.csv`: one row per code with status, reason, batch, title, title basis, failure type, OBDex hash.
* Failure type stored in `derived_from` (not a schema field, so it cannot be refused for being extra).
* `build_basic.py --refresh`, `--status`, `--todo`; `basic_common.py` (one place for the fixed texts);
  `CANONICAL_HI.md` has a new "Basic tier" section that the validator compares with the code.
* The decision records: Hindi `derived_from` kept lean for size; flags false; can-ride unset; titles over 70 characters left out.

## Files

`data/content/`: `generic_basic_en.jsonl`, `generic_basic_hi.jsonl`, `generic_basic_en_manifest.json`,
`generic_basic_hi_manifest.json`, `basic_classification.csv`, `title_agreement_all.csv`, `basic_hi_vocab.tsv`,
`basic_hi_titles.tsv`, `basic_common.py`, `basic_hi.py`, `build_basic.py`, `validate_basic.py`,
`validator_basic_selftest.py`; changed: `title_agreement.py` (new `--all`), `CANONICAL_HI.md` (new section).

Branch `content/seed-20261001`, last content commit: see the line below.

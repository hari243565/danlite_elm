# Hindi report: Hindi for every shipped English entry (aim A4, Phase 2)

Date: 2026-10-03. Branch: `content/seed-20261001`. Author session: one local session, no cloud, no review sessions.
Only `data/content/` and `docs/content/` changed. `main` was not touched. Phase 1 was checked first: the English
validator reports 0 errors (308 entries, 15 warnings as before) and its 109 self-tests pass; both still do after this
work.

## In plain English

All **308** shipped English entries now have a Hindi row (`generic_hi_seed.jsonl`). The new checking program
(`validate_hi.py`) reports **0 errors** on all 308, and its self-test (`validator_hi_selftest.py`) passes
**56 of 56**. Every row is marked as an AI draft. **No person has read this Hindi.** The checks below catch spelling,
wording rules, numbers, fixed sentences and stop/do-not-ride wording; they cannot tell whether a sentence is good Hindi
or whether it means exactly what the English means. That needs a Hindi-reading mechanic or translator.

| What | Count |
|---|---|
| English entries shipped / Hindi rows | 308 / 308 |
| Rider action levels (same as English) | 40 STOP, 199 SERVICE_SOON, 69 MONITOR |
| Distinct English strings | 1,668 (titles, meanings, causes, advice sentences, can-ride reasons, mechanic hints) |
| Filled automatically from the fixed sentences | 23 distinct sentences (used 291 times in advice) |
| Translated by this session | 1,645 distinct strings, each one once, reused wherever the same English appears |
| Hindi words in the set | about 34,700 |
| Longest Hindi sentence | 30 words (limit 30) |
| Hindi length against English | 0.65 to 1.80 times, mean 1.00 (limit 0.5 to 3) |
| Batches, each committed and pushed | 8 (entries 1-40, 41-80, ... 281-308) |

## What was written

- `data/content/GLOSSARY_HI.md`: every term of `GLOSSARY_EN.md` with its Hindi form (workshop loanwords for parts,
  ABS, ECU, CAN, MAP and VIN in Latin script, Latin digits, native verbs such as रुकें, जाँचें, कराएँ, the spellings
  "एडेप्टर" and "फ़ॉल्ट कोड" with the nukta), the failure phrases, and about 40 extra terms the entries use.
- `data/content/CANONICAL_HI.md`: the fixed sentences translated once: stall, petrol smell, ABS (with and without
  "If ABS is affected"), bus fault, the idle pair, the twin clause, the throttle-stuck-open sentence, battery hot or
  swollen, overheat, TWO-CASE, STOP-TAIL, plus a few safety sentences that repeat (coolant steam, knocking, oil
  pressure lamp, "ride gently ... stop if it runs very rough"), the hedge words, and the rider-action wording taken
  from the app (रुकें, जल्द सर्विस कराएँ, नज़र रखें, जानकारी and the three can-ride lines).
- `data/content/generic_hi_seed.jsonl` (308 rows, UTF-8, LF) in the knowledge-pack row format of `PHASE1B_PLAN.md`:
  language stored as separate rows, `content_id` `generic:CODE:hi`, fields `title_hi`, `meaning_hi`,
  `likely_causes_hi`, `rider_advice_hi`, `can_ride_reason_hi`, `technician_hints_hi`.
- `data/content/validate_hi.py`, `validator_hi_selftest.py`, and the translation tooling (below).

## How the translation was made, so it stays consistent

The same English string always gets the same Hindi. `build_hi.py` gives every distinct English string an id
(T0001, M0001, C0001, A0001, R0001, H0001), reads my translations from `hi_tm/batch1.txt` to `batch8.txt`
(one `id | Hindi` line each), copies the fixed sentences in from `CANONICAL_HI.md` word for word, and builds the rows.
If an English string changes later, the build stops and names the id, so a changed English sentence cannot keep a stale
Hindi translation. Re-running the build gives byte-identical output.

## The validator: what each check does

H1 coverage and copied fields; H2 no empty field, list sizes equal to English; H3 Unicode (NFC, no replacement or
invisible characters, no dangling combining marks, no Devanagari digits); H4 Latin letters only in ABS, ECU, CAN, MAP,
MIL, O2, VIN, Danlite, codes, units, sensor letters A-E, and never a token the English field does not have; H5 numbers
and placeholders identical; H6 forbidden spellings (अडैप्टर, एडाप्टर, फॉल्ट without nukta, दोष कोड, and anusvara or
odd-loanword variants such as जांच, कराएं, चलाएं, एबीएस, सेन्सर); H7 fixed sentences word for word, and none added
where the English does not use them; H8 every Hindi sentence 30 words or fewer, same sentence count as English; H9
stop and do-not-ride wording present exactly where the English has it, a STOP entry has one of them, a MONITOR entry has
neither; H10 glossary terms and hedges ("if fitted", "if hose-fed", "less common", "rare", "liquid-cooled", "if your
bike") used where the English uses them; H11 length ratio; H12 the app importer's own schema rules ported from
`kb_validator.dart` (allowed keys, `hi_status`, enum rules, the 1.6 times length caps, list sizes).

Self-test: the 56 tests are 1 baseline (all 308 real rows accepted), 54 deliberately broken rows each rejected by the
rule that should catch it, and 1 coverage test that every rule H1-H12 is exercised. They include the ten the brief
asks for: old spelling (five kinds), English left in (two), missing placeholder or number (three), softened stop
(four), broken combining mark (four, plus a non-NFC letter and a replacement character), canonical sentence changed
(five), empty field (four), extra row, missing row, over-long sentence (and a merged-sentence and a missing full stop).
One test was too weak the first time (it replaced only the first of two "रुकें" in P2111 and so left a stop word
standing); I fixed the test, not the validator.

The validator also caught real mistakes of mine during the work, which is the best evidence it does something:
"रात में न चलाएँ" for "no night rides" (would have read as "do not ride"), a missing glossary word "फ़्यूल", a missing
"ईंधन", a 32-word sentence, and a MONITOR rule that was too strict (see Deviations).

## The ten trickiest phrases and how I decided them

1. **"stalls" against "stop".** The engine stopping by itself is always "बंद हो" (अपने आप बंद हो जाए). "रुकें" is kept
   only for the rider, so the validator can tell a description from an instruction.
2. **"do not keep riding" and "do not ride".** "आगे न चलाएँ" and "बाइक न चलाएँ", always with the chandrabindu (the
   app's spelling). "न चलाएँ" is reserved for these, so "no night rides" became "रात में सवारी न करें".
3. **"switch off".** "इंजन बंद करें" in every safety sentence; the rider is at the roadside with the engine running.
4. **"idle may be uneven / unsteady" and "runs rough".** "आइडल अस्थिर" for both uneven and unsteady, "रफ़ चलना" for
   rough; "hesitate" is "हिचकिचाना" everywhere.
5. **"signal plausibility fault".** There is no plain Hindi word a mechanic would use, so titles say "सिग्नल
   प्लॉज़िबिलिटी फ़ॉल्ट" and the meaning sentence below says in plain words that the readings do not match.
6. **"intermittent circuit fault" and "at times".** "सर्किट में बीच-बीच में खराबी" and "कभी-कभी"; the meaning says the
   signal "कभी-कभी गायब हो जाता है या अचानक बदल जाता है".
7. **"emission".** "उत्सर्जन" (the word the app already uses in `dtcSubEmission`), not "एमिशन"; "emission system" is
   "उत्सर्जन सिस्टम". Formal, but consistent with the app.
8. **"arrange transport" and "have it taken to a workshop".** "बाइक ले जाने का इंतज़ाम करें" and "बाइक को वर्कशॉप तक
   पहुँचवाएँ" (the second is the app's own `canRideNo` wording).
9. **"ride gently" and "ride" as a noun.** "धीरे चलाएँ"; "सवारी" for a ride and "सफ़र" for a trip. I did not use
   "सावधानी से", which the app keeps for "with care".
10. **The failure phrases.** "ग्राउंड से शॉर्ट", "बैटरी सप्लाई से शॉर्ट", "ओपन सर्किट", "सीमा से कम / ज़्यादा",
    "संचार टूट गया" are fixed and checked, so a short to ground never turns into a different phrase in another entry.

## Entries where the English was unclear (translated as written; a person should look)

I noted these while translating; I did not review every entry for English ambiguity, so this list is not complete.

- **P0460 "refuel by distance, not by the display"**: not said by distance since what. I wrote "चली हुई दूरी के
  हिसाब से" (by the distance ridden).
- **P0125 and P2096 "fine fuel control / fine fuel correction"**: "fine" is the kind of idiom the V5 pass removed
  elsewhere. Translated as "सटीक" (precise).
- **P0633 "avoid switching off unless unsafe"**: the reason is not given. Translated literally.
- **P0610 "bike options setting / bike setup"**: unclear which settings. Translated literally.
- **P0600 "Serial communication link"**: vague about which link.
- **P0016, P033F "stretched / slipped timing chain"**: a mechanical claim the source titles do not state; kept as marked "(दुर्लभ)".
- **C0293 (P0651) "Pin pushed out of a connector"**: translated as the pin having come out of the connector.
- **U0140, U0146 and similar**: what a "body control unit" or "gateway" is on a bike is not explained to the rider.

## Wording fixed in my own sceptic pass

I read about 20 rows against the English after the batches. Fixed: "ठंडे में" (colloquial) became "ठंडे इंजन में" in seven
places; "चिपचिपा" (sticky as in gooey) became "चिपक रहा है" for a valve that sticks; the fixed TWO-CASE sentence now
says "अपने आप बंद हो जाए" so "stalls" means the same as everywhere else.

## What is NOT checked

- **No human has read the Hindi.** Meaning fidelity, grammar, gender agreement, register and naturalness are untested.
  A sentence can pass every check and still be wrong or awkward. The rows stay labelled draft.
- The fixed sentences (`CANONICAL_HI.md`) are used in 291 places and carry the most safety weight. They are the
  first thing a Hindi reader should read.
- The meaning of every can-ride reason, mechanic hint and cause is unchecked beyond words and numbers.
- Whether "उत्सर्जन", "व्हीकल" in sensor names against "वाहन" in running text, "इम्मोबिलाइज़र" and the other loanword
  choices suit riders in the field.
- The Dart importer was not run (only Python scripts were approved). `validate_hi.py` H12 is a Python copy of its rules;
  a real import test on a device is still needed.
- Line endings: the manifest hash is of the file with LF endings, which is what git stores. On Windows a checkout may
  turn the file into CRLF; copy it into the app from git (or convert back to LF) before using the hash.

## Deviations from the brief

1. **`hi_status`.** The brief says "ai_translated_draft". The app importer (`kb_validator.dart`) accepts only
   `machine` or `reviewed` and rejects anything else, and the brief also says the importer must accept the rows. The
   rows carry `"hi_status": "machine"`, which means the same thing (machine translated, not reviewed). The validator
   rejects `ai_translated_draft` (test included). If the owner wants the other name, the importer needs a one-line
   change first.
2. **MONITOR rule.** The brief says a MONITOR entry must not contain the stop wording. One MONITOR entry (P0442, fuel
   cap) correctly carries the fixed petrol-smell sentence ("stop and do not ride") because rule R4 puts it in any entry
   that mentions fuel. The rule is: a MONITOR entry has no stop wording except that one fixed sentence.
3. **`needs_independent_review`** is `true` on all 308 Hindi rows, though 156 of the English entries have it `false`:
   nobody has read the Hindi, so the English flag does not carry over.
4. The English validator needs the OBDex clone; I used `OBDEX_DIR=Downloads/obdex_scratch/OBDex` (pinned commit
   `bc58b0eb...`), read-only, and installed `pyyaml` with pip (the environment, not the repo). No code from the clone ran.

## Additions beyond the brief

- Titles are translated (`title_hi`): the importer requires one.
- The translation-memory tooling (`build_hi.py`, `hi_common.py`, `hi_tm/`, `hi_tm.json`) and its drift check.
- `generic_hi_manifest.json` in the shape of the English pack manifest (pack `generic_hi`, version 1, review state
  draft, no signature, SHA-256 of the entries file), so the pack can be imported once someone approves shipping it.
- Validator checks beyond the eleven asked for: the importer's rules (H12), hedges, sentence count alignment, Devanagari
  digits and invisible characters, anusvara and loanword variant spellings, the rule that a Latin token must also be in
  the English field.
- `rider_action_basis_hi` is not written (the app does not show it).

## Files

`data/content/`: `GLOSSARY_HI.md`, `CANONICAL_HI.md`, `generic_hi_seed.jsonl`, `generic_hi_manifest.json`,
`validate_hi.py`, `validator_hi_selftest.py`, `build_hi.py`, `hi_common.py`, `hi_tm/batch1.txt` to `batch8.txt`,
`hi_tm.json`. This report: `docs/content/HI_REPORT.md`.

To check: `python3 validate_hi.py` (0 errors), `python3 validator_hi_selftest.py` (56/56), `python3 build_hi.py` (rebuilds
the same bytes).

Branch `content/seed-20261001`, last commit before this report `ad45aa8`.

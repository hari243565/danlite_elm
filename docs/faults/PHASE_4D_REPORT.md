# Phase 4D report: neutral chip for name-only cards, Yamaha R15 manual table, Yamaha FZ-16 meter codes

Branch `feat/fault-4d` (from `main` @ `c18d898`, Phase 4C). `main` was not touched and nothing was merged.
Commits: M1+M2 `3b6422d`, M3 `1932152`, M4 `f21dfb3`, first report `72d2049`; then the owner's three follow-ups: M5 `427578e`, M6 `62874dd`, M7 `1401e67`, and this updated report.
`ios/Runner/GeneratedPluginRegistrant.m` is still modified and was never staged.

## What was done

| Item | In plain words | Proving tests |
|---|---|---|
| M1 | A name-only card (verification `standard_title_only`) no longer shows the "Info" chip. It shows a grey chip with an icon and the words "Name only" / "सिर्फ़ नाम". The card colour is grey too. Every other entry's chip is untouched. In the data the entry is still INFO, so the CRITICAL count and the card order are exactly as before. The same chip is used on the fault card, the code lookup and the scan history. | `phase4d_name_only_chip_test.dart` (20): words, chip widget, both languages, CRITICAL stays 0 / 1, a STOP card sorts above, a SERVICE SOON card sorts above |
| M2 | On name-only cards the title is shown once. The line "Standard name: <same title>." is hidden; it stays in the data. All 15,344 shipped name-only rows (English and Hindi) repeat the title in that line, so all are hidden; a row whose line said something else would still show it. | same file (card and lookup, English and Hindi, and a guidance card still shows its meaning line) |
| M3 | 21 standard P-codes from the Yamaha R15 2022 manual (page 8-47) with Yamaha's fail-safe columns, for a Yamaha profile whose model is exactly R15, R15M or YZF155 and whose model year is 2022 or later. It beats generic guidance, a bare name and the older table for that bike only. | `phase4d_r15_table_test.dart` (105): every row, scope, year rule, precedence, ride answers, Hindi, strings. `phase4d_r15_screens_test.dart` (38): card, lookup with mechanic section, scan history, 20 other-bike cases |
| M4 | Under "Blink-code references": Yamaha FZ-16 FI meter codes, manual page 7-24. Type the number on the meter. 15 = throttle position sensor, open or short circuit detected; 16 = throttle position sensor, stuck. The screen always says other codes exist, are not listed because they are not verified, and to ask a Yamaha service centre; and that it is not confirmed for newer FZ-S FI models. | `phase4d_fz16_meter_test.dart` (22): both rows, every other number, no-match, odd input, both languages, list order |

## Follow-ups (owner request before merge)

| Item | In plain words | Proving tests |
|---|---|---|
| M5 | The R15 maker text for **P00D1** and **P2195** is no longer shown (their wording conflicts with the standard names). On an R15 those two codes now get the generic standard meaning. The two rows and their "reconstructed" notes stay in the table, marked `withheld: true`, with a comment saying how to restore them after manual page 8-47 is checked. **P0132** stays visible with the Draft line. | `phase4d_r15_table_test.dart`, `phase4d_r15_screens_test.dart`: both codes, with and without a store, English and Hindi, year known or not; 19 rows still shown; P0132 draft |
| M6 | The profile's model year can be unknown (nullable). The form no longer pre-selects the current year: it starts at "Not set" and has an explicit "Year unknown" choice. A one-time migration (flag `vehicleYearUnknownMigrationV1`) sets the year of every existing saved profile to unknown, writes it back, and asks nothing. A year the rider sets afterwards is never wiped; a fresh install sets the flag too. An unreadable saved year reads as unknown. The R15 rule is unchanged: unknown shows the table with the check-your-model-year note. | `phase4d_profile_year_test.dart` (27): model, migration (4 profiles, runs once, fresh install, flag already set, bad data), form (6 cases), R15 with unknown / 2021 / 2022 / 2025, card in English and Hindi |
| M7 | "Look up a code": a code in standard format now resolves through the generic path on every make, including Bosch-ABS makes (Yamaha, Bajaj, Suzuki, KTM), and shows this bike's maker-table meaning first when the profile has one. Bosch raw module codes (5043H) keep their raw handling. A code in a manufacturer range shows "Meaning of manufacturer-defined codes can differ by make" (English and Hindi). | `phase4d_lookup_standard_codes_test.dart` (35): P0107 on Yamaha, Bajaj, no profile and six more makes, P1xxx, P3000, C1043, U2000, B2000, 5043H, 5200H |

How M7 works: a new resolver mode `FaultDomain.lookup` is used only by the lookup screen. In it, the rule that stops a Bosch make's codes from getting generic text (which is about values READ from its module) does not apply to a code the rider typed in standard format. The reading screens (engine and ABS) and the default mode are unchanged and tested to be. The Bosch derived C1xxx values are in the manufacturer range, so they never get generic text either way.

Where the year is read: the profile card (now "Year unknown · PETROL · ..."), the profile's display name (no longer prints "null" or a made-up year), the scan-history snapshot, and the R15 rule. Nothing else in the app (fuel economy, performance, trips) reads the profile year; confirmed by searching the code. The profile form is English-only today, so "Not set" and "Year unknown" are plain English there like the rest of that form.

## M3 decisions and facts

**Static table in code, not a knowledge pack.** The pack format can name a vehicle scope, but it can only carry AI-written guidance: no "manufacturer manual" verification value, no model year rule, no fail-safe columns. Widening the signed, hashed importer for one table is the larger risk. So the table is `lib/constants/maker_engine_tables.dart`, following the Royal Enfield ABS table pattern, and it reuses the existing label "From the manufacturer's service manual".

**Scope is exact.** The make must resolve to Yamaha and the normalised model must exactly equal one of: r15, r15m, r15v4, yzfr15, yzfr15m, yzfr15v4, yzf155, yzf155a, yamahar15, yamahar15m. "R15 V3", "R15S", "FZ-S", "MT-15", a blank model, another make's "R15" get nothing. The resolver also re-checks the make, so a forced vehicle key on a Honda is ignored.

**Year rule.** Before 2022, never; 2022 or later, shown; year unknown, shown with "This table is from the 2022 R15/R15M manual; check your model year." Since M6 the profile can really hold "unknown", so the unknown branch is reachable (every profile saved before M6 becomes unknown).

**Ride answer.** Stop and "cannot ride" where the maker says the engine will not start or the bike cannot be driven (P0201, P0335, P0351); otherwise Service soon and "with care". A line under the card says this is Danlite's reading of the fail-safe column, not Yamaha's wording. Dealer-tool items, the "to be checked" notes and the source line are in the mechanic section only (code lookup).

**Unverified rows.** Since M5, P00D1 and P2195 (reconstructed) are withheld and fall back to the generic meaning. P0132 (inferred) is shown with the Draft line on the card and a "to be checked against the manual page" note in the mechanic section.

## Strings (new)

English / Hindi pairs, all with matching keys (parity tests):

- `riderActionNameOnly`: "Name only" / "सिर्फ़ नाम"
- `makerFailSafeNoStart`: "{make} says the engine will not start and the bike cannot be driven"; `makerFailSafeNoDrive`: "{make} says the bike cannot be driven"; `makerFailSafeCanDrive`: "{make} says the bike can still be driven"
- `makerJudgementNote`: "The action word and the ride answer are Danlite's own reading of {make}'s fail-safe column, not {make}'s wording"
- `makerYearNoteR15`: "This table is from the 2022 R15/R15M manual; check your model year."
- `makerDealerItem`: "{make} dealer-tool item: {item}"
- `makerCheckReconstructed` / `makerCheckInferred`: "This row is to be checked against the manual page: it was reconstructed / its place in the table was worked out, not read from the page"
- `makerSourceR15`: "Source: Yamaha R15 / R15M / YZF155-A 2022 service manual, page 8-47"
- `blinkRefsYamaha`, `blinkRefsYamahaSub`, `fz16Title`, `fz16Intro`, `fz16Applies` ("This applies to the older FZ-16 FI. It has not been confirmed for newer FZ-S FI models."), `fz16Field`, `fz16Choose`, `fz16NoMatch`, `fz16Others` ("Other codes exist on this bike; they are not listed here because they have not been verified. Ask a Yamaha service centre."), `fz16Code15`, `fz16Code16`, `fz16Source` ("Source: Yamaha FZ-16 service manual, page 7-24")
- `lookupMfrRangeNote`: "Meaning of manufacturer-defined codes can differ by make" / "निर्माता-परिभाषित कोड का मतलब अलग-अलग मेक में अलग हो सकता है"
- The profile form's "Not set" and "Year unknown" (English only, like the rest of that form)
- The 21 Yamaha meanings in Hindi are in the table file and are marked machine-translated (the existing Hindi-machine line shows).

## Final verification (after the follow-ups)

- Whole suite after the follow-ups: **1,455 pass, 0 fail** (1,195 before Phase 4D). Changes to older tests: the first report's note below, and the R15 tests that used P00D1 / P2195 now use P0132 or test the fallback. (First report: three Phase 4C card tests were changed on purpose to the new owner-decided behaviour (Info chip becomes Name only; the repeated line is now absent). One optional `year` and one `yearUnknown` parameter were added to the shared screen-test setup.)
- `flutter analyze`: the same 7 known issues, nothing new.
- `flutter build apk --debug`: succeeds.
- `main` is `c18d898d9141d3a335f5a3b07b6617a7f3ec20ca`, the same as at the start, locally and on `origin`.
- One timing test (`knowledge_scale_test`, lookup under 200 ms) failed once in a full run on a busy PC and passed alone twice and in the next full run. Not related to this work.

## Found beyond the brief

Fixed (inside M3):
- **A saved scan could be explained with another bike's maker table.** The scan history re-explains each code for the active profile. A scan saved on another profile (or none), viewed after switching to an R15 profile, would have shown Yamaha's text. It now uses the maker table only when the session was saved on the active profile. Tested in the list detail and in Share, with the fix switched off to prove the test bites.
- **Share in scan history was refused in debug builds** (it asked the screen for a translation outside a build). Release was fine. Fixed because Share is the path this change touches.

Not fixed:
1. **Two R15 rows are withheld, not checked.** P00D1 and P2195 stay out until someone reads manual page 8-47 (P2195 is "signal stuck lean" in the standard, "open circuit" in the brief; P00D1 is "heater performance" in the standard, "no normal signal while driving" in the brief). Restoring either is deleting its `withheld: true`.
2. **The brief said 14 rows; it listed 21 codes.** All 21 are in the data (19 are shown).
3. **The lookup list is not bike-aware.** An R15 owner typing P0107 sees the generic title in the list; the Yamaha meaning is on the page it opens.
4. **Typed C-codes on an ABS bike.** A standard-range C code (C0xxx) typed on a bike with an ABS platform now gets the generic meaning unless that platform's own table lists it (the table still wins). That is what M7 asked for; the platform's own table is checked first.

## What the owner must decide

1. Who checks manual page 8-47 so P00D1 and P2195 can be restored (and P0132's Draft mark removed).
2. The year cut-off for the R15 table: R15 V4 bikes sold in late 2021 are hidden when the year is 2021. Keep 2022, or move it.
3. Keep the grey card colour for name-only cards, or only the chip?
4. Merge `feat/fault-4d` into `main` now? (Phase 4C is already in `main`.) Note the M6 migration runs on the first start after the update and clears the model year of every saved profile.

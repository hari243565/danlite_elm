# Phase 4D report: neutral chip for name-only cards, Yamaha R15 manual table, Yamaha FZ-16 meter codes

Branch `feat/fault-4d` (from `main` @ `c18d898`, Phase 4C). `main` was not touched and nothing was merged.
Commits: M1+M2 `3b6422d`, M3 `1932152`, M4 `f21dfb3`, then this report.
`ios/Runner/GeneratedPluginRegistrant.m` is still modified and was never staged.

## What was done

| Item | In plain words | Proving tests |
|---|---|---|
| M1 | A name-only card (verification `standard_title_only`) no longer shows the "Info" chip. It shows a grey chip with an icon and the words "Name only" / "सिर्फ़ नाम". The card colour is grey too. Every other entry's chip is untouched. In the data the entry is still INFO, so the CRITICAL count and the card order are exactly as before. The same chip is used on the fault card, the code lookup and the scan history. | `phase4d_name_only_chip_test.dart` (20): words, chip widget, both languages, CRITICAL stays 0 / 1, a STOP card sorts above, a SERVICE SOON card sorts above |
| M2 | On name-only cards the title is shown once. The line "Standard name: <same title>." is hidden; it stays in the data. All 15,344 shipped name-only rows (English and Hindi) repeat the title in that line, so all are hidden; a row whose line said something else would still show it. | same file (card and lookup, English and Hindi, and a guidance card still shows its meaning line) |
| M3 | 21 standard P-codes from the Yamaha R15 2022 manual (page 8-47) with Yamaha's fail-safe columns, for a Yamaha profile whose model is exactly R15, R15M or YZF155 and whose model year is 2022 or later. It beats generic guidance, a bare name and the older table for that bike only. | `phase4d_r15_table_test.dart` (105): every row, scope, year rule, precedence, ride answers, Hindi, strings. `phase4d_r15_screens_test.dart` (38): card, lookup with mechanic section, scan history, 20 other-bike cases |
| M4 | Under "Blink-code references": Yamaha FZ-16 FI meter codes, manual page 7-24. Type the number on the meter. 15 = throttle position sensor, open or short circuit detected; 16 = throttle position sensor, stuck. The screen always says other codes exist, are not listed because they are not verified, and to ask a Yamaha service centre; and that it is not confirmed for newer FZ-S FI models. | `phase4d_fz16_meter_test.dart` (22): both rows, every other number, no-match, odd input, both languages, list order |

## M3 decisions and facts

**Static table in code, not a knowledge pack.** The pack format can name a vehicle scope, but it can only carry AI-written guidance: no "manufacturer manual" verification value, no model year rule, no fail-safe columns. Widening the signed, hashed importer for one table is the larger risk. So the table is `lib/constants/maker_engine_tables.dart`, following the Royal Enfield ABS table pattern, and it reuses the existing label "From the manufacturer's service manual".

**Scope is exact.** The make must resolve to Yamaha and the normalised model must exactly equal one of: r15, r15m, r15v4, yzfr15, yzfr15m, yzfr15v4, yzf155, yzf155a, yamahar15, yamahar15m. "R15 V3", "R15S", "FZ-S", "MT-15", a blank model, another make's "R15" get nothing. The resolver also re-checks the make, so a forced vehicle key on a Honda is ignored.

**Year rule.** The profile stores `year` as a plain whole number, never empty (default 2020 in the code and for older saved profiles; the form pre-selects the current year). Rule as applied: before 2022, never; 2022 or later, shown; year unknown, shown with "This table is from the 2022 R15/R15M manual; check your model year." The unknown branch cannot be reached by the profile form today (see gaps).

**Ride answer.** Stop and "cannot ride" where the maker says the engine will not start or the bike cannot be driven (P0201, P0335, P0351); otherwise Service soon and "with care". A line under the card says this is Danlite's reading of the fail-safe column, not Yamaha's wording. Dealer-tool items, the "to be checked" notes and the source line are in the mechanic section only (code lookup).

**Unverified rows.** P00D1 and P2195 (reconstructed) and P0132 (inferred) show the Draft line on the card and a "to be checked against the manual page" note in the mechanic section.

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
- The 21 Yamaha meanings in Hindi are in the table file and are marked machine-translated (the existing Hindi-machine line shows).

## M5 results

- Whole suite: **1,381 pass, 0 fail** (1,195 before, 186 new). Three Phase 4C card tests were changed on purpose to the new owner-decided behaviour (Info chip becomes Name only; the repeated line is now absent). One optional `year` parameter was added to the shared screen-test setup.
- `flutter analyze`: the same 7 known issues, nothing new.
- `flutter build apk --debug`: succeeds.
- `main` is `c18d898d9141d3a335f5a3b07b6617a7f3ec20ca`, the same as at the start, locally and on `origin`.
- One timing test (`knowledge_scale_test`, lookup under 200 ms) failed once in a full run on a busy PC and passed alone twice and in the next full run. Not related to this work.

## Found beyond the brief

Fixed (inside M3):
- **A saved scan could be explained with another bike's maker table.** The scan history re-explains each code for the active profile. A scan saved on another profile (or none), viewed after switching to an R15 profile, would have shown Yamaha's text. It now uses the maker table only when the session was saved on the active profile. Tested in the list detail and in Share, with the fix switched off to prove the test bites.
- **Share in scan history was refused in debug builds** (it asked the screen for a translation outside a build). Release was fine. Fixed because Share is the path this change touches.

Not fixed:
1. **The profile cannot say "no model year".** `VehicleProfile.year` is a whole number, 2020 by default for the code and for old saved profiles (those would never get the R15 table), and the form pre-selects the current year, so an untouched form counts as 2022 or later with no note. A nullable year or an "unknown" entry in the form would make the rule honest.
2. **Two owner rows disagree with the standard's own names.** P2195 is "signal stuck lean" in the standard, but the brief says "open circuit". P00D1 is "heater performance" in the standard, but the brief says "no normal signal while driving". Both are marked reconstructed and show Draft. Consider hiding the three unverified rows until the page is checked (a one-line filter on `check`).
3. **The brief says 14 rows; it lists 21 codes.** All 21 are in. Likely 14 manual lines, some covering more than one code.
4. **Code lookup of an engine code on a Bosch make (Yamaha, Bajaj, Suzuki, KTM) shows "show it to your dealer"** instead of the generic meaning, because the lookup does not know which module the code came from. Older behaviour, not changed. The R15 (2022 and later) is the exception: it now gets the maker meaning.
5. **The lookup list is not bike-aware.** An R15 owner typing P0107 sees the generic title in the list; the Yamaha meaning is on the page it opens.

## What the owner must decide

1. Keep the three unverified rows visible with the Draft line, or hide them until the manual page is checked (item 2).
2. The year rule at its edges: R15 V4 bikes sold in late 2021 are hidden (year 2021). Move the cut-off, or keep 2022.
3. Make the profile year nullable / add "unknown" (item 1)?
4. Keep the grey card colour for name-only cards, or only the chip?
5. Merge `feat/fault-4d` into `main` now? (Phase 4C is already in `main`.)

# Phase A-4 — scenario status

Scenario numbers and definitions are those of `chore/fault-audit:docs/faults/SCENARIO_COVERAGE.md`. "Before" is
`main` @ `d607f8b` (Phase 1B); "after" is branch `feat/fault-a4`. Proven with the simulator, hand-written replay
fixtures and tests — **not on a real bike**; the brief places live testing at the end of the whole project.

| # | Scenario | Before (d607f8b) | After (Phase A-4) | Proving test |
|---|---|---|---|---|
| 3 | Engine off vs running | **HANDLED (reads)** (Phase 1A: RPM sets the engine state; the refusal notice mentions a running engine only when it is known to be running) | **Unchanged, and kept honest next to the new snapshot.** The snapshot's RPM and speed are what the engine was doing *when the fault was recorded*; they sit under the "Snapshot when the fault was recorded" title and never touch the live engine-state reading (the `engineReport` object is identical before and after). A bike that refuses the snapshot is reported as *refused*, not as *no snapshot* | `a4_scenarios_test.dart` "Scenario 3 …" (2 tests) |
| 13 | Intermittent faults | **PARTLY** — Mode 03 confirmed codes only; stored/pending/permanent chips (1A) but no "when" and no "how long": a code that came and went left no trace but its name | **HANDLED (context shown)** — on demand ("Show details"): the snapshot recorded when the fault was set (trigger code, load, coolant, trims, pressure, RPM, speed, intake temp, throttle, ECU voltage, fuel-system status), how long the lamp has been on (km and minutes), how long ago the codes were cleared (km and minutes), and warm-ups since clearing. Each only when the bike offers it; "no snapshot stored" is its own sentence; a snapshot that belongs to a *different* code says so. A lamp that is **off** never produces "lamp has been on" (the counter is 0 then — saying so would be untrue). Nothing from before a Clear Codes is shown after it | `a4_scenarios_test.dart` "Scenario 13 …" (4 tests); `engine_context_screens_test.dart`; `engine_context_service_test.dart`; fixtures `context_full_snapshot.txt`, `context_no_snapshot.txt` |
| 14 | Pending, history and permanent codes | **HANDLED** (Phase 1A: Stored / Pending / Permanent chips, merged cards) | **UNCHANGED, proven unchanged.** The context read is a separate job: it does not rewrite the extras report, the merged records or the chips; a plain scan sends exactly what it sent before (no Mode 02, no counter request); the automatic 5-second re-read never starts a context read; a pending-only code is still listed when the bike's snapshot is for another code | `a4_scenarios_test.dart` "Scenario 14 …" (4 tests); fixture `codes_present.txt` now also asserts `contextWire: none` |

## The other things this phase settles (not numbered scenarios)

| Item | Result | Proving test |
|---|---|---|
| Timeout shown as "no data" (old Freeze Frame sheet) | **Fixed.** The old sheet returned `null` on the first timeout and printed "No Freeze Data Available". Now six outcomes: answered, *no snapshot stored* (PID 02 = 0000), *unsupported*, *no answer* (with Retry), *link lost*, *refused* — plus *not read* for the K-line gate. The old text is removed from every language | `engine_context_service_test.dart` (outcomes group); `engine_context_screens_test.dart` "silent bike"; `a4_strings_test.dart` "the old misleading text is gone" |
| A silent bike | Costs two request windows, not the whole list of 17 requests; every group reports "no answer" | `engine_context_service_test.dart` "a silent bike costs two windows" |
| Delay to the core scan | None. Never chained to a scan; the plain scan test shows no context command; a rider's manual read, Clear Codes and the ABS scan preempt it; it refuses to start while Clear Codes or an ABS scan holds the link (the case where Clear waits with no command in flight was exercised, and the guard was proven necessary by removing it) | `engine_context_service_test.dart` "kept out of the way …" (8 tests) |
| Stale context | Not shown after Clear Codes (even a refused one), on another connection, or after 2 minutes; every result carries its "Read at" time | `engine_context_service_test.dart` "nothing stale is shown as current" (5 tests) |
| Data leaving the phone | None added. Nothing is printed (a release build would turn prints into Sentry breadcrumbs), the History store and Share are untouched by the context | `engine_context_service_test.dart` "nothing is printed" |
| Clear Codes record (S2) | Shown in History **detail** only, neutral wording, English and Hindi; the Clear Codes screen shows nothing new; still left out of Share | `a4_clear_record_history_test.dart` (12 tests) |
| Debug-build Clear message (S3) | "Codes cleared successfully" now appears in debug builds; message, colour, duration and timing unchanged | `clear_codes_debug_message_test.dart` (fails without the fix) |
| Hindi spellings (S1) | One spelling per word; the main tab label is now "फ़ॉल्ट कोड" | `hindi_consistency_test.dart` |

## What still needs a real bike or a decision

- **Everything above is simulator-proven.** In particular: whether target bikes keep a Mode 02 snapshot at all, which of
  the eleven values they keep, whether PID 01 01's B/C/D bits and PIDs 21/31/4D/4E/30 are offered, and how slowly
  they answer. The decode formulas are SAE J1979 as published in public references and are flagged for a re-check
  against the standard in `engine_context.dart`.
- The two-silences-in-a-row rule (a silent bike stops the read early) and the 5-second request window are engineering
  judgement, to be confirmed live.
- Owner decisions are listed in the final report.

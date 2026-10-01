# Phase 1A — scenario status

Scenario numbers and definitions are those of `chore/fault-audit:docs/faults/SCENARIO_COVERAGE.md`. "Before" is
`main` @ `fb92092` (Phase 0 merged); "after" is branch `feat/fault-phase1a`. Status is judged by what a rider sees
on the Fault Codes screen. Everything here is proven with simulators, hand-written replay fixtures and tests —
**not on a real bike**; the brief places live testing at the end of the whole project.

| # | Scenario | Before (fb92092) | After (Phase 1A) | Proving test |
|---|---|---|---|---|
| 3 | Engine off vs running | **PARTLY** — nothing read RPM; the refusal notice always told the rider to switch the engine off, whatever the engine was doing | **HANDLED (reads)** — PID 01 0C sets engine state (running / off / unknown, threshold 300 RPM, to be confirmed live); a refusal adds "The engine is running. Stop the engine…" **only** when the engine is known to be running. Clear Codes wording untouched by owner decision | `phase1a_scenarios_test.dart` "Scenario 3 …"; `fault_screen_labels_test.dart` "A5 refusal wording …" (3 cases); fixture `engine_running_refusal.txt` |
| 8 | Response pending (NRC 0x78) | **NOT HANDLED** — `7F xx 78` was treated as a refusal; with the answer in the same buffer the ABS scan discarded the answer (audit Additions #9); the engine 03 window (3 s) was shorter than a genuine adapter's internal wait (~5 s) | **HANDLED** — one shared helper for every read (engine 03 and extras, ABS `19 02 FF` and its `03`): 5 s per attempt, re-send after 300 ms when the adapter passes the frame through, 20 s overall, flush before giving up; a buffer holding pending + answer keeps the answer; a module busy to the end is "module kept reporting busy" (engine: its own message; ABS: scan log), never empty, never success. `adapterPassesPending` learned per session from behaviour | `response_pending_test.dart` (25 tests: both adapter personalities × engine and ABS, pending forever, pending then refusal, real 5 s window); "Scenario 8 …"; fixtures `adapter_handles_pending.txt`, `adapter_passes_pending.txt`, `pending_then_answer.txt` |
| 11 | Multi-frame and large lists | **PARTLY** — CAN ISO-TP decoded; K-line gated (Phase 0); a reply cut short was shown as a complete shorter list; VIN never read | **HANDLED on CAN** — typed decoders return `Truncated` / `Unparseable` instead of a short list; the engine screen shows "The bike reports N stored code(s) but sent M…" whenever Mode 03's own count byte or PID 01 01 disagrees with what arrived; VIN read and validated from multi-frame, older multi-message, padded, spaces-off and 29-bit forms. **K-line:** a legacy-framing decoder now exists and decodes the audit's K-line samples correctly, but the gate stays off by decision | "Scenario 11 …"; `fault_decoders_test.dart`; `vin_test.dart`; `fault_decoder_fuzz_test.dart`; fixtures `multiframe_vin.txt`, `kline_samples.txt`, `zero_padded.txt` |
| 12 | Low battery and false network codes | **NOT HANDLED** — voltage only on the live dashboard; no warning on the fault screen | **HANDLED** — after the core read, PID 01 42 (else `ATRV`) is read; LOW is < 11.8 V engine off / unknown and < 12.5 V running (HIGH > 15.0 V recorded, no banner) — engineering judgement, to be confirmed live. LOW shows a banner on both segments (never blocks a scan) and marks every U-code "May be a false code caused by low battery voltage" (ABS U-codes when the scan ran within 5 min of the LOW reading). Unknown voltage is never LOW | "Scenario 12 …"; `engine_extras_test.dart` "A5 …"; `fault_screen_labels_test.dart` "A5 [en/hi] low voltage …"; fixture `low_voltage.txt` |
| 14 | Pending, history and permanent codes | **NOT HANDLED** — Mode 07 / 0A never sent; UDS status reduced to one "Unconfirmed" chip | **HANDLED** — Mode 07 and 0A read after the core and merged into one card per code: Stored (03), Pending (07), Permanent (0A); a pending- or permanent-only code gets its own card and is never hidden behind "No Fault Codes Found". Unsupported (NO DATA / NRC 11, 12, 31) shows nothing — not a failure, not empty. ABS cards show Active / Pending / History / Lamp from the status byte. An OBD code is never labelled History; unknown flags show nothing | "Scenario 14 …"; `engine_extras_test.dart` "A4 …"; `fault_record_test.dart`; fixtures `codes_present.txt`, `positive_empty.txt` |
| 17 | Two-byte and three-byte codes on one bike | **PARTLY** — kept apart, but the failure type byte was never shown and the status byte was dropped | **HANDLED** — every code is a `FaultRecord` with its format (`sae2` / `uds3`), raw bytes, failure type and status byte; ABS cards show "Failure type 0x11 · Circuit short to ground" from the 28-entry table (anything else "failure type 0xNN, no description") | "Scenario 17 …"; `fault_screen_labels_test.dart` "A2 …"; fixture `mixed_2byte_3byte.txt` |

## Counts for the six scenarios

| | Before | After |
|---|---|---|
| HANDLED | 0 | 6 (3 for reads; 11 on CAN) |
| PARTLY | 3 (3, 11, 17) | 0 |
| NOT HANDLED | 3 (8, 12, 14) | 0 |

## What still needs a real bike

- Whether target bikes' adapters pass `7F xx 78` through (the app now records `adapterPassesPending` per session
  in tester-mode recordings).
- The RPM and voltage thresholds, and whether PID 01 42 is offered or `ATRV` is the only source (clone `ATRV`
  readings can be off by a constant factor).
- Whether Mode 07 / 0A / 09 are offered at all by Indian two-wheeler ECUs.
- The failure-type table must be re-checked against the official SAE J2012-DA annex.

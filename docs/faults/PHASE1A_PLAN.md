# Phase 1A plan — the diagnostic core

Branch `feat/fault-phase1a` from `main` @ `fb92092` (Phase 0 merged by fast-forward). Worktree
`../danlite_elm_phase1a`. Baseline: **253 tests pass**, `flutter analyze` **7 issues** (all pre-existing, in
`dashboard_screen`, `fuel_screen`, `hud_screen`, `realtime_screen`).

Read first: `chore/fault-audit:docs/faults/{FAULT_SYSTEM_AUDIT,REUSE_MAP,SCENARIO_COVERAGE}.md`, and the Phase 0
code: `engine_dtc_read.dart` (sealed `EngineDtcRead`, `ObdSession`, `ObdProtocol`, K-line gate),
`obd_service.dart` (`readEngineDtcs`, `readChassisDtcs`, `_send*`, poll lock), `session_recorder.dart` (transcript
format), `dtc_screen.dart`, `test/support/engine_sim.dart`.

## What the code does today that matters here

| Fact | Where | Consequence for 1A |
|---|---|---|
| The only per-command serialisation is one completer per transport plus a counted poll lock; two foreground jobs can interleave | `obd_service.dart` `_send*`, `_acquirePollLock`, `_waitForLinkIdle` | Extras that run *after* the core result must give the link back to Clear, ABS scan and freeze frame. Done in `_waitForLinkIdle` (a shared helper), so the Clear logic itself is not edited. |
| A late reply after an app-side timeout can complete the *next* command | `_tryResolveBuffer` | The pending helper flushes the adapter when it gives up after a timeout. |
| `7F 19 78` followed by `59 02` in one buffer: the scan checks the NRC first and drops the answer | `readChassisDtcs`, audit Additions #9 | Pending frames are stripped before the existing parse runs. |
| Mode 03 core window is 3 s; a genuine ELM ≥ 2.1 / STN waits ~5 s internally on a pending | `_readDtcsMinTimeout` | Core window becomes the 5 s pending window. |
| `43 01 33 00 00 00 00` is genuinely ambiguous without the protocol: CAN = count 1 + `P3300`; K-line = `P0133` + padding | `_looksLikeCountByte` | The new decoders take the framing from `ATDPN`. CAN keeps the count byte; legacy (K-line) has none. K-line stays gated. |
| `DtcCode.isPending` is never set; `UdsDtcRecord.statusByte` is parsed then dropped | `vehicle_data.dart`, `readChassisDtcs` | `DtcCode` gains an optional link to its `FaultRecord` and the raw status byte. |
| The screen's 5 s auto-scan calls `readEngineDtcs` | `dtc_screen.dart` | Extras must not run every 5 s: they run on the first answered read, a manual read, a changed code set, or when older than 2 min. |

## Design

New files (all pure Dart unless stated):

- `lib/models/fault_record.dart` — **A1** `FaultRecord`, `FaultStatus` (nullable flags), `DtcFormat`, `ReadSource`,
  `FaultSystem`; adapters from Mode 03/07/0A codes and from `UdsDtcRecord`; `mergeEngineRecords`.
- `lib/services/fault_decoders.dart` — **A2** `UdsStatusByte` (bits + derived labels), `FailureType` table (EN/HI,
  28 entries only), typed decoders `decodeObdDtcReply`, `decodeUds19Reply`, `decodeMilStatus`, `decodeRpm`,
  `decodeModuleVoltage`, `decodeVinReply`, `decodeCalibrationIds`. Never throw; typed `…Unparseable` /
  `…Truncated` results.
- `lib/services/response_pending.dart` — **A3** one helper `sendWithPendingHandling` + pending-frame detection.
  Named constants: 5 s per attempt, 20 s overall, 300 ms retry delay.
- `lib/services/engine_report.dart` — **A4–A6** `EngineReport`, `ExtraRead<T>` (value / unsupported / no answer /
  skipped / cancelled), `MilStatus`, `EngineState`, `VoltageReading` + level thresholds, `Vin` (masked
  `toString`), `FaultReadTiming` (all timing constants, injectable for tests), the 15 s budget.
- `lib/models` link: `DtcCode.record` and `DtcCode.statusByte` (optional, additive).

Changes to existing files:

- `obd_pids.dart`: a public `reassembleFrames()` exposing the existing tokenizer/ISO-TP reassembly with truncation and
  odd-nibble flags (additive fields only); `DtcParseResult.codesByEcu` (additive).
- `engine_dtc_read.dart`: `EngineNoAnswerReason.moduleBusy`; `ObdSession.adapterPassesPending`, `vin`,
  `calibrationIds`; `classifyEngineDtcReply` takes an optional count-byte mode from the protocol.
- `obd_service.dart`: core 03 through the pending helper; extras job after the core result (cancel path, budget,
  yields the link); ABS reader: `19 02` and `03` requests through the pending helper (sweep order, addresses,
  recovery, memory untouched) and status/FTB bytes copied onto `DtcCode`; mode 09 replies masked in the in-memory
  wire ring.
- `dtc_screen.dart`: small labels only — status chips on cards, failure-type row on ABS cards, low-voltage banner,
  "may be false" on U-codes, lamp chip, count-mismatch note, engine-running refusal line. Clear button, dialog and
  snackbar untouched.
- `app_strings.dart`: new EN + HI keys.

Tests (new): `fault_record_test`, `fault_decoders_test` (all A2 vectors), `fault_decoder_fuzz_test` (≥ 10,000
inputs), `response_pending_test` (pure helper + both adapter personalities through the real service, engine and
ABS), `engine_extras_test` (07/0A merge, unsupported, 0101 mismatch, core-first, cancel, budget), `vin_test`,
`voltage_engine_state_test`, `replay_fixtures_test` (every fixture), `phase1a_scenarios_test` (3, 8, 11, 12, 14,
17). Support: `test/support/engine_sim.dart` gains UDS modules and pending personalities;
`test/support/replay_transport.dart`; fixtures in `test/fixtures/replay/` with a README.

## Order of work

1. A2 decoders + fuzz (pure) → 2. A1 record + adapters → 3. A3 helper (pure) → sim personalities → service wiring
(core 03, ABS) → 4. A4/A5/A6 extras job → 5. screen labels + strings → 6. A7 replay + fixtures → 7. A8 scenarios +
`PHASE1A_SCENARIOS.md` → 8. A9 full suite, analyze, `flutter build apk --debug`.

## Risks and how they are contained

- Extras interleaving with Clear/ABS/freeze frame → cooperative yield inside `_waitForLinkIdle`, capped wait; tested.
- Existing tests that count wire commands → the legacy `readDtcs()` wrapper stays core-only (no extras).
- Real-time tests getting slow → `FaultReadTiming` is injectable; one test keeps the real constants to prove the 3 s
  → 5 s core window matters.

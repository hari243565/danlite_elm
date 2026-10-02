# Phase A-4 plan — context reads (freeze frame, lamp and clear distances, emission self-checks) and the small fixes

Branch `feat/fault-a4` from `main` @ `d607f8b` (Phase 1B is on main). Worktree `../danlite_elm_a4`.
Baseline: **567 tests pass**; `flutter analyze` **7 issues** (the known ones in `dashboard_screen`, `fuel_screen`,
`hud_screen`, `realtime_screen`). The owner's folder had one modified file before this phase
(`ios/Runner/GeneratedPluginRegistrant.m`, diff SHA-256 `87646cfb…0cd`); it is left alone and re-hashed at the end.

## Facts from reading the code (they shape the design)

| Fact | Where | Consequence |
|---|---|---|
| **There is no Readiness screen.** The keys `readiness` / `emissionReadiness` exist in `app_strings.dart` (and the dead ARB system) but nothing in `lib/` uses them. The brief says "extend the existing Readiness screen". | grep over `lib/` | C3 builds the readiness view new, as one section of the Freeze Frame sheet. Reported to the owner. |
| **The fault card has no "Show details" control.** | `_HazardCard` in `dtc_screen.dart` | A new collapsed-by-default details block is added to engine cards; nothing is read until the rider taps it. |
| The existing Freeze Frame sheet calls `ObdService.fetchFreezeFrame()`, which returns `null` on the first `TIMEOUT` → the sheet prints "No Freeze Data Available" for a silent bike. It also never reads the support list, reads only 5 PIDs, and never tells "no snapshot stored" (PID 02 = 0000) from "not supported". | `obd_service.dart` ~2764, `_FreezeFrameSheet` | Replaced by a typed read (C1). `fetchFreezeFrame`, `FreezeFrameData` and the `noFreezeData` text are removed. |
| The automatic extras job (`_runEngineExtras`) runs after every answered core read. The brief says these reads are **on demand**. | `obd_service.dart` ~1764 | The new reads are a **separate job** that is never started by a scan. They use the same engine-job slot as the silent Clear check, so Clear Codes, the ABS scan and a manual read hand-over exactly as they do for the extras (`_waitForLinkIdle` → `_yieldEngineExtras`), and Clear itself is not edited. |
| Clear Codes, the ABS scan and the legacy freeze-frame call take the poll lock (`_pollLockDepth`) but not the engine-job slot, and `_waitForLinkIdle` does not wait for them. | `obd_service.dart` | The new job refuses to start (and says "not read") whenever the poll lock is already held by another foreground operation after the engine job has been waited for. Proven by a test that holds the lock like Clear does. |
| `_lastClearOutcome` is assigned at the end of every Clear Codes path (success, refusal, not cleared…). | `clearDtcs`, ~2007 | The field becomes a property whose **setter** bumps a "clear generation". Clear's own code is byte-identical; context results remember the generation they were read in and are not shown after a Clear. A snapshot from before an erase is never shown as current. |
| `decodeMilStatus`, `decodeRpm` … use `_decodeServicePid`, which already handles silence, `NO DATA`, negative responses, response-pending lines, odd hex, truncation and multi-module replies. It returns "every module's data". | `fault_decoders.dart` ~705 | The new decoders sit on the same helper (exposed as `decodePidData`). Mode 02 is `42 <pid> <frame> <data>`: the frame byte is checked (must be 0) and stripped. If two modules answer with **different** data, the value is not shown (typed "unreadable"), never guessed. |
| Existing Mode 01 formulas and units live in `ObdParser.parsePid`. | `obd_pids.dart` | Snapshot values are computed by building a validated `41 <pid> …` string and calling `parsePid`, so freeze-frame and live scaling can never drift. Fuel-system status (03) has no existing decoder and gets its own. |
| `HistoryRecorder` saves engine reads from the outside; the Clear record is `kind = clear_check`, stored but not listed; `list()` hides it unless `includeInternal`. | `scan_history.dart`, `clear_record.dart` | S2 lists clear-check records in History as a plain row (time only) whose **detail** carries the neutral sentences. They stay out of Share (unchanged). The clear time is stored (`attempted_at` inside the existing `pre_clear_json`) so the sentence shows when Clear was attempted, not when the silent re-read ran. **No schema change.** |
| `_clearOutcomeMessage` uses `context.tr`, which is `context.watch` — illegal outside `build`; in debug the Provider assertion throws before `showSnackBar`. Release strips the assertion. | `dtc_screen.dart` ~277, memory note | S3: that one line reads the language with `context.read` instead. The Phase 1B guard test that pins this function byte-for-byte to `main` is narrowed to allow exactly this one-line difference (and nothing else). |
| `AppLocalizations` / `l10n/*.arb` are not imported anywhere in `lib/`. | grep | S1 touches the `hi` map of `app_strings.dart` only. The ARB files are listed, not edited. |

## Design

### Pure Dart (no Flutter)

`lib/services/engine_context.dart` (new):

- `FreezeFrameResult` sealed: `FreezeFrameAnswered(snapshot)`, `FreezeFrameNoSnapshot`, `FreezeFrameUnsupported`,
  `FreezeFrameNoAnswer(reason)`, `FreezeFrameLinkLost`, `FreezeFrameRefused(nrc)`, plus `FreezeFrameGated` (K-line stays
  off; "we did not ask" is not "the bike did not answer"). Every variant carries the time.
- `FreezeFrameSnapshot`: trigger code, `values` (in the fixed order), optional fuel-system status, `unreadPids`
  (supported but no usable answer — shown as "some values could not be read", never as absent), and
  `supportListUnreadable`.
- Counters: `ContextCounters` with `ExtraRead<CounterValue>` per counter (value / unsupported / no answer / skipped /
  cancelled — the type Phase 1A already uses for extras). `CounterValue(value, max)`; `atLeast` when `value >= max`
  (65,535 for the two-byte counters; 255 for warm-ups, which is one byte).
- Readiness: `ReadinessReport` with `Monitor` × `MonitorState {complete, notComplete, notSupported, notApplicable}`.
- Decoders (all in `fault_decoders.dart`'s style: never throw, typed results): `decodeFreezeFrameTrigger` (PID 02;
  `0000` ⇒ no snapshot), `decodeSupportedPids` (mode 01 and 02), `decodeFreezeFrameValue(pid, …)`,
  `decodeContextCounter(counter, …)`, `decodeReadiness` (its own pure function with test vectors),
  `decodeFuelSystemStatus`.

### Service (`obd_service.dart`)

- `readEngineContext({parts, isCancelled})`: ONE job, never started by a scan. Order: PID 01 01 (lamp + readiness bytes,
  one request) → counters 21, 31, 4D, 4E, 30 → snapshot (02 02, then support masks 02 00 / 02 40, then the fixed
  PID set). Each request goes through the Phase 1A pending helper with an own window; budget 20 s
  (`FaultReadTiming.contextReadBudget`); the first request of a group that gets no answer ends that group (a silent bike
  costs one window, not twelve). It stops at the next safe point on cancel, on disconnect, or when another operation
  asks for the link. It does not enable CAN headers and changes no adapter setting, so nothing needs restoring.
- Results are cached with the connection they were read on and the clear generation, and are shown for 2 minutes
  (`kContextFreshness`) with their "Read at" time.
- `engineExtrasInFlight` is true while the job runs, so the screen's 5-second auto-read pauses for the (bounded) job; a
  rider's manual read, Clear Codes and the ABS scan hand-over exactly as they do for the extras.
- `fetchFreezeFrame` / `FreezeFrameData` removed.

### Screens (`dtc_screen.dart`)

- Engine fault cards: collapsed "Show details" → on tap reads (or reuses fresh results) and shows the snapshot section
  (trigger code, values with units, "Read at {time}"; "this snapshot belongs to {code}" when it is another code's) and the
  counters. Unsupported items are not drawn. No answer / refused / link lost get their own text and a Retry.
- Freeze Frame sheet: the same snapshot + counters, plus the **Emission self-checks** section (the new readiness view).
- History detail: the Clear record sentences (S2). Clear Codes screen: unchanged apart from the one S3 line.

## Strings

English + Hindi only (brief). S4 list verbatim; the few extra keys the brief did not list (fuel-system status values,
trims/pressure labels, "other fault's snapshot", partial, refused, not-applicable, hide details) are written in the same
style sheet and flagged for the owner's record in the final report.

## Order of work (failing test first, each)

1. S1 Hindi spellings → 2. S3 debug Clear message → 3. S2 History detail → 4. C1–C3 pure decoders + fuzz →
5. service job over the simulator (all outcomes, 29-bit, pending, silence, cancel, Clear exclusion, K-line gate) →
6. screens (card, sheet, readiness) → 7. replay fixtures + scenarios 3, 13, 14 + `PHASE_A4_SCENARIOS.md` →
8. full suite, analyze, `flutter build apk --debug`.

## Risks and how they are contained

- **A stale or foreign context value** (snapshot from before a Clear, from another connection, for a different code):
  generation + connection check + age cap + "belongs to {code}" line, each tested.
- **A timeout shown as "none"**: every variant is its own type; the screen test asserts the no-answer text never equals
  the no-snapshot text, and the old `noFreezeData` key is gone.
- **Lamp distance with the lamp off** (PID 21 is 0 then; "lamp on for 0 km" would be false): lamp lines are shown only
  when the lamp is not known to be off and the value is above zero.
- **Delay to the core read**: separate job, never chained to a scan; a rider's manual read or Clear preempts it; tested
  that the core stored-code read result is available before any context command is sent.

# Phase 1B — scenario status

Scenario numbers and definitions are those of `chore/fault-audit:docs/faults/SCENARIO_COVERAGE.md`. "Before" is
`main` @ `6490606` (Phase 1A); "after" is branch `feat/fault-phase1b`. Proven with simulators, the real bundled pack
and tests — **not on a real bike**.

| # | Scenario | Before (6490606) | After (Phase 1B) | Proving test |
|---|---|---|---|---|
| 15 | Clear refused or ineffective | **PARTLY (owner rule)** — six outcomes classified internally, one success message shown, and nothing kept: after a refused clear the old codes stayed listed under "cleared successfully" with no record anywhere | **RECORDED** — the rider still sees exactly the same dialog, message, colour and timing (source compared byte for byte with `main`). Around it, an internal record: the last answered read (≤ 60 s old) as the pre-clear snapshot, the service's own outcome (`refused`, `notCleared`, …), and ONE silent stored-code re-read after the message → `codes_returned` / `cleared_verified` / `could_not_verify`. Stored in history, not listed and not shared (owner decision pending) | `phase1b_scenarios_test.dart` "Scenario 15 …"; `phase1b_screens_test.dart` group "B9 …" (3 outcomes, refused, byte-identical source) |
| 18 | Language missing for a code | **PARTLY** — Hindi or English, English fallback not marked; 22 of 23 languages never localised | **HANDLED for the store** — Hindi is a separate row a later pack fills in with no code change; the resolver picks the level first, then the language field by field; anything shown in English says so ("Showing English…" / "Some of this text is shown in English"). Specificity beats language. Other languages: English with the same note | "Scenario 18 …"; `fault_resolver_test.dart` group "language"; `phase1b_screens_test.dart` "[hi] …" (2 tests) |
| 19 | Offline with old data vs newer data | **NOT HANDLED** — everything compiled in, no versioning | **PARTLY (by design for this phase)** — a versioned, hashed baseline pack ships in the APK and is imported on first start (and whenever the bundled version is newer); lookup and every resolution work with no adapter and no network. Newer data: the import path, versioning, revocation and signature check exist and are tested, but every downloaded pack is refused until the production key is set and downloading is built (Phase 3) | "Scenario 19 …"; `kb_store_test.dart`; `scan_history_test.dart` "B4 startup import" |
| 20 | Unknown or wrong model | **PARTLY** — ABS honest; engine P1xxx already blocked by Phase 0 | **HANDLED** — one resolver for every code: unknown make or model identifies nothing; a manufacturer-defined code never gets a generic meaning; an identified ABS platform owns its code space (no generic C0035 on a Classic 350 ABS read); a Bosch raw value is a module number, never an SAE meaning; a Honda blink pattern on another make is raw only; the same number on two Royal Enfield platforms keeps two meanings | "Scenario 20 …"; `fault_resolver_test.dart` groups "never another make's meaning", "L4 generic" |

## What still needs a real bike or a decision

- Scenario 15: whether the record should be shown to the rider (History) — owner decision.
- Scenario 19: the pack-signing key pair and the download path (Phase 3).
- The seed is DRAFT, AI-authored content; every card says so ("Draft: not yet independently reviewed").

# Fault-code system audit — what exists today

- **Scope:** read-only audit of the Danlite ELM fault-code capability, as a basis for redesign.
- **Baseline:** `main` @ `71e2783` (2026-09-30), audited in worktree `../danlite_elm_faults` on branch
  `chore/fault-audit`. No source, asset, test, configuration or migration file was changed.
- **Companion documents:** `FAULT_ASSET_INVENTORY.md` (counts, Hindi, coverage), `SCENARIO_COVERAGE.md` (21
  scenarios), `REUSE_MAP.md` (component status).
- **Field guide:** `FAULT_CODES_FIELD_GUIDE_AND_DESIGN_DIRECTION.md` is **not present** in the repository or in any
  commit, so section J checks the brief's own factual statements instead.
- **Tests:** 7 test files, 167 declared tests, **193 executed, all passed** (parameterised tests expand). They could
  not run inside the worktree because `pubspec.yaml` lists the gitignored `.env` as an asset; they were run from a
  `git archive` copy outside the repository with a blank placeholder `.env`.
- **Evidence convention:** `path:line` at commit `71e2783`. **UNKNOWN** where it could not be established.
  **PLAUSIBLE** marks a defect read from the code but not reproduced.

---

## A. Acquisition

### A1. Bluetooth transport

- **Classic Bluetooth serial (SPP/RFCOMM) only**, through a hand-written Android platform channel
  (`android/app/src/main/kotlin/BluetoothSppPlugin.kt`, UUID `00001101-…` at line 25; secure socket → insecure socket
  → reflective `createRfcommSocket(1)` fallback at `:322-351`). No Bluetooth package from pub.dev.
- **BLE: not supported.** No BLE package in `pubspec.yaml`, no GATT code. BLE-only adapters cannot connect.
- **Wi-Fi:** TCP socket to `192.168.0.10:35000` by default (`obd_service.dart:357-406`), configurable in settings.
- **iOS:** the Bluetooth channel is registered only in `MainActivity.kt:9-11`; there is no iOS implementation, so on
  iOS only Wi-Fi adapters could work.
- **Permissions** (`bluetooth_classic_service.dart:96-141`, `AndroidManifest.xml`):

  | Android | Runtime request | Manifest |
  |---|---|---|
  | API ≥ 31 (12+) | `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN` (`neverForLocation`) | also declares `BLUETOOTH_ADVERTISE` (never used) |
  | API < 31 | `ACCESS_FINE_LOCATION` (when-in-use) | `BLUETOOTH`, `BLUETOOTH_ADMIN` capped at `maxSdkVersion=30` |
  | If `device_info_plus` fails | treated as API 31 (`:85-94`) | |

  Fine/coarse location are declared for all API levels (comment says also for trip logging).

### A2. Adapter initialisation sequence

`_runInitSequence` (`obd_service.dart:630-667`), retried up to 3× with command timeouts 2 s, 4 s, 6 s
(`:602-628`):

| # | Command | Line | Must succeed? |
|---|---|---|---|
| 1 | `ATZ` (after 300 ms), then 500 ms wait | 635-636 | no |
| 2 | `ATE0` | 638-639 | **yes** |
| 3 | `ATL0` | 641 | no |
| 4 | `ATS0` | 642 | no |
| 5 | `ATH0` | 643 | no |
| 6 | `ATSP0` — **automatic protocol** | 645-646 | **yes** |
| 7 | `ATAT1` (adaptive timing) | 648 | no |
| 8 | `ATST32` (~200 ms) | 650 | no |
| 9 | `0100`, up to 2× with 300 ms gap | 653-657 | **no — init succeeds even if the ECU never answers** |
| 10 | `ATDPN` | 659-660 | no — **printed to the debug log and discarded** |

Per engine DTC read (`readDtcs`, `:1129-1198`): `ATS1`, `ATH1`, `ATST7D` (~500 ms), `03`, optionally a second `03`
on count mismatch, then `ATST32`, `ATH0`, `ATS0`.

Per chassis scan (`readChassisDtcs`, `:1394-1709`): `ATS1`, `ATH1`, `ATST7D`, `ATDPN`; per candidate `[ATCP18]`,
`ATSH…`, `ATCRA…`, `ATFCSH…`, `ATFCSD300000`, `ATFCSM1`, `1902FF`, `[03]`; afterwards `ATAR`, `ATCRA`, and the
**entire init sequence again** (including `ATZ`).

**Protocol selection:** always automatic. The detected protocol is used in exactly one place — to decide whether to
add the 29-bit ABS candidate (`:1721-1729`, digits 7 or 9).

### A3. Protocol coverage

| Protocol | Exercised? | Evidence |
|---|---|---|
| ISO 15765-4 CAN 11-bit 500k (6) / 250k (8) | Yes — the only protocols the simulators report (`ATDPN` → `6`) and the only ones the parser, flow control and chassis addressing were built for | tests |
| ISO 15765-4 CAN 29-bit (7/9) | Partly — one extended ABS candidate (`18DA28F1`), tested with a simulator reporting `7` | `chassis_modules.dart:369-379` |
| ISO 14230-4 KWP fast init (5) / 5-baud (4) | Only if `ATSP0` finds it. No K-line-specific code: no K-line header handling, no `ATIIA`, no wake-up/keep-alive tuning (`ATSW`/`ATWM`), no init-timing allowance | — |
| ISO 9141-2 (3) | Same as above | — |
| SAE J1850 (1/2) | Same; irrelevant to motorcycles | — |

**On a K-line-only bike:** the engine path depends on `ATSP0` succeeding within the 2–6 s init windows; a slow
5-baud init can outlast them (UNKNOWN — no K-line simulator or transcript). If it does connect, Mode 03 replies are
**mis-decoded** by a heuristic built for CAN (confirmed at parser level, Additions #8). The ABS scan sends 3-digit `ATSH`
values and CAN-only `ATFCSH`/`ATCRA`; a K-line bus will reject or ignore them, and the rider is told **"Adapter
cannot address the ABS module"** — blaming the adapter for what is a bus-type limit.

### A4. Adapter identification and capability

- **No identification commands are sent**: no `ATI`, `AT@1`, `STI`, `STDI`, `ATPPS` (repo-wide search: 0 hits).
  The `ATZ` banner (e.g. `ELM327 v1.5`) is not parsed.
- **No STN-specific commands.**
- **Timing-based inference only, ABS scan only:** `ChassisTiming.classify` (`chassis_modules.dart:495-546`) labels
  the adapter `timingSuggestsLimited` when ≥ 70% of ≥ 4 negative probes return in < 50 ms or never return; the UI
  then shows "This adapter may not be able to reach the ABS module" (suggests an STN11xx adapter). Never used on the
  engine path.

### A5. Module discovery

- **Engine:** functional addressing only (adapter default, 0x7DF on CAN). With `ATH1` on during reads, the parser
  groups replies by ECU header and reassembles ISO-TP per ECU (`obd_pids.dart:660-672`), so several responders are
  decoded and merged into one list. No physical addressing to the engine, no enumeration of which ECUs answered.
- **ABS/chassis:** an ordered sweep of 15 candidates (`chassis_modules.dart`): 2 "core" (7B0→7B8, 760→768), 2 VAG
  +0x6A (713→77D, 762→7CC), 10 swept +8 slots (7A0…7D0), 1 × 29-bit (18DA28F1→18DAF128, only on protocol 7/9).
  0x7E0–0x7E7 and 0x7DF excluded on purpose. Per candidate: header, receive filter, flow control (`ATFCSH`,
  `ATFCSD300000`, `ATFCSM1`), then `19 02 FF` (plus `03` on the two core and 713). First positive reply wins; the
  address is remembered per make+model on the phone (`chassis_address_memory.dart`) and tried first next time.
  Budget 60 s; abort after 3 consecutive timeouts (protected candidates exempt).
- **Multiple responders to one broadcast:** handled for Mode 04 (per-line judgement, `obd_service.dart:1963-2008`)
  and grouped for Mode 03. For ABS, `ATCRA` filters to one responder; if `ATCRA` is unsupported it reads unfiltered
  and relies on header grouping (`:1514-1519`).

### A6. Negative responses

| Where | What is parsed |
|---|---|
| Live PIDs | Mode byte `7F` → value discarded (`obd_pids.dart:370`) |
| Mode 04 clear | `7F 04` per line; refused only if every responder refused (`obd_service.dart:1963-2061`) |
| UDS `19 02` | `7F 19 <NRC>` → NRC stored and logged as hex; scan moves to the next request/candidate (`obd_pids.dart:907-916`, `obd_service.dart:1604-1610`) |
| Mode 03 | a `7F 03` reply has no `43` line, so `_isUsableDtcResponse` rejects it and the **previous** list is kept (empty on a fresh session → "No Fault Codes Found") |

**0x78 (response pending), 0x22, 0x31, 0x33, 0x11, 0x12 are not handled distinctly** — all are "refused". Diagnostic
session control (0x10), tester present (0x3E) and security access (0x27): **never used**.

### A7. Timeouts, retries, link health, serialisation

- Command timeouts: base 2 s (`:294-296`); DTC read 3 s (`:345`); clear 4 s (`:318`); chassis 5 s (`:352`); Wi-Fi
  connect 10 s (`:286`); pairing 30 s (Kotlin `:233`).
- Link health: one classifier (`_classifyReply`, `:706-729`): `DISCONNECTED`/`ERROR` = link failure; any reply,
  even empty = answered; `TIMEOUT` = link failure only after 6 consecutive timeouts (`:239`) or > 6 s since the last
  reply (`:247`). Clear carries a 15 s proof-of-life credit (`:325`).
- Recovery (`_recoverAdapter`, `:759-802`): bare CR ×2 → `ATZ` + full init → otherwise drop with "Adapter stopped
  responding. Unplug it, wait 5 seconds, plug it back in and reconnect." Poll loop allows 3 recoveries (`:943-946`).
- Serialisation: one outstanding command per transport (single `Completer`, `:835-911`); a counted poll lock
  (`:309-314`) held by DTC read, clear, freeze frame and ABS scan; `_waitForLinkIdle` waits for an in-flight PID
  (`:1911-1918`); `_dtcReadInFlight` and `_chassisScanInFlight` guards.
- Framing: Dart owns `>` detection for both transports (`:476-505`); stray frames with no pending command are discarded.
- **Adapter disconnect mid-scan:** the Bluetooth stream's `onError`/`onDone` or the `BluetoothClassicService`
  listener calls `_handleTransportDrop` (`:573-586`): pending command completes as `DISCONNECTED`, polling stops,
  status "Bluetooth link lost". The ABS scan returns `linkUnavailable` only if the link was down at the start; a
  drop mid-sweep surfaces as timeouts, then the scan ends in whatever state it reached. Code lists are **not**
  cleared on a drop (Scenario 16).

---

## B. Read paths

### B1. Services sent

| Service | Sub-function / PID | Where | When |
|---|---|---|---|
| 01 | 00 | init `obd_service.dart:654` | connect |
| 01 | 0C 0D 05 0F 11 04 2F 0A 10 0B 0E 42 06 07 1F (15 PIDs) | poll loop `:927-989` | continuously, 100 ms apart |
| 02 | 02 00, 0C 00, 0D 00, 05 00, 04 00 (frame 00 only) | `fetchFreezeFrame` `:1838-1907` | Freeze Frame button |
| 03 | — | `readDtcs` `:1152`; chassis probes (core + 713) | every 5 s on Engine tab; ABS scan |
| 04 | — | `clearDtcs` `:1239` | Clear Codes |
| 19 | 02, status mask FF | `ChassisModuleProfiles.udsReadDtcByStatusMask` | ABS scan |
| AT RV | — | `:1013` | when PID 42 is unusable |
| **Not sent** | 01 01 (MIL/count), 05, 06, **07**, 08, **09** (VIN/CALID/ECU name), **0A**; UDS 0x10, 0x11, **0x14**, 0x22, 0x27, 0x3E, 0x19 01/04/06/0A | — | — |

`ObdPids.pendingDtcs = '07'` and `vehicleInfo = '0902'` are declared (`obd_pids.dart:200-201`) and never used.

### B2. Counts, lamp, status, freeze frames, pending/permanent

- DTC count and MIL (PID 01 01): **not read**.
- UDS status byte: parsed; bit 3 → `isConfirmed` → "Unconfirmed" chip on ABS cards; bit 0 getter exists
  (`obd_pids.dart:993`) and is unused; no other bits.
- Failure-type byte: parsed and stored on `DtcCode.failureTypeByte`; **never displayed**.
- Freeze frames: Mode 02 frame 00, five PIDs (trigger DTC, RPM, speed, coolant, load). UDS `19 04`: not used.
- Pending (07) and permanent (0A): **not read**. The Mode 03 parser already accepts `47`/`4A` service bytes
  (`obd_pids.dart:629`), so reading them is a small change.

### B3. Vehicle information

VIN is a free-text field on the vehicle profile only (`vehicle_provider.dart:15`), shown as "VIN: …" on the profile
card. It is never read from the vehicle (09 02 unused), never decoded (no WMI table), and never used for make/model.
Calibration IDs, ECU names: not read.

### B4. Multi-frame and truncated responses

ISO-TP single/first/consecutive frame handling, sequence-gap → stop (truncate), declared-length trim, a
concatenated-single-line unwrapper, and ELM `0:`/`1:` numbered-line format (`obd_pids.dart:748-817`). A reported
count ≠ decoded count triggers one re-read and the better result is kept (`obd_service.dart:1163-1173`). Partial
UDS records at the end are dropped (`while cursor + 4 <= length`). Any result that fails the usability check is
silently replaced by the **previous** list (Scenario 16).

---

## C. Decoding

### C1. Decoders

| Decoder | Location | Accepts | Rejects |
|---|---|---|---|
| Two-byte SAE (`decodeDtcPair`) | `obd_pids.dart:683-694` | any byte pair → `[PCBU][0-3][0-F]{3}` | `00 00` |
| Mode 03/07/0A payload (`parseDetailed`) | `obd_pids.dart:652-681`, `819-847` | service bytes `43`, `47`, `4A`; optional count byte (auto-detected) | noise lines (27 markers incl. `NO DATA`, `SEARCHING`, `?`, `OK`) |
| UDS three-byte (`parseUdsDtcDetailed`) | `obd_pids.dart:880-968` | `59 02 <availMask> [b0 b1 ftb status]…`; dedupe on code+FTB | sub-function other than `02`; all-zero padding records |
| Hex-H manual notation (`deriveSaeCode`) | `chassis_dtc_dictionary.dart:1031-1037` | `^[0-9A-F]{4}H$` → SAE via `decodeDtcPair` | anything else (blink keys can never match) |
| SAE → raw module value (`rawModuleValue/Label`) | `chassis_dtc_dictionary.dart:1086-1107` | 5-char SAE → `0xNNNN` (Bosch display) | non-SAE strings |
| Blink entries | `chassis_dtc_dictionary.dart` Honda table + `honda_blink_reference_screen.dart` | table lookup by `"L-S"` picked in the UI | **No decoder**: there is no electrical path; the rider counts flashes |
| Freeze-frame DTC (`parseFreezeFrameDtc`) | `obd_pids.dart:585-599` | `42 02 00 b1 b2` | anything else |
| Hindi raw-master ingestion (`parseRawDictionary`) | `dtc_service.dart:256-292` | build-time only; not called at runtime | — |

### C2. Normalisation, dedupe, ordering, mismatch

- Parser dedupes by code (Mode 03) or code+FTB (UDS).
- **Engine read keeps only P codes** (`obd_service.dart:1175`: `parsed.powertrainCodes`). C/B/U codes reported by
  the engine ECU are silently discarded. Verified by running the shipped parser: an engine `U0100`
  (`7E8 04 43 01 C1 00`) gives `powertrainCodes = []`; engine + ABS both answering the functional `03` gives
  `allCodes = [P0133, C1058]` but only `P0133` reaches the screen.
- K-line replies are mis-decoded by the count-byte heuristic — see Additions #8.
- Screen `_sanitize` (engine only, `dtc_screen.dart:224-237`): trims, upper-cases, regex `^[PCBU][0-9A-F]{4}$`,
  dedupe, sort by severity (critical → unknown). ABS list is shown in module order, unsanitised.
- Count mismatch: one retry (B4). Multi-ECU counts are summed (`obd_pids.dart:849-853`).

### C3. The fault object today

`DtcCode` (`lib/models/vehicle_data.dart:102-155`): `code`, `description`, `possibleCause`, `severity`
(`critical|high|medium|low|unknown`), `action`, `isPending` (never true), `module` (`'engine'|'chassis'`),
`component`, `query`, `remedy`, `failureTypeByte`, `isConfirmed` (default true). No timestamp, no module address,
no protocol, no raw status byte, no provenance, no language. `FreezeFrameData` is separate and not linked to a code.

---

## D. Knowledge assets

Full detail and all counts: `FAULT_ASSET_INVENTORY.md`. Summary:

- **D1:** 31 English engine entries with cause/action (`DtcDatabase`); 999 Hindi engine descriptions
  (`DtcDictionaryHi`, P only); 1,709 English + 1,709 Hindi engine descriptions (`dtc_translations.json`, P only);
  ABS: 19 Classic 350, 19 Bullet EFI (hex-H), 20 Honda blink, 1 Bosch shared (aliased to 4 makes), each with an
  identical Hindi parallel. The translations JSON holds **en and hi only** — it does not feed other languages.
  The named raw source `hindi_dtcs_raw.txt` and generator are **not present**.
- **D2 — trace of P0198** (not in the 31-entry table):
  1. `03` reply, e.g. `7E8 04 43 01 01 98` → `ObdParser.parseDetailed` → `P0198` in `powertrainCodes`.
  2. `_dtcInfo` → `DtcDatabase.lookup` miss → `description: ''`, `possibleCause: ''`, `severity: 'unknown'`,
     `action: ''` (`dtc_descriptions.dart:203-210`).
  3. Screen: `_HazardCard._localizedDescription` → `DtcLocalizations.description('P0198', lang, englishFallback: '')`.
  4. English (and every language except Hindi): English fallback empty → **JSON `en`**: "Engine Oil Temperature
     Sensor High Voltage". Hindi: `DtcDictionaryHi` hit → `इंर्न ऑयल िापमान सेंसर उच्च वोल्टेर्` (corrupted); the clean
     JSON Hindi (`इंजन ऑयल टेम्परेचर सेंसर हाई वोल्टेज`) is never reached.
  5. Severity chip "⚪ Unknown" in grey; sorted last; not counted in the CRITICAL chip.
  - **Severity when an entry is absent:** always `'unknown'` — from the `DtcDatabase.lookup` default (engine) or
    `entry?.severity ?? 'unknown'` (ABS, `obd_service.dart:1801`). 1,682 of 1,713 English-described engine codes
    therefore always show "Unknown" severity.
- **D3:** 13.4% of OBDex's 9,533 generic codes have app English; 0.3% have cause/action; whole ranges
  P0A–P0F, P28/P2A–P2E and nearly all B/C/U are empty; 436 P1 codes carry fixed meanings.
- **D4:** Hindi engine dictionary: 88.3% of entries and 26.6% of tokens flagged; 99.1% contain a token absent from
  every clean Hindi asset. All other Hindi assets: 0 flagged. Not reversibly repairable; clean text already exists.
- **D5:** No licence or permission recorded for any engine asset; two of them name Torque Pro as their source.
- **D6:** 993 of 999 Hindi overlaps differ and the corrupted one wins; 19 of 27 English overlaps differ and
  `DtcDatabase` wins; no duplicate keys.
- **D7:** 313 KB JSON decoded on the UI isolate before `runApp` (`main.dart:71`); not suitable for tens of
  thousands of entries without redesign.

---

## E. Presentation

### E1. Screens and states

Reached from the dashboard tile and the home screen (`route: '/dtc'`, `app.dart:119`). One screen, two segments
(`dtc_screen.dart:305-372`): **Engine** (`moduleEngine`) and **ABS / Chassis** (`moduleAbs`). Freeze Frame icon in
the app bar (enabled when connected).

| Area | State | What the rider reads (English) |
|---|---|---|
| Any | Not connected | "ADAPTER NOT CONNECTED" (hard-coded) + "Connect adapter to read fault codes" |
| Engine | Connected, no read finished yet | "Scanning for fault codes…" / "Live diagnostic scan in progress — codes will appear here automatically." (both hard-coded) |
| Engine | Reading | button "Reading…" with spinner |
| Engine | Read finished, list empty (**includes a silent ECU**) | "No Fault Codes Found" / "Your vehicle has no stored DTCs. Great news! 🎉" |
| Engine | Codes | summary chips "N CODES", "N CRITICAL" (critical+high), "LIVE SCAN · Ns ago" (hard-coded), cards |
| ABS | CBS model | gate "This vehicle uses CBS, not ABS" + "Scan anyway" |
| ABS | Honda blink model | gate "This Honda's ABS is read by blink code, not over Bluetooth" + "Open blink code reference" + "My Honda is a 2024 or newer OBD2B model" |
| ABS | Notices above results | "Set your vehicle make" / "No ABS dictionary for this make yet" / "Set your vehicle model" (+ list of recognised models) / "Limited data for this make" (Bosch) |
| ABS | Idle | "ABS not scanned yet" |
| ABS | Clean | "No ABS fault codes" / "The ABS module answered and reported no stored faults." |
| ABS | No module | "No reply from the ABS module" (+ "Adapter response timing looked normal during this scan." when timing was genuine) |
| ABS | Timing suspicious | "This adapter may not be able to reach the ABS module" |
| ABS | Addressing refused | "Adapter cannot address the ABS module" |
| ABS | Link unavailable | "Connection Failed" / "Connect adapter to read fault codes" |
| ABS | Every empty state | optional "Remembered address: …", and a collapsible "Scan details" log (English only) |
| Freeze frame | loading / none / data | spinner / "No Freeze Data Available" / Trigger Code, RPM, Speed, Coolant, Eng. Load |

### E2. What a scan persists

Nothing. Engine and ABS lists, freeze frame and the 200-line wire log are memory-only (`obd_service.dart:136-158`,
`214-226`). `exportWireLog()` exists and is never called. The only fault-related persistence is the learned ABS
address per make+model (SharedPreferences `chassis_learned_addresses_v1`). The only "share" is copy-code-to-clipboard
on each card (`dtc_screen.dart:1285-1297`). No history, export, share sheet or snapshot.

### E3. Live auto-scan timer

`Timer.periodic(5 s)` while the screen is mounted (`dtc_screen.dart:65`, `103`), plus one read after first frame.
Skipped while the ABS segment is selected or a read is in flight. Each cycle takes the poll lock and sends at least
7 commands (`ATS1 ATH1 ATST7D 03 ATST32 ATH0 ATS0`), each with a 3 s window, so live data pauses for roughly the
duration of every cycle. The timer keeps running while the app is backgrounded as long as the route is on the stack
(no lifecycle handling found).

### E4. Clear Codes

Engine segment only; button disabled when the list is empty. Dialog: "Clear All Fault Codes?" / "This will erase all
stored DTCs and turn off the Check Engine light." / Cancel / Clear Codes. Then Mode 04 with the outcome
classification described in A6/A7. **By the owner's deliberate rule** the rider always sees a green snackbar
"Codes cleared successfully ✓" (`clearOutcomeMessageKey`, `dtc_screen.dart:45-55`; enforced by tests in
`clear_codes_connection_health_test.dart`). The list is re-read only when the service returned `true`. ABS codes
cannot be cleared (no UDS 0x14). Recorded, not judged.

### E5. Severity, cause, remedy, freeze frame, lamp; typed lookup

- Severity: coloured chip + side bar; text from `app_strings` (`severityCritical…Unknown`). Only 30 engine codes
  have a non-unknown severity; ABS entries are all `critical` by Danlite's choice (comment
  `chassis_dtc_dictionary.dart:76-83`).
- **Cause and action (engine): loaded into `DtcCode` but never rendered.** The `possibleCause` and
  `recommendedAction` translation keys exist in 11 languages and are unused.
- ABS cards render Component, Query, Remedy, a raw module code (Bosch) and "MEANING NOT VERIFIED"/"Unconfirmed" chips.
- Freeze frame: separate bottom sheet, one frame, not linked to the card.
- Lamp/MIL status: not read, not shown.
- **Typed-code lookup without hardware: not present** for DTCs. Only the Honda blink-pattern reference works offline.

### E6. Languages

23 selectable (`settings_provider.dart:27-51`): en, hi, bn, te, mr, ta, gu, kn, ml, or, pa, as, ur, sa, kok, ks, sd,
mni, brx, doi, mai, sat, ne (ur/ks/sd RTL). `tr()` falls back silently to English, then to the raw key
(`app_strings.dart:49-52`).

Fault-screen strings (82 keys used by `dtc_screen.dart` + blink screen), measured through `AppStrings.get`
(a key counts as localised if its value differs from English):

| Localised | Languages |
|---|---|
| 82/82 | hi |
| 25/82 | bn, te, mr, ta, gu, kn, ml, pa, ne |
| 5/82 | ur |
| 4/82 | or |
| 1/82 | as, sa, kok, ks, sd, mni, brx, doi, mai, sat |

Plus hard-coded English in the screen: "ADAPTER NOT CONNECTED", "CODES", "CRITICAL", "LIVE SCAN", "just now",
"Ns ago", "Scanning for fault codes…", "Live diagnostic scan in progress…", "<code> copied", and every ABS scan-log
line. Fault **descriptions**: English and Hindi only; category headers in 10 languages. A missing translation shows
English with no marker.

### E7. Domain coverage

| Domain | Reachable today? | How |
|---|---|---|
| Engine | Yes, P codes only | Mode 03 functional, every 5 s |
| ABS / chassis | Yes, on demand | UDS 19 02 FF physical sweep (15 addresses) |
| ABS on Honda blink models | Reference only | manual flash counting + lookup screen |
| Network (U) | Only as ABS-reported U29xx (Classic 350) | engine-reported U codes dropped |
| Body, transmission, cluster, immobiliser, tyre pressure, charging, SRS, TPMS | **No** | — |

---

## F. Backend and reuse

### F1. Reusable signing

The app verifies Ed25519 with `package:cryptography` against a compiled-in raw 32-byte public key
(`entitlement_service.dart:218-222`); the server signs with a PKCS#8 key from `ED25519_PRIVATE_KEY`
(`supabase/functions/entitlement`). **It cannot verify an arbitrary data pack as written:** `_verifyPayload`
(`:632-675`) hard-codes the fields and the canonical string `sub|lic|sid|did|iat|exp`. The primitive is reusable;
a pack verifier needs its own canonical form (e.g. `pack-id|version|sha256(payload)|issued|expires`), a hash over
the pack bytes, and **a separate key pair** (sharing the licence key across purposes weakens both). Key rotation
today requires an app release (comment in `entitlement_public_key.dart`); a pack key should carry a key id.

### F2. Supabase and admin portal

- Tables (14): activation_requests, activation_tokens, admin_otp_requests, admin_users, audit_log, consent_records,
  devices, intl_order_attempts, licences, orders, payments, profiles, sessions, webhook_events. **None about faults.**
- Storage buckets: **none** (`supabase/config.toml:120-121` has the example commented out).
- Edge Functions (17): admin-audit-log, admin-force-signout, admin-grant-licence, admin-list-payments,
  admin-list-users, admin-overview, admin-request-otp, admin-revoke-licence, admin-user-detail, admin-verify-otp,
  claim-session, create-order, entitlement, razorpay-webhook, send-activation, sign-out-devices, verify-activation.
- Admin portal (`admin/`, Next.js 16, `proxy.ts`): pages login, mission-control, users, users/[id], payments,
  audit-log. Access = email in `admin_users` (no role column) checked by `_shared/admin_guard.ts`. A review queue
  can be added as new pages + tables, but roles would have to be introduced.

### F3. Remote-config / content-update mechanism

**None.** Configuration comes from the bundled `.env` (`app_config.dart`); the app's only Supabase reads are
`profiles` and `licences` (`account_screen.dart:181-186`) and the entitlement function. No feature flags, no content
download, no asset versioning.

### F4. Telemetry and Sentry

- No code sends fault data deliberately: `ErrorReportingService.reportError` is called only from
  `auth_provider.dart` and `entitlement_service.dart`.
- **But every adapter command and reply is `debugPrint`ed** (`_logWire`, `obd_service.dart:218-224`, plus
  `readDtcs`/clear/scan debug lines). In the pinned `sentry_flutter 9.27.0`, the debug-print integration records
  prints as breadcrumbs when not in debug mode, and `enablePrintBreadcrumbs` defaults to `true`
  (`sentry-9.27.0/lib/src/sentry_options.dart:332`, `sentry_flutter-9.27.0/.../debug_print_integration.dart:22-23`);
  the app does not turn it off. So in release builds, raw fault-code bytes can ride along on any Sentry error event.
- Redaction (`_scrub`, `error_reporting_service.dart:150-161`) applies to the `context` map only, and only removes
  email- and phone-shaped strings. Breadcrumbs are not scrubbed. `sendDefaultPii = false`,
  `maxRequestBodySize = never`, 5% traces.
- The legal inventory reaches the same conclusion independently (`chore/legal-drafts` `DATA_INVENTORY.md` D-46,
  D-50; `OPEN_QUESTIONS.md` Q-33 asks whether crash reports carrying vehicle diagnostic lines need consent).

### F5. Consent state (from `chore/legal-drafts` @ `8f9ba5f`, unmerged)

`consent_records` exists with **0 rows and no writer**; signup has no consent checkbox; there is no withdrawal
mechanism (`DATA_INVENTORY.md` D-09 and lines 215-219). Vehicle profiles incl. VIN stay on the phone but may be
copied by Android Auto Backup (D-42). An opt-in unknown-code report therefore needs consent capture built first.

---

## G. Simulation and tests

### G1. Simulators (all extend `BluetoothClassicService`, all answer every AT command with `OK`)

| Simulator | File | Can produce | Cannot produce |
|---|---|---|---|
| `FakeElm` | `clear_codes_connection_health_test.dart:32` | Single ECU on CAN 11-bit (`ATDPN`→6); Mode 03 one code / none; Mode 04 bare prompt, `44`, `7F 04 xx`, extra `7F 04 11` responders, header-prefixed frames; ack latency; post-erase silence; dead link; erase that does not take; 6 supported PIDs | ignition-off (`UNABLE TO CONNECT`, `SEARCHING`), `NO DATA`, K-line, multi-frame Mode 03, `?` to AT commands, NRC 0x78, voltage |
| `FakeChassisElm` | `chassis_dtc_test.dart:1002` | Addressing state; wedged adapter (ignores 2 CRs → forces `ATZ` recovery); engine `03` on broadcast only | any ABS module answer |
| `ProgrammableElm` | `chassis_addressing_coverage_test.dart:677` | ABS answering at a chosen header with one 59 02 record (single frame); `NO DATA` with configurable delay (clone vs genuine timing); protocol 6 or 7 | multi-frame over the wire, NRCs, `?` rejections |
| `AnsweringElm` | `chassis_multi_make_test.dart:726` | ABS at a chosen header returning chosen DTC bytes | same as above |

Multi-frame UDS decoding is tested at parser level only (string fixtures), not through a simulator.

### G2. Tests

| File | Declared tests | Covers |
|---|---|---|
| `chassis_dtc_test.dart` | 57 | UDS parse, platform resolution, Classic 350 / Bullet EFI tables, hex-H aliasing, Hindi parity for chassis, scan sequence, addressing re-applied after recovery |
| `chassis_multi_make_test.dart` | 39 | Honda blink/OBD2B/CBS, Bosch makes, 0x5200, blink screen widget, registry invariants |
| `chassis_addressing_coverage_test.dart` | 36 | candidate list invariants, sweep order, 29-bit gating, timing classifier, learned-address memory |
| `clear_codes_connection_health_test.dart` | 25 | clear outcomes, link classification, the fixed success message in every language |
| `entitlement_token_binding_test.dart` | 6 | licence token binding |
| `billing_domain_test.dart` | 2 | billing host |
| `framework_locale_fallback_test.dart` | 2 | drawer per language |
| **Total** | **167 declared, 193 executed, 193 passed** | |

Two extra parser checks were run by the auditor in the scratch copy only (not committed): K-line/multi-ECU Mode 03
shapes and a `7F 19 78` + `59 02` buffer — results in C2 and Additions #8–#9.

**Not covered:** engine description resolution with the JSON loaded (`DtcLocalizations.init` is never called in
tests); Hindi quality (the only engine-Hindi test asserts `isNotEmpty`, `chassis_dtc_test.dart:208-215`); multi-ECU
Mode 03; ignition-off / silent ECU; stale-result behaviour; the 5 s auto-scan; the engine fault card widget;
freeze frame; K-line; NRC 0x78/0x22/0x33; `?` rejection of `ATSH`; Wi-Fi transport; permission paths.

### G3. Real-vehicle transcripts

**None in the repository.** No capture files, no recorded `[WIRE]` logs, no fixtures taken from a real bike; every
reply in the tests is hand-written. (`exportWireLog()` exists but is not wired to any UI, so riders cannot send one.)

---

## H. Vehicle profile

- Fields (`vehicle_provider.dart:5-33`): name, make, model (free text), year, fuelType (petrol, diesel, hybrid,
  electric, cng, lpg), engineSizeL, powerBhp, weightKg, vin (optional free text), notes. Stored as JSON strings in
  SharedPreferences. Defaults are car-like (1.6 L, 120 bhp, 1,400 kg).
- **No make or model lists** in the form (free text with hints "e.g. Maruti Suzuki" / "e.g. Swift VXi" —
  `vehicle_profile_screen.dart:284-285`).
- Normalisation (chassis only): lower-case, strip non-alphanumerics, exact alias match
  (`chassis_dtc_dictionary.dart:170-192`, `556-570`); 16 make aliases → 6 manufacturers; model aliases per platform;
  manufacturer fallback for Honda and the four Bosch makes; Royal Enfield requires an exact model.
- Drives: ABS probe order (manufacturer; empty map today, so always generic), ABS dictionary (platform), capability
  gates, learned-address key. **Does not affect engine codes at all.**
- Blank or wrong: blank make → "Set your vehicle make"; the **default profile** is make "Unknown", model "Vehicle"
  (`vehicle_provider.dart:88-97`), which resolves as an unsupported make ("No ABS dictionary for this make yet")
  rather than prompting to set it. A wrong Honda model can route a real ABS bike to the CBS gate (one-tap bypass).
- VIN/WMI decoding: **none**.

---

## J. Checking the field guide

The field guide is not in the repository, so nothing in it could be checked. Statements in the brief itself that the
code or data contradicts or qualifies:

| Brief statement | Finding |
|---|---|
| "the translations JSON asset that feeds other languages" | **Contradicted.** It contains only `en` and `hi`. Every other language gets English descriptions. |
| "dtc_dictionary_hi.dart … generated from hindi_dtcs_raw.txt" | The header says so, but the raw file and generator are absent from the repo and all history — **not reproducible**. |
| "the 31-entry DtcDatabase" | Confirmed: 31 (27 P, 1 B, 1 C, 2 U). |
| The four Hindi corruption examples | Confirmed, and quantified (D4); all four are among the most frequent broken tokens. |
| "blink entries" listed among decoders | Qualified: blink codes are a lookup table picked in the UI; there is no decoder because nothing is read electronically. |
| Code comment "999 entries" for the JSON (`dtc_service.dart:53`) | **Stale**: 1,709 per language since `f27573a`. |
| Memory note "10 languages get full coverage" | Not true for the fault screens: only Hindi is complete (82/82); nine others 25/82; thirteen ≤ 5/82. |

---

## Additions beyond the brief

Ranked by impact. Each is evidence-backed; PLAUSIBLE items were read from code but not reproduced.

1. **False all-clear when the ECU is silent.** Init succeeds without any ECU answer and the engine screen then says
   "No Fault Codes Found … Great news!" for ignition-off, wrong protocol, dead ECU, carburetted or EV bikes
   (Scenario 2). For a diagnostic tool this is the most consequential behaviour in the audit.
2. **Engine-reported C, B and U codes are thrown away** (`obd_service.dart:1175`). A `U0100` or a network fault set
   by the engine ECU never appears; the DtcDatabase entries for B0001, C0035, U0001, U0100 are unreachable.
3. **Cause and action exist for 31 codes but are never shown**, and the translated labels for them are unused.
4. **Corrupted Hindi shadows clean Hindi** for 993 codes because of lookup order (`dtc_service.dart:109-113`).
   Swapping two lines would fix what a Hindi rider sees for those codes today; that is a product decision.
5. **`P1xxx` codes shown with another manufacturer's meaning.** 436 manufacturer-range codes have one fixed English
   text (several are GM terms: "SDM", "Active Banking Control", "Park/Neutral to Drive/Reverse at High RPM"). A
   Royal Enfield or Bajaj `P1xxx` gets that text with no "manufacturer-specific" warning — the exact risk the ABS side
   was carefully designed to avoid.
6. **Diagnostic traffic reaches Sentry** as release-build breadcrumbs (F4), unscrubbed and without consent.
7. **Stale results presented as live.** A timed-out read returns the old list and refreshes "LIVE SCAN · just now";
   lists survive a link drop and reconnect (Scenario 16).
8. **CONFIRMED at parser level — K-line Mode 03 replies decode to wrong codes.** The count-byte heuristic
   (`_looksLikeCountByte`, `obd_pids.dart:839-847`) was built for CAN. K-line replies have no count byte and are
   zero-padded to three codes per frame, so when the first code's high byte is `01` or `02` (every P01xx fuel/air
   sensor code and P02xx injector code) and it is the only code, the heuristic mistakes it for a count and strips it.
   Running the shipped `ObdParser.parseDetailed` (in a scratch copy, not the repo) on hand-built K-line replies:
   `43 01 33 00 00 00 00` (P0133) → **`P3300`**; the same with headers on and a checksum byte, as `readDtcs` actually
   requests (`48 6B 10 43 01 33 00 00 00 00 C0`) → **`P3300, P00C0`**; a two-frame reply meant to carry
   P0133, P0301, P0113, P0234 → **`P3303, P0101, P1343, P0234`**. CAN replies of the same codes decode correctly.
   Whether the target bikes are K-line, and exactly how their adapters format the reply, still needs a real
   transcript — but on K-line this defect shows the rider wrong codes.
9. **CONFIRMED at parser level — a pending response throws away the real answer.** For `7B8 03 7F 19 78` followed
   by `7B8 07 59 02 FF 50 58 00 2F`, the parser returns `negativeResponseCode = 0x78` **and**
   `sawPositiveResponse = true` with `C1058`; `obd_service.dart:1606-1610` checks the NRC first and discards the
   code. Whether a given adapter passes the 0x78 frame through is UNKNOWN.
10. **ABS scan on a K-line bike blames the adapter** ("Adapter cannot address the ABS module"), because CAN-only
    addressing commands are rejected (A3).
11. **JSON load failure is silent.** If `dtc_translations.json` fails to load, 1,682 English descriptions become "—"
    with only a debug print (`dtc_service.dart:66-68`).
12. **Severity is effectively absent for engine codes** (1,682 of 1,713 are "Unknown"), so sorting and the CRITICAL
    chip carry little information.
13. **Freeze frame timeout reads as "No Freeze Data Available"** (`obd_service.dart:1859-1862`) — a link problem is
    reported as an absence of data.
14. **The auto-scan competes with live data** every 5 s and keeps running in the background while the route exists.
15. **No BLE and no iOS Bluetooth.** Whether the adapters riders actually buy are Classic or BLE is UNKNOWN from the
    repo, and matters to reach.
16. **Provenance is unauditable from history**: all asset commits use the placeholder author identity; the Hindi
    generator and source are missing; the JSON's growth from 999 to 1,709 codes has no recorded source.
17. **Safety wording:** the clear dialog promises to "turn off the Check Engine light" (car wording) and the
    unconditional success message (owner's rule) applies even when the ECU refused; combined with no ABS clear and
    no re-read on refusal, a rider can believe a braking or engine fault is gone when it is not. Recorded for the
    owner, not judged.
18. **Default vehicle profile ("Unknown"/"Vehicle", 1.6 L, 1,400 kg)** is car-shaped and suppresses the "set your
    make" prompt.
19. **Tests never load the real engine knowledge assets**, so none of the D4/D6 problems can be caught by CI.
20. **No way to collect real transcripts from the field** (`exportWireLog` unused) — which is also why G3 is empty.

### Questions for the owner

1. May the Torque Pro-derived Hindi dictionary and JSON be kept, redistributed, or used as seed data at all? Is any
   permission on file?
2. Should Hindi prefer the clean loanword register of the JSON (`पोजिशन`, `कंट्रोल`) or a more native register
   (`स्थिति`, `नियंत्रण`)? That decides whether to promote the JSON Hindi or commission new text.
3. How should `P1xxx` (and other manufacturer-range) codes be described when the make has no verified table —
   generic text with a warning, or "manufacturer-specific, not verified"?
4. Should "no reply from the engine" become its own state instead of "No Fault Codes Found"?
5. Does the unconditional clear-success rule still stand once refusals and "codes still present" can be shown
   neutrally?
6. Which bikes are the priority, and which of them are K-line versus CAN? Real transcripts from even three of them
   would retire several UNKNOWN and PLAUSIBLE items above.
7. Should raw OBD traffic stay out of Sentry entirely?
8. Is BLE adapter support in scope?

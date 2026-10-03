# Phase 4B — scenario status

Branch `feat/fault-4b`, cut from `main` @ `15fbde2` (Phase A-4b). Proven with the simulator, hand-written fixtures and
tests — **not on a real bike**. Master plan v1.1 aims touched: **A6** (sections by domain), **A2** (honest reach
guidance), **A3 tier 3** (maker table for older Royal Enfield EFI). Everything is local: no network call, no new
dependency, no change to Clear Codes, the ABS probe/sweep/recovery, the K-line gate, auth, payments or backend.

## B1 — domain sections (views over the codes already found)

Sections: Engine & emissions, Brakes & ABS, Body & instruments, Network, Transmission & riding aids, Other. A card row
sits on the Fault Codes tab above the results (both the Engine and the ABS / Chassis views); an "All" chip resets.
**No new scanning**: a card reports what the engine scan and the ABS scan already established.

| Question | Answer | Proving test |
|---|---|---|
| Which section does a code belong to? | Rule (a) a code the ABS module scan returned is Brakes & ABS, whatever its number; (b) else the resolved knowledge entry's system when it names one; (c) else the code's letter and range | `fault_domain_test.dart` "B1 mapping…" (49 cases), "rule (a)" (5), "rule (b)" (7), "a blink pattern" (1) |
| Ranges | P00xx–P06xx, P1xxx, P20xx–P26xx, P3xxx → Engine & emissions; P07xx–P09xx, P27xx → Transmission & riding aids; C → Brakes & ABS; B → Body; U → Network; everything else → Other | same, every boundary (P0699/P0700, P0999/P0A00, P2699/P2700, P2799/P2800, P0FFF, P1000, P3FFF…) |
| Engine card | Not scanned / Scanning / The bike did not answer / The engine computer is busy / refused / lost contact / connection type not readable yet / No faults / N faults. A list left from an earlier answer is **not** counted once the last read failed | `fault_domain_test.dart` "B1 cards: engine" (10); `fault_sections_screen_test.dart` "B1 cards on the screen" |
| Brakes & ABS card | One state per ABS scan outcome (not scanned, scanning, no reply, busy, adapter cannot address, link lost, no faults, N faults). ABS codes kept from a scan that later lost the link are **not** counted | `fault_domain_test.dart` "B1 cards: Brakes & ABS" (8) |
| Body, Network, Transmission, Other | "Not scanned yet" until the engine scan or the ABS scan **answers**; then "None found" / "N found", with the caption "Based on the engine and ABS scans." A scan that did not answer never turns them into "None found" | `fault_domain_test.dart` "B1 cards: Body, Network…" (7); screen test "bike did not answer…" |
| Filter | Tapping a card lists the codes of that section from **both** scans (engine list + ABS list), from either module view; tapping it again or "All" resets; an empty section shows the card's own state sentence. Card count always equals the filtered list length | `fault_domain_test.dart` "B1 the list behind a card" (4); `fault_sections_screen_test.dart` "B1 filter" (7) |
| Existing behaviour | Module selector, Read Codes, Clear Codes (still keyed on the engine Mode 03 list), live scan and the 5-second re-read are untouched | `fault_sections_screen_test.dart` "the filter keeps the module selector, Read Codes and Clear Codes working"; the 111 earlier screen tests |
| Strings | 19 new keys in English and Hindi, placeholders match, Latin digits, no half-translations | `fault_sections_screen_test.dart` "B1 strings" (3) |

### Decisions and findings (B1)

- **Rule (b) cannot change anything today.** The knowledge pack's `system` field is validated to equal the code's
  letter (`kb_validator.dart`) and is not stored on `KbEntry`; the resolver only exposes a system for a structure-only
  answer, and that is the letter again. So (b) is wired (the screen passes the resolved system in) but is a no-op
  until a pack carries a finer domain. **Powertrain deliberately does not decide**: it is the letter for both Engine
  and Transmission, so letting it win over the number would file P0700 under Engine and make the transmission rule
  unreachable. Chassis, body and network do decide.
- **Range reading.** The brief writes ranges as P0000–P0699. The last two characters of a group are read as any hex
  digit, so P069A–P06FF (computer circuits, e.g. P06A0) are Engine, not Other. P0A00 and above (hybrid ranges) and
  P2800 and above are Other, as the brief says "anything else".
- **A C code in the engine computer's own list** is filed under Brakes & ABS by its letter. The ABS module was not
  scanned, so the card shows the count and says "Reported by the engine scan."; it does not say the ABS module was
  checked.
- **Engine card, "No faults" with other codes on screen.** If the engine answered and every code in its list belongs
  to another section, the Engine card says "No faults" and the other card shows the count.
- The cards appear only when connected; disconnected, nothing could have been scanned.

## B2 — entry points

"Look up a code" and "Scan history" were reachable only through two unlabelled app-bar icons. They are now labelled
buttons on the tab itself: in a row above the section cards when connected, and in place of the single lookup button
when no adapter is connected (neither needs one). The same two existing screens open; no logic changed, and the
app-bar icons are kept.

| Question | Answer | Proving test |
|---|---|---|
| Reachable, labelled, connected and not | Both buttons present, labelled in the rider's language, each opens the existing screen | `fault_entry_points_test.dart` "B2 …" (8 tests: connected × disconnected × lookup/history, Hindi labels, old icon still works) |

## B3 — adapter help ("Which adapter works best?")

A static screen, English and Hindi, six short points: what an ELM327 adapter reads (engine codes, with an OBD-II
socket and ignition ON), why other modules such as ABS need an adapter that can address them (many cheap clones
cannot; STN11xx-based adapters document it), the links the app uses today (classic Bluetooth and Wi-Fi), the
bike-specific cable from a 2, 3, 4 or 6-pin socket to the 16-pin adapter, older bikes with a connection type the app
cannot read yet, and bikes that can only be read by blink code or a dealer tool. No brand, price, link or promise.

| Question | Answer | Proving test |
|---|---|---|
| Says only what is known | Each statement matches the brief; exactly 14 texts on the screen (title, intro, six headings, six bodies) | `adapter_help_test.dart` "B3 the screen says only what is known" (4) |
| No promotion | No URL, price, currency, brand name or "recommend" in either language | `adapter_help_test.dart` "no brand, price, link or promise" |
| Reached from the help icon | App-bar `?` icon, connected or not, with a spoken label | `adapter_help_test.dart` "B3 how it is reached" (3) |
| Reached from "The bike did not answer" | Link under that state only — **not** for a busy module, a refusal, a lost link or an answer | `adapter_help_test.dart` "when the link is offered" (every `EngineNoAnswerReason`), "links to it" |
| Reached from "No reply from the ABS module" | Link under no-reply and under "adapter cannot address the ABS module"; not for a clean scan, an ABS fault list, busy, link lost or never scanned | `adapter_help_test.dart` (every `ChassisScanOutcome`) |
| Strings | 14 keys in English and Hindi, translated, Latin digits; the Hindi spellings are covered by `hindi_consistency_test.dart` | `adapter_help_test.dart` "English and Hindi both exist…" |

Decision: the link also appears under "The adapter cannot address the ABS module" (not named in the brief) because
that is the same adapter-reach problem in its plainest form. Easy to remove: `absOutcomeOffersAdapterHelp`.

## B4 — Royal Enfield older-EFI blink reference (manual look-up, NOT a scan)

Source: Royal Enfield Bullet Classic EFI service manual (221 pp), pages 163 to 164, read in full by the owner's
assistant on 2026-10-01. Applies **only** to the Bullet Classic EFI and Bullet Electra EFI of the UCE era; the screen
says so, in a bordered card before the procedure, and says it does NOT apply to the BS6 Classic 350, Meteor or Hunter.
A small "Blink-code references" list (button on the Fault Codes tab, connected or not) leads to this screen and to
the existing Honda one; a Royal Enfield vehicle profile sees the Royal Enfield entry first, anyone else sees Honda first
(as before). The Honda screen, its table and the ABS blink gate that opens it are untouched.

| Question | Answer | Proving test |
|---|---|---|
| The table is the manual's | Ten rows, the owner's order: 0-6 P0120, 0-9 P0105, 1-1 P0195, 1-7 P0130, 4-5 P0135 (run, under-perform); 1-5 P1630, 3-3 P0201, 3-7 P0351, 4-1 P0230, 6-6 P0335 (crank, will not start). P1630 alone is labelled "Manufacturer code" | `royal_enfield_blink_test.dart` "the table is the manual's table, row for row" (14) |
| Every row, through the screen | Entering long then short shows the pattern, the dealer-tool code, the meaning and the effect | "each row, entered as long then short counts…" |
| No match | All 90 unlisted patterns of 0..9 × 0..9 say "No code in the table for this pattern" and send the rider to a Royal Enfield service centre; long/short order matters (6-0 ≠ 0-6) | "B4 no match and input limits" (4), "a pattern not in the table…" |
| Input limits | Pickers offer exactly 0 to 9 for each count; the lookup rejects anything outside 0..9; a half-entered pattern is not a pattern | "the pickers offer exactly 0 to 9", "only one count chosen", "counts outside 0..9 never match" |
| Nothing pre-selected | The screen opens with a prompt, not a "match" the rider never entered | "nothing is chosen at first" |
| States the gaps | The manual pages read give no blink duration and no way to clear codes; the screen says so | "the procedure is the manual's, and the gaps are stated" |
| Provenance | The existing "From the manufacturer's service manual" label, plus a source line naming the manual and pages 163 to 164 | "says what it is, which bikes, how, and what it does not know" (en, hi) |
| Not a scan | No button that reads anything; the existing "MANUAL REFERENCE — NOT A LIVE SCAN" badge first | "there is no scan or read button anywhere on it" |
| The list and its order | Royal Enfield profile (spelling-tolerant: "ROYAL-ENFIELD", "RE") → Royal Enfield first; Honda, other makes, no profile → Honda first | "B4 the list of references" (5) |
| Reachable from the tab | "Blink-code references" button, connected and disconnected | "B4 reachable from the Fault Codes tab" (2) |
| Strings | 30 keys in English and Hindi, translated, Latin digits, Latin-script names kept; other languages fall back to English | "B4 strings" (3) |

Decisions and notes (B4):

- The table reads "long first, short second" exactly as the owner wrote it (0,6 = zero long, six short).
- P0195 is shown as the manual states it ("engine oil temperature sensor circuit"), even though other sources title
  that code differently; the app follows the manual.
- Hindi for part names is the workshop loanword (थ्रॉटल, मैनिफ़ोल्ड, इग्निशन कॉइल…); all of it is **proposed**, not the
  owner's own wording, and is listed in the final report.

## B5 — fuel-system status 0 ("Engine off") only when the engine is known to be off

The fuel-system status in the freeze-frame snapshot says "Engine off" for the value 0 (A-4b F2). That was shown even
beside a snapshot whose own engine speed was 2,400 RPM. Now the row is shown only when the snapshot's own engine speed
is exactly 0 or, when the snapshot has no engine speed, the engine is otherwise known to be off (the live engine
report). A running engine or an unknown state hides the whole row. Every other fuel status is untouched.

| Snapshot's own RPM | Engine otherwise (live) | "Engine off" row |
|---|---|---|
| 0 | anything (unknown, running, off, none) | shown (the snapshot describes the same moment as the status) |
| greater than 0 (including a cranking 150) | anything | hidden |
| absent | off | shown |
| absent | running, unknown, none | hidden |

Proving test: `fuel_status_engine_off_test.dart` — the 32 rpm × state combinations, the two precedence cases, every other
status unchanged, a status that reports nothing still hidden, and the real screen in English and Hindi (rpm 0 shown;
rpm 800 hidden with the RPM row kept; absent + unknown hidden; absent + off shown; absent + running hidden).

Note: only the exact reading 0 counts as off for the snapshot's own speed, as the brief says — a cranking 150 RPM
hides the row rather than claiming the engine was off.

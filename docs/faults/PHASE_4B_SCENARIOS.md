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

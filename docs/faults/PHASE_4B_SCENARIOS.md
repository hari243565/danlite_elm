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

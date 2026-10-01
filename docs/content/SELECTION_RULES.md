# Selection rules (Step 1), revised 2026-10-01

Source: OBDex generic list, commit `bc58b0eb7273226a1aabae98e956b70b8362bda1` (9,533 codes, CC0-1.0 data).
Output: `data/content/relevance_ranking.csv` (code, rank, tier, reason_tags, anchor, honda_family, title_obdex, title_standard, title_status, write_ok).
Reproduce with `python3 data/content/select_codes.py /tmp/obdex data/content/relevance_ranking.csv` (it also rewrites `title_suspects.csv`).

## Result

**387 codes selected** (target in the brief was about 1,200). The rules do not produce more, and the list was not padded. 365 can be written; **22 are held back because their title cannot be trusted** (see "Titles" below).

| Family | Selected | Note |
|---|---:|---|
| P0 powertrain | 247 | |
| P2 powertrain | 54 | ride-by-wire, fuel trim, ignition coil A/B, charging |
| C0 chassis | 57 | wheel speed and ABS pump/module/relay/lamp only |
| U0 network | 29 | CAN bus, ECU, ABS, cluster, immobiliser, software, invalid data |
| P3, U3, B0 | 0 | P3 is mixed hybrid/other; U3 is hybrid/fuel cell; B0 is airbag and car comfort |

## What changed on 2026-10-01 (version 3)

1. **Selection bug fixed.** The ECU power relay range stopped at P0688 and missed P0689 and P0690. It now runs P0685 to P0690, which also pulls in P068A and P068B (relay switched off too early or too late). Total 383 to 387.
2. **Titles checked by the owner (public sources, 2026-10-01) are applied** from `title_overrides.csv` (P0139, P0626, P0686, P0687, P0688, U0075, U0076, U0077). `title_standard` is the title in force: the override if there is one, otherwise the OBDex title. Entries record `standard_title_en` and `derived_from.title_basis` (override or obdex). Also confirmed by the owner and not suspect: P0685 is "ECM/PCM Power Relay Control Circuit/Open", U0073 is bus A off, U0074 is bus B off.
3. **Re-ranking inside tier 3** by how likely a small Indian bike is to raise the code. The order of reason tags is `TAG_PRIORITY` in `select_codes.py`: throttle, MAP, intake air, engine and oil temperature, O2 sensor and heater, fuel trim, injector, fuel pump, misfire, crankshaft, camshaft, ignition coil, knock, vehicle speed, neutral, idle, system voltage, starter relay, ECU power relay, sensor supply, control module, immobiliser, CAN, fan, oil pressure, EVAP, secondary air, catalyst, and **ride-by-wire last** (it exists only on bikes with a ride-by-wire throttle). P0638 and P2135 were retagged from `throttle` to `ride_by_wire` for the same reason. Ranks 1 to 40 (the pilot) did not change.
4. **Two new reason tags** so the rubric is not forced to over- or under-warn: `injector_balance` (P0263, P0266) and `ect_warmup` (P0125, P0126, P0128). See RUBRIC.md.
5. **Duplicate-title scan** over all selected codes, comparing each title with the five codes either side in the same family after normalising quotes, slashes, "sensor", "circuit" and spelling (immobilizer/immobiliser). It found P0141 against P0142 (the source gives P0142 the same title; P0142 is outside the selection), P2110 against P2113, U0167 against U0168, plus the pairs the reviewer found. The remaining suspect titles are listed by hand with the reason in `title_suspects.csv`.

## How a code gets in

1. The code is inside a hand-written range for one of the included systems (the list is in `select_codes.py`, one line per system).
2. Its OBDex title does not match the exclusion pattern: bank 2, cylinder 3 or higher, sensor 3, turbo or supercharger, diesel, glow plug, hybrid or HV, transmission or torque converter, A/C, cruise, power steering, EGR, particulate, NOx, reductant, transfer case, 4WD, airbag, SRS, seat belt.
3. It is not in the explicit `DROP` list (second throttle actuator, cold-start strategy codes, brake assist, second barometric sensor, brake pedal feedback).

## Systems included

Throttle position and ride-by-wire; idle control; intake pressure (MAP) and barometric pressure; intake and ambient air temperature; engine coolant and oil temperature; cooling fan; oil pressure; bank 1 O2 sensors (sensor 1 and 2) and heaters; fuel trim; catalyst; injector circuits for cylinders 1 and 2; fuel pump circuits and fuel level; misfire P0300 to P0302 and P0316; crankshaft and camshaft position; ignition coils A and B; knock; evaporative emission; secondary air; vehicle speed, neutral and gear position, clutch switch, brake switch correlation; system voltage, charging, starter relay, ECU power relay, sensor reference supply; control module faults and immobiliser; CAN and bus faults; lost communication with the ECU, ABS, cluster and immobiliser; software and invalid-data codes about those units; ABS wheel speed, pump, module, relay and lamp codes.

## Systems excluded, with reasons

- Diesel, glow plug, particulate, NOx, reductant, EGR: not on Indian BS6 petrol bikes.
- Turbo and boost, hybrid and electric propulsion: out of scope in the brief.
- Bank 2, cylinders 3 and up, sensor 3: a bike has one or two cylinders.
- Automatic transmission (P07xx to P09xx) except gear position inputs P0914 to P0919. P0704 (clutch switch input) was kept because a manual bike with a clutch interlock can raise it; this is a small extension of the brief.
- Mass air flow (P01xx): small bikes use speed-density (MAP plus throttle). Not selected.
- Variable valve timing, camshaft actuators and cam profile codes (P0010 to P0025, P001x, P002x): rare on small bikes. Not selected.
- Fuel rail pressure, pressure regulator and fuel volume codes: small bikes have no fuel pressure sensor. Not selected.
- Wide-band O2 pumping-current codes (P2237 to P2240, P223C, P223E): used on a few bikes only. Not selected; can be added in a later batch.
- Network lost-communication codes for modules a bike does not have (second ECM, injector or fuel-pump control modules, throttle actuator module, starter/generator module, brake system module, glow plug, HVAC and so on). U0105, U0107, U0109, U0115, U0120 and U0129 were removed after the quality-gate sample showed U0115 makes no sense on a single-ECU bike.
- All B0 codes: airbag and comfort body codes are excluded by the brief. Lamp and horn circuit codes were also left out because bikes rarely report them through generic codes.

## Rank order

| Tier | Meaning | Count |
|---|---|---:|
| 1 | The 9 evidence anchors from the Royal Enfield EFI manual, in the order given in the brief | 9 |
| 2 | 31 common circuits spread over powertrain, network and chassis (includes the Honda blink-table sensor families MAP, engine temperature, throttle position, intake air temperature, injector) | 31 |
| 3 | Core codes of every included system | 148 |
| 4 | Extended: less likely on a small bike or a duplicate-style variant (second oxygen sensor responses, wheel speed variants, EVAP pressure sensor, charging terminals, etc.) | 199 |

Within a tier the order follows `TAG_PRIORITY`, then the code. `honda_family` is `yes` for 44 codes in the MAP, engine temperature, throttle position, intake air temperature and injector families (51 before the retagging above).

Batches: ranks 1 to 40 are the pilot (9 anchors, 3 misfire codes, fuel trim, catalyst, the high/low pairs of the throttle, MAP, intake and engine temperature sensors, upstream O2 high/low, speed, voltage, neutral, ECU link, camshaft, idle, ECU/ABS/cluster communication and one wheel speed sensor). **Batch 1 is ranks 41 to 141** (P0121 to U0008): 101 ranks, 100 entries, because P0134 (rank 58) is held back.

## Titles: what is written and what is held back

| Status | Count | Meaning |
|---|---:|---|
| obdex | 354 | OBDex title used as the standard title |
| override | 8 | owner-checked title replaces the OBDex title (`title_overrides.csv`) |
| confirmed | 3 | checked and correct (P0685, U0073, U0074); the OBDex title already matches |
| suspect | 22 | `write_ok = no`: no entry is written; listed in `title_suspects.csv` with the reason |

The 22 held-back codes: P0134 and P0140 ("No Activity / Slow Response" mixes two meanings), P0141 (title shared with P0142), P2110 (shared with P2113), P2230 (same as P2228), U0167 and U0168 (same title, spelling aside), P033F (not a clear standard title), and the wheel-speed titles C0030 to C0034, C0036, C0037, C0038, C003A to C003F, which do not follow the C0035 / C0040 / C0045 / C0050 pattern. C0035 itself, C0040, C0045 and C0050 are kept. A small bike has one CAN bus, so U0075 to U0077 (now bus C, D and E off) will be written as one plain entry each ("a communication bus on the bike has stopped working") with low confidence, in a later batch.

## Known weak spots in the selection

- **Chassis (C0) codes.** Generic C0 codes are four-corner car codes (left front, right rear). A bike has a front and a rear wheel only. They stay at tier 4 (except four at tier 3), every one needs independent review and the rider title never names a car wheel position.
- **Codes that only exist on bikes with the hardware.** P0202, P0264 to P0266 and P0352 need two cylinders (`applies_when`). P0128 and the cooling codes need liquid cooling. P0340 to P0344 need a camshaft sensor; knock, EVAP and secondary air codes depend on the bike. The app should only show them when the bike family allows it.
- **Source titles.** Several OBDex titles disagree with the standard pattern (see `title_suspects.csv`). The source entry text for a code can also describe a different failure from the checked title: the OBDex entry for P0688 describes a sense circuit high fault and the entry for P0687 describes a sense circuit open fault, the reverse of the checked titles. Entries follow the checked title.

# Selection rules (Step 1)

Source: OBDex generic list, commit `bc58b0eb7273226a1aabae98e956b70b8362bda1` (9,533 codes, CC0-1.0 data).
Output: `data/content/relevance_ranking.csv` (code, rank, tier, reason_tags, anchor, honda_family, OBDex title).
Reproduce with `python3 data/content/select_codes.py /tmp/obdex data/content/relevance_ranking.csv`.

## Result

**383 codes selected** (target in the brief was about 1,200). The rules do not produce more, and the list was not padded.

| Family | Selected | Note |
|---|---:|---|
| P0 powertrain | 243 | |
| P2 powertrain | 54 | ride-by-wire, fuel trim, ignition coil A/B, charging |
| C0 chassis | 57 | wheel speed and ABS pump/module/relay/lamp only |
| U0 network | 29 | CAN bus, ECU, ABS, cluster, immobiliser, software, invalid data |
| P3, U3, B0 | 0 | P3 is mixed hybrid/other; U3 is hybrid/fuel cell; B0 is airbag and car comfort |

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
| 3 | Core codes of every included system | 144 |
| 4 | Extended: less likely on a small bike or a duplicate-style variant (second oxygen sensor responses, wheel speed variants, EVAP pressure sensor, charging terminals, etc.) | 199 |

Within a tier the order follows the order of the system list in `select_codes.py`, then the code. `honda_family` is `yes` for 51 codes in the MAP, engine temperature, throttle position, intake air temperature and injector families.

The first 40 ranks are the pilot set. They cover 9 anchors, 3 misfire codes, fuel trim, catalyst, the high/low input pairs of the throttle, MAP, intake and engine temperature sensors, upstream O2 high/low, speed, voltage, neutral, ECU link, camshaft, idle, ECU/ABS/cluster communication and one wheel speed sensor.

## Known weak spots in the selection

- **Chassis (C0) codes.** Generic C0 codes are four-corner car codes (left front, right rear). A bike has a front and a rear wheel only. They are kept at tier 4 (except four at tier 3) and every one will need mechanic review and a maker-specific table to say which wheel is meant.
- **Codes that only exist on bikes with the hardware.** P0202 and P0352 need two cylinders. P0340 needs a camshaft sensor. EVAP pressure and secondary air codes depend on the bike. The app should only show them when the bike family allows it (see "Additions beyond the brief" in the pilot report).
- **Source titles.** Several OBDex titles disagree with the standard pattern. They are listed in `data/content/title_suspects.csv`.

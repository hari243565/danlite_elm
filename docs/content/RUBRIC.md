# Rider action rubric (Step 2), revised 2026-10-02 (schema version 2; owner decisions D1 to D8 of the batch 2 to 4 run are at the end)

| Level | Use when | Rider advice must |
|---|---|---|
| STOP | Typically causes stalling, no start, sudden power loss, fuel leakage or fire risk, or loss of the ability to brake or steer normally; also an active condition that can destroy the engine within minutes (overheating, no oil pressure; rubric gap found by the batch 1 reviewer) | tell the rider to pull over safely, switch off and not keep riding (rules R3, R18) |
| SERVICE_SOON | Can damage the engine or catalyst if ignored, or hurts drivability (misfire, O2 sensor, throttle, fuel trim) | say to get it checked soon and how to ride meanwhile; any stall or no-start wording must be conditional ("if ...") |
| MONITOR | Minor, emissions-only or likely to clear | say it can wait for the next service; no stall or no-start claim |
| INFO | Reserved, test not completed, purely diagnostic | not use "pull over" |

`needs_independent_review` (renamed from `needs_mechanic_review`: there is no mechanic on this project, so independent review means a separate reviewer session plus rider feedback) is true for every STOP, every chassis or braking code, every ABS or wheel-speed code, every low-confidence entry and every entry that mentions a petrol smell. The author may also set it for any other entry that needs a second pair of eyes. The validator enforces the minimum.

## Owner decisions applied (final, 2026-10-01)

- **D1, P0563 system voltage high.** SERVICE_SOON, firm advice with explicit stop triggers (battery hot, swollen or smells of rotten eggs, lights very bright, bulbs keep blowing: stop, switch off and do not ride on; otherwise a short daytime ride to a workshop only). `can_ride_to_workshop` = with_care. The reasoning is in `rider_action_basis`. Review true.
- **D2, U0100.** SERVICE_SOON, two honest cases ("if the engine runs normally, have it checked soon; if it stalls, loses power or will not start, do not keep riding"). No unconditional stall or no-start claim and no scan tool in the text. The same two-case pattern is used for the other "the ECU or its link may be at fault" entries (ECU power relay sense circuit, ECU internal faults that do not threaten the engine, CAN bus).
- **D3, ABS and wheel-speed function loss.** SERVICE_SOON. The advice contains: "Your normal brakes still work, but ABS is off, so a wheel can lock in hard braking." (or a close paraphrase with the three facts and no hedge). STOP only for brake fluid loss or hydraulic pressure loss; no such code is selected. Rider titles never name a car wheel position ("Wheel speed sensor fault (front or rear wheel)"). The validator maps `lost_comm_abs`, `wheel_speed`, `abs_pump`, `abs_module`, `abs_relay` and `abs_lamp` to SERVICE_SOON only (rule R5).
- **D4, `can_ride_to_workshop`.** STOP gives `no`; SERVICE_SOON gives `with_care`, or `yes` when the fault clearly cannot strand the rider (O2 sensor, O2 heater and similar); MONITOR and INFO give `yes`. `can_ride_reason` (max 80 characters) says why. The validator rejects any other combination, so a deviation needs a change to the validator mapping, not just a note.
- **D5, single-cylinder bikes.** `applies_when: {"cylinders_min": 2}` on every code that needs a second cylinder: any standard title with "cylinder 2", "ignition coil B" or "contribution/balance". The validator enforces it.
- **D6, honest labels.** `verification` is `ai_authored_from_standard_title` (structure-only mode) or `ai_authored_adapted`. The word "verified" (or "verification") is rejected in every text field.

## Mapping enforced by the validator (reason tag to allowed levels)

The tags come from `relevance_ranking.csv`. A code with several tags may use any level allowed by any of its tags.

| Tag | Allowed |
|---|---|
| crankshaft | STOP |
| injector, ignition_coil | STOP or SERVICE_SOON (the STOP table, rule R13, decides; changed 2026-10-02) |
| fuel_pump, cam_crank_sync, engine_speed_input, oil_pressure, ecu_power_relay | STOP, SERVICE_SOON |
| camshaft, misfire, injector_balance, throttle, ride_by_wire, twist_grip_sensor, ect, cooling_fan, cooling_system, system_voltage, starter_relay, charging, sensor_reference_supply, control_module, immobiliser, starter_immobiliser, can_bus, lost_comm_engine | SERVICE_SOON, STOP |
| lost_comm_abs, wheel_speed, abs_pump, abs_module, abs_relay, abs_lamp | SERVICE_SOON (D3) |
| idle, map_baro, fuel_trim, knock | SERVICE_SOON |
| o2_sensor, o2_heater, vehicle_speed, brake_switch, neutral_gear, clutch_switch | SERVICE_SOON, MONITOR |
| iat, oil_temp, catalyst, overspeed, secondary_air, software, invalid_data, lost_comm_cluster, ect_warmup | MONITOR, SERVICE_SOON |
| evap, fuel_level, ambient_temp | MONITOR |

New in this revision: `injector_balance` (P0263, P0266: one cylinder not doing its share, a drivability fault, not "no fuel") and `ect_warmup` (P0125, P0126, P0128: engine slow to warm up, an emissions and fuel-use fault) were split out of `injector` and `ect` so they are not forced to STOP or SERVICE_SOON.

Judgement calls inside the mapping (for the reviewer to challenge):

- All fuel pump circuit codes (P0230 to P0233, P0627 to P0629) are STOP: a pump that drops out stops the engine without warning, and a "high" reading is often an open circuit.
- ECU power relay: control circuit open or low (P0685, P0686) is STOP (the ECU can lose power). Control circuit high, the sense circuit codes and the "switched off too early or late" codes are SERVICE_SOON with the two-case advice, because the ECU is powered well enough to store the code.
- ECU internal processor, RAM and ROM faults (P0604 to P0606) are STOP; checksum, programming, keep-alive and general performance faults (P0601 to P0603, P0607) are SERVICE_SOON. This split is the least certain call in batch 1.
- Intermittent crankshaft or fuel pump circuit codes (P0339, P0233) are STOP because the loss is sudden.
- Sensor supply faults (P0641 to P0643) are SERVICE_SOON with the stall condition and `can_ride` with_care.

## Text rules the validator enforces (R1 to R10)

| Rule | What is rejected |
|---|---|
| R1 | Circular advice: "stop if the engine stalls, cuts out or dies" (also in reverse order). If it has stalled the rider has already stopped. Use "if it stalls more than once or will not restart, do not keep riding; have it taken to a workshop". |
| R2 | Assumed hardware in rider text: gauge, tachometer, rev counter, blinking or flashing lamp, scan tool. Allowed only as "if your bike ...". Technician hints may say "scan tool" but not gauge or blinking lamp. |
| R3 | Below STOP: an unconditional claim that the engine will or may stall, cut out or not start (use "if ..."). At STOP: the advice must say pull over or stop and not to keep riding. Applies to meaning, basis, advice and `can_ride_reason`. |
| R4 | Any mention of a petrol or fuel smell must come with "If you smell petrol strongly near the engine or tank, or see fuel dripping, stop and do not ride." and needs_independent_review true. |
| R5 | ABS and wheel-speed codes: brakes work, ABS is off, a wheel can lock (no hedge words), SERVICE_SOON, no "braking is not affected" or "ride as normal". |
| R6 | Low and high codes: the title says "voltage below threshold" or "voltage above threshold" and the meaning says below/low or above/high, not the opposite. Coolant, oil, intake and ambient air temperature sensors: LOW voltage means the engine, oil or air LOOKS HOTTER; HIGH voltage means it LOOKS COLDER. The direction comes from the standard title (override applied). |
| R7 | Car-only parts: EGR, MAF, PCV, transmission fluid, turbo or boost, glow plug, diesel, DPF, power steering, cruise control, A/C. A timing chain cause must say "rare". A catalytic converter may be a cause only for catalyst codes. |
| R8 | A fuse or relay in a cause or hint needs "if fitted" (not required when the code's own standard title names the relay). A hose needs "if hose-fed". |
| R9 | The first 12 words of the meaning contain no workshop phrase (short to ground, open circuit, voltage below threshold, plausibility, internal fault and similar). |
| R10 | No "(listed as", no "bank 2" and no duplicate title across codes in a rider title. |

## Flags

- `mil`: the warning lamp (MIL) normally lights for this code. Chassis and network codes are set false unless the engine unit raises them; false also means "not known to light it".
- `emissions_relevant`: the fault can affect exhaust emissions or fuel control.
- `limp_possible`: the ECU may substitute a default value or limit power. In structure-only mode these three flags are the author's judgement from the code's structure, not copied from OBDex (its flags are generic car values). The independent review noted that nothing checks them; a reviewer should spot-check.

## Confidence

- high: standard generic meaning, not bike-specific.
- medium: meaning is standard but the effect depends on the bike (speed source, neutral interlock, camshaft sensor, knock sensor, network units).
- low: thin or car-oriented source, or the generic code is ambiguous on a bike (serial link, chassis wheel codes, ECU relay sense circuits, ECU internal faults, bus-off codes).

## Wording rules

No absolute words (always, never, guaranteed, definitely, certainly, absolutely). No part numbers, pin numbers, voltages, resistances or cost figures. No brand names. Parts named in an entry must appear in the source entry's title, components or causes (a part found only in the source description gives a validator warning). In structure-only mode this is the check that stops the author inventing parts: 24 of the 100 batch 1 first drafts failed it and were rewritten.


## Owner decisions of the batch 2 to 4 run (final, 2026-10-02)

- **D1** The reviewer's validator rules R12 to R19 are adopted (see below) and the reviewer's 8 defective entries are in `review_regression_cases.json` for good.
- **D2** Downgraded from STOP to SERVICE_SOON with `can_ride_to_workshop` with_care: P0604, P0605, P0606 (the source says the ECU keeps running in reduced power mode) and the cylinder 2 faults P0202, P0264, P0265, P0352. P0232 is downgraded too, because its OBDex description says the pump stays powered when it should be off (reason in `rider_action_basis`). P0336, P0629, P0685 and P0686 stay at STOP with `needs_independent_review` true.
- **D3** Idle faults carry the advice "If it stalls at stops or will not hold idle, ride gently, avoid heavy traffic and have it checked soon." followed by the STALL sentence. P0507 (idle too high) carries its own first sentence about a throttle that does not snap shut. The self-contradicting "avoid traffic and do not keep riding" is gone everywhere (P0506, P0510, P0519 and ten more).
- **D4** One canonical form for each standard sentence: STALL, PETROL, ABS and NETWORK (see GLOSSARY_EN.md, "Fixed sentences"). Bus faults (U0001 to U0010, U0073 to U0077, U0140, U0146) carry NETWORK and `needs_independent_review` true.
- **D5** P068B says the battery may go flat if the ECU stays powered after switch-off (the source description supports it).
- **D6** Hindi-readiness: sentences of at most 25 words, no idioms, glossary terms only (rule R22). One fixed sentence is longer than that on purpose: the owner's D1 BATTERY sentence for P0563 and P2504 (29 words); the validator exempts exactly that sentence.
- **D7** P0633, P0512 and P0513 no longer claim "may not restart" at SERVICE_SOON; the reason now starts with "if it starts, ...".
- **D8** Entries keep schema version 2, the AI-authored labels, and never say "verified".

## STOP table (`data/content/stop_table.csv`, rule R13)

The table is the owner's list of STOP codes. A STOP entry that is not in the table is an error and so is a table code below STOP, so a STOP changes only by an edit of this file. `status` is `owner_confirmed` for the 20 codes of the first 140 entries and `proposed_batch2` or `proposed_batch3` for the 13 added in this run (P0524 oil pressure too low; P2104, P2105, P2111, P2112 ride-by-wire throttle; P2146 injector supply open; P2300 to P2302 ignition coil A; P0320 to P0323 engine speed signal). Their reasons are in the file; the owner confirms or removes each one. After this run STOP is 33 of 329 entries (10 percent).

## Validator rules added on 2026-10-02

| Rule | What it checks |
|---|---|
| R12 | Below STOP: no unconditional "shuts off", "stops running", "will not start", "dies" claim; the "if" must come before the claim and not be "if you like". |
| R13 | The locked STOP table, both ways. |
| R14 | Temperature direction words (hotter, colder) agree with the standard title in every rider field. |
| R15 | ABS and wheel speed entries: no reassurance wording, and the second advice sentence comes from a closed list. |
| R16 | A fuel leak, drip or fumes in rider text needs the PETROL sentence and never "keep riding" or "wipe". |
| R17 | Technician hints may not contain unsafe procedures (bypass, jumper wire, battery lead off while running ...). Rider text may only say "do not bypass". |
| R18 | STOP text must not permit riding and must say "pull over" and "do not keep riding" in one sentence. |
| R19 | A powertrain code with an engine-control tag has `mil` true. |
| R20 | `applies_when` must name the hardware that not every bike has (new keys below). |
| R21 | The canonical sentences (STALL, PETROL, ABS, NETWORK, the idle sentence) word for word where they apply; no variants; bus faults need review true. |
| R22 | Hindi-readiness: sentences of at most 25 words, an idiom blocklist (cut out, drops out, hunt, reduce load, run rich ...), discouraged words (module, harness, loom). |
| T1 | Title agreement (`title_agreement.csv`): a new entry needs AGREE; an entry written before Step T only warns. |

New `applies_when` keys (all `true`): `knock_sensor_fitted`, `camshaft_sensor_fitted`, `oil_temp_sensor_fitted`, `closed_throttle_switch_fitted`, `evap_fitted`, `secondary_air_fitted`, `cooling_fan_fitted`, `oil_pressure_sensor_fitted`, `ambient_temp_sensor_fitted`, `fuel_level_sensor_fitted`, `gear_position_sensor_fitted`, `clutch_switch_fitted`, `downstream_o2_sensor_fitted`, `can_bus_fitted`, besides the existing `cylinders_min`, `liquid_cooled`, `ride_by_wire` and `abs_fitted`. The app has to know which of these a bike family has; otherwise it would show codes the bike cannot raise.

Level mapping change: `injector` and `ignition_coil` now allow STOP and SERVICE_SOON in the tag table, because the STOP table (R13) decides which of them is STOP.

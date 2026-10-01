# English glossary for the seed (preferred forms)

The Hindi pass should translate each preferred form one way every time. The validator rejects the discouraged forms in the right-hand column.

## Failure phrases (shared with the app's failure-type table)

Use exactly these when a title or meaning says how a circuit failed:
short to ground; short to battery supply; open circuit; voltage below threshold; voltage above threshold; current below threshold; current above threshold; resistance above threshold; signal out of range; signal plausibility fault; performance or incorrect operation; stuck; internal fault of the control unit; communication lost.

Generic "circuit malfunction" codes do not say how the circuit failed. Use **circuit fault** for them (for example "Throttle position sensor A: circuit fault") and do not guess a failure type.

| Discouraged | Preferred |
|---|---|
| shorted to ground, short circuit to ground, short to earth | short to ground |
| shorted to supply or power, short to positive | short to battery supply |
| open-circuited, broken circuit | open circuit |
| low voltage, voltage too low, voltage is low | voltage below threshold |
| high voltage, voltage too high, voltage is high | voltage above threshold |
| lost communication, no communication, communication failure or loss | communication lost |
| implausible signal, plausibility error | signal plausibility fault |
| internal module or unit fault | internal fault of the control unit |

## Terms

| Preferred form | Meaning for the translator | Do not use |
|---|---|---|
| bike's computer (ECU) | the engine control unit. Write "bike's computer (ECU)" the first time an entry's meaning mentions it, then "ECU" in the rest of that entry | ECM, PCM, engine control module |
| control unit | any electronic unit on the bike (ECU, ABS unit, cluster) | module (alone), node |
| warning lamp (MIL) | the engine or fault lamp on the cluster | check engine light, CEL, MIL lamp, trouble light |
| fault code | a stored code such as P0120 | DTC |
| scan tool | the tool or app that reads the codes | scanner, OBD tool |
| sensor | a part that measures something and sends a signal | transducer |
| circuit | the sensor or actuator, its wiring and connector as one electrical path | loop |
| wiring | the wires between the unit and the part | cabling, loom |
| connector | the plug where wiring meets a part | coupler, plug (for a plug cap say "spark plug cap" only if the source names it) |
| ground | the return path to the battery negative | earth, earthing |
| supply, battery supply | positive voltage feed | power (alone), plus |
| sensor supply | the reference feed the ECU gives a sensor | 5 V line, VREF |
| signal | the reading the sensor sends back | output |
| range | the span of normal readings | window |
| plausibility | the ECU checks if two readings make sense together | rationality (alone) |
| intermittent | comes and goes | erratic (use "intermittent") |
| threshold | the limit the ECU compares against | limit value |
| stall | the engine stops running by itself | die, cut off |
| cut out | the engine stops or loses power suddenly | quit |
| reduced power mode | the ECU limits power on purpose (the "limp possible" flag) | limp mode, limp-home |
| freeze-frame data | readings saved when the fault was stored | snapshot |
| live data | readings shown while the engine runs | PID data |
| key-on | ignition switched on, engine not running | KOEO |
| intake air leak | unmetered air entering after the throttle (also "vacuum leak" once, in brackets) | false air |
| mixture | the air-fuel mix | A/F ratio |
| too lean / too rich | too little fuel or too much air / too much fuel or too little air | lean condition |
| fuel trim | the ECU's correction to the fuel amount | trim (alone) |
| oxygen (O2) sensor, upstream / downstream | exhaust sensor before / after the catalytic converter | lambda sensor, HO2S, bank 1 sensor 1 (keep bank wording only in the source title) |
| catalytic converter | the exhaust part that cleans exhaust | cat, catalyst (except in a tag) |
| emission system | the group of parts that keep exhaust clean | emissions parts |
| throttle position sensor | measures how far the throttle is open | TPS (only in the glossary) |
| intake manifold pressure (MAP) sensor | measures pressure after the throttle | vacuum sensor |
| engine (coolant) temperature sensor | engine heat sensor; on air-cooled bikes it reads head or oil heat | ECT sensor in the text |
| crankshaft / camshaft position sensor | tells the ECU the engine position | CKP, CMP |
| reluctor ring, tone ring | toothed ring read by a position or wheel speed sensor | pulse wheel, exciter ring |
| ignition coil | makes the spark voltage | coil pack |
| injector | sprays fuel into the intake | nozzle |
| idle air control valve | lets air bypass the throttle at idle | IAC (alone) |
| neutral switch | tells the ECU the gear is in neutral | PNP switch |
| immobiliser | the key-code anti-theft start lock | security module |
| ABS | anti-lock braking system | |
| wheel speed sensor | reads how fast a wheel turns | WSS |
| instrument cluster | the meter and lamp panel | dashboard, IPC |
| CAN bus | the wire network the units use to talk | data bus (alone), network line |
| communication lost | a unit cannot reach another unit | |
| regulator | the part that limits charging voltage (regulator-rectifier on most bikes) | |
| mechanic, technician | "mechanic" for the rider text, "technician" for the technician hints | |
| ride | for the rider advice use "ride", "stop", "pull over" | drive |
| bike | the vehicle (covers scooter and motorcycle) | motorbike, motorcycle |

## Added 2026-10-01 (pilot fixes and batch 1)

### Fixed sentences (translate once and reuse word for word)

| Id | English | Used in |
|---|---|---|
| STALL | If it stalls more than once or will not restart, do not keep riding; have it taken to a workshop. | throttle position sensor codes (P0120 to P0124) and similar |
| TWO-CASE | If the engine runs normally, have it checked soon; if it stalls, loses power or will not start, do not keep riding. | U0100, ECU power relay sense codes, ECU internal faults, CAN bus codes |
| STOP-TAIL | Pull over safely, switch off and do not keep riding; have the bike taken to a workshop. | every STOP entry |
| PETROL | If you smell petrol strongly near the engine or tank, or see fuel dripping, stop and do not ride. | any entry that mentions a petrol smell (rule R4) |
| ABS | Your normal brakes still work, but ABS is off, so a wheel can lock in hard braking. | every ABS and wheel-speed entry (rule R5) |
| BATTERY | If the battery is hot, swollen or smells of rotten eggs, or the lights are very bright or bulbs keep blowing, stop, switch off and do not ride on. | P0563 |
| LATER | Get it checked soon; ride gently and avoid long trips until it is fixed. | MAP sensor codes |

### Hedges (keep the hedge in every language)

| English | Meaning |
|---|---|
| (if fitted) | the part exists only on some bikes; mandatory after a fuse or a relay in a cause or hint |
| (if hose-fed) | the sensor takes its signal through a hose on some bikes only |
| (liquid-cooled bikes) | the cause applies only to bikes with a coolant system |
| (less common) | a real but rare cause |
| if your bike has / shows ... | the rider's bike may not have that display or system; never assume it |

### Terms

| Preferred form | Meaning for the translator | Do not use |
|---|---|---|
| performance or incorrect operation | shared failure phrase for "range/performance" codes: the reading is not plausible for the conditions | range error |
| intermittent circuit fault | the signal drops out or jumps at times | erratic, sporadic |
| slow response | an oxygen sensor that switches too slowly | lag |
| signal stuck lean / stuck rich | an oxygen sensor signal that stays on one value | frozen |
| fuel mixture correction (fuel trim) | the ECU's correction to the fuel amount; the title says it in plain words first | trim (alone) |
| out of balance (cylinder) | one cylinder does not do its share of the work | contribution fault |
| CAN bus (+) wire, plus wire; CAN bus (-) wire, minus wire | the two wires of the bike's data network | CAN high, CAN low |
| safety systems | ABS and similar systems that may switch off when the data network fails; ABS itself is named only in ABS entries | |
| learned settings | values the ECU stores to adjust idle and fuel (keep-alive memory); lost when the battery is disconnected or weak | KAM, adaptations |
| immobiliser (key-code anti-theft start lock) | gloss the first time an entry says immobiliser | security module |
| ECU power relay (if fitted) | the relay that powers the ECU, on bikes that have one | main relay (alone) |
| sensor supply | the shared reference feed the ECU gives its sensors | 5 V line, VREF |
| toothed ring (reluctor ring) on the crankshaft; toothed ring (tone ring) on a wheel | toothed ring read by a position or wheel speed sensor; give the workshop word in brackets once | pulse wheel, exciter ring |
| engine overheating | the engine temperature went above the allowed limit | overtemperature |
| knocking, pinging | harmful metallic pinging from the engine under load | detonation |
| workshop | where the bike is repaired; "mechanic" for the person | garage, service centre |
| pull over | stop safely at the roadside | park up |
| do not keep riding | stop riding now and do not start again until checked | do not drive |
| ECU | write "bike's computer (ECU)" the first time in an entry, then "ECU" | ECM, PCM, engine control module |

Rider-facing text never says "scan tool", "gauge", "tachometer" or a blinking lamp unless it is written "if your bike ..." (rules R1 to R3 in RUBRIC.md). Technician hints may say "scan tool".

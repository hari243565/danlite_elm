"""V5 fixes (2026-10-02): the owner's decisions G4 to G8 applied after the independent review of V4
(docs/content/REVIEW_REPORT_V4_20261002.md). Applied by authored_all.py on top of the V4 fixes and all batches, so the
original authored text stays visible in git history. Every field change is logged by `authored_all.py --log5` in
fix_changes_v5_20261002.csv (code, group, field, old, new, why).

fix(code, group, why, **fields) may be called more than once for a code; the calls are applied in order.
Keys are the authored field names (title, meaning, causes, level, basis, advice, hints, flags, confidence, ride,
applies, review). Entries that are held out (held_v5.py) are fixed too, so a later release is not stale.
"""
from canon import *  # noqa: F401,F403

FIXES = []  # (code, group, why, fields)


def fix(code, group, why, **fields):
    FIXES.append((code, group, why, fields))


# ======================= G4: ride-by-wire levels ===========================================================
# Rule: faults that can leave the throttle unresponsive (actuator motor, module or forced-limited-power faults) are
# STOP; sensor plausibility faults are SERVICE_SOON. P2101 stays SERVICE_SOON with with_care (owner decision).
G4 = "G4"
for _c, _basis, _lead in [
    ("P2100", "ECU may lose control of the throttle",
     "The ECU may switch to reduced power mode, and the throttle may not follow the twist grip."),
    ("P2102", "ECU may lose control of the throttle",
     "The ECU may switch to reduced power mode, and the throttle may not follow the twist grip."),
    ("P2103", "ECU may lose control of the throttle",
     "The ECU may switch to reduced power mode, and the throttle may not follow the twist grip."),
]:
    fix(_c, G4, "G4 owner decision: throttle motor circuit fault can leave the throttle unresponsive, as P2104: STOP",
        level=S, basis=_basis, advice=_lead + " " + STOP_TAIL, ride=(NO, "throttle may not follow the twist grip; arrange transport"))
fix("P2106", G4, "G4 rule check: forced limited power fault is on the owner's STOP list; as P2104",
    level=S, basis="power is limited on purpose",
    advice="The bike may accelerate weakly because power is limited. " + STOP_TAIL,
    ride=(NO, "power is limited on purpose; arrange transport"))
fix("P2107", G4, "G4 rule check: control module fault, the ECU may not control the throttle; as P2104",
    level=S, basis="ECU may not control the throttle",
    advice="The ECU may not control the throttle correctly. " + STOP_TAIL,
    ride=(NO, "the ECU may not control the throttle; arrange transport"))
fix("P2108", G4, "G4 rule check: control module self-test fault, the ECU may not control the throttle; as P2104",
    level=S, basis="ECU may not control the throttle",
    advice="The ECU may not control the throttle correctly. " + STOP_TAIL,
    ride=(NO, "the ECU may not control the throttle; arrange transport"))
fix("P2110", G4, "G4 rule check: forced limited engine speed is a forced-limited-power fault; as P2104",
    level=S, basis="engine speed limited on purpose",
    advice="The engine speed may be limited to a low value. " + STOP_TAIL,
    ride=(NO, "engine speed is limited on purpose; arrange transport"))
fix("P2111", G4, "G4 owner decision: tell the rider how to slow down; confidence medium because Q4 forbids high on braking text",
    advice="Close the throttle, pull in the clutch, use both brakes to slow down, then stop safely and switch off. "
           "Pull over and do not keep riding; have the bike taken to a workshop.",
    confidence=MD)


# ======================= G5: idle entries ==================================================================
# One pair of sentences, nothing that can read as the opposite; the stacked canonical STALL sentence is removed.
G5 = "G5"
for _c in ("P0505", "P0506", "P0508", "P0509", "P050A", "P050D", "P0510", "P0511", "P0518", "P0519"):
    fix(_c, G5, "G5 owner decision: idle pair replaces the stacked IDLE_FIRST + STALL sentences", advice=IDLE_PAIR)
fix("P0507", G5, "G5: the throttle-not-closing stop sentence is mandatory and the advice may have only 2 sentences, so P0507 "
                 "keeps it and carries the second half of the pair instead of the stacked STALL sentence",
    advice="If the throttle does not snap fully shut when you let go, do not ride; have it checked first. " + IDLE_REPEAT)


# ======================= G6: twin wording for the cylinder 1 ignition and injector STOP entries ==============
# Levels stay as they are. One short clause joined to the first sentence (the advice may have only 2 sentences).
G6 = "G6"
for _c in ("P0201", "P0261", "P0262", "P0351", "P2300", "P2301", "P2302"):
    fix(_c, G6, "G6 owner decision: twin wording clause for a cylinder 1 fault (levels unchanged)",
        advice="The engine may misfire, lose power or stop; " + TWIN_CLAUSE + ". " + STOP_TAIL)


# ======================= G7: long sentences ================================================================
# The 29-word BATTERY sentence is split into two sentences of 25 words or fewer; the validator measures every
# sentence and no longer exempts it. The NETWORK sentence was already two sentences (20 and 21 words): unchanged.
G7 = "G7"
for _c in ("P0563", "P2504"):
    fix(_c, G7, "G7 owner decision: split the 29-word BATTERY sentence (19 and 13 words)",
        advice=BATTERY_SPLIT + " Otherwise ride only a short way, in daylight, to a workshop.")


# ======================= G8: the reviewer's CONCERN rows (see fix_log_v5_20261002.csv for APPLIED / REJECTED) ==========
G8 = "G8"
import re  # noqa: E402


def sub(pattern, repl, flags=0):
    """A transformation of a text field or a list of texts: re.sub on every string."""
    def f(old):
        if isinstance(old, list):
            return [re.sub(pattern, repl, x, flags=flags) for x in old]
        return re.sub(pattern, repl, old, flags=flags)
    return f


def replace_in_list(old_item, new_item):
    return lambda lst: [new_item if x == old_item else x for x in lst]


HOT = "If your bike has a temperature warning and it comes on, or you see steam or smell hot coolant, stop and let the engine cool."
_HOT_OLD = r"(\.|;) [Gg]et it checked soon; if (the engine|it) runs very hot, stop and let it cool\."
# reviewer problem 9: a rider without a temperature display cannot judge "runs very hot"
for _c in ("P0115", "P0116", "P0118", "P0119", "P0480", "P0483", "P0484", "P0485", "P0691", "P0692", "P2181"):
    fix(_c, G8, "G8 problem 9: replace 'if the engine runs very hot' by a sign the rider can see", advice=sub(_HOT_OLD, "; get it checked soon. " + HOT))
for _c in ("P0480", "P0483", "P0484", "P0485", "P0691", "P0692"):
    fix(_c, G8, "G8 problem 9: the ride reason said 'stop if the engine gets very hot', which a rider cannot judge",
        ride=lambda r: (r[0], r[1].replace("stop if the engine gets very hot", "stop if you see steam or smell hot coolant")))
fix("P0117", G8, "G8 problem 9: P0117 makes the engine LOOK hotter; the overheating warning belongs to P0118",
    advice="The bike may be hard to start when cold and run unevenly until warm. Get it checked soon.")

# wording of the fixed oil pressure test and idioms (checks 2, 5, 6, 10)
_TESTER = "mechanical oil pressure tester"
for _c in ("P0520", "P0521", "P0522", "P0523", "P0524"):
    fix(_c, G8, "G8 check 5: the source names no 'mechanical oil pressure tester'; say 'the workshop's pressure test'",
        hints=sub(r"(?i)a mechanical oil pressure tester", "the workshop's oil pressure test"))
fix("P0524", G8, "G8 check 2: a false low reading is possible (as P0520 to P0523); level stays STOP",
    hints=lambda h: h + ["Check the sensor and wiring after the oil level and the pressure test are good"])
fix("P0522", G8, "G8 check 4: the source says it can mean really low oil pressure and the lamp may not exist; review true",
    advice="Check the engine oil level. If it is low, the engine is noisy or hot, or a warning lamp stays on, stop, "
           "switch off and do not keep riding.", review=True)
fix("P0224", G8, "G8 check 10: 'misbehave' is an idiom", ride=(CARE, "throttle may work wrongly at times; ride gently, avoid traffic"))
fix("P0124", G8, "G8 check 10 (same word as P0224): 'misbehave'", ride=lambda r: (r[0], r[1].replace("misbehave", "work wrongly")))
fix("P0600", G8, "G8 check 10 (same word as P0224): 'misbehaves'", ride=lambda r: (r[0], r[1].replace("misbehaves", "works wrongly")))
for _c in ("P0601", "P0602", "P0607"):
    fix(_c, G8, "G8 check 10: 'misbehave' is an idiom", basis="ECU may work wrongly")
fix("P0634", G8, "G8 check 10 (same word as P0602): 'misbehave'", basis="hot ECU may work wrongly")
fix("P0617", G8, "G8 check 10: 'run on' is an idiom", basis="starter may keep turning after the engine starts")
for _c in ("P0130", "P2195", "P2196", "P2A00"):
    fix(_c, G8, "G8 check 10: 'fine-tune' is an idiom; use 'adjust'", meaning=sub(r"fine-tune", "adjust"))
for _c in ("U0004", "U0007", "U0009", "U0073", "U0074", "U0075", "U0076", "U0077"):
    fix(_c, G8, "G8 check 10: 'pulling the bus down' is an idiom", causes=sub(r"A faulty unit pulling the bus down", "A faulty unit that disturbs the bus"))
fix("P033F", G8, "G8 check 10: 'jumped' (a verb form of 'jump') is an idiom; use the reviewer's wording",
    causes=replace_in_list("Stretched or jumped timing chain (rare)", "Worn or slipped timing chain (rare)"))
for _c in ("P0460", "P0464"):
    fix(_c, G8, "G8 checks 6 and 10: 'sender' is not a glossary term; use 'sensor'",
        causes=sub(r"\bsender\b", "sensor"), hints=sub(r"\bsender\b", "sensor"))
fix("P0322", G8, "G8 check 2: 'Dead pickup' is informal", causes=replace_in_list("Dead pickup", "Failed pickup"))
fix("P0445", G8, "G8 check 2: the first cause only repeats the title", causes=replace_in_list("Shorted purge valve circuit", "Shorted purge valve coil or wire"))
fix("P2097", G8, "G8 check 2: the first cause only repeats the code", causes=replace_in_list("Downstream oxygen sensor reading too rich", "Contaminated or aged downstream oxygen sensor"))
fix("P00D1", G8, "G8 check 1: 'works electrically' is not in the title",
    meaning="The heater of the upstream oxygen sensor does not warm the sensor as expected.")
fix("P0321", G8, "G8 checks 1 and 7: 'in range' and 'plausibility check' removed",
    meaning="The engine speed signal does not match what the bike's computer (ECU) expects, so the engine speed may be misread.")
fix("P2109", G8, "G8 check 7: 'closed throttle stop' is not explained",
    meaning="The throttle position reading at the closed position of the throttle does not match the value that the bike's computer (ECU) has learned.")
fix("P2118", G8, "G8 check 1: the cause is stated as fact; the title only says range/performance",
    meaning=sub(r", from a binding", ", often from a binding"))
for _c, _t in [("P0231", "Fuel pump circuit (secondary): voltage below threshold"),
               ("P0232", "Fuel pump circuit (secondary): voltage above threshold"),
               ("P0233", "Fuel pump circuit (secondary): intermittent circuit fault")]:
    fix(_c, G8, "G8 check 1: the standard title says 'secondary circuit'; 'power circuit' was the author's reading",
        title=_t, meaning=sub(r"fuel pump (power )?circuit", "fuel pump circuit (secondary)", re.I))
for _c in ("P0053", "P0054"):
    fix(_c, G8, "G8 check 6: 'resistance outside range' is added to the shared phrase list as 'resistance out of range' and used",
        title=sub(r"resistance outside range", "resistance out of range"))
fix("P068A", G8, "G8 check 8: with_care but the reason said 'usually rideable'", ride=(CARE, "ride with care; go to a workshop soon"))
fix("P0504", G8, "G8 check 8: a bike with no brake light should not be ridden", ride=(CARE, "ride only if the brake light works; ride gently"))
for _c in ("P0633", "P0512", "P0513"):
    fix(_c, G8, "G8 problem 8: 'do not switch off on the way' removed the one action that always makes a bike safe",
        ride=(CARE, "if it starts, go to a workshop; avoid switching off unless unsafe"))
fix("P2148", G8, "G8 check 9: the hot or swollen battery stop condition belongs in the advice (as P0561 and P2502)",
    advice="The engine may run poorly, and the battery may be overcharged; get it checked soon. " + BATTERY_HOT)

fix("P0118", G8, "G8 problem 9 (shortened so the advice fits 220 characters)",
    advice="The bike may use more fuel and smoke, and cooling may not switch on; get it checked soon. " + HOT)
# twist grip sensors D and E (check 5): the source says 'throttle/pedal position sensor D/E'
for _c in ("P2122", "P2123", "P2127", "P2128", "P2138"):
    fix(_c, G8, "G8 check 5: 'twist grip sensor D/E' is the author's mapping of 'throttle/pedal position sensor D/E'",
        title=sub(r"Twist grip sensors? ", lambda m: m.group(0).replace("Twist grip sensor", "Throttle (twist grip) position sensor")),
        meaning=sub(r"twist grip sensor", "throttle (twist grip) position sensor"),
        causes=sub(r"twist grip sensor", "throttle (twist grip) position sensor"),
        hints=sub(r"twist grip sensors", "throttle (twist grip) sensors"))

fix("P2138", G8, "G8 check 5 (title kept to 70 characters)", title="Throttle (twist grip) sensors D and E: signal plausibility fault")
# CAN bus (checks 7 and 11): the key exists in the validator; the first use explains the word
for _c in ("U0001", "U0002", "U0003", "U0004", "U0005", "U0006", "U0007", "U0008", "U0009", "U0010", "U0073", "U0074",
           "U0075", "U0076", "U0077", "U0140", "U0146"):
    fix(_c, G8, "G8 check 11: only a bike with a CAN bus can raise this code", applies={"can_bus_fitted": True})
_NET = "CAN bus (the bike's data network)"
for _c, _m in [
    ("U0003", f"The plus wire of the {_NET} is broken or disconnected, so units cannot talk reliably."),
    ("U0004", f"The plus wire of the {_NET} reads too low, often from a short to ground, so units cannot talk."),
    ("U0005", f"The plus wire of the {_NET} reads too high, often from a short to battery supply, so units cannot talk."),
    ("U0006", f"The minus wire of the {_NET} is broken or disconnected, so units cannot talk reliably."),
    ("U0007", f"The minus wire of the {_NET} reads too low, often from a short to ground, so units cannot talk."),
    ("U0008", f"The minus wire of the {_NET} reads too high, often from a short to battery supply, so units cannot talk."),
    ("U0073", f"A control unit stopped using CAN bus A (the bike's data network) because it is not working, so units cannot talk."),
    ("U0074", f"A control unit stopped using CAN bus B (the bike's data network) because it is not working, so units cannot talk."),
]:
    fix(_c, G8, "G8 check 7: 'CAN bus' is used without saying what it is (sentence kept to 25 words or fewer)", meaning=_m)
for _c in ("U0075", "U0076", "U0077"):
    fix(_c, G8, "G8 check 6: bus off titles say 'communication lost (bus off)' as U0073 and U0074",
        title=sub(r": bus off", ": communication lost (bus off)"))

# held-out entries are fixed too, so a later release is not stale
fix("C003F", G8, "G8 check 1: unsupported claim about direction sensing removed; check 7: plain wording",
    meaning="The ABS control unit found that the wheel speed sensor signals do not agree with each other, so ABS may be switched off.")
for _c in ("P0914", "P0915", "P0916", "P0917", "P0918", "P0919"):
    fix(_c, G8, "G8 check 1: the source is a gearbox code; say only that the gear position signal is unreliable and drop the effect on starting",
        advice="The gear position signal is unreliable, so the bike may not know which gear is selected. Get it checked soon; "
               "if it will not start, do not bypass any safety switch.",
        ride=(CARE, "gear position unreliable; short trip to a workshop"))
fix("P0625", G8, "G8 check 2: brushed field alternators are rare on small bikes",
    causes=lambda c: [x for x in c if "brushes" not in x])

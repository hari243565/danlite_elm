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

"""Entries held OUT of the shipped seed (owner decision G3, 2026-10-02), following the HOLD recommendations of the
independent review of V4 (docs/content/REVIEW_REPORT_V4_20261002.md, sections B, G, I and J). They are not deleted:
build_seed.py writes them, unchanged, to held_entries_v5.jsonl with the reason below. Their authored text stays in
the authored_*.py files, so lifting a hold means removing the code from HELD here and rebuilding."""

WHEEL = ("Chassis wheel-speed entry held until the owner's assistant settles which edition of the chassis code numbering "
         "applies: OBDex holds both editions (the same wheel fault sits under two numbers, e.g. C0037 and C0045) and "
         "Wal33D reads C0035 as a right front sensor SUPPLY code, not a left front circuit code. Also unresolved: whether "
         "'position-neutral' also rules out front or rear in the text, and the stored standard_title_en still names a "
         "wheel. (Review problem 4, sections G, I and J.)")
WHEEL_3F = (WHEEL + " C003F additionally makes an unsupported claim about wheel direction sensing that is a car feature.")
GEAR = ("P0914 to P0919: the OBDex source is an automatic gearbox selector code (transmission module, harsh shifts, "
        "locked in one gear) and the entry maps it onto a bike gear position sensor; the effect on starting was invented. "
        "Held until the owner's assistant confirms what these codes mean on a bike. (Review problem 6.)")
ALT = ("Alternator field or lamp terminal code: an ECU-controlled alternator field or lamp terminal is a car-style "
       "feature that small bikes rarely have, and there is no applies_when key to hide it from bikes that cannot raise "
       "it. Held until a key such as alternator_ecu_controlled exists. (Review problem 10, section I.)")

HELD = {}
for _c in ("C0035", "C0037", "C0038", "C003A", "C003B", "C003C", "C003D", "C003E"):
    HELD[_c] = WHEEL
HELD["C003F"] = WHEEL_3F
for _c in ("P0914", "P0915", "P0916", "P0917", "P0918", "P0919"):
    HELD[_c] = GEAR
for _c in ("P0620", "P0621", "P0625", "P0626", "P2500", "P2501"):
    HELD[_c] = ALT

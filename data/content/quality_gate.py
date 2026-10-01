#!/usr/bin/env python3
"""Step 1B: source quality gate. Holds the verdicts for the 60-code stratified
sample (drawn with random.seed(20261001) from the first selection: P0=36,
P2=9, C0=8, U0=7) and computes the rates and the MODE decision.

Verdict scale
  OK            correct and usable for a small motorcycle or scooter
  QUESTIONABLE  true somewhere, but boilerplate, car-only, padded, or
                imprecise enough that a rider could be misled
  WRONG         contradicts the standard or sound engineering
  EMPTY         the source has nothing for this field (symptoms only)
Order of fields: title, components, causes, symptoms.

Usage: python3 quality_gate.py data/content/source_quality_gate_sample.csv
"""
import csv
import sys

O, Q, W, E = "OK", "QUESTIONABLE", "WRONG", "EMPTY"

V = {
    "C003C": (Q, O, O, Q, "non-standard title; ESC/brake-assist boilerplate, MIL flag set"),
    "C003D": (O, O, O, Q, "single cause; ESC/transmission symptoms are car boilerplate"),
    "C0042": (O, O, O, Q, "ESC and brake-assist wording is car boilerplate, same four symptoms on every C-code"),
    "C0050": (O, O, O, Q, "same boilerplate symptoms"),
    "C0052": (O, O, O, Q, "same boilerplate symptoms"),
    "C0080": (Q, O, O, Q, "'front axle' has no meaning on a bike; boilerplate symptoms"),
    "C0111": (O, O, Q, Q, "hydraulic block leak is a stretch; ABS lamp is not the usual symptom"),
    "C0234": (O, O, O, Q, "same boilerplate symptoms"),
    "P0054": (O, O, O, E, "heater resistance, causes thin but right"),
    "P0068": (O, Q, O, O, "components list a MAF sensor, small bikes use speed-density"),
    "P0109": (O, O, O, E, "no symptoms in source"),
    "P0110": (O, O, O, E, "no symptoms; combined MAF/IAT cause is car-only but minor"),
    "P0114": (O, O, O, E, "no symptoms; causes padded with near duplicates"),
    "P0122": (O, O, O, O, "limp mode wording fits ride-by-wire, softer on cable throttles"),
    "P013F": (O, O, O, Q, "downstream sensor: fuel use and rough idle symptoms are misleading"),
    "P0197": (O, O, O, E, "no symptoms in source"),
    "P0217": (O, O, O, W, "cabin heater and long warm-up do not fit an overheating code"),
    "P0219": (O, O, O, E, "over-rev from missed downshift is right for a bike"),
    "P0220": (O, Q, O, O, "'pedal' sensor wording; a bike has a twist grip"),
    "P0231": (O, O, O, O, ""),
    "P0262": (O, O, O, E, "no symptoms in source"),
    "P033F": (Q, O, O, E, "title could not be confirmed against the standard"),
    "P0340": (O, O, O, O, ""),
    "P0341": (O, Q, O, O, "variable valve timing solenoid is rare on small bikes"),
    "P0344": (O, O, O, O, "three causes say nearly the same thing (padding)"),
    "P0410": (O, Q, Q, E, "air pump and combi valve are car parts; bikes use a reed valve"),
    "P0454": (O, O, O, Q, "fuel smell and loose-cap symptoms do not fit a sensor circuit fault"),
    "P0457": (O, O, O, O, ""),
    "P0460": (O, O, O, E, "single cause"),
    "P0497": (O, O, O, Q, "loose-cap warning does not fit low purge flow"),
    "P0499": (O, O, O, Q, "fuel smell and loose-cap symptoms do not fit a circuit fault"),
    "P0512": (O, O, O, E, "no symptoms in source"),
    "P0518": (O, O, O, O, "padded causes"),
    "P0519": (O, O, O, O, ""),
    "P0520": (O, O, O, E, "single cause, no symptoms"),
    "P0563": (O, O, O, E, "no symptoms in source"),
    "P0605": (O, O, O, O, ""),
    "P060B": (O, O, O, O, ""),
    "P0629": (O, O, O, O, "'ground open' is a stretch for a circuit-high code"),
    "P0638": (O, O, O, O, "single cause"),
    "P0652": (O, O, O, O, ""),
    "P0687": (W, O, Q, O, "SAE P0687 is the relay control circuit HIGH; source says sense circuit open"),
    "P0697": (O, O, O, O, ""),
    "P0915": (O, Q, Q, W, "automatic-transmission symptoms (slipping, harsh shifts) on a gear position input"),
    "P2100": (O, O, O, O, ""),
    "P2118": (O, O, O, O, ""),
    "P2119": (O, O, O, O, ""),
    "P2127": (O, Q, O, O, "'pedal' sensor wording"),
    "P2177": (O, Q, O, O, "MAF listed in components and causes"),
    "P2181": (O, O, O, E, "no symptoms in source"),
    "P2195": (O, O, O, O, ""),
    "P2271": (O, O, O, Q, "downstream sensor: fuel use and rough idle symptoms are misleading"),
    "P2305": (O, O, O, E, "no symptoms in source"),
    "U0004": (O, O, O, O, ""),
    "U0005": (O, O, O, O, ""),
    "U0075": (Q, O, O, O, "title conflicts with U0073-U0077 pattern (two entries for bus B)"),
    "U0115": (O, O, Q, O, "a second engine computer does not exist on a bike (code later dropped from selection)"),
    "U0146": (O, O, Q, O, "central-electronics fuse is a car idea (thin entry)"),
    "U0168": (O, O, O, Q, "generic bus symptoms; the real symptom (no start) is missing"),
    "U0401": (O, O, O, O, ""),
}
FIELDS = ["title", "components", "causes", "symptoms"]


def main(out_csv):
    assert len(V) == 60, len(V)
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["code"] + FIELDS + ["reason"])
        for c in sorted(V):
            w.writerow([c, *V[c]])
    n = len(V)
    print(f"sample size {n}")
    for i, f in enumerate(FIELDS):
        q = sum(1 for v in V.values() if v[i] == Q)
        wr = sum(1 for v in V.values() if v[i] == W)
        e = sum(1 for v in V.values() if v[i] == E)
        print(f"{f:10s} OK {n-q-wr-e:2d}  QUESTIONABLE {q:2d}  WRONG {wr:2d}  EMPTY {e:2d}  "
              f"bad-rate {100*(q+wr)/n:.1f}%")
    cs = sum(1 for v in V.values() if v[2] in (Q, W) or v[3] in (Q, W))
    print(f"codes with a QUESTIONABLE/WRONG cause or symptom: {cs}/{n} = {100*cs/n:.1f}%")


if __name__ == "__main__":
    main(sys.argv[1])

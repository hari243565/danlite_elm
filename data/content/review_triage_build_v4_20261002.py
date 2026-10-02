import csv
rows=list(csv.DictReader(open('held_back_titles_v2.csv')))
W,N,D,X='WORDING','NUMBERING','DIFFERENT_FAULT','NO_SECOND_SOURCE'
dec={
 'P0351':(W,'Ignition Coil A Primary/Secondary Circuit Malfunction','high','Same coil circuit; the OBDex form is the older wording, Wal33D the newer. Owner already verified; entry stays.'),
 'P0352':(W,'Ignition Coil B Primary/Secondary Circuit Malfunction','high','As P0351 (coil B, cylinder 2, twin only). Owner already verified; entry stays.'),
 'P0505':(W,'Idle Control System Malfunction','high','Same system, shorter wording in Wal33D. Owner already verified; entry stays.'),
 'P0134':(W,'O2 Sensor Circuit No Activity Detected (Bank 1 Sensor 1)','medium','OBDex adds "/ Slow Response", but P0133 is the slow response code in both sources, so the OBDex title looks merged. No-activity reading is the safer meaning.'),
 'P0140':(W,'O2 Sensor Circuit No Activity Detected (Bank 1 Sensor 2)','medium','As P0134 for the downstream sensor (P0136 to P0139 neighbours agree between the sources).'),
 'P0325':(W,'Knock Sensor 1 Circuit Malfunction (Bank 1 or Single Sensor)','high','Same sensor; Wal33D calls it knock/combustion vibration sensor A. Owner already verified; entry stays.'),
 'P0327':(W,'Knock Sensor 1 Circuit Low Input (Bank 1 or Single Sensor)','high','As P0325. Owner already verified; entry stays.'),
 'P0328':(W,'Knock Sensor 1 Circuit High Input (Bank 1 or Single Sensor)','high','As P0325. Owner already verified; entry stays.'),
 'P0446':(W,'Evaporative Emission System Vent Control Circuit','high','Same vent control circuit; neighbours P0447 and P0448 agree between the sources.'),
 'P0449':(W,'Evaporative Emission System Vent Valve/Solenoid Circuit','medium','Same vent valve circuit; Wal33D adds "Open", which P0447 already uses in both sources, so check the failure kind.'),
 'P0418':(W,'Secondary Air Injection System Relay A Circuit','medium','Same relay or control circuit A named in different words; Wal33D drops the word relay.'),
 'P0421':(D,'','low','OBDex: warm-up catalyst. Wal33D: "Catalyst 1" (P0422 is "Catalyst 2"). May be the same catalyst under a new naming scheme, but that is a guess. Not a small-bike code; low priority.'),
 'P2119':(D,'','low','OBDex: throttle closed position performance. Wal33D: throttle body range/performance. Different fault names; P2109 already covers the minimum stop.'),
 'P2230':(D,'','medium','OBDex repeats "Barometric Pressure Circuit Low" (the title of P2228). Wal33D says intermittent/erratic, which fits the P2227 to P2230 sequence (range, low, high, intermittent). Likely an OBDex duplicate.'),
 'U0168':(D,'','medium','OBDex repeats the immobiliser title of U0167 (spelled with z). Wal33D says vehicle security control module. Likely an OBDex duplicate.'),
 'U0327':(D,'','medium','OBDex says powertrain control module (that is U0301). Wal33D says vehicle security control module, which follows U0326 (immobiliser). Likely an OBDex error.'),
 'U0408':(D,'','low','OBDex: immobiliser control module. Wal33D: throttle actuator A control module. No block pattern explains it.'),
 'U0421':(D,'','low','OBDex: throttle/pedal position sensor. Wal33D: suspension control module A. No block pattern explains it.'),
 'C0021':(D,'','medium','OBDex: ABS pump motor circuit range/performance. Wal33D: brake booster performance. Wal33D C0020 (pump motor control) agrees with OBDex, so the two sources split after C0020.'),
 'C0022':(D,'','medium','OBDex: ABS pump motor circuit low. Wal33D: brake booster solenoid.'),
 'C0023':(D,'','medium','OBDex: ABS pump motor circuit high. Wal33D: stop lamp control.'),
 'C0025':(D,'','medium','OBDex: ABS pump motor stalled. Wal33D: brake pedal feedback pressure sensor circuit.'),
 'C0030':(D,'','medium','Old seven-code left front series in OBDex (range, low, high, erratic, no signal, malfunction, intermittent). Wal33D has three codes per wheel (tone wheel, sensor, supply): here the left front tone wheel. Two editions of the standard, unverified.'),
 'C0031':(D,'','medium','Same wheel, but OBDex says circuit low and Wal33D says plain wheel speed sensor. Two editions, unverified.'),
 'C0032':(D,'','medium','Same wheel, OBDex circuit high versus Wal33D sensor supply. Two editions, unverified.'),
 'C0033':(D,'','medium','OBDex: left front signal erratic. Wal33D: right front tone wheel. Wal33D follows the three-per-wheel layout (C0033 right front tone wheel, C0034 right front sensor, C0035 right front supply).'),
 'C0034':(D,'','medium','OBDex: left front no signal. Wal33D: right front wheel speed sensor. Three-per-wheel layout in Wal33D.'),
 'C0036':(D,'','medium','OBDex: left front circuit intermittent. Wal33D: left rear tone wheel. Three-per-wheel layout in Wal33D (C0037 left rear sensor, C0038 left rear supply agree with OBDex).'),
 'C0041':(D,'','medium','OBDex: right front circuit range/performance. Wal33D: brake pedal switch B (Wal33D C0040 to C0046 is a brake pedal and pressure block).'),
 'C0042':(D,'','medium','OBDex: right front circuit low. Wal33D: brake pedal position sensor circuit A.'),
 'C0043':(D,'','medium','OBDex: right front circuit high. Wal33D: brake pedal position sensor circuit B.'),
 'C0044':(D,'','medium','OBDex: right front signal erratic. Wal33D: brake pressure sensor A.'),
 'C0046':(D,'','medium','OBDex: right front circuit intermittent. Wal33D: brake pressure sensor A/B.'),
 'C0052':(D,'','medium','OBDex: left rear circuit low. Wal33D: steering wheel position sensor signal A (a steering block). A bike has no such sensor.'),
 'C0053':(D,'','medium','OBDex: left rear circuit high. Wal33D: steering wheel position sensor signal B.'),
 'C0054':(D,'','medium','OBDex: left rear signal erratic. Wal33D: steering wheel position sensor signal C.'),
 'C0055':(D,'','medium','OBDex: left rear no signal. Wal33D: steering wheel position sensor signal D.'),
 'C0061':(D,'','medium','OBDex: right rear circuit range/performance. Wal33D: lateral acceleration sensor (a vehicle dynamics block).'),
 'C0062':(D,'','medium','OBDex: right rear circuit low. Wal33D: longitudinal acceleration sensor.'),
 'C0063':(D,'','medium','OBDex: right rear circuit high. Wal33D: yaw rate sensor.'),
 'C0064':(D,'','medium','OBDex: right rear signal erratic. Wal33D: roll rate sensor.'),
 'C0065':(D,'','medium','OBDex: right rear no signal. Wal33D: vertical acceleration sensor.'),
 'C0081':(D,'','low','OBDex: wheel speed mismatch (rear axle). Wal33D: ABS malfunction indicator. A bike has no axle pair.'),
 'C0099':(D,'','low','OBDex: ABS control module internal fault. Wal33D: a 4WD rear differential position sensor. Car-only in Wal33D.'),
 'C0035':(N,'Wheel Speed Sensor Circuit Malfunction','low','OBDex title (left front circuit malfunction) is the same fault as Wal33D C0031 (left front wheel speed sensor). Wal33D C0035 is "right front wheel speed sensor supply". So the sources do NOT both say circuit: Wal33D says supply, and the wheel differs. A position-neutral title is only safe if the owner confirms the edition.'),
 'C0040':(N,'Wheel Speed Sensor Circuit Malfunction','low','OBDex title (right front circuit malfunction) equals Wal33D C0034 (right front wheel speed sensor). Wal33D C0040 is "brake pedal switch A". Do not write until the edition is confirmed: under the newer edition this is a brake pedal code.'),
 'C0045':(N,'Wheel Speed Sensor Circuit Malfunction','low','OBDex title (left rear circuit malfunction) equals Wal33D C0037, and OBDex itself also lists the same fault at C0037, so OBDex holds one fault under two numbers (two editions mixed). Wal33D C0045 is "brake pressure sensor B".'),
 'C0050':(N,'Wheel Speed Sensor Circuit Malfunction','low','OBDex title (right rear circuit malfunction) equals Wal33D C003A, and OBDex also lists it at C003A. Wal33D has no generic row for C0050.'),
}
for r in rows:
    if r['verdict']=='MISSING' and r['code'] not in dec:
        dec[r['code']]=(X,'','low','Wal33D has no generic row for this code, so there is nothing to compare. One public lookup decides it; do not write an entry before that.')
assert set(dec)==set(r['code'] for r in rows), set(r['code'] for r in rows)^set(dec)
# MISSING rows that I classed NUMBERING keep NUMBERING (C0050)
out=open('held_back_triage_v2_20261002.csv','w',newline='')
w=csv.writer(out)
w.writerow(['code','OBDex title','Wal33D title','difference type','proposed position-neutral or semantic title','confidence','evidence and note','already written in the seed'])
for r in rows:
    t,p,cf,n=dec[r['code']]
    w.writerow([r['code'],r['obdex_title'],r['wal33d_title'],t,p,cf,n,r['entry_written']])
out.close()
import collections
print(collections.Counter(v[0] for v in dec.values()))

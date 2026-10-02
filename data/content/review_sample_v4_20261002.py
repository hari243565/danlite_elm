"""Reproducible sample for the V4 review (seed 20261002). Run: python3 review_sample_v4_20261002.py
Writes review_sample_v4_20261002.json next to itself."""
import json, random, os
here = os.path.dirname(os.path.abspath(__file__))
E = [json.loads(l) for l in open(os.path.join(here, 'generic_en_seed.jsonl'))]
old = [l.strip() for l in open(os.path.join(here, 'entries_before_step_t.txt')) if l.strip()]
by = {e['code']: e for e in E}
old_set = set(old); new = sorted(c for c in by if c not in old_set); old_sorted = sorted(old_set)
rng = random.Random(20261002)
A = sorted(c for c, e in by.items() if e['rider_action_level'] == 'STOP')
chassis_new = sorted(c for c in new if by[c]['system'] == 'chassis')
net = sorted(c for c in by if by[c]['system'] == 'network')
net_new = [c for c in net if c in new]
pool = [c for c in new if c not in chassis_new and c not in net and c not in A]
B_rand = sorted(rng.sample(pool, 100))
# brief says 100 random of the 189 new; take the random 100 from the new entries, then add the mandatory groups
B100 = sorted(rng.sample(new, 100))
C_pool = [c for c in old_sorted if c not in A]
C = sorted(rng.sample(old_sorted, 30))
D1 = ['P0604','P0605','P0606','P0202','P0264','P0265','P0352','P0232']
rbw = sorted(c for c, e in by.items() if (e.get('applies_when') or {}).get('ride_by_wire') or 'ride-by-wire' in (e['standard_title_en']+e['title_en']).lower() or 'twist grip' in e['title_en'].lower() or c in ('P2104','P2105','P2111','P2112'))
abs_ = sorted(c for c, e in by.items() if e['system']=='chassis' or c in ('U0121','C0035') or 'ABS' in e['rider_advice_en'] or 'wheel speed' in e['title_en'].lower())
out = dict(A=A, B100=B100, chassis_new=chassis_new, net=net, C=C, D1=D1, rbw=rbw, abs=abs_, new=new, old=old_sorted)
reviewed = sorted(set(A)|set(B100)|set(chassis_new)|set(net)|set(C)|set(D1)|set(rbw)|set(abs_))
out['reviewed'] = reviewed
json.dump(out, open(os.path.join(here,'review_sample_v4_20261002.json'),'w'), indent=1)
print({k: len(v) for k, v in out.items()})

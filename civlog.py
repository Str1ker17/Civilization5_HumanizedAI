import sys, os, re
from collections import Counter

def parse(run):
    exp, caps = {}, []
    p = os.path.join(run, 'HumanizedCivilianLog.csv')
    if not os.path.exists(p):
        return exp, caps
    for line in open(p, encoding='utf-8', errors='replace'):
        f = [x.strip() for x in line.split(',')]
        if len(f) < 6:
            continue
        turn, player, kind = int(f[0]), int(f[1]), f[2]
        if kind == 'exposure':
            kv = dict(re.findall(r'(\w+)=(-?\d+)', line))
            exp[(turn, player, int(f[4]), int(f[5]))] = dict(kv, type=f[3])
        elif kind == 'capture':
            caps.append((turn, player, f[3], int(f[4]), int(f[5]), int(f[6])))
    return exp, caps

stats = Counter()
total_exp = Counter()
rows = []
for run in sys.argv[1:]:
    exp, caps = parse(run)
    for k, e in exp.items():
        total_exp[e['type']] += 1
        if int(e['within2']) > 0:
            total_exp[e['type'] + ' enemy<=2'] += 1
            if e['visible'] == '1':
                total_exp[e['type'] + ' enemy<=2 visible'] += 1
            if e['guard'] == '1':
                total_exp[e['type'] + ' enemy<=2 guarded'] += 1
    for turn, player, utype, x, y, captor in caps:
        e = exp.get((turn, player, x, y))
        if e is None:
            stats['capture without snapshot'] += 1
            rows.append((os.path.basename(run), turn, player, utype, x, y, 'no snapshot'))
            continue
        key = '%s: nearest=%s visible=%s build=%s guard=%s danger>0=%s hazard=%s city=%s own=%s' % (
            e['type'], e['nearest'], e['visible'], e['build'], e['guard'], int(int(e['danger']) > 0), e['hazard'], e['city'], e['own'])
        stats['captures'] += 1
        stats['visible nearest' if e['visible'] == '1' else 'hidden nearest'] += 1
        stats['danger>0' if int(e['danger']) > 0 else 'danger=0'] += 1
        stats['building' if e['build'] == '1' else 'not building'] += 1
        stats['guarded' if e['guard'] == '1' else 'unguarded'] += 1
        rows.append((os.path.basename(run), turn, player, key))
print('snapshots:', dict(total_exp))
print('captures:', dict(stats))
for r in rows:
    print(r)

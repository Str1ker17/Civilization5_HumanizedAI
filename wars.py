import sys, re, csv
from collections import Counter
tot = Counter()
for run in sys.argv[1:]:
    c = Counter()
    wars = set()
    for line in open(run + '/DiplomacyAI_War_Log.csv', encoding='utf-8', errors='replace'):
        p = [x.strip() for x in line.split(',')]
        if len(p) > 6 and p[0].isdigit() and any(x in ('WGL Conquest', 'WGL Damage') for x in p):
            wars.add((p[1], p[2]))
    c['war_pairs'] = len(wars)
    for line in open(run + '/DiplomacyAI_Messages_Log.csv', encoding='utf-8', errors='replace'):
        if 'WAR DECLARATION' in line:
            c['declarations'] += 1
    ops = {}
    for line in open(run + '/OperationalAILog.csv', encoding='utf-8', errors='replace'):
        p = [x.strip() for x in line.split(',')]
        if len(p) > 3 and 'SNEAK_CITY_ATTACK' in p[2]:
            m = re.search(r'Army: (\d+)', line)
            key = (p[1], m.group(1) if m else '?')
            st = ops.setdefault(key, set())
            st.add(p[3].split(' ')[0])
    c['sneak_ops'] = len(ops)
    c['sneak_reached_target'] = sum(1 for s in ops.values() if 'Moving' in s or 'At' in s)
    with open(run + '/EconomicMonitorLog.csv', encoding='utf-8', errors='replace', newline='') as f:
        rows = list(csv.DictReader(f))
    prev = {}
    byturn = {}
    for r in rows:
        pl = r.get('Player') or r['Civ Name']
        t = int(r['Turn']) if 'Turn' in r else int(list(r.values())[0])
        n = int(r['# Cities'])
        if pl in prev:
            d = n - prev[pl]
            if d:
                byturn.setdefault(t, []).append(d)
        prev[pl] = n
    for t, ds in byturn.items():
        lost = sum(-d for d in ds if d < 0)
        gained = sum(d for d in ds if d > 0)
        c['cities_lost'] += lost
        c['cities_taken_by_major'] += min(lost, gained)
    tot.update(c)
print(' '.join('%s=%d' % kv for kv in sorted(tot.items())))

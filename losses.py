import sys, os, re, csv
from collections import Counter
tot = Counter()
for run in sys.argv[1:]:
    c = Counter()
    p = os.path.join(run, 'PlayerTacticalAILog.csv')
    if os.path.exists(p):
        for line in open(p, encoding='utf-8', errors='replace'):
            m = re.match(r'(\d+), ([^,]+), [^,]*, Captured: ([^,]+), Enemy was: (.*)', line.strip())
            if m and m.group(2) != 'Варвары':
                c['captured_' + {'Поселенцы': 'settler', 'Рабочие': 'worker'}.get(m.group(3), 'other')] += 1
            if re.match(r'\d+, [^,]+, [^,]*, Killed in combat', line) and ', Варвары,' not in line:
                c['units_killed'] += 1
    with open(os.path.join(run, 'EconomicMonitorLog.csv'), encoding='utf-8', errors='replace', newline='') as f:
        rows = list(csv.DictReader(f))
    prev = {}
    peak = Counter()
    for r in rows:
        pl = r.get('Player') or r['Civ Name']
        n = int(r['# Cities'])
        if pl in prev and n < prev[pl]:
            c['cities_lost'] += prev[pl] - n
        prev[pl] = n
        peak[pl] = max(peak[pl], n)
    tot.update(c)
    print('%-20s %s' % (os.path.basename(run.rstrip('/')), ' '.join('%s=%d' % kv for kv in sorted(c.items()))))
print('%-20s %s' % ('TOTAL', ' '.join('%s=%d' % kv for kv in sorted(tot.items()))))

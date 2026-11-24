import sys, os, re, csv
from collections import Counter, defaultdict

def hexdist(x1, y1, x2, y2):
    def cube(x, y):
        q = x - (y - (y & 1)) // 2
        return q, y, -q - y
    a, b = cube(x1, y1), cube(x2, y2)
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))

hist = defaultdict(Counter)
rows = []
for run in sys.argv[1:]:
    with open(os.path.join(run, 'EconomicMonitorLog.csv'), encoding='utf-8', errors='replace') as f:
        majors = {r['Civ Name'] for r in csv.DictReader(f)}
    cities = defaultdict(list)
    for line in open(os.path.join(run, 'PlayerHomelandAILog.csv'), encoding='utf-8', errors='replace'):
        m = re.match(r'(\d+), ([^,]+), Founded city at, X: (\d+), Y: (\d+)', line)
        if m and m.group(2) in majors:
            cities[m.group(2)].append((int(m.group(1)), int(m.group(3)), int(m.group(4))))
    attacks = defaultdict(list)
    captures = []
    last_settler_move = {}
    for line in open(os.path.join(run, 'PlayerTacticalAILog.csv'), encoding='utf-8', errors='replace'):
        m = re.match(r'(\d+), ([^,]+), [^,]*, Attacking high priority civilian, X: (\d+), Y: (\d+)', line)
        if m:
            attacks[int(m.group(1))].append((int(m.group(3)), int(m.group(4)), m.group(2)))
            continue
        m = re.match(r'(\d+), ([^,]+), [^,]*, Captured: ([^,]+), Enemy was: (.*)', line.strip())
        if m and m.group(2) in majors:
            captures.append((int(m.group(1)), m.group(2), m.group(3), m.group(4)))
        m = re.match(r'(\d+), ([^,]+), [^,]*, (Moving Поселенцы without escort|Moving escorting)', line)
        if m:
            last_settler_move[m.group(2)] = (int(m.group(1)), 'alone' if 'without' in m.group(3) else 'escorted')
    for turn, civ, unit, captor in captures:
        cand = [a for a in attacks.get(turn, []) + attacks.get(turn - 1, [])]
        best = None
        for x, y, attacker in cand:
            own = [(cx, cy) for t, cx, cy in cities[civ] if t <= turn]
            if not own:
                continue
            d = min(hexdist(x, y, cx, cy) for cx, cy in own)
            if best is None or d < best[0]:
                best = (d, x, y, attacker)
        kind = unit
        if unit == 'Поселенцы':
            t, mode = last_settler_move.get(civ, (-99, '?'))
            kind = unit + ('/' + mode if turn - t <= 1 else '/other')
        d = best[0] if best else None
        hist[kind]['dist ' + (str(min(d, 6)) + ('+' if d is not None and d >= 6 else '') if d is not None else '?')] += 1
        hist[kind]['captor ' + captor] += 1
        hist[kind]['turn ' + ('<=30' if turn <= 30 else '31-60' if turn <= 60 else '61+')] += 1
        rows.append((os.path.basename(run), turn, civ, kind, d, captor))
for kind, c in hist.items():
    print(kind, sum(v for k, v in c.items() if k.startswith('captor')))
    for prefix in ('dist', 'turn', 'captor'):
        print('   ', ', '.join('%s=%d' % (k.split(' ', 1)[1], v) for k, v in sorted(c.items()) if k.startswith(prefix)))
if os.environ.get('ROWS'):
    for r in rows:
        print(r)

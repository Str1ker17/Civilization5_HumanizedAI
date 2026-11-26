import csv, os, sys, collections
R = os.environ.get('RUNS') or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'runs')
COLS = ['Num Techs', 'Policies', 'Science', 'Pop', 'Net Happiness', 'Treasury', 'Unit Maint', 'Build Maint', '# Workers', 'Improved tiles']
EARLY = [50, 100]
NMAJ = 4


def load(run):
    p = os.path.join(R, run, 'EconomicMonitorLog.csv')
    if not os.path.exists(p):
        return None
    r = csv.reader(open(p, encoding='utf-8', errors='replace'))
    h = [c.strip() for c in next(r)]
    ip, it, inet = h.index('Player'), h.index('Turn'), h.index('Net Happiness')
    ix = [h.index(c) for c in COLS]
    at = collections.defaultdict(lambda: [0.0] * len(COLS))
    unh = 0
    last = 0
    for row in r:
        if len(row) < len(h) - 1 or not row[it].strip().isdigit() or not row[ip].strip().isdigit():
            continue
        t, p = int(row[it]), int(row[ip])
        if p >= NMAJ:
            continue
        last = max(last, t)
        if t in EARLY or t == 199:
            for k, i in enumerate(ix):
                at[t][k] += float(row[i])
        if t <= 199 and float(row[inet]) < 0:
            unh += 1
    if last < 199:
        return None
    return at, unh / NMAJ


def main(a, b, mode, maps=('tpan', 'tfra')):
    n = 0
    sa = collections.defaultdict(lambda: [0.0] * len(COLS))
    sb = collections.defaultdict(lambda: [0.0] * len(COLS))
    wins = [0] * len(COLS)
    ua = ub = 0.0
    for m in maps:
        for s in range(1, 9):
            x, y = load('b8-%s-%s-%s-s%d' % (a, mode, m, s)), load('b8-%s-%s-%s-s%d' % (b, mode, m, s))
            if not x or not y:
                continue
            n += 1
            for t in EARLY + [199]:
                for k in range(len(COLS)):
                    sa[t][k] += x[0][t][k]
                    sb[t][k] += y[0][t][k]
            for k in range(len(COLS)):
                wins[k] += y[0][199][k] > x[0][199][k]
            ua += x[1]
            ub += y[1]
    if not n:
        print('no pairs')
        return
    print('%s vs %s, %s, %d games; unhappy turns per AI %.1f vs %.1f' % (b, a, mode, n, ub / n, ua / n))
    print('%-26s %s' % ('metric', '  '.join('%18s' % ('T%d' % t) for t in EARLY + [199])))
    for k, c in enumerate(COLS):
        cells = []
        for t in EARLY + [199]:
            va, vb = sa[t][k] / n / NMAJ, sb[t][k] / n / NMAJ
            pct = (vb / va - 1) * 100 if va else 0
            cells.append('%6.1f>%6.1f %+5.0f%%' % (va, vb, pct))
        print('%-26s %s  wins %d/%d' % (c, '  '.join(cells), wins[k], n))


main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else 'duelr')

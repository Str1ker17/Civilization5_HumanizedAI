import csv
import os
import sys


def rows(run):
    p = os.path.join(run, 'EconomicMonitorLog.csv')
    r = csv.reader(open(p, encoding='utf-8', errors='replace'))
    h = [c.strip() for c in next(r)]
    it = h.index('Turn')
    out = {}
    for row in r:
        if len(row) < len(h) - 1 or not row[it].isdigit():
            continue
        out[(row[0], int(row[it]))] = tuple(x.strip() for x in row)
    return h, out


ref = sys.argv[1]
h, a = rows(ref)
ip, ic = h.index('Pop'), h.index('# Cities')
last = max(t for _, t in a) - 1
for run in sys.argv[2:]:
    if not os.path.exists(os.path.join(run, 'EconomicMonitorLog.csv')):
        print('%s: no log' % run)
        continue
    _, b = rows(run)
    keys = sorted(set(a) & set(b), key=lambda k: (k[1], k[0]))
    diff = [k for k in keys if k[1] <= last and a[k] != b[k]]
    pa = sum(float(a[k][ip]) for k in keys if k[1] == last)
    pb = sum(float(b[k][ip]) for k in keys if k[1] == last)
    ca = sum(float(a[k][ic]) for k in keys if k[1] == last)
    cb = sum(float(b[k][ic]) for k in keys if k[1] == last)
    first = '%s T%d' % diff[0] if diff else 'none'
    print('%s vs %s: rows compared %d, differing %d, first difference %s, T%d pop %.0f vs %.0f, cities %.0f vs %.0f' % (
        os.path.basename(run), os.path.basename(ref), len([k for k in keys if k[1] <= last]), len(diff), first, last, pa, pb, ca, cb))

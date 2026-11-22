import sys, os, csv
from collections import defaultdict
techs = sys.argv[1].split(',')
res = defaultdict(list)
n = 0
for run in sys.argv[2:]:
    with open(os.path.join(run, 'EconomicMonitorLog.csv'), encoding='utf-8', errors='replace') as f:
        majors = {r['Civ Name'] for r in csv.DictReader(f)}
    first = {}
    for line in open(os.path.join(run, 'TechAILog.csv'), encoding='utf-8', errors='replace'):
        f = [x.strip() for x in line.split(',')]
        if len(f) >= 4 and f[2] == 'CHOSEN' and f[1] in majors:
            first.setdefault((f[1], f[3]), int(f[0]))
    for civ in majors:
        n += 1
        for t in techs:
            if (civ, t) in first:
                res[t].append(first[(civ, t)])
for t in techs:
    v = sorted(res[t])
    print('%-24s chosen by %d of %d, median turn %s' % (t, len(v), n, v[len(v)//2] if v else '-'))

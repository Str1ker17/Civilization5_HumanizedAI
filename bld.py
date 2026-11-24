import sys, os, csv, re
from collections import Counter, defaultdict
target = sys.argv[1]
LIMIT = int(os.environ.get('LIMIT', '88'))
avail = 0
chosen = []
never = 0
instead = Counter()
ranks = Counter()
for run in sys.argv[2:]:
    with open(os.path.join(run, 'EconomicMonitorLog.csv'), encoding='utf-8', errors='replace') as f:
        majors = {r['Civ Name'] for r in csv.DictReader(f)}
    first = {}
    done = {}
    cand = defaultdict(list)
    for line in open(os.path.join(run, 'CityStrategyAILog.csv'), encoding='utf-8', errors='replace'):
        f = [x.strip() for x in line.split(',')]
        if len(f) < 5 or f[1] not in majors:
            continue
        t = int(f[0])
        if t > LIMIT:
            continue
        key = (f[1], f[2])
        if f[3] in ('Building', 'Unit', 'Army unit', 'Operation unit', 'Project', 'Process'):
            try:
                cand[key].append((f[4], int(f[5])))
            except (ValueError, IndexError):
                pass
            continue
        m = re.search(r'CHOSEN: ([^,]*),', line)
        if m:
            names = [c[0] for c in cand[key]]
            if target in names and key not in done:
                first.setdefault(key, t)
                order = sorted(cand[key], key=lambda c: -c[1])
                r = [c[0] for c in order].index(target) + 1
                ranks[r] += 1
                if m.group(1) == target:
                    done[key] = t
                else:
                    instead[m.group(1)] += 1
            cand[key] = []
    for key, t in first.items():
        avail += 1
        if key in done:
            chosen.append(done[key] - t)
        else:
            never += 1
chosen.sort()
print('%s: available in %d cities, chosen in %d (median wait %s turns), never by T%d: %d' % (target, avail, len(chosen), chosen[len(chosen)//2] if chosen else '-', LIMIT, never))
print('rank of %s at decisions before it was chosen:' % target, dict(sorted(ranks.items())))
print('chosen instead:', instead.most_common(15))

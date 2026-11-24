import sys, os, re
from collections import defaultdict
agg = defaultdict(lambda: defaultdict(int))
cnt = defaultdict(int)
for run in sys.argv[1:]:
    for line in open(os.path.join(run, 'Lua.log'), encoding='utf-8', errors='replace'):
        if 'HumanizedAutoplay: tiles ' not in line:
            continue
        kv = dict(re.findall(r'(\w+)=(-?\d+)', line))
        t = int(kv['turn'])
        cnt[t] += 1
        for k in ('worked', 'improved', 'improvable', 'water', 'workers'):
            agg[t][k] += int(kv[k])
for t in sorted(agg):
    a = agg[t]
    land = a['worked'] - a['water']
    print('turn %3d players %2d: worked %.1f (water %.1f), improved %.1f, unimproved-but-improvable %.1f (%.0f%% of worked), workers %.1f' % (
        t, cnt[t], a['worked'] / cnt[t], a['water'] / cnt[t], a['improved'] / cnt[t], a['improvable'] / cnt[t],
        100.0 * a['improvable'] / max(1, a['worked']), a['workers'] / cnt[t]))

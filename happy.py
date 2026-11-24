import re, sys, os
from collections import defaultdict
keys = None
agg = defaultdict(lambda: defaultdict(float))
cnt = defaultdict(int)
for run in sys.argv[1:]:
    for line in open(os.path.join(run, 'Lua.log'), encoding='utf-8', errors='replace'):
        if 'HumanizedAutoplay: happy ' not in line:
            continue
        kv = dict(re.findall(r'(\w+)=(-?\d+)', line))
        t = int(kv['turn'])
        cnt[t] += 1
        for k, v in kv.items():
            if k not in ('turn', 'player'):
                agg[t][k] += int(v)
for t in sorted(agg):
    print(t, cnt[t], ' '.join('%s=%.1f' % (k, v / cnt[t]) for k, v in agg[t].items()))

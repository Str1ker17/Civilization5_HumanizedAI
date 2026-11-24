import sys, re
from collections import defaultdict

summary = defaultdict(list)
for run in sys.argv[1:]:
    ops = {}
    for line in open(run + '/OperationalAILog.csv', encoding='utf-8', errors='replace'):
        p = [x.strip() for x in line.split(',')]
        if len(p) < 4 or not p[0].isdigit():
            continue
        t = int(p[0]); civ = p[1]; op = p[2].replace('AI_OPERATION_', ''); msg = p[3]
        m = re.search(r'Army: (\d+)', line)
        if not m:
            continue
        key = (civ, op, m.group(1))
        d = ops.setdefault(key, {'t0': t, 't1': t, 'recruit': 0, 'gather': 0, 'move': 0, 'first_move': None})
        d['t1'] = t
        if msg.startswith('Recruiting'):
            d['recruit'] += 1
        elif msg.startswith('Gathering'):
            d['gather'] += 1
        elif msg.startswith('Moving'):
            d['move'] += 1
            if d['first_move'] is None:
                d['first_move'] = t
    for (civ, op, a), d in ops.items():
        if any(k in op for k in ('FOUND', 'ESCORT', 'COLONIZE', 'MERCHANT', 'CONCERT', 'SPY')):
            continue
        summary[op].append(d)
for op, lst in sorted(summary.items()):
    moved = [d for d in lst if d['first_move'] is not None]
    rec = sorted(d['recruit'] for d in lst)
    med = rec[len(rec) // 2] if rec else 0
    lat = sorted(d['first_move'] - d['t0'] for d in moved)
    print('%-28s ops=%3d reached_move=%3d recruit_turns_median=%d start_to_move_median=%s' % (op, len(lst), len(moved), med, lat[len(lat) // 2] if lat else '-'))

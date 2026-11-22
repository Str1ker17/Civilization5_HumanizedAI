import sys, os, re
from collections import Counter, defaultdict
cat = defaultdict(Counter)
res = defaultdict(Counter)
players = Counter()
have = {}
for run in sys.argv[1:]:
    for line in open(os.path.join(run, 'Lua.log'), encoding='utf-8', errors='replace'):
        if 'HumanizedAutoplay: happy ' in line:
            players[int(re.search(r'turn=(\d+)', line).group(1))] += 1
        m = re.search(r'HumanizedAutoplay: luxury turn=(\d+) player=(\d+) ?(.*)', line)
        if m:
            have[(run, m.group(1), m.group(2))] = {i.rsplit(':', 1)[0] for i in m.group(3).split() if i.endswith('I')}
            continue
        if 'HumanizedAutoplay: luxplot ' not in line:
            continue
        kv = dict(re.findall(r'(\w+)=(-?\w+)', line.split('luxplot ')[1]))
        t = int(kv['turn'])
        if kv['res'] in have.get((run, kv['turn'], kv['player']), set()):
            cat[t]['(duplicate of improved type)'] += 1
            continue
        g = lambda k: int(kv[k])
        if g('water'):
            c = 'water'
        elif not g('can'):
            c = 'cannot build'
        elif g('workers') == 0:
            c = 'can, no workers'
        elif g('danger') > 0:
            c = 'can, danger'
        elif not g('samearea'):
            c = 'can, no worker on landmass'
        elif not g('radius'):
            c = 'can, outside city radius'
        else:
            c = 'can, workers %s' % ('all busy' if g('busy') == g('workers') else 'idle/moving')
        cat[t][c] += 1
        res[t]['%s %s' % (c, kv['res'])] += 1
for t in sorted(cat):
    print('turn %d, players %d, unimproved luxury plots %d' % (t, players[t], sum(cat[t].values())))
    for c, n in cat[t].most_common():
        print('   %-32s %d' % (c, n))
    if os.environ.get('RES'):
        for c, n in res[t].most_common():
            print('      %-40s %d' % (c, n))

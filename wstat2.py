import sys, re, collections, glob
def stats(path, players=range(4)):
    seq = collections.defaultdict(list)
    for line in open(path, encoding='utf-8', errors='replace'):
        p = [x.strip() for x in line.split(',')]
        if len(p) < 9 or p[4] != 'UNIT_WORKER' or not p[0].isdigit() or int(p[2]) not in players: continue
        m = re.search(r'act=(\d+)', p[8]); d = re.search(r' danger=(\d+)', p[8])
        seq[(int(p[2]), p[3])].append((int(p[0]), p[1], (int(p[6]), int(p[7])), int(m.group(1)) if m else -1, int(d.group(1)) if d else 0))
    c = collections.Counter()
    for k, s in seq.items():
        bt = {}
        for t, kind, pos, act, dg in s:
            bt.setdefault(t, {})[kind] = (pos, act, dg)
        for t in sorted(bt):
            e = bt[t].get('end'); st = bt[t].get('start')
            if not e: continue
            c['turns'] += 1
            if e[1] == 6:
                c['build'] += 1
            elif st and st[0] == e[0]:
                c['stand'] += 1
                c['stand_danger'] += e[2] > 0
            else:
                c['move'] += 1
                c['move_danger'] += (st[2] if st else 0) > 0
    return c
if __name__ == '__main__':
    for pat in sys.argv[1:]:
        tot = collections.Counter()
        for f in glob.glob(pat):
            tot.update(stats(f))
        n = tot['turns']
        print('%s: worker-turns %d build %.0f%% move %.0f%% (from danger %.0f%%) stand %.0f%% (on danger %.0f%%)' % (pat, n, 100 * tot['build'] / n, 100 * tot['move'] / n, 100 * tot['move_danger'] / n, 100 * tot['stand'] / n, 100 * tot['stand_danger'] / n))

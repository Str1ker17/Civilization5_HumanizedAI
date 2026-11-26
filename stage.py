import csv, sys, glob, os
R = os.environ.get('RUNS') or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'runs')
cols = ['# Cities', 'Pop', 'Production', '# Workers', 'Trade Routes established', 'Trade Routes available', 'GPT - Connects', 'Unit Maint', 'Total Income', 'Net Happiness', 'Treasury']
turns = [int(t) for t in os.environ.get('TURNS', '25,50,75,100,150').split(',')]
nmaj = int(os.environ.get('NMAJ', '4'))
for pat in sys.argv[1:]:
    acc = {}
    runs = sorted(glob.glob(f'{R}/{pat}'))
    n = 0
    for d in runs:
        f = f'{d}/EconomicMonitorLog.csv'
        if not os.path.exists(f):
            continue
        n += 1
        with open(f, encoding='latin-1') as fh:
            r = csv.reader(fh)
            head = [h.strip() for h in next(r)]
            ip, it = head.index('Player'), head.index('Turn')
            for row in r:
                try:
                    p, t = int(row[ip]), int(row[it])
                except ValueError:
                    continue
                if p >= nmaj or t not in turns:
                    continue
                for c in cols:
                    try:
                        v = float(row[head.index(c)])
                    except (ValueError, IndexError):
                        continue
                    acc.setdefault((t, c), []).append(v)
    print(f'{pat}: {n} runs')
    print('turn ' + ' | '.join(c[:10] for c in cols))
    for t in turns:
        print(f'{t:4d} ' + ' | '.join(f'{sum(acc.get((t, c), [0])) / max(1, len(acc.get((t, c), []))):10.1f}' for c in cols))

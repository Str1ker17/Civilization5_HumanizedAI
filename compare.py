import csv
import os
import sys

METRICS = ['# Cities', 'Pop', 'Food', 'Production', 'Science', 'Culture', 'Faith', 'Num Techs', 'Policies',
           'Net GPT', 'Treasury', '# Workers', 'Improved tiles', 'Net Happiness']


def load(run):
    path = os.path.join(run, 'EconomicMonitorLog.csv')
    with open(path, encoding='utf-8', errors='replace', newline='') as f:
        rows = list(csv.reader(f))
    head = rows[0]
    data = {}
    for row in rows[1:]:
        rec = dict(zip(head, row))
        data.setdefault(int(rec['Turn']), {})[rec['Civ Name']] = rec
    return data


def mean_at(runs, turn, metric):
    values = []
    for data in runs:
        civs = data.get(turn, {})
        values += [float(rec[metric]) for rec in civs.values() if rec.get(metric, '') != '']
    return sum(values) / len(values) if values else None


def last_full_turn(runs):
    turns = []
    for data in runs:
        counts = {t: len(c) for t, c in data.items()}
        full = max(counts.values())
        turns.append(max(t for t, n in counts.items() if n == full))
    return min(turns)


def main():
    args = sys.argv[1:]
    if '--' not in args:
        sys.exit('usage: compare.py RUN... -- RUN...')
    cut = args.index('--')
    a = [load(r) for r in args[:cut]]
    b = [load(r) for r in args[cut + 1:]]
    end = min(last_full_turn(a), last_full_turn(b))
    turns = sorted({t for t in (25, 50, 75, end) if t <= end})
    print('runs: A=%d B=%d, mean per civ' % (len(a), len(b)))
    print('%-16s %5s %10s %10s %8s' % ('metric', 'turn', 'A', 'B', 'B/A'))
    for metric in METRICS:
        for turn in turns:
            va, vb = mean_at(a, turn, metric), mean_at(b, turn, metric)
            if va is None or vb is None:
                continue
            ratio = '%+7.1f%%' % ((vb / va - 1) * 100) if va else '      -'
            print('%-16s %5d %10.1f %10.1f %8s' % (metric, turn, va, vb, ratio))
        print()


main()

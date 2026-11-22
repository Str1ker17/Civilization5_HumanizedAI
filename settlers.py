import csv
import os
import re
import sys
from collections import Counter, defaultdict

OPS = ('AI_OPERATION_FOUND_CITY', 'AI_OPERATION_QUICK_COLONIZE')


def read_lines(run, name):
    path = os.path.join(run, name)
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8', errors='replace') as f:
        return [line.strip() for line in f]


def city_turns(run):
    with open(os.path.join(run, 'EconomicMonitorLog.csv'), encoding='utf-8', errors='replace', newline='') as f:
        rows = list(csv.DictReader(f))
    key = 'Player' if 'Player' in rows[0] else 'Civ Name'
    found = defaultdict(list)
    prev = {}
    for row in rows:
        player = row[key]
        cities = int(row['# Cities'])
        turn = int(row['Turn'])
        if cities > prev.get(player, 0):
            found[player] += [turn] * (cities - prev.get(player, 0))
        prev[player] = cities
    return found


def run_stats(run):
    stats = Counter()
    last_move = {}
    for line in read_lines(run, 'PlayerTacticalAILog.csv'):
        m = re.match(r'(\d+), ([^,]+), [^,]*, (.*)', line)
        if not m:
            continue
        turn, civ, msg = int(m.group(1)), m.group(2), m.group(3)
        if 'Поселенцы without escort' in msg:
            last_move[civ] = ('alone', turn)
        elif 'Moving escorting' in msg:
            last_move[civ] = ('escorted', turn)
        m = re.match(r'Captured: Поселенцы, Enemy was: (.*)', msg)
        if m and civ != 'Варвары':
            kind, at = last_move.get(civ, ('other', -99))
            stats['lost_' + (kind if turn - at <= 1 else 'other')] += 1
    waits = defaultdict(set)
    for line in read_lines(run, 'OperationalAILog.csv'):
        f = [x.strip() for x in line.split(',')]
        if len(f) < 4 or f[2] not in OPS:
            continue
        if f[3] == 'City founded':
            stats['founded'] += 1
        elif f[3] == 'Ended':
            stats['ended_' + (f[4] if len(f) > 4 else '?')] += 1
        elif f[3] == 'Started':
            stats['started'] += 1
        m = re.search(r'Army: (\d+)', line)
        if m and f[3] == 'Recruiting Units':
            waits[(f[1], m.group(1))].add(int(f[0]))
    stats['wait_ops'] = len(waits)
    stats['wait_turns'] = sum(len(v) for v in waits.values())
    return stats


def main():
    total = Counter()
    nth = defaultdict(list)
    players = 0
    for run in sys.argv[1:]:
        stats = run_stats(run)
        total.update(stats)
        for turns in city_turns(run).values():
            players += 1
            for i, t in enumerate(turns[1:4], 2):
                nth[i].append(t)
        print('%-22s %s' % (os.path.basename(run.rstrip('/')), ' '.join('%s=%d' % kv for kv in sorted(stats.items()))))
    print('%-22s %s' % ('TOTAL', ' '.join('%s=%d' % kv for kv in sorted(total.items()))))
    for i in sorted(nth):
        v = sorted(nth[i])
        print('city #%d: %d of %d players, median turn %d' % (i, len(v), players, v[len(v) // 2]))


main()

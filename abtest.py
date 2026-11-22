import csv
import os
import re
import sys
from collections import defaultdict

METRICS = ['# Cities', 'Pop', 'Production', 'Science', 'Culture', 'Faith', 'Num Techs', 'Policies', 'Treasury',
           'Improved tiles', 'Net Happiness']


def settings(run):
    conf = {}
    with open(os.path.join(run, 'run.txt'), encoding='utf-8') as f:
        for line in f:
            for key, value in re.findall(r'(\w+)=(\S*)', line):
                conf[key] = value
    groups = {}
    for slot, level in re.findall(r'(\d+)=(\w+)', conf.get('mistakes', '')):
        groups[int(slot)] = level
    return conf, groups


def final_rows(run):
    with open(os.path.join(run, 'EconomicMonitorLog.csv'), encoding='utf-8', errors='replace', newline='') as f:
        rows = list(csv.DictReader(f))
    by_turn = defaultdict(dict)
    for row in rows:
        by_turn[int(row['Turn'])][int(row['Player'])] = row
    full = max(len(v) for v in by_turn.values())
    turn = max(t for t, v in by_turn.items() if len(v) == full)
    return turn, by_turn[turn]


def main():
    runs = sys.argv[1:]
    values = defaultdict(lambda: defaultdict(list))
    paired = defaultdict(dict)
    turns = set()
    for run in runs:
        conf, groups = settings(run)
        turn, rows = final_rows(run)
        turns.add(turn)
        default = conf.get('handicap', '?')
        for player, row in rows.items():
            level = groups.get(player, default)
            for metric in METRICS:
                v = float(row[metric])
                values[level][metric].append(v)
                paired[(conf.get('seed'), player, metric)][level] = v
    levels = sorted(values)
    print('runs=%d final turn(s)=%s samples per level: %s' % (len(runs), sorted(turns),
          ', '.join('%s=%d' % (lv, len(values[lv][METRICS[0]])) for lv in levels)))
    print('%-15s' % 'metric' + ''.join('%18s' % lv.replace('HANDICAP_', '') for lv in levels) + '   paired wins (first vs second)')
    for metric in METRICS:
        means = [sum(values[lv][metric]) / len(values[lv][metric]) for lv in levels]
        wins = total = 0
        if len(levels) == 2:
            for key, by_level in paired.items():
                if key[2] == metric and len(by_level) == 2:
                    a, b = by_level[levels[0]], by_level[levels[1]]
                    if a != b:
                        total += 1
                        wins += a > b
        print('%-15s' % metric + ''.join('%18.1f' % m for m in means) + ('   %d/%d' % (wins, total) if total else ''))


main()

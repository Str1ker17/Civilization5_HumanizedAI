import csv
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict

args = sys.argv[1:]
cut = args.index('--')
A, B = args[:cut], args[cut + 1:]
TURNS = (99, 149, 199)
METRICS = ['# Cities', 'Pop', 'Food', 'Production', 'Science', 'Culture', 'Num Techs', 'Policies', 'Improved tiles', '# Workers',
           'Net GPT', 'Treasury', 'GPT - Connects', 'Trade Routes established', 'Net Happiness']

base = os.path.expanduser("~/snap/steam/common/.local/share/Steam/steamapps/compatdata/8930/pfx/drive_c/users/steamuser/Documents/My Games/Sid Meier's Civilization 5/cache/")
db = sqlite3.connect('file:' + base + 'Civ5DebugDatabase.db?mode=ro', uri=True)
loc = sqlite3.connect('file:' + base + 'Localization-Merged.db?mode=ro', uri=True)
text = dict((t, x.split('|')[0]) for t, x in loc.execute("select Tag, Text from LocalizedText where Language = 'ru_RU'"))
kind = {}
growth = {r[0] for r in db.execute("select BuildingType from Building_YieldChanges where YieldType in ('YIELD_FOOD','YIELD_SCIENCE') and Yield > 0 union select BuildingType from Building_YieldChangesPerPop where YieldType = 'YIELD_SCIENCE' union select BuildingType from Building_YieldModifiers where YieldType in ('YIELD_FOOD','YIELD_SCIENCE') union select Type from Buildings where FoodKept > 0 union select BuildingType from Building_SeaPlotYieldChanges where YieldType = 'YIELD_FOOD'")}
for t, desc, cls, happy, flavor in db.execute("select b.Type, b.Description, c.MaxGlobalInstances, b.Happiness + b.UnmoddedHappiness, (select group_concat(FlavorType) from Building_Flavors f where f.BuildingType = b.Type) from Buildings b join BuildingClasses c on c.Type = b.BuildingClass"):
    n = text.get(desc, desc)
    if cls == 1:
        k = 'wonder'
    elif t in growth:
        k = 'growth/sci'
    elif happy and happy > 0:
        k = 'happiness'
    elif flavor and 'FLAVOR_RELIGION' in flavor:
        k = 'religion'
    else:
        k = 'other bldg'
    kind.setdefault(n, k)
for desc, combat, ai in db.execute('select Description, Combat + RangedCombat, DefaultUnitAI from Units'):
    n = text.get(desc, desc)
    kind.setdefault(n, 'settler' if ai == 'UNITAI_SETTLE' else 'worker' if ai in ('UNITAI_WORKER', 'UNITAI_WORKER_SEA') else 'military' if combat and combat > 0 else 'other unit')


def econ(runs):
    rows = defaultdict(dict)
    for run in runs:
        with open(os.path.join(run, 'EconomicMonitorLog.csv'), encoding='utf-8', errors='replace', newline='') as f:
            for r in csv.DictReader(f):
                try:
                    rows[(run, r['Civ Name'])][int(r['Turn'])] = r
                except (ValueError, KeyError):
                    pass
    return rows


def mean(rows, turn, metric):
    v = [float(t[turn][metric]) for t in rows.values() if turn in t and t[turn].get(metric, '') != '']
    return sum(v) / len(v) if v else float('nan')


def broke(rows, lo, hi):
    n = b = 0
    for t in rows.values():
        for turn, r in t.items():
            if lo <= turn <= hi:
                n += 1
                b += int(r['Treasury']) + int(r['Net GPT']) < 0
    return 100.0 * b / max(n, 1)


def choices(runs, lo, hi):
    c = Counter()
    for run in runs:
        with open(os.path.join(run, 'EconomicMonitorLog.csv'), encoding='utf-8', errors='replace') as f:
            majors = {r['Civ Name'] for r in csv.DictReader(f)}
        for line in open(os.path.join(run, 'CityStrategyAILog.csv'), encoding='utf-8', errors='replace'):
            m = re.match(r'(\d+), ([^,]+), [^,]+, SEED: [^,]+, CHOSEN: ([^,]+),', line)
            if m and m.group(2) in majors and lo <= int(m.group(1)) <= hi:
                c[kind.get(m.group(3).strip(), 'process')] += 1
    s = sum(c.values())
    return ' '.join('%s=%.0f%%' % (k, 100.0 * v / s) for k, v in c.most_common()) if s else '-'


ea, eb = econ(A), econ(B)
print('%-26s %s' % ('metric', ' '.join('     T%-3d base -> new' % t for t in TURNS)))
for m in METRICS:
    cells = []
    for t in TURNS:
        a, b = mean(ea, t, m), mean(eb, t, m)
        d = (b - a) / abs(a) * 100 if a else float('nan')
        cells.append('%7.1f -> %7.1f %+6.1f%%' % (a, b, d))
    print('%-26s %s' % (m, ' | '.join(cells)))
print('broke%% T100-149 %.0f -> %.0f, T150-199 %.0f -> %.0f' % (broke(ea, 100, 149), broke(eb, 100, 149), broke(ea, 150, 199), broke(eb, 150, 199)))
for lo, hi in ((0, 99), (100, 199)):
    print('choices T%d-%d base: %s' % (lo, hi, choices(A, lo, hi)))
    print('choices T%d-%d new:  %s' % (lo, hi, choices(B, lo, hi)))

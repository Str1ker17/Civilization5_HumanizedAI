import sqlite3, sys, os, re
from collections import Counter
base = os.path.expanduser("~/snap/steam/common/.local/share/Steam/steamapps/compatdata/8930/pfx/drive_c/users/steamuser/Documents/My Games/Sid Meier's Civilization 5/cache/")
db = sqlite3.connect('file:' + base + 'Civ5DebugDatabase.db?mode=ro', uri=True)
loc = sqlite3.connect('file:' + base + 'Localization-Merged.db?mode=ro', uri=True)
text = dict((t, x.split("|")[0]) for t, x in loc.execute("select Tag, Text from LocalizedText where Language = 'ru_RU'"))
cat = {}
for desc, cost, combat, ai in db.execute('select Description, Cost, Combat + RangedCombat, DefaultUnitAI from Units'):
    name = text.get(desc, desc)
    if ai == 'UNITAI_SETTLE':
        c = 'settler'
    elif ai == 'UNITAI_WORKER' or ai == 'UNITAI_WORKER_SEA':
        c = 'worker'
    elif combat and combat > 0:
        c = 'military'
    else:
        c = 'other unit'
    cat[name] = (c, cost)
for desc, cost, bc in db.execute('select b.Description, b.Cost, bc.MaxGlobalInstances from Buildings b join BuildingClasses bc on bc.Type = b.BuildingClass'):
    name = text.get(desc, desc)
    if name not in cat:
        cat[name] = ('wonder' if bc == 1 else 'building', cost)
LIMIT = int(os.environ.get('LIMIT', '100'))
tot = Counter()
unknown = Counter()
for run in sys.argv[1:]:
    majors = set()
    for line in open(os.path.join(run, 'EconomicMonitorLog.csv'), encoding='utf-8', errors='replace'):
        p = line.split(',')
        if len(p) > 2:
            majors.add(p[1].strip())
    for line in open(os.path.join(run, 'CityStrategyAILog.csv'), encoding='utf-8', errors='replace'):
        m = re.match(r'(\d+), ([^,]+), [^,]+, SEED: [^,]+, CHOSEN: ([^,]+),', line)
        if not m or int(m.group(1)) > LIMIT:
            continue
        c, cost = cat.get(m.group(3).strip(), (None, 0))
        if c is None:
            if m.group(3).startswith('Process') or 'Процесс' in m.group(3) or 'Исследования' in m.group(3) or 'Богатство' in m.group(3):
                c, cost = 'process', 0
            else:
                unknown[m.group(3)] += 1
                continue
        tot[c] += max(cost, 0)
s = sum(tot.values())
print(' '.join('%s=%.0f%%' % (k, 100.0 * v / s) for k, v in tot.most_common()), 'total=%d' % s)
if unknown:
    print('unknown:', dict(unknown.most_common(5)))

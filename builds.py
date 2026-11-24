import sys, os, csv, re
from collections import Counter
MIL = {'Воины', 'Лучники', 'Копейщики', 'Гоплиты', 'Бессмертные', 'Меткие лучники', 'Боевые колесницы', 'Катапульты', 'Баллисты', 'Мечники', 'Легионеры', 'Конные лучники', 'Всадники', 'Гетайры', 'Колесницы-лучники', 'Трирема'}
LIMIT = int(os.environ.get('LIMIT', '100'))
tot = Counter()
first = Counter()
players = 0
for run in sys.argv[1:]:
    with open(os.path.join(run, 'EconomicMonitorLog.csv'), encoding='utf-8', errors='replace') as f:
        majors = {r['Civ Name'] for r in csv.DictReader(f)}
    players += len(majors)
    for line in open(os.path.join(run, 'CityStrategyAILog.csv'), encoding='utf-8', errors='replace'):
        m = re.match(r'(\d+), ([^,]+), [^,]+, SEED: [^,]+, CHOSEN: ([^,]+),', line)
        if not m or m.group(2) not in majors or int(m.group(1)) > LIMIT:
            continue
        name = m.group(3)
        kind = 'military' if name in MIL else name
        tot[kind] += 1
for k, v in tot.most_common(14):
    print('%-28s %5.2f per civ' % (k, v / players))

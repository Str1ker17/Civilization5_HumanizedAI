import os
import re
import sqlite3
import sys

DEFAULT = os.path.expanduser("~/snap/steam/common/.local/share/Steam/steamapps/compatdata/8930/pfx/drive_c/users/steamuser/Documents/My Games/Sid Meier's Civilization 5/ModUserData/HumanizedAI-1.db")
path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
db = sqlite3.connect(path)
db.text_factory = bytes
values = {}
for name, value in db.execute('select Name, Value from SimpleValues'):
    values[name.decode('utf-8', 'replace')] = value.decode('utf-8', 'replace') if isinstance(value, bytes) else value


def lines(prefix, count_key):
    return [str(values.get('%s%d' % (prefix, i), '')) for i in range(1, int(values.get(count_key) or 0) + 1)]


seen = set()
notes = []
for line in lines('ChatHist', 'ChatHists') + lines('ChatNote', 'ChatNotes'):
    m = re.match(r'turn=(-?\d+) from=(.*?) text=(.*)', line)
    if not m or (m.group(1), m.group(3)) in seen:
        continue
    seen.add((m.group(1), m.group(3)))
    notes.append((int(m.group(1)), m.group(2), m.group(3)))
for turn, sender, text in sorted(notes, key=lambda n: n[0]):
    print('T%03d %s: %s' % (turn, sender, text))

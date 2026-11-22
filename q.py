import sqlite3, sys, os
db = os.path.expanduser("~/snap/steam/common/.local/share/Steam/steamapps/compatdata/8930/pfx/drive_c/users/steamuser/Documents/My Games/Sid Meier's Civilization 5/cache/Civ5DebugDatabase.db")
c = sqlite3.connect('file:' + db + '?mode=ro', uri=True)
for r in c.execute(sys.argv[1]):
    print(' | '.join(str(x) for x in r))

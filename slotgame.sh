#!/bin/sh
set -eu
SLOT=${1:?usage: slotgame.sh SLOT [DLL]}
DLL=${2:-}
COMMON=$HOME/snap/steam/common
GAME="$COMMON/.local/share/Steam/steamapps/common/Sid Meier's Civilization V"
MOD="Assets/DLC/Tournament Mod V12.3a + HumanizedAI"
DST=$COMMON/civ5-par/$SLOT/game
if [ ! -d "$COMMON/civ5-par/$SLOT/pfx" ]; then
	echo "no prefix for slot $SLOT" >&2
	exit 1
fi
if [ ! -d "$DST" ]; then
	rm -rf "$DST.tmp"
	cp -as "$GAME" "$DST.tmp"
	mv "$DST.tmp" "$DST"
fi
if [ -n "$DLL" ]; then
	cp "$DLL" "$DST/$MOD/CvGameCore_Expansion2.dll.tmp"
	mv "$DST/$MOD/CvGameCore_Expansion2.dll.tmp" "$DST/$MOD/CvGameCore_Expansion2.dll"
fi
echo "$SLOT dll $(md5sum < "$DST/$MOD/CvGameCore_Expansion2.dll" | cut -d' ' -f1)"

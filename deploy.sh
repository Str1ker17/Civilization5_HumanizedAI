#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
GAME=${GAME:-"$HOME/snap/steam/common/.local/share/Steam/steamapps/common/Sid Meier's Civilization V"}
DEST="$GAME/Assets/DLC/Tournament Mod V12.3a + HumanizedAI"
OUT=$ROOT/CvGameCoreDLL_Expansion2/BuildOutput/VS2013_ModWin32
PROTON=${PROTON:-$HOME/snap/steam/common/.local/share/Steam/steamapps/common/Proton 11.0/files}
WINE=$PROTON/bin/wine

if [ ! -d "$GAME/Assets/DLC" ]; then
	echo "game not found: $GAME (set GAME=...)" >&2
	exit 1
fi
if [ ! -x "$WINE" ]; then
	echo "wine not found: $WINE (set PROTON=.../files)" >&2
	exit 1
fi
if [ ! -f "$OUT/CvGameCore_Expansion2.dll" ]; then
	echo "build first: $OUT/CvGameCore_Expansion2.dll" >&2
	exit 1
fi

mkdir -p "$DEST/UI"
rsync -a --delete --itemize-changes --exclude=/UI/ \
	"$ROOT/Art" "$ROOT/Fonts" "$ROOT/Override" "$ROOT/Mods" "$ROOT/tmp" "$ROOT/MPModsPack.Civ5Pkg" "$ROOT/ui_check.bat" \
	"$OUT/CvGameCore_Expansion2.dll" "$OUT/CvGameCore_Expansion2.pdb" \
	"$DEST/"

export WINEPREFIX="$ROOT/.toolchain/wineprefix"
export WINEDEBUG=-all
find "$DEST/UI" -maxdepth 1 -type f -delete
log=$(mktemp)
s=0
(cd "$DEST" && "$WINE" cmd /c ui_check.bat) > "$log" 2>&1 || s=$?
cat "$log"
rm -f "$log"
if [ "$s" -ne 0 ]; then
	echo "ui_check.bat failed: $s" >&2
	exit "$s"
fi
echo "UI: $(find "$DEST/UI" -type f | wc -l) files"

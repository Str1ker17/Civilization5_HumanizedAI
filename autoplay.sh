#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
SLOT=${SLOT:-}
if [ -n "$SLOT" ]; then
	PFX=${PFX:-"$HOME/snap/steam/common/civ5-par/$SLOT/pfx"}
	if [ -z "${XVFB_DISPLAY:-}" ]; then
		echo "SLOT=$SLOT needs XVFB_DISPLAY" >&2
		exit 1
	fi
fi
PFX=${PFX:-"$HOME/snap/steam/common/.local/share/Steam/steamapps/compatdata/8930/pfx"}
LAUNCHER=$HOME/snap/steam/common/civ5-direct-launch.sh
MYGAMES="$PFX/drive_c/users/steamuser/Documents/My Games/Sid Meier's Civilization 5"
CONFIG=$MYGAMES/config.ini
GFX=$MYGAMES/GraphicsSettingsDX9.ini
LOGS=$MYGAMES/Logs
DATA=$MYGAMES/ModUserData/HumanizedAI-1.db
export DISPLAY="${DISPLAY:-:0}"
SUPERVISE=${SUPERVISE:-0}
XVFB=${XVFB:-1}
if [ "$SUPERVISE" = 1 ]; then
	XVFB=0
fi
if [ -n "$SLOT" ]; then
	XVFB=1
fi
XVFB_DISPLAY=${XVFB_DISPLAY:-:99}
XVFB_ENV=${XVFB_ENV:-MESA_VK_WSI_DEBUG=sw DXVK_CONFIG=d3d9.presentInterval=0}
ENVFILE=$HOME/snap/steam/common/civ5-autoplay.env
GAME_DISPLAY=$DISPLAY
if [ "$XVFB" = 1 ]; then
	GAME_DISPLAY=$XVFB_DISPLAY
fi

TURNS=${TURNS:-100}
SEED=${SEED:-1}
WORLDSIZE=${WORLDSIZE:-WORLDSIZE_SMALL}
GAMESPEED=${GAMESPEED:-GAMESPEED_STANDARD}
HANDICAP=${HANDICAP:-HANDICAP_PRINCE}
MAPSCRIPT=${MAPSCRIPT:-"Assets\\Maps\\Continents.lua"}
CIVS=${CIVS:-CIVILIZATION_ROME,CIVILIZATION_GREECE,CIVILIZATION_EGYPT,CIVILIZATION_CHINA,CIVILIZATION_PERSIA,CIVILIZATION_FRANCE}
MINORCIVS=${MINORCIVS:-8}
GAMEOPTIONS=${GAMEOPTIONS:-GAMEOPTION_AI_TWEAKS=0}
MISTAKES=${MISTAKES:-}
SAVEAS=${SAVEAS:-}
LOAD=${LOAD:-}
BUILDERLOG=${BUILDERLOG:-0}
START_TIMEOUT=${START_TIMEOUT:-600}
TURN_TIMEOUT=${TURN_TIMEOUT:-600}
OUT=${OUT:-"$ROOT/runs/$(date +%Y%m%d-%H%M%S)-s$SEED-t$TURNS"}

db() {
	python3 -I - "$DATA" "$@" <<'EOF'
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1], timeout=10)
db.execute('create table if not exists SimpleValues(Name TEXT Primary Key, Value VARIANT)')
args = sys.argv[2:]
if args[0] == 'set':
    for name, value in zip(args[1::2], args[2::2]):
        if value.lstrip('-').isdigit():
            value = int(value)
        db.execute('insert or replace into SimpleValues values (?, ?)', (name, value))
    db.commit()
else:
    row = db.execute('select Value from SimpleValues where Name = ?', (args[1],)).fetchone()
    print('' if row is None else row[0])
EOF
}

ini_get() {
	sed -n "s/^$2 = \(.*\)\r\$/\1/p" "$1"
}

ini_set() {
	sed -i "s/^$2 = .*\r\$/$2 = $3\r/" "$1"
}

game_window() {
	xwininfo -display "$GAME_DISPLAY" -root -tree 2>/dev/null | sed -n "s/^ *\(0x[0-9a-f]*\) \"Sid Meier's Civilization V.*(\"steam_app_8930\".*/\1/p" | head -n 1
}

iconify() {
	python3 -I - "$1" <<'EOF2'
import ctypes
import sys

x = ctypes.cdll.LoadLibrary('libX11.so.6')
x.XOpenDisplay.restype = ctypes.c_void_p
x.XDefaultScreen.argtypes = [ctypes.c_void_p]
x.XIconifyWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int]
x.XFlush.argtypes = [ctypes.c_void_p]
x.XCloseDisplay.argtypes = [ctypes.c_void_p]
d = x.XOpenDisplay(None)
x.XIconifyWindow(d, int(sys.argv[1], 16), x.XDefaultScreen(d))
x.XFlush(d)
x.XCloseDisplay(d)
EOF2
}

game_windows() {
	xwininfo -display "${1:-$GAME_DISPLAY}" -root -tree 2>/dev/null | grep -c '("steam_app_8930"' || true
}

if [ "$(game_windows)" -ne 0 ] || { [ -z "$SLOT" ] && [ "$(game_windows "$DISPLAY")" -ne 0 ]; }; then
	echo "Civ5 is already running, close it first" >&2
	exit 1
fi

old_sync=$(ini_get "$CONFIG" SyncRandSeed)
old_map=$(ini_get "$CONFIG" MapRandSeed)
old_builder=$(ini_get "$CONFIG" BuilderAILog)
old_full=$(ini_get "$GFX" FullScreen)
old_wx=$(ini_get "$GFX" WindowResX)
old_wy=$(ini_get "$GFX" WindowResY)
restore() {
	ini_set "$CONFIG" SyncRandSeed "$old_sync"
	ini_set "$CONFIG" MapRandSeed "$old_map"
	ini_set "$CONFIG" BuilderAILog "$old_builder"
	ini_set "$GFX" FullScreen "$old_full"
	ini_set "$GFX" WindowResX "$old_wx"
	ini_set "$GFX" WindowResY "$old_wy"
	db set AutoplayTurns 0 Status idle
	if [ "$XVFB" = 1 ]; then
		if [ -z "$SLOT" ]; then
			rm -f "$ENVFILE"
		fi
		if [ -n "$xvfb_pid" ]; then
			if [ "$(game_windows)" -eq 0 ]; then
				kill "$xvfb_pid"
			else
				echo "Xvfb $XVFB_DISPLAY (pid $xvfb_pid) left running with the game" >&2
			fi
		fi
	fi
}
xvfb_pid=
trap restore EXIT
trap 'exit 130' INT TERM

if [ "$XVFB" = 1 ]; then
	if [ ! -S "/tmp/.X11-unix/X${XVFB_DISPLAY#:}" ]; then
		Xvfb "$XVFB_DISPLAY" -screen 0 1280x800x24 -nolisten tcp > /dev/null 2>&1 &
		xvfb_pid=$!
		i=0
		while [ ! -S "/tmp/.X11-unix/X${XVFB_DISPLAY#:}" ] && [ $i -lt 20 ]; do
			sleep 0.5
			i=$((i + 1))
		done
		if [ ! -S "/tmp/.X11-unix/X${XVFB_DISPLAY#:}" ]; then
			echo "Xvfb $XVFB_DISPLAY did not start" >&2
			exit 1
		fi
	fi
	if [ -z "$SLOT" ]; then
		{
			echo "DISPLAY=$XVFB_DISPLAY"
			for kv in $XVFB_ENV; do
				echo "$kv"
			done
		} > "$ENVFILE"
	fi
fi

ini_set "$CONFIG" SyncRandSeed "$SEED"
ini_set "$CONFIG" MapRandSeed "$SEED"
ini_set "$CONFIG" AILog 1
ini_set "$CONFIG" BuilderAILog "$BUILDERLOG"
if [ "$SUPERVISE" != 1 ]; then
	ini_set "$GFX" FullScreen 0
	ini_set "$GFX" WindowResX 1280
	ini_set "$GFX" WindowResY 800
fi
db set AutoplayTurns "$TURNS" Status pending Turn -1 WorldSize "$WORLDSIZE" GameSpeed "$GAMESPEED" \
	Handicap "$HANDICAP" MapScript "$MAPSCRIPT" Civs "$CIVS" MinorCivs "$MINORCIVS" GameOptions "$GAMEOPTIONS" Mistakes "$MISTAKES" \
	SaveAs "$SAVEAS" LoadFile "$LOAD" Supervise "$SUPERVISE" SuperviseNotes 0

mkdir -p "$OUT"
marker=$OUT/.started
: > "$marker"
{
	echo "seed=$SEED turns=$TURNS size=$WORLDSIZE speed=$GAMESPEED handicap=$HANDICAP minors=$MINORCIVS"
	echo "map=$MAPSCRIPT"
	echo "civs=$CIVS"
	echo "options=$GAMEOPTIONS"
	echo "mistakes=$MISTAKES"
	echo "saveas=$SAVEAS load=$LOAD"
	echo "xvfb=$XVFB display=$GAME_DISPLAY env=$XVFB_ENV supervise=$SUPERVISE slot=$SLOT"
	echo "git=$(git -C "$ROOT" describe --always --dirty)"
	echo "dll=$(md5sum "$ROOT/CvGameCoreDLL_Expansion2/BuildOutput/VS2013_ModWin32/CvGameCore_Expansion2.dll" | cut -d' ' -f1)"
} > "$OUT/run.txt"

if [ -n "$SLOT" ]; then
	if ! cmp -s "$ROOT/steam-direct-launch.sh" "$LAUNCHER"; then
		cp "$ROOT/steam-direct-launch.sh" "$LAUNCHER.$$"
		chmod +x "$LAUNCHER.$$"
		mv "$LAUNCHER.$$" "$LAUNCHER"
	fi
	set -- "${PFX%/pfx}" "$XVFB_DISPLAY"
	for kv in $XVFB_ENV; do
		set -- "$@" "$kv"
	done
	setsid -f snap run --shell steam -c "exec \"\$HOME/civ5-direct-launch.sh\" \"\$@\"" sh "$@" > /dev/null 2>&1 < /dev/null
else
	setsid -f /snap/bin/steam -applaunch 8930 > /dev/null 2>&1 < /dev/null
fi
echo "launched, output in $OUT"

t0=$(date +%s)
last_turn=
last_change=$t0
iconified=
while :; do
	sleep 5
	status=$(db get Status)
	win=$(game_window)
	if [ "$XVFB" = 1 ] && [ -n "$win" ]; then
		rm -f "$ENVFILE"
	fi
	if [ "$XVFB" != 1 ] && [ "$SUPERVISE" != 1 ] && [ -n "$win" ] && [ "$win:$status" != "$iconified" ]; then
		iconify "$win"
		iconified=$win:$status
	fi
	turn=$(db get Turn)
	now=$(date +%s)
	case $status in
	done)
		echo "done at turn $turn after $((now - t0))s"
		break
		;;
	running)
		if [ "$SUPERVISE" = 1 ] && [ -z "$win" ]; then
			echo "game window closed at turn $turn"
			break
		fi
		if [ "$turn" != "$last_turn" ]; then
			last_turn=$turn
			last_change=$now
			echo "turn $turn ($((now - t0))s)"
		elif [ "$SUPERVISE" != 1 ] && [ $((now - last_change)) -gt "$TURN_TIMEOUT" ]; then
			echo "no progress at turn $turn for ${TURN_TIMEOUT}s, game left running" >&2
			exit 1
		fi
		;;
	*)
		if [ $((now - t0)) -gt "$START_TIMEOUT" ]; then
			echo "game did not start within ${START_TIMEOUT}s (status=$status), game left running" >&2
			exit 1
		fi
		;;
	esac
done

i=0
while [ "$(game_windows)" -ne 0 ] && [ $i -lt 60 ]; do
	sleep 2
	i=$((i + 1))
done
if [ "$(game_windows)" -ne 0 ]; then
	echo "game did not exit after the run" >&2
fi

find "$LOGS" -type f -newer "$marker" -exec cp -p {} "$OUT/" \;
rm -f "$marker"
echo "logs: $(find "$OUT" -type f | wc -l) files, $(du -sh "$OUT" | cut -f1)"

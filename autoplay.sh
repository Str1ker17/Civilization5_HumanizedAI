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
MAINGAME="$HOME/snap/steam/common/.local/share/Steam/steamapps/common/Sid Meier's Civilization V"
GAMEDIR=${GAMEDIR:-}
if [ -n "$SLOT" ] && [ -z "$GAMEDIR" ] && [ -d "$HOME/snap/steam/common/civ5-par/$SLOT/game" ]; then
	GAMEDIR=$HOME/snap/steam/common/civ5-par/$SLOT/game
fi
LAUNCHER=$HOME/snap/steam/common/civ5-direct-launch.sh
MYGAMES="$PFX/drive_c/users/steamuser/Documents/My Games/Sid Meier's Civilization 5"
CONFIG=$MYGAMES/config.ini
GFX=$MYGAMES/GraphicsSettingsDX9.ini
LOGS=$MYGAMES/Logs
DATA=$MYGAMES/ModUserData/HumanizedAI-1.db
export DISPLAY="${DISPLAY:-:0}"
SUPERVISE=${SUPERVISE:-0}
if [ "$SUPERVISE" = 1 ]; then
	XVFB=${XVFB:-0}
fi
XVFB=${XVFB:-1}
if [ -n "$SLOT" ]; then
	XVFB=1
fi
XVFB_DISPLAY=${XVFB_DISPLAY:-:99}
if [ -n "$SLOT" ] && [ -z "${XVFB_ENV+x}" ]; then
	XVFB_ENV="MESA_VK_WSI_DEBUG=sw DXVK_CONFIG=d3d9.presentInterval=0 WINEDLLOVERRIDES=winepulse.drv=d;winealsa.drv=d"
fi
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
COACH=${COACH:--1}
SAVEAS=${SAVEAS:-}
LOAD=${LOAD:-}
DUMP=${DUMP:-}
DUMP_FROM=${DUMP_FROM:-0}
DUMP_TO=${DUMP_TO:-0}
VIEW=${VIEW:-0}
BUILDERLOG=${BUILDERLOG:-0}
START_TIMEOUT=${START_TIMEOUT:-600}
TURN_TIMEOUT=${TURN_TIMEOUT:-600}
if [ -n "$SLOT" ]; then
	WINDOW_X=${WINDOW_X:-1024}
	WINDOW_Y=${WINDOW_Y:-768}
fi
WINDOW_X=${WINDOW_X:-1280}
WINDOW_Y=${WINDOW_Y:-800}
GAMEVIEW=${GAMEVIEW-}
if [ -n "$SLOT" ] && [ -z "${GAMEVIEW_SET+x}" ] && [ -z "$GAMEVIEW" ]; then
	GAMEVIEW=strategic
fi
WINDOW_TIMEOUT=${WINDOW_TIMEOUT:-180}
EXIT_TIMEOUT=${EXIT_TIMEOUT:-120}
START_RETRIES=${START_RETRIES:-2}
WINESERVER="$HOME/snap/steam/common/.local/share/Steam/steamapps/common/Proton 11.0/files/bin/wineserver"
OUT=${OUT:-"$ROOT/runs/$(date +%Y%m%d-%H%M%S)-s$SEED-t$TURNS"}

db() {
	python3 -I - "$DATA" "$@" <<'EOF'
import sqlite3
import sys
import time

args = sys.argv[2:]
for attempt in range(5):
    try:
        db = sqlite3.connect(sys.argv[1], timeout=60)
        db.execute('create table if not exists SimpleValues(Name TEXT Primary Key, Value VARIANT)')
        if args[0] == 'set':
            for name, value in zip(args[1::2], args[2::2]):
                if value.lstrip('-').isdigit():
                    value = int(value)
                db.execute('insert or replace into SimpleValues values (?, ?)', (name, value))
            db.commit()
        else:
            row = db.execute('select Value from SimpleValues where Name = ?', (args[1],)).fetchone()
            print('' if row is None else row[0])
        break
    except sqlite3.OperationalError:
        if attempt == 4:
            raise
        time.sleep(5)
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

close_game() {
	snap run --shell steam -c "WINEPREFIX=\"\$1\" \"\$2\" -k" sh "$PFX" "$WINESERVER" > /dev/null 2>&1 || true
	j=0
	while [ "$(game_windows)" -ne 0 ] && [ $j -lt 15 ]; do
		sleep 2
		j=$((j + 1))
	done
	if [ "$(game_windows)" -ne 0 ]; then
		echo "game on $GAME_DISPLAY did not close" >&2
		return 1
	fi
	echo "closed the game on $GAME_DISPLAY"
}

idle_game() {
	k=0
	while [ $k -lt 30 ]; do
		cg=$(cut -d: -f3 "/proc/$game_pid/cgroup" 2>/dev/null || true)
		case $cg in
		*/snap.steam.*.scope)
			systemctl --user set-property --runtime "${cg##*/}" CPUWeight=idle > /dev/null 2>&1 || true
			echo "game scope $cg"
			return 0
			;;
		esac
		sleep 1
		k=$((k + 1))
	done
	echo "no snap scope for the game, CPU weight not lowered" >&2
}

save_logs() {
	mkdir -p "$1"
	find "$LOGS" -type f -newer "$marker" -exec cp -p {} "$1/" \;
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
		systemd-run --user --scope -q -p CPUWeight=idle Xvfb "$XVFB_DISPLAY" -screen 0 1280x800x24 -nolisten tcp > /dev/null 2>&1 &
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
if [ -n "$SLOT" ]; then
	ini_set "$GFX" ShadowLevel 0
	ini_set "$GFX" TerrainDetailLevel 0
fi
if [ "$SUPERVISE" != 1 ] || [ "$XVFB" = 1 ]; then
	ini_set "$GFX" FullScreen 0
	ini_set "$GFX" WindowResX "$WINDOW_X"
	ini_set "$GFX" WindowResY "$WINDOW_Y"
fi
mkdir -p "$OUT"
marker=$OUT/.started
prepare() {
	db set AutoplayTurns "$TURNS" Status pending Turn -1 WorldSize "$WORLDSIZE" GameSpeed "$GAMESPEED" \
		Handicap "$HANDICAP" MapScript "$MAPSCRIPT" Civs "$CIVS" MinorCivs "$MINORCIVS" GameOptions "$GAMEOPTIONS" Mistakes "$MISTAKES" \
		SaveAs "$SAVEAS" LoadFile "$LOAD" Supervise "$SUPERVISE" SuperviseNotes 0 Coach "$COACH" CoachReplay 0 \
		Dump "$DUMP" DumpFrom "$DUMP_FROM" DumpTo "$DUMP_TO" DumpIndex "$DUMP_FROM" View "$VIEW" GameView "$GAMEVIEW"
	: > "$marker"
}
{
	echo "seed=$SEED turns=$TURNS size=$WORLDSIZE speed=$GAMESPEED handicap=$HANDICAP minors=$MINORCIVS"
	echo "map=$MAPSCRIPT"
	echo "civs=$CIVS"
	echo "options=$GAMEOPTIONS"
	echo "mistakes=$MISTAKES"
	echo "saveas=$SAVEAS load=$LOAD dump=$DUMP from=$DUMP_FROM to=$DUMP_TO view=$VIEW"
	echo "xvfb=$XVFB display=$GAME_DISPLAY env=$XVFB_ENV supervise=$SUPERVISE coach=$COACH slot=$SLOT window=${WINDOW_X}x$WINDOW_Y gameview=$GAMEVIEW"
	echo "git=$(git -C "$ROOT" describe --always --dirty)"
	echo "dll=$(md5sum "$ROOT/CvGameCoreDLL_Expansion2/BuildOutput/VS2013_ModWin32/CvGameCore_Expansion2.dll" | cut -d' ' -f1)"
	echo "game=${GAMEDIR:-$MAINGAME} gamedll=$(md5sum < "${GAMEDIR:-$MAINGAME}/Assets/DLC/Tournament Mod V12.3a + HumanizedAI/CvGameCore_Expansion2.dll" | cut -d' ' -f1)"
} > "$OUT/run.txt"

if [ -n "$SLOT" ] && ! cmp -s "$ROOT/steam-direct-launch.sh" "$LAUNCHER"; then
	cp "$ROOT/steam-direct-launch.sh" "$LAUNCHER.$$"
	chmod +x "$LAUNCHER.$$"
	mv "$LAUNCHER.$$" "$LAUNCHER"
fi
launch() {
	prepare
	if [ -n "$SLOT" ]; then
		set -- "${PFX%/pfx}" "$XVFB_DISPLAY"
		if [ -n "$GAMEDIR" ]; then
			set -- "$@" "CIV5_GAME=$GAMEDIR"
		fi
		for kv in $XVFB_ENV; do
			set -- "$@" "$kv"
		done
		setsid snap run --shell steam -c "exec \"\$HOME/civ5-direct-launch.sh\" \"\$@\"" sh "$@" > /dev/null 2>&1 < /dev/null &
		game_pid=$!
		idle_game
	else
		setsid -f /snap/bin/steam -applaunch 8930 > /dev/null 2>&1 < /dev/null
	fi
	echo "launched, output in $OUT"
	t0=$(date +%s)
	last_turn=
	last_change=$t0
	seen=
	gone=0
}

attempt=1
iconified=
launch
while :; do
	sleep 5
	status=$(db get Status)
	win=$(game_window)
	if [ "$(game_windows)" -ne 0 ]; then
		seen=1
		gone=0
	elif [ -n "$seen" ]; then
		gone=$((gone + 1))
	fi
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
	running | reloading)
		if [ "$SUPERVISE" = 1 ] && [ -z "$win" ]; then
			echo "game window closed at turn $turn"
			break
		fi
		if [ "$gone" -ge 3 ]; then
			echo "game window gone at turn $turn" >&2
			save_logs "$OUT"
			exit 1
		fi
		if [ "$turn" != "$last_turn" ]; then
			last_turn=$turn
			last_change=$now
			echo "turn $turn ($((now - t0))s)"
		elif [ "$SUPERVISE" != 1 ] && [ $((now - last_change)) -gt "$TURN_TIMEOUT" ]; then
			echo "no progress at turn $turn for ${TURN_TIMEOUT}s" >&2
			save_logs "$OUT"
			if [ -n "$SLOT" ] && [ "$VIEW" != 1 ]; then
				close_game || true
			else
				echo "game left running" >&2
			fi
			exit 1
		fi
		;;
	*)
		why=
		if [ "$gone" -ge 3 ]; then
			why="game window gone before the start"
		elif [ -z "$seen" ] && [ $((now - t0)) -gt "$WINDOW_TIMEOUT" ]; then
			why="no game window within ${WINDOW_TIMEOUT}s"
		elif [ $((now - t0)) -gt "$START_TIMEOUT" ]; then
			why="game did not start within ${START_TIMEOUT}s"
		fi
		if [ -n "$why" ]; then
			echo "$why (status=$status, attempt $attempt)" >&2
			save_logs "$OUT/start-fail-$attempt"
			if [ -z "$SLOT" ]; then
				if [ "$(game_windows)" -ne 0 ]; then
					echo "game left running" >&2
				fi
				exit 1
			fi
			close_game || exit 1
			if [ "$attempt" -gt "$START_RETRIES" ]; then
				exit 1
			fi
			attempt=$((attempt + 1))
			launch
		fi
		;;
	esac
done

i=0
while [ "$(game_windows)" -ne 0 ] && [ $((i * 2)) -lt "$EXIT_TIMEOUT" ]; do
	sleep 2
	i=$((i + 1))
done
save_logs "$OUT"
rm -f "$marker"
if [ "$(game_windows)" -ne 0 ]; then
	echo "game did not exit after the run" >&2
	if [ -n "$SLOT" ]; then
		close_game || true
	fi
fi
echo "logs: $(find "$OUT" -type f | wc -l) files, $(du -sh "$OUT" | cut -f1)"

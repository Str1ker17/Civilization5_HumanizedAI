#!/bin/sh
set -u
N=${1:?usage: qworker.sh SLOTNUMBER}
R=$(cd "$(dirname "$0")" && pwd)
RUNS=${RUNS:-$R/runs}
QDIR=${QDIR:-$RUNS/queue}
Q=$QDIR/day-queue.txt
MOD="Assets/DLC/Tournament Mod V12.3a + HumanizedAI/CvGameCore_Expansion2.dll"
mkdir -p "$QDIR" "$RUNS/bench-logs"
touch "$Q"
while :; do
	job=$(flock "$Q.lock" sh -c "head -n 1 \"\$1\"; sed -i 1d \"\$1\"" sh "$Q")
	if [ -z "$job" ]; then [ -e "$QDIR/day-queue.stop" ] && break; sleep 30; continue; fi
	read -r name mode map seed dll <<JOB
$job
JOB
	case $mode in
	peace) opts="GAMEOPTION_AI_TWEAKS=0 GAMEOPTION_NO_BARBARIANS=1 GAMEOPTION_ALWAYS_PEACE=1" ;;
	barbp) opts="GAMEOPTION_AI_TWEAKS=0 GAMEOPTION_ALWAYS_PEACE=1" ;;
	ragep) opts="GAMEOPTION_AI_TWEAKS=0 GAMEOPTION_ALWAYS_PEACE=1 GAMEOPTION_RAGING_BARBARIANS=1" ;;
	duelr) opts="GAMEOPTION_AI_TWEAKS=0 GAMEOPTION_RAGING_BARBARIANS=1 GAMEOPTION_NO_ESPIONAGE=1 GAMEOPTION_NO_LEAGUES=1 GAMEOPTION_DUEL_STUFF=1 GAMEOPTION_TOURNAMENT_MODE=1 GAMEOPTION_LIMITATION_COMBAT_EXPERIENCE=1 GAMEOPTION_LIMITATION_NON_AGGRESSION_PACTS=1 GAMEOPTION_LIMITATION_RA=1 GAMEOPTION_EXPENSIVE_SCIENTISTS_FOR_FAITH=1 GAMEOPTION_RESTRICTION_ON_LIBERATION_OF_CS=1" ;;
	dueln) opts="GAMEOPTION_AI_TWEAKS=0 GAMEOPTION_NO_BARBARIANS=1 GAMEOPTION_NO_ESPIONAGE=1 GAMEOPTION_NO_LEAGUES=1 GAMEOPTION_DUEL_STUFF=1 GAMEOPTION_TOURNAMENT_MODE=1 GAMEOPTION_LIMITATION_COMBAT_EXPERIENCE=1 GAMEOPTION_LIMITATION_NON_AGGRESSION_PACTS=1 GAMEOPTION_LIMITATION_RA=1 GAMEOPTION_EXPENSIVE_SCIENTISTS_FOR_FAITH=1 GAMEOPTION_RESTRICTION_ON_LIBERATION_OF_CS=1" ;;
	*) echo "bad mode $mode"; continue ;;
	esac
	case $map in
	tpan) script='Assets\Maps\Pangaea.lua' ;;
	tfra) script='Assets\Maps\Fractal.lua' ;;
	*) echo "bad map $map"; continue ;;
	esac
	mistakes="1=HANDICAP_DEITY,2=HANDICAP_DEITY,3=HANDICAP_DEITY,4=HANDICAP_DEITY"
	[ "$name" = van ] && mistakes=
	want=$(md5sum < "$dll" | cut -d' ' -f1)
	if [ "$(md5sum < "$HOME/snap/steam/common/civ5-par/p$N/game/$MOD" | cut -d' ' -f1)" != "$want" ]; then
		"$R/slotgame.sh" "p$N" "$dll" > /dev/null
	fi
	out=$RUNS/b8-$name-$mode-$map-s$seed
	if SLOT=p$N XVFB_DISPLAY=:$((99 + N)) SEED=$seed TURNS=200 WORLDSIZE=WORLDSIZE_TINY MAPSCRIPT="$script" \
		CIVS=CIVILIZATION_ROME,CIVILIZATION_GREECE,CIVILIZATION_EGYPT,CIVILIZATION_CHINA MINORCIVS=4 \
		MISTAKES="$mistakes" GAMEOPTIONS="$opts" OUT="$out" "$R/autoplay.sh" >> "$RUNS/bench-logs/$name-$mode-$map-p$N.log" 2>&1; then
		echo "$name $mode $map seed $seed done (p$N)"
	else
		echo "$name $mode $map seed $seed failed (p$N)"
	fi
	echo "$want" > "$out/dll.md5"
done
echo "worker p$N done"

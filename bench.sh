#!/bin/sh
cd "$(dirname "$0")" || exit 1
NAME=${1:?usage: bench.sh NAME}
SLOTS=${SLOTS:-4}
SEEDS=${SEEDS:-"1 2 3 4 5 6 7 8"}
TURNS=${TURNS:-100}
GAMEOPTIONS=${GAMEOPTIONS:-"GAMEOPTION_AI_TWEAKS=0 GAMEOPTION_RAGING_BARBARIANS=1"}
MISTAKES=${MISTAKES-1=HANDICAP_DEITY,2=HANDICAP_DEITY,3=HANDICAP_DEITY,4=HANDICAP_DEITY,5=HANDICAP_DEITY,6=HANDICAP_DEITY}
LOGDIR=runs/bench-logs
mkdir -p "$LOGDIR"

run_slot() {
	slot=$1
	for s in $2; do
		if SLOT=p$slot XVFB_DISPLAY=:$((99 + slot)) SEED=$s TURNS=$TURNS MISTAKES=$MISTAKES GAMEOPTIONS="$GAMEOPTIONS" OUT=runs/b8-$NAME-s$s \
			./autoplay.sh >> "$LOGDIR/$NAME-p$slot.log" 2>&1; then
			echo "seed $s done (p$slot)"
		else
			echo "seed $s failed (p$slot)"
		fi
	done
}

slot=1
while [ "$slot" -le "$SLOTS" ]; do
	list=
	j=0
	for s in $SEEDS; do
		if [ $((j % SLOTS + 1)) -eq "$slot" ]; then
			list="$list $s"
		fi
		j=$((j + 1))
	done
	run_slot "$slot" "$list" &
	slot=$((slot + 1))
	sleep 10
done
wait
echo "batch done"

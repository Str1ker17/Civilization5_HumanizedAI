#!/bin/sh
R=$(cd "$(dirname "$0")" && pwd)
QDIR=${QDIR:-${RUNS:-$R/runs}/queue}
mkdir -p "$QDIR"
for n in "$@"; do
	nice -n 19 ionice -c 3 "$R/qworker.sh" "$n" >> "$QDIR/day.log" 2>&1 &
	sleep 2
done
wait
echo "qpool done" >> "$QDIR/day.log"

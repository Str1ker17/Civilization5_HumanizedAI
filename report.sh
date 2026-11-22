#!/bin/sh
cd "$(dirname "$0")" || exit 1
N=${1:?usage: report.sh NAME}
for r in van r-final "$N"; do
	printf '%-10s %s\n' "$r" "$(python3 losses.py runs/b8-"$r"-s[1-8] | tail -1 | sed 's/TOTAL *//')"
	printf '%-10s %s\n' "" "$(python3 settlers.py runs/b8-"$r"-s[1-8] | tail -2 | tr '\n' ' ')"
	printf '%-10s %s\n' "" "$(python3 tiles.py runs/b8-"$r"-s[1-8] | tail -1 | sed 's/turn 100 players [0-9]*: //')"
done
for b in r-final van; do
	echo "== $b -> $N (T99)"
	python3 compare.py runs/b8-"$b"-s[1-8] -- runs/b8-"$N"-s[1-8] | grep -E "# Cities|^Pop|Food|Production|Science|Culture|Num Techs|Improved|# Workers|Net Happiness" | grep " 99 " | awk '{printf "%s%s %s; ", $1, ($2 ~ /^[0-9]/ ? "" : " " $2), $NF} END {print ""}'
done

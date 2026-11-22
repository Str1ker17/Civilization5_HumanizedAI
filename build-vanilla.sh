#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p runs
stashed=0
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
	git stash push -m "wip before vanilla build"
	stashed=1
fi
git checkout main -- CvGameCoreDLL_Expansion2
./build.sh > runs/build-vanilla.log 2>&1 || echo "vanilla build failed, see runs/build-vanilla.log"
cp CvGameCoreDLL_Expansion2/BuildOutput/VS2013_ModWin32/CvGameCore_Expansion2.dll runs/vanilla.dll
git checkout HEAD -- CvGameCoreDLL_Expansion2
if [ "$stashed" = 1 ]; then
	git stash pop
fi
md5sum runs/vanilla.dll

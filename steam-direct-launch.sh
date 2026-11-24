#!/bin/sh
STEAM=$HOME/.local/share/Steam
APPS=$STEAM/steamapps
PROTON="$APPS/common/Proton 11.0"
SLR="$APPS/common/SteamLinuxRuntime_4"

export STEAM_COMPAT_DATA_PATH="$1"
export DISPLAY="$2"
shift 2
for kv in "$@"; do
	export "${kv?}"
done
GAME=${CIV5_GAME:-"$APPS/common/Sid Meier's Civilization V"}
unset CIV5_GAME
unset WAYLAND_DISPLAY

export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM"
export STEAM_COMPAT_INSTALL_PATH="$GAME"
export STEAM_COMPAT_LIBRARY_PATHS="$APPS"
export STEAM_COMPAT_TOOL_PATHS="$PROTON:$SLR"
export STEAM_COMPAT_MOUNTS="$APPS/common/Steamworks Shared:$PROTON:$SLR"
export STEAM_COMPAT_APP_ID=8930
export SteamAppId=8930
export SteamGameId=8930
export STEAM_COMPAT_FLAGS=search-cwd
export STEAM_COMPAT_PROTON=1

cd "$GAME" || exit 1
exec "$SLR/_v2-entry-point" --verb=waitforexitandrun -- "$PROTON/proton" waitforexitandrun "$GAME/CivilizationV.exe"

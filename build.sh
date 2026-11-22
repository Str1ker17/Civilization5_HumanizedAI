#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
SRC=$ROOT/CvGameCoreDLL_Expansion2
PROJ=$SRC/_build_gh_actions.vcxproj
TC=$ROOT/.toolchain
PROTON=${PROTON:-$HOME/snap/steam/common/.local/share/Steam/steamapps/common/Proton 11.0/files}
WINE=$PROTON/bin/wine

OUT=BuildOutput/VS2013_ModWin32
TMP=BuildTemp/VS2013_CvGameCoreDLL_Expansion2ModWin32
DLL=$OUT/CvGameCore_Expansion2.dll
PCH=$TMP/CvGameCore_Expansion2.pch
MANIFEST=$TMP/CvGameCore_Expansion2.dll.intermediate.manifest

if [ ! -x "$WINE" ]; then
	echo "wine not found: $WINE (set PROTON=.../files)" >&2
	exit 1
fi
for d in vc9 sdk sdk71; do
	if [ ! -d "$TC/$d" ]; then
		echo "toolchain missing: $TC/$d" >&2
		exit 1
	fi
done

export WINEPREFIX="$TC/wineprefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES='mscoree,mshtml=;winedbg.exe=d'

winpath() {
	"$WINE" winepath -w "$1" 2>/dev/null | tr -d '\r'
}

VC=$(winpath "$TC/vc9/Program Files/Microsoft Visual Studio 9.0")
SDK=$(winpath "$TC/sdk71/Program Files/Microsoft SDKs/Windows/v7.1")
FWSDK=$(winpath "$TC/sdk/Program Files/Microsoft SDKs/Windows/v6.0A")
DROOT='D:\a\Civ5-Patch\Civ5-Patch'
DSRC="$DROOT\\CvGameCoreDLL_Expansion2"
SQLITE="$DSRC\\ThirdPartyLibs\\winsqlite3\\"

mkdir -p "$TC/ddrive/a/Civ5-Patch"
ln -sfn "$ROOT" "$TC/ddrive/a/Civ5-Patch/Civ5-Patch"
ln -sfn ../../ddrive "$WINEPREFIX/dosdevices/d:"

export WINEPATH="$VC\\VC\\bin;$SDK\\Bin;$VC\\Common7\\IDE"
export INCLUDE="$SQLITE;$VC\\VC\\include;$VC\\VC\\atlmfc\\include;$SDK\\Include;$FWSDK\\Include"
export LIB="$SQLITE;$VC\\VC\\lib;$VC\\VC\\atlmfc\\lib;$SDK\\Lib;$FWSDK\\Lib"

cd "$SRC"
mkdir -p "$OUT" "$TMP"

sources=$(sed -n 's/.*<ClCompile Include="\([^"]*\)".*/\1/p' "$PROJ" | sed 's|\\|/|g')
headers=$(find . -path ./BuildOutput -prune -o -path ./BuildTemp -prune -o -type f \( -name '*.h' -o -name '*.inl' \) -print | sed 's|^\./||' | tr '\n' ' ')

{
	cat <<EOF
builddir = $TMP
wine = "$WINE"
cflags = /c '/I$DSRC\\CvWorldBuilderMap\\include\\' '/I$DSRC\\CvGameCoreDLLUtil\\include\\' \$
    '/I$DSRC\\CvLocalization\\include\\' '/I$DSRC\\CvGameDatabase\\include\\' '/I$DSRC\\FirePlace\\include\\' \$
    '/I$DSRC\\FirePlace\\include\\FireWorks\\' '/I$DSRC\\ThirdPartyLibs\\Lua51\\include\\' \$
    /Zi /nologo /W3 /WX- /Ox /Ob2 /Oi /Oy /DFXS_IS_DLL /DWIN32 /DNDEBUG /D_WINDOWS /D_USRDLL \$
    /DCVGAMECOREDLL_EXPORTS /DFINAL_RELEASE /D_CRT_SECURE_NO_WARNINGS /D_WINDLL /D_MBCS /Gm- /MD /GS- /Gy \$
    /fp:strict /Zc:wchar_t /Zc:forScope
cflags2 = /Fd$TMP/vc90.pdb /Gd /TP /errorReport:queue /EHs /EHc '/I$SQLITE' "/I$VC\\VC\\include" \$
    "/I$VC\\VC\\atlmfc\\include" "/I$SDK\\Include" "/I$FWSDK\\Include" /X
libs = CvWorldBuilderMap/lib/CvWorldBuilderMapWin32.lib CvGameCoreDLLUtil/lib/CvGameCoreDLLUtilWin32.lib \$
    CvLocalization/lib/CvLocalizationWin32.lib CvGameDatabase/lib/CvGameDatabaseWin32.lib \$
    FirePlace/lib/FireWorksWin32.lib FirePlace/lib/FLuaWin32.lib ThirdPartyLibs/Lua51/lib/lua51_Win32.lib \$
    winmm.lib kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib \$
    ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib

rule pch
  command = \$wine cl.exe \$cflags /YcCvGameCoreDLLPCH.h /Fp$PCH /Fo$TMP/_precompile.obj \$cflags2 _precompile.cpp \$
    > $TMP/_precompile.log 2>&1; s=\$\$?; cat $TMP/_precompile.log; exit \$\$s
  description = PCH \$in

rule cc
  command = \$wine cl.exe \$cflags /YuCvGameCoreDLLPCH.h /Fp$PCH /Fo\$out \$cflags2 '\$wsrc' \$
    > \$out.log 2>&1; s=\$\$?; cat \$out.log; exit \$\$s
  description = CC \$in

rule rc
  command = \$wine rc.exe /nologo /fo\$out \$in
  description = RC \$in

rule link
  command = { \$wine link.exe @\$out.rsp && \$wine mt.exe /nologo /verbose '/outputresource:\$out;#2' \$
    /manifest $MANIFEST; } > \$out.log 2>&1; s=\$\$?; cat \$out.log; exit \$\$s
  rspfile = \$out.rsp
  rspfile_content = /OUT:\$out /INCREMENTAL:NO /NOLOGO \$libs /DEF:CvGameCoreDLL.def \$
    /MANIFEST /MANIFESTFILE:$MANIFEST "/MANIFESTUAC:level='asInvoker' uiAccess='false'" /DEBUG \$
    /PDB:$OUT/CvGameCore_Expansion2.pdb /SUBSYSTEM:WINDOWS /LARGEADDRESSAWARE /OPT:REF /OPT:ICF /TLBID:1 \$
    /DYNAMICBASE:NO /IMPLIB:$OUT/CvGameCore_Expansion2.lib /MACHINE:X86 /DLL \$in /ignore:4099 /PDBALTPATH:%_PDB%
  description = LINK \$out

build $TMP/_precompile.obj $PCH: pch _precompile.cpp | $headers
build $TMP/CvGameCoreDLL.res: rc CvGameCoreDLL.rc | resource.h
EOF
	objs=
	for s in $sources; do
		o=$TMP/$(basename "$s" .cpp).obj
		objs="$objs $o"
		[ "$s" = _precompile.cpp ] && continue
		printf 'build %s: cc %s | %s\n  wsrc = %s\n' "$o" "$s" "$PCH" "$(printf '%s' "$s" | sed 's|/|\\|g')"
	done
	printf 'build %s: link %s %s/CvGameCoreDLL.res | CvGameCoreDLL.def\n' "$DLL" "$objs" "$TMP"
	printf 'default %s\n' "$DLL"
} > "$TMP/build.ninja"

exec ninja -f "$TMP/build.ninja" "$@"

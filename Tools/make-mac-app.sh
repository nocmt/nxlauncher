#!/bin/bash
# Package the nxnative Mac host as a double-clickable macOS .app -- for ANY game that has a profile.
#
# Why a Mac .app at all: the IPA holds an iOS binary (arm64-apple-ios), which macOS cannot execute.
# The Mac host (dm/host/dmhost) is the same rewriter + Metal replay layer + shader chain, built for
# macOS, and the Mac front end maps the keyboard and the mouse (as a touchscreen) and draws the
# on-screen gamepad overlay. So the .app is the same game, native on the Mac.
#
# Everything the game needs comes out of the profile in dm/games/<title id>/ and the work folder the
# packing script made (the extracted game files, the rewritten modules, the shader libraries).
#
# Usage:
#   make-mac-app.sh --game <title id> --work <build dir> --ver <version> --out <app path>
#                   [--name <bundle name>] [--display <display name>] [--bundle-id <id>]
#                   [--dlc <dir>] [--support <folder name>] [--mem-pool <hex>] [--mem-reserve <hex>]
#                   [--repo <path>] [--python <path>]
#
#   --game        the base game's title ID (the profile's folder name in dm/games/)
#   --work        the work folder: <id>_build (extract/, patched_<ver>/, shader/cache/)
#   --ver         the packed version, e.g. v1114112 (the folder names under extract/ and patched_*)
#   --out         the .app to write (the folder is replaced)
#   --name        the bundle name (default: the profile's ipa base name, e.g. "BotW Native")
#   --display     the name in the menu bar and the window title (default: the profile's name)
#   --bundle-id   the bundle identifier (default: org.nxnative.<title id in lowercase>.mac)
#   --dlc         a folder holding the add-on content: <index>/RomFS per DLC (optional)
#   --support     the Application Support folder (default: the bundle name); saves and log.txt live there
#   --mem-pool    the memory the game is told it has (default: the profile's app_pool)
#   --mem-reserve the address space reserved for it (default: the profile's mem_reserve)
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
REPO=$ROOT/nxnative
GAME=""; WORK=""; VER=""; OUT=""; NAME=""; DISPLAY=""; BUNDLE_ID=""; DLC=""; SUPPORT=""
MEM_POOL=""; MEM_RESERVE=""; PY=""

fail() { echo "FAIL: $*" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --game) GAME=$2; shift 2;;
    --work) WORK=$2; shift 2;;
    --ver) VER=$2; shift 2;;
    --out) OUT=$2; shift 2;;
    --name) NAME=$2; shift 2;;
    --display) DISPLAY=$2; shift 2;;
    --bundle-id) BUNDLE_ID=$2; shift 2;;
    --dlc) DLC=$2; shift 2;;
    --support) SUPPORT=$2; shift 2;;
    --mem-pool) MEM_POOL=$2; shift 2;;
    --mem-reserve) MEM_RESERVE=$2; shift 2;;
    --repo) REPO=$2; shift 2;;
    --python) PY=$2; shift 2;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) fail "unknown option $1";;
  esac
done
[ -n "$GAME" ] && [ -n "$WORK" ] && [ -n "$VER" ] && [ -n "$OUT" ] || fail "--game, --work, --ver and --out are required"
[ -d "$REPO/dm/games/$GAME" ] || fail "no profile for $GAME (dm/games/$GAME)"

PROF=$REPO/dm/games/$GAME
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# A Python with PIL (the .icns is written by hand, because sips cannot write to the sandboxed TMPDIR)
if [ -z "$PY" ]; then
  for c in /Users/guxiu/Library/miniforge3/bin/python3 python3 /opt/homebrew/bin/python3; do
    if [ -x "$c" ] && "$c" -c "import PIL" >/dev/null 2>&1; then PY="$c"; break; fi
  done
fi
PY=${PY:-/usr/bin/python3}

# The profile's values (name, version, memory split). game.tsv: key<TAB>value...
prof() { sed -n "s/^$1[[:space:]]\{1,\}//p" "$PROF/game.tsv" | head -1; }
GAME_NAME=$(prof name)
BUILD_LINE=$(prof build)
GAME_VERSION=$(printf '%s' "$BUILD_LINE" | awk '{print $2}')
IPA_NAME=$(prof ipa)
[ -n "$GAME_NAME" ] || fail "the profile has no name"
[ -n "$GAME_VERSION" ] || GAME_VERSION=1.0
NAME=${NAME:-${IPA_NAME%.ipa}}
DISPLAY=${DISPLAY:-$GAME_NAME}
BUNDLE_ID=${BUNDLE_ID:-org.nxnative.$(printf '%s' "$GAME" | tr 'A-Z' 'a-z').mac}
SUPPORT=${SUPPORT:-$NAME}
MEM_POOL=${MEM_POOL:-$(prof app_pool)}
MEM_RESERVE=${MEM_RESERVE:-$(prof mem_reserve)}
CHAIN=$(sed -n 's/^#define DMSH_CHAIN "\(.*\)"/\1/p' "$PROF/dmsh_chain.h")
[ -n "$CHAIN" ] || fail "the profile has no DMSH_CHAIN (dmsh_chain.h)"

RES="$OUT/Contents/Resources"
echo "=== packaging the Mac .app ==="
echo "game   : $GAME ($GAME_NAME $GAME_VERSION)"
echo "work   : $WORK"
echo "app    : $OUT"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$RES/dm" "$RES/font" "$RES/msl"

# --- the host ---
echo "[1] the Mac host ..."
( cd "$REPO/dm/host" && make -s GAME="$GAME" dmhost ) || { echo "FAIL: the host did not build"; exit 1; }
# In Contents/MacOS, next to the launcher: after the launcher's exec the process is still inside the bundle, so
# macOS resolves the bundle for it and the window and the Dock entry show the app's own icon. A host outside
# Contents/MacOS would be a bare executable and macOS would show the generic "exec" icon instead.
cp "$REPO/dm/host/dmhost" "$OUT/Contents/MacOS/dmhost"
chmod +x "$OUT/Contents/MacOS/dmhost"
echo "    $(ls -la "$OUT/Contents/MacOS/dmhost" | awk '{print $5}') bytes"

# --- the rewritten modules ---
echo "[2] the rewritten modules ..."
[ -d "$WORK/patched_$VER" ] || fail "no $WORK/patched_$VER (the rewrite stage did not run)"
cp -R "$WORK/patched_$VER" "$RES/patched"
echo "    $(ls "$RES/patched" | wc -l | tr -d ' ') files"

# --- the shader tables (the host looks for them beside DM_NVN_SHMAP) ---
echo "[3] the shader tables ..."
for t in shader_map.tsv pso_manifest.tsv c1_full.tsv; do
  [ -f "$PROF/$t" ] && cp "$PROF/$t" "$RES/dm/" || echo "    (no $t in the profile)"
done

# --- the macOS shader libraries ---
echo "[4] the macOS shader libraries (APFS clone) ..."
[ -d "$WORK/shader/cache/b-$CHAIN" ] || fail "no $WORK/shader/cache/b-$CHAIN (the shader stage did not run)"
cp -cR "$WORK/shader/cache/b-$CHAIN" "$RES/msl/b-$CHAIN"
echo "    $(find "$RES/msl" -name '*.metallib' | wc -l | tr -d ' ') metallibs"

# --- the game files ---
echo "[5] the game files (APFS clone) ..."
[ -d "$WORK/extract/$VER/RomFS" ] || fail "no $WORK/extract/$VER/RomFS (the extract stage did not run)"
cp -cR "$WORK/extract/$VER/RomFS" "$RES/romfs"
echo "    $(find "$RES/romfs" -type f | wc -l | tr -d ' ') files"

# --- the shared-font stand-ins ---
echo "[6] the fonts ..."
FONT_DIR="$REPO/dm/ios/Gen/dm/font"
if [ -f "$FONT_DIR/standard.ttf" ] && [ -f "$FONT_DIR/nintendo_ext.ttf" ]; then
  cp "$FONT_DIR/standard.ttf" "$FONT_DIR/nintendo_ext.ttf" "$RES/font/"
else
  echo "    (no fonts at $FONT_DIR -- the game may show no text)"
fi

# --- the icon (the game's own icon.jpg, written as .icns by make-icns.py) ---
echo "[7] the icon ..."
ICON_SRC="$WORK/extract/$VER/icon.jpg"
if [ -f "$ICON_SRC" ] && "$PY" -c "import PIL" >/dev/null 2>&1; then
  "$PY" "$HERE/make-icns.py" "$ICON_SRC" "$RES/AppIcon.icns" || echo "    (the icon could not be written)"
  [ -f "$RES/AppIcon.icns" ] && echo "    AppIcon.icns $(ls -la "$RES/AppIcon.icns" | awk '{print $5}') bytes" || echo "    (no icon)"
else
  echo "    (no icon.jpg, or no Python with PIL)"
fi

# --- the add-on content (DLC): Resources/aoc/<index>/ holds the RomFS of one DLC ---
# The host reports every numbered folder as an owned add-on content (aoc::ListAddOnContent)
# and mounts it read-only when the game asks for it (fs::MountAddOnContent -> DM_AOC_DIR/<index>).
echo "[8] the add-on content ..."
if [ -n "$DLC" ] && [ -d "$DLC" ]; then
  for d in "$DLC"/*/; do
    idx=$(basename "$d")
    [ -d "$d/RomFS" ] || continue
    mkdir -p "$RES/aoc"
    cp -cR "$d/RomFS" "$RES/aoc/$idx"
    echo "    aoc/$idx: $(find "$RES/aoc/$idx" -type f | wc -l | tr -d ' ') files"
  done
else
  echo "    (none)"
fi

# --- the launcher: a real Mach-O binary (LaunchServices refuses a bundle whose CFBundleExecutable
#     is a shell script), it sets the environment and execs the host ---
echo "[9] the launcher ..."
clang -O2 -DAPP_SUPPORT_NAME="\"$SUPPORT\"" -DAPP_MEM_POOL="\"$MEM_POOL\"" -DAPP_MEM_RESERVE="\"$MEM_RESERVE\"" \
  -o "$OUT/Contents/MacOS/BotW" "$HERE/launcher.c" || { echo "FAIL: the launcher did not build"; exit 1; }
chmod +x "$OUT/Contents/MacOS/BotW"
file "$OUT/Contents/MacOS/BotW" | sed 's/^/    /'

# --- Info.plist ---
"$PY" "$HERE/make-info-plist.py" "$OUT/Contents/Info.plist" "$NAME" "$DISPLAY" "$BUNDLE_ID" "$GAME_VERSION" "26.0" || exit 1
plutil -lint "$OUT/Contents/Info.plist" >/dev/null || { echo "FAIL: the Info.plist is not well-formed"; exit 1; }

# A bundle whose executable is a script cannot be code-signed, and a locally built bundle carries no
# quarantine attribute, so it opens as it is (no Gatekeeper prompt).

echo
echo "=== the app ==="
du -sh "$OUT"
echo
echo "run it with:  open \"$OUT\""
echo "logs / saves : ~/Library/Application Support/$SUPPORT/"

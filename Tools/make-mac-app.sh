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
#   --out         the .app to write (must not already exist)
#   --name        the bundle name (default: the profile's ipa base name, e.g. "BotW Native")
#   --display     the name in the menu bar and the window title (default: the profile's name)
#   --bundle-id   the bundle identifier (default: org.nxnative.<title id in lowercase>.mac)
#   --dlc         extracted add-on content: <index>/ files or <index>/RomFS/ (optional)
#   --support     the Application Support folder (default: nxnative/<title id> — a fixed per-game home
#                 that survives renaming the .app); saves and log.txt live there
#   --mem-pool    the memory the game is told it has (default: the profile's app_pool)
#   --mem-reserve the address space reserved for it (default: the profile's mem_reserve)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
REPO=$ROOT/nxnative
GAME=""; WORK=""; VER=""; OUT=""; NAME=""; DISPLAY=""; BUNDLE_ID=""; DLC=""; SUPPORT=""
MEM_POOL=""; MEM_RESERVE=""; PY=""; GRAPHICS_API=${GFXAPI:-auto}

clone_tree() {
  # cp may leave a partial destination when clonefile is unsupported.
  if ! cp -cR "$1" "$2" 2>/dev/null; then
    rm -rf "$2"
    cp -R "$1" "$2"
  fi
}

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
    --graphics-api) GRAPHICS_API=$2; shift 2;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) fail "unknown option $1";;
  esac
done
[ -n "$GAME" ] && [ -n "$WORK" ] && [ -n "$VER" ] && [ -n "$OUT" ] || fail "--game, --work, --ver and --out are required"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export DM_GAMES_DIR="$WORK/profile${DM_GAMES_DIR:+:$DM_GAMES_DIR}"
if [ -f "$WORK/profile/$GAME/game.tsv" ]; then export DM_GAMES_FIRST=1; fi
PROF=$(python3 "$REPO/dm/games/game.py" dir "$GAME") || fail "no profile for $GAME (including $WORK/profile)"
[ -f "$PROF/game.tsv" ] || fail "no profile at $PROF/game.tsv"

# A Python with PIL (the .icns is written by hand, because sips cannot write to the sandboxed TMPDIR).
# NXLAUNCHER_PYTHON is the launcher's own Python (the app carries one); its packages are on the
# PYTHONPATH, so the check below sees the Pillow there.
if [ -z "$PY" ]; then
  for c in "${NXLAUNCHER_PYTHON:-}" "$ROOT/.venv/bin/python3" "$(command -v python3 || true)" /opt/homebrew/bin/python3; do
    [ -n "$c" ] || continue
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
# The support folder: a fixed per-game home nxnative/<title id> (the id is baked into the bundle, the
# folder's name does not follow the .app), falling back to the bundle name when there is no id. The
# launcher also gets the bundle name as APP_LEGACY_SUPPORT_NAME: exports before this kept the saves
# there, and the launcher moves that folder over on the first run.
if [ -z "$SUPPORT" ] && [ -n "$GAME" ]; then SUPPORT="nxnative/$GAME"; fi
SUPPORT=${SUPPORT:-$NAME}
MEM_POOL=${MEM_POOL:-$(prof app_pool)}
MEM_RESERVE=${MEM_RESERVE:-$(prof mem_reserve)}
SHADER_LIBRARY=$("$PY" "$HERE/shader_chain.py" --repo "$REPO" --profile "$PROF" --game "$GAME" \
  --resources --work "$WORK" --target mac --graphics-api "$GRAPHICS_API") || fail "shader cache is not compatible with the host and profile"
SHADER_NAME=$(basename "$SHADER_LIBRARY")
MIN_MACOS=11.0
case "$SHADER_NAME" in b-*) MIN_MACOS=26.0;; esac

[ ! -e "$OUT" ] || fail "output already exists: $OUT"
mkdir -p "$(dirname "$OUT")"
FINAL_OUT=$OUT
STAGING=$(mktemp -d "$(dirname "$OUT")/.nxlauncher-export.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT INT TERM
OUT="$STAGING/$(basename "$FINAL_OUT")"
RES="$OUT/Contents/Resources"
echo "=== packaging the Mac .app ==="
echo "game   : $GAME ($GAME_NAME $GAME_VERSION)"
echo "work   : $WORK"
echo "app    : $OUT"

[ ! -e "$OUT" ] || fail "output already exists: $OUT"
mkdir -p "$OUT/Contents/MacOS" "$RES/dm" "$RES/font" "$RES/msl"

# --- the host ---
echo "[1] the Mac host ..."
if [ -f "$WORK/.nxlauncher/dmhost" ]; then
  HOST="$WORK/.nxlauncher/dmhost"
else
  ( cd "$REPO/dm/host" && make -s GAME="$GAME" dmhost ) || fail "the host did not build"
  HOST="$REPO/dm/host/dmhost"
fi
# In Contents/MacOS, next to the launcher: after the launcher's exec the process is still inside the bundle, so
# macOS resolves the bundle for it and the window and the Dock entry show the app's own icon. A host outside
# Contents/MacOS would be a bare executable and macOS would show the generic "exec" icon instead.
cp "$HOST" "$OUT/Contents/MacOS/dmhost"
chmod +x "$OUT/Contents/MacOS/dmhost"
echo "    $(ls -la "$OUT/Contents/MacOS/dmhost" | awk '{print $5}') bytes"

# --- the rewritten modules ---
echo "[2] the rewritten modules ..."
[ -d "$WORK/patched_$VER" ] || fail "no $WORK/patched_$VER (the rewrite stage did not run)"
cp -R "$WORK/patched_$VER" "$RES/patched"
echo "    $(ls "$RES/patched" | wc -l | tr -d ' ') files"

# --- the shader tables (the host looks for them beside DM_NVN_SHMAP) ---
echo "[3] the shader tables ..."
for t in shader_map.tsv pso_manifest.tsv c1_full.tsv cb_extent.tsv; do
  [ -f "$PROF/$t" ] && cp "$PROF/$t" "$RES/dm/" || echo "    (no $t in the profile)"
done

# --- the macOS shader libraries ---
echo "[4] the macOS shader libraries (APFS clone) ..."
clone_tree "$SHADER_LIBRARY" "$RES/msl/$SHADER_NAME"
echo "    $(find "$RES/msl" -name '*.metallib' | wc -l | tr -d ' ') metallibs"

# --- the game files ---
echo "[5] the game files (APFS clone) ..."
if [ -f "$WORK/extract/$VER/RomFS.img" ]; then
  clone_tree "$WORK/extract/$VER/RomFS.img" "$RES/romfs.img"
else
  [ -d "$WORK/extract/$VER/RomFS" ] || fail "no $WORK/extract/$VER/RomFS (the extract stage did not run)"
  clone_tree "$WORK/extract/$VER/RomFS" "$RES/romfs"
fi

# Always use the license-aware helper; never reuse old Gen system-font copies.
echo "[6] the fonts ..."
FONT_HELPER=${NXLAUNCHER_FONT_HELPER:-$ROOT/Scripts/font-policy.py}
[ -f "$FONT_HELPER" ] || fail "font policy helper missing: $FONT_HELPER"
"$PY" "$FONT_HELPER" --repo "$REPO" --out "$RES/font" || fail "font policy preparation failed"
[ -s "$RES/font/standard.ttf" ] && [ -s "$RES/font/nintendo_ext.ttf" ] || fail "font helper produced incomplete fonts"

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
    [ -d "$d" ] || continue
    idx=$(basename "$d")
    case "$idx" in ''|*[!0-9]*) continue;; esac
    src=${d%/}
    [ ! -d "$d/RomFS" ] || src="$d/RomFS"
    mkdir -p "$RES/aoc"
    clone_tree "$src" "$RES/aoc/$idx"
    echo "    aoc/$idx: $(find "$RES/aoc/$idx" -type f | wc -l | tr -d ' ') files"
  done
else
  echo "    (none)"
fi

# --- the launcher: a real Mach-O binary (LaunchServices refuses a bundle whose CFBundleExecutable
#     is a shell script), it sets the environment and execs the host ---
echo "[9] the launcher ..."
clang -O2 -DAPP_SUPPORT_NAME="\"$SUPPORT\"" -DAPP_LEGACY_SUPPORT_NAME="\"$NAME\"" -DAPP_MEM_POOL="\"$MEM_POOL\"" -DAPP_MEM_RESERVE="\"$MEM_RESERVE\"" \
  -o "$OUT/Contents/MacOS/BotW" "$HERE/launcher.c" || { echo "FAIL: the launcher did not build"; exit 1; }
chmod +x "$OUT/Contents/MacOS/BotW"
file "$OUT/Contents/MacOS/BotW" | sed 's/^/    /'

# --- Info.plist ---
"$PY" "$HERE/make-info-plist.py" "$OUT/Contents/Info.plist" "$NAME" "$DISPLAY" "$BUNDLE_ID" "$GAME_VERSION" "$MIN_MACOS" || exit 1
plutil -lint "$OUT/Contents/Info.plist" >/dev/null || { echo "FAIL: the Info.plist is not well-formed"; exit 1; }

# Sign the nested host before sealing the complete bundle and its resources.
echo "[10] signing the app ..."
codesign --force --sign - "$OUT/Contents/MacOS/dmhost" || fail "the Mac host could not be signed"
codesign --force --sign - "$OUT" || fail "the app could not be signed"
codesign --verify --deep --strict "$OUT" || fail "the app signature is not valid"

# Rename on the destination volume only after validation and signing succeeds.
[ ! -e "$FINAL_OUT" ] || fail "output appeared during export: $FINAL_OUT"
mv "$OUT" "$FINAL_OUT"
OUT=$FINAL_OUT

echo
echo "=== the app ==="
du -sh "$OUT"
echo
echo "run it with:  open \"$OUT\""
echo "logs / saves : ~/Library/Application Support/$SUPPORT/"

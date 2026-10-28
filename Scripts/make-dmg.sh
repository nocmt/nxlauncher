#!/bin/bash
# Build a signed disk image containing the app and the usual Applications shortcut.
# Usage: make-dmg.sh APP OUTPUT.dmg [--identity ID] [--timestamp none|secure]
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
APP=""
OUT=""
IDENTITY=${DEVELOPER_ID:--}
STAMP=${CODESIGN_TIMESTAMP:-none}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --identity) [ "$#" -ge 2 ] || exit 2; IDENTITY=$2; shift 2;;
    --timestamp) [ "$#" -ge 2 ] || exit 2; STAMP=$2; shift 2;;
    --help) printf 'Usage: %s APP OUTPUT.dmg [--identity ID] [--timestamp none|secure]\n' "$0"; exit 0;;
    -*) echo "FAIL: unknown option $1" >&2; exit 2;;
    *) if [ -z "$APP" ]; then APP=$1; elif [ -z "$OUT" ]; then OUT=$1; else
         echo 'FAIL: too many arguments' >&2; exit 2; fi; shift;;
  esac
done
[ -n "$APP" ] && [ -n "$OUT" ] || { echo 'FAIL: APP and OUTPUT.dmg are required' >&2; exit 2; }
[ -d "$APP" ] || { echo "FAIL: no app at $APP" >&2; exit 2; }
command -v create-dmg >/dev/null || { echo 'FAIL: create-dmg is not installed (brew install create-dmg)' >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
[[ "$OUT" == *.dmg ]] || { echo 'FAIL: output must end in .dmg' >&2; exit 2; }
[ ! -e "$OUT" ] || rm -f "$OUT"
WORK=$(mktemp -d "$(dirname "$OUT")/.nxlauncher-dmg.XXXXXX")
cleanup(){ rm -rf "$WORK"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# create-dmg lays out the window (icon positions, Applications drop link) and writes to a
# staging path; the result is signed afterwards so the seal covers the final bytes.
VOLUME="NxLauncher"
create-dmg \
  --volname "$VOLUME" \
  --window-pos 200 120 \
  --window-size 620 400 \
  --icon-size 100 \
  --icon "NxLauncher.app" 170 190 \
  --hide-extension "NxLauncher.app" \
  --app-drop-link 440 190 \
  --no-internet-enable \
  "$WORK/NxLauncher.dmg" "$APP" >/dev/null
[ -f "$WORK/NxLauncher.dmg" ] || { echo 'FAIL: create-dmg produced no image' >&2; exit 1; }
# Sign the image itself: notarization covers the container the user downloads.
codesign --force --sign "$IDENTITY" \
  "$([ "$STAMP" = secure ] && printf '%s' --timestamp || printf '%s' --timestamp=none)" \
  "$WORK/NxLauncher.dmg"
codesign --verify --strict "$WORK/NxLauncher.dmg"
hdiutil verify "$WORK/NxLauncher.dmg" >/dev/null
python3 "$HERE/Scripts/release-support.py" publish "$WORK/NxLauncher.dmg" "$OUT"
printf 'dmg: %s\n' "$OUT"

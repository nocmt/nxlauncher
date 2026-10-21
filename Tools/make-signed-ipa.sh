#!/bin/bash
# Pack the signed iOS app into a signed IPA.
#
# The app was signed AFTER the game files and the shader libraries were put into it, so the resource
# seal covers the whole bundle and the signature stays valid. A sideloading tool can re-sign it with
# the user's own certificate (that is the point of the unsigned variant next to this one).
#
# Usage: make-signed-ipa.sh [--work <build dir>] [--out <ipa>] [--repo <nxnative>]
#   --work   the game's build folder (default: <repo>/../botw-nsp/<title id>_build)
#   --out    the IPA to write (default: <work>/../../<name>-signed.ipa)
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
REPO=${NXLAUNCHER_REPO:-$ROOT/nxnative}
WORK=""; OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --work) WORK=$2; shift 2;;
    --out) OUT=$2; shift 2;;
    --repo) REPO=$2; shift 2;;
    -h|--help) sed -n '2,10p' "$0"; exit 0;;
    *) echo "FAIL: unknown option $1" >&2; exit 1;;
  esac
done

GAME=$(python3 "$REPO/dm/games/game.py" list 2>/dev/null | head -1 | cut -f1)
if [ -z "$WORK" ]; then
  [ -n "$GAME" ] || { echo "FAIL: no game profile found under $REPO/dm/games"; exit 1; }
  WORK="$ROOT/../botw-nsp/${GAME}_build"
fi
APP="$WORK/ipa/build/ios/pkg/dd/Build/Products/Release-iphoneos/DmIOS.app"
[ -d "$APP" ] || { echo "FAIL: no signed app at $APP (run sign-build.sh + finish-install.sh first)"; exit 1; }
[ -n "$OUT" ] || OUT="$WORK/../$(basename "$APP" .app)-signed.ipa"

STORE=$(python3 -c "
import sys; sys.path.insert(0, '$REPO/dm/games')
import game
g = game.load('$GAME')
print(g.get('zip_store', ''))
")

echo "=== signing the IPA ==="
echo "app : $APP"
echo "out : $OUT"
echo "--- the app's signature ---"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Authority|TeamIdentifier'
codesign --verify --strict "$APP" && echo "    verify OK" || { echo "FAIL: the app's signature is not valid"; exit 1; }
[ -f "$APP/embedded.mobileprovision" ] && echo "    embedded.mobileprovision present" || echo "    (no provisioning profile!)"

echo
echo "--- packing (this reads and writes ~15 GB) ---"
cd "$REPO/dm/ios" || exit 1
time python3 tools/pack_ipa.py "$OUT" --store "$STORE" "Payload/DmIOS.app=$APP"
rc=$?
echo "pack exit=$rc"
[ $rc -eq 0 ] || exit $rc
ls -la "$OUT"

echo
echo "--- the archive's key entries ---"
python3 - "$OUT" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    names = {i.filename for i in z.infolist()}
    for k in ('Payload/DmIOS.app/DmIOS', 'Payload/DmIOS.app/Info.plist',
              'Payload/DmIOS.app/embedded.mobileprovision',
              'Payload/DmIOS.app/_CodeSignature/CodeResources'):
        print(f'  {k:55s} {"present" if k in names else "ABSENT"}')
    print('  metallib entries:', sum(1 for n in names if n.endswith('.metallib')))
    print('  romfs entries   :', sum(1 for n in names if '/romfs/' in n))
    print('  aoc entries     :', sum(1 for n in names if '/aoc/' in n))
PY
echo
echo "=== done $(date '+%Y-%m-%d %H:%M:%S') ==="

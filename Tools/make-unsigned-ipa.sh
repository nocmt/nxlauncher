#!/bin/bash
# Pack the UNSIGNED all-in-one IPA.
#
# This is the one a colleague can install: the app carries no signature, so Sideloadly / AltStore /
# LiveContainer can put the colleague's own Apple ID certificate and bundle ID on it. The signed IPA
# (make-signed-ipa.sh) is bound to the developer's provisioning profile, whose device list holds
# only the developer's own iPhone -- iOS refuses to install it anywhere else.
#
# It is packed from the same app make-signed-ipa.sh uses, minus the two signature entries
# (_CodeSignature and embedded.mobileprovision), so the payload is identical: the same binary, the
# same game files, the same shader libraries, the same DLC.
#
# Usage: make-unsigned-ipa.sh [--work <build dir>] [--out <ipa>] [--repo <nxnative>]
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
REPO=${NXLAUNCHER_REPO:-$ROOT/nxnative}
WORK=""; OUT=""; GAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --work) WORK=$2; shift 2;;
    --out) OUT=$2; shift 2;;
    --repo) REPO=$2; shift 2;;
    --game) GAME=$2; shift 2;;
    -h|--help) sed -n '2,13p' "$0"; exit 0;;
    *) echo "FAIL: unknown option $1" >&2; exit 1;;
  esac
done

if [ -z "$WORK" ]; then
  GAME=${GAME:-$(python3 "$REPO/dm/games/game.py" list 2>/dev/null | head -1 | cut -f1)}
  [ -n "$GAME" ] || { echo "FAIL: no game profile found under $REPO/dm/games"; exit 1; }
  WORK="$ROOT/../botw-nsp/${GAME}_build"
fi
APP="$WORK/ipa/build/ios/pkg/dd/Build/Products/Release-iphoneos/DmIOS.app"
[ -d "$APP" ] || { echo "FAIL: no app at $APP (run sign-build.sh + finish-install.sh first)"; exit 1; }
for d in romfs msl aoc; do
  [ -d "$APP/$d" ] || echo "    (the app has no $d)"
done
[ -n "$OUT" ] || OUT="$WORK/../$(basename "$APP" .app).ipa"

STORE=$(python3 -c "
import sys; sys.path.insert(0, '$REPO/dm/games')
import game
g = game.load('${GAME:-01007EF00011E000}')
print(g.get('zip_store', ''))
")

echo "=== packing the UNSIGNED IPA ==="
echo "app : $APP"
echo "out : $OUT"
echo
echo "--- packing (this reads and writes ~15 GB) ---"
cd "$REPO/dm/ios" || exit 1
time python3 tools/pack_ipa.py "$OUT" --store "$STORE" \
  --skip Payload/DmIOS.app/_CodeSignature \
  --skip Payload/DmIOS.app/embedded.mobileprovision \
  "Payload/DmIOS.app=$APP"
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
        print(f'  {k:55s} {"present" if k in names else "ABSENT (unsigned, as intended)"}')
    print('  metallib entries:', sum(1 for n in names if n.endswith('.metallib')))
    print('  romfs entries   :', sum(1 for n in names if '/romfs/' in n))
    print('  aoc entries     :', sum(1 for n in names if '/aoc/' in n))
PY
echo
echo "=== done $(date '+%Y-%m-%d %H:%M:%S') ==="

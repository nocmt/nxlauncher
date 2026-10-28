#!/bin/bash
# Build one complete app, audit it, optionally notarize it, and atomically publish a signed
# (and, when a notary profile is given, notarized and stapled) disk image. No uploads and no
# game execution.
#
# Only a DMG is produced: the stapler cannot attach a ticket to a ZIP, so a zip would ship an
# app that still needs a network round-trip to Apple on first launch. The DMG is the one
# container that carries the ticket.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(tr -d '\n' < "$HERE/VERSION")
IDENTITY=${DEVELOPER_ID:--}
PYTHON_ROOT=${NXLAUNCHER_PYTHON_ROOT:-}
PACKAGE_ONLY=0
NOTARY_PROFILE=${NOTARY_PROFILE:-}
OUT=""
STAMP=${CODESIGN_TIMESTAMP:-none}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --package-only) PACKAGE_ONLY=1; shift;;
    --identity) [ "$#" -ge 2 ] || exit 2; IDENTITY=$2; shift 2;;
    --python) [ "$#" -ge 2 ] || exit 2; PYTHON_ROOT=$2; shift 2;;
    --notary-profile) [ "$#" -ge 2 ] || exit 2; NOTARY_PROFILE=$2; shift 2;;
    --help) printf 'Usage: %s [output.dmg] [--package-only] [--identity ID] [--python ROOT] [--notary-profile NAME]\n--package-only packages NXLAUNCHER_APP or dist/NxLauncher.app without rebuilding it.\n--notary-profile notarizes and staples the DMG.\n' "$0"; exit 0;;
    -*) echo "FAIL: unknown option $1" >&2; exit 2;;
    *) [ -z "$OUT" ] || { echo 'FAIL: output specified twice' >&2; exit 2; }; OUT=$1; shift;;
  esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'FAIL: invalid VERSION' >&2; exit 2; }
[ -n "$OUT" ] || OUT="$HERE/dist/NxLauncher-${VERSION}-macos-arm64.dmg"
[[ "$OUT" == *.dmg && ! -L "$OUT" && ! -d "$OUT" ]] || { echo 'FAIL: output must be a regular .dmg path' >&2; exit 2; }
# Notarization rejects an ad-hoc signature, and it needs a secure timestamp.
if [ -n "$NOTARY_PROFILE" ]; then
  [ "$IDENTITY" != '-' ] || { echo 'FAIL: --notary-profile needs a Developer ID --identity' >&2; exit 2; }
  if [ "$STAMP" != secure ]; then
    echo 'note: notarization requires a secure timestamp; using CODESIGN_TIMESTAMP=secure' >&2
    STAMP=secure
  fi
fi
mkdir -p "$(dirname "$OUT")"
OUT=$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")
LOCK="$OUT.release-lock"; mkdir "$LOCK" 2>/dev/null || { echo "FAIL: locked $LOCK" >&2; exit 1; }
STAGE=$(mktemp -d "$(dirname "$OUT")/.nxlauncher-release.XXXXXX")
cleanup(){ rm -rf "$STAGE"; rmdir "$LOCK"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
APP="$STAGE/NxLauncher.app"

# Notarizes one item, waits for the verdict, and staples the ticket into it. ZIP archives are
# never passed here: the stapler cannot attach a ticket to a zip, which is why only a DMG ships.
notarize() {
  local target=$1
  echo "notarizing $(basename "$target") ..."
  xcrun notarytool submit "$target" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$target"
  xcrun stapler validate "$target"
}

if [ "$PACKAGE_ONLY" -eq 0 ]; then
  ARGS=("$APP")
  [ -z "$PYTHON_ROOT" ] || ARGS+=(--python "$PYTHON_ROOT")
  DEVELOPER_ID="$IDENTITY" CODESIGN_TIMESTAMP="$STAMP" bash "$HERE/Scripts/make-app.sh" "${ARGS[@]}"
else
  SOURCE_APP=${NXLAUNCHER_APP:-$HERE/dist/NxLauncher.app}
  [ -d "$SOURCE_APP" ] || { echo "FAIL: --package-only requires $SOURCE_APP" >&2; exit 2; }
  ditto "$SOURCE_APP" "$APP"
fi
codesign --verify --deep --strict "$APP"
python3 "$HERE/Tools/release-audit.py" --root "$APP" --kind app --manifest "$STAGE/app-audit.json" > "$STAGE/audit-output.json"
python3 - "$APP" "$VERSION" "$IDENTITY" <<'PY'
import plistlib,subprocess,sys
from pathlib import Path
app, version, identity = Path(sys.argv[1]),sys.argv[2],sys.argv[3]
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString']==version and info['CFBundleVersion']==version, 'App version differs from VERSION'
signature=subprocess.check_output(['codesign','-dvv',str(app)],stderr=subprocess.STDOUT,text=True)
if identity != '-':
 assert 'Authority='+identity in signature, 'App signing identity mismatch'
 assert 'runtime' in signature, 'App lacks hardened runtime'
else:
 assert 'Signature=adhoc' in signature, 'Expected explicit ad-hoc CI/development app'
PY

# notarytool accepts a zip, a pkg or a dmg — never a bare .app. The disk image is therefore the
# item submitted: the app goes into the image already Developer ID signed, and the ticket the
# service issues for the image covers the bundle inside it. No ZIP is produced at all, because
# the stapler cannot attach a ticket to one.
NOTARIZED=0
DMG_STAGE="$STAGE/NxLauncher-${VERSION}.dmg"
bash "$HERE/Scripts/make-dmg.sh" "$APP" "$DMG_STAGE" --identity "$IDENTITY" --timestamp "$STAMP"
if [ -n "$NOTARY_PROFILE" ]; then
  notarize "$DMG_STAGE"
  NOTARIZED=1
fi
bash "$HERE/Scripts/verify-release.sh" "$DMG_STAGE"
python3 - "$STAGE/manifest.json" "$DMG_STAGE" "$OUT" "$VERSION" "$IDENTITY" \
         "$STAGE/app-audit.json" "$HERE" "$STAMP" "$NOTARIZED" <<'PY'
import hashlib,json,pathlib,sys
manifest, dmg, output = map(pathlib.Path,sys.argv[1:4])
version,identity,audit,root,timestamp,notarized=sys.argv[4:]
digest=hashlib.sha256(dmg.read_bytes()).hexdigest()
pin=(pathlib.Path(root)/'patches/base-commit').read_text().strip()
result={'version':version,'architecture':'arm64','signing_identity':identity,
        'hardened_runtime':True,'timestamp':timestamp,
        'notarized':notarized=='1','stapled':notarized=='1',
        'upstream_commit':pin,
        'dmg':{'path':output.name,'size':dmg.stat().st_size,'sha256':digest},
        'app_audit':json.loads(pathlib.Path(audit).read_text())}
manifest.write_text(json.dumps(result,indent=2)+'\n')
(pathlib.Path(str(manifest)+'.sha256')).write_text(f'{digest}  {output.name}\n')
PY
python3 "$HERE/Scripts/release-support.py" publish "$DMG_STAGE" "$OUT"
python3 "$HERE/Scripts/release-support.py" publish "$STAGE/manifest.json.sha256" "$OUT.sha256"
python3 "$HERE/Scripts/release-support.py" publish "$STAGE/manifest.json" "$OUT.manifest.json"
printf 'release image: %s\nsha256: %s\nmanifest: %s\n' "$OUT" "$OUT.sha256" "$OUT.manifest.json"

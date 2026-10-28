#!/bin/bash
# Build one complete app, audit it, and atomically publish a ZIP. No uploads or game execution.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(tr -d '\n' < "$HERE/VERSION")
IDENTITY=${DEVELOPER_ID:--}
PYTHON_ROOT=${NXLAUNCHER_PYTHON_ROOT:-}
PACKAGE_ONLY=0
OUT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --package-only) PACKAGE_ONLY=1; shift;;
    --identity) [ "$#" -ge 2 ] || exit 2; IDENTITY=$2; shift 2;;
    --python) [ "$#" -ge 2 ] || exit 2; PYTHON_ROOT=$2; shift 2;;
    --help) printf 'Usage: %s [output.zip] [--package-only] [--identity ID] [--python ROOT]\n--package-only verifies NXLAUNCHER_APP or dist/NxLauncher.app without modifying it.\n' "$0"; exit 0;;
    -*) echo "FAIL: unknown option $1" >&2; exit 2;;
    *) [ -z "$OUT" ] || { echo 'FAIL: output specified twice' >&2; exit 2; }; OUT=$1; shift;;
  esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'FAIL: invalid VERSION' >&2; exit 2; }
[ -n "$OUT" ] || OUT="$HERE/dist/NxLauncher-${VERSION}-macos-arm64.zip"
[[ "$OUT" == *.zip && ! -L "$OUT" && ! -d "$OUT" ]] || { echo 'FAIL: output must be a regular .zip path' >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"
OUT=$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")
LOCK="$OUT.release-lock"; mkdir "$LOCK" 2>/dev/null || { echo "FAIL: locked $LOCK" >&2; exit 1; }
STAGE=$(mktemp -d "$(dirname "$OUT")/.nxlauncher-release.XXXXXX")
cleanup(){ rm -rf "$STAGE"; rmdir "$LOCK"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
APP="$STAGE/NxLauncher.app"
if [ "$PACKAGE_ONLY" -eq 0 ]; then
  ARGS=("$APP")
  [ -z "$PYTHON_ROOT" ] || ARGS+=(--python "$PYTHON_ROOT")
  DEVELOPER_ID="$IDENTITY" CODESIGN_TIMESTAMP=${CODESIGN_TIMESTAMP:-none} bash "$HERE/Scripts/make-app.sh" "${ARGS[@]}"
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
ZIP_STAGE="$STAGE/release.zip"
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc "$APP" "$ZIP_STAGE"
bash "$HERE/Scripts/verify-release.sh" "$ZIP_STAGE"
python3 - "$STAGE/manifest.json" "$ZIP_STAGE" "$OUT" "$VERSION" "$IDENTITY" "$STAGE/app-audit.json" "$HERE" <<'PY'
import hashlib,json,pathlib,subprocess,sys
manifest, archive, output = map(pathlib.Path,sys.argv[1:4])
version,identity,audit,root=sys.argv[4:]
digest=hashlib.sha256(archive.read_bytes()).hexdigest()
pin=(pathlib.Path(root)/'patches/base-commit').read_text().strip()
result={'version':version,'architecture':'arm64','signing_identity':identity,
        'hardened_runtime':True,'timestamp': 'none', 'notarized':False,'stapled':False,
        'upstream_commit':pin,'archive':{'path':output.name,'size':archive.stat().st_size,'sha256':digest},
        'app_audit':json.loads(pathlib.Path(audit).read_text())}
manifest.write_text(json.dumps(result,indent=2)+'\n')
(pathlib.Path(str(manifest)+'.sha256')).write_text(digest+'  '+output.name+'\n')
PY
python3 "$HERE/Scripts/release-support.py" publish "$ZIP_STAGE" "$OUT"
python3 "$HERE/Scripts/release-support.py" publish "$STAGE/manifest.json.sha256" "$OUT.sha256"
python3 "$HERE/Scripts/release-support.py" publish "$STAGE/manifest.json" "$OUT.manifest.json"
printf 'release package: %s\nsha256: %s\nmanifest: %s\n' "$OUT" "$OUT.sha256" "$OUT.manifest.json"

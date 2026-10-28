#!/bin/bash
# Verify a built app or ZIP without launching it or contacting Apple.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
[ "$#" -eq 1 ] || { printf 'Usage: %s APP_OR_ZIP\n' "$0" >&2; exit 2; }
INPUT=$1
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/nxlauncher-verify.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
if [[ "$INPUT" == *.app ]]; then
    APP=$INPUT
elif [[ "$INPUT" == *.zip ]]; then
    python3 - "$INPUT" <<'PY'
import sys,zipfile
from pathlib import PurePosixPath
with zipfile.ZipFile(sys.argv[1]) as archive:
    for member in archive.infolist():
        path=PurePosixPath(member.filename)
        if path.is_absolute() or '..' in path.parts or '\\' in member.filename:
            raise SystemExit('Unsafe ZIP member')
        if not (member.filename == 'NxLauncher.app/' or member.filename.startswith('NxLauncher.app/')):
            raise SystemExit('Unexpected ZIP root')
    if archive.testzip(): raise SystemExit('Corrupt ZIP')
PY
    ditto -x -k "$INPUT" "$STAGE"
    APP="$STAGE/NxLauncher.app"
else
    echo 'FAIL: expected .app or .zip' >&2; exit 2
fi
[ -x "$APP/Contents/MacOS/NxLauncher" ] || { echo 'FAIL: executable missing' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
python3 "$HERE/Tools/release-audit.py" --root "$APP" --kind app --manifest "$STAGE/audit.json" > "$STAGE/output.json"
python3 - "$STAGE/audit.json" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
print('App audit passed: '+str(len(report['files']))+' files; no game execution or notarization check performed.')
PY

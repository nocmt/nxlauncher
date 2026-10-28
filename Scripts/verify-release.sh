#!/bin/bash
# Verify a built app, ZIP or DMG without launching it. The app inside is always checked; a DMG
# mount is read-only and detached afterwards. A stapled ticket is validated when present, and an
# unnotarized build is reported as such rather than treated as a verification failure.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
[ "$#" -eq 1 ] || { printf 'Usage: %s APP_OR_ZIP_OR_DMG\n' "$0" >&2; exit 2; }
INPUT=$1
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/nxlauncher-verify.XXXXXX")
MOUNTED=""
cleanup() {
    [ -z "$MOUNTED" ] || hdiutil detach "$MOUNTED" -quiet >/dev/null 2>&1 || true
    rm -rf "$STAGE"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
TICKET_TARGET=""
if [[ "$INPUT" == *.app ]]; then
    APP=$INPUT
    TICKET_TARGET="$APP"
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
    TICKET_TARGET="$APP"
elif [[ "$INPUT" == *.dmg ]]; then
    codesign --verify --strict "$INPUT"
    MOUNTED=$(hdiutil attach "$INPUT" -readonly -nobrowse -noverify -mountpoint "$STAGE/mnt" -plist \
              | python3 -c 'import plistlib,sys; d=plistlib.loads(sys.stdin.buffer.read()); print(next(e["mount-point"] for e in d["system-entities"] if "mount-point" in e))')
    APP="$MOUNTED/NxLauncher.app"
    [ -d "$APP" ] || { echo 'FAIL: the DMG does not contain NxLauncher.app' >&2; exit 1; }
    if xcrun stapler validate "$INPUT" >/dev/null 2>&1; then
        echo 'DMG: notarization ticket valid and stapled.'
    else
        echo 'DMG: no stapled ticket (unnotarized build).'
    fi
else
    echo 'FAIL: expected .app, .zip or .dmg' >&2; exit 2
fi
[ -x "$APP/Contents/MacOS/NxLauncher" ] || { echo 'FAIL: executable missing' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
if xcrun stapler validate "$TICKET_TARGET" >/dev/null 2>&1; then
    echo "App: notarization ticket valid and stapled in $([ "$INPUT" = "$TICKET_TARGET" ] && echo the bundle || echo the archive)."
else
    echo 'App: no stapled ticket (unnotarized build).'
fi
python3 "$HERE/Tools/release-audit.py" --root "$APP" --kind app --manifest "$STAGE/audit.json" > "$STAGE/output.json"
python3 - "$STAGE/audit.json" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
print('App audit passed: '+str(len(report['files']))+' files; no game execution was performed.')
PY

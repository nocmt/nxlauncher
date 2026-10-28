#!/bin/bash
# Build a fresh tools/source/wheels/standalone-Python archive, then publish atomically.
# Usage: make-home-archive.sh [out.tgz] [--python <dir>]
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT="$HERE/dist/nxlauncher-home.tgz"
PYTHON_DIR=""
SIGN_IDENTITY="${DEVELOPER_ID:--}"
SIGN_TIMESTAMP="${CODESIGN_TIMESTAMP:-none}"
OUT_GIVEN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --python)
            [ "$#" -ge 2 ] || { echo "FAIL: --python needs a directory" >&2; exit 1; }
            PYTHON_DIR="$2"; shift 2;;
        -h|--help) printf 'Usage: %s [out.tgz] [--python <dir>]\n' "$0"; exit 0;;
        --*) echo "FAIL: unknown option $1" >&2; exit 1;;
        *)
            [ "$OUT_GIVEN" -eq 0 ] || { echo "FAIL: only one output path is accepted" >&2; exit 1; }
            OUT="$1"; OUT_GIVEN=1; shift;;
    esac
done

# Refuse a stale pin or any unrepresented dependency edits before copying anything.
python3 "$HERE/Tools/prepare-nxnative.py" --check
# Wheels are cp313/arm64; do not silently bundle another Python ABI or architecture.
if [ -z "$PYTHON_DIR" ]; then
    for c in "$HOME/.local/share/uv/python"/cpython-3.13.*; do
        [ ! -x "$c/bin/python3" ] || PYTHON_DIR="$c"
    done
fi
if [ -z "$PYTHON_DIR" ] || [ ! -x "$PYTHON_DIR/bin/python3" ]; then
    echo "FAIL: no standalone Python 3.13 found; run uv python install 3.13 or pass --python <dir>." >&2
    exit 1
fi
PYTHON_DIR=$(cd "$PYTHON_DIR" && pwd)
"$PYTHON_DIR/bin/python3" -c 'import platform, sys; sys.exit(0 if sys.version_info[:2] == (3, 13) and sys.platform == "darwin" and platform.machine() == "arm64" else "bundled wheels require macOS arm64 CPython 3.13")'
printf 'python: %s (%s)\n' "$PYTHON_DIR" "$("$PYTHON_DIR/bin/python3" -V 2>&1)"

mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
[ ! -L "$OUT" ] && [ ! -d "$OUT" ] || { echo "FAIL: archive output must be a regular file path" >&2; exit 1; }
LOCK="$OUT.build-lock"
mkdir "$LOCK" 2>/dev/null || { echo "FAIL: archive already locked at $LOCK" >&2; exit 1; }
STAGE=""
cleanup() {
    [ -z "$STAGE" ] || rm -rf "$STAGE"
    rmdir "$LOCK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
STAGE=$(mktemp -d "$(dirname "$OUT")/.nxlauncher-home.XXXXXX")
PAYLOAD="$STAGE/payload"
mkdir "$PAYLOAD"

echo "exporting verified upstream source ..."
# Export the exact verified patch tree, not a recursive copy of the dirty checkout.
# No Git metadata, ignored binaries, generated projects or user data enter the payload.
python3 "$HERE/Tools/prepare-nxnative.py" --check --export "$PAYLOAD/nxnative"
echo "copying the release tools, font policy, wheels and standalone Python ..."
# The release payload carries the runtime tools plus the release helper and its pinned
# open-font assets; it never carries repository metadata or user data.
cp -R "$HERE/Tools" "$PAYLOAD/Tools"
# Runtime tools are an explicit allowlist. release-audit.py and local bytecode are build-only.
python3 - "$PAYLOAD/Tools" <<'PY'
from pathlib import Path
import shutil, sys
allowed = {'launcher.c', 'make-icns.py', 'make-info-plist.py', 'make-ipa.py', 'make-mac-app.sh',
           'make-signed-ipa.sh', 'make-unsigned-ipa.sh', 'pack_pipeline.py', 'prepare-nxnative.py',
           'shader_chain.py', 'toolchain.py'}
for path in Path(sys.argv[1]).iterdir():
    if path.name not in allowed:
        if path.is_dir() and not path.is_symlink(): shutil.rmtree(path)
        else: path.unlink()
PY
mkdir -p "$PAYLOAD/Scripts"
cp "$HERE/Scripts/font-policy.py" "$PAYLOAD/Scripts/"
cp -R "$HERE/Scripts/fonts" "$PAYLOAD/Scripts/fonts"
cp -R "$HERE/Resources/wheels" "$PAYLOAD/wheels"
cp -R "$PYTHON_DIR" "$PAYLOAD/python"
cp "$HERE/VERSION" "$HERE/LICENSE" "$HERE/THIRD_PARTY_NOTICES.md" "$PAYLOAD/"
# Tool bytecode is machine-local and may be stale. Only remove it from staging.
find "$PAYLOAD/Tools" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$PAYLOAD/Tools" -type f \( -name '*.pyc' -o -name '.DS_Store' \) -delete
# Drop debug symbols and generated/ignored artifacts only from verified export staging.
find "$PAYLOAD/nxnative" -type f -name '*.pdb' -delete
python3 "$HERE/Scripts/release-support.py" payload "$PAYLOAD" "$PYTHON_DIR" \
    --identity "$SIGN_IDENTITY" --timestamp "$SIGN_TIMESTAMP"
if ! python3 "$HERE/Tools/release-audit.py" --root "$PAYLOAD" --kind payload --manifest "$STAGE/payload-audit.json" > "$STAGE/audit-output.json"; then
    python3 - "$STAGE/payload-audit.json" <<'PY'
import json, sys
print('\n'.join(json.load(open(sys.argv[1]))['findings']), file=sys.stderr)
PY
    exit 1
fi

echo "packing ..."
COPYFILE_DISABLE=1 tar -czf "$STAGE/home.tgz" -C "$PAYLOAD" .
tar -tzf "$STAGE/home.tgz" >/dev/null
# The temporary archive is on the destination filesystem. No cached archive fallback.
python3 - "$STAGE/home.tgz" "$OUT" <<'PY'
import os
import sys
os.replace(sys.argv[1], sys.argv[2])
PY
printf '\nthe archive: %s\n' "$OUT"
du -sh "$OUT"

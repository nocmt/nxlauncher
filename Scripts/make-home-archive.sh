#!/bin/bash
# Build the archive the app carries: the tools, the upstream source tree, the Python wheels and a
# standalone Python -- in one file.
#
# The app unpacks it into the cache on the first run, so the app can be shared as a single file
# and needs nothing else from this repository. The tree is unpacked into the cache (not into the
# bundle) because the build writes into it, and an app in /Applications is read-only.
#
# The standalone Python is a relocatable CPython 3.13 (the upstream packing script needs 3.12+:
# it uses PEP 701 f-strings). uv keeps one in its cache; another one can be given with --python.
#
# Usage: make-home-archive.sh [out.tgz] [--python <dir>]
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT="$HERE/dist/nxlauncher-home.tgz"
PYTHON_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --python) PYTHON_DIR="$2"; shift 2;;
    -h|--help) sed -n '2,16p' "$0"; exit 0;;
    *) OUT="$1"; shift;;
  esac
done

# the standalone Python: uv's cache, or the one that was named.
# 3.13 exactly: the wheels in Resources/wheels are the cp313 ones, and the upstream packing
# script needs 3.12+ (it uses PEP 701 f-strings).
if [ -z "$PYTHON_DIR" ]; then
  for c in "$HOME/.local/share/uv/python"/cpython-3.13.*; do
    [ -x "$c/bin/python3" ] && PYTHON_DIR="$c"
  done
fi
if [ -z "$PYTHON_DIR" ] || [ ! -x "$PYTHON_DIR/bin/python3" ]; then
  echo "FAIL: no standalone Python 3.13 found in uv's cache."
  echo "      install uv (curl -LsSf https://astral.sh/uv/install.sh | sh), then: uv python install 3.13"
  echo "      or pass --python <dir>."
  exit 1
fi
echo "python: $PYTHON_DIR ($("$PYTHON_DIR/bin/python3" -V 2>&1))"

STAGE="$HERE/dist/home-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$(dirname "$OUT")" || exit 1

echo "copying the tools ..."
cp -R "$HERE/Tools" "$STAGE/Tools"

echo "copying the upstream tree ..."
cp -R "$HERE/nxnative" "$STAGE/nxnative"
rm -rf "$STAGE/nxnative/.git"                 # the submodule's pointer, not the tree
rm -rf "$STAGE/nxnative/dm/host/gen"          # the host's build products
rm -rf "$STAGE/nxnative/dm/ios/Gen"           # the iOS project's build products
rm -rf "$STAGE/nxnative/dm/tools/nx_extract/obj" "$STAGE/nxnative/dm/tools/nx_extract/bin"

echo "copying the Python wheels ..."
cp -R "$HERE/Resources/wheels" "$STAGE/wheels"

echo "copying the standalone Python ..."
cp -R "$PYTHON_DIR" "$STAGE/python"

echo "packing ..."
tar -czf "$OUT" -C "$STAGE" . || { echo "FAIL: tar"; exit 1; }
rm -rf "$STAGE"

echo
echo "the archive: $OUT"
du -sh "$OUT"

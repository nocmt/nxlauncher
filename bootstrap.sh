#!/bin/bash
# Prepare the repository: the nxnative dependency (a submodule) with our patches on it, and the
# toolchain the pipeline needs.
#
#   ./bootstrap.sh            prepare everything and report what is missing
#   ./bootstrap.sh --check    only report (does not change anything)
#
# The upstream commit and ordered patch series are recorded in patches/. Preparation checks the
# complete resulting tree; an upstream bump requires rebasing and verifying that series.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

say() { printf '%s\n' "$*"; }
miss=0
need() {   # need <command> <how to get it>
  if command -v "$1" >/dev/null 2>&1; then say "  ✓ $1"; else say "  ✗ $1  —— $2"; miss=1; fi
}

say "=== the nxnative dependency ==="
if [ ! -d "$HERE/nxnative/.git" ] && [ ! -f "$HERE/nxnative/.git" ]; then
  if [ $CHECK -eq 0 ]; then
    say "  cloning the submodule ..."
    git -C "$HERE" submodule update --init --recursive || { say "  ✗ the submodule could not be fetched"; miss=1; }
  else
    say "  ✗ the submodule is not initialized (run ./bootstrap.sh)"; miss=1
  fi
fi
if [ -d "$HERE/nxnative/dm/host" ]; then
  if [ $CHECK -eq 1 ]; then
    python3 "$HERE/Tools/prepare-nxnative.py" --check || miss=1
  else
    python3 "$HERE/Tools/prepare-nxnative.py" || exit 1
  fi
else
  say "  ✗ nxnative is missing"; miss=1
fi

say
say "=== the toolchain ==="
need xcodegen   "brew install xcodegen"
need zstd       "brew install zstd"
need spirv-cross "brew install spirv-cross"
need dotnet     "brew install --cask dotnet-sdk"
need python3    "the one in the PATH (the venv below is made from it)"
need swift      "Xcode's toolchain"

say
say "=== the Python the upstream script needs ==="
# The upstream packing script needs lz4, capstone and fontTools. The repository gets its own venv
# (nothing is installed system wide, and the user's Python is left alone).
VENV="$HERE/.venv"
if [ ! -x "$VENV/bin/python3" ]; then
  if [ $CHECK -eq 0 ]; then
    say "  making the venv ..."
    python3 -m venv "$VENV" || { say "  ✗ the venv could not be made"; miss=1; }
  fi
fi
if [ -x "$VENV/bin/pip3" ] && [ $CHECK -eq 0 ]; then
  say "  installing lz4 capstone fonttools pillow ..."
  "$VENV/bin/pip3" install --quiet --upgrade lz4 capstone fonttools pillow || { say "  ✗ the install failed"; miss=1; }
fi
if [ -x "$VENV/bin/python3" ]; then
  if "$VENV/bin/python3" -c "import lz4, capstone, fontTools" >/dev/null 2>&1; then
    say "  ✓ $VENV/bin/python3 has lz4, capstone and fontTools"
  else
    say "  ✗ $VENV/bin/python3 is missing lz4 / capstone / fontTools"
    miss=1
  fi
  if "$VENV/bin/python3" -c "import PIL" >/dev/null 2>&1; then say "  ✓ $VENV/bin/python3 has PIL (the .icns writer)"
  else say "  ✗ $VENV/bin/python3 needs Pillow"; miss=1; fi
else
  say "  ✗ no venv at $VENV"
  miss=1
fi

say
say "=== building the launcher ==="
if [ $CHECK -eq 0 ]; then
  ( cd "$HERE" && swift build ) && say "  ✓ swift build" || { say "  ✗ swift build failed"; miss=1; }
fi

say
if [ $miss -eq 0 ]; then say "=== ready ==="; else say "=== something is missing (see above) ==="; fi
exit $miss

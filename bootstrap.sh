#!/bin/bash
# Prepare the repository: the nxnative dependency (a submodule) with our patches on it, and the
# toolchain the pipeline needs.
#
#   ./bootstrap.sh            prepare everything and report what is missing
#   ./bootstrap.sh --check    only report (does not change anything)
#
# The submodule is pinned to the commit our patch was made against (bc5815a). Upstream moves on; when
# it is bumped the patch has to be rebased (git -C nxnative am / git am the patch) and the build
# re-verified -- the patch touches the host's frame pacing, the input layer and the progress view.
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
  say "  cloning the submodule ..."
  git -C "$HERE" submodule update --init --recursive || { say "  ✗ the submodule could not be fetched"; miss=1; }
fi
if [ -d "$HERE/nxnative/dm/host" ]; then
  say "  ✓ nxnative is at $(git -C "$HERE/nxnative" rev-parse --short HEAD)"
  if git -C "$HERE/nxnative" diff --quiet && [ ! -f "$HERE/nxnative/dm/host/front_gamepad_mac.m" ]; then
    if [ $CHECK -eq 0 ]; then
      say "  applying our patches ..."
      for p in "$HERE"/patches/*.patch; do
        git -C "$HERE/nxnative" apply "$p" && say "    ✓ $(basename "$p")" || { say "    ✗ $(basename "$p") did not apply"; miss=1; }
      done
    else
      say "  · the patches are not applied yet (run ./bootstrap.sh)"
    fi
  else
    say "  ✓ our patches are applied"
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
need python3    "the one in the PATH"
need swift      "Xcode's toolchain"
if python3 -c "import lz4, capstone" >/dev/null 2>&1; then say "  ✓ python3 has lz4 + capstone"
else say "  ✗ python3 needs lz4 and capstone: python3 -m pip install lz4 capstone"; miss=1; fi
if python3 -c "import fontTools" >/dev/null 2>&1; then say "  ✓ python3 has fontTools"
else say "  ✗ python3 needs fontTools: python3 -m pip install fonttools"; miss=1; fi
if python3 -c "import PIL" >/dev/null 2>&1; then say "  ✓ python3 has PIL (the .icns writer)"
else say "  ✗ python3 needs Pillow: python3 -m pip install pillow"; miss=1; fi

say
say "=== building the launcher ==="
if [ $CHECK -eq 0 ]; then
  ( cd "$HERE" && swift build ) && say "  ✓ swift build" || { say "  ✗ swift build failed"; miss=1; }
fi

say
if [ $miss -eq 0 ]; then say "=== ready ==="; else say "=== something is missing (see above) ==="; fi
exit $miss

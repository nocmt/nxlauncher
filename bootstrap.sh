#!/bin/bash
# Prepare the pinned dependency and a repository-local Python environment.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CHECK=0
TARGET=mac
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift;;
    --target) TARGET=${2:?missing target}; shift 2;;
    *) printf 'Usage: %s [--check] [--target mac|ios]\n' "$0" >&2; exit 2;;
  esac
done
[[ "$TARGET" == mac || "$TARGET" == ios ]] || { printf 'Invalid target: %s\n' "$TARGET" >&2; exit 2; }
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PY=""
for candidate in "${NXLAUNCHER_PYTHON:-}" python3.14 python3.13 python3.12 python3; do
  [ -n "$candidate" ] || continue
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3,12))' >/dev/null 2>&1; then
    PY=$(command -v "$candidate"); break
  fi
done
[ -n "$PY" ] || { printf 'Python 3.12+ is required. Install it from python.org or Homebrew.\n' >&2; exit 1; }

printf '=== nxnative dependency ===\n'
if [ ! -e "$HERE/nxnative/.git" ]; then
  [ "$CHECK" -eq 0 ] || { printf 'Submodule missing: run ./bootstrap.sh\n' >&2; exit 1; }
  git -C "$HERE" submodule update --init --recursive
fi
if [ "$CHECK" -eq 1 ]; then
  "$PY" "$HERE/Tools/prepare-nxnative.py" --check
else
  "$PY" "$HERE/Tools/prepare-nxnative.py"
fi

VENV="$HERE/.venv"
if [ ! -x "$VENV/bin/python3" ]; then
  [ "$CHECK" -eq 0 ] || { printf 'Local Python environment missing: run ./bootstrap.sh\n' >&2; exit 1; }
  "$PY" -m venv "$VENV"
fi
"$VENV/bin/python3" -c 'import sys; sys.exit(sys.version_info < (3,12))' || {
  printf 'Existing .venv uses an unsupported Python. Preserve it and create a new environment with Python 3.12+.\n' >&2; exit 1;
}
if [ "$CHECK" -eq 0 ]; then
  printf '\n=== Python packages ===\n'
  if "$VENV/bin/python3" -c 'import sys,platform; sys.exit(not (sys.version_info[:2] == (3,13) and platform.system() == "Darwin" and platform.machine() == "arm64"))'; then
    "$VENV/bin/python3" -m pip install --no-index --find-links "$HERE/Resources/wheels" lz4 capstone fonttools pillow backports.zstd
  else
    printf 'Using pinned package versions from the bundled wheel inventory; this interpreter may need downloads.\n'
    "$VENV/bin/python3" - "$HERE" <<'PY'
from pathlib import Path
import subprocess, sys
wheels = sorted((Path(sys.argv[1]) / 'Resources/wheels').glob('*.whl'))
if not wheels:
    raise SystemExit('Bundled wheel inventory is missing.')
requirements = [f'{p.name.split("-")[0]}=={p.name.split("-")[1]}' for p in wheels]
if sys.version_info >= (3, 14):
    requirements = [r for r in requirements if not r.startswith('backports_zstd==')]
subprocess.run([sys.executable, '-m', 'pip', 'install', *requirements], check=True)
PY
  fi
fi
printf '\n=== %s build environment ===\n' "$TARGET"
"$VENV/bin/python3" "$HERE/Tools/pack_pipeline.py" doctor --repo "$HERE/nxnative" --target "$TARGET"
if [ "$CHECK" -eq 0 ]; then
  printf '\n=== Swift launcher ===\n'
  (cd "$HERE" && swift build)
fi
printf '\nPreparation finished. Review the dependency report before building a game.\n'

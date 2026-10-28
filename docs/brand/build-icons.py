#!/usr/bin/env python3
"""Build every icon style into Resources/: the app icon plus the three Dock variants.

The actual rasterisation lives in render.swift, which already knows how to draw the SVGs with
AppKit; this script only drives it so one command refreshes all icon outputs.

Run: python3 docs/brand/build-icons.py
"""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def main() -> int:
    result = subprocess.run(["swift", str(HERE / "render.swift")], capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())

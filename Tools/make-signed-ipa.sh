#!/bin/bash
# Export a complete app whose bundled game resources have already been signed.
# Usage: make-signed-ipa.sh --work DIR [--out FILE] [--repo DIR] [--game ID] [--ver VERSION]
# Missing or different bundled resources require assembling and re-signing the app first.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
exec "${PYTHON:-python3}" "$HERE/make-ipa.py" --signed "$@"

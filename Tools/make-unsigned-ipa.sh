#!/bin/bash
# Export the selected game's unsigned all-in-one IPA, using upstream resource mappings.
# Usage: make-unsigned-ipa.sh --work DIR [--out FILE] [--repo DIR] [--game ID] [--ver VERSION]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
exec "${PYTHON:-python3}" "$HERE/make-ipa.py" "$@"

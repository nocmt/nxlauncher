#!/bin/bash
# Build the app icon: draw the pictures (Scripts/make-icon.swift) and pack them into an .icns.
#
# The result (Resources/AppIcon.icns) is kept in the repository, so a normal build does not have to
# draw it; run this script again after changing the drawing.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
ICONSET="$HERE/dist/AppIcon.iconset"
ICNS="$HERE/Resources/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$(dirname "$ICNS")" || exit 1

swift "$HERE/Scripts/make-icon.swift" "$ICONSET" || { echo "FAIL: drawing the icon"; exit 1; }
iconutil --convert icns "$ICONSET" --output "$ICNS" || { echo "FAIL: iconutil"; exit 1; }
rm -rf "$ICONSET"

echo
echo "the icon: $ICNS"
ls -l "$ICNS"

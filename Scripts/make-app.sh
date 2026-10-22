#!/bin/bash
# Build the launcher into a double-clickable macOS .app.
#
# SwiftPM builds an executable; a macOS app is a bundle around it, so this makes the bundle: the
# binary, an Info.plist and the resources (the tools the pipeline needs are referenced by path, so
# the bundle keeps the repository next to it -- the app finds the tools through NXLAUNCHER_HOME or by
# walking up from the binary).
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$HERE/dist/NxLauncher.app}

cd "$HERE" || exit 1
swift build -c release || { echo "FAIL: swift build"; exit 1; }
BIN=$(swift build -c release --show-bin-path 2>/dev/null)/NxLauncher
[ -x "$BIN" ] || { echo "FAIL: no binary at $BIN"; exit 1; }

# the icon: it is an asset of the repository (Resources/AppIcon.icns)
ICON="$HERE/Resources/AppIcon.icns"
if [ ! -f "$ICON" ]; then
    echo "FAIL: no icon at $ICON"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/NxLauncher"
cp "$ICON" "$OUT/Contents/Resources/AppIcon.icns"

# The app carries its own tools: the pipeline, the upstream source tree and a standalone Python,
# in one archive. The app unpacks it into the cache on the first run, so the app can be shared as
# a single file and needs nothing else from this repository.
bash "$HERE/Scripts/make-home-archive.sh" "$OUT/Contents/Resources/nxlauncher-home.tgz" \
    || { echo "FAIL: the archive"; exit 1; }

cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>NxLauncher</string>
    <key>CFBundleDisplayName</key>          <string>NxLauncher</string>
    <key>CFBundleIdentifier</key>           <string>local.nxlauncher.app</string>
    <key>CFBundleExecutable</key>           <string>NxLauncher</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>0.1.0</string>
    <key>CFBundleVersion</key>              <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSPrincipalClass</key>             <string>NSApplication</string>
</dict>
</plist>
PLIST
plutil -lint "$OUT/Contents/Info.plist" >/dev/null || { echo "FAIL: the Info.plist is not well-formed"; exit 1; }

# where the tools are: the app reads this file (the bundle can live anywhere)
printf '%s' "$HERE" > "$OUT/Contents/Resources/nxlauncher-home.txt"

# an ad-hoc signature: a locally built bundle opens without a Gatekeeper prompt
codesign --force --sign - "$OUT" >/dev/null 2>&1 && echo "  signed (ad-hoc)"

echo
echo "=== the app ==="
du -sh "$OUT"
echo
echo "run it with:  open \"$OUT\""
echo "the tools    : $HERE"

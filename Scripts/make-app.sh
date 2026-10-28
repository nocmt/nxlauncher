#!/bin/bash
# Build a self-contained launcher bundle; publish only after every check succeeds.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT="$HERE/dist/NxLauncher.app"
SIGN_IDENTITY=${DEVELOPER_ID:--}
SIGN_TIMESTAMP=${CODESIGN_TIMESTAMP:-none}
PYTHON_DIR=${NXLAUNCHER_PYTHON_ROOT:-}
OUT_GIVEN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --python) [ "$#" -ge 2 ] || exit 2; PYTHON_DIR=$2; shift 2;;
        --help) printf 'Usage: %s [output.app] [--python ROOT]\n' "$0"; exit 0;;
        --*) echo "FAIL: unknown option $1" >&2; exit 2;;
        *) [ "$OUT_GIVEN" = 0 ] || exit 2; OUT=$1; OUT_GIVEN=1; shift;;
    esac
done

cd "$HERE"
VERSION=$(< "$HERE/VERSION")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "FAIL: VERSION must be major.minor.patch" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
[[ "$OUT" == *.app && ! -L "$OUT" ]] || { echo "FAIL: output must be a non-symlink .app path" >&2; exit 1; }
[ ! -e "$OUT" ] || [ -d "$OUT" ] || { echo "FAIL: output exists and is not an app directory" >&2; exit 1; }
LOCK="$OUT.build-lock"
mkdir "$LOCK" 2>/dev/null || { echo "FAIL: packaging already locked at $LOCK" >&2; exit 1; }
STAGE=""
cleanup() {
    [ -z "$STAGE" ] || rm -rf "$STAGE"
    rmdir "$LOCK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
STAGE=$(mktemp -d "$(dirname "$OUT")/.nxlauncher-app.XXXXXX")
APP="$STAGE/NxLauncher.app"

BUILD_ARGS=(-c release -Xswiftc -debug-prefix-map -Xswiftc "$HERE=/NxLauncher" -Xswiftc -file-prefix-map -Xswiftc "$HERE=/NxLauncher")
swift build "${BUILD_ARGS[@]}"
BIN=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/NxLauncher
[ -x "$BIN" ] || { echo "FAIL: no binary at $BIN" >&2; exit 1; }
ICON="$HERE/Resources/AppIcon.icns"
[ -f "$ICON" ] || { echo "FAIL: no icon at $ICON" >&2; exit 1; }
[ -f "$HERE/Resources/AppIcon.png" ] || { echo "FAIL: no PNG icon at $HERE/Resources/AppIcon.png" >&2; exit 1; }
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Resources/licenses"
cp "$BIN" "$APP/Contents/MacOS/NxLauncher"
# Swift release objects carry absolute DWARF paths even with prefix maps; strip debug
# info from the distributable so no build machine path is embedded. Symbols stay intact.
strip -S "$APP/Contents/MacOS/NxLauncher"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp "$HERE/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
# The Dock-icon choices offered in the settings; missing ones would leave empty previews.
mkdir -p "$APP/Contents/Resources/IconVariants"
for variant in solid outline retro; do
    cp "$HERE/Resources/IconVariants/$variant.png" "$APP/Contents/Resources/IconVariants/$variant.png"
done
cp "$HERE/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$HERE/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp -R "$HERE/Scripts/licenses/." "$APP/Contents/Resources/licenses/"

# Always build a fresh verified payload. A failed archive never touches the old app.
HOME_ARGS=("$APP/Contents/Resources/nxlauncher-home.tgz")
[ -z "$PYTHON_DIR" ] || HOME_ARGS+=(--python "$PYTHON_DIR")
bash "$HERE/Scripts/make-home-archive.sh" "${HOME_ARGS[@]}"
cat > "$APP/Contents/Info.plist" <<PLIST
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
    <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
    <key>CFBundleVersion</key>              <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSPrincipalClass</key>             <string>NSApplication</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
# Release builds must not retain an absolute development-home hint. The bundled archive
# is located relative to the app by the Swift runtime.
if [ "${NXLAUNCHER_DEVELOPMENT_HOME_HINT:-0}" = 1 ]; then
    printf '%s' "$HERE" > "$APP/Contents/Resources/nxlauncher-home.txt"
fi
codesign --force --sign "$SIGN_IDENTITY" --options runtime \
    "$([ "$SIGN_TIMESTAMP" = secure ] && printf '%s' --timestamp || printf '%s' --timestamp=none)" "$APP"
codesign --verify --deep --strict "$APP"

# Both directories are on the output filesystem. macOS RENAME_SWAP exchanges
# nonempty bundles atomically; on failure the old app remains at OUT. After a
# successful exchange the trap removes the previous bundle from STAGE.
python3 - "$APP" "$OUT" <<'PY'
import ctypes
import os
import sys
source, destination = sys.argv[1:]
if os.path.lexists(destination):
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renamex_np
    rename.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint)
    rename.restype = ctypes.c_int
    if rename(os.fsencode(source), os.fsencode(destination), 0x00000002):  # RENAME_SWAP
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), destination)
else:
    os.rename(source, destination)
PY
printf '\n=== NxLauncher %s ===\n' "$VERSION"
du -sh "$OUT"
printf '\nrun it with: open "%s"\nthe tools: %s\n' "$OUT" "$HERE"

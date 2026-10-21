#!/usr/bin/env python3
# Write the Info.plist of the Mac .app from the values the packaging script passes in.
# The plist is written here (not by a here-document in the shell) so the game's name is XML-escaped
# and the file is always well-formed: plutil -lint checks it afterwards.
#
# Usage: make-info-plist.py <out.plist> <bundle name> <display name> <bundle id> <version> <min macOS>
import sys
from xml.sax.saxutils import escape

out, bundle, display, bid, version, minos = sys.argv[1:7]
keys = [
    ('CFBundleName', bundle),
    ('CFBundleDisplayName', display),
    ('CFBundleIdentifier', bid),
    ('CFBundleExecutable', 'BotW'),
    ('CFBundlePackageType', 'APPL'),
    ('CFBundleIconFile', 'AppIcon'),
    ('CFBundleShortVersionString', version),
    ('CFBundleVersion', version),
    ('LSMinimumSystemVersion', minos),
]
body = '\n'.join(f'    <key>{k}</key>{" " * max(1, 24 - len(k))}<string>{escape(v)}</string>' for k, v in keys)
plist = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
{body}
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
    <key>NSRequiresAquaSystemAppearance</key><false/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
'''
with open(out, 'w') as f:
    f.write(plist)
print(f'    Info.plist: {bundle} / {display} / {bid} / {version}')

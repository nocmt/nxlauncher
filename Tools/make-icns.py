#!/usr/bin/env python3
"""Build the macOS .icns from the game's own icon (the English 256x256 one nx_extract saved).

sips cannot be used here (the agent shell's sandbox blocks its temporary file), so the PNGs are
made with PIL and the .icns container is written by hand:
'icns' + the total size, then one entry per icon: the type (4 bytes), the entry length (4 bytes,
including this header) and the data (a PNG for the types below).
"""
import struct
import sys
from io import BytesIO
from pathlib import Path

from PIL import Image

# (type, size in pixels) — the types macOS reads from a modern .icns
SIZES = [
    (b'icp4', 16), (b'icp5', 32), (b'icp6', 64),
    (b'ic07', 128), (b'ic08', 256), (b'ic09', 512), (b'ic10', 1024),
    (b'ic11', 32), (b'ic12', 64), (b'ic13', 256), (b'ic14', 512),
]

src = Path(sys.argv[1])
out = Path(sys.argv[2])
im = Image.open(src).convert('RGBA')

entries = []
for kind, size in SIZES:
    # the 1024 size is the upscaled 256 icon; macOS scales it down for the smaller ones
    scaled = im.resize((size, size), Image.LANCZOS)
    buf = BytesIO()
    scaled.save(buf, format='PNG', optimize=True)
    data = buf.getvalue()
    entries.append(kind + struct.pack('>I', len(data) + 8) + data)

body = b''.join(entries)
out.write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
print(f'{out}: {out.stat().st_size} bytes, {len(entries)} icons (from {src.name} {im.size})')

#!/usr/bin/env python3
"""Generate the gamepad icon variants that share one red tile.

Every variant draws the same single closed silhouette (a chubby pad: 513 x 356, centred on the
tile's optical centre at 512,512), so the styles only differ in fill, and switching styles in the
settings never makes the icon jump. One path also avoids the little notch a body-plus-grips union
leaves at the shoulders.

Run: python3 docs/brand/build-icon-variants.py
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent

TILE_DEFS = '''    <linearGradient id="tile" x1=".15" y1="0" x2=".85" y2="1">
      <stop stop-color="#FF6E62"/><stop offset=".42" stop-color="#F5343C"/><stop offset=".78" stop-color="#E01824"/><stop offset="1" stop-color="#CB111D"/>
    </linearGradient>
    <radialGradient id="glow" cx=".3" cy=".05" r=".9">
      <stop stop-color="#FFF3EF" stop-opacity=".3"/><stop offset=".6" stop-color="#FFD9D4" stop-opacity=".06"/><stop offset="1" stop-color="#B00C18" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="1" y2="1">
      <stop stop-color="#FFF4F0" stop-opacity=".55"/><stop offset=".5" stop-color="#FFC9C3" stop-opacity=".1"/><stop offset="1" stop-color="#8E0A15" stop-opacity=".28"/>
    </linearGradient>
    <linearGradient id="glyph" x1=".18" y1="0" x2=".72" y2="1">
      <stop stop-color="#FFFFFF"/><stop offset=".6" stop-color="#FFF6F3"/><stop offset="1" stop-color="#FFDCD4"/>
    </linearGradient>
'''

TILE = '''  <rect x="108" y="120" width="808" height="808" rx="222" fill="#5C020C" opacity=".13"/>
  <rect x="103" y="110" width="818" height="818" rx="225" fill="#5C020C" opacity=".2"/>
  <rect x="100" y="100" width="824" height="824" rx="228" fill="url(#tile)"/>
  <rect x="100" y="100" width="824" height="824" rx="228" fill="url(#glow)"/>
  <rect x="101.5" y="101.5" width="821" height="821" rx="226.5" fill="none" stroke="url(#rim)" stroke-width="3"/>
'''

# One closed outline: flat top, shoulders swept out, two grips, and a shallow middle recess.
# Bounds x 246..780, y 330..692; centre (513, 511) — visually centred on the tile.
PAD = (
    "M 380 330 L 640 330 "
    "C 708 330 748 368 762 428 "
    "C 776 488 784 556 772 606 "
    "C 760 656 730 686 694 690 "
    "C 658 694 628 672 606 650 "
    "C 592 636 578 630 560 630 "
    "L 464 630 "
    "C 446 630 432 636 418 650 "
    "C 396 672 366 694 330 690 "
    "C 294 686 264 656 252 606 "
    "C 240 556 248 488 262 428 "
    "C 276 368 312 330 380 330 Z"
)

# Controls sit in the upper half of the body: plus pad left, two buttons right.
CONTROLS = '''      <rect x="306" y="462" width="112" height="34" rx="17" fill="#000"/>
      <rect x="345" y="423" width="34" height="112" rx="17" fill="#000"/>
      <circle cx="642" cy="479" r="22" fill="#000"/>
      <circle cx="696" cy="479" r="22" fill="#000"/>'''


def document(title, desc, extra_defs, body):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
  <title id="title">NxLauncher — {title}</title>
  <desc id="desc">{desc}</desc>
  <defs>
{TILE_DEFS}{extra_defs}  </defs>
{TILE}{body}</svg>
'''


# --- solid: filled silhouette with the controls cut through to the tile ----------
solid_defs = f'''    <mask id="pad" maskUnits="userSpaceOnUse" x="230" y="320" width="564" height="392">
      <rect x="230" y="320" width="564" height="392" fill="#000"/>
      <path d="{PAD}" fill="#fff"/>
{CONTROLS}
    </mask>
'''
solid_body = '''  <rect x="230" y="320" width="564" height="392" fill="url(#glyph)" mask="url(#pad)"/>
'''

# --- outline: only the rim, controls solid -------------------------------------
outline_defs = f'''    <mask id="pad" maskUnits="userSpaceOnUse" x="230" y="320" width="564" height="392">
      <rect x="230" y="320" width="564" height="392" fill="#000"/>
      <path d="{PAD}" fill="none" stroke="#fff" stroke-width="34" stroke-linejoin="round"/>
      <rect x="306" y="462" width="112" height="34" rx="17" fill="#fff"/>
      <rect x="345" y="423" width="34" height="112" rx="17" fill="#fff"/>
      <circle cx="642" cy="479" r="24" fill="#fff"/>
      <circle cx="696" cy="479" r="24" fill="#fff"/>
    </mask>
'''
outline_body = '''  <rect x="230" y="320" width="564" height="392" fill="url(#glyph)" mask="url(#pad)"/>
'''

# --- retro: one flat rounded panel with minimal controls ------------------------
retro_defs = '''    <mask id="pad" maskUnits="userSpaceOnUse" x="240" y="368" width="544" height="288">
      <rect x="240" y="368" width="544" height="288" fill="#000"/>
      <rect x="250" y="378" width="524" height="268" rx="134" fill="#fff"/>
      <rect x="316" y="462" width="104" height="32" rx="16" fill="#000"/>
      <rect x="352" y="426" width="32" height="104" rx="16" fill="#000"/>
      <circle cx="636" cy="458" r="21" fill="#000"/>
      <circle cx="688" cy="458" r="21" fill="#000"/>
      <rect x="592" y="540" width="46" height="13" rx="6.5" fill="#000"/>
      <rect x="650" y="540" width="46" height="13" rx="6.5" fill="#000"/>
    </mask>
'''
retro_body = '''  <rect x="240" y="368" width="544" height="288" fill="url(#glyph)" mask="url(#pad)"/>
'''

VARIANTS = {
    # The default artwork keeps the historical file name.
    'app-icon.svg': document(
        'gamepad',
        'Original vector artwork. A soft red gradient macOS tile with one chubby warm-white gamepad: rounded body and grips, a plus pad and two round buttons. No third-party logo or game artwork.',
        solid_defs, solid_body),
    'app-icon-outline.svg': document(
        'gamepad outline',
        'Original vector artwork. A soft red gradient macOS tile with a chubby warm-white outlined gamepad and solid controls. No third-party logo or game artwork.',
        outline_defs, outline_body),
    'app-icon-retro.svg': document(
        'gamepad retro',
        'Original vector artwork. A soft red gradient macOS tile with a flat warm-white retro gamepad panel and minimal controls. No third-party logo or game artwork.',
        retro_defs, retro_body),
}

for name, svg in VARIANTS.items():
    (HERE / name).write_text(svg)
    print('wrote docs/brand/' + name)

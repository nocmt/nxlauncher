#!/usr/bin/env python3
"""Build the standalone README banner from the original editable icon SVG.

Usage: python3 docs/brand/build-hero.py
No third-party modules, network requests, fonts, or linked image resources.
The output is plain static SVG and works in GitHub's image sandbox.
"""
from pathlib import Path
import xml.etree.ElementTree as ET

BRAND = Path(__file__).resolve().parent
icon = (BRAND / "app-icon.svg").read_text()
# Keep vector geometry, gradients and accessibility text; no base64 raster data.
icon_body = icon[icon.index(">") + 1:icon.rindex("</svg>")]
icon_body = icon_body.replace('id="title"', 'id="iconTitle"').replace('id="desc"', 'id="iconDesc"')
hero = '''<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="640" viewBox="0 0 1600 640" role="img" aria-labelledby="heroTitle heroDesc">
  <title id="heroTitle">NxLauncher</title>
  <desc id="heroDesc">Your library. A new launch. An original warm-white library portal on a vivid red background.</desc>
  <defs>
    <linearGradient id="canvas" x1=".05" y1="0" x2=".95" y2="1"><stop stop-color="#ff625c"/><stop offset=".5" stop-color="#e6242c"/><stop offset="1" stop-color="#bd0d1b"/></linearGradient>
    <radialGradient id="halo" cx=".78" cy=".4" r=".62"><stop stop-color="#fff2ec" stop-opacity=".3"/><stop offset="1" stop-color="#c1101c" stop-opacity="0"/></radialGradient>
    <linearGradient id="rule" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#fff6f2"/><stop offset="1" stop-color="#fff6f2" stop-opacity="0"/></linearGradient>
    <linearGradient id="word" x1="0" y1="0" x2=".7" y2="1"><stop stop-color="#ffffff"/><stop offset="1" stop-color="#ffe6e2"/></linearGradient>
  </defs>
  <rect width="1600" height="640" rx="28" fill="url(#canvas)"/>
  <rect width="1600" height="640" rx="28" fill="url(#halo)"/>
  <rect x=".75" y=".75" width="1598.5" height="638.5" rx="27.25" fill="none" stroke="#ffd9d4" stroke-opacity=".35" stroke-width="1.5"/>
  <!-- Quiet drafting traces echo the angle of the original library strata. -->
  <g fill="none" stroke="#ffd0cb" stroke-width="1">
    <path d="M788 410L1192 176Q1210 166 1228 176L1580 379" stroke="#ff9d97" stroke-opacity=".5"/>
    <path d="M788 447L1192 213Q1210 203 1228 213L1580 416" stroke="#ff8a83" stroke-opacity=".42"/>
    <path d="M788 484L1192 250Q1210 240 1228 250L1580 453" stroke="#ff7a72" stroke-opacity=".34"/>
  </g>
  <path d="M104 144H158" stroke="#ffe9e5" stroke-width="3" stroke-linecap="round"/>
  <text x="180" y="150" fill="#ffd9d4" font-family="'Avenir Next',Avenir,'Trebuchet MS',sans-serif" font-size="17" font-weight="600" letter-spacing="4">LIBRARY / BUILD / LAUNCH</text>
  <text x="99" y="302" fill="url(#word)" font-family="'Avenir Next',Avenir,'Trebuchet MS',sans-serif" font-size="105" font-weight="650" letter-spacing="-5">NxLauncher</text>
  <text x="106" y="371" fill="#ffe3df" font-family="'Avenir Next',Avenir,'Trebuchet MS',sans-serif" font-size="31" font-weight="400" letter-spacing=".1">Your library. A new launch.</text>
  <path d="M106 432H604" stroke="url(#rule)" stroke-opacity=".5"/>
  <text x="106" y="489" fill="#ffcfc9" font-family="'Avenir Next',Avenir,'Trebuchet MS',sans-serif" font-size="18" letter-spacing="1">A considered home for your games.</text>
  <svg x="915" y="19" width="602" height="602" viewBox="0 0 1024 1024" aria-labelledby="iconTitle iconDesc">
''' + icon_body + '''
  </svg>
</svg>
'''
ET.fromstring(hero)  # Fail before writing if the source introduced invalid XML.
(BRAND / "hero.svg").write_text(hero)
print("Built docs/brand/hero.svg (standalone original vectors)")

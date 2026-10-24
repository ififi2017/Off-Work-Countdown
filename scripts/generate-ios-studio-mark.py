"""Outline the web footer's fi_niaR Studio mark for the iOS asset catalog.

Mirrors components/off-work-countdown.tsx: "> fi_niaR Studio" in Geist Mono
Bold, -0.01em tracking, 0.4em after the chevron and a 0.55em x 0.95em cursor
block 0.15em after the text. Text uses iOS secondaryLabel; accents use the
web footer's blue. Requires fontTools (`pip install fonttools`).

    python3 scripts/generate-ios-studio-mark.py
"""
import os
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.misc.transform import Transform
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src-mobile/ios/App/App/Assets.xcassets/StudioMark.imageset")
font = instantiateVariableFont(TTFont(os.path.join(ROOT, "app/fonts/GeistMonoVF.woff")), {"wght": 700})
gs = font.getGlyphSet(); cmap = font.getBestCmap(); hmtx = font["hmtx"]
EM = 1000; track = -0.01 * EM
def run(text, x):
    out = []
    for ch in text:
        name = cmap[ord(ch)]
        out.append((name, x)); x += hmtx[name][0] + track
    return out, x
chev, x = run(">", 0); x += 0.4 * EM
word, x = run("fi_niaR Studio", x)
cx = x + 0.15 * EM; cw, ch = 0.55 * EM, 0.95 * EM
def paths(items):
    pen = SVGPathPen(gs, ntos=lambda v: ("%.1f" % v).rstrip("0").rstrip(".")); bp = BoundsPen(gs)
    for name, gx in items:
        t = Transform(1, 0, 0, -1, gx, 0)
        gs[name].draw(TransformPen(pen, t)); gs[name].draw(TransformPen(bp, t))
    return pen.getCommands(), bp.bounds
cp, cb = paths(chev); wp, wb = paths(word)
top = min(cb[1], wb[1], -ch); bottom = max(cb[3], wb[3], 0)
left = min(cb[0], wb[0], 0); right = cx + cw
vb = f"{left:.0f} {top:.0f} {right-left:.0f} {bottom-top:.0f}"
def svg(text_fill, text_op, accent):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" width="{(right-left)/EM*17:.2f}" height="{(bottom-top)/EM*17:.2f}">
<path fill="{accent}" d="{cp}"/>
<path fill="{text_fill}" fill-opacity="{text_op}" d="{wp}"/>
<rect fill="{accent}" fill-opacity="0.85" x="{cx:.0f}" y="{-ch:.0f}" width="{cw:.0f}" height="{ch:.0f}"/>
</svg>
'''
open(os.path.join(OUT, "studio-light.svg"), "w").write(svg("#3C3C43", "0.6", "#2F6FDB"))
open(os.path.join(OUT, "studio-dark.svg"), "w").write(svg("#EBEBF5", "0.6", "#7AA7FF"))

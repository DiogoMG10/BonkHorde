"""Top-down plan of the exported world: hillshaded terrain coloured by surface,
props by kind, interactable anchors, paths and landmark sites.

    python tools/map/plan_world.py work/map/world.json work/map/plan_world.png
"""

import json
import math
import sys

from PIL import Image, ImageDraw

src = sys.argv[1] if len(sys.argv) > 1 else "work/map/world.json"
dst = sys.argv[2] if len(sys.argv) > 2 else "work/map/plan_world.png"
W = json.load(open(src, encoding="utf-8"))
n, cell, half = W["n"], W["cell"], W["half"]
H = W["heights"]
S = W["surfaces"]
PX = 3  # pixels per cell
size = (n - 1) * PX

COL = {
    "Grass": (110, 150, 55), "Meadow": (128, 160, 60), "LeafyGrass": (72, 122, 52), "Lush": (78, 128, 52),
    "Carpet": (118, 166, 60),
    "Ground": (110, 85, 58), "Path": (150, 118, 80), "Mud": (80, 62, 44), "ForestFloor": (60, 80, 42),
    "Rock": (105, 105, 105), "Slate": (80, 82, 88), "Cliff": (120, 115, 105), "Sand": (180, 160, 112),
    "Pavement": (140, 140, 132), "Cobblestone": (128, 126, 116), "Snow": (236, 242, 246),
}

img = Image.new("RGB", (size, size))
px = img.load()
for iz in range(n - 1):
    for ix in range(n - 1):
        a = iz * n + ix
        dzdx = (H[a + 1] - H[a]) / cell
        dzdz = (H[a + n] - H[a]) / cell
        shade = max(0.35, min(1.25, 1 + (-dzdx * 0.6 + dzdz * 0.6)))
        c = COL.get(S[a], (255, 0, 255))
        hh = H[a] / 80
        c = tuple(int(min(255, v * shade * (0.85 + 0.3 * hh))) for v in c)
        for oy in range(PX):
            for ox in range(PX):
                # north (+z) at the top of the image
                px[ix * PX + ox, size - 1 - (iz * PX + oy)] = c

d = ImageDraw.Draw(img)


def to_px(x, z):
    return ((x + half) / cell * PX, size - 1 - (z + half) / cell * PX)


for w in W.get("water") or []:
    x, y = to_px(w["x"], w["z"])
    r = w["r"] / cell * PX
    d.ellipse((x - r, y - r, x + r, y + r), outline=(80, 170, 220), width=2)

KIND = {
    "Spruce": (25, 70, 55), "SpruceFar": (25, 70, 55), "SpruceRidge": (25, 70, 55), "Pine": (60, 110, 70),
    "Birch": (230, 230, 210), "Beech": (150, 210, 70), "Oak": (120, 180, 60), "OakLeaning": (120, 180, 60),
    "Sapling": (170, 220, 90), "Elder": (255, 230, 90), "AncientOak": (255, 230, 90), "AncientPine": (255, 230, 90),
}
for p in W["props"]:
    x, y = to_px(p["x"], p["z"])
    k = p["kind"]
    c = KIND.get(k)
    if c is None:
        if "Ruin" in k or "Ward" in k or "Pillar" in k or "Menhir" in k or "Gate" in k or "Steps" in k:
            c = (235, 235, 240)
        elif "Boulder" in k or "Rock" in k:
            c = (175, 175, 180)
        elif "Flower" in k:
            c = (255, 140, 200)
        else:
            c = (120, 100, 70)
    r = 2 if k in KIND else 1.2
    d.ellipse((x - r, y - r, x + r, y + r), fill=c)

for a in W["anchors"]:
    x, y = to_px(a[0], a[1])
    d.rectangle((x - 1.5, y - 1.5, x + 1.5, y + 1.5), outline=(255, 255, 0))

for path in W.get("paths") or []:
    pts = [to_px(p[0], p[1]) for p in path["points"]]
    d.line(pts, fill=(255, 220, 150), width=1)

for s in W.get("sites") or []:
    x, y = to_px(s["x"], s["z"])
    d.text((x + 4, y - 6), s["name"], fill=(255, 255, 255))
    d.ellipse((x - 3, y - 3, x + 3, y + 3), outline=(255, 60, 60), width=2)

x0, y0 = to_px(0, 0)
d.ellipse((x0 - 4, y0 - 4, x0 + 4, y0 + 4), fill=(255, 0, 0))
img.save(dst)
print("plan ->", dst)

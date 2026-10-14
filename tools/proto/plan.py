"""Top-down plan of the Wardwood prototype region.

Reads work/map/layout_wardwood.json (written by `lune run tools/map/prove.luau
wardwood`) and draws work/proto/plan_wardwood.png: ground height, the clearing
and spawn keep-clear circles, paths, anchors, every Wardwood prop at its real
position and size (trunks with their canopy spread), and the viewpoints with
the direction they face. MossyWoods props just outside the region are drawn
faintly for context.

    python tools/proto/plan.py
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
LAYOUT = ROOT / "work" / "map" / "layout_wardwood.json"
OUT = ROOT / "work" / "proto" / "plan_wardwood.png"

PX = 4  # pixels per stud
MARGIN = 24  # studs of context round the region


def main():
    layout = json.loads(LAYOUT.read_text())
    ww = layout["wardwood"]
    reg = ww["region"]
    x0, x1 = reg["minX"] - MARGIN, reg["maxX"] + MARGIN
    z0, z1 = reg["minZ"] - MARGIN, reg["maxZ"] + MARGIN
    w, h = int((x1 - x0) * PX), int((z1 - z0) * PX)

    # north (+z) at the top of the image
    def at(x, z):
        return ((x - x0) * PX, (z1 - z) * PX)

    img = Image.new("RGB", (w, h))
    px = img.load()
    half, cell, rows = layout["half"], layout["cell"], layout["heights"]
    for iy in range(h):
        z = z1 - iy / PX
        for ix in range(w):
            x = x0 + ix / PX
            gi = min(max(int((x + half) / cell), 0), len(rows[0]) - 1)
            gj = min(max(int((z + half) / cell), 0), len(rows) - 1)
            v = rows[gj][gi]
            shade = max(0, min(255, int(70 + v * 3)))
            px[ix, iy] = (int(shade * 0.55), int(shade * 0.75), int(shade * 0.5))

    d = ImageDraw.Draw(img, "RGBA")
    # region, clearing, spawn keep-clear, band edge
    d.rectangle([at(reg["minX"], reg["maxZ"]), at(reg["maxX"], reg["minZ"])], outline=(255, 255, 255, 160), width=2)
    for r, col in ((ww["clearing"], (255, 220, 140, 200)), (ww["spawnKeepClear"], (255, 255, 255, 120))):
        d.ellipse([at(-r, r), at(r, -r)], outline=col, width=2)
    d.line([at(ww["bandMaxX"], reg["minZ"]), at(ww["bandMaxX"], reg["maxZ"])], fill=(120, 200, 255, 110), width=1)
    # paths
    for path in ww["paths"]:
        pts = [at(p[0], p[1]) for p in path]
        d.line(pts, fill=(200, 170, 110, 110), width=int(ww["pathHalfWidth"] * 2 * PX))

    def circle(x, z, r, fill=None, outline=None, width=1):
        cx, cy = at(x, z)
        d.ellipse([cx - r * PX, cy - r * PX, cx + r * PX, cy + r * PX], fill=fill, outline=outline, width=width)

    for a in layout["anchors"]:
        circle(a["x"], a["z"], 1.2, fill=(255, 255, 255, 200))

    inside = lambda p: reg["minX"] <= p["x"] <= reg["maxX"] and reg["minZ"] <= p["z"] <= reg["maxZ"]  # noqa: E731
    for p in layout["props"]:
        k, x, z, s = p["kind"], p["x"], p["z"], p["scale"]
        if not k.startswith("WW_"):
            if x0 <= x <= x1 and z0 <= z <= z1 and p["radius"] > 0:
                circle(x, z, p["radius"], outline=(255, 255, 255, 70))
            continue
        if k == "WW_Trunk":
            circle(x, z, 5.5 * s, fill=(30, 70, 45, 120))  # canopy spread
            circle(x, z, p["radius"], fill=(70, 45, 30, 255))
        elif k == "WW_Slab":
            circle(x, z, p["radius"], fill=(140, 150, 145, 230), outline=(90, 140, 70, 255), width=2)
        elif k == "WW_Fern":
            circle(x, z, 1.4 * s, fill=(80, 150, 70, 200))
        elif k == "WW_Tile":
            hs = 2.85
            c, sn = math.cos(p["yaw"]), math.sin(p["yaw"])
            corners = [(-hs, -hs), (hs, -hs), (hs, hs), (-hs, hs)]
            d.polygon([at(x + lx * c + lz * sn, z - lx * sn + lz * c) for lx, lz in corners], fill=(170, 170, 160, 230))
        elif k in ("WW_Pillar", "WW_PillarBroken"):
            circle(x, z, p["radius"], fill=(210, 210, 200, 255))
        elif k == "WW_Brazier":
            circle(x, z, 9, fill=(255, 150, 60, 60))  # rough light pool
            circle(x, z, p["radius"], fill=(255, 150, 60, 255))
        elif k == "WW_WardStone":
            circle(x, z, p["radius"], fill=(255, 190, 110, 255))

    ward = next((p for p in layout["props"] if p["kind"] == "WW_Brazier"), None)
    for i, v in enumerate(ww["viewpoints"], 1):
        tx, tz = (ward["x"], ward["z"]) if v.get("lookAt") == "ward" and ward else (v.get("lookX", 0), v.get("lookZ", 0))
        dx, dz = tx - v["x"], tz - v["z"]
        n = math.hypot(dx, dz) or 1
        d.line([at(v["x"], v["z"]), at(v["x"] + dx / n * 30, v["z"] + dz / n * 30)], fill=(120, 220, 255, 255), width=2)
        circle(v["x"], v["z"], 2.5, fill=(120, 220, 255, 255))
        d.text((at(v["x"], v["z"])[0] + 8, at(v["x"], v["z"])[1] - 6), f"cam {i}", fill=(255, 255, 255, 255))

    counts = {}
    for p in layout["props"]:
        if p["kind"].startswith("WW_") and inside(p):
            counts[p["kind"]] = counts.get(p["kind"], 0) + 1
    legend = [
        "Wardwood prototype region (north up, 4 px per stud)",
        "gold ring: clearing   white ring: spawn keep-clear   blue line: band edge",
        "white dots: anchors   tan bands: paths   blue: viewpoints",
        "  ".join(f"{k[3:]}={n}" for k, n in sorted(counts.items())),
    ]
    d.rectangle([0, 0, w, 14 * len(legend) + 8], fill=(0, 0, 0, 160))
    for i, line in enumerate(legend):
        d.text((8, 4 + 14 * i), line, fill=(255, 255, 255, 255))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"{OUT.relative_to(ROOT)} {w}x{h}")


if __name__ == "__main__":
    main()

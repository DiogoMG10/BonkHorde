"""Before/after previews of the M3.B art across the Wardwood, from the game's
own camera, offline (Blender renders: shape and palette only, never Studio).

    python tools/art/preview_map.py [outdir]

For each spot: exports the world once as the old props and once as a client
standing there draws the kit (tools/map/export_world.luau ... art x z), renders
a gameplay view and a raised view of both, and tiles them into
<outdir>/map_ab.jpg (old left, new right).
"""

import json
import os
import subprocess
import sys

from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "work/art/map"
BLENDER = os.environ.get("BLENDER", "blender")
SPOTS = [
    ("spawn", 0, 0, 200),
    ("old_grove", -372, -40, 110),
    ("dense_wood", -300, 120, 160),
    ("north_meadow", 90, 300, 200),
    ("thornwood", 250, -150, 250),
]

os.makedirs(OUT, exist_ok=True)


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


before = os.path.join(OUT, "world_before.json")
run(["lune", "run", "tools/map/export_world.luau", before, "short"])
W = json.load(open(before, encoding="utf-8"))
n, cell, half, H = W["n"], W["cell"], W["half"], W["heights"]


def height(x, z):
    fx = min(max((x + half) / cell, 0), n - 1.001)
    fz = min(max((z + half) / cell, 0), n - 1.001)
    ix, iz = int(fx), int(fz)
    tx, tz = fx - ix, fz - iz
    h = lambda a, b: H[b * n + a]
    return (h(ix, iz) * (1 - tx) + h(ix + 1, iz) * tx) * (1 - tz) + (h(ix, iz + 1) * (1 - tx) + h(ix + 1, iz + 1) * tx) * tz


rows = []
for name, x, z, yaw in SPOTS:
    after = os.path.join(OUT, f"world_{name}.json")
    # a leading space, or lune takes "-372" for one of its own flags
    run(["lune", "run", "tools/map/export_world.luau", after, "short", "art", f" {x}", f" {z}"])
    import math
    a = math.radians(yaw)
    ex, ez = x + math.sin(a) * 70, z + math.cos(a) * 70
    views = [
        {"name": f"{name}_game", "x": x, "z": z, "yaw": yaw},
        {"name": f"{name}_raised", "eye": [ex, height(ex, ez) + 45, ez], "target": [x, height(x, z) + 6, z], "fov": 70},
    ]
    vfile = os.path.join(OUT, f"views_{name}.json")
    json.dump(views, open(vfile, "w"))
    for tag, world in (("before", before), ("after", after)):
        run([BLENDER, "-b", "-P", "tools/map/preview_blender.py", "--", world, os.path.join(OUT, tag), vfile])
    for v in views:
        a_img = Image.open(os.path.join(OUT, "before", v["name"] + ".png")).convert("RGB")
        b_img = Image.open(os.path.join(OUT, "after", v["name"] + ".png")).convert("RGB")
        s = 640 / a_img.width
        a_img = a_img.resize((640, int(a_img.height * s)))
        b_img = b_img.resize((640, int(b_img.height * s)))
        row = Image.new("RGB", (1286, a_img.height))
        row.paste(a_img, (0, 0))
        row.paste(b_img, (646, 0))
        rows.append(row)
    print("rendered", name)

sheet = Image.new("RGB", (1286, sum(r.height + 6 for r in rows)))
y = 0
for r in rows:
    sheet.paste(r, (0, y))
    y += r.height + 6
sheet.save(os.path.join(OUT, "map_ab.jpg"), quality=84)
print("sheet", os.path.join(OUT, "map_ab.jpg"))

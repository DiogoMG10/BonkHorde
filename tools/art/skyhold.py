"""Blender side of the Skyhold kit (T6/T7): the island hub's art.

    lune run tools/art/skyhold_plan.luau                       (the island's plan, from the game's own code)
    "$BLENDER" -b -P tools/art/skyhold.py -- [--render DIR] [--no-glb]
    "$BLENDER" -b assets/art/skyhold_kit.blend -P tools/art/skyhold.py -- --from-blend [--render DIR]

Builds every asset (tools/art/skyhold_land.py, skyhold_props.py), one
collection each under "Kit", and lays the island out as instances in the
"Layout" collection (and the far scenery in "Decor"), then writes:

  assets/art/skyhold_kit.blend          the editable source: move an instance in
                                        Layout, then export with --from-blend
  src/server/Skyhold/Meshes/<Asset>.luau  each asset packed for the game (positions,
                                        normals, vertex colours), baked at server start
  src/server/Skyhold/Layout.luau        where every piece stands on the island
  src/shared/Config/SkyholdDecor.luau   the clouds and the far peak (drawn by clients)
  assets/art/export/skyhold/<Asset>.glb importable copies, for a future upload
  assets/art/skyhold_manifest.json      triangles, parts and sizes per asset

--render DIR also renders the island from several angles into DIR (EEVEE;
shape, composition and palette only: Roblox's lighting and materials differ).
"""

from __future__ import annotations

import json
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import skyhold_land as LAND  # noqa: E402
import skyhold_props as PROPS  # noqa: E402
import skyhold_util as U  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
FROM_BLEND = "--from-blend" in ARGS
NO_GLB = "--no-glb" in ARGS
RENDER = ARGS[ARGS.index("--render") + 1] if "--render" in ARGS else None

PLAN = json.load(open(os.path.join(ROOT, "work", "skyhold", "plan.json")))
A = PLAN["anchors"]


def B(x, y, z):
    """An island-local Roblox point in Blender space."""
    return Vector((x, -z, y))


def ground(x, z):
    """The island's ground height (island-local) at a Roblox (x, z), from the plan."""
    g = PLAN["grid"]
    fx = (x - g["x0"]) / g["step"]
    fz = (z - g["z0"]) / g["step"]
    ix, iz = int(math.floor(fx)), int(math.floor(fz))
    tx, tz = fx - ix, fz - iz
    vals = []
    for dz in (0, 1):
        for dx in (0, 1):
            cx = min(max(ix + dx, 0), g["nx"] - 1)
            cz = min(max(iz + dz, 0), g["nz"] - 1)
            h = g["h"][cz * g["nx"] + cx]
            vals.append(h if h is not False else None)
    known = [v for v in vals if v is not None]
    if not known:
        return 0.0
    vals = [v if v is not None else sum(known) / len(known) for v in vals]
    top = vals[0] + (vals[1] - vals[0]) * tx
    bottom = vals[2] + (vals[3] - vals[2]) * tx
    return top + (bottom - top) * tz


def surface(x, z):
    g = PLAN["grid"]
    ix = int(round((x - g["x0"]) / g["step"]))
    iz = int(round((z - g["z0"]) / g["step"]))
    if 0 <= ix < g["nx"] and 0 <= iz < g["nz"]:
        return g["surface"][iz * g["nx"] + ix]
    return False


# ------------------------------------------------------------------ the kit


ASSETS = []  # (name, builder(coll))


def asset(name):
    def wrap(fn):
        ASSETS.append((name, fn))
        return fn

    return wrap


def rim_points(key):
    return [(p[0], -p[1], p[2]) for p in PLAN[key]]


asset("IslandRock")(lambda c: LAND.rock_mass(c, "Rock", rim_points("outline"), depth=150, seed=3, crystals=16, vines=90, apron=2.8))
asset("IsletRock")(lambda c: LAND.rock_mass(c, "Rock", rim_points("islet"), depth=70, seed=9, scale=0.7, spikes=4, crystals=4, vines=24, apron=2.8))
asset("FloatIsleA")(lambda c: LAND.float_isle(c, "Isle", 22, 101))
asset("FloatIsleB")(lambda c: LAND.float_isle(c, "Isle", 14, 102))
asset("FloatIsleC")(lambda c: LAND.float_isle(c, "Isle", 9, 103))
asset("CloudA")(lambda c: LAND.cloud(c, "Cloud", 120, 201, flat=0.42))
asset("CloudB")(lambda c: LAND.cloud(c, "Cloud", 80, 202, flat=0.55))
asset("CloudC")(lambda c: LAND.cloud(c, "Cloud", 54, 203, flat=0.65))
asset("CloudD")(lambda c: LAND.cloud(c, "Cloud", 170, 204, flat=0.3))
asset("FarPeak")(lambda c: LAND.far_peak(c, "Peak", 301))
asset("Falls")(lambda c: LAND.waterfall(c, "Water", 70, 5, 401))
asset("Portal")(lambda c: PROPS.portal(c, A["portalCentreHeight"]))
asset("RuneStone")(lambda c: PROPS.rune_stone(c))
asset("Plaza")(lambda c: PROPS.plaza(c))
asset("RuneCircle")(lambda c: PROPS.rune_circle(c, A["circleRadius"], A["squad"]))
asset("HeroPlinth")(lambda c: PROPS.plinth(c))
asset("Colonnade")(lambda c: PROPS.colonnade(c))
asset("HallFloor")(lambda c: PROPS.hall_floor(c))
asset("Brazier")(lambda c: PROPS.brazier(c))
asset("Stairs")(lambda c: PROPS.stairs(c))
asset("RuinWallLong")(lambda c: PROPS.ruin_wall(c, "Wall", 14, 6.5, 501))
asset("RuinWallShort")(lambda c: PROPS.ruin_wall(c, "Wall", 8, 4.0, 502))
asset("RuinWallLow")(lambda c: PROPS.ruin_wall(c, "Wall", 11, 2.6, 503))
asset("TrophyWall")(lambda c: PROPS.trophy_wall(c))
asset("Lantern")(lambda c: PROPS.lantern(c))
asset("Bench")(lambda c: PROPS.bench(c))
asset("StallTeal")(lambda c: PROPS.stall(c, "teal", 601))
asset("StallCoral")(lambda c: PROPS.stall(c, "coral", 602))
asset("StallSaffron")(lambda c: PROPS.stall(c, "saffron", 603))
asset("Barrels")(lambda c: PROPS.barrels(c))
asset("BannerTeal")(lambda c: PROPS.banner_pole(c, "teal", 701))
asset("BannerSaffron")(lambda c: PROPS.banner_pole(c, "saffron", 702))
asset("FlowersWhite")(lambda c: PROPS.flowers(c, U.rgb(250, 248, 240), 801))
asset("FlowersPink")(lambda c: PROPS.flowers(c, U.rgb(240, 150, 186), 802))
asset("FlowersBlue")(lambda c: PROPS.flowers(c, U.rgb(120, 156, 236), 803))
asset("FlowersGold")(lambda c: PROPS.flowers(c, U.rgb(252, 214, 84), 804))
asset("Telescope")(lambda c: PROPS.telescope(c))
asset("LookoutRail")(lambda c: PROPS.railing(c, 9.0, math.radians(150), math.radians(300)))


def bridge_builder(c):
    a, b = A["bridge"]["from"], A["bridge"]["to"]
    pa = B(a[0], ground(a[0] * 0.97, a[1] * 0.97) + 0.1, a[1])
    pb = B(b[0], ground(b[0] * 1.02, b[1] * 1.02) + 0.1, b[1])
    PROPS.bridge(c, pa, pb)


asset("Bridge")(bridge_builder)


# ------------------------------------------------------------------ the layout (island-local Roblox studs)

LAYOUT = []  # dicts
DECOR = []
rnd = random.Random(20261021)


def put(asset_name, x, z, yaw=0.0, dy=0.0, scale=1.0, name=None, y=None, kit="skyhold", **flags):
    LAYOUT.append(
        dict(asset=asset_name, x=x, y=(ground(x, z) + dy) if y is None else y, z=z, yaw=yaw, scale=scale, name=name, kit=kit, **flags)
    )


def decor(asset_name, x, y, z, yaw=0.0, scale=1.0):
    DECOR.append(dict(asset=asset_name, x=x, y=y, z=z, yaw=yaw, scale=scale))


def trunk(asset_name, scale):
    sizes = {"Oak": (2.6, 9), "Birch": (1.4, 12), "Beech": (2.2, 10), "Elder": (7, 26), "AncientOak": (8, 30), "Pine": (1.8, 14), "Spruce": (1.8, 14), "Sapling": (0.8, 5)}
    for k, (d, h) in sizes.items():
        if asset_name.startswith(k):
            return [round(d * scale, 2), round(h * scale, 2)]
    return None


def layout():
    plaza = A["plaza"]
    portal = A["portal"]
    put("Portal", portal["x"], portal["z"], yaw=portal["yaw"], name="Portal")
    ph = ground(portal["x"], portal["z"])
    for k in range(8):
        a = k / 8 * math.tau
        put("RuneStone", portal["x"] + math.cos(a) * 23, portal["z"] - 1.0, y=ph + A["portalCentreHeight"] + math.sin(a) * 23, name=f"Orbit{k + 1}", collide=False, scale=1.4)
    for side in (-1, 1):
        put("Brazier", portal["x"] + side * 16, portal["z"] + 11.5)
    put("Plaza", plaza["x"], plaza["z"], name="Plaza")
    for i, c in enumerate(A["circles"]):
        put("RuneCircle", c["x"], c["z"], dy=0.22, name=f"Circle{i + 1}")
    for i, p in enumerate(A["plinths"]):
        put("HeroPlinth", p["x"], p["z"], yaw=p["yaw"], name=f"Plinth{i + 1}")
    put("HallFloor", -96, -18, dy=-0.05)
    put("Colonnade", -96, -18, dy=0.35)
    for z in (-31, -5):
        put("Brazier", -92, z, dy=0.35)
    put("Stairs", 0, 7.2, dy=-0.15, name="Stairs")
    tr = A["trophy"]
    put("TrophyWall", tr["x"], tr["z"] + 4, name="Trophies")
    lo = A["lookout"]
    put("LookoutRail", lo["x"], lo["z"])
    put("Telescope", lo["x"] - 3.5, lo["z"] + 4.0, yaw=-45)
    put("Bench", lo["x"] + 6, lo["z"] - 6, yaw=-135, seat=True)
    put("IslandRock", 0, 0, y=0)
    put("IsletRock", 0, 0, y=0)
    put("Bridge", 0, 0, y=0)
    put("Falls", 137, 22, y=-6, yaw=90)

    # the market islet: closed stalls for traders to come, barrels, a lantern
    put("StallTeal", 146, 128, yaw=200)
    put("StallCoral", 168, 136, yaw=250)
    put("StallSaffron", 150, 152, yaw=330)
    put("Barrels", 162, 152, yaw=20)
    put("Lantern", 134, 124, yaw=135)
    put("BannerSaffron", 176, 128, yaw=250)

    # lanterns along the main way up, pairs facing the path
    for z in (90, 68, 46, 24):
        put("Lantern", 6.5, z, yaw=-90)
        put("Lantern", -6.5, z - 11, yaw=90)
    # round the plaza, by its ways in
    for a in (-60, -120, 120, 60, 0, 180):
        r = 39
        x = plaza["x"] + math.cos(math.radians(a)) * r
        z = plaza["z"] - math.sin(math.radians(a)) * r
        put("Lantern", x, z, yaw=a - 90)
    # banners flanking the stairs' top, and round the plaza
    put("BannerTeal", -9.5, -4.5, yaw=0)
    put("BannerSaffron", 9.5, -4.5, yaw=0)
    for k, a in enumerate((-30, -150, 150, 30)):
        x = plaza["x"] + math.cos(math.radians(a)) * 41
        z = plaza["z"] - math.sin(math.radians(a)) * 41
        put("BannerTeal" if k % 2 == 0 else "BannerSaffron", x, z, yaw=a - 90)

    # the knoll: the Elder, benches looking out over the clouds
    t = A["tree"]
    put("Elder", t["x"], t["z"], kit="wardwood", scale=0.75, trunk=trunk("Elder", 0.75))
    for k, a in enumerate((-30, 20, 70)):
        r = 24
        x = t["x"] + math.cos(math.radians(a)) * r
        z = t["z"] + math.sin(math.radians(a)) * r
        put("Bench", x, z, yaw=-a - 90 + 180, seat=True)
    put("Lantern", t["x"] - 20, t["z"] + 14, yaw=45)
    put("Lantern", t["x"] + 18, t["z"] + 26, yaw=-45)

    # ruins: framing the hall, along the north rim, by the lookout
    for x, z, yaw, kind in (
        (-128, -70, 20, "RuinWallLong"),
        (-136, 30, 100, "RuinWallShort"),
        (-118, 62, 75, "RuinWallLow"),
        (-40, -112, 5, "RuinWallLong"),
        (40, -116, -8, "RuinWallShort"),
        (108, -70, -40, "RuinWallLow"),
        (-92, 100, 30, "RuinWallLow"),
        (-58, 112, 0, "RuinWallShort"),
        (118, 54, -70, "RuinWallLow"),
    ):
        put(kind, x, z, yaw=yaw)

    # bunting: across the way up, and from the stairs' banners to the plaza lanterns
    runs = []

    def post_top(x, z, h=6.6):
        return tuple(B(x, ground(x, z) + h, z))

    for z in (90, 68, 46, 24):
        runs.append((post_top(6.5, z), post_top(-6.5, z - 11)))
    runs.append((post_top(-9.5, -4.5, 12.5), post_top(plaza["x"] + math.cos(math.radians(-120)) * 39, plaza["z"] - math.sin(math.radians(-120)) * 39)))
    runs.append((post_top(9.5, -4.5, 12.5), post_top(plaza["x"] + math.cos(math.radians(-60)) * 39, plaza["z"] - math.sin(math.radians(-60)) * 39)))
    BUNTING_RUNS.extend(runs)
    put("Bunting", 0, 0, y=0, collide=False)

    # trees: round the edges and in groves, never on the ways, the plaza or the hall's floor
    def clear(x, z, r):
        if surface(x, z) in (False, "Path"):
            return False
        if math.hypot(x - plaza["x"], z - plaza["z"]) < 46 + r:
            return False
        if -136 - r < x < -60 + r and -72 - r < z < 38 + r:
            return False  # the Hall of Heroes and its terrace
        if math.hypot(x - portal["x"], z - portal["z"]) < 34 + r:
            return False  # the portal and its dais
        if abs(x) < 16 + r and z > -10:
            return False  # the view from the spawn up to the portal
        if math.hypot(x - t["x"], z - t["z"]) < 34 + r:
            return False
        if math.hypot(x - tr["x"], z - (tr["z"] + 4)) < 16 + r or math.hypot(x - lo["x"], z - lo["z"]) < 14 + r:
            return False
        for e in LAYOUT:
            if e["kit"] == "wardwood" and math.hypot(e["x"] - x, e["z"] - z) < r + 8:
                return False
        return True

    kinds = ["OakA", "OakB", "OakC", "BeechA", "BirchA", "BirchB", "PineA", "SpruceA"]
    placed = 0
    tries = 0
    while placed < 46 and tries < 6000:
        tries += 1
        x, z = rnd.uniform(-140, 136), rnd.uniform(-124, 126)
        # trees favour the rim and the west
        edge = min(abs(x) / 136, 1) ** 2 + max(0, z / 126) ** 3 * 0.3
        if rnd.random() > 0.35 + edge * 0.65:
            continue
        kind = rnd.choice(kinds)
        scale = rnd.uniform(0.8, 1.05)
        if clear(x, z, 6):
            put(kind, x, z, yaw=rnd.uniform(0, 360), kit="wardwood", scale=round(scale, 2), trunk=trunk(kind, scale))
            placed += 1
    # bushes, ferns, rocks and saplings at the feet of things
    small = ["BushA", "BushB", "BushC", "FernA", "FernB", "RockSmallA", "RockSmallB", "BoulderFlat", "SaplingA"]
    count = 0
    tries = 0
    while count < 120 and tries < 9000:
        tries += 1
        x, z = rnd.uniform(-140, 136), rnd.uniform(-124, 126)
        if surface(x, z) in (False, "Path") or math.hypot(x - plaza["x"], z - plaza["z"]) < 40:
            continue
        if -128 < x < -66 and -66 < z < 30:
            continue  # the hall's floor stays clear
        if math.hypot(x - portal["x"], z - portal["z"]) < 26:
            continue
        kind = rnd.choice(small)
        put(kind, x, z, yaw=rnd.uniform(0, 360), kit="wardwood", scale=round(rnd.uniform(0.8, 1.3), 2), collide=False)
        count += 1
    # flowers in drifts over the meadow and the knoll: a few patches of one colour together
    drifts = 0
    while drifts < 26:
        x, z = rnd.uniform(-120, 120), rnd.uniform(-60, 116)
        if surface(x, z) != "Turf" or math.hypot(x - plaza["x"], z - plaza["z"]) < 42 or abs(x) < 10:
            continue
        drifts += 1
        kind = rnd.choice(["FlowersWhite", "FlowersPink", "FlowersBlue", "FlowersGold"])
        for _ in range(rnd.randint(2, 5)):
            fx, fz = x + rnd.uniform(-6, 6), z + rnd.uniform(-6, 6)
            if surface(fx, fz) == "Turf":
                put(kind, fx, fz, yaw=rnd.uniform(0, 360), scale=round(rnd.uniform(0.9, 1.3), 2), collide=False)

    # floating isles round the island, with trees of their own (scenery)
    isles = [("FloatIsleA", 230, 40, -120, 1.0), ("FloatIsleB", -250, 30, -60, 1.0), ("FloatIsleC", -190, 70, 170, 1.0),
             ("FloatIsleB", 170, -40, 230, 1.2), ("FloatIsleC", 60, 90, -260, 1.0), ("FloatIsleA", -120, -60, -300, 0.8)]
    for k, (name, x, y, z, s) in enumerate(isles):
        put(name, x, z, y=y, scale=s, collide=False, name=f"Isle{k + 1}")
        top = y + 2.5 * s
        put("OakB" if k % 2 else "BirchA", x + 2, z - 1, y=top, kit="wardwood", scale=0.7 * s, collide=False)
        if name == "FloatIsleA":
            put("PineA", x - 8 * s, z + 5 * s, y=top, kit="wardwood", scale=0.6 * s, collide=False)
            put("Falls", x + 20 * s, z, y=y - 1, yaw=90, scale=0.6 * s, collide=False)

    # far scenery the clients draw: a sea of clouds well under the island's
    # rock (its tip is near -200), banks at mid height, the peak
    for k in range(48):
        a = k / 48 * math.tau + rnd.uniform(-0.1, 0.1)
        r = rnd.uniform(60, 760)
        decor(rnd.choice(["CloudA", "CloudD", "CloudD"]), math.cos(a) * r, rnd.uniform(-300, -270), math.sin(a) * r, rnd.uniform(0, 360), round(rnd.uniform(1.1, 1.9), 2))
    # the banks keep off the sun's side (west): seen against the sun, Roblox
    # shades them a flat grey
    for k in range(14):
        a = rnd.uniform(-0.45, 0.45) * math.pi
        r = rnd.uniform(420, 900)
        decor(rnd.choice(["CloudB", "CloudC", "CloudA"]), math.cos(a) * r, rnd.uniform(-60, 120), math.sin(a) * r, rnd.uniform(0, 360), round(rnd.uniform(0.7, 1.3), 2))
    decor("FarPeak", -900, -40, -1500, 30, 1.6)
    decor("FarPeakRock", -900, -40, -1500, 30, 1.6)
    decor("FloatIsleA", 700, 60, -900, 0, 2.2)
    decor("FloatIsleB", -1100, 140, 400, 0, 2.6)
    decor("FloatIsleC", 950, 20, 650, 0, 3.0)


BUNTING_RUNS = []
asset("Bunting")(lambda c: PROPS.bunting(c, BUNTING_RUNS))


# ------------------------------------------------------------------ build


def build_kit():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit = U.collection("Kit")
    layout()  # the bunting needs the layout's runs first
    for name, fn in ASSETS:
        coll = U.collection("SK_" + name, kit)
        fn(coll)
        print(f"[skyhold] built {name}")
    # the far peak's rock is its own asset (one mesh each, under the limit)
    peak = bpy.data.collections.get("SK_FarPeak")
    rock = [o for o in peak.objects if o.name.startswith("PeakRock")]
    if rock:
        coll = U.collection("SK_FarPeakRock", kit)
        for o in rock:
            peak.objects.unlink(o)
            coll.objects.link(o)
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.name == "Kit":
            lc.exclude = True
    place_instances()


def place_instances():
    lay = U.collection("Layout")
    dec = U.collection("Decor")
    for e in LAYOUT:
        ob = bpy.data.objects.new(e.get("name") or e["asset"], None)
        ob.location = B(e["x"], e["y"], e["z"])
        ob.rotation_euler = (0, 0, math.radians(e["yaw"]))
        ob.scale = (e["scale"],) * 3
        for k in ("asset", "kit", "name", "trunk", "seat", "collide"):
            if e.get(k) is not None:
                ob["sk_" + k] = e[k]
        src = bpy.data.collections.get("SK_" + e["asset"]) if e["kit"] == "skyhold" else None
        if src:
            ob.instance_type = "COLLECTION"
            ob.instance_collection = src
        lay.objects.link(ob)
    for e in DECOR:
        ob = bpy.data.objects.new(e["asset"], None)
        ob.location = B(e["x"], e["y"], e["z"])
        ob.rotation_euler = (0, 0, math.radians(e["yaw"]))
        ob.scale = (e["scale"],) * 3
        ob["sk_asset"] = e["asset"]
        src = bpy.data.collections.get("SK_" + e["asset"])
        if src:
            ob.instance_type = "COLLECTION"
            ob.instance_collection = src
        dec.objects.link(ob)


# ------------------------------------------------------------------ export


def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int,)):
        return str(v)
    if isinstance(v, float):
        s = f"{v:.4f}".rstrip("0").rstrip(".")
        return s if s not in ("", "-0") else "0"
    if isinstance(v, str):
        return '"' + v.replace('"', '\\"') + '"'
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    raise TypeError(v)


def export_asset(coll, outdir, manifest):
    name = coll.name[3:]
    parts, colliders = [], []
    tris = 0
    for ob in sorted(coll.objects, key=lambda o: o.name):
        if ob.name.startswith("COL_"):
            m = ob.matrix_world
            loc = U.blender_to_roblox(m.to_translation())
            rot = U.roblox_matrix(m.to_3x3().normalized())
            size = [abs(ob.scale[0]) * 2, abs(ob.scale[2]) * 2, abs(ob.scale[1]) * 2]
            colliders.append({"p": loc, "r": rot, "size": size, "shape": ob.get("shape", "box")})
            continue
        if ob.type != "MESH" or len(ob.data.polygons) == 0:
            continue
        chunks, vc = U.pack_object(ob)
        for pk in chunks:
            entry = {
                "name": ob.get("rbx_part", ob.name),
                "color": list(ob.get("rbx_color", [255, 255, 255])),
                "material": ob.get("rbx_material", "SmoothPlastic"),
                "vc": vc,
                **pk,
            }
            for key in ("transparency", "shadow", "tag"):
                if ob.get("rbx_" + key) is not None:
                    entry[key] = ob.get("rbx_" + key)
            parts.append(entry)
            tris += pk["tris"]
    lines = [
        "--!strict",
        f"-- {name}: generated by tools/art/skyhold.py (Skyhold kit, T6/T7). Do not edit:",
        "-- change the script, or the .blend and export with --from-blend. Server/Skyhold/Builder bakes it.",
        "return {",
        f'\tname = "{name}",',
        "\tparts = {",
    ]
    for p in parts:
        lines.append("\t\t{")
        for key in ("name", "color", "material", "vc", "transparency", "shadow", "tag", "verts", "tris", "min", "max", "data"):
            if key in p:
                lines.append(f"\t\t\t{key} = {lua(p[key])},")
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append("\tcolliders = {")
    for c in colliders:
        lines.append(f"\t\t{{ p = {lua([round(v, 3) for v in c['p']])}, r = {lua([round(v, 5) for v in c['r']])}, size = {lua([round(v, 3) for v in c['size']])}, shape = {lua(c['shape'])} }},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")
    with open(os.path.join(outdir, f"{name}.luau"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    manifest[name] = {"tris": tris, "parts": len(parts), "colliders": len(colliders)}
    return tris


def read_layout(coll_name):
    out = []
    coll = bpy.data.collections.get(coll_name)
    for ob in coll.objects if coll else []:
        loc = U.blender_to_roblox(ob.location)
        out.append(
            {
                "asset": ob.get("sk_asset") or (ob.instance_collection.name[3:] if ob.instance_collection else ob.name),
                "kit": ob.get("sk_kit", "skyhold"),
                "name": ob.get("sk_name"),
                "cf": [round(loc[0], 3), round(loc[1], 3), round(loc[2], 3), 0, round(math.degrees(ob.rotation_euler.z), 2), 0],
                "scale": round(ob.scale[0], 3),
                "trunk": list(ob["sk_trunk"]) if "sk_trunk" in ob else None,
                "seat": ob.get("sk_seat"),
                "collide": ob.get("sk_collide"),
            }
        )
    out.sort(key=lambda e: (e["kit"] != "skyhold", e["asset"], e["name"] or "", e["cf"]))
    return out


def write_layout(entries, path, header, trailer_key=None):
    lines = ["--!strict"] + header + ["return {"]
    for e in entries:
        bits = [f'asset = "{e["asset"]}"']
        if e.get("kit") and e["kit"] != "skyhold":
            bits.append(f'kit = "{e["kit"]}"')
        if e.get("name"):
            bits.append(f'name = "{e["name"]}"')
        bits.append(f"cf = {lua(e['cf'])}")
        if e.get("scale", 1) != 1:
            bits.append(f"scale = {lua(e['scale'])}")
        if e.get("trunk"):
            bits.append(f"trunk = {lua(e['trunk'])}")
        if e.get("seat"):
            bits.append("seat = true")
        if e.get("collide") is False:
            bits.append("collide = false")
        lines.append("\t{ " + ", ".join(bits) + " },")
    lines.append("}")
    lines.append("")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def export_all():
    meshes = os.path.join(ROOT, "src", "server", "Skyhold", "Meshes")
    os.makedirs(meshes, exist_ok=True)
    for f in os.listdir(meshes):
        if f.endswith(".luau"):
            os.remove(os.path.join(meshes, f))
    manifest = {}
    total = 0
    kit = bpy.data.collections.get("Kit")
    for coll in kit.children:
        total += export_asset(coll, meshes, manifest)
    layout_entries = read_layout("Layout")
    write_layout(
        layout_entries,
        os.path.join(ROOT, "src", "server", "Skyhold", "Layout.luau"),
        [
            "-- Skyhold's layout: where every piece stands on the island hub (island-local",
            "-- studs; cf = x, y, z, then x/y/z rotation in degrees). Generated by",
            "-- tools/art/skyhold.py from the Layout collection of assets/art/skyhold_kit.blend:",
            "-- move pieces there and export with --from-blend. Do not edit by hand.",
        ],
    )
    decor_entries = []
    for e in read_layout("Decor"):
        decor_entries.append(e)
    write_layout(
        decor_entries,
        os.path.join(ROOT, "src", "shared", "Config", "SkyholdDecor.luau"),
        [
            "-- Skyhold's far scenery, drawn by each client on the island (HubDecorController):",
            "-- the sea of clouds, the far peak and isles. Island-local studs, generated by",
            "-- tools/art/skyhold.py from the Decor collection. Do not edit by hand.",
        ],
    )
    # the generated Luau must pass the format gate as written
    import subprocess

    try:
        subprocess.run(["stylua", meshes, os.path.join(ROOT, "src", "server", "Skyhold", "Layout.luau"), os.path.join(ROOT, "src", "shared", "Config", "SkyholdDecor.luau")], check=False)
    except OSError:
        print("[skyhold] stylua not found: run `stylua src` before the gates")
    manifest["_total_tris"] = total
    with open(os.path.join(ROOT, "assets", "art", "skyhold_manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"source": "tools/art/skyhold.py", "blend": "assets/art/skyhold_kit.blend", "assets": manifest}, f, indent=1)
    print(f"[skyhold] exported {len(manifest) - 1} assets, {total} triangles; {len(layout_entries)} placements, {len(decor_entries)} decor")


def export_glb():
    out = os.path.join(ROOT, "assets", "art", "export", "skyhold")
    os.makedirs(out, exist_ok=True)
    kit = bpy.data.collections.get("Kit")
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.name == "Kit":
            lc.exclude = False
    for coll in kit.children:
        bpy.ops.object.select_all(action="DESELECT")
        for ob in coll.objects:
            if ob.type == "MESH":
                ob.select_set(True)
        try:
            bpy.ops.export_scene.gltf(
                filepath=os.path.join(out, coll.name[3:] + ".glb"),
                use_selection=True,
                export_format="GLB",
                export_vertex_color="ACTIVE",
                export_yup=True,
                export_apply=True,
            )
        except Exception as err:  # an exporter option renamed in another Blender: keep going
            print(f"[skyhold] glb {coll.name}: {err}")
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.name == "Kit":
            lc.exclude = True


# ------------------------------------------------------------------ preview renders


def preview_materials():
    """Viewport/render materials from the parts' colours (preview only)."""
    vc = bpy.data.materials.get("SK_VC") or bpy.data.materials.new("SK_VC")
    vc.use_nodes = True
    nt = vc.node_tree
    nt.nodes.clear()
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.85
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    for ob in bpy.data.objects:
        if ob.type != "MESH" or not ob.get("rbx_part"):
            continue
        ob.data.materials.clear()
        if ob.get("rbx_vc", True) and ob.data.color_attributes.get("Col"):
            ob.data.materials.append(vc)
        else:
            col = [c / 255 for c in ob.get("rbx_color", [255, 255, 255])]
            name = "SK_" + "_".join(str(int(c * 255)) for c in col) + ("_glow" if ob.get("rbx_material") == "Neon" else "")
            m = bpy.data.materials.get(name)
            if not m:
                m = bpy.data.materials.new(name)
                m.use_nodes = True
                b = m.node_tree.nodes.get("Principled BSDF")
                b.inputs["Base Color"].default_value = (*[c**2.2 for c in col], 1)
                if ob.get("rbx_material") == "Neon":
                    b.inputs["Emission Color"].default_value = (*[c**2.2 for c in col], 1)
                    b.inputs["Emission Strength"].default_value = 3.0
            ob.data.materials.append(m)


def preview_ground():
    """The Terrain the server writes, as a mesh, for the previews."""
    import bmesh

    g = PLAN["grid"]
    bm = bmesh.new()
    verts = {}
    for iz in range(g["nz"]):
        for ix in range(g["nx"]):
            h = g["h"][iz * g["nx"] + ix]
            if h is not False:
                verts[(ix, iz)] = bm.verts.new(B(g["x0"] + ix * g["step"], h, g["z0"] + iz * g["step"]))
    for (ix, iz), v in list(verts.items()):
        q = [verts.get((ix, iz)), verts.get((ix + 1, iz)), verts.get((ix + 1, iz + 1)), verts.get((ix, iz + 1))]
        if all(q):
            bm.faces.new(q)
    me = bpy.data.meshes.new("Ground")
    bm.to_mesh(me)
    ob = bpy.data.objects.new("PreviewGround", me)
    bpy.context.scene.collection.objects.link(ob)
    me.shade_smooth()
    cols = {"Turf": U.rgb(112, 158, 58), "Path": U.rgb(142, 114, 78), "ForestFloor": U.rgb(78, 96, 54)}

    def colour(p, n, c):
        x, z = c.x, -c.y
        return U.scale(cols.get(surface(x, z), cols["Turf"]), 0.9 + 0.2 * U.n3(c, 6))

    U.paint(ob, colour)
    ob["rbx_part"] = "preview"
    return ob


def import_wardwood():
    """Append the Wardwood kit's trees (for the previews only)."""
    path = os.path.join(ROOT, "assets", "art", "wardwood_kit.blend")
    want = {e["asset"] for e in LAYOUT if e["kit"] == "wardwood"} if LAYOUT else set()
    lay = bpy.data.collections.get("Layout")
    for ob in lay.objects:
        if ob.get("sk_kit") == "wardwood":
            want.add(ob.get("sk_asset"))
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.collections = [c for c in src.collections if c in want]
    holder = U.collection("WardwoodPreview")
    for coll in dst.collections:
        if coll is not None:
            holder.children.link(coll)
            # the kit lays its assets out side by side: instance each from its own spot
            meshes = [o for o in coll.objects if o.type == "MESH"]
            if meshes:
                coll.instance_offset = meshes[0].location.copy()
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.name == "WardwoodPreview":
            lc.exclude = True
    for ob in lay.objects:
        if ob.get("sk_kit") == "wardwood":
            src_coll = bpy.data.collections.get(ob.get("sk_asset"))
            if src_coll:
                ob.instance_type = "COLLECTION"
                ob.instance_collection = src_coll


def render(outdir):
    os.makedirs(outdir, exist_ok=True)
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX" if "AgX" in [t.identifier for t in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Standard"
    try:
        scene.eevee.taa_render_samples = 32
    except AttributeError:
        pass
    preview_ground()
    import_wardwood()
    preview_materials()
    # the decor (clouds, far peak) is drawn by the clients; show it here too
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes.get("Background")
    sky = nt.nodes.new("ShaderNodeTexSky")
    try:
        sky.sky_type = "NISHITA"
        sky.sun_elevation = math.radians(28)
        sky.sun_rotation = math.radians(225)
        sky.altitude = 1200
        sky.air_density = 0.6
        sky.dust_density = 0.6
    except Exception:
        pass
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.35
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 4.0
    sun.color = (1.0, 0.92, 0.8)
    sun.angle = math.radians(3)
    sun_ob = bpy.data.objects.new("Sun", sun)
    sun_ob.rotation_euler = (math.radians(58), 0, math.radians(225))
    scene.collection.objects.link(sun_ob)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.clip_end = 6000
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    spawn = A["spawn"]
    views = {
        "arrival": ((spawn["x"] + 3, ground(spawn["x"], spawn["z"]) + 7, spawn["z"] + 12), (0, 16, -70), 62),
        "aerial": ((300, 210, 300), (0, -30, 0), 40),
        "plaza": ((34, 14, -6), (0, 14, -82), 60),
        "hall": ((-58, 16, -6), (-104, 10, -18), 60),
        "below": ((330, -60, 230), (0, -60, 0), 45),
        "lookout": ((-118, 9, 122), (40, 10, -40), 60),
        "portal": ((14, 9, -58), (0, 18, -88), 66),
    }
    for name, (eye, target, fov) in views.items():
        e, t = B(*eye), B(*target)
        cam.location = e
        cam.rotation_euler = (t - e).to_track_quat("-Z", "Y").to_euler()
        cam_data.angle = math.radians(fov)
        scene.render.filepath = os.path.join(outdir, f"skyhold_{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[skyhold] rendered {name}")


# ------------------------------------------------------------------ main


def main():
    if FROM_BLEND:
        print("[skyhold] exporting the open .blend as it stands")
    else:
        build_kit()
    export_all()
    if not FROM_BLEND:
        if not NO_GLB:
            export_glb()
        path = os.path.join(ROOT, "assets", "art", "skyhold_kit.blend")
        bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
        print(f"[skyhold] saved {path}")
    if RENDER:
        render(os.path.abspath(RENDER))


main()

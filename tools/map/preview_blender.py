"""Offline preview of the BonkHorde map in Blender, from the gameplay camera.

    "%BLENDER%" -b -P tools/map/preview_blender.py -- work/map/world.json out_dir [views.json]

Reads the world exported by tools/map/export_world.luau and renders it from
the views listed (default: the built-in tour). Terrain is coloured by surface,
part-built props are their exact primitives, mesh props are proxies sized from
the asset manifest. It shows composition, scale, elevation, density and
lighting direction; it does NOT show Roblox textures, grass blades or
Roblox's own lighting response, so it never replaces a look in Studio.

Coordinates: Roblox (x, y, z) -> Blender (x, -z, y), which keeps handedness.
"""

import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
WORLD = argv[0] if argv else "work/map/world.json"
OUT = os.path.abspath(argv[1] if len(argv) > 1 else "work/map/preview")
VIEWS = argv[2] if len(argv) > 2 else None
os.makedirs(OUT, exist_ok=True)

with open(WORLD, encoding="utf-8") as f:
    W = json.load(f)

P = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # roblox -> blender


def to_bl(x, y, z):
    return Vector((x, -z, y))


# ------------------------------------------------------------------ palette
# approximate Roblox terrain material looks with the tints MapService applies
SURFACE = {
    "Grass": (0.42, 0.58, 0.20),
    "Meadow": (0.48, 0.62, 0.22),
    "LeafyGrass": (0.28, 0.48, 0.20),
    "Lush": (0.30, 0.50, 0.20),
    "Ground": (0.42, 0.33, 0.22),
    "Path": (0.55, 0.44, 0.30),
    "Mud": (0.30, 0.24, 0.17),
    "ForestFloor": (0.24, 0.30, 0.15),
    "Rock": (0.40, 0.40, 0.40),
    "Slate": (0.30, 0.31, 0.33),
    "Cliff": (0.46, 0.44, 0.40),
    "Sand": (0.70, 0.62, 0.44),
    "Pavement": (0.55, 0.55, 0.52),
    "Cobblestone": (0.50, 0.49, 0.45),
}


def srgb(c):
    # inputs are sRGB 0..1 -> linear for blender
    return tuple((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


_mats = {}


def mat(name, color, emit=0.0, rough=0.85, alpha=1.0):
    key = (name, tuple(round(v, 3) for v in color), emit, alpha)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    lin = srgb(color)
    bsdf.inputs["Base Color"].default_value = (*lin, 1)
    bsdf.inputs["Roughness"].default_value = rough
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = (*lin, 1)
        bsdf.inputs["Emission Strength"].default_value = emit
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
    _mats[key] = m
    return m


# ------------------------------------------------------------------ scene
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.film_transparent = False
try:
    scene.eevee.taa_render_samples = 24
    scene.eevee.use_shadows = True
except Exception:
    pass
scene.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
scene.view_settings.look = "None"

coll = bpy.data.collections.new("World")
scene.collection.children.link(coll)


def link(obj):
    coll.objects.link(obj)
    return obj


# terrain
n, cell, half = W["n"], W["cell"], W["half"]
heights = W["heights"]
surfaces = W["surfaces"]
mesh = bpy.data.meshes.new("Terrain")
bm = bmesh.new()
verts = []
for iz in range(n):
    z = -half + iz * cell
    for ix in range(n):
        x = -half + ix * cell
        verts.append(bm.verts.new(to_bl(x, heights[iz * n + ix] + 2, z)))  # surface sits ~2 above the field
bm.verts.ensure_lookup_table()
col_layer = bm.loops.layers.color.new("col")
import random

rng = random.Random(7)
palette = W.get("palette") or {}
for key, entry in palette.items():
    SURFACE[key] = tuple(v / 255 for v in entry["color"])
# a colour per vertex, averaged from the cells round it: Roblox blends terrain
# materials across voxels, so hard per-cell squares would mislead
vcol = []
for iz in range(n):
    for ix in range(n):
        acc = [0.0, 0.0, 0.0]
        k = 0
        for dz in (-1, 0):
            for dx in (-1, 0):
                jx, jz = min(max(ix + dx, 0), n - 2), min(max(iz + dz, 0), n - 2)
                c = SURFACE.get(surfaces[jz * n + jx], (1, 0, 1))
                acc = [acc[i] + c[i] for i in range(3)]
                k += 1
        jit = 1 + (rng.random() - 0.5) * 0.12
        vcol.append(srgb(tuple(min(1, acc[i] / k * jit) for i in range(3))))
for iz in range(n - 1):
    for ix in range(n - 1):
        a = iz * n + ix
        f = bm.faces.new((verts[a], verts[a + 1], verts[a + n + 1], verts[a + n]))
        for loop, vi in zip(f.loops, (a, a + 1, a + n + 1, a + n)):
            loop[col_layer] = (*vcol[vi], 1)
bm.normal_update()
bm.to_mesh(mesh)
bm.free()
for poly in mesh.polygons:
    poly.use_smooth = True
terrain = link(bpy.data.objects.new("Terrain", mesh))
tm = bpy.data.materials.new("TerrainMat")
tm.use_nodes = True
nt = tm.node_tree
attr = nt.nodes.new("ShaderNodeVertexColor")
attr.layer_name = "col"
nt.links.new(attr.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
terrain.data.materials.append(tm)

# water
for wtr in W.get("water") or []:
    bpy.ops.mesh.primitive_circle_add(vertices=48, radius=wtr["r"], fill_type="NGON", location=to_bl(wtr["x"], wtr["level"] + 0.1, wtr["z"]))
    o = bpy.context.active_object
    bpy.context.collection.objects.unlink(o)
    link(o)
    o.data.materials.append(mat("Water", (0.20, 0.42, 0.45), rough=0.05))

# ------------------------------------------------------------------ primitives
_shape_mesh = {}


def shape_mesh(shape):
    if shape in _shape_mesh:
        return _shape_mesh[shape]
    bm = bmesh.new()
    if shape == "block":
        bmesh.ops.create_cube(bm, size=1)
    elif shape == "ball":
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.5)
    elif shape == "cylinder":
        # roblox cylinder: axis along local X
        r = bmesh.ops.create_cone(bm, cap_ends=True, segments=14, radius1=0.5, radius2=0.5, depth=1)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif shape == "wedge":
        # in roblox local space: vertical face at +z, slope rising from -z to +z.
        # build it in roblox local coords and convert with P.
        pts = [(-0.5, -0.5, -0.5), (0.5, -0.5, -0.5), (0.5, -0.5, 0.5), (-0.5, -0.5, 0.5), (0.5, 0.5, 0.5), (-0.5, 0.5, 0.5)]
        vs = [bm.verts.new(P @ Vector(p)) for p in pts]
        for face in ((0, 1, 2, 3), (3, 2, 4, 5), (0, 3, 5), (1, 4, 2), (0, 5, 4, 1)):
            bm.faces.new([vs[i] for i in face])
    elif shape == "cornerwedge":
        # apex over the (+x, -z) corner? unverified in Roblox, so not used by blueprints
        pts = [(-0.5, -0.5, -0.5), (0.5, -0.5, -0.5), (0.5, -0.5, 0.5), (-0.5, -0.5, 0.5), (0.5, 0.5, -0.5)]
        vs = [bm.verts.new(P @ Vector(p)) for p in pts]
        for face in ((0, 1, 2, 3), (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)):
            bm.faces.new([vs[i] for i in face])
    me = bpy.data.meshes.new("shape_" + shape)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    _shape_mesh[shape] = me
    return me


def add_part(p):
    shape = p.get("shape", "block")
    sx, sy, sz = p["size"]
    cf = p["cf"]  # px, py, pz, then a row-major roblox rotation matrix
    pos = to_bl(cf[0], cf[1], cf[2])
    R = Matrix(((cf[3], cf[4], cf[5]), (cf[6], cf[7], cf[8]), (cf[9], cf[10], cf[11])))
    Rb = P @ R @ P.transposed()
    if shape == "ball":
        d = min(sx, sy, sz)
        sx = sy = sz = d
    elif shape == "cylinder":
        d = min(sy, sz)
        sy = sz = d
    # scale in roblox local axes -> blender local axes (x, -z, y)
    S = Matrix.Diagonal((sx, sz, sy))
    me = shape_mesh(shape)
    if len(me.materials) == 0:
        me.materials.append(mat("placeholder", (1, 0, 1)))
    o = bpy.data.objects.new(p.get("mat", "part"), me)
    o.matrix_world = Matrix.Translation(pos) @ (Rb @ S).to_4x4()
    col = tuple(v / 255 for v in p.get("color", (163, 162, 165)))
    m = mat(p.get("mat", "part"), col, emit=4.0 if p.get("neon") else 0.0)
    link(o)
    # meshes are shared between parts, so the colour goes on the object
    o.material_slots[0].link = "OBJECT"
    o.material_slots[0].material = m
    if p.get("light"):
        L = p["light"]
        ld = bpy.data.lights.new("pl", "POINT")
        ld.color = tuple(v / 255 for v in L.get("color", (255, 180, 100)))
        ld.energy = L.get("brightness", 2) * 2500
        ld.shadow_soft_size = 1
        lo = bpy.data.objects.new("pl", ld)
        lo.location = pos
        link(lo)


def proxy(prop):
    kind = prop["kind"]
    bx, by, bz = prop["bounds"]
    s = prop["scale"]
    x, y, z, yaw = prop["x"], prop["y"], prop["z"], prop["yaw"]
    rot = Matrix.Rotation(yaw, 3, "Z")

    def put(shape, size, local, color, roughness=0.8, emit=0, upright=False):
        lx, ly, lz = local
        world = rot @ Vector((lx * s, -lz * s, ly * s))
        c, sn = math.cos(yaw), math.sin(yaw)
        # roblox Ry(yaw), or Ry(yaw) * Rz(90) for a cylinder standing upright
        m = [0, -c, sn, 1, 0, 0, 0, sn, c] if upright else [c, 0, sn, 0, 1, 0, -sn, 0, c]
        part = {
            "shape": shape,
            "size": [size[0] * s, size[1] * s, size[2] * s],
            "cf": [x + world.x, y + world.z, z - world.y, *m],
            "color": color,
            "mat": kind,
        }
        if emit:
            part["neon"] = True
        add_part(part)

    leaf = (120, 190, 70)
    if kind.startswith("Tree"):
        th = by * 0.45
        put("cylinder", (th, bx * 0.12, bx * 0.12), (0, th / 2, 0), (120, 82, 50), upright=True)
        put("ball", (bx * 0.6,) * 3, (0, by * 0.68, 0), leaf)
        put("ball", (bx * 0.45,) * 3, (bx * 0.25, by * 0.58, bz * 0.1), (105, 175, 60))
        put("ball", (bx * 0.45,) * 3, (-bx * 0.22, by * 0.6, -bz * 0.15), (135, 200, 80))
        put("ball", (bx * 0.4,) * 3, (0, by * 0.82, bz * 0.2), leaf)
    elif kind == "Bush":
        put("ball", (bx * 0.6,) * 3, (0, by * 0.4, 0), (110, 180, 70))
        put("ball", (bx * 0.45,) * 3, (bx * 0.25, by * 0.3, 0), (95, 165, 60))
    elif kind in ("BoulderLarge", "BoulderFlat", "RockSmall"):
        put("ball", (bx, by * 1.2, bz), (0, by * 0.35, 0), (140, 140, 145))
        put("block", (bx * 0.7, by * 0.8, bz * 0.7), (0, by * 0.4, 0), (130, 132, 136))
    elif kind in ("FallenLog",):
        put("cylinder", (bx, by, bz), (0, by * 0.5, 0), (115, 80, 50))
    elif kind == "Stump":
        put("cylinder", (by, bx, bz), (0, by * 0.5, 0), (115, 80, 50), upright=True)
    elif kind == "LanternPost":
        put("block", (0.6, by, 0.6), (0, by * 0.5, 0), (120, 120, 125))
        put("ball", (1.2, 1.2, 1.2), (0, by * 0.8, 0.8), (255, 200, 120), emit=1)
    elif kind == "RuinTower":
        put("cylinder", (by, bx * 0.8, bz * 0.8), (0, by * 0.5, 0), (150, 148, 135), upright=True)
    else:
        put("block", (bx, by, bz), (0, by * 0.5, 0), (150, 148, 135))


for prop in W["props"]:
    if prop.get("parts"):
        for p in prop["parts"]:
            add_part(p)
    else:
        proxy(prop)

# ------------------------------------------------------------------ light and air
look = W.get("look") or {}
sun_az = math.radians(look.get("sun_azimuth", 200))  # degrees from roblox +x towards +z
sun_el = math.radians(look.get("sun_elevation", 24))
sd = to_bl(math.cos(sun_az) * math.cos(sun_el), math.sin(sun_el), math.sin(sun_az) * math.cos(sun_el))
sun = bpy.data.lights.new("Sun", "SUN")
sun.energy = look.get("sun_energy", 4.2)
sun.color = srgb(tuple(v / 255 for v in look.get("sun_color", (255, 214, 160))))
sun.angle = math.radians(1.5)
so = bpy.data.objects.new("Sun", sun)
so.rotation_euler = (-sd).to_track_quat("-Z", "Y").to_euler()
link(so)

world = bpy.data.worlds.new("Sky")
scene.world = world
world.use_nodes = True
wn = world.node_tree
bg = wn.nodes["Background"]
sky = wn.nodes.new("ShaderNodeTexSky")
try:
    sky.sky_type = "NISHITA"
    sky.sun_elevation = sun_el
    sky.sun_rotation = math.atan2(sd.y, sd.x) + math.pi / 2
    sky.altitude = 100
    sky.air_density = 1.2
    sky.dust_density = 2.5
except Exception:
    pass
wn.links.new(sky.outputs["Color"], bg.inputs["Color"])
bg.inputs["Strength"].default_value = look.get("sky_strength", 0.35)

# distance haze through the mist pass
world.mist_settings.start = look.get("haze_start", 60)
world.mist_settings.depth = look.get("haze_depth", 520)
world.mist_settings.falloff = "QUADRATIC"
scene.view_layers[0].use_pass_mist = True
scene.use_nodes = True
ct = scene.node_tree
for node in list(ct.nodes):
    ct.nodes.remove(node)
rl = ct.nodes.new("CompositorNodeRLayers")
mix = ct.nodes.new("CompositorNodeMixRGB")
mix.blend_type = "MIX"
hz = look.get("haze_color", (150, 180, 175))
mix.inputs[2].default_value = (*srgb(tuple(v / 255 for v in hz)), 1)
mul = ct.nodes.new("CompositorNodeMath")
mul.operation = "MULTIPLY"
mul.inputs[1].default_value = look.get("haze_amount", 0.55)
ct.links.new(rl.outputs["Mist"], mul.inputs[0])
ct.links.new(mul.outputs[0], mix.inputs[0])
ct.links.new(rl.outputs["Image"], mix.inputs[1])
comp = ct.nodes.new("CompositorNodeComposite")
ct.links.new(mix.outputs[0], comp.inputs["Image"])

# ------------------------------------------------------------------ cameras
cam_data = bpy.data.cameras.new("Cam")
cam_data.sensor_fit = "VERTICAL"
cam_data.angle_y = math.radians(80)
cam_data.clip_end = 3000
cam = bpy.data.objects.new("Cam", cam_data)
link(cam)
scene.camera = cam


def height_at(x, z):
    fx = min(max((x + half) / cell, 0), n - 1.001)
    fz = min(max((z + half) / cell, 0), n - 1.001)
    ix, iz = int(fx), int(fz)
    tx, tz = fx - ix, fz - iz
    h00 = heights[iz * n + ix]
    h10 = heights[iz * n + ix + 1]
    h01 = heights[(iz + 1) * n + ix]
    h11 = heights[(iz + 1) * n + ix + 1]
    return (h00 * (1 - tx) + h10 * tx) * (1 - tz) + (h01 * (1 - tx) + h11 * tx) * tz


def gameplay_view(x, z, yaw_deg, pitch_deg=-18, distance=18):
    """The in-game camera: focus 3.5 above the root, `distance` back along the look."""
    root_y = height_at(x, z) + 2 + 3
    focus = Vector((x, root_y + 3.5, z))
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    look = Vector((-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)))
    eye = focus - look * distance
    return eye, focus


def aim(eye, target):
    e = to_bl(*eye)
    t = to_bl(*target)
    cam.location = e
    cam.rotation_euler = (t - e).to_track_quat("-Z", "Y").to_euler()


views = None
if VIEWS:
    with open(VIEWS, encoding="utf-8") as f:
        views = json.load(f)
else:
    views = W.get("views") or [
        {"name": "spawn_default", "x": 0, "z": 0, "yaw": 0},
        {"name": "overview", "eye": [0, 420, 380], "target": [0, 0, 0]},
    ]

# a stand-in hero at each gameplay view, for scale
hero_mat = mat("Hero", (0.85, 0.3, 0.25))
for v in views:
    if "eye" in v:
        aim(v["eye"], v["target"])
        hero = None
    else:
        eye, focus = gameplay_view(v["x"], v["z"], v.get("yaw", 0), v.get("pitch", -18))
        aim(eye, focus)
        bpy.ops.mesh.primitive_cylinder_add(radius=1.2, depth=5.4, location=to_bl(v["x"], height_at(v["x"], v["z"]) + 2 + 2.7, v["z"]))
        hero = bpy.context.active_object
        hero.data.materials.append(hero_mat)
    scene.render.filepath = os.path.join(OUT, v["name"] + ".png")
    bpy.ops.render.render(write_still=True)
    if hero:
        bpy.data.objects.remove(hero)
    print("rendered", v["name"])

"""Look at the kit: one framed render per asset under warm afternoon light.

    "$BLENDER" -b assets/art/wardwood_kit.blend -P tools/art/render.py -- <outdir> [Asset ...]

Each asset collection is shown alone on a meadow-green ground, from a
three-quarter view a little above eye height, then the frames are tiled
into <outdir>/sheet.jpg by tools/map/sheet.py (or opened one by one).
A render is evidence of shape and palette only: Roblox's lighting and
materials differ, so the in-engine look still needs Studio.
"""

from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0] if ARGS else "work/art/renders")
ONLY = set(ARGS[1:])
os.makedirs(OUT, exist_ok=True)

scene = bpy.context.scene
for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.resolution_x, scene.render.resolution_y = 900, 900
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"

world = bpy.data.worlds.new("Sky")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.42, 0.6, 0.85, 1)
bg.inputs["Strength"].default_value = 0.9

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 4.2
sun_data.color = (1.0, 0.9, 0.74)
sun_data.angle = math.radians(3)
sun = bpy.data.objects.new("Sun", sun_data)
sun.rotation_euler = (math.radians(52), 0, math.radians(35))
scene.collection.objects.link(sun)

ground_mat = bpy.data.materials.new("Ground")
ground_mat.use_nodes = True
ground_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.18, 0.38, 0.05, 1)
ground_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1
bpy.ops.mesh.primitive_plane_add(size=600)
ground = bpy.context.active_object
ground.data.materials.append(ground_mat)

cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

colls = [c for c in scene.collection.children if c.objects and (not ONLY or c.name in ONLY)]


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in objs:
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


for c in scene.collection.children:
    c.hide_render = True
for coll in colls:
    coll.hide_render = False
    lo, hi = bounds(coll.objects)
    centre = (lo + hi) / 2
    # enemies are centred on their middle for the game: stand them on the ground here
    ground.location = (centre.x, centre.y, lo.z if coll.name.startswith("KitEnemy") else 0)
    size = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
    cam_data.lens = 50
    dist = size * 1.85 + 2
    elev = math.radians(14 if hi.z - lo.z > 4 or coll.name.startswith("KitEnemy") else 32)
    az = math.radians(-35 if not coll.name.startswith("KitEnemy") else 60)
    target = Vector((centre.x, centre.y, (lo.z + hi.z) * 0.45))
    cam.location = target + Vector((math.cos(az) * math.cos(elev), math.sin(az) * math.cos(elev), math.sin(elev))) * dist
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(OUT, f"{coll.name}.png")
    bpy.ops.render.render(write_still=True)
    coll.hide_render = True
    print(f"[render] {coll.name}")

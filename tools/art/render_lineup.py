"""The horde's line-up at game scale: each enemy at its roster height next to a
hero-sized stand-in, on grass, from about where the game camera sits.

    "$BLENDER" -b assets/art/wardwood_kit.blend -P tools/art/render_lineup.py -- <out.png> name=height ...

e.g. KitEnemyGoblinRunt=3.8 KitEnemyGoblinBruiser=6.2 KitEnemySlime=2.9 (studs).
Shape, scale and palette only: Roblox's lighting differs, so this is no Studio check.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(ARGS[0])
WANT = [(a.split("=")[0], float(a.split("=")[1])) for a in ARGS[1:]]
HERO = 5.4

scene = bpy.context.scene
for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.resolution_x, scene.render.resolution_y = 1600, 900
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("Sky")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.65, 0.85, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 4.0
sun.data.color = (1.0, 0.92, 0.78)
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)
grass = bpy.data.materials.new("Grass")
grass.use_nodes = True
grass.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.17, 0.34, 0.045, 1)
bpy.ops.mesh.primitive_plane_add(size=400)
bpy.context.active_object.data.materials.append(grass)

for c in scene.collection.children:
    c.hide_render = True


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in objs:
        for corner in ob.bound_box:
            w = ob.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


x = 0.0
spacing = 4.5
# the hero stand-in first
hero_mat = bpy.data.materials.new("Hero")
hero_mat.use_nodes = True
hero_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.25, 0.2, 1)
bpy.ops.mesh.primitive_cylinder_add(radius=1.2, depth=HERO, location=(x, 0, HERO / 2))
bpy.context.active_object.data.materials.append(hero_mat)
x += spacing
for name, height in WANT:
    coll = bpy.data.collections.get(name)
    if not coll:
        continue
    coll.hide_render = False
    objs = list(coll.objects)
    lo, hi = bounds(objs)
    # the kit lays its assets out in a row: every part of one shares the offset
    off = objs[0].location.copy()
    k = height / max(hi.z - lo.z, 1e-3)
    cx, cy = (lo.x + hi.x) / 2 - off.x, (lo.y + hi.y) / 2 - off.y
    w = (hi.x - lo.x) * k
    x += w / 2
    for ob in objs:
        ob.scale = (k, k, k)
        ob.location = (x - cx * k, -cy * k, -(lo.z - off.z) * k)
    x += w / 2 + spacing

cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.lens = 35
mid = Vector(((x - spacing) / 2, 0, 2.5))
cam.location = mid + Vector((0, 24, 10))  # in front of their faces, raised, as the game camera looks down a little
cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("[lineup]", OUT)

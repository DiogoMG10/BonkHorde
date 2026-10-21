"""Blender helpers for the Skyhold kit (T6/T7): building meshes with bmesh,
baking modifier stacks, painting vertex colours, ambient occlusion from a BVH,
and packing a finished mesh into the game's format.

Runs inside Blender (bpy). Blender is Z up; the game is Y up: a Blender point
(x, y, z) is the Roblox point (x, z, -y), a rotation, so winding is kept.
"""

from __future__ import annotations

import base64
import math
import random
import struct

import bmesh
import bpy
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

# ------------------------------------------------------------------ colour


def rgb(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def scale(c, k):
    return (min(1.0, c[0] * k), min(1.0, c[1] * k), min(1.0, c[2] * k))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def n3(p, size=1.0, seed=0.0):
    """Blender's Perlin noise in [0, 1] at a point, scaled."""
    v = Vector((p[0] / size + seed * 17.13, p[1] / size - seed * 9.71, p[2] / size + seed * 3.3))
    return 0.5 + 0.5 * noise.noise(v)


# ------------------------------------------------------------------ objects


def collection(name, parent=None):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(coll)
    return coll


def obj_from_bm(name, bm, coll, part=None, material="SmoothPlastic", vc=True, recalc=True, **props):
    """A mesh object from a bmesh, carrying the game part it becomes. Closed
    solids get their faces turned outward (Roblox draws one side only); open
    surfaces (`recalc=False`) keep the winding they were built with."""
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob["rbx_part"] = part or name
    ob["rbx_material"] = material
    ob["rbx_vc"] = vc
    for k, v in props.items():
        ob["rbx_" + k] = v
    return ob


def bake(ob):
    """Apply the object's modifier stack into its own mesh (no operators)."""
    if not ob.modifiers:
        return ob
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return ob


def bevel(ob, width=0.15, segments=1, angle=40):
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.harden_normals = False
    return m


def decimate(ob, ratio, group=None):
    m = ob.modifiers.new("Decimate", "DECIMATE")
    m.ratio = ratio
    m.use_collapse_triangulate = True
    if group:
        m.vertex_group = group
        m.invert_vertex_group = True
    return m


def displace(ob, kind, size, strength, group=None, seed=0, mid=0.5):
    tex = bpy.data.textures.new(f"{ob.name}_{kind}", type=kind)
    if hasattr(tex, "noise_scale"):
        tex.noise_scale = size
    if kind == "VORONOI":
        tex.distance_metric = "DISTANCE"
        tex.color_mode = "INTENSITY"
    m = ob.modifiers.new("Displace", "DISPLACE")
    m.texture = tex
    m.strength = strength
    m.mid_level = mid
    m.direction = "NORMAL"
    m.texture_coords = "OBJECT"
    if group:
        m.vertex_group = group
    # a different crop of the same texture per asset
    empty = bpy.data.objects.new(f"{ob.name}_texspace", None)
    empty.location = (seed * 31.7, seed * 17.3, seed * 7.1)
    bpy.context.scene.collection.objects.link(empty)
    m.texture_coords_object = empty
    return m


def remesh(ob, voxel):
    m = ob.modifiers.new("Remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    m.use_smooth_shade = True
    return m


def smooth_mod(ob, factor=0.5, repeat=4):
    m = ob.modifiers.new("Smooth", "SMOOTH")
    m.factor = factor
    m.iterations = repeat
    return m


def shade(ob, flat=False, angle=40):
    me = ob.data
    if flat:
        me.shade_flat()
    else:
        me.shade_smooth()
        if angle is not None:
            me.set_sharp_from_angle(angle=math.radians(angle))


# ------------------------------------------------------------------ bmesh builders


def prism(bm, poly, z0, z1, cap_bottom=True):
    """An upright prism over a counter-clockwise 2D polygon."""
    bottom = [bm.verts.new((x, y, z0)) for x, y in poly]
    top = [bm.verts.new((x, y, z1)) for x, y in poly]
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bm.faces.new(top)
    if cap_bottom:
        bm.faces.new(list(reversed(bottom)))
    return bottom, top


def box(bm, cx, cy, cz, sx, sy, sz, rot=0.0):
    """An axis box (rotated `rot` about Z) centred at (cx, cy, cz)."""
    c, s = math.cos(rot), math.sin(rot)
    pts = []
    for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        x, y = dx * sx / 2, dy * sy / 2
        pts.append((cx + x * c - y * s, cy + x * s + y * c))
    return prism(bm, pts, cz - sz / 2, cz + sz / 2)


def ring_poly(r, segments, phase=0.0, wobble=0.0, seed=0):
    rnd = random.Random(seed)
    out = []
    for i in range(segments):
        a = phase + i / segments * math.tau
        rr = r * (1 + (rnd.random() - 0.5) * wobble)
        out.append((math.cos(a) * rr, math.sin(a) * rr))
    return out


def arc_block(bm, r0, r1, a0, a1, z0, z1, steps=3):
    """A curved block between radii r0..r1 and angles a0..a1 (radians)."""
    inner = [(math.cos(a0 + (a1 - a0) * k / steps) * r0, math.sin(a0 + (a1 - a0) * k / steps) * r0) for k in range(steps + 1)]
    outer = [(math.cos(a0 + (a1 - a0) * k / steps) * r1, math.sin(a0 + (a1 - a0) * k / steps) * r1) for k in range(steps + 1)]
    poly = outer + list(reversed(inner))
    return prism(bm, poly, z0, z1)


def lathe(bm, profile, segments, phase=0.0):
    """Revolve a (radius, z) profile about Z; caps where the radius is 0."""
    rings = []
    for r, z in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((math.cos(phase + i / segments * math.tau) * r, math.sin(phase + i / segments * math.tau) * r, z)) for i in range(segments)])
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(segments):
            j = (i + 1) % segments
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], b[0], a[j]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    return rings


def offset(rings, dx, dy, dz=0.0):
    """Move the rings a lathe returned."""
    for ring in rings:
        for v in ring:
            v.co.x += dx
            v.co.y += dy
            v.co.z += dz
    return rings


def tube(bm, path, radius, sides=6):
    """A plain tube along a list of points (ropes, rails, poles)."""
    prev = None
    first_ring = None
    for k, p in enumerate(path):
        p = Vector(p)
        if k < len(path) - 1:
            t = (Vector(path[k + 1]) - p).normalized()
        else:
            t = (p - Vector(path[k - 1])).normalized()
        u = t.cross(Vector((0, 0, 1)))
        if u.length < 1e-4:
            u = t.cross(Vector((1, 0, 0)))
        u.normalize()
        v = t.cross(u)
        ring = [bm.verts.new(p + (u * math.cos(i / sides * math.tau) + v * math.sin(i / sides * math.tau)) * radius) for i in range(sides)]
        if prev:
            for i in range(sides):
                j = (i + 1) % sides
                bm.faces.new((prev[i], prev[j], ring[j], ring[i]))
        else:
            first_ring = ring
        prev = ring
    bm.faces.new(list(reversed(first_ring)))
    bm.faces.new(prev)


def catenary(a, b, sag, n):
    a, b = Vector(a), Vector(b)
    out = []
    for k in range(n + 1):
        t = k / n
        p = a.lerp(b, t)
        p.z -= sag * 4 * t * (1 - t)
        out.append(tuple(p))
    return out


def transform_bm(bm, matrix):
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)


# ------------------------------------------------------------------ painting


def paint(ob, fn, ao=None):
    """Write per-corner sRGB colours: fn(position, normal, face_centre) -> rgb,
    times the ambient occlusion `ao` (a per-vertex factor list) if given."""
    me = ob.data
    attr = me.color_attributes.get("Col") or me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    me.color_attributes.active_color = attr
    mw = ob.matrix_world
    nrm = mw.to_3x3().inverted().transposed()
    for poly in me.polygons:
        centre = mw @ poly.center
        n = (nrm @ poly.normal).normalized()
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            p = mw @ me.vertices[vi].co
            c = fn(p, n, centre)
            if ao is not None:
                c = scale(c, ao[vi])
            attr.data[li].color_srgb = (c[0], c[1], c[2], 1.0)


def occlusion(ob, others=(), rays=20, reach=4.0, strength=0.55):
    """A per-vertex ambient factor in [1 - strength, 1]: rays over the normal's
    hemisphere that hit this object (or `others`) within `reach` darken it."""
    dg = bpy.context.evaluated_depsgraph_get()
    verts, polys = [], []
    for o in (ob, *others):
        me = o.data
        mw = o.matrix_world
        base = len(verts)
        verts.extend(mw @ v.co for v in me.vertices)
        polys.extend([base + i for i in p.vertices] for p in me.polygons)
    tree = BVHTree.FromPolygons(verts, polys)
    rnd = random.Random(7)
    dirs = []
    for _ in range(rays):
        # cosine-weighted hemisphere about +Z, rotated to each normal below
        u, v = rnd.random(), rnd.random()
        r, a = math.sqrt(u), v * math.tau
        dirs.append(Vector((r * math.cos(a), r * math.sin(a), math.sqrt(max(0.0, 1 - u)))))
    me = ob.data
    mw = ob.matrix_world
    nrm = mw.to_3x3().inverted().transposed()
    out = []
    for v in me.vertices:
        p = mw @ v.co
        n = (nrm @ v.normal).normalized()
        rot = n.to_track_quat("Z", "Y").to_matrix()
        hits = 0
        start = p + n * 0.05
        for d in dirs:
            loc, _, _, dist = tree.ray_cast(start, rot @ d, reach)
            if loc is not None:
                hits += 1 - (dist / reach) * 0.5
        out.append(1.0 - strength * min(1.0, hits / rays * 1.3))
    return out


# ------------------------------------------------------------------ packing


def blender_to_roblox(v):
    return (v[0], v[2], -v[1])


def pack_object(ob, origin=Vector((0, 0, 0)), max_tris=19000):
    """The object's triangles in Roblox space relative to `origin`, as one or
    more packed chunks (EditableMesh holds 20,000 triangles at most)."""
    me = ob.data
    me.calc_loop_triangles()
    mw = ob.matrix_world
    nrm = mw.to_3x3().inverted().transposed()
    corner_normals = [nrm @ cn.vector for cn in me.corner_normals]
    attr = me.color_attributes.get("Col")
    vc = bool(ob.get("rbx_vc", True)) and attr is not None
    tris = []
    for lt in me.loop_triangles:
        corners = []
        for li in lt.loops:
            vi = me.loops[li].vertex_index
            p = mw @ me.vertices[vi].co - origin
            n = corner_normals[li].normalized()
            c = tuple(attr.data[li].color_srgb[:3]) if vc else (1.0, 1.0, 1.0)
            corners.append((blender_to_roblox(p), blender_to_roblox(n), c))
        tris.append(corners)
    chunks = [tris[i : i + max_tris] for i in range(0, len(tris), max_tris)]
    return [pack_tris(chunk, vc) for chunk in chunks if chunk], vc


def pack_tris(tris, vc):
    verts, index, out = [], {}, []
    for tri in tris:
        ids = []
        for p, n, c in tri:
            qn = tuple(max(-127, min(127, round(x * 127))) for x in n)
            qc = tuple(max(0, min(255, round(x * 255))) for x in c) if vc else (255, 255, 255)
            key = (round(p[0], 3), round(p[1], 3), round(p[2], 3), qn, qc)
            if key not in index:
                index[key] = len(verts)
                verts.append((p, qn, qc))
            ids.append(index[key])
        out.append(ids)
    lo = [min(v[0][i] for v in verts) for i in range(3)]
    hi = [max(v[0][i] for v in verts) for i in range(3)]
    span = [max(hi[i] - lo[i], 1e-4) for i in range(3)]
    buf = bytearray()
    for p, qn, qc in verts:
        buf += struct.pack("<HHH", *[round((p[i] - lo[i]) / span[i] * 65535) for i in range(3)])
        buf += struct.pack("<bbb", *qn)
        if vc:
            buf += struct.pack("<BBB", *qc)
    for t in out:
        buf += struct.pack("<HHH", *t)
    assert len(verts) < 60000, f"{len(verts)} vertices: over EditableMesh's limit"
    return {"verts": len(verts), "tris": len(out), "min": lo, "max": hi, "data": base64.b64encode(bytes(buf)).decode("ascii")}


def roblox_matrix(m):
    """A Blender 3x3 rotation as the Roblox CFrame's 9 numbers (R00..R22)."""
    p = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))
    r = p @ m @ p.inverted()
    return [r[0][0], r[0][1], r[0][2], r[1][0], r[1][1], r[1][2], r[2][0], r[2][1], r[2][2]]

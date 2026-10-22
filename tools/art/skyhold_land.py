"""Skyhold's land in Blender (T6/T7): the rock the island floats on, the market
islet's, the small floating isles around it, the clouds and the far peak.

The main island's rock is hung from the very rim the game's Terrain stops at
(work/skyhold/plan.json, exported by tools/art/skyhold_plan.luau): a rocky lip
that rises a little above the grass round the edge, layered cliffs that bulge
then taper into lobes and spikes far below, all faceted (Voronoi displacement,
then a decimate that leaves irregular planes) and painted per corner: grass on
the lip, moss on every ledge, warm sandstone bands under the rim cooling to
blue-grey stone in the depths, ambient occlusion in every crease.
"""

from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import skyhold_util as U
from skyhold_util import mix, n3, rgb, smooth

GRASS = rgb(116, 164, 60)
GRASS_DARK = rgb(88, 136, 52)
MOSS = rgb(92, 132, 58)
MOSS_DARK = rgb(64, 98, 48)
# sandstone strata: cream, ochre, rust, grey-brown, ochre again
WARM = [rgb(226, 204, 160), rgb(204, 164, 106), rgb(174, 116, 78), rgb(150, 128, 104), rgb(214, 182, 128)]
COOL = rgb(120, 126, 148)
DEEP = rgb(88, 90, 120)
CRYSTAL = [96, 236, 214]
ROOT = rgb(92, 70, 52)


def _ccw(points):
    area = 0.0
    for i in range(len(points)):
        x0, y0 = points[i][0], points[i][1]
        x1, y1 = points[(i + 1) % len(points)][0], points[(i + 1) % len(points)][1]
        area += x0 * y1 - x1 * y0
    return points if area > 0 else list(reversed(points))


def _resample(points, step):
    """Even spacing round a closed (x, y, h) loop."""
    out = []
    n = len(points)
    for i in range(n):
        a, b = points[i], points[(i + 1) % n]
        d = math.dist(a[:2], b[:2])
        k = max(1, int(d / step))
        for j in range(k):
            t = j / k
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t))
    return out


def _normals(points):
    """Outward 2D normals of a counter-clockwise loop."""
    out = []
    n = len(points)
    for i in range(n):
        a, b = points[i - 1], points[(i + 1) % n]
        tx, ty = b[0] - a[0], b[1] - a[1]
        length = math.hypot(tx, ty) or 1.0
        out.append((ty / length, -tx / length))
    return out


def rock_mass(coll, name, rim, depth, seed, lip=1.25, bulge=3.0, spikes=10, scale=1.0, grass_top=False, crystals=0, vines=0, tip=1.15, rounding=1.6, apron=0.0):
    """The rock under a piece of floating land whose ground ends at `rim`
    ((x, y, h) in Blender space). `apron` studs push the lip and the first
    studs of cliff out past the rim, over the Terrain's own edge (its 4-stud
    voxels reach past the rim and would show as a dark band). Returns the object."""
    rnd = random.Random(seed)
    pts = _ccw(_resample(rim, 2.4 * scale))
    nrm = _normals(pts)
    n = len(pts)
    cx = sum(p[0] for p in pts) / n
    cy = sum(p[1] for p in pts) / n
    base = sum(p[2] for p in pts) / n
    bm = bmesh.new()
    rings = []

    def ring(fn):
        verts = []
        for i, p in enumerate(pts):
            verts.append(bm.verts.new(fn(i, p)))
        rings.append(verts)

    # under the grass (hidden), the lip's crest, the overhang
    ring(lambda i, p: (p[0] - nrm[i][0] * 3.6 * scale, p[1] - nrm[i][1] * 3.6 * scale, p[2] - 1.8 * scale))
    ring(lambda i, p: (p[0] + nrm[i][0] * (0.4 * scale + apron), p[1] + nrm[i][1] * (0.4 * scale + apron), p[2] + lip * (0.7 + 0.6 * n3((p[0], p[1], 0), 6, seed))))
    ring(lambda i, p: (p[0] + nrm[i][0] * (1.6 * scale + apron), p[1] + nrm[i][1] * (1.6 * scale + apron), p[2] - 1.2 * scale))

    levels = [3, 6, 10, 15, 21, 28, 36, 45, 55, 66, 78, 91, 105, 120, 136, 152, 168]
    levels = [d / levels[-1] * depth for d in levels]
    for d in levels:
        t = d / depth

        def at(i, p, d=d, t=t):
            ang = math.atan2(p[1] - cy, p[0] - cx)
            # lobes: some sectors hang deeper than others
            lobe = n3((math.cos(ang) * 3, math.sin(ang) * 3, 0), 1.0, seed)
            reach = 0.55 + 0.75 * lobe
            te = min(1.0, t / reach)
            # (with an apron the cliff holds its line under the lip before it tapers)
            lead = 0.04 * (smooth(d / (30 * scale)) if apron else 1.0)
            shrink = lead + 0.96 * te**rounding
            # a bulge under the rim, then the taper
            out = bulge * scale * math.sin(math.pi * min(1.0, t * 3.2)) * (1 - te)
            out += apron * (1 - smooth((d - 18) / 16))
            # sedimentary steps: a ledge every few studs
            ledge = -0.9 * scale if ((d + 3 * n3(p, 9, seed)) % (7 * scale)) < 1.4 * scale else 0.0
            k = 1 - shrink
            x = cx + (p[0] - cx) * k + nrm[i][0] * (out + ledge)
            y = cy + (p[1] - cy) * k + nrm[i][1] * (out + ledge)
            top = p[2] - d
            z = top + (base - p[2]) * smooth((d - 8 * scale) / (30 * scale))
            z -= lobe * d * 0.35
            return (x, y, z)

        ring(at)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((b[i], b[j], a[j], a[i]))
    bottom = bm.verts.new((cx, cy, base - depth * tip))
    last = rings[-1]
    for i in range(n):
        bm.faces.new((last[(i + 1) % n], last[i], bottom))

    # stalactite spikes under the lobes
    under = [v for v in last]
    for _ in range(spikes):
        v = rnd.choice(under)
        r = rnd.uniform(3, 7) * scale
        h = rnd.uniform(10, 26) * scale
        geom = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=6, radius1=r, radius2=0.2, depth=h)
        verts = geom["verts"]
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi, 3, "X"))
        bmesh.ops.translate(bm, verts=verts, vec=(v.co.x * 0.85 + cx * 0.15, v.co.y * 0.85 + cy * 0.15, v.co.z - h / 2 + 2))

    ob = U.obj_from_bm(name, bm, coll, part="rock", material="SmoothPlastic", recalc=False)
    # keep the lip clean of displacement: weight by depth under the rim
    vg = ob.vertex_groups.new(name="rough")
    for v in ob.data.vertices:
        w = smooth((base + lip - v.co.z) / (7 * scale))
        vg.add([v.index], w, "REPLACE")
    keep = ob.vertex_groups.new(name="keep")
    keep.add([v.index for v in ob.data.vertices if v.co.z > base - 3 * scale], 1.0, "REPLACE")
    U.displace(ob, "VORONOI", 9.0 * scale, 3.6 * scale, group="rough", seed=seed)
    U.displace(ob, "CLOUDS", 3.0 * scale, 0.9 * scale, group="rough", seed=seed + 1)
    U.decimate(ob, 0.5, group="keep")
    U.bake(ob)
    U.shade(ob, flat=True)

    def colour(p, nn, c):
        dz = p.z - base
        k = n3(p, 5, seed)
        if c.z - base > -2.5 * scale and nn.z > 0.3:
            return mix(GRASS_DARK, GRASS, k)
        if nn.z > 0.55:
            return mix(MOSS_DARK, MOSS, k)
        # bands that wander a little, as real strata do, blended across each face
        f = -dz / (5.5 * scale) + n3(p, 14, seed + 4) * 2.2
        i0 = int(math.floor(f))
        band = mix(WARM[i0 % len(WARM)], WARM[(i0 + 1) % len(WARM)], smooth((f - i0 - 0.7) / 0.3))
        col = mix(band, COOL, smooth((-dz - 34 * scale) / (60 * scale)))
        col = mix(col, DEEP, smooth((-dz - 90 * scale) / (80 * scale)))
        if nn.z > 0.28:
            col = mix(col, MOSS, 0.6)
        if -dz < 7 * scale and nn.z < -0.15:
            col = mix(col, ROOT, 0.4)  # earth and roots under the overhang
        # moss running down from the lip in streaks
        if -dz < 14 * scale and n3((p.x, p.y, 0), 3.5, seed + 7) > 0.7 - smooth(-dz / (14 * scale)) * 0.25:
            col = mix(col, MOSS_DARK, 0.55)
        return U.scale(col, 0.9 + 0.2 * k)

    ao = U.occlusion(ob, reach=10 * scale, strength=0.5, rays=16)
    U.paint(ob, colour, ao)
    if grass_top:
        _grass_cap(coll, name + "Top", pts, seed, scale)
    if crystals:
        _crystals(coll, name + "Crystals", ob, base, depth, crystals, seed)
    if vines:
        _vines(coll, name + "Vines", pts, nrm, vines, seed, scale, apron)
    return ob


def _surface_points(ob, rnd, count, test):
    """Random spots on the rock's faces that pass `test(position, normal)`."""
    me = ob.data
    polys = [p for p in me.polygons if test(p.center, p.normal)]
    rnd.shuffle(polys)
    return [(p.center.copy(), p.normal.copy()) for p in polys[:count]]


def _crystals(coll, name, rock, base, depth, count, seed):
    """Clusters of glowing teal crystal growing out of the underside."""
    rnd = random.Random(seed + 11)
    spots = _surface_points(rock, rnd, count, lambda c, n: c.z < base - depth * 0.3 and n.z < 0.2)
    bm = bmesh.new()
    for c, n in spots:
        for _ in range(rnd.randint(3, 5)):
            d = (n + Vector((rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), rnd.uniform(-0.6, 0.1)))).normalized()
            length = rnd.uniform(2.5, 7.0)
            w = length * rnd.uniform(0.16, 0.24)
            rings = U.lathe(bm, [(0.0, -0.5), (w, 0.0), (w * 0.8, length * 0.7), (0.0, length)], 5)
            rotm = d.to_track_quat("Z", "Y").to_matrix()
            for ring_ in rings:
                for v in ring_:
                    v.co = rotm @ v.co + c - n * 0.6
    ob = U.obj_from_bm(name, bm, coll, part="Crystal", material="Neon", vc=False, color=CRYSTAL, shadow=False, tag="WWRune")
    U.shade(ob, flat=True)
    return ob


def _vines(coll, name, pts, nrm, count, seed, scale, apron=0.0):
    """Roots and ivy hanging from the lip."""
    rnd = random.Random(seed + 13)
    bm = bmesh.new()
    n = len(pts)
    for _ in range(count):
        i = rnd.randrange(n)
        p, nn = pts[i], nrm[i]
        length = rnd.uniform(4, 13) * scale
        start = Vector((p[0] + nn[0] * (0.9 * scale + apron), p[1] + nn[1] * (0.9 * scale + apron), p[2] + 0.3))
        path = []
        for k in range(7):
            t = k / 6
            out = 1.6 * scale * math.sin(t * math.pi * 0.6)
            path.append((start.x + nn[0] * out, start.y + nn[1] * out, start.z - t * length))
        U.tube(bm, path, rnd.uniform(0.09, 0.18) * scale, 4)
    ob = U.obj_from_bm(name, bm, coll, part="vines")
    U.shade(ob, flat=False, angle=None)
    U.paint(ob, lambda p, nn, c: mix(rgb(70, 108, 50), rgb(104, 86, 60), n3(c, 2, seed)))
    return ob


def _grass_cap(coll, name, pts, seed, scale):
    """A domed grassy top for a small isle nobody walks on (no Terrain)."""
    bm = bmesh.new()
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    top = max(p[2] for p in pts)
    centre = bm.verts.new((cx, cy, top + 2.2 * scale))
    mids = []
    for p in pts:
        mx, my = cx + (p[0] - cx) * 0.55, cy + (p[1] - cy) * 0.55
        mids.append(bm.verts.new((mx, my, top + 1.6 * scale + n3((mx, my, 0), 4, seed) * scale)))
    edge = [bm.verts.new((p[0], p[1], p[2] + 0.9 * scale)) for p in pts]
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((centre, mids[i], mids[j]))
        bm.faces.new((mids[i], edge[i], edge[j], mids[j]))
    ob = U.obj_from_bm(name, bm, coll, part="grass", recalc=False)
    U.shade(ob, flat=True)
    U.paint(ob, lambda p, nn, c: U.scale(mix(GRASS_DARK, GRASS, n3(c, 3, seed)), 1.0))
    return ob


def blob_rim(radius, seed, points=40, wobble=0.28, h=0.0):
    rnd = random.Random(seed)
    out = []
    phase = rnd.random() * 10
    for i in range(points):
        a = i / points * math.tau
        r = radius * (1 + wobble * (n3((math.cos(a) * 2 + phase, math.sin(a) * 2, 0), 1.0, seed) - 0.5) * 2)
        out.append((math.cos(a) * r, math.sin(a) * r, h))
    return out


def float_isle(coll, name, radius, seed):
    """A small floating isle with a grassy dome: scenery round the hub."""
    rim = blob_rim(radius, seed)
    rock = rock_mass(
        coll, name, rim, depth=radius * 1.5, seed=seed, lip=0.6, bulge=radius * 0.2, spikes=2, scale=max(0.35, radius / 26), grass_top=True, crystals=2, vines=8, tip=0.85, rounding=2.6
    )
    return rock


def cloud(coll, name, size, seed, flat=0.45):
    """A soft cloud bank: puffs merged by a voxel remesh, smoothed round."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    puffs = 7 + int(size / 14)
    for k in range(puffs):
        r = size * rnd.uniform(0.18, 0.34) * (1.25 if k == 0 else 1)
        x = rnd.uniform(-0.5, 0.5) * size
        y = rnd.uniform(-0.32, 0.32) * size
        z = rnd.uniform(0, 0.2) * size + r * 0.3  # puffs at different heights: relief seen from above
        geom = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r)
        bmesh.ops.scale(bm, vec=(1, 1, flat), verts=geom["verts"])
        bmesh.ops.translate(bm, vec=(x, y, z), verts=geom["verts"])
    ob = U.obj_from_bm(name, bm, coll, part="cloud")
    U.remesh(ob, max(1.2, size / 34))
    U.smooth_mod(ob, 0.8, 6)
    U.decimate(ob, 0.35)
    U.bake(ob)
    # flatten the underside a little, like real cloud bases
    lo = min(v.co.z for v in ob.data.vertices)
    for v in ob.data.vertices:
        if v.co.z < lo + size * 0.08:
            v.co.z = lo + (v.co.z - lo) * 0.35
    U.shade(ob, flat=False, angle=None)
    top = max(v.co.z for v in ob.data.vertices)

    def colour(p, nn, c):
        h = (p.z - lo) / max(top - lo, 0.01)
        base = mix(rgb(196, 208, 230), rgb(248, 248, 250), smooth(h * 1.4))
        if nn.z < -0.2:
            base = mix(base, rgb(182, 194, 220), 0.6)
        # the warm side faces the afternoon sun, in the west (-x)
        return mix(base, rgb(255, 232, 210), max(0.0, -nn.x) * 0.3)

    U.paint(ob, colour)
    ob["rbx_shadow"] = False
    return ob


def far_peak(coll, name, seed):
    """The far mountain island on the horizon (like Sky's): steep rounded
    peaks over green shoulders, floating on its own rock."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    peaks = [(0, 0, 230, 120), (70, 40, 170, 90), (-80, 30, 140, 80), (30, -70, 120, 70)]
    for x, y, h, r in peaks:
        geom = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=14, radius1=r, radius2=r * 0.12, depth=h)
        bmesh.ops.translate(bm, vec=(x, y, h / 2), verts=geom["verts"])
    ob = U.obj_from_bm(name, bm, coll, part="peak")
    U.remesh(ob, 9)
    U.smooth_mod(ob, 0.6, 3)
    U.displace(ob, "VORONOI", 60, 18, seed=seed)
    U.decimate(ob, 0.5)
    U.bake(ob)
    U.shade(ob, flat=True)
    top = max(v.co.z for v in ob.data.vertices)

    def colour(p, nn, c):
        h = c.z / top
        k = n3(c, 40, seed)
        if nn.z > 0.55 and h < 0.55:
            return mix(rgb(70, 118, 66), rgb(98, 146, 76), k)
        rock = mix(rgb(150, 156, 168), rgb(118, 124, 142), k)
        return mix(rock, rgb(214, 220, 232), smooth((h - 0.82) / 0.18))

    U.paint(ob, colour)
    base = blob_rim(150, seed + 3, points=36, wobble=0.18)
    rock_mass(coll, name + "Rock", base, depth=220, seed=seed + 5, lip=2, bulge=12, spikes=6, scale=5)
    return ob


def waterfall(coll, name, drop, width, seed):
    """A ribbon of falling water, curving out from a ledge."""
    bm = bmesh.new()
    rows = []
    steps = 14
    for k in range(steps + 1):
        t = k / steps
        y = -(1 - (1 - t) ** 2) * 6  # out from the ledge
        z = -drop * t
        w = width * (1 + 0.5 * t)
        rows.append([bm.verts.new((x * w / 2, y, z)) for x in (-1, -0.33, 0.33, 1)])
    for a, b in zip(rows, rows[1:]):
        for i in range(3):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    ob = U.obj_from_bm(name, bm, coll, part="water", recalc=False, transparency=0.25, shadow=False, tag="WWMist")
    solid = ob.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.3
    U.bake(ob)
    U.shade(ob, flat=False, angle=None)

    def colour(p, nn, c):
        return mix(rgb(236, 248, 255), rgb(170, 214, 236), n3(c, 3, seed) * 0.6)

    U.paint(ob, colour)
    return ob

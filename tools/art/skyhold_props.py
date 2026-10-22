"""Skyhold's architecture and props in Blender (T6/T7).

Every asset is modelled at the origin, its foot at z = 0, its front facing
south (Blender -Y, the game's +Z): the kit's layout turns and places it. Parts
that the game lights or tints at runtime are their own objects with plain
colours (rbx_vc False): a rune circle's Glow and Slot crystals, the portal's
Runes and Crystal, a plinth's Banner, a lantern's Glass. Stone, wood and cloth
are painted per corner, with ambient occlusion baked into the colour.

Objects named COL_* are not drawn: they become the asset's invisible colliders.
"""

from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import skyhold_util as U
from skyhold_util import mix, n3, rgb, smooth

STONE = rgb(216, 198, 162)
STONE_MID = rgb(192, 172, 138)
STONE_DARK = rgb(140, 122, 98)
STONE_COOL = rgb(206, 198, 182)
STONE_PORTAL = rgb(220, 206, 178)
MOSS = rgb(108, 148, 62)
WOOD = rgb(150, 104, 66)
WOOD_DARK = rgb(100, 68, 46)
IRON = rgb(64, 62, 60)
GOLD = rgb(232, 186, 84)
BRASS = rgb(204, 160, 80)
TEAL = rgb(70, 214, 200)
CLOTH = {
    "teal": rgb(52, 158, 150),
    "coral": rgb(226, 108, 84),
    "saffron": rgb(236, 176, 62),
    "cream": rgb(244, 232, 206),
    "plum": rgb(128, 80, 132),
    "sky": rgb(94, 150, 214),
}


def collider(coll, name, loc, size, rot=(0, 0, 0), shape="box"):
    """An invisible collider (the game builds a Part from it)."""
    ob = bpy.data.objects.new("COL_" + name, None)
    ob.empty_display_type = "CUBE"
    ob.location = loc
    ob.rotation_euler = rot
    ob.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    ob["shape"] = shape
    coll.objects.link(ob)
    return ob


def stone_paint(seed, base=STONE, mossy=0.6, top_moss=True, dark=STONE_DARK):
    def colour(p, n, c):
        k = n3(c, 2.5, seed)
        col = mix(dark, base, 0.55 + 0.45 * k)
        if top_moss and n.z > 0.6 and n3(c, 4, seed + 3) > 1 - mossy * 0.5:
            col = mix(col, MOSS, 0.7)
        return col

    return colour


def finish(ob, colour, reach=2.5, strength=0.5, flat=True, others=(), angle=40):
    U.bake(ob)
    U.shade(ob, flat=flat, angle=angle)
    ao = U.occlusion(ob, others=others, reach=reach, strength=strength, rays=16)
    U.paint(ob, colour, ao)
    return ob


def plain(ob, flat=True):
    U.bake(ob)
    U.shade(ob, flat=flat, angle=40)
    return ob


# ------------------------------------------------------------------ the portal


def portal(coll, centre_height, inner=13.4, outer=17.2, seed=11):
    """The Skygate: a great ring of fitted voussoirs with an inner reveal, an
    outer moulding and a heavy keystone set with a glowing gem, rising from a
    stepped dais between two rune obelisks crowned with floating crystals.
    The glowing face inside the ring is the game's own (Skyhold/Builder)."""
    rnd = random.Random(seed)
    objs = []
    # the dais: three broad tiers
    bm = bmesh.new()
    tiers = [(40, 18), (33, 14.5), (26, 11)]
    for k, (w, d) in enumerate(tiers):
        U.box(bm, 0, 0, 0.9 * k + 0.45, w, d, 0.9)
    dais = U.obj_from_bm("Dais", bm, coll, part="stone")
    U.bevel(dais, 0.45, 2, 30)
    objs.append(finish(dais, stone_paint(seed, STONE, 0.5), reach=3))
    for k, (w, d) in enumerate(tiers):
        collider(coll, f"Step{k}", (0, 0, 0.9 * k + 0.45), (w, d, 0.9))

    rot = Matrix.Rotation(math.pi / 2, 4, "X")
    lift = Matrix.Translation((0, 0, centre_height))
    # the ring: tight voussoirs, the keystone at the top
    bm = bmesh.new()
    blocks = 22
    gap = 0.012
    for b in range(blocks):
        a0 = (b - 0.5) / blocks * math.tau + math.pi / 2 + gap
        a1 = (b + 0.5) / blocks * math.tau + math.pi / 2 - gap
        key = b == 0
        U.arc_block(bm, inner, outer + (1.6 if key else rnd.uniform(-0.1, 0.15)), a0, a1, -2.2 - (0.3 if key else 0), 2.2 + (0.3 if key else 0), steps=3)
    # the inner reveal and the outer moulding, stepped back
    for b in range(44):
        a0, a1 = b / 44 * math.tau, (b + 1) / 44 * math.tau
        U.arc_block(bm, inner - 0.7, inner + 0.05, a0, a1, -1.3, 1.3, steps=1)
        U.arc_block(bm, outer - 0.05, outer + 0.55, a0, a1, -1.0, 1.0, steps=1)
    U.transform_bm(bm, lift @ rot)
    ring = U.obj_from_bm("Ring", bm, coll, part="stone")
    U.bevel(ring, 0.16, 1, 30)

    def ring_colour(p, n, c):
        r = math.hypot(c.x, c.z - centre_height)
        k = n3(c, 2.2, seed)
        col = mix(STONE_DARK, STONE_PORTAL, 0.6 + 0.4 * k)
        if r > outer - 0.1 or r < inner - 0.05:
            col = mix(col, STONE_DARK, 0.45)  # the mouldings read darker
        if n.z > 0.55 and n3(c, 3.5, seed + 2) > 0.45:
            col = mix(col, MOSS, 0.75)
        return col

    objs.append(finish(ring, ring_colour, reach=4, strength=0.55))
    # the ring's sides, where it stands on the dais
    for side in (-1, 1):
        collider(coll, f"Leg{side}", (side * (inner + outer) / 2, 0, 2.7 + 7.5), (outer - inner + 0.6, 4.6, 15))

    # runes: a band round the inner reveal on both faces, glyphs round the
    # ring's face, the keystone's gem
    bm = bmesh.new()
    for face_y in (-1.32, 1.32):
        for b in range(56):
            U.arc_block(bm, inner - 0.62, inner - 0.32, b / 56 * math.tau, (b + 0.8) / 56 * math.tau, face_y - 0.06, face_y + 0.06, steps=1)
    for face_y in (-2.24, 2.24):
        for g in range(14):
            a = g / 14 * math.tau + math.pi / 14
            cx, cz = math.cos(a) * (inner + outer) / 2, math.sin(a) * (inner + outer) / 2
            # (the ring still lies flat here: x, y round it, z out of its face)
            for dx, dz, sx, sz in ((0, 0, 0.2, 1.1), (0.26, 0.3, 0.5, 0.16), (-0.24, -0.34, 0.44, 0.16), (0.0, 0.62, 0.4, 0.14)):
                U.box(bm, cx + dx, cz + dz, face_y, sx, sz, 0.08, rot=0)
    # (before the ring is stood up: y is up the ring, z out of its face)
    for face in (1, -1):
        U.offset(U.lathe(bm, [(0.0, -0.9), (0.95, 0.0), (0.0, 0.9)], 6), 0, outer + 0.85, face * 2.45)
    U.transform_bm(bm, lift @ rot)
    runes = U.obj_from_bm("Runes", bm, coll, part="Runes", material="Neon", vc=False, color=[96, 238, 216], tag="WWRune", shadow=False)
    plain(runes)
    objs.append(runes)

    # the obelisks, crowned with gold and a floating crystal
    for side in (-1, 1):
        x = side * 25.0
        bm = bmesh.new()
        U.box(bm, x, 0, 1.2, 5.2, 5.2, 2.4)
        U.box(bm, x, 0, 2.7, 4.4, 4.4, 0.6)
        U.offset(U.lathe(bm, [(2.2, 3.0), (1.75, 25.0), (1.95, 25.0), (1.95, 25.6), (0.0, 25.6)], 4, phase=math.pi / 4), x, 0)
        ob = U.obj_from_bm(f"Obelisk{side}", bm, coll, part="stone")
        U.bevel(ob, 0.12, 1, 30)
        objs.append(finish(ob, stone_paint(seed + 4 + side, STONE_PORTAL, 0.6), reach=3))
        collider(coll, f"Obelisk{side}", (x, 0, 13), (5, 5, 26))
        bm = bmesh.new()
        U.offset(U.lathe(bm, [(1.4, 25.6), (0.0, 28.6)], 4, phase=math.pi / 4), x, 0)
        cap = U.obj_from_bm(f"Cap{side}", bm, coll, part="gold")
        finish(cap, lambda p, n, c: mix(GOLD, rgb(252, 222, 140), max(0.0, n.z)), reach=1, strength=0.3)
        bm = bmesh.new()
        for z in (9.0, 16.5):
            U.offset(U.lathe(bm, [(2.02, z), (1.9, z + 0.4), (0.0, z + 0.4)], 4, phase=math.pi / 4), x, 0)
        U.offset(U.lathe(bm, [(0.0, 30.0), (1.0, 31.8), (0.0, 34.6)], 6), x, 0)
        glow = U.obj_from_bm(f"Crystal{side}", bm, coll, part="Crystal", material="Neon", vc=False, color=[110, 240, 222], shadow=False, tag="WWRune")
        plain(glow)
        objs.append(glow)
    return objs


def rune_stone(coll, seed=31):
    """One of the monoliths that circle the portal (the client turns them)."""
    bm = bmesh.new()
    U.box(bm, 0, 0, 1.6, 1.7, 0.8, 3.2)
    ob = U.obj_from_bm("Stone", bm, coll, part="stone")
    U.bevel(ob, 0.32, 2, 30)
    finish(ob, stone_paint(seed, rgb(112, 118, 120), 0.2, dark=rgb(78, 84, 88)), reach=1.5)
    bm = bmesh.new()
    for dx, dz, sx, sz in ((0, 0, 0.16, 1.6), (0.32, 0.4, 0.5, 0.14), (-0.3, -0.35, 0.5, 0.14), (0, 0.9, 0.5, 0.14)):
        U.box(bm, dx, -0.42, 1.6 + dz, sx, 0.06, sz)
    glyph = U.obj_from_bm("Glyph", bm, coll, part="Glyph", material="Neon", vc=False, color=[90, 236, 214], tag="WWRune", shadow=False)
    plain(glyph)


# ------------------------------------------------------------------ the plaza and its circles


def frustum_tile(bm, poly, z0, z1, inset):
    """A paving stone: a prism whose top is inset (a cheap chamfer)."""
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    top_poly = [(cx + (x - cx) * (1 - inset), cy + (y - cy) * (1 - inset)) for x, y in poly]
    bottom = [bm.verts.new((x, y, z0)) for x, y in poly]
    top = [bm.verts.new((x, y, z1)) for x, y in top_poly]
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bm.faces.new(top)


def plaza(coll, radius=34.0, seed=21):
    """The round plaza before the portal: rings of fitted paving round a rune
    medallion, a kerb with four ways in, grass growing in the joints."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    # the medallion: one disc of darker stone
    U.lathe(bm, [(0.0, 0.3), (7.3, 0.3), (7.3, 0.0)], 32)
    r = 7.6
    width = 2.6
    while r + width <= radius:
        ring_len = math.tau * (r + width / 2)
        count = max(8, int(ring_len / 3.1))
        phase = rnd.random()
        for k in range(count):
            a0 = (k + phase) / count * math.tau + 0.006 * 32 / (r + 1)
            a1 = (k + 1 + phase) / count * math.tau - 0.006 * 32 / (r + 1)
            poly = []
            for t in (0, 0.5, 1):
                a = a0 + (a1 - a0) * t
                poly.append((math.cos(a) * (r + 0.08), math.sin(a) * (r + 0.08)))
            for t in (1, 0.5, 0):
                a = a0 + (a1 - a0) * t
                poly.append((math.cos(a) * (r + width - 0.08), math.sin(a) * (r + width - 0.08)))
            frustum_tile(bm, poly, 0.0, rnd.uniform(0.18, 0.3), 0.06)
        r += width
    ob = U.obj_from_bm("Paving", bm, coll, part="stone")

    def colour(p, n, c):
        k = n3(c, 1.7, seed)
        tone = [STONE, STONE_MID, rgb(222, 212, 188), rgb(200, 188, 164)][int(n3(c, 2.9, seed + 9) * 3.99)]
        col = mix(tone, STONE_DARK, 0.18 * k)
        if math.hypot(c.x, c.y) < 7.4:
            col = mix(rgb(150, 156, 158), rgb(176, 180, 178), k)
        if n.z < 0.5:
            col = U.scale(col, 0.78)
        return col

    finish(ob, colour, reach=1.2, strength=0.35)
    collider(ob.users_collection[0], "Floor", (0, 0, 0.12), (radius * 2, radius * 2, 0.25), shape="cyl")

    # the kerb, with ways in to the south, west, east and the portal (north)
    bm = bmesh.new()
    ways = [-math.pi / 2, math.pi, 0.0, math.pi / 2]
    blocks = 64
    for k in range(blocks):
        a0 = k / blocks * math.tau
        a1 = (k + 0.92) / blocks * math.tau
        mid = (a0 + a1) / 2
        if any(abs(math.atan2(math.sin(mid - w), math.cos(mid - w))) < 0.2 for w in ways):
            continue
        U.arc_block(bm, radius + 0.1, radius + 1.5, a0, a1, 0.0, 0.55 + rnd.uniform(0, 0.12), steps=2)
    kerb = U.obj_from_bm("Kerb", bm, coll, part="stone")
    U.bevel(kerb, 0.12, 1, 30)
    finish(kerb, stone_paint(seed + 1, STONE_MID, 0.8), reach=1.5)

    # the medallion's inlaid runes
    bm = bmesh.new()
    for r0, r1 in ((6.55, 6.85), (3.9, 4.15)):
        for b in range(40):
            U.arc_block(bm, r0, r1, b / 40 * math.tau, (b + 0.85) / 40 * math.tau, 0.3, 0.36, steps=1)
    for s in range(8):
        a = s / 8 * math.tau
        U.box(bm, math.cos(a) * 5.35, math.sin(a) * 5.35, 0.33, 2.3, 0.22, 0.06, rot=a)
    U.lathe(bm, [(0.0, 0.37), (1.2, 0.33)], 4)
    inlay = U.obj_from_bm("Inlay", bm, coll, part="Inlay", material="Neon", vc=False, color=[96, 230, 210], tag="WWRune", shadow=False)
    plain(inlay)


def rune_circle(coll, radius=6.0, squad=3, seed=41):
    """A party's place before the portal: a ring of fitted stones, a glowing
    rune pattern the game colours, a crystal socket per member and a stone
    board (its front to the south) that says who is in."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    segs = 12
    for k in range(segs):
        U.arc_block(bm, radius - 1.4, radius, k / segs * math.tau + 0.03, (k + 1) / segs * math.tau - 0.03, 0.0, 0.42 + rnd.uniform(0, 0.08), steps=2)
    # the sockets, one per squad slot (the first at the back, by the board)
    for s in range(squad):
        a = math.pi / 2 + s / squad * math.tau
        x, y = math.cos(a) * (radius - 0.7), math.sin(a) * (radius - 0.7)
        U.offset(U.lathe(bm, [(0.75, 0.0), (0.75, 0.75), (0.55, 0.95), (0.0, 0.95)], 8), x, y)
    ring = U.obj_from_bm("Ring", bm, coll, part="stone")
    U.bevel(ring, 0.1, 1, 30)
    finish(ring, stone_paint(seed, STONE_MID, 0.7), reach=1.2)

    bm = bmesh.new()
    for b in range(36):
        U.arc_block(bm, radius - 2.0, radius - 1.75, b / 36 * math.tau, (b + 0.8) / 36 * math.tau, 0.05, 0.12, steps=1)
    for s in range(6):
        a = s / 6 * math.tau + math.pi / 6
        U.box(bm, math.cos(a) * (radius - 3.0), math.sin(a) * (radius - 3.0), 0.09, 1.6, 0.16, 0.06, rot=a)
    U.lathe(bm, [(0.0, 0.1), (0.9, 0.08)], 6)
    glow = U.obj_from_bm("Glow", bm, coll, part="Glow", material="Neon", vc=False, color=[90, 220, 205], shadow=False)
    plain(glow)

    for s in range(squad):
        a = math.pi / 2 + s / squad * math.tau
        x, y = math.cos(a) * (radius - 0.7), math.sin(a) * (radius - 0.7)
        bm = bmesh.new()
        U.offset(U.lathe(bm, [(0.0, 1.05), (0.42, 1.55), (0.0, 2.35)], 4), x, y)
        slot = U.obj_from_bm(f"Slot{s + 1}", bm, coll, part=f"Slot{s + 1}", material="Neon", vc=False, color=[70, 96, 92], shadow=False)
        plain(slot)

    # the party board at the back, facing south: a little timber notice board
    # with a shingled roof (its plank face carries the game's text)
    y = radius + 1.4
    bm = bmesh.new()
    for x in (-2.0, 2.0):
        U.box(bm, x, y, 2.6, 0.38, 0.38, 5.2)
    U.box(bm, 0, y, 1.55, 4.4, 0.32, 0.26)
    U.box(bm, 0, y, 4.35, 4.4, 0.32, 0.26)
    U.box(bm, -1.85, y, 2.95, 0.26, 0.32, 2.6)
    U.box(bm, 1.85, y, 2.95, 0.26, 0.32, 2.6)
    frame = U.obj_from_bm("Frame", bm, coll, part="wood")
    finish(frame, lambda p, n, c: mix(WOOD_DARK, WOOD, 0.35 + 0.65 * n3(c, 0.9, seed)), reach=1.0)
    bm = bmesh.new()
    for side in (-1, 1):
        v = [
            bm.verts.new((-2.7, y + side * 0.05, 5.55)),
            bm.verts.new((2.7, y + side * 0.05, 5.55)),
            bm.verts.new((2.7, y + side * 1.25, 4.75)),
            bm.verts.new((-2.7, y + side * 1.25, 4.75)),
        ]
        bm.faces.new(list(reversed(v)) if side < 0 else v)
    roof = U.obj_from_bm("Roof", bm, coll, part="roof", recalc=False)
    solid = roof.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.22

    def shingles(p, n, c):
        row = int((5.6 - p.z) / 0.28) % 2
        return mix(rgb(52, 120, 116), rgb(70, 150, 140), 0.3 + 0.4 * row + 0.3 * n3(p, 0.6, seed))

    finish(roof, shingles, reach=1.0, strength=0.3)
    bm = bmesh.new()
    U.box(bm, 0, y - 0.02, 2.95, 3.44, 0.16, 2.6)
    board = U.obj_from_bm("Board", bm, coll, part="Board")

    def planks(p, n, c):
        plank = int((p.z - 1.65) / 0.52)
        return mix(rgb(196, 160, 112), rgb(178, 140, 96), (plank % 2) * 0.6 + 0.4 * n3(p, 0.8, seed + plank))

    finish(board, planks, reach=0.8, strength=0.25)
    collider(coll, "Board", (0, y, 2.6), (4.6, 0.8, 5.2))


# ------------------------------------------------------------------ the Hall of Heroes


def plinth(coll, seed=51):
    """A hero's pedestal: an octagon in three tiers with a gold band, a plaque on
    its front, and a banner on a pole behind it (the game dyes the banner)."""
    bm = bmesh.new()
    prof = [(0.0, 0.0), (3.3, 0.0), (3.3, 0.8), (2.85, 0.8), (2.85, 2.55), (3.1, 2.65), (3.1, 3.0), (2.75, 3.0), (2.75, 3.2), (0.0, 3.2)]
    U.lathe(bm, prof, 8, phase=math.pi / 8)
    ob = U.obj_from_bm("Pedestal", bm, coll, part="stone")
    finish(ob, stone_paint(seed, STONE, 0.4), reach=1.5)
    bm = bmesh.new()
    U.lathe(bm, [(2.9, 2.2), (2.9, 2.45)], 8, phase=math.pi / 8)
    U.box(bm, 0, -2.95, 1.55, 2.2, 0.14, 0.9)
    trim = U.obj_from_bm("Trim", bm, coll, part="trim")
    finish(trim, lambda p, n, c: mix(GOLD, rgb(250, 214, 120), max(0.0, n.z) * 0.6), reach=0.8, strength=0.3)
    collider(coll, "Pedestal", (0, 0, 1.6), (6.6, 6.6, 3.2), shape="cyl")

    bm = bmesh.new()
    U.box(bm, 0, 4.2, 5.3, 0.45, 0.45, 10.6)
    U.box(bm, 0, 4.2, 10.3, 3.4, 0.35, 0.35)
    U.offset(U.lathe(bm, [(0.0, 10.6), (0.35, 10.8), (0.0, 11.3)], 6), 0, 4.2)
    pole = U.obj_from_bm("Pole", bm, coll, part="wood")
    finish(pole, lambda p, n, c: mix(WOOD_DARK, WOOD, n3(c, 1.2, seed)), reach=1.0)
    collider(coll, "Pole", (0, 4.2, 5.3), (0.6, 0.6, 10.6))

    bm = bmesh.new()
    rows = []
    for k in range(9):
        t = k / 8
        z = 10.0 - t * 5.6
        sway = math.sin(t * math.pi) * 0.25
        w = 1.35
        row = [bm.verts.new((x, 4.2 - 0.25 - sway, z)) for x in (-w, 0, w)]
        rows.append(row)
    for a, b in zip(rows, rows[1:]):
        for i in range(2):
            bm.faces.new((a[i], b[i], b[i + 1], a[i + 1]))
    tip = bm.verts.new((0, 4.2 - 0.25, 10.0 - 6.6))
    last = rows[-1]
    bm.faces.new((last[0], tip, last[1]))
    bm.faces.new((last[1], tip, last[2]))
    banner = U.obj_from_bm("Banner", bm, coll, part="Banner", material="Fabric", vc=False, recalc=False, color=[200, 200, 200])
    solid = banner.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.12
    plain(banner)


def column(bm, x, y, height, radius=1.05, broken=False, seed=0):
    """A fluted column on a square base with a flared capital."""
    rnd = random.Random(seed)
    U.box(bm, x, y, 0.45, radius * 2.8, radius * 2.8, 0.9)
    top = height - 1.4 if not broken else height * rnd.uniform(0.35, 0.6)
    flutes = 16
    rings = []
    for z in (0.9, top):
        ring = []
        for i in range(flutes):
            a = i / flutes * math.tau
            r = radius * (0.9 if i % 2 else 1.0) * (1.0 if z < 1 else 0.92)
            ring.append(bm.verts.new((x + math.cos(a) * r, y + math.sin(a) * r, z)))
        rings.append(ring)
    for i in range(flutes):
        j = (i + 1) % flutes
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    if broken:
        # a jagged break
        c = bm.verts.new((x, y, top + 0.4))
        for i in range(flutes):
            j = (i + 1) % flutes
            rings[1][i].co.z += rnd.uniform(-0.6, 0.6)
            bm.faces.new((rings[1][i], rings[1][j], c))
        return top
    bm.faces.new(rings[1])
    U.offset(U.lathe(bm, [(radius * 0.95, top), (radius * 1.45, height - 0.6)], 8), x, y)
    U.box(bm, x, y, height - 0.3, radius * 3.1, radius * 3.1, 0.6)
    return height


def colonnade(coll, seed=61):
    """The Hall of Heroes' colonnade: a row behind the plinths with returning
    wings, its beams fallen in places, one column broken."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    height = 13.0
    spots = []
    for k in range(7):
        spots.append((-22.0, -39.0 + k * 13.0))
    for k in (1, 2):
        spots.append((-22.0 + k * 11.0, -39.0))
        spots.append((-22.0 + k * 11.0, 39.0))
    broken = {2, 8}  # not behind a plinth: a broken column there reads as a gravestone
    tops = {}
    for i, (x, y) in enumerate(spots):
        tops[i] = column(bm, x, y, height, broken=i in broken, seed=seed + i)
        collider(coll, f"Col{i}", (x, y, tops[i] / 2), (2.4, 2.4, tops[i]), shape="cyl")
    links = [(i, i + 1) for i in range(6)] + [(0, 7), (7, 9), (6, 8), (8, 10)]
    missing = {(3, 4), (8, 10)}
    for a, b in links:
        if (a, b) in missing or a in broken or b in broken:
            continue
        (x0, y0), (x1, y1) = spots[a], spots[b]
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        length = math.hypot(x1 - x0, y1 - y0) + 3.0
        U.box(bm, cx, cy, height + 0.9, 2.4 if x0 == x1 else length, length if x0 == x1 else 2.4, 1.8)
    # fallen drums by the broken column
    for k in range(3):
        x, y = spots[2]
        geom = U.lathe(bm, [(0.0, 0.0), (1.0, 0.0), (1.0, 1.6), (0.0, 1.6)], 10)
        for ring_ in geom:
            for v in ring_:
                v.co = Matrix.Rotation(math.pi / 2, 3, "Y") @ v.co
                v.co.x += x + 3 + k * 1.8
                v.co.y += y + rnd.uniform(-2, 2)
                v.co.z += 1.0
    ob = U.obj_from_bm("Colonnade", bm, coll, part="stone")
    U.bevel(ob, 0.12, 1, 35)
    finish(ob, stone_paint(seed, STONE, 0.9), reach=3, strength=0.55)


def hall_floor(coll, seed=65):
    """The Hall of Heroes' terrace: worn paving under the colonnade and the
    plinths, a step up from the grass along its open (east) side."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    x0, x1, y0, y1 = -28.0, 16.0, -45.0, 45.0
    step = 3.0
    x = x0
    while x < x1 - 0.1:
        y = y0 + (0.0 if int((x - x0) / step) % 2 == 0 else -step / 2)
        while y < y1 - 0.1:
            ya, yb = max(y, y0), min(y + step, y1)
            if yb - ya > 0.5 and rnd.random() > 0.04:
                poly = [(x + 0.07, ya + 0.07), (x + step - 0.07, ya + 0.07), (x + step - 0.07, yb - 0.07), (x + 0.07, yb - 0.07)]
                frustum_tile(bm, poly, -0.2, rnd.uniform(0.32, 0.42), 0.05)
            y += step
        x += step
    # the step along the open side, and kerbs along the others
    U.box(bm, x1 + 1.2, 0, 0.15, 2.4, y1 - y0 + 2.4, 0.3)
    U.box(bm, x0 - 0.8, 0, 0.3, 1.6, y1 - y0 + 3.2, 0.6)
    U.box(bm, (x0 + x1) / 2, y0 - 0.8, 0.3, x1 - x0, 1.6, 0.6)
    U.box(bm, (x0 + x1) / 2, y1 + 0.8, 0.3, x1 - x0, 1.6, 0.6)
    ob = U.obj_from_bm("Floor", bm, coll, part="stone")

    def colour(p, n, c):
        k = n3(c, 2.0, seed)
        col = mix(STONE_DARK, STONE, 0.5 + 0.5 * k)
        if n3(c, 6, seed + 1) > 0.66:
            col = mix(col, MOSS, 0.5)  # moss creeping over the old stones
        return col

    finish(ob, colour, reach=1.2, strength=0.35)
    collider(coll, "Floor", ((x0 + x1) / 2, 0, 0.2), (x1 - x0, y1 - y0, 0.4))


def brazier(coll, seed=67):
    """A stone fire bowl on a short column (the game lights its embers)."""
    bm = bmesh.new()
    U.lathe(bm, [(0.0, 0.0), (1.1, 0.0), (1.1, 0.4), (0.55, 0.6), (0.45, 2.6), (1.5, 3.1), (1.7, 3.8), (1.45, 3.8), (0.0, 3.5)], 8)
    ob = U.obj_from_bm("Bowl", bm, coll, part="stone")
    finish(ob, stone_paint(seed, STONE_MID, 0.3, dark=rgb(110, 98, 84)), reach=1.2)
    bm = bmesh.new()
    U.lathe(bm, [(0.0, 3.55), (1.35, 3.6), (0.0, 3.85)], 8)
    embers = U.obj_from_bm("Embers", bm, coll, part="Embers", material="Neon", vc=False, color=[255, 150, 64], shadow=False, tag="WWFlame")
    plain(embers)
    collider(coll, "Bowl", (0, 0, 1.9), (3.2, 3.2, 3.8), shape="cyl")


# ------------------------------------------------------------------ ruins


def ruin_wall(coll, name, length, height, seed, thickness=1.6):
    """A wall of fitted blocks in courses, broken down unevenly, moss on top."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    course = 1.15
    rows = int(height / course)
    profile = [height * (0.45 + 0.55 * smooth(1 - abs((i / 8) - 0.5) * 2 + rnd.uniform(-0.3, 0.3))) for i in range(9)]
    for r in range(rows):
        z = r * course
        x = -length / 2 + (0.0 if r % 2 == 0 else -0.7)
        while x < length / 2:
            w = rnd.uniform(1.6, 2.8)
            x1 = min(x + w, length / 2)
            mid = (x + x1) / 2
            limit = profile[min(8, max(0, int((mid / length + 0.5) * 8)))]
            if z + course <= limit and x1 - x > 0.4:
                U.box(bm, mid, rnd.uniform(-0.06, 0.06), z + course / 2, x1 - x - 0.08, thickness + rnd.uniform(-0.1, 0.1), course - 0.06)
            x = x1
    ob = U.obj_from_bm(name, bm, coll, part="stone")
    U.bevel(ob, 0.14, 1, 35)
    finish(ob, stone_paint(seed, STONE_MID, 1.2), reach=2.0)
    collider(coll, name, (0, 0, height * 0.4), (length, thickness, height * 0.8))


def trophy_wall(coll, seed=71):
    """A curved ruin wall with five empty niches: room for trophies to come."""
    bm = bmesh.new()
    r0, r1 = 11.0, 12.6
    a0, a1 = math.radians(25), math.radians(155)
    U.arc_block(bm, r0, r1, a0, a1, 0.0, 8.5, steps=20)
    ob = U.obj_from_bm("Wall", bm, coll, part="stone")
    for k in range(5):
        a = a0 + (k + 0.5) / 5 * (a1 - a0)
        cbm = bmesh.new()
        U.box(cbm, 0, 0, 0, 2.6, 2.4, 4.4)
        U.lathe(cbm, [(0.0, 2.2), (1.3, 2.2), (0.0, 3.5)], 12)
        for v in cbm.verts:
            v.co = Matrix.Rotation(a - math.pi / 2, 3, "Z") @ v.co
            v.co += Vector((math.cos(a) * r0, math.sin(a) * r0, 3.6))
        cme = bpy.data.meshes.new(f"cut{k}")
        cbm.to_mesh(cme)
        cbm.free()
        cut = bpy.data.objects.new(f"TrophyCut{k}", cme)
        bpy.context.scene.collection.objects.link(cut)
        cut.hide_render = True
        mod = ob.modifiers.new(f"Niche{k}", "BOOLEAN")
        mod.object = cut
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
    U.bake(ob)
    for o in [o for o in bpy.context.scene.collection.objects if o.name.startswith("TrophyCut")]:
        bpy.data.objects.remove(o)
    U.bevel(ob, 0.12, 1, 35)
    finish(ob, stone_paint(seed, STONE, 1.0), reach=2.5)
    bm = bmesh.new()
    U.arc_block(bm, r0 - 0.3, r1 + 0.3, a0, a1, 8.5, 9.2, steps=20)
    for k in range(5):
        a = a0 + (k + 0.5) / 5 * (a1 - a0)
        U.offset(U.lathe(bm, [(0.7, 0.0), (0.7, 1.4), (0.85, 1.6), (0.0, 1.6)], 8), math.cos(a) * (r0 - 2.2), math.sin(a) * (r0 - 2.2))
    cornice = U.obj_from_bm("Cornice", bm, coll, part="stone")
    finish(cornice, stone_paint(seed + 1, STONE_MID, 0.9), reach=1.5)
    for k in range(5):
        a = a0 + (k + 0.5) / 5 * (a1 - a0)
        collider(coll, f"Wall{k}", (math.cos(a) * 11.8, math.sin(a) * 11.8, 4.5), (6.0, 1.8, 9.0), rot=(0, 0, a - math.pi / 2))


# ------------------------------------------------------------------ the settlement's small things


def lantern(coll, seed=81):
    """A wooden lantern post with an iron arm (the glass glows: the game lights it)."""
    bm = bmesh.new()
    U.box(bm, 0, 0, 3.4, 0.5, 0.5, 6.8)
    U.box(bm, 0, 0, 0.3, 1.0, 1.0, 0.6)
    post = U.obj_from_bm("Post", bm, coll, part="wood")
    finish(post, lambda p, n, c: mix(WOOD_DARK, WOOD, n3(c, 1, seed)), reach=1.0)
    bm = bmesh.new()
    U.box(bm, 0, -0.8, 6.6, 0.16, 1.8, 0.16)
    U.box(bm, 0, -1.6, 6.25, 0.08, 0.08, 0.6)
    for dx, dy in ((-0.45, -0.45), (0.45, -0.45), (0.45, 0.45), (-0.45, 0.45)):
        U.box(bm, dx, -1.6 + dy, 5.4, 0.1, 0.1, 1.2)
    U.offset(U.lathe(bm, [(0.65, 6.0), (0.0, 6.5)], 4, phase=math.pi / 4), 0, -1.6)
    U.box(bm, 0, -1.6, 4.8, 1.0, 1.0, 0.12)
    iron = U.obj_from_bm("Iron", bm, coll, part="iron")
    finish(iron, lambda p, n, c: IRON, reach=0.6, strength=0.3)
    bm = bmesh.new()
    U.box(bm, 0, -1.6, 5.4, 0.78, 0.78, 1.1)
    glass = U.obj_from_bm("Glass", bm, coll, part="Glass", material="Neon", vc=False, color=[255, 196, 112], shadow=False, tag="WWFlame")
    plain(glass)
    collider(coll, "Post", (0, 0, 3.4), (0.6, 0.6, 6.8))


def bench(coll, seed=91):
    bm = bmesh.new()
    for x in (-1.5, 1.5):
        U.box(bm, x, 0, 0.6, 0.6, 1.3, 1.2)
    stone = U.obj_from_bm("Legs", bm, coll, part="stone")
    U.bevel(stone, 0.1, 1)
    finish(stone, stone_paint(seed, STONE_MID, 0.6), reach=1.0)
    bm = bmesh.new()
    for k in range(3):
        U.box(bm, 0, -0.45 + k * 0.45, 1.3, 4.2, 0.38, 0.2)
    for k in range(2):
        U.box(bm, 0, 0.75, 1.9 + k * 0.5, 4.2, 0.12, 0.32)
    U.box(bm, -1.5, 0.75, 1.9, 0.2, 0.15, 1.3)
    U.box(bm, 1.5, 0.75, 1.9, 0.2, 0.15, 1.3)
    wood = U.obj_from_bm("Seat", bm, coll, part="wood")
    finish(wood, lambda p, n, c: mix(WOOD_DARK, WOOD, 0.4 + 0.6 * n3(c, 0.7, seed)), reach=1.0)
    collider(coll, "Seat", (0, 0, 0.7), (4.2, 1.4, 1.4))


def crate(bm, x, y, z, s, rot=0.0):
    U.box(bm, x, y, z + s / 2, s, s, s, rot=rot)


def stall(coll, cloth, seed):
    """A market stall, closed for now: a timber frame, a counter under a
    tarp, a striped canopy and crates. Waiting for its trader."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    for x in (-2.8, 2.8):
        for y in (-1.6, 1.6):
            U.box(bm, x, y, 3.2 + (0.5 if y > 0 else 0), 0.35, 0.35, 6.4 + (1.0 if y > 0 else 0))
    U.box(bm, 0, -1.2, 1.2, 5.4, 1.4, 2.4)
    for k in range(3):
        crate(bm, 3.8 + rnd.uniform(-0.2, 0.2), -1.0 + k * 0.4, (0 if k < 2 else 1.1), 1.1, rot=rnd.uniform(-0.3, 0.3))
    frame = U.obj_from_bm("Frame", bm, coll, part="wood")
    finish(frame, lambda p, n, c: mix(WOOD_DARK, WOOD, 0.3 + 0.7 * n3(c, 0.8, seed)), reach=1.5)
    bm = bmesh.new()
    rows = []
    for k in range(9):
        t = k / 8
        y = -2.4 + t * 4.8
        z = 6.2 + t * 1.2
        rows.append([bm.verts.new((x, y, z - 0.18 * math.sin(abs(x) * 1.2))) for x in [-3.4 + i * 0.85 for i in range(9)]])
    for a, b in zip(rows, rows[1:]):
        for i in range(8):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    # the valance: a scalloped hem along the front
    for i in range(8):
        x0, x1 = -3.4 + i * 0.85, -3.4 + (i + 1) * 0.85
        v0, v1 = rows[0][i], rows[0][i + 1]
        m = bm.verts.new(((x0 + x1) / 2, -2.4, 5.4))
        bm.faces.new((v1, v0, m))
    # the tarp over the counter
    U.box(bm, 0, -1.2, 2.5, 5.6, 1.6, 0.22)
    canopy = U.obj_from_bm("Canopy", bm, coll, part="cloth", material="Fabric", recalc=False)
    solid = canopy.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.1
    main = CLOTH[cloth]

    def stripes(p, n, c):
        band = int((c.x + 3.4) / 0.85) % 2
        col = main if band == 0 else CLOTH["cream"]
        if c.z < 3:
            col = mix(main, rgb(90, 80, 70), 0.3)
        return col

    finish(canopy, stripes, reach=1.5, strength=0.35, flat=False, angle=50)
    collider(coll, "Counter", (0, -1.2, 1.2), (5.6, 1.6, 2.4))


def barrels(coll, seed=111):
    rnd = random.Random(seed)
    bm = bmesh.new()
    for k in range(3):
        x, y = rnd.uniform(-1.5, 1.5), rnd.uniform(-1.5, 1.5)
        geom = U.lathe(bm, [(0.0, 0.0), (0.7, 0.0), (0.85, 0.9), (0.7, 1.8), (0.0, 1.8)], 10)
        for r in geom:
            for v in r:
                v.co.x += x
                v.co.y += y
    ob = U.obj_from_bm("Barrels", bm, coll, part="wood")
    finish(ob, lambda p, n, c: IRON if abs((c.z % 0.9) - 0.45) > 0.38 else mix(WOOD_DARK, WOOD, n3(c, 0.6, seed)), reach=1.0, flat=False, angle=50)


def banner_pole(coll, cloth, seed):
    """A tall pole with a long banner: the island's colours."""
    bm = bmesh.new()
    U.box(bm, 0, 0, 7.0, 0.4, 0.4, 14.0)
    U.box(bm, 0, -0.3, 13.4, 0.25, 0.25, 0.25)
    U.lathe(bm, [(0.0, 14.0), (0.45, 14.25), (0.0, 14.8)], 6)
    pole = U.obj_from_bm("Pole", bm, coll, part="wood")
    finish(pole, lambda p, n, c: GOLD if c.z > 13.9 else mix(WOOD_DARK, WOOD, n3(c, 1, seed)), reach=1.0)
    bm = bmesh.new()
    rows = []
    for k in range(11):
        t = k / 10
        z = 13.3 - t * 7.0
        sway = math.sin(t * math.pi * 1.4) * 0.3
        rows.append([bm.verts.new((x, -0.35 - sway, z)) for x in (-1.1, 0, 1.1)])
    for a, b in zip(rows, rows[1:]):
        for i in range(2):
            bm.faces.new((a[i], b[i], b[i + 1], a[i + 1]))
    tip = bm.verts.new((0, -0.35, 5.6))
    bm.faces.new((rows[-1][0], tip, rows[-1][1]))
    bm.faces.new((rows[-1][1], tip, rows[-1][2]))
    # tagged so the camera's fader ghosts it when it hangs between the camera and the hero
    flag = U.obj_from_bm("Flag", bm, coll, part="cloth", material="Fabric", recalc=False, tag="CameraFade")
    solid = flag.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.1
    main = CLOTH[cloth]

    def colour(p, n, c):
        edge = abs(c.x) > 0.85 or c.z > 12.9
        mid = abs(c.x) < 0.25 and 8.2 < c.z < 11.6
        return GOLD if edge or mid else main

    finish(flag, colour, reach=1.0, strength=0.3, flat=False, angle=60)
    collider(coll, "Pole", (0, 0, 7), (0.5, 0.5, 14))


def flowers(coll, petal, seed):
    """A patch of little flowers (five petals and a bright heart)."""
    rnd = random.Random(seed)
    bm_s = bmesh.new()
    bm_p = bmesh.new()
    for _ in range(16):
        x, y = rnd.uniform(-2.2, 2.2), rnd.uniform(-2.2, 2.2)
        h = rnd.uniform(0.6, 1.2)
        U.box(bm_s, x, y, h / 2, 0.07, 0.07, h)
        for k in range(2):
            a = rnd.random() * math.tau
            v0 = bm_s.verts.new((x, y, 0.05))
            v1 = bm_s.verts.new((x + math.cos(a) * 0.5, y + math.sin(a) * 0.5, 0.35))
            v2 = bm_s.verts.new((x + math.cos(a + 0.5) * 0.35, y + math.sin(a + 0.5) * 0.35, 0.05))
            bm_s.faces.new((v0, v1, v2))
        tilt = Matrix.Rotation(rnd.uniform(-0.3, 0.3), 3, "X")
        centre = Vector((x, y, h))
        for k in range(5):
            a = k / 5 * math.tau + rnd.random()
            c = bm_p.verts.new(centre)
            a1 = bm_p.verts.new(centre + tilt @ Vector((math.cos(a - 0.45) * 0.32, math.sin(a - 0.45) * 0.32, 0.05)))
            a2 = bm_p.verts.new(centre + tilt @ Vector((math.cos(a) * 0.42, math.sin(a) * 0.42, 0.08)))
            a3 = bm_p.verts.new(centre + tilt @ Vector((math.cos(a + 0.45) * 0.32, math.sin(a + 0.45) * 0.32, 0.05)))
            bm_p.faces.new((c, a1, a2, a3))
        U.box(bm_p, x, y, h + 0.06, 0.16, 0.16, 0.08)
    stems = U.obj_from_bm("Stems", bm_s, coll, part="stems", recalc=False)
    finish(stems, lambda p, n, c: mix(rgb(58, 110, 46), rgb(96, 150, 62), n3(c, 0.5, seed)), reach=0.6, strength=0.25)
    petals = U.obj_from_bm("Petals", bm_p, coll, part="petals", recalc=False)
    centre_col = rgb(250, 206, 72)
    plain(petals)
    U.paint(petals, lambda p, n, c: petal if (p.xy - c.xy).length > 0.12 else centre_col)
    petals["rbx_shadow"] = False
    stems["rbx_shadow"] = False


def telescope(coll, seed=121):
    """A brass telescope on a tripod, looking out over the clouds."""
    bm = bmesh.new()
    for k in range(3):
        a = k / 3 * math.tau
        U.tube(bm, [(math.cos(a) * 1.2, math.sin(a) * 1.2, 0), (0, 0, 3.4)], 0.08, 5)
    legs = U.obj_from_bm("Tripod", bm, coll, part="wood")
    finish(legs, lambda p, n, c: WOOD_DARK, reach=0.6)
    bm = bmesh.new()
    U.tube(bm, [(0, 0.9, 3.0), (0, -0.4, 3.6)], 0.28, 10)
    U.tube(bm, [(0, -0.4, 3.6), (0, -1.6, 4.15)], 0.4, 10)
    tube_ = U.obj_from_bm("Brass", bm, coll, part="brass", material="Metal")
    finish(tube_, lambda p, n, c: mix(BRASS, rgb(240, 206, 120), max(0.0, n.z)), reach=0.6, strength=0.25, flat=False)


def railing(coll, radius, a0, a1, seed=131):
    """A curved stone balustrade (the lookout's)."""
    bm = bmesh.new()
    count = int((a1 - a0) * radius / 1.3)
    for k in range(count + 1):
        a = a0 + (a1 - a0) * k / count
        x, y = math.cos(a) * radius, math.sin(a) * radius
        U.offset(U.lathe(bm, [(0.0, 0.0), (0.32, 0.0), (0.22, 0.5), (0.36, 1.4), (0.2, 2.2), (0.32, 2.4), (0.0, 2.4)], 6), x, y)
    U.arc_block(bm, radius - 0.45, radius + 0.45, a0 - 0.02, a1 + 0.02, 2.4, 2.85, steps=max(4, count))
    ob = U.obj_from_bm("Rail", bm, coll, part="stone")
    finish(ob, stone_paint(seed, STONE, 0.8), reach=1.0)
    steps_ = 6
    for k in range(steps_):
        t0, t1 = a0 + (a1 - a0) * k / steps_, a0 + (a1 - a0) * (k + 1) / steps_
        am = (t0 + t1) / 2
        length = 2 * radius * math.sin((t1 - t0) / 2) + 0.5
        collider(coll, f"Rail{k}", (math.cos(am) * radius, math.sin(am) * radius, 1.6), (length, 0.9, 3.2), rot=(0, 0, am + math.pi / 2))


def stairs(coll, width=12.0, steps=6, rise=1.0, run=1.8, seed=141):
    """A flight of broad steps between cheek walls, climbing to the north."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    for k in range(steps):
        U.box(bm, 0, k * run + run / 2, (k + 1) * rise / 2 - 0.2, width - 0.2, run + 0.06, (k + 1) * rise + 0.4)
    for side in (-1, 1):
        x = side * (width / 2 + 0.6)
        poly = [(0.0, -0.4), (steps * run, steps * rise + 0.2), (steps * run, steps * rise + 1.0), (0.0, 0.8)]
        f = [bm.verts.new((x - 0.6, y, z)) for y, z in poly]
        b = [bm.verts.new((x + 0.6, y, z)) for y, z in poly]
        n = len(poly)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((f[i], f[j], b[j], b[i]))
        bm.faces.new(list(reversed(f)))
        bm.faces.new(b)
    ob = U.obj_from_bm("Steps", bm, coll, part="stone")
    U.bevel(ob, 0.1, 1, 35)
    finish(ob, stone_paint(seed, STONE, 0.7), reach=1.5)
    length = math.hypot(steps * run, steps * rise)
    tilt = math.atan2(steps * rise, steps * run)
    collider(coll, "Ramp", (0, steps * run / 2, steps * rise / 2 - 0.2), (width, length, 0.5), rot=(tilt, 0, 0))
    for side in (-1, 1):
        collider(coll, f"Cheek{side}", (side * (width / 2 + 0.6), steps * run / 2, steps * rise / 2 + 0.4), (1.2, length, 1.0), rot=(tilt, 0, 0))


def bunting(coll, runs, seed=151):
    """Strings of little flags between posts (the island's festival air).
    `runs` are pairs of Blender points; built in place (island coordinates)."""
    rnd = random.Random(seed)
    bm_r = bmesh.new()
    bm_f = bmesh.new()
    colours = []
    order = ["teal", "saffron", "coral", "cream", "plum", "sky"]
    for a, b in runs:
        path = U.catenary(a, b, sag=math.dist(a, b) * 0.08, n=16)
        U.tube(bm_r, path, 0.05, 4)
        length = math.dist(a, b)
        count = int(length / 1.4)
        for k in range(1, count):
            t = k / count
            p = Vector(U.catenary(a, b, math.dist(a, b) * 0.08, count)[k])
            d = (Vector(b) - Vector(a)).normalized()
            w = 0.5
            tipv = p + Vector((0, 0, -1.05)) + Vector((rnd.uniform(-0.1, 0.1), rnd.uniform(-0.1, 0.1), 0))
            # both sides of the flag (its own corners for each, as bmesh wants)
            for side_ in ((0, 1), (1, 0)):
                corners = (p - d * w, p + d * w)
                bm_f.faces.new((bm_f.verts.new(corners[side_[0]]), bm_f.verts.new(corners[side_[1]]), bm_f.verts.new(tipv)))
            colours.append(CLOTH[order[(k + rnd.randint(0, 2)) % len(order)]])
    rope = U.obj_from_bm("Rope", bm_r, coll, part="rope")
    plain(rope)
    U.paint(rope, lambda p, n, c: rgb(120, 96, 70))
    flags = U.obj_from_bm("Flags", bm_f, coll, part="cloth", material="Fabric", recalc=False)
    plain(flags, flat=True)
    me = flags.data
    attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    for poly in me.polygons:
        col = colours[poly.index // 2 % len(colours)] if colours else CLOTH["teal"]
        for li in poly.loop_indices:
            attr.data[li].color_srgb = (col[0], col[1], col[2], 1.0)
    flags["rbx_shadow"] = False


def bridge(coll, a, b, width=4.6, seed=161):
    """A rope bridge of planks between two points (island coordinates)."""
    rnd = random.Random(seed)
    a, b = Vector(a), Vector(b)
    d = b - a
    flat = Vector((d.x, d.y, 0)).normalized()
    side = Vector((-flat.y, flat.x, 0))
    length = d.length
    sag = 2.0
    n = int(length / 1.15)
    path = [Vector(p) for p in U.catenary(a, b, sag, n)]
    bm = bmesh.new()
    for k in range(n):
        p = (path[k] + path[k + 1]) / 2
        yaw = math.atan2(flat.y, flat.x)
        U.box(bm, p.x, p.y, p.z - 0.12, 0.95, width + rnd.uniform(-0.2, 0.2), 0.24, rot=yaw + rnd.uniform(-0.04, 0.04))
    for end in (a, b):
        for s in (-1, 1):
            q = end + side * s * (width / 2 + 0.3)
            U.box(bm, q.x, q.y, q.z + 1.6, 0.5, 0.5, 4.2)
    planks = U.obj_from_bm("Planks", bm, coll, part="wood")
    finish(planks, lambda p, n, c: mix(WOOD_DARK, WOOD, 0.3 + 0.7 * n3(c, 0.8, seed)), reach=1.0)
    bm = bmesh.new()
    for s in (-1, 1):
        rail = [Vector(p) + side * s * (width / 2 + 0.2) + Vector((0, 0, 2.8)) for p in U.catenary(a, b, sag * 0.7, 24)]
        U.tube(bm, [tuple(p) for p in rail], 0.09, 5)
        for k in range(0, len(path), 3):
            top = Vector(U.catenary(a, b, sag * 0.7, len(path) - 1)[k]) + side * s * (width / 2 + 0.2) + Vector((0, 0, 2.8))
            U.tube(bm, [tuple(path[k] + side * s * (width / 2 + 0.2)), tuple(top)], 0.05, 4)
    ropes = U.obj_from_bm("Ropes", bm, coll, part="rope")
    plain(ropes)
    U.paint(ropes, lambda p, n, c: rgb(150, 122, 84))
    # colliders: the deck in segments, and a waist-high wall each side
    segs = 8
    for k in range(segs):
        p0, p1 = Vector(U.catenary(a, b, sag, segs)[k]), Vector(U.catenary(a, b, sag, segs)[k + 1])
        mid = (p0 + p1) / 2
        seg = p1 - p0
        yaw = math.atan2(seg.y, seg.x)
        pitch = math.atan2(seg.z, Vector((seg.x, seg.y, 0)).length)
        rot = (Matrix.Rotation(yaw, 3, "Z") @ Matrix.Rotation(-pitch, 3, "Y")).to_euler()
        collider(coll, f"Deck{k}", (mid.x, mid.y, mid.z - 0.2), (seg.length + 0.3, width, 0.4), rot=tuple(rot))
        for s in (-1, 1):
            q = mid + side * s * (width / 2 + 0.3)
            collider(coll, f"Side{k}{s}", (q.x, q.y, q.z + 2.0), (seg.length + 0.3, 0.4, 4.0), rot=tuple(rot))

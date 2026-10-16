"""The Wardwood environment kit (M3.B): every asset as a seeded recipe.

Sizes are studs at scale 1 and match the props they stand in for (the
part-built blueprints and the mesh props measured in the game), so a showcase
can swap one for the other in place: same footprint, same collider.

    Broadleaf  Oak, OakLeaning, Beech, Birch, Sapling
    Conifers   Spruce, Pine
    Landmark   AncientOak
    Ground     GrassA, GrassB, GrassC (low 3D grass patches)
    Stone      BoulderLarge, RockSmall, BoulderFlat, Pillar, PillarBroken
"""

from __future__ import annotations

import math
import random

from geo import (Asset, add, banded_blob, blob, card, cross, dot, fbm, lerp, length, mul, norm, perp, rot_vec,
                 rot_z, sample_ellipsoid, smooth, sub, sun_light, tube)

# ------------------------------------------------------------------ palette
# One warm, sunlit palette for the whole kit: greens lean yellow in the light
# and blue-green in the shade, bark and stone stay warm, nothing pure grey.

PAL = {
    "bark": (104, 78, 58),
    "barkDark": (82, 62, 48),
    "barkAncient": (96, 76, 60),
    "barkPine": (132, 88, 62),
    "barkBirch": (226, 220, 202),
    "birchMark": (62, 58, 52),
    "leafDark": (46, 92, 44),
    "leafMid": (78, 126, 48),
    "leafLight": (118, 160, 58),
    "beechDark": (56, 98, 42),
    "beechMid": (98, 142, 52),
    "beechLight": (132, 168, 62),
    "birchDark": (88, 128, 52),
    "birchMid": (132, 168, 66),
    "birchLight": (156, 184, 74),
    "ancientDark": (40, 84, 44),
    "ancientMid": (74, 124, 50),
    "ancientLight": (114, 156, 56),
    "ancientGold": (156, 180, 70),
    "spruceDark": (30, 68, 50),
    "spruceMid": (50, 102, 62),
    "spruceLight": (88, 138, 76),
    "pineDark": (44, 86, 50),
    "pineMid": (66, 112, 56),
    "pineLight": (102, 142, 64),
    "moss": (92, 130, 52),
    "stone": (168, 160, 142),
    "stoneDark": (128, 122, 110),
    "rock": (136, 130, 118),
    "rockDark": (110, 106, 98),
    "mossRock": (74, 108, 44),
    "grassA": (122, 170, 62),
    "grassB": (130, 176, 66),
    "grassC": (114, 162, 58),
}

# ------------------------------------------------------------------ canopy


def canopy(parts, bands, spots, centre, rng, leaf, density, seed, subdiv=2, tilt=(0.12, 0.5)):
    """Leaf masses: each a lumpy core painted in light bands, fringed with
    leaves that lie along its surface and overlap its edge, so the crown reads
    as soft, layered foliage with a ragged leafy outline, not as balls."""
    top = max(p[2] + r for p, r in spots)
    bottom = min(p[2] - r for p, r in spots)

    def light(n, q):
        return sun_light(n, (q[2] - bottom) / max(top - bottom, 1))

    def pick(lit, n):
        if n[2] < -0.45:
            return parts[0]
        k = 0
        while k < len(bands) and lit >= bands[k]:
            k += 1
        return parts[k]

    for ci, (p, r) in enumerate(spots):
        banded_blob(parts, bands, p, (r * 0.9, r * 0.9, r * 0.82), light, subdiv=subdiv, lump=0.22,
                    seed=seed + ci, shade_center=centre)
        for _ in range(int(density * r * r)):
            v, d = sample_ellipsoid(rng, (r, r, r * 0.88))
            if d[2] < -0.5 and rng.random() < 0.75:
                continue  # few leaves on the belly: the shaded core shows there
            q = add(p, mul(v, rng.uniform(1.0, 1.16)))
            shade = norm(lerp(d, norm(sub(q, centre)), 0.5))
            lit = light(shade, q) + rng.uniform(-0.09, 0.09)
            card(pick(lit, shade), q, d, leaf * rng.uniform(0.75, 1.25), rng, shade, fold=0.3, tilt=tilt)


def crown_spots(rng, centre, crown_r, crown_h, clump_r, clumps, low=-0.55):
    """Leaf-mass centres over a dome: one summit, then lobes spread over the
    upper and outer envelope, kept apart, so the outline is lumpy and layered."""
    rx = crown_r - clump_r * 0.75
    rz = max(crown_h * 0.5 - clump_r * 0.6, 0.6)
    spots = [(add(centre, (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rz)), clump_r * 1.05)]
    tries = 0
    while len(spots) < clumps and tries < 6000:
        tries += 1
        v, d = sample_ellipsoid(rng, (rx, rx, rz))
        if d[2] < low:
            continue
        p = add(centre, mul(v, rng.uniform(0.55, 1.0)))
        if all(length(sub(p, q)) > clump_r * 0.95 for q, _ in spots):
            spots.append((p, clump_r * rng.uniform(0.8, 1.15)))
    return spots


# ------------------------------------------------------------------ broadleaf


def broadleaf(name, seed, *, height, crown_r, crown_h, trunk_h, trunk_r, lean=(0.0, 0.0), clumps=9,
              clump_r=4.2, leaf=2.1, density=5.4, limbs=4, pal=("leafDark", "leafMid", "leafLight"),
              bark="bark", birch=False, roots=5):
    """A stylized broadleaf: a flared, slightly bent trunk forks into limbs that
    reach out to clumps of folded leaves around dark cores. Clumps sit on the
    crown's envelope, so the silhouette is a ragged dome of lobes, never a ball."""
    rng = random.Random(seed)
    a = Asset(name)
    barkp = a.part("bark", PAL[bark])
    dark = a.part("leafDark", PAL[pal[0]])
    mid = a.part("leafMid", PAL[pal[1]])
    light = a.part("leafLight", PAL[pal[2]])
    marks = a.part("barkMark", PAL["birchMark"]) if birch else None

    fork = (lean[0], lean[1], trunk_h)
    # trunk: an S-bend from a flared foot
    path, radii = [], []
    n = 6
    for i in range(n + 1):
        t = i / n
        bend = math.sin(t * math.pi) * 0.25 * trunk_r
        p = (lean[0] * t ** 1.3 + bend, lean[1] * t ** 1.3 - bend * 0.5, -0.8 + (trunk_h + 0.8) * t)
        path.append(p)
        radii.append(trunk_r * (1.0 - 0.32 * t))

    def flare(i, ang):
        if i > 1:
            return 1.0
        k = (1.0 if i == 0 else 0.45)
        return 1 + k * 0.55 * max(0.0, math.cos(ang * roots + seed)) ** 2

    tube(barkp, path, radii, sides=8, lobes=flare, seed=seed, cap=False)
    if birch:
        for k in range(9):
            z = rng.uniform(1.0, trunk_h * 0.95)
            ang = rng.uniform(0, math.tau)
            t = z / trunk_h
            r = trunk_r * (1 - 0.32 * t) * 1.02
            c = add((lean[0] * t ** 1.3, lean[1] * t ** 1.3, z), (math.cos(ang) * r, math.sin(ang) * r, 0))
            blob(marks, c, (0.26 * trunk_r * 2, 0.26 * trunk_r * 2, 0.12), subdiv=0, lump=0.1, seed=seed + k)

    centre = (lean[0] * 1.15, lean[1] * 1.15, height - crown_h * 0.5)
    spots = crown_spots(rng, centre, crown_r, crown_h, clump_r, clumps)

    # limbs: clumps grouped by bearing, one limb per group, a twig per clump
    order = sorted(spots, key=lambda s: math.atan2(s[0][1] - centre[1], s[0][0] - centre[0]))
    groups = [order[i::limbs] for i in range(limbs)]
    for gi, group in enumerate(groups):
        if not group:
            continue
        tgt = tuple(sum(g[0][i] for g in group) / len(group) for i in range(3))
        start = add(fork, (0, 0, -trunk_h * 0.12 * (gi % 2)))
        end = lerp(start, tgt, 0.72)
        end = add(end, (0, 0, 0.6))
        mid_pt = add(lerp(start, end, 0.5), (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0.9))
        lp = [start, lerp(start, mid_pt, 0.5), mid_pt, lerp(mid_pt, end, 0.5), end]
        lr = [radii[-1] * 0.78, radii[-1] * 0.66, radii[-1] * 0.54, radii[-1] * 0.44, radii[-1] * 0.34]
        tube(barkp, lp, lr, sides=6, seed=seed + gi)
        for (p, r) in group:
            s = lerp(start, end, rng.uniform(0.55, 0.95))
            e = lerp(s, p, 0.82)
            m = add(lerp(s, e, 0.5), (0, 0, 0.4))
            tube(barkp, [s, m, e], [lr[-1] * 0.85, lr[-1] * 0.6, lr[-1] * 0.32], sides=5, seed=seed + 31)

    canopy((dark, mid, light), (0.5, 0.68), spots, centre, rng, leaf, density, seed,
           subdiv=2 if clump_r > 3 else 1)
    return a


def ancient_oak(seed=11):
    """The landmark: a gnarled ancient with buttress roots, a twisted trunk, great
    limbs and a sprawling crown of big leaf masses, moss on its upper sides."""
    rng = random.Random(seed)
    a = Asset("AncientOak")
    barkp = a.part("bark", PAL["barkAncient"])
    dark = a.part("leafDark", PAL["ancientDark"])
    mid = a.part("leafMid", PAL["ancientMid"])
    light = a.part("leafLight", PAL["ancientLight"])
    gold = a.part("leafGold", PAL["ancientGold"])

    trunk_h, r0 = 26.0, 7.6
    path, radii = [], []
    for i in range(9):
        t = i / 8
        path.append((math.sin(t * 2.2) * 1.4, math.cos(t * 1.7) * 1.0 - 1.0, -2.0 + (trunk_h + 2.0) * t))
        radii.append(r0 * (1.0 - 0.28 * t))

    def gnarl(i, ang):
        twist = ang + i * 0.5
        return 1 + 0.16 * math.cos(twist * 5) + 0.08 * math.cos(twist * 3 + 1) + (0.35 if i == 0 else 0.0)

    tube(barkp, path, radii, sides=14, lobes=gnarl, seed=seed, cap=False)
    # buttress roots: out of the trunk, down and away into the ground
    nroots = 7
    for k in range(nroots):
        ang = k / nroots * math.tau + rng.uniform(-0.2, 0.2)
        d = (math.cos(ang), math.sin(ang), 0)
        reach = rng.uniform(13, 21)
        start = add(mul(d, r0 * 0.55), (0, 0, rng.uniform(5, 8)))
        pts, rr = [], []
        for i in range(6):
            t = i / 5
            out = r0 * 0.55 + reach * t
            z = start[2] * (1 - t) ** 1.6 - 0.9 * t
            side = math.sin(t * 3 + k) * 1.2
            pts.append(add(add(mul(d, out), mul((-d[1], d[0], 0), side)), (0, 0, z)))
            rr.append(rng.uniform(2.6, 3.2) * (1 - t) ** 0.8 + 0.35)
        tube(barkp, pts, rr, sides=8, seed=seed + k)

    # the crown: a broad dome of great leaf masses, and the limbs that carry them
    centre = (0.0, -1.0, 60.0)
    spots = crown_spots(rng, centre, 34.0, 44.0, 9.5, 28, low=-0.5)
    order = sorted(spots, key=lambda s: math.atan2(s[0][1] - centre[1], s[0][0] - centre[0]))
    nl = 6
    for k in range(nl):
        group = order[k::nl]
        if not group:
            continue
        tgt = tuple(sum(g[0][i] for g in group) / len(group) for i in range(3))
        start = add(path[-1], (0, 0, rng.uniform(-6, 0)))
        end = lerp(start, tgt, 0.8)
        knee = add(lerp(start, end, 0.45), (rng.uniform(-2, 2), rng.uniform(-2, 2), -3.0))
        pts = [start, lerp(start, knee, 0.5), knee, lerp(knee, end, 0.5), end]
        rr = [radii[-1] * 0.72, radii[-1] * 0.6, radii[-1] * 0.48, radii[-1] * 0.36, radii[-1] * 0.24]
        tube(barkp, pts, rr, sides=9, seed=seed + 40 + k)
        for ci, (p, r) in enumerate(group):
            s = lerp(knee, end, rng.uniform(0.2, 1.0))
            e = lerp(s, p, 0.75)
            tube(barkp, [s, add(lerp(s, e, 0.5), (0, 0, 1.5)), e], [2.0, 1.3, 0.6], sides=6, seed=seed + 90 + ci)
    canopy((dark, mid, light, gold), (0.5, 0.66, 0.8), spots, centre, rng, 3.2, 0.85, seed + 200)
    return a


# ------------------------------------------------------------------ conifers


def spruce(seed=21, height=32.5, base_r=10.0):
    """A spruce: whorls of drooping, saw-toothed fronds, longer and more ragged
    low down, around a dark heart, a leader spike on top. Lengths and bearings
    jitter so the tiers read as boughs, not a stack of cones."""
    rng = random.Random(seed)
    a = Asset("Spruce")
    barkp = a.part("bark", PAL["barkDark"])
    dark = a.part("needleDark", PAL["spruceDark"])
    mid = a.part("needleMid", PAL["spruceMid"])
    light = a.part("needleLight", PAL["spruceLight"])
    tube(barkp, [(0, 0, -0.8), (0, 0, 6), (0.1, 0, 16), (0, 0.1, height - 1)], [0.95, 0.8, 0.55, 0.15], sides=7, seed=seed)
    z0, z1 = 2.6, height - 1.2
    # dark heart, so there is no daylight through the middle
    heart_pts = [(0, 0, z0 + (z1 - z0) * t) for t in (0, 0.25, 0.5, 0.75, 1.0)]
    heart_r = [base_r * 0.3 * (1 - t) ** 1.05 + 0.2 for t in (0, 0.25, 0.5, 0.75, 1.0)]
    tube(dark, heart_pts, heart_r, sides=8, seed=seed, cap=True)
    z = z0
    level = 0
    while z < z1:
        t = (z - z0) / (z1 - z0)
        # every tier its own length, so the outline steps in and out like boughs
        tier = rng.uniform(0.78, 1.12)
        reach = (base_r * (1 - t) ** 0.95 + 0.8) * tier
        nf = 8 if t < 0.55 else (6 if t < 0.8 else 4)
        off = rng.uniform(0, math.tau)
        for k in range(nf):
            if t < 0.7 and rng.random() < 0.12:
                continue
            ang = off + k / nf * math.tau + rng.uniform(-0.3, 0.3)
            L = reach * rng.uniform(0.8, 1.1)
            frond(a, (dark, mid, light), rng, (0, 0, z + rng.uniform(-0.2, 0.2)), ang, L, t,
                  droop=0.55 + 0.3 * (1 - t), wide=0.3)
            if t < 0.85:
                # a shorter bough between, a little higher: fills the tier
                frond(a, (dark, mid, light), rng, (0, 0, z + 0.45), ang + math.pi / nf, L * 0.62, t,
                      droop=0.4 + 0.2 * (1 - t), wide=0.28)
        level += 1
        z += rng.uniform(1.7, 2.4) * (1 - 0.4 * t)
    # leader
    frond(a, (dark, mid, light), rng, (0, 0, z1 - 0.6), 0, 2.2, 1.0, droop=-6.0)
    return a


def frond(a, parts, rng, root, ang, L, t, droop=0.5, segs=5, wide=0.26):
    """A spruce bough as a broad drooping pad: widest near its middle, folded
    down from the midrib like a shallow umbrella, its edge lightly toothed,
    darker at the trunk and lighter toward the sunlit tip."""
    dark, mid, light = parts
    leader = droop < -1
    d = (math.cos(ang), math.sin(ang), 0.0)
    side = norm((-d[1], d[0], 0)) if not leader else (1.0, 0.0, 0.0)
    width = max(0.7, min(3.0, L * wide))
    rows = []
    for i in range(segs + 1):
        s = i / segs
        if leader:
            m = add(root, (0, 0, L * s))
        else:
            m = add(root, (d[0] * L * s, d[1] * L * s, (0.3 * s - droop * s * s) * L * 0.55))
        w = width * (math.sin(math.pi * min(s * 1.15, 1.0)) ** 0.6) * (1.0 if i % 2 == 0 else 0.82)
        if i == 0:
            w = width * 0.2
        fold = 0.32 * w
        left = add(add(m, mul(side, w)), (0, 0, -fold))
        right = add(add(m, mul(side, -w)), (0, 0, -fold))
        rows.append((m, left, right, s))
    for i in range(segs):
        m0, l0, r0, s0 = rows[i]
        m1, l1, r1, s1 = rows[i + 1]
        along = norm(sub(m1, m0))
        up = norm(cross(side, along))
        if up[2] < 0:
            up = mul(up, -1)
        out = norm((m1[0] - root[0] + 1e-3, m1[1] - root[1], 0.0))
        shade = norm(add(mul(up, 0.8), mul(out, 0.5)))
        lit = 0.4 * s1 + 0.45 * t + 0.2 * shade[2] + rng.uniform(-0.08, 0.08)
        part = dark if lit < 0.42 else (mid if lit < 0.7 else light)
        for quad in ((l0, m0, m1, l1), (m0, r0, r1, m1)):
            ids = [part.vert(q) for q in quad]
            part.tri(ids[0], ids[1], ids[2], shade, shade, shade)
            part.tri(ids[0], ids[2], ids[3], shade, shade, shade)
            part.tri(ids[0], ids[2], ids[1], shade, shade, shade)
            part.tri(ids[0], ids[3], ids[2], shade, shade, shade)


def pine(seed=31, height=33.0):
    """A Scots pine: a tall, bare, warm-barked trunk that bends a little, boughs
    only in the top third, each ending in a flat cloud of needle tufts."""
    rng = random.Random(seed)
    a = Asset("Pine")
    barkp = a.part("bark", PAL["barkPine"])
    dark = a.part("needleDark", PAL["pineDark"])
    mid = a.part("needleMid", PAL["pineMid"])
    light = a.part("needleLight", PAL["pineLight"])
    trunk = [(0, 0, -0.8), (0.3, 0, 8), (0.9, 0.3, 16), (1.4, 0.4, 23), (1.2, 0.6, height - 4)]
    tube(barkp, trunk, [1.0, 0.85, 0.7, 0.55, 0.3], sides=7, seed=seed)
    puffs = []
    for k in range(9):
        t = rng.uniform(0.0, 1.0)
        z = 20 + t * (height - 25)
        base = (1.0 + 0.4 * t, 0.3 + 0.3 * t, z)
        ang = k * 2.4 + rng.uniform(-0.3, 0.3)
        reach = (7.5 - 4.5 * t) * rng.uniform(0.8, 1.15)
        end = add(base, (math.cos(ang) * reach, math.sin(ang) * reach, rng.uniform(1.5, 3.5)))
        midp = add(lerp(base, end, 0.5), (0, 0, -0.6))
        tube(barkp, [base, midp, end], [0.42, 0.3, 0.16], sides=5, seed=seed + k)
        puffs.append((add(end, (0, 0, 0.4)), rng.uniform(2.6, 3.6)))
    puffs.append(((1.3, 0.6, height - 2.4), 3.0))
    centre = (1.0, 0.5, height - 6)
    top = height
    for ci, (p, r) in enumerate(puffs):
        blob(dark, p, (r * 0.85, r * 0.85, r * 0.38), subdiv=1, lump=0.2, seed=seed + ci, shade_center=centre)
        for _ in range(int(9.5 * r * r)):
            v, d = sample_ellipsoid(rng, (r, r, r * 0.45))
            if d[2] < -0.3 and rng.random() < 0.7:
                continue
            q = add(p, v)
            shade = norm(lerp(d, norm(sub(q, centre)), 0.45))
            out = norm(add(d, (0, 0, 0.6)))
            lit = sun_light(shade, (q[2] - (height - 15)) / 15) + rng.uniform(-0.1, 0.1)
            part = dark if (lit < 0.48 or shade[2] < -0.2) else (mid if lit < 0.68 else light)
            card(part, q, out, rng.uniform(1.5, 2.1), rng, shade, fold=0.05, aspect=0.22)
    return a


# ------------------------------------------------------------------ grass


def grass_patch(name, seed, color_key, blades=330, radius=3.4):
    """Low 3D grass: thin blades 0.2 to 0.5 studs above the ground, thinning
    to a soft edge so overlapping patches read as one continuous lawn. Blades
    come in three tones and their normals lean toward the way each one faces,
    so the sun catches some and not others: the ground gets a fine living
    texture without anything standing tall. Each blade starts 0.2 studs under
    the surface, so voxel terrain a little off the heightfield never leaves
    one floating or swallows it."""
    rng = random.Random(seed)
    a = Asset(name)
    base_col = PAL[color_key]

    def tone(k):
        return tuple(max(0, min(255, round(c * k))) for c in base_col)

    parts = (a.part("bladesDark", tone(0.76)), a.part("bladesMid", base_col), a.part("bladesLight", tone(1.13)))
    n = 0
    while n < blades:
        r = radius * math.sqrt(rng.random())
        if rng.random() > 1 - smooth((r - radius * 0.55) / (radius * 0.45)):
            continue
        ang = rng.uniform(0, math.tau)
        x, y = math.cos(ang) * r, math.sin(ang) * r
        h = 0.2 + 0.3 * rng.random() ** 1.5
        w = rng.uniform(0.1, 0.16)
        face = rng.uniform(0, math.tau)
        side = (math.cos(face) * w * 0.5, math.sin(face) * w * 0.5, 0)
        facing = (-math.sin(face), math.cos(face), 0)
        lean = rng.uniform(0.1, 0.45) * h
        la = rng.uniform(0, math.tau)
        base = (x, y, -0.2)
        tip = (x + math.cos(la) * lean, y + math.sin(la) * lean, h)
        nrm = norm(add(add((0, 0, 0.62), mul(facing, 0.55)), (math.cos(la) * 0.12, math.sin(la) * 0.12, 0)))
        roll = rng.random()
        g = parts[0] if roll < 0.3 else (parts[1] if roll < 0.8 else parts[2])
        i0, i1, i2 = g.vert(sub(base, side)), g.vert(add(base, side)), g.vert(tip)
        g.tri(i0, i1, i2, nrm, nrm, nrm)
        g.tri(i1, i0, i2, nrm, nrm, nrm)
        n += 1
    return a


# ------------------------------------------------------------------ stone


def rock(name, seed, radii, sink=0.25, moss_amount=0.5, subdiv=2):
    """A chunky stylized rock: broad facets, a flattened seat, moss on its back."""
    rng = random.Random(seed)
    a = Asset(name)
    st = a.part("stone", PAL["rock"])
    sd = a.part("stoneDark", PAL["rockDark"])
    moss = a.part("moss", PAL["mossRock"])
    from geo import icosphere
    verts, faces = icosphere(subdiv)
    pts = []
    for v in verts:
        n = 1 + 0.32 * (fbm(mul(v, 1.3), seed) - 0.5) * 2 + 0.12 * (fbm(mul(v, 3.1), seed + 3) - 0.5)
        p = (v[0] * radii[0] * n, v[1] * radii[1] * n, v[2] * radii[2] * n)
        # flat-ish top planes and a cut seat: the stylized boulder look
        if p[2] > radii[2] * 0.7:
            p = (p[0], p[1], radii[2] * 0.7 + (p[2] - radii[2] * 0.7) * 0.55)
        p = (p[0], p[1], max(p[2], -radii[2] * sink))
        pts.append(add(p, (0, 0, radii[2] * sink)))
    vn = [(0.0, 0.0, 0.0)] * len(pts)
    fn = []
    for f in faces:
        n = norm(cross(sub(pts[f[1]], pts[f[0]]), sub(pts[f[2]], pts[f[0]])))
        fn.append(n)
        for i in f:
            vn[i] = add(vn[i], n)
    vn = [norm(v) for v in vn]
    # moss grows where a vertex faces up, broken by noise: whole caps, not specks
    mossiness = [vn[i][2] * 0.75 + 0.5 * (fbm(mul(pts[i], 0.6), seed + 9) - 0.5) for i in range(len(pts))]
    mossy = set()
    for fi, f in enumerate(faces):
        n = fn[fi]
        c = mul(add(add(pts[f[0]], pts[f[1]]), pts[f[2]]), 1 / 3)
        part = sd if fbm(mul(c, 0.9), seed + 4) > 0.58 else st
        ids = [part.vert(pts[i]) for i in f]
        part.tri_flat(*ids)
        if all(mossiness[i] > 1 - moss_amount for i in f):
            mossy.add(fi)
    # moss: one continuous raised pad over the mossy faces, softly shaded
    thick = 0.06 + 0.03 * max(radii)
    mv = {}
    for fi in mossy:
        f = faces[fi]
        j = []
        for i in f:
            if i not in mv:
                mv[i] = moss.vert(add(pts[i], mul(vn[i], thick)))
            j.append(mv[i])
        ns = [norm(add(vn[i], (0, 0, 0.7))) for i in f]
        moss.tri(j[0], j[1], j[2], ns[0], ns[1], ns[2])
    return a


def fluted_ring(part, z, r_out, r_in, flutes, jitter, rng, height, cap_top=True, broken=None):
    """One column drum: a fluted cylinder, faceted per flute, optionally broken."""
    n = flutes * 2
    base, topr = [], []
    for k in range(n):
        ang = k / n * math.tau
        r = r_out if k % 2 == 0 else r_in
        c, s = math.cos(ang), math.sin(ang)
        dz = 0.0
        if broken is not None:
            dz = -broken * (0.2 + 0.8 * rng.random()) if rng.random() < 0.7 else -broken * 0.1
        base.append((c * r + jitter[0], s * r + jitter[1], z))
        topr.append((c * r * 0.98 + jitter[0], s * r * 0.98 + jitter[1], z + height + dz))
    bi = [part.vert(p) for p in base]
    ti = [part.vert(p) for p in topr]
    for k in range(n):
        k2 = (k + 1) % n
        part.tri_flat(bi[k], bi[k2], ti[k2])
        part.tri_flat(bi[k], ti[k2], ti[k])
    if cap_top:
        c = part.vert((jitter[0], jitter[1], z + height + (-(broken or 0) * 0.5)))
        for k in range(n):
            part.tri_flat(ti[k], ti[(k + 1) % n], c)
    return topr


def box(part, lo, hi):
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    v = [part.vert(p) for p in [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                 (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]]
    for f in [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4),
              (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)]:
        part.tri_flat(v[f[0]], v[f[1]], v[f[2]])


def moss_cap(moss, rng, centre, r, z, seed, coverage=0.7):
    """A ragged pad of moss lying on a flat top."""
    pts = []
    n = 10
    for k in range(n):
        ang = k / n * math.tau
        rr = r * (0.55 + 0.45 * fbm((math.cos(ang) * 2, math.sin(ang) * 2, seed), seed)) * coverage
        pts.append((centre[0] + math.cos(ang) * rr, centre[1] + math.sin(ang) * rr, z + 0.04))
    c = moss.vert((centre[0], centre[1], z + 0.07))
    ids = [moss.vert(p) for p in pts]
    up = (0, 0, 1)
    for k in range(n):
        moss.tri(c, ids[k], ids[(k + 1) % n], up, up, up)


def pillar(name="Pillar", seed=41, broken=False):
    """A weathered fluted column on a plinth, capital on top, moss in its ledges;
    the broken one snaps off two drums up, its third drum fallen beside it."""
    rng = random.Random(seed)
    a = Asset(name)
    st = a.part("stone", PAL["stone"])
    dk = a.part("stoneDark", PAL["stoneDark"])
    moss = a.part("moss", PAL["moss"])
    box(dk, (-2.35, -2.35, -0.6), (2.35, 2.35, 0.9))
    box(st, (-2.0, -2.0, 0.9), (2.0, 2.0, 1.5))
    moss_cap(moss, rng, (0.6, -0.4, 0), 2.1, 0.9, seed)
    z = 1.5
    drums = 2 if broken else 4
    for i in range(drums):
        j = (rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06))
        last = broken and i == drums - 1
        fluted_ring(st, z, 1.75, 1.55, 10, j, rng, 4.05, broken=(1.6 if last else None))
        z += 4.1
    if not broken:
        fluted_ring(dk, z, 1.85, 1.85, 8, (0, 0), rng, 0.5)
        box(st, (-2.4, -2.4, z + 0.5), (2.4, 2.4, z + 1.3))
        moss_cap(moss, rng, (-0.3, 0.5, 0), 2.3, z + 1.3, seed + 1, coverage=0.8)
    else:
        moss_cap(moss, rng, (0, 0, 0), 1.6, z - 1.4, seed + 2, coverage=0.6)
        # the fallen drum, on its side beside the column
        fd = a.part("stone", PAL["stone"])
        tmp = Asset("tmp")
        tp = tmp.part("s", (0, 0, 0))
        fluted_ring(tp, -2.0, 1.75, 1.55, 10, (0, 0), rng, 4.0)
        ang = rng.uniform(0.2, 0.6)
        for tri, nr in zip(tp.tris, tp.nrm):
            ids = []
            for vi in tri:
                x, y, zz = tp.pos[vi]
                # lay it down along +x, and push it out beside the column
                p = (zz + 5.2, y, x + 1.5)
                p = rot_z(p, ang)
                ids.append(fd.vert(p))
            fd.tri_flat(*ids)
        for k in range(4):
            ang2 = rng.uniform(0, math.tau)
            d = rng.uniform(2.6, 4.2)
            blob(dk, (math.cos(ang2) * d, math.sin(ang2) * d, 0.15), (rng.uniform(0.4, 0.7), rng.uniform(0.35, 0.6), 0.32),
                 subdiv=0, lump=0.3, seed=seed + k, flat=True)
    return a


# ------------------------------------------------------------------ the kit


def fit(asset, size):
    """Scale an asset so its box is exactly `size` (x, y, z studs), seat on z=0
    kept: rocks are sized to the props they replace in the game."""
    lo, hi = asset.bounds()
    k = [size[i] / max(hi[i] - lo[i], 1e-6) for i in range(3)]
    for p in asset.parts.values():
        p.pos = [(v[0] * k[0], v[1] * k[1], v[2] * k[2]) for v in p.pos]
        fixed = []
        for tri, nr in zip(p.tris, p.nrm):
            fixed.append(tuple(norm((n[0] / k[0], n[1] / k[1], n[2] / k[2])) for n in nr))
        p.nrm = fixed
    return asset


def build_all():
    kit = []
    kit.append(broadleaf("Oak", 101, height=17.0, crown_r=10.8, crown_h=12.8, trunk_h=5.0, trunk_r=1.35, clumps=14,
                         clump_r=3.8, leaf=1.5, density=4.6, limbs=4))
    kit.append(broadleaf("OakLeaning", 103, height=17.0, crown_r=11.0, crown_h=12.0, trunk_h=5.4, trunk_r=1.35,
                         lean=(2.4, 0.4), clumps=13, clump_r=3.8, leaf=1.5, density=4.6, limbs=3))
    kit.append(broadleaf("Beech", 107, height=18.0, crown_r=8.2, crown_h=14.0, trunk_h=5.2, trunk_r=1.1, clumps=13,
                         clump_r=3.2, leaf=1.35, density=4.8, limbs=4, pal=("beechDark", "beechMid", "beechLight")))
    kit.append(broadleaf("Birch", 109, height=24.5, crown_r=5.4, crown_h=15.0, trunk_h=9.5, trunk_r=0.62, clumps=12,
                         clump_r=2.4, leaf=1.05, density=5.2, limbs=4, pal=("birchDark", "birchMid", "birchLight"),
                         bark="barkBirch", birch=True, roots=3))
    kit.append(broadleaf("Sapling", 113, height=9.6, crown_r=3.6, crown_h=6.5, trunk_h=3.0, trunk_r=0.34, clumps=6,
                         clump_r=1.7, leaf=0.95, density=5.5, limbs=2, roots=3))
    kit.append(spruce())
    kit.append(pine())
    kit.append(ancient_oak())
    kit.append(grass_patch("GrassA", 201, "grassA"))
    kit.append(grass_patch("GrassB", 203, "grassB"))
    kit.append(grass_patch("GrassC", 205, "grassC"))
    kit.append(fit(rock("BoulderLarge", 301, (4.4, 4.5, 2.9), sink=0.18, moss_amount=0.6), (8.8, 9.0, 4.6)))
    kit.append(fit(rock("RockSmall", 303, (0.95, 0.9, 1.15), sink=0.15, moss_amount=0.45, subdiv=1), (1.8, 1.8, 2.0)))
    kit.append(fit(rock("BoulderFlat", 305, (1.35, 1.3, 1.25), sink=0.12, moss_amount=0.5, subdiv=1), (2.6, 2.4, 1.6)))
    kit.append(pillar("Pillar", 401, broken=False))
    kit.append(pillar("PillarBroken", 403, broken=True))
    return kit

"""The Wardwood environment kit (M3.B): every asset as a seeded recipe.

Sizes are studs at scale 1 and match the props they stand in for (the
part-built blueprints and the mesh props measured in the game), so the game
swaps one for the other in place: same footprint, same collider.

    Broadleaf  Oak, OakLeaning, Beech, Birch, Sapling (variants, _LOD, _FAR)
    Conifers   Spruce, Pine (variants, _LOD, _FAR)
    Landmarks  AncientOak, AncientPine, Elder, FallenGiant
    Woodland   Bush, Fern, Stump, FallenLog
    Stone      BoulderLarge, RockSmall, BoulderFlat, Menhir, Pillar, PillarBroken, RuinWall

Grass is not in the kit: option B's blades stand on the terrain, so they are
grown per chunk in the game (src/shared/Core/GrassField.luau).
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
    "bushDark": (42, 86, 44),
    "bushMid": (70, 118, 48),
    "bushLight": (108, 150, 56),
    "fernDark": (50, 100, 48),
    "fernMid": (76, 130, 56),
    "fernLight": (110, 158, 64),
    "wood": (176, 140, 96),
    "earth": (92, 74, 54),
    "elderDark": (36, 84, 62),
    "elderMid": (64, 124, 82),
    "elderLight": (108, 164, 96),
    "elderGold": (170, 204, 120),
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
              bark="bark", birch=False, roots=5, bend=0.25, lod=False):
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
        bend_ = math.sin(t * math.pi) * bend * trunk_r
        p = (lean[0] * t ** 1.3 + bend_, lean[1] * t ** 1.3 - bend_ * 0.5, -0.8 + (trunk_h + 0.8) * t)
        path.append(p)
        radii.append(trunk_r * (1.0 - 0.32 * t))

    def flare(i, ang):
        if i > 1:
            return 1.0
        k = (1.0 if i == 0 else 0.45)
        return 1 + k * 0.55 * max(0.0, math.cos(ang * roots + seed)) ** 2

    tube(barkp, path, radii, sides=6 if lod else 8, lobes=flare, seed=seed, cap=False)
    if birch and lod != 2:
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
        if not group or lod == 2:
            continue  # on the horizon the masses hide the limbs
        tgt = tuple(sum(g[0][i] for g in group) / len(group) for i in range(3))
        start = add(fork, (0, 0, -trunk_h * 0.12 * (gi % 2)))
        end = lerp(start, tgt, 0.72)
        end = add(end, (0, 0, 0.6))
        mid_pt = add(lerp(start, end, 0.5), (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0.9))
        lp = [start, lerp(start, mid_pt, 0.5), mid_pt, lerp(mid_pt, end, 0.5), end]
        lr = [radii[-1] * 0.78, radii[-1] * 0.66, radii[-1] * 0.54, radii[-1] * 0.44, radii[-1] * 0.34]
        tube(barkp, lp, lr, sides=5 if lod else 6, seed=seed + gi)
        for (p, r) in group:
            if lod:
                break  # far away, the masses hide the twigs
            s = lerp(start, end, rng.uniform(0.55, 0.95))
            e = lerp(s, p, 0.82)
            m = add(lerp(s, e, 0.5), (0, 0, 0.4))
            tube(barkp, [s, m, e], [lr[-1] * 0.85, lr[-1] * 0.6, lr[-1] * 0.32], sides=5, seed=seed + 31)

    if lod == 2:
        # on the horizon: a few big masses make the silhouette
        spots = [(p, r * 1.7) for p, r in spots[::4]]
    elif lod:
        # far away: half as many, larger masses, no leaf fringe, coarser cores
        spots = [(p, r * 1.35) for p, r in spots[::2]]
    canopy((dark, mid, light), (0.5, 0.68), spots, centre, rng, leaf, 0 if lod else density, seed,
           subdiv=1 if (lod or clump_r <= 3) else 2)
    return a


def ancient_oak(name="AncientOak", seed=11, lod=False, trunk_h=26.0, r0=7.6, crown_z=60.0, crown_r=34.0,
                crown_h=44.0, clump_r=9.5, clumps=28, nroots=7, reach=(13, 21),
                pal=("ancientDark", "ancientMid", "ancientLight", "ancientGold")):
    """The landmark: a gnarled ancient with buttress roots, a twisted trunk, great
    limbs and a sprawling crown of big leaf masses, a few of them gold-lit."""
    rng = random.Random(seed)
    a = Asset(name)
    barkp = a.part("bark", PAL["barkAncient"])
    dark = a.part("leafDark", PAL[pal[0]])
    mid = a.part("leafMid", PAL[pal[1]])
    light = a.part("leafLight", PAL[pal[2]])
    gold = a.part("leafGold", PAL[pal[3]])

    path, radii = [], []
    for i in range(9):
        t = i / 8
        path.append((math.sin(t * 2.2) * 1.4, math.cos(t * 1.7) * 1.0 - 1.0, -2.0 + (trunk_h + 2.0) * t))
        radii.append(r0 * (1.0 - 0.28 * t))

    def gnarl(i, ang):
        twist = ang + i * 0.5
        return 1 + 0.16 * math.cos(twist * 5) + 0.08 * math.cos(twist * 3 + 1) + (0.35 if i == 0 else 0.0)

    tube(barkp, path, radii, sides=10 if lod else 14, lobes=gnarl, seed=seed, cap=False)
    # buttress roots: out of the trunk, down and away into the ground
    reach_range = reach
    for k in range(nroots):
        ang = k / nroots * math.tau + rng.uniform(-0.2, 0.2)
        d = (math.cos(ang), math.sin(ang), 0)
        reach = rng.uniform(*reach_range)
        start = add(mul(d, r0 * 0.55), (0, 0, rng.uniform(5, 8)))
        pts, rr = [], []
        for i in range(6):
            t = i / 5
            out = r0 * 0.55 + reach * t
            z = start[2] * (1 - t) ** 1.6 - 0.9 * t
            side = math.sin(t * 3 + k) * 1.2
            pts.append(add(add(mul(d, out), mul((-d[1], d[0], 0), side)), (0, 0, z)))
            rr.append(rng.uniform(2.6, 3.2) * r0 / 7.6 * (1 - t) ** 0.8 + 0.35)
        tube(barkp, pts, rr, sides=6 if lod else 8, seed=seed + k)

    # the crown: a broad dome of great leaf masses, and the limbs that carry them
    centre = (0.0, -1.0, crown_z)
    spots = crown_spots(rng, centre, crown_r, crown_h, clump_r, clumps, low=-0.5)
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
        tube(barkp, pts, rr, sides=7 if lod else 9, seed=seed + 40 + k)
        for ci, (p, r) in enumerate(group):
            if lod:
                break
            s = lerp(knee, end, rng.uniform(0.2, 1.0))
            e = lerp(s, p, 0.75)
            tube(barkp, [s, add(lerp(s, e, 0.5), (0, 0, 1.5)), e], [2.0, 1.3, 0.6], sides=6, seed=seed + 90 + ci)
    if lod == 2:
        spots = [(p, r * 1.45) for p, r in spots[::3]]
    canopy((dark, mid, light, gold), (0.5, 0.66, 0.8), spots, centre, rng, 3.2, 0 if lod else 0.85, seed + 200,
           subdiv=1 if lod else 2)
    return a


# ------------------------------------------------------------------ conifers


def spruce(name="Spruce", seed=21, height=32.5, base_r=10.0, trunk_r=0.95, lod=False):
    """A spruce: whorls of drooping, saw-toothed fronds, longer and more ragged
    low down, around a dark heart, a leader spike on top. Lengths and bearings
    jitter so the tiers read as boughs, not a stack of cones."""
    rng = random.Random(seed)
    a = Asset(name)
    k = height / 32.5
    barkp = a.part("bark", PAL["barkDark"])
    dark = a.part("needleDark", PAL["spruceDark"])
    mid = a.part("needleMid", PAL["spruceMid"])
    light = a.part("needleLight", PAL["spruceLight"])
    tube(barkp, [(0, 0, -0.8), (0, 0, 6 * k), (0.1, 0, 16 * k), (0, 0.1, height - 1)],
         [trunk_r, trunk_r * 0.84, trunk_r * 0.58, 0.15], sides=6 if lod else 7, seed=seed)
    z0, z1 = 2.6 * k, height - 1.2 * k
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
        nf = max(3, (8 if t < 0.55 else (6 if t < 0.8 else 4)) - (3 if lod == 2 else (1 if lod else 0)))
        off = rng.uniform(0, math.tau)
        for fi in range(nf):
            if t < 0.7 and rng.random() < 0.12:
                continue
            ang = off + fi / nf * math.tau + rng.uniform(-0.3, 0.3)
            L = reach * rng.uniform(0.8, 1.1)
            frond(a, (dark, mid, light), rng, (0, 0, z + rng.uniform(-0.2, 0.2) * k), ang, L, t,
                  droop=0.55 + 0.3 * (1 - t), wide=0.62 if lod == 2 else (0.5 if lod else 0.3),
                  segs=2 if lod == 2 else (3 if lod else 4),
                  sided=1 if lod else 2)
            if t < 0.85 and not lod:
                # a shorter bough between, a little higher: fills the tier
                frond(a, (dark, mid, light), rng, (0, 0, z + 0.45 * k), ang + math.pi / nf, L * 0.62, t,
                      droop=0.4 + 0.2 * (1 - t), wide=0.28)
        level += 1
        z += rng.uniform(1.7, 2.4) * (1 - 0.4 * t) * k * (2.3 if lod == 2 else (1.55 if lod else 1.0))
    # leader
    frond(a, (dark, mid, light), rng, (0, 0, z1 - 0.6 * k), 0, 2.2 * k, 1.0, droop=-6.0)
    return a


def frond(a, parts, rng, root, ang, L, t, droop=0.5, segs=5, wide=0.26, rise=0.3, sided=2):
    """A spruce bough as a broad drooping pad: widest near its middle, folded
    down from the midrib like a shallow umbrella, its edge lightly toothed,
    darker at the trunk and lighter toward the sunlit tip."""
    dark, mid, light = parts
    leader = droop < -1
    d = (math.cos(ang), math.sin(ang), 0.0)
    side = norm((-d[1], d[0], 0)) if not leader else (1.0, 0.0, 0.0)
    width = max(0.7, min(3.0 * max(1.0, L / 10.0), L * wide))
    rows = []
    for i in range(segs + 1):
        s = i / segs
        if leader:
            m = add(root, (0, 0, L * s))
        else:
            m = add(root, (d[0] * L * s, d[1] * L * s, (rise * s - droop * s * s) * L * 0.55))
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
            # one face up (what the game camera sees); the underside too unless one-sided
            part.tri(ids[0], ids[2], ids[1], shade, shade, shade)
            part.tri(ids[0], ids[3], ids[2], shade, shade, shade)
            if sided == 2:
                part.tri(ids[0], ids[1], ids[2], shade, shade, shade)
                part.tri(ids[0], ids[2], ids[3], shade, shade, shade)


def pine(name="Pine", seed=31, height=33.0, lod=False):
    """A Scots pine: a tall, bare, warm-barked trunk that bends a little, boughs
    only in the top third, each ending in a flat cloud of needle tufts."""
    rng = random.Random(seed)
    a = Asset(name)
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
    if lod == 2:
        puffs = [(p, r * 1.35) for p, r in puffs[::2]]
    centre = (1.0, 0.5, height - 6)
    top = height
    for ci, (p, r) in enumerate(puffs):
        if lod:
            # far away: the needle cloud as a shaded puff
            banded_blob((dark, mid, light), (0.5, 0.68), p, (r * 1.05, r * 1.05, r * 0.5),
                        lambda n, q: sun_light(n, (q[2] - (height - 15)) / 15), subdiv=1, lump=0.2,
                        seed=seed + ci, shade_center=centre)
            continue
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



# ------------------------------------------------------------------ woodland


def bush(name, seed, lod=False):
    """A shrub: a low cluster of the same leaf masses the trees wear."""
    rng = random.Random(seed)
    a = Asset(name)
    parts = (a.part("leafDark", PAL["bushDark"]), a.part("leafMid", PAL["bushMid"]), a.part("leafLight", PAL["bushLight"]))
    spots = [((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 1.95), 1.4)]
    n = rng.choice((4, 5, 6))
    for k in range(n):
        ang = k / n * math.tau + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.8, 1.2)
        spots.append(((math.cos(ang) * d, math.sin(ang) * d, rng.uniform(1.05, 1.45)), rng.uniform(0.95, 1.25)))
    canopy(parts, (0.5, 0.68), spots, (0, 0, 1.0), rng, 0.8, 0 if lod else 6.0, seed, subdiv=1)
    return a


def fern(name, seed):
    """A fern: a ring of arching fronds, toothed along their edges."""
    rng = random.Random(seed)
    a = Asset(name)
    parts = (a.part("frondDark", PAL["fernDark"]), a.part("frondMid", PAL["fernMid"]), a.part("frondLight", PAL["fernLight"]))
    n = rng.choice((9, 10, 11))
    for k in range(n):
        ang = k / n * math.tau + rng.uniform(-0.25, 0.25)
        frond(a, parts, rng, (0, 0, 0.05), ang, rng.uniform(2.2, 3.2), 0.6, droop=rng.uniform(1.6, 1.9), segs=5,
              wide=0.13, rise=2.3)
    return a


def disc(part, centre, axis, r, sides, rng, rough=0.0):
    """A flat, slightly ragged disc facing along `axis` (a cut end of wood)."""
    u = perp(axis)
    v = cross(axis, u)
    c = part.vert(centre)
    ring = []
    for k in range(sides):
        ang = k / sides * math.tau
        rr = r * (1 - rough * rng.random())
        ring.append(part.vert(add(centre, add(mul(u, math.cos(ang) * rr), mul(v, math.sin(ang) * rr)))))
    for k in range(sides):
        part.tri(c, ring[k], ring[(k + 1) % sides], axis, axis, axis)


def stump(name, seed):
    """A sawn-off stump on flared roots, its cut face pale wood, moss at one side."""
    rng = random.Random(seed)
    a = Asset(name)
    barkp = a.part("bark", PAL["bark"])
    wood = a.part("wood", PAL["wood"])
    moss = a.part("moss", PAL["mossRock"])
    h, r = rng.uniform(1.6, 2.1), 1.25
    roots = rng.choice((4, 5))

    def flare(i, ang):
        if i > 1:
            return 1.0
        k = 1.0 if i == 0 else 0.4
        return 1 + k * 0.6 * max(0.0, math.cos(ang * roots + seed)) ** 2

    tube(barkp, [(0, 0, -0.5), (0, 0, 0.4), (0, 0, h * 0.7), (0, 0, h)], [r * 1.2, r * 1.06, r, r * 0.97],
         sides=9, lobes=flare, seed=seed, cap=False)
    disc(wood, (0, 0, h - 0.02), (0, 0, 1), r * 0.97, 9, rng)
    moss_cap(moss, rng, (0.35, -0.25, 0), r * 0.85, h + 0.01, seed, coverage=0.55)
    return a


def fallen_log(name, seed):
    """A fallen trunk: bark, pale cut ends, a broken branch stub, moss on its back."""
    rng = random.Random(seed)
    a = Asset(name)
    barkp = a.part("bark", PAL["bark"])
    wood = a.part("wood", PAL["wood"])
    moss = a.part("moss", PAL["mossRock"])
    r0, r1, half = 1.3, 1.05, 2.45
    path = [(-half, 0, r0 - 0.35), (-half * 0.3, 0.1, r0 - 0.38), (half * 0.35, -0.08, r1 - 0.3), (half, 0, r1 - 0.3)]
    radii = [r0, r0 * 0.95, r1 * 1.02, r1]
    tube(barkp, path, radii, sides=9, seed=seed, cap=False, moss=moss, moss_up=0.55)
    disc(wood, (-half - 0.01, 0, r0 - 0.35), (-1, 0, 0), r0 * 0.97, 9, rng)
    disc(wood, (half + 0.01, 0, r1 - 0.3), (1, 0, 0), r1 * 0.97, 9, rng)
    tube(barkp, [(0.4, 0.5, r0 + 0.2), (0.9, 1.0, r0 + 0.9), (1.2, 1.3, r0 + 1.2)], [0.36, 0.26, 0.18], sides=5, seed=seed + 1)
    return a


def ruin_wall(name, seed):
    """A stub of ruined wall: courses of dressed blocks, the top broken into
    steps, fallen blocks at its feet, moss on its ledges."""
    rng = random.Random(seed)
    a = Asset(name)
    st = a.part("stone", PAL["stone"])
    dk = a.part("stoneDark", PAL["stoneDark"])
    moss = a.part("moss", PAL["moss"])
    L, T = 5.0, 2.2

    def top(x):
        return 4.2 * (0.5 + 0.5 * fbm((x * 0.55 + seed, 0.3, 1.7), seed))

    z, row = -0.4, 0
    while z < 4.2:
        hgt = rng.uniform(0.7, 0.9)
        x = -L / 2 + (0.45 if row % 2 else 0.0) - 0.45
        while x < L / 2:
            ln = rng.uniform(1.0, 1.7)
            x0, x1 = max(x, -L / 2), min(x + ln, L / 2)
            if x1 - x0 > 0.3 and z < top((x0 + x1) / 2):
                y = rng.uniform(-0.08, 0.08)
                part = dk if rng.random() < 0.3 else st
                box(part, (x0 + 0.03, -T / 2 + y, z + 0.03), (x1 - 0.03, T / 2 + y, z + hgt - 0.03))
                if z + hgt >= top((x0 + x1) / 2) and rng.random() < 0.6:
                    moss_cap(moss, rng, ((x0 + x1) / 2, y, 0), min(x1 - x0, T) * 0.5, z + hgt - 0.03, seed + row, 0.8)
            x += ln
        z += hgt
        row += 1
    # fallen blocks to either side
    for k in range(6):
        side = 1 if k % 2 == 0 else -1
        c = (rng.uniform(-2.0, 2.0), side * rng.uniform(1.5, 2.3), 0.2)
        blob(dk if k % 3 == 0 else st, c, (rng.uniform(0.45, 0.75), rng.uniform(0.4, 0.6), 0.38), subdiv=0, lump=0.3,
             seed=seed + k, flat=True)
    return a



def fallen_giant(name="FallenGiant", seed=1002):
    """The Fallen Giant: an ancient trunk come down across its gully. It lies
    along +x, its axis at the origin, never thinner than the 4.75-stud collider
    the game keeps for it (Blueprints.FallenGiant), so nothing invisible ever
    stops a hero: ridged bark, moss along its back, broken limbs, a splintered
    crown end, and at +x a reared-up plate of roots and torn earth."""
    rng = random.Random(seed)
    a = Asset(name)
    barkp = a.part("bark", PAL["barkAncient"])
    dark = a.part("barkDark", PAL["barkDark"])
    moss = a.part("moss", PAL["mossRock"])
    earth = a.part("earth", PAL["earth"])
    half, r = 36.0, 5.1
    path = [(-half + 2 * half * i / 26, 0.0, 0.0) for i in range(27)]
    radii = [r * (1.0 + 0.015 * math.sin(i * 0.65)) for i in range(27)]

    def ridges(i, ang):
        # bark ridges, never cutting inside the collider (radius 4.75)
        return 0.985 + 0.015 * math.cos(ang * 9 + i * 0.35)

    trunk = a.part("trunk", PAL["barkAncient"])
    tube(trunk, path, radii, sides=18, lobes=ridges, seed=seed, cap=False, moss=moss, moss_up=0.62, wobble=0.02)
    # the crown end: a ragged break, shards of splintered wood, no flat face
    for k in range(9):
        ang = k / 9 * math.tau + rng.uniform(-0.2, 0.2)
        rr = r * rng.uniform(0.45, 0.85)
        base = (-half + 0.6, math.cos(ang) * rr, math.sin(ang) * rr)
        length_ = rng.uniform(2.5, 7.5)
        tip = add(base, (-length_, math.cos(ang) * rng.uniform(0.3, 1.6), math.sin(ang) * rng.uniform(0.3, 1.6)))
        tube(dark if k % 3 else barkp, [base, lerp(base, tip, 0.5), tip], [rng.uniform(0.9, 1.5), 0.6, 0.08],
             sides=4, seed=seed + k, cap=True)
    blob(dark, (-half + 0.3, 0, 0), (1.2, r * 0.9, r * 0.9), subdiv=1, lump=0.35, seed=seed + 20, flat=True)
    # broken limbs reaching up from the trunk
    for k, lx in enumerate((-18.0, 2.0, 21.0)):
        side = 1 if k % 2 else -1
        base = (lx, side * r * 0.4, r * 0.75)
        tip = add(base, (rng.uniform(-3, 3), side * rng.uniform(3, 6), rng.uniform(6, 10)))
        knee = add(lerp(base, tip, 0.5), (0, side * 1.0, 0))
        tube(barkp, [base, knee, tip], [1.8, 1.2, 0.6], sides=7, seed=seed + 30 + k, moss=moss, moss_up=0.6)
        for j in range(3):
            sp = add(tip, (rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8), rng.uniform(1.0, 2.2)))
            tube(dark, [tip, sp], [0.4, 0.05], sides=3, seed=seed + 40 + j, cap=True)
    # the root plate: earth torn up with the roots, reared on the far bank
    plate = (half + 3.0, 0.0, 4.5)
    blob(earth, plate, (3.2, 11.5, 10.5), subdiv=2, lump=0.3, seed=seed + 50, flat=True)
    for k in range(13):
        ang = k / 13 * math.tau + rng.uniform(-0.15, 0.15)
        d = (0.0, math.cos(ang), math.sin(ang))
        start = add(plate, (rng.uniform(-0.5, 1.5), d[1] * 7.0, d[2] * 6.5))
        reach = rng.uniform(6, 12)
        pts = [start]
        for i in range(1, 5):
            t = i / 4
            pts.append(add(start, (rng.uniform(0.5, 2.5) * t * 3, d[1] * reach * t, d[2] * reach * t - 1.5 * t * t)))
        tube(dark if k % 2 else barkp, pts, [1.5, 1.1, 0.7, 0.4, 0.12], sides=6, seed=seed + 60 + k, cap=True)
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


# kind families: (name, recipe) per variant; trees also get a far-detail "_LOD"
TREES = [
    ("OakA", lambda lod: broadleaf("OakA", 101, height=17.0, crown_r=10.8, crown_h=12.8, trunk_h=5.0, trunk_r=1.35,
                                   clumps=14, clump_r=3.8, leaf=1.5, density=4.2, limbs=4, lod=lod)),
    ("OakB", lambda lod: broadleaf("OakB", 121, height=17.5, crown_r=10.2, crown_h=13.6, trunk_h=5.4, trunk_r=1.3,
                                   clumps=13, clump_r=3.7, leaf=1.5, density=4.2, limbs=3, bend=0.45, lod=lod)),
    ("OakC", lambda lod: broadleaf("OakC", 131, height=16.6, crown_r=11.4, crown_h=11.8, trunk_h=4.8, trunk_r=1.4,
                                   clumps=15, clump_r=3.6, leaf=1.5, density=4.2, limbs=5, roots=6, lod=lod)),
    ("OakLeaningA", lambda lod: broadleaf("OakLeaningA", 103, height=17.0, crown_r=11.0, crown_h=12.0, trunk_h=5.4,
                                          trunk_r=1.35, lean=(2.4, 0.4), clumps=13, clump_r=3.8, leaf=1.5,
                                          density=4.2, limbs=3, lod=lod)),
    ("OakLeaningB", lambda lod: broadleaf("OakLeaningB", 123, height=16.4, crown_r=10.5, crown_h=11.6, trunk_h=5.8,
                                          trunk_r=1.3, lean=(2.2, -0.6), clumps=12, clump_r=3.8, leaf=1.5,
                                          density=4.2, limbs=3, bend=0.4, lod=lod)),
    ("BeechA", lambda lod: broadleaf("BeechA", 107, height=18.0, crown_r=8.2, crown_h=14.0, trunk_h=5.2, trunk_r=1.1,
                                     clumps=13, clump_r=3.2, leaf=1.35, density=4.4, limbs=4,
                                     pal=("beechDark", "beechMid", "beechLight"), lod=lod)),
    ("BeechB", lambda lod: broadleaf("BeechB", 127, height=18.5, crown_r=7.6, crown_h=15.0, trunk_h=5.6, trunk_r=1.05,
                                     clumps=12, clump_r=3.1, leaf=1.35, density=4.4, limbs=3, bend=0.35,
                                     pal=("beechDark", "beechMid", "beechLight"), lod=lod)),
    ("BirchA", lambda lod: broadleaf("BirchA", 109, height=24.5, crown_r=5.4, crown_h=15.0, trunk_h=9.5, trunk_r=0.62,
                                     clumps=12, clump_r=2.4, leaf=1.05, density=5.2, limbs=4,
                                     pal=("birchDark", "birchMid", "birchLight"), bark="barkBirch", birch=True,
                                     roots=3, lod=lod)),
    ("BirchB", lambda lod: broadleaf("BirchB", 129, height=25.0, crown_r=4.9, crown_h=16.0, trunk_h=10.5,
                                     trunk_r=0.6, clumps=11, clump_r=2.3, leaf=1.05, density=5.2, limbs=3,
                                     pal=("birchDark", "birchMid", "birchLight"), bark="barkBirch", birch=True,
                                     roots=3, bend=0.5, lod=lod)),
    ("SaplingA", lambda lod: broadleaf("SaplingA", 113, height=9.6, crown_r=3.6, crown_h=6.5, trunk_h=3.0,
                                       trunk_r=0.34, clumps=6, clump_r=1.7, leaf=0.95, density=5.5, limbs=2, roots=3,
                                       lod=lod)),
    ("SaplingB", lambda lod: broadleaf("SaplingB", 133, height=10.2, crown_r=3.2, crown_h=7.0, trunk_h=3.4,
                                       trunk_r=0.32, clumps=6, clump_r=1.6, leaf=0.95, density=5.5, limbs=2, roots=3,
                                       pal=("beechDark", "beechMid", "beechLight"), bend=0.5, lod=lod)),
    ("SpruceA", lambda lod: spruce("SpruceA", 21, 32.5, 10.0, lod=lod)),
    ("SpruceB", lambda lod: spruce("SpruceB", 22, 33.5, 9.2, lod=lod)),
    ("SpruceC", lambda lod: spruce("SpruceC", 23, 31.0, 10.8, lod=lod)),
    ("PineA", lambda lod: pine("PineA", 31, 33.0, lod=lod)),
    ("PineB", lambda lod: pine("PineB", 32, 34.0, lod=lod)),
    ("AncientOakA", lambda lod: ancient_oak("AncientOakA", 11, lod=lod)),
    ("AncientOakB", lambda lod: ancient_oak("AncientOakB", 12, lod=lod, crown_r=36.0, crown_h=42.0, nroots=8)),
    ("AncientPine", lambda lod: spruce("AncientPine", 24, 107.0, 25.0, trunk_r=4.2, lod=lod)),
    ("Elder", lambda lod: ancient_oak("Elder", 14, lod=lod, trunk_h=20.0, r0=6.8, crown_z=46.0, crown_r=34.0,
                                      crown_h=36.0, clump_r=8.5, clumps=24, nroots=8, reach=(12, 18),
                                      pal=("elderDark", "elderMid", "elderLight", "elderGold"))),
    ("BushA", lambda lod: bush("BushA", 501, lod=lod)),
    ("BushB", lambda lod: bush("BushB", 503, lod=lod)),
    ("BushC", lambda lod: bush("BushC", 505, lod=lod)),
]


def build_all():
    kit = []
    for name, recipe in TREES:
        kit.append(recipe(False))
        lod = recipe(1)
        lod.name = name + "_LOD"
        kit.append(lod)
        if not name.startswith(("Bush", "Sapling")):
            far = recipe(2)
            far.name = name + "_FAR"
            kit.append(far)
    kit.append(fern("FernA", 601))
    kit.append(fern("FernB", 603))
    kit.append(stump("StumpA", 701))
    kit.append(stump("StumpB", 703))
    kit.append(fallen_log("FallenLog", 711))
    kit.append(fallen_giant())
    kit.append(fit(rock("BoulderLargeA", 301, (4.4, 4.5, 2.9), sink=0.18, moss_amount=0.6), (8.8, 9.0, 4.6)))
    kit.append(fit(rock("BoulderLargeB", 311, (4.6, 4.2, 3.2), sink=0.2, moss_amount=0.55), (8.8, 9.0, 4.8)))
    kit.append(fit(rock("RockSmallA", 303, (0.95, 0.9, 1.15), sink=0.15, moss_amount=0.45, subdiv=1), (1.8, 1.8, 2.0)))
    kit.append(fit(rock("RockSmallB", 313, (1.0, 0.85, 1.1), sink=0.15, moss_amount=0.4, subdiv=1), (1.8, 1.8, 2.1)))
    kit.append(fit(rock("BoulderFlat", 305, (1.35, 1.3, 1.25), sink=0.12, moss_amount=0.5, subdiv=1), (2.6, 2.4, 1.6)))
    kit.append(fit(rock("MenhirA", 801, (1.5, 1.1, 5.5), sink=0.08, moss_amount=0.32), (3.4, 2.4, 11.0)))
    kit.append(fit(rock("MenhirB", 803, (1.4, 1.2, 5.5), sink=0.08, moss_amount=0.38), (3.2, 2.5, 11.5)))
    kit.append(ruin_wall("RuinWallA", 901))
    kit.append(ruin_wall("RuinWallB", 903))
    kit.append(pillar("PillarA", 401, broken=False))
    kit.append(pillar("PillarB", 411, broken=False))
    kit.append(pillar("PillarBrokenA", 403, broken=True))
    kit.append(pillar("PillarBrokenB", 413, broken=True))
    return kit

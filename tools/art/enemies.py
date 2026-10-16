"""Enemy models for the horde (M4.A), in the Wardwood kit's style.

Second pass, after the enemy references (D:/Dev.2/Enemie References): bigger,
stronger silhouettes, softer colours that still part from the green grass.

    KitEnemyGoblinRunt     fodder: a big expressive head on a scrawny body, huge
                           sideways ears, a long nose and a toothy grin, a rust
                           tunic with a leather strap, pointy shoes; khaki-olive skin
    KitEnemyGoblinBruiser  the heavy: a hunched burgundy brute, head low between
                           massive shoulders, an iron cap with sweeping bone horns,
                           tusks, one iron pauldron, long bandaged forearms, a
                           leather loincloth
    KitEnemySlime          the leaper: a soft mauve egg-dome with a glossy
                           highlight, two little nubs, dark oval eyes

Parts follow the names EnemyRenderController animates: Body and Head stay with
the body, ArmL/ArmR/LegL/LegR swing about the top of their own box (so an arm's
box starts at its shoulder or elbow, a leg's at its hip). Every other part rides
with the body. The model faces Blender +Y (Roblox -Z, the way enemies face) and
is centred on its own box, as the renderer places enemies by their middle.
"""

from __future__ import annotations

import math

from geo import Asset, Part, add, blob, lerp, norm, rot_vec, tube

# ---------------------------------------------------------------- palette: muted, warm, readable on green
SKIN_GOBLIN = (172, 164, 104)  # khaki-olive: lighter and yellower than the grass
TUNIC_RUST = (132, 62, 48)
LEATHER = (88, 60, 42)
PANTS = (80, 66, 54)
IVORY = (232, 224, 204)
DARK = (36, 28, 26)
SKIN_BRUTE = (146, 72, 60)  # burgundy-rust
IRON = (86, 94, 108)  # cool grey-blue
BONE = (226, 214, 184)
BANDAGE = (172, 156, 122)
LOIN = (104, 74, 50)
EYE_AMBER = (228, 176, 86)
SLIME = (162, 116, 160)  # mauve
SLIME_LIGHT = (220, 194, 218)
SLIME_DARK = (58, 38, 60)


# ---------------------------------------------------------------- building blocks


def centre(asset):
    """Move an asset so its box is centred on the origin (the renderer's pivot)."""
    lo, hi = asset.bounds()
    c = [(lo[i] + hi[i]) / 2 for i in range(3)]
    for p in asset.parts.values():
        p.pos = [(v[0] - c[0], v[1] - c[1], v[2] - c[2]) for v in p.pos]
    return asset


def _turn(v, rot):
    for axis, ang in zip(((1, 0, 0), (0, 1, 0), (0, 0, 1)), rot):
        if ang:
            v = rot_vec(v, axis, ang)
    return v


def put(dst, build, at=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Build a shape at the origin, then scale, turn (x, y, z radians) and place
    it into `dst`, its normals carried along."""
    tmp = Part("tmp", (0, 0, 0))
    build(tmp)
    base = len(dst.pos)
    for v in tmp.pos:
        p = _turn((v[0] * scale[0], v[1] * scale[1], v[2] * scale[2]), rot)
        dst.pos.append(add(p, at))
    for tri, nrms in zip(tmp.tris, tmp.nrm):
        n3 = tuple(norm(_turn((n[0] / scale[0], n[1] / scale[1], n[2] / scale[2]), rot)) for n in nrms)
        dst.tri(tri[0] + base, tri[1] + base, tri[2] + base, *n3)


def ball(part, c, r, sub=2, lump=0.04, seed=0):
    blob(part, c, r, subdiv=sub, lump=lump, seed=seed)


def limb(part, pts, radii, seed=0, sides=7):
    tube(part, pts, radii, sides=sides, seed=seed, cap=True, wobble=0.02)


def cone(part, base, tip, r, seed=0, sides=8, bend=(0.0, 0.0, 0.0)):
    mid = add(lerp(base, tip, 0.55), bend)
    tube(part, [base, mid, tip], [r, r * 0.55, 0.03], sides=sides, seed=seed, cap=True, wobble=0.02)


# ---------------------------------------------------------------- the goblin


def goblin_runt(name="KitEnemyGoblinRunt", seed=1):
    a = Asset(name)
    tunic = a.part("Body", TUNIC_RUST)
    strap = a.part("Leather", LEATHER)
    head = a.part("Head", SKIN_GOBLIN)
    whites = a.part("Eyes", IVORY)
    dark = a.part("Pupils", DARK)
    arm_l = a.part("ArmL", SKIN_GOBLIN)
    arm_r = a.part("ArmR", SKIN_GOBLIN)
    leg_l = a.part("LegL", PANTS)
    leg_r = a.part("LegR", PANTS)

    # legs: bent, wide apart, ending in long pointy shoes
    for part, sx in ((leg_l, -1), (leg_r, 1)):
        hip, knee, ankle = (sx * 0.24, 0, 1.0), (sx * 0.34, 0.12, 0.55), (sx * 0.36, -0.02, 0.16)
        limb(part, [hip, knee, ankle], [0.15, 0.12, 0.1], seed)
        put(part, lambda p: ball(p, (0, 0, 0), (0.17, 0.42, 0.13), sub=1), at=(sx * 0.38, 0.18, 0.1), rot=(0.25, 0, 0))
        cone(part, (sx * 0.38, 0.5, 0.12), (sx * 0.36, 0.78, 0.28), 0.1, seed, sides=6)
    # a small pear of a body in a rust tunic, leaning forward a little
    put(tunic, lambda p: ball(p, (0, 0, 0), (0.46, 0.4, 0.55), sub=1), at=(0, 0.04, 1.32), rot=(0.18, 0, 0))
    put(tunic, lambda p: ball(p, (0, 0, 0), (0.5, 0.44, 0.18), sub=1, lump=0.1), at=(0, 0.02, 0.98))
    # a leather belt and a strap over one shoulder
    tube(strap, [(0, 0.02, 1.02), (0, 0.04, 1.1)], [0.5, 0.5], sides=12, seed=seed, cap=False, wobble=0.0)
    put(strap, lambda p: ball(p, (0, 0, 0), (0.07, 0.43, 0.6), sub=1, lump=0.0), at=(0.1, 0.06, 1.4), rot=(0.18, 0.55, 0))

    # the head: big, a wide jaw, heavy brow, long nose, grin, huge ears
    hc = (0, 0.3, 2.28)
    ball(head, hc, (0.6, 0.55, 0.52), seed=seed + 1)
    ball(head, add(hc, (0, 0.12, -0.22)), (0.56, 0.46, 0.34), sub=1, seed=seed + 2)  # the jaw
    ball(head, add(hc, (0, 0.38, 0.2)), (0.48, 0.18, 0.12), sub=1, seed=seed + 3)  # the brow
    put(head, lambda p: cone(p, (0, 0, 0), (0, 0, 0.62), 0.13, seed, sides=7), at=add(hc, (0, 0.5, 0.05)), rot=(-1.9, 0, 0))
    for sx in (-1, 1):
        # long ears out to the side and a little up, flat like leaves
        put(head, lambda p: ball(p, (0, 0, 0), (0.62, 0.08, 0.22), sub=1, lump=0.02),
            at=add(hc, (sx * 0.95, -0.05, 0.12)), rot=(0, sx * -0.35, sx * 0.12))
        # big eyes under the brow, pupils looking ahead
        ball(whites, add(hc, (sx * 0.22, 0.47, 0.06)), (0.15, 0.08, 0.14), sub=1, lump=0.0)
        ball(dark, add(hc, (sx * 0.2, 0.53, 0.05)), (0.07, 0.04, 0.08), sub=1, lump=0.0)
    # the grin: a dark mouth, two teeth showing
    put(dark, lambda p: ball(p, (0, 0, 0), (0.28, 0.05, 0.08), sub=1, lump=0.0), at=add(hc, (0, 0.55, -0.28)))
    for sx in (-1, 1):
        ball(whites, add(hc, (sx * 0.1, 0.58, -0.24)), (0.05, 0.03, 0.06), sub=0, lump=0.0)

    # skinny arms hanging forward, big hands
    for part, sx in ((arm_l, -1), (arm_r, 1)):
        sh, el, wr = (sx * 0.5, 0.05, 1.68), (sx * 0.62, 0.2, 1.22), (sx * 0.58, 0.38, 0.86)
        limb(part, [sh, el, wr], [0.11, 0.09, 0.08], seed)
        ball(part, add(wr, (0, 0.04, -0.1)), (0.17, 0.17, 0.16), sub=1, lump=0.06)
    return centre(a)


# ---------------------------------------------------------------- the bruiser


def goblin_bruiser(name="KitEnemyGoblinBruiser", seed=2):
    a = Asset(name)
    body = a.part("Body", SKIN_BRUTE)
    head = a.part("Head", SKIN_BRUTE)
    armor = a.part("Armor", IRON)
    bone = a.part("Bone", BONE)
    loin = a.part("Cloth", LOIN)
    eyes = a.part("Eyes", EYE_AMBER)
    arm_l = a.part("ArmL", BANDAGE)
    arm_r = a.part("ArmR", BANDAGE)
    leg_l = a.part("LegL", LEATHER)
    leg_r = a.part("LegR", LEATHER)

    # short thick legs, bent, wide apart
    for part, sx in ((leg_l, -1), (leg_r, 1)):
        hip, knee, ankle = (sx * 0.5, -0.1, 1.45), (sx * 0.62, 0.15, 0.8), (sx * 0.6, 0.0, 0.25)
        limb(part, [hip, knee, ankle], [0.36, 0.3, 0.27], seed)
        put(part, lambda p: ball(p, (0, 0, 0), (0.34, 0.5, 0.2), sub=1), at=(sx * 0.6, 0.18, 0.16))

    # a hunched barrel: belly low, chest high and forward, a hump between the shoulders
    ball(body, (0, 0.05, 1.85), (0.9, 0.78, 0.7), sub=1, seed=seed)
    put(body, lambda p: ball(p, (0, 0, 0), (1.12, 0.85, 0.82)), at=(0, 0.35, 2.75), rot=(0.42, 0, 0))
    ball(body, (0, -0.2, 3.35), (0.75, 0.6, 0.45), sub=1, seed=seed + 4)  # the hump
    # upper arms: massive shoulders hanging forward (part of the body; the
    # bandaged forearms swing from the elbow)
    for sx in (-1, 1):
        limb(body, [(sx * 1.05, 0.3, 3.15), (sx * 1.3, 0.5, 2.55), (sx * 1.38, 0.62, 2.1)], [0.46, 0.4, 0.34], seed)
    # the loincloth and its belt
    tube(loin, [(0, 0.05, 1.3), (0, 0.05, 1.55)], [0.86, 0.9], sides=14, seed=seed, cap=False, wobble=0.0)
    put(loin, lambda p: ball(p, (0, 0, 0), (0.42, 0.1, 0.5), sub=1, lump=0.08), at=(0, 0.8, 0.95), rot=(0.12, 0, 0))
    ball(armor, (0, 0.88, 1.43), (0.18, 0.06, 0.14), sub=1, lump=0.0)  # the buckle

    # the head, low and forward between the shoulders: a heavy jaw, tusks, a brow
    hc = (0, 1.05, 3.3)
    ball(head, hc, (0.52, 0.5, 0.46), seed=seed + 1)
    ball(head, add(hc, (0, 0.22, -0.28)), (0.55, 0.42, 0.3), sub=1, seed=seed + 2)  # the jaw
    ball(head, add(hc, (0, 0.42, 0.12)), (0.46, 0.16, 0.12), sub=1, seed=seed + 3)  # the brow
    for sx in (-1, 1):
        cone(bone, add(hc, (sx * 0.28, 0.5, -0.32)), add(hc, (sx * 0.34, 0.62, 0.08)), 0.09, seed, sides=6)
        ball(eyes, add(hc, (sx * 0.19, 0.48, 0.0)), (0.09, 0.04, 0.06), sub=1, lump=0.0)
        # small ears
        put(head, lambda p: ball(p, (0, 0, 0), (0.3, 0.07, 0.16), sub=1, lump=0.02),
            at=add(hc, (sx * 0.58, -0.05, 0.05)), rot=(0, sx * -0.3, 0))
    # an iron cap with sweeping bone horns
    ball(armor, add(hc, (0, -0.02, 0.28)), (0.55, 0.52, 0.3), sub=1, lump=0.03, seed=seed + 5)
    for sx in (-1, 1):
        tube(bone, [add(hc, (sx * 0.42, 0, 0.38)), add(hc, (sx * 0.95, -0.05, 0.7)), add(hc, (sx * 1.15, 0.15, 1.2)),
                    add(hc, (sx * 1.0, 0.35, 1.55))], [0.17, 0.13, 0.08, 0.02], sides=7, seed=seed, cap=True, wobble=0.0)
    # one iron pauldron on the left shoulder, spiked
    put(armor, lambda p: ball(p, (0, 0, 0), (0.66, 0.62, 0.36), sub=1, lump=0.04), at=(-1.1, 0.2, 3.3), rot=(0, 0.35, 0))
    for k in range(3):
        cone(bone, (-1.0 - k * 0.18, 0.05 + k * 0.18, 3.55), (-1.25 - k * 0.22, -0.05 + k * 0.2, 3.95), 0.09, seed, sides=5)

    # long bandaged forearms from the elbow, big fists near the knees
    for part, sx in ((arm_l, -1), (arm_r, 1)):
        el, wr = (sx * 1.38, 0.62, 2.15), (sx * 1.32, 0.95, 1.2)
        limb(part, [el, lerp(el, wr, 0.5), wr], [0.36, 0.34, 0.3], seed)
        ball(part, add(wr, (0, 0.08, -0.25)), (0.42, 0.42, 0.4), sub=1, lump=0.07)
    return centre(a)


# ---------------------------------------------------------------- the slime


def slime(name="KitEnemySlime", seed=3):
    a = Asset(name)
    body = a.part("Body", SLIME)
    light = a.part("Shine", SLIME_LIGHT)
    dark = a.part("Eyes", SLIME_DARK)
    # a soft egg-dome, its foot spreading a little
    ball(body, (0, 0, 0.82), (1.0, 0.95, 0.85), seed=seed)
    ball(body, (0, 0, 0.22), (1.12, 1.07, 0.26), sub=2, lump=0.08, seed=seed + 1)
    # a glossy highlight and two little nubs on top
    put(light, lambda p: ball(p, (0, 0, 0), (0.3, 0.16, 0.1), sub=1, lump=0.0), at=(-0.35, 0.35, 1.45), rot=(0.5, -0.4, 0))
    for sx in (-1, 1):
        cone(light, (sx * 0.38, -0.05, 1.5), (sx * 0.5, -0.05, 1.86), 0.12, seed, sides=6)
    # dark oval eyes and a small mouth on its front
    for sx in (-1, 1):
        ball(dark, (sx * 0.31, 0.86, 1.0), (0.13, 0.07, 0.21), sub=1, lump=0.0)
        ball(light, (sx * 0.29, 0.92, 1.08), (0.04, 0.02, 0.05), sub=0, lump=0.0)
    put(dark, lambda p: ball(p, (0, 0, 0), (0.1, 0.04, 0.05), sub=1, lump=0.0), at=(0, 0.93, 0.66))
    return centre(a)


def build_all():
    return [goblin_runt(), goblin_bruiser(), slime()]

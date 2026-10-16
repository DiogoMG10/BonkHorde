"""Enemy models for the horde (M4.A), in the Wardwood kit's style.

Readable at the game camera's distance, against green grass:

    KitEnemyGoblinRunt     fodder: small, ochre skin, a tall red pointed cap, big ears
    KitEnemyGoblinBruiser  the charger: hulking, hunched, dusky purple, iron helm and
                           pauldrons, bone horns and tusks, glowing eyes, huge fists
    KitEnemySlime          the leaper: a glossy magenta dome with big eyes

Parts follow the names EnemyRenderController animates: Body and Head stay with
the body, ArmL/ArmR/LegL/LegR swing about the top of their own box (so an arm's
box starts at its shoulder, a leg's at its hip). Every other part rides with the
body. The model faces Blender +Y (Roblox -Z, the way enemies face) and is
centred on its own box, as the renderer places enemies by their middle.
"""

from __future__ import annotations

import math
import random

from geo import Asset, add, blob, lerp, mul, norm, tube

SKIN_RUNT = (206, 168, 72)
CAP_RED = (204, 50, 38)
TUNIC = (112, 74, 44)
BOOT = (64, 44, 32)
EYE_DARK = (28, 22, 20)
EYE_WHITE = (246, 244, 236)
SKIN_BRUTE = (124, 98, 150)
IRON = (78, 80, 92)
BONE = (232, 222, 192)
SASH = (214, 104, 36)
EYE_GLOW = (255, 214, 72)
SLIME = (226, 82, 164)
SLIME_SHINE = (255, 186, 226)


def centre(asset):
    """Move an asset so its box is centred on the origin (the renderer's pivot)."""
    lo, hi = asset.bounds()
    c = [(lo[i] + hi[i]) / 2 for i in range(3)]
    for p in asset.parts.values():
        p.pos = [(v[0] - c[0], v[1] - c[1], v[2] - c[2]) for v in p.pos]
    return asset


def limb(part, top, bottom, r_top, r_bottom, seed, sides=6):
    tube(part, [top, lerp(top, bottom, 0.5), bottom], [r_top, (r_top + r_bottom) / 2, r_bottom],
         sides=sides, seed=seed, cap=True, wobble=0.02)


def cone(part, base, tip, r, seed, sides=8, bend=(0.0, 0.0, 0.0)):
    mid = add(lerp(base, tip, 0.55), bend)
    tube(part, [base, mid, tip], [r, r * 0.55, 0.04], sides=sides, seed=seed, cap=True, wobble=0.02)


def goblin_runt(name="KitEnemyGoblinRunt", seed=1):
    a = Asset(name)
    body = a.part("Body", TUNIC)
    head = a.part("Head", SKIN_RUNT)
    cap = a.part("Cap", CAP_RED)
    eyes = a.part("Eyes", EYE_DARK)
    arm_l = a.part("ArmL", SKIN_RUNT)
    arm_r = a.part("ArmR", SKIN_RUNT)
    leg_l = a.part("LegL", BOOT)
    leg_r = a.part("LegR", BOOT)
    # legs: short, a little bowed; feet as round boots
    for part, sx in ((leg_l, -0.22), (leg_r, 0.22)):
        limb(part, (sx, 0, 0.85), (sx * 1.15, 0.02, 0.18), 0.17, 0.14, seed)
        blob(part, (sx * 1.15, 0.1, 0.1), (0.2, 0.3, 0.12), subdiv=1, lump=0.05, seed=seed)
    # a round tunic body with a belt line
    blob(body, (0, 0, 1.2), (0.46, 0.4, 0.48), subdiv=2, lump=0.06, seed=seed)
    # a big head, a long nose, ears out to the sides
    blob(head, (0, 0.05, 2.0), (0.48, 0.44, 0.42), subdiv=2, lump=0.05, seed=seed + 1)
    cone(head, (0, 0.38, 1.98), (0, 0.72, 1.9), 0.11, seed, sides=6)
    for sx in (-1, 1):
        cone(head, (sx * 0.4, 0, 2.05), (sx * 1.05, -0.08, 2.25), 0.16, seed, sides=5)
        blob(eyes, (sx * 0.18, 0.4, 2.1), (0.12, 0.07, 0.16), subdiv=1, lump=0.0, seed=seed)
    # the tall red cap, its tip drooping back
    tube(cap, [(0, 0, 2.3), (0, -0.05, 2.55)], [0.47, 0.47], sides=10, seed=seed, cap=False, wobble=0.01)
    tube(cap, [(0, -0.05, 2.5), (0, -0.08, 2.95), (0, -0.3, 3.35), (0, -0.78, 3.5)], [0.44, 0.3, 0.15, 0.03],
         sides=10, seed=seed, cap=True, wobble=0.01)
    # arms from the shoulders, hands as small fists
    for part, sx in ((arm_l, -0.5), (arm_r, 0.5)):
        limb(part, (sx, 0, 1.45), (sx * 1.18, 0.12, 0.85), 0.12, 0.1, seed)
        blob(part, (sx * 1.18, 0.12, 0.8), (0.13, 0.13, 0.13), subdiv=1, lump=0.05, seed=seed)
    return centre(a)


def goblin_bruiser(name="KitEnemyGoblinBruiser", seed=2):
    a = Asset(name)
    body = a.part("Body", SKIN_BRUTE)
    armor = a.part("Armor", IRON)
    cloth = a.part("Cloth", SASH)
    head = a.part("Head", SKIN_BRUTE)
    bone = a.part("Bone", BONE)
    eyes = a.part("Eyes", EYE_GLOW)
    arm_l = a.part("ArmL", SKIN_BRUTE)
    arm_r = a.part("ArmR", SKIN_BRUTE)
    leg_l = a.part("LegL", BOOT)
    leg_r = a.part("LegR", BOOT)
    # thick short legs
    for part, sx in ((leg_l, -0.42), (leg_r, 0.42)):
        limb(part, (sx, 0, 1.2), (sx * 1.1, 0.05, 0.25), 0.3, 0.26, seed)
        blob(part, (sx * 1.1, 0.12, 0.14), (0.32, 0.42, 0.18), subdiv=1, lump=0.05, seed=seed)
    # a hunched barrel of a body, leaning forward, a belly
    blob(body, (0, 0.2, 2.05), (0.95, 0.78, 0.9), subdiv=2, lump=0.08, seed=seed)
    # loincloth and a sash belt, in hot orange
    tube(cloth, [(0, 0.1, 1.25), (0, 0.12, 1.5)], [0.86, 0.88], sides=12, seed=seed, cap=False, wobble=0.02)
    blob(cloth, (0, 0.55, 1.0), (0.38, 0.12, 0.42), subdiv=1, lump=0.05, seed=seed, flat=True)
    # iron pauldrons, broad: the silhouette's shoulders
    for sx in (-1, 1):
        blob(armor, (sx * 0.95, 0.05, 2.7), (0.55, 0.55, 0.32), subdiv=1, lump=0.06, seed=seed + 3, flat=True)
    # a small head thrust forward, jaw and tusks
    blob(head, (0, 0.85, 2.75), (0.42, 0.42, 0.4), subdiv=2, lump=0.05, seed=seed + 1)
    for sx in (-1, 1):
        cone(bone, (sx * 0.16, 1.18, 2.58), (sx * 0.22, 1.32, 2.9), 0.06, seed, sides=5)
        blob(eyes, (sx * 0.15, 1.2, 2.86), (0.08, 0.04, 0.07), subdiv=1, lump=0.0, seed=seed)
    # the iron helm and its horns
    blob(armor, (0, 0.8, 3.02), (0.47, 0.47, 0.28), subdiv=1, lump=0.04, seed=seed + 2, flat=True)
    for sx in (-1, 1):
        cone(bone, (sx * 0.38, 0.8, 3.1), (sx * 0.95, 0.95, 3.75), 0.13, seed, sides=6, bend=(sx * 0.18, 0, -0.05))
    # long arms ending in huge fists, hanging low
    for part, sx in ((arm_l, -1.1), (arm_r, 1.1)):
        limb(part, (sx, 0.15, 2.6), (sx * 1.12, 0.45, 1.1), 0.3, 0.26, seed)
        blob(part, (sx * 1.12, 0.48, 0.92), (0.42, 0.42, 0.4), subdiv=1, lump=0.08, seed=seed)
    return centre(a)


def slime(name="KitEnemySlime", seed=3):
    a = Asset(name)
    body = a.part("Body", SLIME)
    shine = a.part("Shine", SLIME_SHINE)
    eyes = a.part("Eyes", EYE_WHITE)
    pupils = a.part("Pupils", EYE_DARK)
    # a glossy dome, a little wider than tall, with a soft skirt at its foot
    blob(body, (0, 0, 0.62), (0.95, 0.9, 0.7), subdiv=2, lump=0.05, seed=seed)
    blob(body, (0, 0, 0.18), (1.05, 1.0, 0.22), subdiv=1, lump=0.12, seed=seed + 1)
    blob(shine, (-0.3, 0.25, 1.15), (0.28, 0.18, 0.1), subdiv=1, lump=0.0, seed=seed)
    # big eyes on its front, pupils looking ahead
    for sx in (-1, 1):
        blob(eyes, (sx * 0.3, 0.72, 0.8), (0.22, 0.12, 0.26), subdiv=1, lump=0.0, seed=seed)
        blob(pupils, (sx * 0.28, 0.82, 0.78), (0.11, 0.06, 0.14), subdiv=1, lump=0.0, seed=seed)
    # a small dark mouth
    blob(pupils, (0, 0.86, 0.48), (0.12, 0.04, 0.05), subdiv=1, lump=0.0, seed=seed)
    return centre(a)


def build_all():
    return [goblin_runt(), goblin_bruiser(), slime()]

"""Geometry kit for the Wardwood art (M3.B): plain-Python mesh builders.

Every asset is a set of PARTS, one per colour (bark, leaves dark/mid/light,
stone, moss...). A part is an indexed triangle list with a normal per corner,
in Blender space (Z up, 1 unit = 1 stud). Normals are authored, not derived:
foliage is lit like the soft canopy it stands for (normals bent away from the
canopy's heart), bark like a smooth round limb, stone faceted. That is what
keeps a stylized tree from reading as a heap of polygons.

No Blender import here, so the builders can be checked headless; kit.py turns
parts into Blender objects, renders and exports.
"""

from __future__ import annotations

import math
import random

# ------------------------------------------------------------------ vectors


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length(a):
    return math.sqrt(dot(a, a))


def norm(a):
    n = length(a)
    return (a[0] / n, a[1] / n, a[2] / n) if n > 1e-9 else (0.0, 0.0, 1.0)


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def rot_z(v, ang):
    c, s = math.cos(ang), math.sin(ang)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2])


def perp(d):
    """Any unit vector perpendicular to d."""
    a = (0.0, 0.0, 1.0) if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
    return norm(cross(d, a))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# a cheap smooth value noise, deterministic, so lumps and bark wobble agree run to run
def _hash3(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 1442695041) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h ^ (h >> 16)) / 0xFFFFFFFF


def vnoise(p, seed=0):
    x, y, z = p
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = smooth(x - ix), smooth(y - iy), smooth(z - iz)
    acc = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                acc += w * _hash3(ix + dx, iy + dy, iz + dz, seed)
    return acc


def fbm(p, seed=0, octaves=3):
    acc, amp, total = 0.0, 1.0, 0.0
    for o in range(octaves):
        acc += amp * vnoise(mul(p, 2 ** o), seed + o * 17)
        total += amp
        amp *= 0.5
    return acc / total


# ------------------------------------------------------------------ parts


class Part:
    """One colour of an asset: positions, triangles, and a normal per corner."""

    def __init__(self, name, color, material="SmoothPlastic"):
        self.name = name
        self.color = color
        self.material = material
        self.pos = []
        self.tris = []  # (a, b, c)
        self.nrm = []  # ((nx,ny,nz) x3) per triangle

    def vert(self, p):
        self.pos.append(p)
        return len(self.pos) - 1

    def tri(self, a, b, c, na, nb, nc):
        self.tris.append((a, b, c))
        self.nrm.append((na, nb, nc))

    def tri_flat(self, a, b, c):
        n = norm(cross(sub(self.pos[b], self.pos[a]), sub(self.pos[c], self.pos[a])))
        self.tri(a, b, c, n, n, n)

    def __len__(self):
        return len(self.tris)


class Asset:
    def __init__(self, name):
        self.name = name
        self.parts = {}

    def part(self, key, color, material="SmoothPlastic"):
        if key not in self.parts:
            self.parts[key] = Part(key, color, material)
        return self.parts[key]

    def tris(self):
        return sum(len(p) for p in self.parts.values())

    def bounds(self):
        lo, hi = [1e9] * 3, [-1e9] * 3
        for p in self.parts.values():
            for v in p.pos:
                for i in range(3):
                    lo[i] = min(lo[i], v[i])
                    hi[i] = max(hi[i], v[i])
        return lo, hi


# ------------------------------------------------------------------ primitives


def frames(path):
    """Parallel-transport frames along a polyline: (tangent, u, v) per point."""
    out = []
    t0 = norm(sub(path[1], path[0]))
    u = perp(t0)
    for i in range(len(path)):
        if i == 0:
            t = t0
        elif i == len(path) - 1:
            t = norm(sub(path[i], path[i - 1]))
        else:
            t = norm(sub(path[i + 1], path[i - 1]))
        u = norm(sub(u, mul(t, dot(u, t))))
        v = cross(t, u)
        out.append((t, u, v))
    return out


def tube(part, path, radii, sides=6, lobes=None, seed=0, cap=True, moss=None, moss_up=0.62, wobble=0.08):
    """A tapered, smooth-shaded tube along `path`. `lobes(i, angle)` scales the
    ring's radius (root flare, gnarls). `moss` gets the upward-facing faces
    again, lifted a hair, so limbs and roots carry moss on their backs."""
    fr = frames(path)
    rings = []
    for i, (p, r) in enumerate(zip(path, radii)):
        t, u, v = fr[i]
        ring = []
        for k in range(sides):
            a = (k / sides) * math.tau + i * 0.35
            scale = lobes(i, a) if lobes else 1.0
            wob = 1 + wobble * (fbm((p[0] * 0.4 + k, p[1] * 0.4, p[2] * 0.4), seed) - 0.5)
            d = add(mul(u, math.cos(a)), mul(v, math.sin(a)))
            q = add(p, mul(d, r * scale * wob))
            ring.append((part.vert(q), norm(d), q))
        rings.append(ring)
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for k in range(sides):
            a, b = r0[k], r0[(k + 1) % sides]
            c, d = r1[(k + 1) % sides], r1[k]
            part.tri(a[0], b[0], c[0], a[1], b[1], c[1])
            part.tri(a[0], c[0], d[0], a[1], c[1], d[1])
            if moss is not None:
                n = norm(add(add(a[1], b[1]), add(c[1], d[1])))
                if n[2] > moss_up and fbm(mul(a[2], 0.35), seed + 5) > 0.42:
                    lift = 0.06 + 0.02 * radii[i]
                    qs = [add(x[2], mul(x[1], lift)) for x in (a, b, c, d)]
                    ids = [moss.vert(q) for q in qs]
                    nn = [norm(add(x[1], (0, 0, 0.8))) for x in (a, b, c, d)]
                    moss.tri(ids[0], ids[1], ids[2], nn[0], nn[1], nn[2])
                    moss.tri(ids[0], ids[2], ids[3], nn[0], nn[2], nn[3])
    if cap:
        last = rings[-1]
        tip = add(path[-1], mul(fr[-1][0], radii[-1] * 0.6))
        ti = part.vert(tip)
        for k in range(sides):
            a, b = last[k], last[(k + 1) % sides]
            part.tri(a[0], b[0], ti, a[1], b[1], fr[-1][0])


def icosphere(subdiv):
    t = (1 + math.sqrt(5)) / 2
    verts = [norm(v) for v in [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t),
                                (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]]
    faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
             (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5),
             (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    for _ in range(subdiv):
        cache = {}

        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                verts.append(norm(lerp(verts[a], verts[b], 0.5)))
                cache[key] = len(verts) - 1
            return cache[key]

        nf = []
        for a, b, c in faces:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        faces = nf
    return verts, faces


def blob(part, center, radii, subdiv=1, lump=0.18, seed=0, shade_center=None, shade_mix=0.6, flat=False):
    """A lumpy ellipsoid. Normals bend toward `shade_center` (the canopy's
    heart) so a clump lights as part of the whole crown."""
    verts, faces = icosphere(subdiv)
    ids, nrms = [], []
    for v in verts:
        n = 1 + lump * (fbm(mul(add(v, (seed * 0.37, 0, 0)), 1.6), seed) - 0.5) * 2
        q = add(center, (v[0] * radii[0] * n, v[1] * radii[1] * n, v[2] * radii[2] * n))
        ids.append(part.vert(q))
        local = norm((v[0] / radii[0], v[1] / radii[1], v[2] / radii[2]))
        if shade_center is not None:
            local = norm(lerp(local, norm(sub(q, shade_center)), shade_mix))
        nrms.append(local)
    for a, b, c in faces:
        if flat:
            part.tri_flat(ids[a], ids[b], ids[c])
        else:
            part.tri(ids[a], ids[b], ids[c], nrms[a], nrms[b], nrms[c])
    return [part.pos[i] for i in ids]


def card(part, center, out, size, rng, shade, fold=0.25, aspect=0.62, spin=None, tilt=(0.1, 0.55)):
    """A two-sided leaf: a diamond folded along its midrib, its tip leaning
    outward, both faces lit by the same `shade` normal (soft canopy light)."""
    up = (0.0, 0.0, 1.0)
    side = norm(cross(out, up)) if abs(out[2]) < 0.95 else perp(out)
    along = norm(cross(side, out))
    ang = spin if spin is not None else rng.uniform(-1.2, 1.2)
    c, s = math.cos(ang), math.sin(ang)
    a2 = norm(add(mul(along, c), mul(side, s)))
    s2 = norm(sub(mul(side, c), mul(along, s)))
    tilt = norm(add(a2, mul(out, rng.uniform(tilt[0], tilt[1]))))
    L, W = size, size * aspect
    base = sub(center, mul(tilt, L * 0.45))
    tip = add(center, mul(tilt, L * 0.55))
    left = add(add(center, mul(s2, W * 0.5)), mul(out, -fold * W))
    right = add(add(center, mul(s2, -W * 0.5)), mul(out, -fold * W))
    i = [part.vert(q) for q in (base, left, tip, right)]
    n = shade
    part.tri(i[0], i[1], i[2], n, n, n)
    part.tri(i[0], i[2], i[3], n, n, n)
    part.tri(i[0], i[2], i[1], n, n, n)
    part.tri(i[0], i[3], i[2], n, n, n)


def banded_blob(parts, bands, center, radii, light, subdiv=2, lump=0.2, seed=0, shade_center=None, shade_mix=0.5):
    """A lumpy ellipsoid whose faces fall into colour bands by how lit they are
    (`light(shade_normal, point) -> 0..1`, band edges in `bands`): a leaf mass
    painted in three tones, cel-style, under the leaves that fringe it."""
    verts, faces = icosphere(subdiv)
    pts, nrms = [], []
    for v in verts:
        n = 1 + lump * (fbm(mul(add(v, (seed * 0.37, 0, 0)), 1.6), seed) - 0.5) * 2
        q = add(center, (v[0] * radii[0] * n, v[1] * radii[1] * n, v[2] * radii[2] * n))
        pts.append(q)
        local = norm((v[0] / radii[0], v[1] / radii[1], v[2] / radii[2]))
        if shade_center is not None:
            local = norm(lerp(local, norm(sub(q, shade_center)), shade_mix))
        nrms.append(local)
    for f in faces:
        c = mul(add(add(pts[f[0]], pts[f[1]]), pts[f[2]]), 1 / 3)
        fn = norm(add(add(nrms[f[0]], nrms[f[1]]), nrms[f[2]]))
        lit = light(fn, c) + 0.1 * (fbm(mul(c, 0.7), seed + 77) - 0.5)
        k = 0
        while k < len(bands) and lit >= bands[k]:
            k += 1
        part = parts[k]
        ids = [part.vert(pts[i]) for i in f]
        part.tri(ids[0], ids[1], ids[2], nrms[f[0]], nrms[f[1]], nrms[f[2]])


def spike(part, root, direction, length_, width, shade, twist=0.0):
    """A two-sided needle spike (one triangle each way)."""
    side = perp(direction)
    side = rot_vec(side, direction, twist)
    a = add(root, mul(side, width * 0.5))
    b = add(root, mul(side, -width * 0.5))
    t = add(root, mul(direction, length_))
    i = [part.vert(q) for q in (a, b, t)]
    part.tri(i[0], i[1], i[2], shade, shade, shade)
    part.tri(i[1], i[0], i[2], shade, shade, shade)


def rot_vec(v, axis, ang):
    axis = norm(axis)
    c, s = math.cos(ang), math.sin(ang)
    return add(add(mul(v, c), mul(cross(axis, v), s)), mul(axis, dot(axis, v) * (1 - c)))


def sample_ellipsoid(rng, radii):
    while True:
        v = (rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))
        if 0.2 < dot(v, v) <= 1:
            v = norm(v)
            return (v[0] * radii[0], v[1] * radii[1], v[2] * radii[2]), v


def sun_light(n, height01):
    """How lit a leaf reads, 0..1: facing the high warm sun, and how high it sits."""
    sun = norm((0.35, -0.25, 1.0))
    return 0.55 * (dot(n, sun) * 0.5 + 0.5) + 0.45 * height01

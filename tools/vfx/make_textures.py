"""Draw the game's own particle textures: white, bold, cartoon shapes on a
transparent background, so every one can be tinted in the emitter.

They are drawn at 4x and scaled down, which gives clean anti-aliased edges.
Output: assets/vfx/tex/<name>.png (256 x 256).

Needs Pillow, so run with the Forge Python:
    D:\\Forge\\system\\python\\python.exe tools/vfx/make_textures.py
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "vfx" / "tex"
S = 1024  # working size
FINAL = 256
C = S / 2


def canvas():
    return Image.new("L", (S, S), 0)


def save(name, alpha, soften=0.0):
    if soften:
        alpha = alpha.filter(ImageFilter.GaussianBlur(soften))
    alpha = alpha.resize((FINAL, FINAL), Image.LANCZOS)
    img = Image.merge("RGBA", (Image.new("L", alpha.size, 255),) * 3 + (alpha,))
    img.save(OUT / f"{name}.png")


def star(points, inner, outer=0.46, rot=-90.0):
    pts = []
    for i in range(points * 2):
        r = (outer if i % 2 == 0 else inner) * S
        a = math.radians(rot + i * 180 / points)
        pts.append((C + math.cos(a) * r, C + math.sin(a) * r))
    return pts


def make():
    OUT.mkdir(parents=True, exist_ok=True)

    # puff: a cartoon cloud of overlapping circles
    a = canvas()
    d = ImageDraw.Draw(a)
    for cx, cy, r in ((0.5, 0.52, 0.3), (0.32, 0.56, 0.2), (0.68, 0.56, 0.21), (0.42, 0.36, 0.2), (0.6, 0.36, 0.19)):
        d.ellipse((cx * S - r * S, cy * S - r * S, cx * S + r * S, cy * S + r * S), fill=255)
    save("puff", a, 6)

    # dot: a plain solid disc with a slightly soft edge
    a = canvas()
    ImageDraw.Draw(a).ellipse((S * 0.1, S * 0.1, S * 0.9, S * 0.9), fill=255)
    save("dot", a, 8)

    # glow: soft radial falloff
    a = canvas()
    px = a.load()
    for y in range(0, S, 2):
        for x in range(0, S, 2):
            r = math.hypot(x - C, y - C) / (S * 0.5)
            v = int(255 * max(0.0, 1 - r) ** 2)
            px[x, y] = px[x + 1, y] = px[x, y + 1] = px[x + 1, y + 1] = v
    save("glow", a, 4)

    # star4 (twinkle) and star5 (cartoon star)
    a = canvas()
    ImageDraw.Draw(a).polygon(star(4, 0.1), fill=255)
    save("star4", a, 3)
    a = canvas()
    ImageDraw.Draw(a).polygon(star(5, 0.2), fill=255)
    save("star5", a, 3)

    # burst: a spiky comic impact
    a = canvas()
    ImageDraw.Draw(a).polygon(star(12, 0.27, 0.47), fill=255)
    save("burst", a, 3)

    # ring: thick, and ring_thin: a shockwave line
    for name, width in (("ring", 0.075), ("ring_thin", 0.03)):
        a = canvas()
        ImageDraw.Draw(a).ellipse((S * 0.06, S * 0.06, S * 0.94, S * 0.94), outline=255, width=int(S * width))
        save(name, a, 3)

    # crescent: a slash swoosh, thick in the middle and tapering to both ends
    a = canvas()
    ImageDraw.Draw(a).ellipse((S * 0.05, S * 0.05, S * 0.95, S * 0.95), fill=255)
    cut = canvas()
    ImageDraw.Draw(cut).ellipse((S * -0.02, S * 0.2, S * 0.83, S * 1.05), fill=255)
    a = ImageChops.subtract(a, cut)
    save("crescent", a, 3)

    # plus: a fat rounded heal cross
    a = canvas()
    d = ImageDraw.Draw(a)
    d.rounded_rectangle((S * 0.38, S * 0.12, S * 0.62, S * 0.88), radius=S * 0.07, fill=255)
    d.rounded_rectangle((S * 0.12, S * 0.38, S * 0.88, S * 0.62), radius=S * 0.07, fill=255)
    save("plus", a, 3)

    # shard: an angular chip
    a = canvas()
    ImageDraw.Draw(a).polygon(((S * 0.5, S * 0.06), (S * 0.78, S * 0.5), (S * 0.56, S * 0.94), (S * 0.26, S * 0.6)), fill=255)
    save("shard", a, 3)

    # streak: a speed line, fat head and a long tapered tail (points up)
    a = canvas()
    ImageDraw.Draw(a).polygon(((S * 0.5, S * 0.04), (S * 0.58, S * 0.3), (S * 0.5, S * 0.97), (S * 0.42, S * 0.3)), fill=255)
    save("streak", a, 4)

    # confetti: a small rounded rectangle
    a = canvas()
    ImageDraw.Draw(a).rounded_rectangle((S * 0.3, S * 0.18, S * 0.7, S * 0.82), radius=S * 0.06, fill=255)
    save("confetti", a, 3)

    # bolt: a jagged vertical lightning strip that fills the texture top to bottom
    rnd = random.Random(7)
    a = canvas()
    d = ImageDraw.Draw(a)
    x = C
    pts = [(x, 0)]
    for i in range(1, 9):
        x = C + rnd.uniform(-0.2, 0.2) * S
        pts.append((x, i * S / 8))
    pts[-1] = (C, S)
    d.line(pts, fill=255, width=int(S * 0.075), joint="curve")
    save("bolt", a, 3)

    # swirl: three comma arms for portals
    a = canvas()
    d = ImageDraw.Draw(a)
    for arm in range(3):
        base = arm * 120
        for i in range(60):
            t = i / 59
            ang = math.radians(base + t * 200)
            r = (0.1 + t * 0.34) * S
            w = (0.07 * (1 - t) + 0.012) * S
            x, y = C + math.cos(ang) * r, C + math.sin(ang) * r
            d.ellipse((x - w, y - w, x + w, y + w), fill=255)
    save("swirl", a, 3)

    # leaf: a simple leaf for ambient drift and bush breaks
    a = canvas()
    d = ImageDraw.Draw(a)
    d.ellipse((S * 0.2, S * 0.08, S * 0.8, S * 0.92), fill=255)
    cut = canvas()
    dc = ImageDraw.Draw(cut)
    dc.polygon(((0, 0), (S * 0.5, 0), (S * 0.2, S * 0.5), (S * 0.5, S), (0, S)), fill=255)
    a = ImageChops.subtract(a, cut.filter(ImageFilter.GaussianBlur(40)))
    save("leaf", a, 3)

    # beam: a soft vertical wedge for chest light rays (narrow at the bottom)
    a = canvas()
    ImageDraw.Draw(a).polygon(((S * 0.46, S), (S * 0.54, S), (S * 0.86, 0), (S * 0.14, 0)), fill=255)
    fade = Image.linear_gradient("L").resize((S, S))  # black at the top, white at the bottom
    a = ImageChops.multiply(a, fade.point(lambda v: int(60 + v * 195 / 255)))
    save("beam", a, 10)

    print(f"wrote {len(list(OUT.glob('*.png')))} textures to {OUT}")


if __name__ == "__main__":
    make()

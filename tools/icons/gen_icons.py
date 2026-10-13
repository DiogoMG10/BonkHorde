"""Resumable icon batch for Bonk Horde.

  python gen_icons.py            generate/draw every key whose PNG is missing
  python gen_icons.py --rekey    redo the background keying from the saved raws
  python gen_icons.py KeyA KeyB  only these keys

Driven by icons.json. Raw 1024 px generations are kept in tools/icons/raw/.
"""
import base64
import io
import json
import os
import sys
import time

import numpy as np
import requests
from PIL import Image, ImageFilter
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "assets", "ui", "icons")
RAW = os.path.join(HERE, "raw")
API = "http://127.0.0.1:7860/sdapi/v1/txt2img"
SIZE = 256
BGNAMES = {"magenta": "magenta pink", "green": "chroma key green, green screen", "blue": "royal blue", "white": "pure white"}
OUTLINE = 13
DARK = (27, 24, 40)


def load():
    with open(os.path.join(HERE, "icons.json"), encoding="utf-8") as f:
        return json.load(f)


def full_prompt(cfg, it):
    if it["mode"] == "thumb":
        return cfg["thumb_style"].format(subject=it["subject"]), cfg["thumb_negative"]
    p = cfg["style"].format(subject=it["subject"], bgname=BGNAMES[it["bg"]])
    neg = cfg["negative_v1"] if it.get("v") == 1 else cfg["negative"]
    if it.get("neg"):
        neg = it["neg"] + ", " + neg
    return p, neg


def txt2img(prompt, negative, seed):
    r = requests.post(API, json={
        "prompt": prompt, "negative_prompt": negative, "width": 1024, "height": 1024,
        "steps": 22, "cfg_scale": 6, "sampler_name": "Euler a", "seed": seed,
    }, timeout=600)
    r.raise_for_status()
    return Image.open(io.BytesIO(base64.b64decode(r.json()["images"][0]))).convert("RGB")


def key_out(img, tol=None, white=False, holes=True):
    """Remove the flat background. Returns RGBA 256x256 and a stats dict."""
    a = np.asarray(img).astype(np.int16)
    h, w, _ = a.shape
    border = np.concatenate([a[:6].reshape(-1, 3), a[-6:].reshape(-1, 3),
                             a[:, :6].reshape(-1, 3), a[:, -6:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    # chroma-aware distance: compare colour after removing brightness differences too
    d = np.sqrt(((a - bg) ** 2).sum(axis=2))
    lum = a.sum(axis=2, keepdims=True) / 3.0
    chroma = a - lum
    bgc = bg - bg.mean()
    dc = np.sqrt(((chroma - bgc) ** 2).sum(axis=2))
    tol = tol or 70
    hsv = np.asarray(img.convert("HSV")).astype(np.int16)
    bh = np.asarray(Image.fromarray(np.uint8([[bg]]), "RGB").convert("HSV"))[0, 0].astype(np.int16)
    dh = np.abs(hsv[..., 0] - bh[0])
    dh = np.minimum(dh, 256 - dh)
    huelike = (dh < 14) & (hsv[..., 1] > 110) & (hsv[..., 2] > 45)
    if white:
        huelike = np.zeros_like(huelike)
        tol = min(tol, 48)
    cand = (d < tol) | huelike
    lab, n = ndimage.label(cand)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    edge = edge[edge != 0]
    bgmask = np.isin(lab, edge)
    # enclosed holes (inside rings, handles): strict colour match, reasonably big
    strict = (d < tol * 0.6) & ~bgmask
    lab2, n2 = ndimage.label(strict)
    if n2 and holes:
        sizes = ndimage.sum(strict, lab2, range(1, n2 + 1))
        big = [i + 1 for i, s in enumerate(sizes) if s > 500]
        bgmask |= np.isin(lab2, big)
    fg = ~bgmask
    # drop specks not attached to the main object
    lab3, n3 = ndimage.label(fg)
    if n3 > 1:
        sizes = ndimage.sum(fg, lab3, range(1, n3 + 1))
        keep = [i + 1 for i, s in enumerate(sizes) if s > max(400, sizes.max() * 0.004)]
        fg = np.isin(lab3, keep)
    fg = ndimage.binary_erosion(fg, iterations=2)
    # despill: neutralise background-tinted pixels in a band near the edge
    band = fg & ~ndimage.binary_erosion(fg, iterations=5)
    rgb = a.copy()
    near = (dc < tol * 1.1) | huelike
    sp = band & near
    if sp.any():
        g = rgb[sp].min(axis=1, keepdims=True)
        rgb[sp] = (g * 0.6).astype(np.int16).repeat(3, axis=1)
    alpha = Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    al = np.asarray(alpha).astype(np.float32)
    al = np.clip((al - 40) * 255.0 / 180.0, 0, 255)
    al[~ndimage.binary_dilation(fg, iterations=2)] = 0
    # uniform thick dark outline around the silhouette (matches the drawn icons)
    yy, xx = np.ogrid[-OUTLINE:OUTLINE + 1, -OUTLINE:OUTLINE + 1]
    disk = (xx * xx + yy * yy) <= OUTLINE * OUTLINE
    ring = ndimage.binary_dilation(fg, structure=disk)
    ral = np.asarray(Image.fromarray((ring * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32)
    af = (al / 255.0)[..., None]
    rgb = rgb.clip(0, 255) * af + np.array(DARK, np.float32) * (1 - af)
    al = np.maximum(al, ral)
    rgba = np.dstack([rgb.clip(0, 255).astype(np.uint8), al.astype(np.uint8)])
    ys, xs = np.where(al > 8)
    stats = {"bg": [int(x) for x in bg], "coverage": float(fg.mean())}
    if len(xs) == 0:
        stats["empty"] = True
        return Image.new("RGBA", (SIZE, SIZE)), stats
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    stats["touches_edge"] = bool(x0 <= 1 or y0 <= 1 or x1 >= w - 1 or y1 >= h - 1)
    crop = Image.fromarray(rgba, "RGBA").crop((x0, y0, x1, y1))
    side = max(crop.size)
    pad = int(side * 0.06)
    sq = Image.new("RGBA", (side + 2 * pad, side + 2 * pad), (0, 0, 0, 0))
    sq.paste(crop, (pad + (side - crop.width) // 2, pad + (side - crop.height) // 2))
    out = sq.resize((SIZE, SIZE), Image.LANCZOS)
    o = np.asarray(out)
    stats["corner_alpha"] = [int(o[0, 0, 3]), int(o[0, -1, 3]), int(o[-1, 0, 3]), int(o[-1, -1, 3])]
    return out, stats


def main():
    cfg = load()
    args = [x for x in sys.argv[1:] if not x.startswith("--")]
    rekey = "--rekey" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(RAW, exist_ok=True)
    import draw_icons
    statpath = os.path.join(HERE, "stats.json")
    allstats = json.load(open(statpath)) if os.path.exists(statpath) else {}
    for it in cfg["icons"]:
        key = it["key"]
        if args and key not in args:
            continue
        dst = os.path.join(OUT, key + ".png")
        if it["mode"] == "draw":
            if not os.path.exists(dst) or args or rekey:
                draw_icons.DRAW[key]().save(dst)
                print("drawn", key, flush=True)
            continue
        raw = os.path.join(RAW, "%s_%d.png" % (key, it["seed"]))
        if os.path.exists(dst) and os.path.exists(raw) and not rekey:
            continue
        if not os.path.exists(raw):
            p, neg = full_prompt(cfg, it)
            t = time.time()
            img = txt2img(p, neg, it["seed"])
            img.save(raw)
            print("generated %s seed %d in %.0fs" % (key, it["seed"], time.time() - t), flush=True)
        img = Image.open(raw).convert("RGB")
        if it["mode"] == "thumb":
            img.resize((SIZE, SIZE), Image.LANCZOS).save(dst)
            continue
        out, st = key_out(img, it.get("tol"), it["bg"] == "white", it.get("holes", it["bg"] != "white"))
        out.save(dst)
        allstats[key] = st
        flag = ""
        if st.get("empty") or st.get("touches_edge") or st["coverage"] < 0.12 or max(st.get("corner_alpha", [0])) > 0:
            flag = "  <-- CHECK"
        print("keyed", key, st, flag, flush=True)
        json.dump(allstats, open(statpath, "w"), indent=1)


if __name__ == "__main__":
    main()

"""Contact sheets: 6x4 icons on a mid-grey checker, labelled. python sheets.py [KeyA KeyB ...]"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "assets", "ui", "icons")
COLS, ROWS, CELL, LAB = 6, 4, 256, 26


def checker(w, h, s=16):
    im = Image.new("RGB", (w, h), (128, 128, 128))
    d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range(0, w, s):
            if (x // s + y // s) % 2:
                d.rectangle([x, y, x + s - 1, y + s - 1], fill=(104, 104, 104))
    return im


def main():
    keys = [i["key"] for i in json.load(open(os.path.join(HERE, "icons.json"), encoding="utf-8"))["icons"]]
    only = sys.argv[1:]
    prefix = "_sheet_"
    if only:
        keys = [k for k in keys if k in only]
        prefix = "_recheck_"
    font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 16)
    per = COLS * ROWS
    for n in range(0, len(keys), per):
        chunk = keys[n:n + per]
        rows = (len(chunk) + COLS - 1) // COLS
        sheet = checker(COLS * CELL, rows * (CELL + LAB))
        d = ImageDraw.Draw(sheet)
        for i, k in enumerate(chunk):
            x, y = (i % COLS) * CELL, (i // COLS) * (CELL + LAB)
            p = os.path.join(OUT, k + ".png")
            d.rectangle([x, y + CELL, x + CELL - 1, y + CELL + LAB - 1], fill=(30, 30, 36))
            if os.path.exists(p):
                im = Image.open(p).convert("RGBA")
                sheet.paste(im, (x, y), im)
            else:
                d.text((x + 80, y + 110), "MISSING", fill=(255, 60, 60), font=font)
            d.text((x + 6, y + CELL + 4), k, fill=(255, 255, 255), font=font)
        path = os.path.join(OUT, "%s%d.png" % (prefix, n // per + 1))
        sheet.save(path)
        print(path)


if __name__ == "__main__":
    main()

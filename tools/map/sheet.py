"""Contact sheet of a preview folder: python tools/map/sheet.py <dir> <out.jpg> [cols]"""
import glob
import os
import sys

from PIL import Image, ImageDraw

d, out = sys.argv[1], sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
files = sorted(glob.glob(os.path.join(d, "*.png")))
W, H = 480, 270
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (W * cols, H * rows))
for k, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((W, H))
    x, y = (k % cols) * W, (k // cols) * H
    sheet.paste(im, (x, y))
    ImageDraw.Draw(sheet).text((x + 4, y + 4), os.path.basename(f)[:-4], fill=(255, 255, 0))
sheet.save(out, quality=88)
print(out)

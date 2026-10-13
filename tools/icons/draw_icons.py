"""Flat icons drawn directly with Pillow (4x supersampled, 256 px out)."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

S = 1024
DARK = (27, 24, 40)
OUTLINE = 34


class Canvas:
    def __init__(self):
        self.layers = []

    def layer(self, colour):
        m = Image.new("L", (S, S), 0)
        self.layers.append((m, colour))
        return ImageDraw.Draw(m)

    def render(self, outline=OUTLINE):
        union = np.zeros((S, S), bool)
        for m, _ in self.layers:
            union |= np.asarray(m) > 127
        yy, xx = np.ogrid[-outline:outline + 1, -outline:outline + 1]
        disk = (xx * xx + yy * yy) <= outline * outline
        big = ndimage.binary_dilation(union, structure=disk)
        img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        img.paste(DARK + (255,), (0, 0), Image.fromarray((big * 255).astype(np.uint8)))
        for m, c in self.layers:
            img.paste(tuple(c) + (255,), (0, 0), m)
        img = img.filter(ImageFilter.GaussianBlur(1.5))
        return img.resize((256, 256), Image.LANCZOS)


def thick(d, pts, w):
    d.line(pts, fill=255, width=w, joint="curve")
    r = w // 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)


def check():
    c = Canvas()
    pts = [(190, 540), (420, 770), (840, 270)]
    thick(c.layer((60, 200, 70)), pts, 150)
    hl = [(230, 520), (420, 705), (800, 255)]
    thick(c.layer((130, 235, 120)), [(x, y - 18) for x, y in hl], 44)
    return c.render()


def arrow_player():
    c = Canvas()
    c.layer((45, 140, 255)).polygon([(512, 90), (890, 910), (512, 730), (134, 910)], fill=255)
    c.layer((120, 195, 255)).polygon([(512, 190), (512, 640), (250, 790)], fill=255)
    return c.render()


def exclaim():
    c = Canvas()
    d = c.layer((255, 255, 255))
    d.polygon([(400, 150), (624, 150), (580, 640), (444, 640)], fill=255)
    d.ellipse([400, 80, 624, 240], fill=255)
    d.ellipse([444, 590, 580, 700], fill=255)
    d.ellipse([412, 760, 612, 960], fill=255)
    d2 = c.layer((205, 215, 235))
    d2.polygon([(560, 170), (624, 170), (584, 630), (540, 630)], fill=255)
    d2.pieslice([412, 760, 612, 960], -60, 80, fill=255)
    return c.render()


def map_chest():
    c = Canvas()
    c.layer((176, 104, 48)).rounded_rectangle([130, 250, 894, 850], radius=90, fill=255)
    c.layer((214, 138, 66)).rounded_rectangle([130, 250, 894, 520], radius=90, fill=255)
    d = c.layer(DARK)
    d.rectangle([130, 500, 894, 540], fill=255)
    g = c.layer((255, 205, 50))
    g.rectangle([240, 250, 320, 850], fill=255)
    g.rectangle([704, 250, 784, 850], fill=255)
    c.layer(DARK).rounded_rectangle([422, 430, 602, 650], radius=30, fill=255)
    c.layer((255, 225, 90)).rounded_rectangle([452, 460, 572, 620], radius=18, fill=255)
    return c.render()


def map_shrine():
    c = Canvas()
    c.layer((150, 155, 175)).rounded_rectangle([230, 780, 794, 930], radius=40, fill=255)
    c.layer((110, 115, 140)).rectangle([330, 660, 694, 790], fill=255)
    c.layer((60, 225, 235)).polygon([(512, 70), (720, 360), (512, 660), (304, 360)], fill=255)
    c.layer((170, 250, 255)).polygon([(512, 70), (512, 360), (304, 360)], fill=255)
    c.layer((30, 170, 200)).polygon([(512, 660), (512, 360), (720, 360)], fill=255)
    return c.render()


def map_boss():
    c = Canvas()
    h = c.layer((225, 45, 55))
    h.polygon([(250, 330), (120, 80), (420, 230)], fill=255)
    h.polygon([(774, 330), (904, 80), (604, 230)], fill=255)
    s = c.layer((250, 248, 240))
    s.ellipse([190, 180, 834, 760], fill=255)
    s.rounded_rectangle([340, 640, 684, 920], radius=50, fill=255)
    e = c.layer(DARK)
    e.ellipse([290, 400, 470, 590], fill=255)
    e.ellipse([554, 400, 734, 590], fill=255)
    e.polygon([(512, 600), (560, 690), (464, 690)], fill=255)
    e.rectangle([436, 790, 456, 920], fill=255)
    e.rectangle([502, 790, 522, 920], fill=255)
    e.rectangle([568, 790, 588, 920], fill=255)
    r = c.layer((235, 50, 60))
    r.ellipse([345, 460, 415, 535], fill=255)
    r.ellipse([609, 460, 679, 535], fill=255)
    return c.render()


def map_vendor():
    c = Canvas()
    b = c.layer((196, 150, 92))
    b.ellipse([170, 360, 854, 950], fill=255)
    b.polygon([(400, 420), (624, 420), (700, 110), (512, 190), (324, 110)], fill=255)
    c.layer((150, 100, 60)).rounded_rectangle([370, 320, 654, 400], radius=30, fill=255)
    c.layer(DARK).ellipse([352, 500, 672, 820], fill=255)
    c.layer((255, 205, 50)).ellipse([382, 530, 642, 790], fill=255)
    c.layer((255, 240, 150)).ellipse([430, 570, 530, 670], fill=255)
    return c.render()


def map_teammate():
    c = Canvas()
    d = c.layer((70, 215, 100))
    d.ellipse([332, 90, 692, 450], fill=255)
    d.pieslice([170, 500, 854, 1300], 180, 360, fill=255)
    c.layer((150, 240, 160)).ellipse([400, 140, 540, 270], fill=255)
    return c.render()


DRAW = {
    "IconCheck": check,
    "IconArrowPlayer": arrow_player,
    "IconExclaim": exclaim,
    "IconMapChest": map_chest,
    "IconMapShrine": map_shrine,
    "IconMapBoss": map_boss,
    "IconMapVendor": map_vendor,
    "IconMapTeammate": map_teammate,
}

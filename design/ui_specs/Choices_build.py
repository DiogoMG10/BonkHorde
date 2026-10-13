"""Builds the `Choices` ScreenGui (every pause panel) with the roblox-ui skill.

    D:\\Forge\\system\\python\\python.exe design/ui_specs/Choices_build.py

One generator, one resolved tree per output:

  design/ui_specs/Choices.json            the shipped spec (all panels, sample children)
  design/ui_specs/Choices_<State>.json    one mockup spec per panel state
  assets/ui/mockups/Choices_<State>.png   the mockups
  src/ui/Choices.model.json               the shipped tree (Rojo)
  design/ui_specs/Choices.lua             the Luau builder for execute_luau
  assets/ui/manifest.Choices.json         named elements and icon usage

The skill's ui_build.py is imported, not copied. Its spec language cannot express
a few things the contract asks for, so this file adds spec keys and applies them
in ONE place (the emitter wrapper below), so the .model.json and the Luau builder
still come from the same tree:

  font       "LuckiestGuy" on a label or button caption (the skill has one font per theme)
  as         className override for a frame ("TextButton" card roots)
  paint      hex; the named instance carries BackgroundColor3 itself under a
             neutral gradient so the game can recolour it by rarity
  flatPaint  with paint: no gradient at all (light rays the code tints)
  rich       rich-text markup shipped as Text with RichText=true
  autoX      label sizes itself to its text (AutomaticSize X, fixed TextSize)
  props      raw property overrides on the named instance
  mockHide   not drawn in the PNG (the element ships, usually Visible=false)
"""

from __future__ import annotations

import copy
import json
import math
import re
import sys
import tempfile
from pathlib import Path

SKILL = Path(r"C:\Users\diogo\.claude\skills\roblox-ui\scripts")
sys.path.insert(0, str(SKILL))
import ui_build as ub  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
THEME = json.loads((ROOT / "design" / "ui_theme.json").read_text(encoding="utf-8"))
PAL = THEME["palette"]
LG = "LuckiestGuy"
REF = [1920, 1080]

_measure = ImageDraw.Draw(Image.new("RGB", (8, 8)))


# ----------------------------------------------------------------- colour helpers

def _hex(rgb):
    return "#%02X%02X%02X" % tuple(int(round(c)) for c in rgb)


def C(c):
    """Colour pair [top, base] with the contract's soft gradient: 8% lighter at the top."""
    base = ub.hex_rgb(PAL.get(c, c))
    top = tuple(v + (255 - v) * 0.08 for v in base)
    return [_hex(top), _hex(base)]


PAINT_SHADE = 0.90


def P(c):
    """A surface the game recolours: keys for a paintable frame."""
    base = ub.hex_rgb(PAL.get(c, c))
    return {"colour": [_hex(base), _hex(tuple(v * PAINT_SHADE for v in base))],
            "paint": _hex(base)}


# ----------------------------------------------------------------- spec helpers

def L(name, text, x, y, w, h, colour="ink", align="left", scale=0.8, font=None,
      stroke=0, samples=None, **kw):
    d = {"type": "label", "name": name, "text": text, "size": [0, w, 0, h],
         "pos": [0, x, 0, y], "textColour": colour, "align": align,
         "textScale": scale, "textStroke": stroke}
    smp = list(samples or [])
    if font:
        d["font"] = font
        # LuckiestGuy is an all-caps face; the preview font is not, so the text-fit
        # check measures the capitalised string.
        smp = [s.upper() for s in smp] + [text.upper()]
    if smp:
        d["samples"] = smp
    d.update(kw)
    return d


def LC(name, text, y, w, h, **kw):
    """A label centred horizontally in its parent."""
    return L(name, text, 0, y, w, h, align=kw.pop("align", "center"),
             pos=[0.5, 0, 0, y], anchor=[0.5, 0], **kw)


def F(name, x, y, w, h, colour=None, children=None, **kw):
    d = {"type": "frame", "name": name, "size": [0, w, 0, h], "pos": [0, x, 0, y]}
    if colour is None:
        d["transparent"] = True
    elif isinstance(colour, dict):
        d.update(colour)
    else:
        d["colour"] = C(colour)
    if children:
        d["children"] = children
    d.update(kw)
    return d


def icon(name, key, x, y, side, **kw):
    d = {"type": "icon", "name": name, "icon": key, "size": [0, side, 0, side],
         "pos": [0, x, 0, y]}
    d.update(kw)
    return d


def icon_c(name, key, side, **kw):
    return icon(name, key, 0, 0, side, pos=[0.5, 0, 0.5, 0], anchor=[0.5, 0.5], **kw)


def text_w(text, px, font=None):
    t = text.upper() if font == LG else text
    bb = _measure.textbbox((0, 0), t, font=ub.load_font(px))
    return int(bb[2] - bb[0]) + 4


def auto_label(name, text, h, colour, font=None, scale=0.85, stroke=0):
    """A label that packs to its text inside a horizontal list."""
    px = int(h * scale)
    d = L(name, text, 0, 0, text_w(text, px, font), h, colour=colour, align="left",
          scale=scale, font=font, stroke=stroke)
    d.pop("samples", None)
    d["autoX"] = True
    return d


def button(name, text, colour, x, y, w=160, h=56, count=None, **kw):
    kids = []
    if count is not None:
        kids.append(L("Count", count, 0, 0, 60, 20, colour="ink", align="center",
                      scale=0.95, font=LG, stroke=2, pos=[0.5, 0, 0, -26],
                      anchor=[0.5, 0], overhang=True))
    d = {"type": "button", "name": name, "colour": C(colour), "corner": 8,
         "size": [0, w, 0, h], "pos": [0, x, 0, y], "text": text, "font": LG,
         "textScale": 0.56, "textStroke": 2, "textColour": "onDark",
         "samples": [text.upper()], "children": kids}
    d.update(kw)
    return d


def header(title, w):
    return F("Header", 8, 8, w - 16, 56, "header", corner=8, children=[
        {"type": "label", "name": "Title", "text": title, "size": [1, -56, 1, 0],
         "pos": [0, 28, 0, 0], "textColour": "ink", "align": "left",
         "textScale": 0.62, "textStroke": 3, "font": LG, "samples": [title.upper()]}])


def rivets(w, h):
    out = []
    for x, y in ((14, 14), (w - 22, 14), (14, h - 22), (w - 22, h - 22)):
        out.append(F("Rivet", x, y, 8, 8, "#A3A69F", corner=0.5, outline=False,
                     overhang=True))
    return out


def panel(name, w, h, pos, anchor, title, children, colour="panel"):
    kids = ([header(title, w)] if title else []) + children + rivets(w, h)
    return {"type": "panel", "name": name, "colour": C(colour), "corner": 12,
            "size": [0, w, 0, h], "pos": pos, "anchor": anchor, "visible": False,
            "modal": True, "z": 1, "children": kids}


def focus(w, h, shown):
    """Four white corner brackets, 8px outside the card. Ships hidden."""
    bars = []
    lw, t = 24, 5
    W, H = w + 16, h + 16
    for cx, cy, nm in ((0, 0, "TL"), (1, 0, "TR"), (0, 1, "BL"), (1, 1, "BR")):
        hx = 0 if cx == 0 else W - lw
        vx = 0 if cx == 0 else W - t
        hy = 0 if cy == 0 else H - t
        vy = 0 if cy == 0 else H - lw
        for suffix, x, y, bw, bh in (("H", hx, hy, lw, t), ("V", vx, vy, t, lw)):
            bars.append(F(nm + suffix, x, y, bw, bh, {"colour": ["#FFFFFF", "#FFFFFF"]},
                          corner=0, outline=False, overhang=True))
    d = {"type": "frame", "name": "Focus", "transparent": True,
         "size": [0, W, 0, H], "pos": [0.5, 0, 0.5, 0], "anchor": [0.5, 0.5],
         "overhang": True, "visible": False, "children": bars}
    if not shown:
        d["mockHide"] = True
    return d


RARITY = {
    "Common": ("cardCommon", "rarityCommon"),
    "Uncommon": ("cardUncommon", "rarityUncommon"),
    "Rare": ("cardRare", "rarityRare"),
    "Epic": ("cardEpic", "rarityEpic"),
    "Legendary": ("cardLegendary", "rarityLegendary"),
    "New": ("cardNew", "inkSoft"),
}


# ----------------------------------------------------------------- cards

def stat_line(label, old, new):
    return {"type": "frame", "name": "StatLine", "transparent": True,
            "size": [0, 458, 0, 26],
            "layout": {"type": "list", "dir": "x", "gap": 8, "align": "start"},
            "children": [
                auto_label("Label", label, 26, "tan"),
                auto_label("From", old, 26, "ink", font=LG),
                auto_label("Arrow", "->", 26, "ink", font=LG),
                auto_label("To", new, 26, "green", font=LG)]}


def card_left(rarity, icon_key):
    fill, tint = RARITY[rarity]
    return [
        L("RarityTag", rarity, 12, 6, 120, 22, colour=tint, align="center",
          scale=0.95, stroke=2, samples=["Legendary", "Uncommon"]),
        F("IconTile", 22, 36, 100, 100, P(tint), corner=8,
          children=[icon_c("Icon", icon_key, 84)]),
    ]


def offer_card(rarity, icon_key, name, level, lines=None, description=None, focused=False):
    fill, _ = RARITY[rarity]
    show_desc = description is not None
    lines = lines or [("Damage:", "1x", "1.08x"), ("Projectile Count:", "3.6", "4.6")]
    lines_frame = {"type": "frame", "name": "Lines", "transparent": True,
                   "size": [0, 458, 0, 60], "pos": [0, 150, 0, 74],
                   "layout": {"type": "list", "dir": "y", "gap": 8, "align": "start"},
                   "children": [stat_line(*ln) for ln in lines]}
    desc = L("Description", description or "Summons lightning to smite nearby enemies",
             150, 70, 458, 64, colour="inkSoft", scale=0.36, wrap=True, overhang=True,
             samples=["Throws a spinning banana that comes back and bonks all it meets"])
    if show_desc:
        lines_frame["visible"] = False
        lines_frame["mockHide"] = True
    else:
        desc["visible"] = False
        desc["mockHide"] = True
    kids = card_left(rarity, icon_key) + [
        L("OfferName", name, 150, 22, 340, 44, font=LG, scale=0.8, stroke=2,
          samples=["Lightning Staff"]),
        L("LevelTag", level, 498, 24, 110, 36, colour="gold", align="right", font=LG,
          scale=0.8, stroke=2, samples=["LVL 28", "NEW"]),
        lines_frame, desc, focus(630, 145, focused)]
    return {"type": "frame", "name": "OfferCard", "as": "TextButton", **P(fill),
            "corner": 8, "size": [0, 630, 0, 145], "children": kids}


LONG_ITEM = ("Attacks have a 25% chance to explode, dealing 65% Damage to "
             "surrounding enemies and stunning them for a moment")


def item_card(card_name, rarity, icon_key, name, text, price=None, focused=False):
    fill, tint = RARITY[rarity]
    kids = card_left(rarity, icon_key)
    name_w = 330 if price is not None else 458
    kids.append(L("ItemName", name, 150, 14, name_w, 40, font=LG, scale=0.8, stroke=2,
                  samples=["Second Wind Clock"]))
    if price is not None:
        kids.append({"type": "frame", "name": "PriceTag", "transparent": True,
                     "size": [0, 110, 0, 34], "pos": [0, 498, 0, 16],
                     "layout": {"type": "list", "dir": "x", "gap": 8, "align": "end"},
                     "children": [
                         {"type": "icon", "name": "IconGold", "icon": "IconGold",
                          "size": [0, 30, 0, 30]},
                         auto_label("Price", price, 34, "gold", font=LG, scale=0.82,
                                    stroke=2)]})
    kids.append(L("ItemText", text, 150, 62, 458, 72, colour="inkSoft", scale=0.3,
                  wrap=True, samples=[LONG_ITEM]))
    if price is not None:
        kids.append({"type": "label", "name": "SoldTag", "text": "SOLD",
                     "size": [0, 300, 0, 90], "pos": [0.5, 0, 0.5, 0],
                     "anchor": [0.5, 0.5], "textColour": "red", "align": "center",
                     "textScale": 0.9, "textStroke": 3, "font": LG, "rotation": -8,
                     "overhang": True, "visible": False, "mockHide": True})
    kids.append(focus(630, 145, focused))
    return {"type": "frame", "name": card_name, "as": "TextButton", **P(fill),
            "corner": 8, "size": [0, 630, 0, 145], "children": kids}


def cards_frame(children, y):
    return {"type": "frame", "name": "Cards", "transparent": True,
            "size": [0, 630, 0, 475], "pos": [0.5, 0, 0, y], "anchor": [0.5, 0],
            "layout": {"type": "list", "dir": "y", "gap": 20, "align": "start"},
            "children": children}


CENTRE = [0.5, 0, 0.5, 0]
MID = [0.5, 0.5]


# ----------------------------------------------------------------- panels

def level_up_fx():
    rays = []
    for k in range(6):
        rays.append({"type": "frame", "name": "Ray", "colour": ["#FFF9C4", "#FFF3A0"],
                     "alpha": 0.5, "outline": False, "corner": 0,
                     "size": [0, 2600, 0, 96], "pos": CENTRE, "anchor": MID,
                     "rotation": 15 + 30 * k, "overhang": True})
    return {"type": "frame", "name": "LevelUpFx", "transparent": True,
            "size": [1, 0, 1, 0], "visible": False, "z": 0, "children": [
                {"type": "frame", "name": "RayBurst", "transparent": True,
                 "size": [1, 0, 1, 0], "children": rays},
                {"type": "frame", "name": "Confetti", "transparent": True,
                 "size": [1, 0, 1, 0], "overhang": True}]}


WEAPONS = [("IconSword", "LVL 3"), ("IconLightningStaff", "LVL 2"),
           ("IconFrostRing", "LVL 1"), ("IconBone", "LVL 1")]
TOMES = [("IconTomeDamage", "LVL 2"), ("IconTomeAgility", "LVL 1"),
         ("IconTomeCooldown", "LVL 1"), ("IconTomeLuck", "LVL 1")]
ITEMS = ["IconItemLuckyClover", "IconItemTickingBracelet", "IconItemZoomSocks",
         "IconItemProteinGoop", "IconItemSusJuice", "IconItemDodgyBattery",
         "IconItemBandageBox", "IconItemStinkyCheese", "IconItemFrostShard",
         "IconItemGiantSlayerPin", "IconItemShrineWrench", "IconItemGildedSneakers",
         "IconItemEchoGem", "IconItemPocketCampfire", "IconItemFeatherweight",
         "IconItemStaticMitts", "IconItemSkeletonKey", "IconItemVampireMitts",
         "IconItemNightlight", "IconItemCrackedGoggles", "IconItemPanicMirror",
         "IconItemVolatileMeatball", "IconItemBigIceCube", "IconItemColossalFork",
         "IconItemSecondWindClock", "IconItemLuckyClover", "IconItemZoomSocks",
         "IconItemEchoGem"]


def inv_slot(key, level):
    return F("InvSlot", 0, 0, 72, 92, "slot", corner=8, children=[
        icon("Icon", key, 0, 6, 54, pos=[0.5, 0, 0, 6], anchor=[0.5, 0]),
        LC("Level", level, 68, 64, 20, font=LG, scale=0.95, stroke=2,
           samples=["LVL 28"])])


def inv_item(key, count):
    return {"type": "frame", "name": "InvItem", "colour": C("slot"), "corner": 8,
            "size": [0, 56, 0, 56], "aspect": 1.0, "children": [
                icon_c("Icon", key, 44),
                L("Count", count, 0, 0, 46, 18, align="right", font=LG, scale=1.0,
                  stroke=2, pos=[1, -3, 1, -3], anchor=[1, 1], overhang=True,
                  samples=["x12"])]}


def slot_row(name, y, entries):
    return {"type": "frame", "name": name, "transparent": True,
            "size": [0, 448, 0, 92], "pos": [0, 28, 0, y],
            "layout": {"type": "list", "dir": "x", "gap": 8, "align": "start"},
            "children": [inv_slot(k, lv) for k, lv in entries]}


def inventory_panel(n_items=3):
    w, h = 504, 668
    items = [inv_item(k, "x%d" % (1 + (i * 7) % 3)) for i, k in enumerate(ITEMS[:n_items])]
    kids = [
        L("Weapons", "Weapons", 28, 76, 300, 32, font=LG, scale=0.85, stroke=2),
        slot_row("WeaponSlots", 116, WEAPONS),
        L("Tomes", "Tomes", 28, 220, 300, 32, font=LG, scale=0.85, stroke=2),
        slot_row("TomeSlots", 260, TOMES),
        L("Items", "Items", 28, 364, 300, 32, font=LG, scale=0.85, stroke=2),
        {"type": "frame", "name": "ItemGrid", "transparent": True,
         "size": [0, 448, 0, 248], "pos": [0, 28, 0, 404],
         "layout": {"type": "grid", "cell": [56, 56], "gap": 8},
         "children": items},
    ]
    return panel("InventoryPanel", w, h, [0, 22, 0.5, 0], [0, 0.5], "Inventory", kids)


STATS = [
    [("Max HP", "150"), ("HP Regen", "10"), ("Overheal", "0"), ("Shield", "25"),
     ("Armor", "22%"), ("Evasion", "1%"), ("Lifesteal", "0%"), ("Thorns", "0")],
    [("Damage", "1.0x"), ("Crit Chance", "1%"), ("Crit Damage", "1.1x"),
     ("Attack Speed", "100%"), ("Projectile Count", "0"), ("Projectile Bounces", "0")],
    [("Size", "1.0x"), ("Projectile Speed", "1.0x"), ("Duration", "1.0x"),
     ("Damage to Elites", "1.0x"), ("Knockback", "1.0x"), ("Movement Speed", "1.1x")],
    [("Extra Jumps", "0"), ("Jump Height", "7"), ("Luck", "0%"), ("Difficulty", "5%")],
    [("Pickup Range", "5"), ("XP Gain", "1.0x"), ("Gold Gain", "1.0x"),
     ("Silver Gain", "1.2x"), ("Elite Spawn Increase", "1.25x"),
     ("Powerup Multiplier", "1.0x"), ("Powerup Drop Chance", "1.0x")],
]
assert sum(len(g) for g in STATS) == 31


def stat_row(name, value):
    return F("StatRow", 0, 0, 336, 20, children=[
        L("Name", name, 0, 0, 240, 20, colour="inkSoft", scale=0.9,
          samples=["Elite Spawn Increase"]),
        L("Value", value, 252, 0, 84, 20, align="right", font=LG, scale=0.9,
          samples=["1.25x", "9,999"])])


def stat_gap():
    return F("StatGap", 0, 0, 336, 12)


def stats_panel(full=False):
    w, h = 368, 808
    rows = []
    if full:
        for gi, group in enumerate(STATS):
            if gi:
                rows.append(stat_gap())
            rows += [stat_row(n, v) for n, v in group]
    else:
        rows = [stat_row("Max HP", "150"), stat_row("HP Regen", "10"), stat_gap(),
                stat_row("Elite Spawn Increase", "1.25x")]
    kids = [{"type": "frame", "name": "Rows", "transparent": True,
             "size": [0, 336, 0, 720], "pos": [0, 16, 0, 76],
             "layout": {"type": "list", "dir": "y", "gap": 1, "align": "start"},
             "children": rows}]
    return panel("StatsPanel", w, h, [1, -22, 0.5, 0], [1, 0.5], "Stats", kids)


def footer(w, h, children):
    return F("Footer", 8, h - 104, w - 16, 96, "slot", corner=8, children=children)


def upgrade_offers():
    w, h = 744, 752
    cards = [
        offer_card("Common", "IconSword", "Sword", "LVL 2",
                   lines=[("Size:", "100%", "120%"), ("Projectile Count:", "3.6", "4.6")]),
        offer_card("New", "IconLightningStaff", "Lightning Staff", "NEW",
                   description="Summons lightning to smite nearby enemies", focused=True),
        offer_card("Legendary", "IconTomeDamage", "Damage Tome", "LVL 28",
                   lines=[("Damage:", "1x", "1.08x")]),
    ]
    foot = footer(w, h, [
        button("BanishButton", "BANISH", "banish", 100, 32, count="1"),
        button("SkipButton", "SKIP", "skip", 284, 32, count="5"),
        button("RefreshButton", "REFRESH", "blue", 468, 32, count="3"),
        L("ChoiceTimer", "12", 648, 32, 60, 56, colour="gold", align="center", font=LG,
          scale=0.8, stroke=3, samples=["30"]),
    ])
    return panel("UpgradeOffers", w, h, CENTRE, MID, "UPGRADE OFFERS",
                 [cards_frame(cards, 104), foot])


def chest_panel():
    w, h = 744, 790
    rays = []
    for k in range(8):
        ang = 11.25 + 22.5 * k
        reach = 200 if k % 2 == 0 else 165
        # steep rays are shortened so none reaches up into ItemText
        length = int(2 * min(reach, 128 / abs(math.sin(math.radians(ang)))))
        rays.append({"type": "frame", "name": "Ray", **P("rarityLegendary"),
                     "flatPaint": True, "alpha": 0.3, "outline": False, "corner": 0.5,
                     "size": [0, length, 0, 22], "pos": [0.5, 0, 0, 126],
                     "anchor": MID, "rotation": ang, "overhang": True})
    for r in rays:  # flat in the mockup too
        r["colour"] = [r["paint"], r["paint"]]
    stage = {"type": "frame", "name": "Stage", "transparent": True,
             "size": [0, 520, 0, 440], "pos": [0.5, 0, 0, 232], "anchor": [0.5, 0],
             "children": [
                 {"type": "frame", "name": "LightRays", "transparent": True,
                  "size": [1, 0, 1, 0], "overhang": True, "children": rays},
                 icon("ItemSprite", "IconItemSecondWindClock", 0, 36, 180,
                      pos=[0.5, 0, 0, 36], anchor=[0.5, 0]),
                 icon("ChestIcon", "IconChest", 0, 224, 200,
                      pos=[0.5, 0, 0, 224], anchor=[0.5, 0])]}
    kids = [
        LC("RarityWord", "LEGENDARY", 30, 600, 52, colour="rarityLegendary", font=LG,
           scale=0.85, stroke=3, samples=["UNCOMMON"]),
        LC("ItemName", "Second Wind Clock", 96, 660, 50, font=LG, scale=0.8, stroke=3),
        LC("ItemText", "Once per stage, cheat death and come back with half your HP. "
           "Ticks very loudly.", 158, 620, 60, colour="inkSoft", scale=0.42, wrap=True,
           samples=[LONG_ITEM]),
        stage,
        footer(w, h, [
            button("BanishButton", "BANISH", "banish", 178, 32, w=170, count="0"),
            button("TakeButton", "TAKE", "blue", 380, 32, w=170)]),
    ]
    return panel("ChestPanel", w, h, CENTRE, MID, None, kids, colour="teal")


def reward_row(rarity, plain, rich):
    fill, tint = RARITY[rarity]
    return {"type": "frame", "name": "RewardRow", "as": "TextButton", **P(fill),
            "corner": 8, "size": [0, 630, 0, 104], "children": [
                F("RarityBox", 20, 12, 130, 34, "slot", corner=8),
                L("RarityTag", rarity, 20, 12, 130, 34, colour=tint, align="center",
                  scale=0.68, stroke=0, overhang=True, samples=["Legendary", "Uncommon"]),
                L("Text", plain, 20, 56, 590, 36, scale=0.85, rich=rich,
                  samples=["Gain 15% Elite Spawn Increase"])]}


def shrine_offers():
    w, h = 824, 646
    g = PAL["green"]

    def rich(n, rest):
        return 'Gain <font color="%s">%s</font> %s' % (g, n, rest)
    rows = {"type": "frame", "name": "Rows", "transparent": True,
            "size": [0, 630, 0, 356], "pos": [0.5, 0, 0, 132], "anchor": [0.5, 0],
            "layout": {"type": "list", "dir": "y", "gap": 22, "align": "start"},
            "children": [
                reward_row("Common", "Gain 10% Jump Height", rich("10%", "Jump Height")),
                reward_row("Common", "Gain 5% Crit Chance", rich("5%", "Crit Chance")),
                reward_row("Common", "Gain 15% Elite Spawn Increase",
                           rich("15%", "Elite Spawn Increase"))]}
    ignore = {"type": "frame", "name": "IgnoreRow", "as": "TextButton", **P("#4A1218"),
              "corner": 8, "size": [0, 630, 0, 68], "pos": [0.5, 0, 0, 510],
              "anchor": [0.5, 0], "children": [
                  L("Label", "Ignore Offers", 20, 14, 590, 40, scale=0.8)]}
    kids = [
        L("Intro", "The shrine offers you a reward:", 44, 80, 600, 32, colour="inkSoft",
          scale=0.8),
        rows, ignore]
    return panel("ShrineOffers", w, h, CENTRE, MID, "Charge Shrine", kids)


def shop_panel():
    w, h = 744, 752
    cards = [
        item_card("ShopCard", "Legendary", "IconItemVolatileMeatball", "Volatile Meatball",
                  "Attacks have a 25% chance to explode, dealing 65% Damage to "
                  "surrounding enemies", price="286"),
        item_card("ShopCard", "Rare", "IconItemBigIceCube", "Big Ice Cube",
                  "20% chance to inflict ice damage when hitting enemies. Ice can now "
                  "freeze enemies.", price="297"),
        item_card("ShopCard", "Legendary", "IconItemColossalFork", "Colossal Fork",
                  "You can eat so much spaghetti with this. Also crits have a chance "
                  "to become megacrits.", price="298", focused=True),
    ]
    kids = [
        LC("FlavourLine", "Every item is suspiciously warm, as if he was just holding "
           "it under his coat.", 72, 640, 50, colour="inkSoft", scale=0.44, wrap=True),
        cards_frame(cards, 130),
        footer(w, h, [
            L("GoldLabel", "Your gold: 1,234", 24, 30, 240, 36, colour="gold", font=LG,
              scale=0.75, stroke=2, samples=["Your gold: 99,999"]),
            button("LeaveButton", "LEAVE", "grey", 0, 20, w=170,
                   pos=[0.5, 0, 0.5, -2], anchor=MID, centre=False)]),
    ]
    return panel("ShopPanel", w, h, CENTRE, MID, "DODGY DAN'S DEALS", kids)


def statue_offers():
    w, h = 744, 752
    cards = [
        item_card("ItemCard", "Common", "IconItemLuckyClover", "Lucky Clover",
                  "+10% Luck. Four leaves, zero guarantees.", focused=True),
        item_card("ItemCard", "Uncommon", "IconItemZoomSocks", "Zoom Socks",
                  "+12% Movement Speed. They have never been washed and that is "
                  "where the power comes from."),
        item_card("ItemCard", "Epic", "IconItemPanicMirror", "Panic Mirror",
                  "When hit, reflect 40% of the damage back at whoever was rude "
                  "enough to do it."),
    ]
    kids = [
        LC("FlavourLine", "The statue holds out three things and stares at you. "
           "Take one. It insists.", 72, 640, 50, colour="inkSoft", scale=0.44,
           wrap=True),
        cards_frame(cards, 130),
        footer(w, h, [
            button("SkipButton", "SKIP", "skip", 0, 20, w=170,
                   pos=[0.5, 0, 0.5, -2], anchor=MID, centre=False)]),
    ]
    return panel("StatueOffers", w, h, CENTRE, MID, "ITEM OFFERS", kids)


def page(name, children):
    return {"name": name, "theme": "../ui_theme.json", "resolution": REF,
            "kind": "page", "displayOrder": 20, "ignoreGuiInset": True,
            "enabled": True, "children": children}


# ----------------------------------------------------------------- emitter wrapper

FAMILY = {LG: ("rbxasset://fonts/families/LuckiestGuy.json", "Regular"),
          "FredokaOne": ("rbxasset://fonts/families/FredokaOne.json", "Regular")}
DECOR = {"UICorner", "UIGradient", "UIStroke"}

_orig_to_instances = ub.to_instances


def _font_tag(name):
    fam, weight = FAMILY[name]
    return {"Font": {"family": fam, "weight": weight, "style": "Normal"}}


def _child(node, name):
    for c in node.get("children") or []:
        if c.get("name") == name:
            return c
    return None


def to_instances(spec, theme, palette, counter=None):
    made = _orig_to_instances(spec, theme, palette, counter)
    node = made[0]
    kind = spec.get("type", "frame")
    props = node.setdefault("properties", {})
    z = spec.get("z", 0)

    # Named children sit directly under the named instance, as the contract's
    # "Children" columns read, instead of inside the depth stack's Face.
    if kind in ("panel", "button") and not spec.get("layout") and not spec.get("padding"):
        face = _child(node, "Face")
        if face:
            keep = [c for c in face["children"] if c["className"] in DECOR]
            moved = [c for c in face["children"] if c["className"] not in DECOR]
            face["children"] = keep
            for c in moved:
                cp = c.setdefault("properties", {})
                cp["ZIndex"] = z + 2 + int(cp.get("ZIndex", 0))
            node["children"] += moved

    if spec.get("font"):
        target = node
        if kind == "button":
            target = _child(node, spec.get("captionName", "Label"))
        if target is not None:
            target["properties"]["FontFace"] = _font_tag(spec["font"])

    if spec.get("as"):
        node["className"] = spec["as"]
        if spec["as"] == "TextButton":
            props.update({"Text": "", "AutoButtonColor": False})

    if spec.get("paint") and kind == "frame":
        base = ub.hex_rgb(spec["paint"])
        props["BackgroundColor3"] = ub.col3(base)
        kids = node.get("children") or []
        if spec.get("flatPaint"):
            node["children"] = [c for c in kids if c.get("name") != "Gradient"]
        else:
            grey = round(PAINT_SHADE, 4)
            for c in kids:
                if c.get("name") == "Gradient" and c["className"] == "UIGradient":
                    c["properties"]["Color"] = {"ColorSequence": {"keypoints": [
                        {"time": 0, "color": [grey, grey, grey]},
                        {"time": 1, "color": [1, 1, 1]}]}}

    if spec.get("rich"):
        props["Text"] = spec["rich"]
        props["RichText"] = True

    if spec.get("autoX") and kind == "label":
        hpx = spec["size"][3]
        props["TextScaled"] = False
        props["TextSize"] = int(hpx * spec.get("textScale", 0.62))
        props["AutomaticSize"] = "X"
        props["Size"] = ub.udim2_tag([0, 0, 0, hpx])
        node["children"] = [c for c in node.get("children") or []
                            if c.get("name") != "SizeCap"]

    # The skill writes `align` to HorizontalAlignment and always centres vertically,
    # while its PNG renderer applies `align` along the FILL direction and centres the
    # cross axis. Emit what the renderer draws.
    lay = spec.get("layout")
    if lay and lay.get("type") != "grid":
        holder = _child(node, "Face") if kind in ("panel", "button") else node
        lnode = _child(holder, "Layout")
        a = lay.get("align", "start")
        if lay.get("dir", "y") == "x":
            lnode["properties"]["HorizontalAlignment"] = {"start": "Left", "center": "Center", "end": "Right"}[a]
            lnode["properties"]["VerticalAlignment"] = "Center"
        else:
            lnode["properties"]["VerticalAlignment"] = {"start": "Top", "center": "Center", "end": "Bottom"}[a]
            lnode["properties"]["HorizontalAlignment"] = "Center"

    if spec.get("props"):
        props.update(spec["props"])
    if spec.get("attrs"):
        node.setdefault("attributes", {}).update(spec["attrs"])
    return made


ub.to_instances = to_instances
ub.ENUM_PROPS |= {"AutomaticSize"}

_orig_lua_value = ub.lua_value


def lua_value(v, prop=None, is_attribute=False):
    if isinstance(v, dict) and "Font" in v:
        f = v["Font"]
        return 'Font.new("%s", Enum.FontWeight.%s, Enum.FontStyle.%s)' % (
            f["family"], f["weight"], f["style"])
    return _orig_lua_value(v, prop=prop, is_attribute=is_attribute)


ub.lua_value = lua_value


def finalize(root):
    """Contract shape: panels are direct children of the ScreenGui, and the game
    adds its own UIScale, so the skill's CanvasFrame and Scale are removed."""
    canvas = _child(root, "CanvasFrame")
    root["children"] = [c for c in canvas["children"] if c["className"] != "UIScale"]
    root.setdefault("attributes", {}).update(canvas.get("attributes") or {})

    def walk(n):
        for c in n.get("children") or []:
            # A UIStroke under a TextLabel must stroke the TEXT. The skill emits
            # ApplyStrokeMode=Border, which outlines the label's rectangle.
            if c["className"] == "UIStroke" and n["className"] == "TextLabel":
                c["properties"]["ApplyStrokeMode"] = "Contextual"
            walk(c)
    walk(root)
    return root


def build_root(spec):
    ub.set_style(THEME)
    ub.RESOLVED_H.clear()
    root_spec = {"type": "root", "name": spec["name"], "size": [1, 0, 1, 0],
                 "children": spec["children"]}
    ub.measure_heights(root_spec, THEME, REF)
    tree = [i for c in spec["children"] for i in ub.to_instances(c, THEME, PAL)]
    return finalize(ub.build_root(spec, spec["name"], tree))


def luau_text(root):
    """ui_build.luau declares one `local` per instance; Luau allows 200 locals per
    function and this tree has far more, so the instances go in one table."""
    src = ub.luau(ub.qualify_enums(copy.deepcopy(root)))
    out = []
    for line in src.split("\n"):
        line = re.sub(r"^local o(\d+) = ", r"o[\1] = ", line)
        line = re.sub(r"^o(\d+)([.:])", r"o[\1]\2", line)
        line = re.sub(r"\.Parent = o(\d+)$", r".Parent = o[\1]", line)
        line = re.sub(r"#o(\d+):GetDescendants", r"#o[\1]:GetDescendants", line)
        out.append(line)
    out.insert(4, "local o = {}")
    return "\n".join(out) + "\n"


# ----------------------------------------------------------------- mockups

def mock_view(node):
    """The spec as the PNG draws it: hidden sample parts removed, LuckiestGuy text
    capitalised (the face is all caps; the preview font is Fredoka)."""
    out = dict(node)
    if out.get("font") == LG and out.get("text"):
        out["text"] = str(out["text"]).upper()
    if out.get("children"):
        out["children"] = [mock_view(c) for c in out["children"] if not c.get("mockHide")]
    return out


def placeholder_icons(keys):
    d = Path(tempfile.mkdtemp(prefix="choices_icons_"))
    out = {}
    for i, k in enumerate(sorted(keys)):
        im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        hue = (i * 47) % 360
        import colorsys
        r, g, b = (int(c * 255) for c in colorsys.hsv_to_rgb(hue / 360, 0.55, 0.95))
        dr.ellipse([10, 10, 118, 118], fill=(r, g, b, 255), outline=(16, 21, 18, 255), width=8)
        short = re.sub(r"^Icon(Item|Tome)?", "", k)[:2].upper()
        f = ub.load_font(52)
        bb = dr.textbbox((0, 0), short, font=f)
        dr.text(((128 - (bb[2] - bb[0])) / 2 - bb[0], (128 - (bb[3] - bb[1])) / 2 - bb[1]),
                short, font=f, fill=(16, 21, 18, 255))
        p = d / (k + ".png")
        im.save(p)
        out[k] = p
    return out


def icon_keys(node, acc):
    if node.get("type") == "icon":
        acc.add(node["icon"])
    for c in node.get("children") or []:
        icon_keys(c, acc)
    return acc


def render_png(spec, path, icons):
    ub.set_style(THEME)
    view = [mock_view(c) for c in spec["children"]]
    root = ub.resolve({"type": "root", "name": spec["name"], "size": [1, 0, 1, 0],
                       "children": view}, (0, 0, REF[0], REF[1]), THEME)
    ub.render(root, THEME, PAL, icons, REF).convert("RGB").save(path)
    print("[png]  ", path)


# ----------------------------------------------------------------- contract check

T, B, I, FR = "TextLabel", "TextButton", "ImageLabel", "Frame"
# name -> (class, required parent name or None, Visible must be False at top level)
TOP = ["LevelUpFx", "InventoryPanel", "StatsPanel", "UpgradeOffers", "ChestPanel",
       "ShrineOffers", "ShopPanel", "StatueOffers"]
CONTRACT = [
    # (path of names, class)
    ("LevelUpFx", FR), ("LevelUpFx/RayBurst", FR), ("LevelUpFx/Confetti", FR),
    ("InventoryPanel", FR), ("InventoryPanel/Weapons", T), ("InventoryPanel/WeaponSlots", FR),
    ("InventoryPanel/WeaponSlots/InvSlot", FR), ("InventoryPanel/WeaponSlots/InvSlot/Icon", I),
    ("InventoryPanel/WeaponSlots/InvSlot/Level", T),
    ("InventoryPanel/Tomes", T), ("InventoryPanel/TomeSlots", FR),
    ("InventoryPanel/TomeSlots/InvSlot", FR), ("InventoryPanel/Items", T),
    ("InventoryPanel/ItemGrid", FR), ("InventoryPanel/ItemGrid/InvItem", FR),
    ("InventoryPanel/ItemGrid/InvItem/Icon", I), ("InventoryPanel/ItemGrid/InvItem/Count", T),
    ("StatsPanel", FR), ("StatsPanel/Rows", FR), ("StatsPanel/Rows/StatRow", FR),
    ("StatsPanel/Rows/StatRow/Name", T), ("StatsPanel/Rows/StatRow/Value", T),
    ("StatsPanel/Rows/StatGap", FR),
    ("UpgradeOffers", FR), ("UpgradeOffers/Cards", FR), ("UpgradeOffers/Cards/OfferCard", B),
    ("UpgradeOffers/Cards/OfferCard/RarityTag", T),
    ("UpgradeOffers/Cards/OfferCard/IconTile", FR),
    ("UpgradeOffers/Cards/OfferCard/IconTile/Icon", I),
    ("UpgradeOffers/Cards/OfferCard/OfferName", T),
    ("UpgradeOffers/Cards/OfferCard/Lines", FR),
    ("UpgradeOffers/Cards/OfferCard/Lines/StatLine", FR),
    ("UpgradeOffers/Cards/OfferCard/Lines/StatLine/Label", T),
    ("UpgradeOffers/Cards/OfferCard/Lines/StatLine/From", T),
    ("UpgradeOffers/Cards/OfferCard/Lines/StatLine/Arrow", T),
    ("UpgradeOffers/Cards/OfferCard/Lines/StatLine/To", T),
    ("UpgradeOffers/Cards/OfferCard/Description", T),
    ("UpgradeOffers/Cards/OfferCard/LevelTag", T),
    ("UpgradeOffers/Cards/OfferCard/Focus", FR),
    ("UpgradeOffers/Footer/BanishButton", B), ("UpgradeOffers/Footer/BanishButton/Label", T),
    ("UpgradeOffers/Footer/BanishButton/Count", T),
    ("UpgradeOffers/Footer/SkipButton", B), ("UpgradeOffers/Footer/SkipButton/Label", T),
    ("UpgradeOffers/Footer/SkipButton/Count", T),
    ("UpgradeOffers/Footer/RefreshButton", B), ("UpgradeOffers/Footer/RefreshButton/Label", T),
    ("UpgradeOffers/Footer/RefreshButton/Count", T),
    ("UpgradeOffers/Footer/ChoiceTimer", T),
    ("ChestPanel", FR), ("ChestPanel/RarityWord", T), ("ChestPanel/ItemName", T),
    ("ChestPanel/ItemText", T), ("ChestPanel/Stage", FR), ("ChestPanel/Stage/LightRays", FR),
    ("ChestPanel/Stage/ItemSprite", I), ("ChestPanel/Stage/ChestIcon", I),
    ("ChestPanel/Footer/BanishButton", B), ("ChestPanel/Footer/BanishButton/Count", T),
    ("ChestPanel/Footer/TakeButton", B),
    ("ShrineOffers", FR), ("ShrineOffers/Rows", FR), ("ShrineOffers/Rows/RewardRow", B),
    ("ShrineOffers/Rows/RewardRow/RarityTag", T), ("ShrineOffers/Rows/RewardRow/Text", T),
    ("ShrineOffers/IgnoreRow", B),
    ("ShopPanel", FR), ("ShopPanel/FlavourLine", T), ("ShopPanel/Cards", FR),
    ("ShopPanel/Cards/ShopCard", B), ("ShopPanel/Cards/ShopCard/RarityTag", T),
    ("ShopPanel/Cards/ShopCard/IconTile", FR), ("ShopPanel/Cards/ShopCard/IconTile/Icon", I),
    ("ShopPanel/Cards/ShopCard/ItemName", T), ("ShopPanel/Cards/ShopCard/ItemText", T),
    ("ShopPanel/Cards/ShopCard/PriceTag", FR), ("ShopPanel/Cards/ShopCard/PriceTag/IconGold", I),
    ("ShopPanel/Cards/ShopCard/PriceTag/Price", T), ("ShopPanel/Cards/ShopCard/SoldTag", T),
    ("ShopPanel/Footer/GoldLabel", T), ("ShopPanel/Footer/LeaveButton", B),
    ("StatueOffers", FR), ("StatueOffers/FlavourLine", T), ("StatueOffers/Cards", FR),
    ("StatueOffers/Cards/ItemCard", B), ("StatueOffers/Cards/ItemCard/RarityTag", T),
    ("StatueOffers/Cards/ItemCard/IconTile", FR), ("StatueOffers/Cards/ItemCard/IconTile/Icon", I),
    ("StatueOffers/Cards/ItemCard/ItemName", T), ("StatueOffers/Cards/ItemCard/ItemText", T),
    ("StatueOffers/Footer/SkipButton", B),
]
HIDDEN = ["UpgradeOffers/Cards/OfferCard/Focus", "ShopPanel/Cards/ShopCard/SoldTag"]


def find_path(root, path):
    node = root
    for part in path.split("/"):
        node = _child(node, part)
        if node is None:
            return None
    return node


def check_contract(root):
    bad = []
    p = root["properties"]
    for k, want in (("DisplayOrder", 20), ("ResetOnSpawn", False), ("IgnoreGuiInset", True),
                    ("ZIndexBehavior", "Sibling"), ("Enabled", True)):
        if p.get(k) != want:
            bad.append("ScreenGui.%s is %r, want %r" % (k, p.get(k), want))
    for path, cls in CONTRACT:
        n = find_path(root, path)
        if n is None:
            bad.append("MISSING " + path)
        elif n["className"] != cls:
            bad.append("%s is %s, want %s" % (path, n["className"], cls))
    for name in TOP:
        n = find_path(root, name)
        if n is not None and n["properties"].get("Visible") is not False:
            bad.append(name + " does not ship Visible=false")
    for path in HIDDEN:
        n = find_path(root, path)
        if n is not None and n["properties"].get("Visible") is not False:
            bad.append(path + " does not ship Visible=false")

    def icons(n, trail):
        for c in n.get("children") or []:
            t = trail + [c.get("name", c["className"])]
            if c["className"] == "ImageLabel":
                if not (c.get("attributes") or {}).get("IconName"):
                    bad.append("/".join(t) + " has no IconName attribute")
                if c["properties"].get("Image"):
                    bad.append("/".join(t) + " has a non-empty Image")
            icons(c, t)
    icons(root, [])
    return bad


def manifest(root):
    elements, icon_use = {}, {}

    def walk(n, trail):
        for c in n.get("children") or []:
            if "name" not in c or c["className"].startswith("UI"):
                continue
            path = "/".join(trail + [c["name"]])
            elements.setdefault(path, {"class": c["className"],
                                       "visible": c["properties"].get("Visible", True)})
            key = (c.get("attributes") or {}).get("IconName")
            if key:
                used = icon_use.setdefault(key, [])
                if path not in used:
                    used.append(path)
            walk(c, trail + [c["name"]])
    walk(root, [])
    skip = ("Shadow", "Face", "Rivet")
    return {
        "screenGui": "Choices",
        "displayOrder": root["properties"]["DisplayOrder"],
        "note": "Paths are instance names from the ScreenGui down. Sample children "
                "repeat under one path. Shadow/Face/Rivet decoration is left out. "
                "Icon keys listed are the sample values shipped; the game overwrites "
                "IconName on runtime-filled icons.",
        "elements": [{"path": k, **v} for k, v in elements.items()
                     if k.split("/")[-1] not in skip],
        "icons": {k: icon_use[k] for k in sorted(icon_use)},
    }


# ----------------------------------------------------------------- main

def main():
    shipped = page("Choices", [
        level_up_fx(), inventory_panel(3), stats_panel(False), upgrade_offers(),
        chest_panel(), shrine_offers(), shop_panel(), statue_offers()])

    def flank(n_items=12):
        return [inventory_panel(n_items), stats_panel(True)]

    mocks = {
        "Choices_UpgradeOffers": [level_up_fx()] + flank() + [upgrade_offers()],
        "Choices_ChestPanel": flank() + [chest_panel()],
        "Choices_ShrineOffers": flank() + [shrine_offers()],
        "Choices_ShopPanel": flank(28) + [shop_panel()],
        "Choices_StatueOffers": flank() + [statue_offers()],
    }

    (HERE / "Choices.json").write_text(json.dumps(shipped, indent=1), encoding="utf-8")
    for name, kids in mocks.items():
        (HERE / (name + ".json")).write_text(json.dumps(page(name, kids), indent=1),
                                             encoding="utf-8")

    only = sys.argv[1:]
    mock_dir = ROOT / "assets" / "ui" / "mockups"
    mock_dir.mkdir(parents=True, exist_ok=True)
    keys = set()
    for kids in list(mocks.values()) + [shipped["children"]]:
        for k in kids:
            icon_keys(k, keys)
    if "--no-png" not in only:
        icons = placeholder_icons(keys)
        for name, kids in mocks.items():
            if [a for a in only if not a.startswith("--")] and name not in only:
                continue
            render_png(page(name, kids), mock_dir / (name + ".png"), icons)

    root = build_root(shipped)
    rojo_root = copy.deepcopy(root)
    ub.strip_content_for_rojo(rojo_root)
    rojo_root.pop("name", None)
    model = ROOT / "src" / "ui" / "Choices.model.json"
    model.write_text(json.dumps(rojo_root, indent=1), encoding="utf-8")
    print("[model]", model)
    lua = HERE / "Choices.lua"
    lua.write_text(luau_text(root), encoding="utf-8")
    print("[luau] ", lua)

    man = manifest(root)
    (ROOT / "assets" / "ui" / "manifest.Choices.json").write_text(
        json.dumps(man, indent=1), encoding="utf-8")
    print("[manifest] %d elements, %d icon keys" % (len(man["elements"]), len(man["icons"])))

    bad = check_contract(root)
    print("[contract] %d names checked, %d problems" % (len(CONTRACT), len(bad)))
    for b in bad:
        print("   ", b)
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())

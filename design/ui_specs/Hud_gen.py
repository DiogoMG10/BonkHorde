"""Spec generator for the `Hud` ScreenGui (Bonk Horde).

    python Hud_gen.py

Writes, next to this file:
    Hud.json            the full spec: every element, hidden ones included.
                        This is what ships (through ui_build.py + Hud_post.py).
    Hud_<state>.json    the SAME nodes filtered to one play state, for mockups
                        only (the PNG renderer draws hidden elements, so the
                        full spec is unreadable as a picture).

Keys ui_build.py does not know are carried for Hud_post.py:
    font      "LuckiestGuy" on a label (ui_build has one font per theme)
    props     raw Roblox properties merged onto the instance
    flat      drop the UIGradient (full-screen fills)
    rainbow   replace the gradient with the seven-step rainbow
    round     add a UICorner (scale) to a transparent frame
    wraps     on a layout: UIListLayout.Wraps
    valign    on a layout: VerticalAlignment override
    show      mockup states in which a Visible=false node is drawn

Layout numbers are 1920x1080 pixels from design/refs/REFERENCE.md.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
THEME = json.loads((HERE.parent / "ui_theme.json").read_text(encoding="utf-8"))
PAL = THEME["palette"]

TITLE = "LuckiestGuy"
PANEL_R, CARD_R = 12, 8


def C(name, k=0.92):
    """[top, bottom]: the base colour at the top, 8% darker at the bottom.
    Hud_post.py turns this into BackgroundColor3 = top + a neutral gradient, so
    a controller that recolours the frame gets the colour it wrote."""
    h = PAL.get(name, name).lstrip("#")
    rgb = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    low = [int(round(c * k)) for c in rgb]
    return ["#%02X%02X%02X" % tuple(rgb), "#%02X%02X%02X" % tuple(low)]


def F(name, size, pos=None, colour=None, anchor=None, **kw):
    n = {"type": "frame", "name": name, "size": size, "pos": pos or [0, 0, 0, 0]}
    if anchor:
        n["anchor"] = anchor
    if colour:
        n["colour"] = C(colour)
        n.setdefault("corner", CARD_R)
    else:
        n["transparent"] = True
    n.update(kw)
    return n


def L(name, text, size, pos=None, anchor=None, colour="ink", title=True,
      scale=0.85, align="center", stroke=None, **kw):
    n = {"type": "label", "name": name, "text": text, "size": size,
         "pos": pos or [0, 0, 0, 0], "textColour": colour, "align": align,
         "textScale": scale,
         "textStroke": stroke if stroke is not None else (3 if title else 2)}
    if anchor:
        n["anchor"] = anchor
    if title:
        n["font"] = TITLE
    n.update(kw)
    return n


def I(name, icon, side, pos=None, anchor=None, **kw):
    n = {"type": "icon", "name": name, "icon": icon, "size": [0, side, 0, side],
         "pos": pos or [0, 0, 0, 0]}
    if anchor:
        n["anchor"] = anchor
    n.update(kw)
    return n


def hidden(node, *states):
    node["visible"] = False
    node["show"] = list(states)
    return node


CENTRE = [0.5, 0.5]


# ----------------------------------------------------------------- top row

def stat(name, icon, x, text, samples):
    """A number with its icon as a child, hanging off the label's left edge."""
    return L(name, text, [0, 112, 0, 34], [0, x + 36, 0, 43], align="left",
             samples=samples, children=[
                 I("Icon", icon, 28, [0, -8, 0.5, 0], [1, 0.5], overhang=True)])


def xp_bar():
    return F("XPBar", [1, 0, 0, 26], [0, 0, 0, 0], "dark", corner=0, children=[
        F("Fill", [0.72, 0, 1, 0], [0, 0, 0, 0], "xp", corner=0, outline=False, z=1),
        hidden(F("Rainbow", [1, 0, 1, 0], [0, 0, 0, 0], "green", corner=0,
                 outline=False, z=2, overhang=True, rainbow=True)),
    ])


def difficulty_pill():
    return hidden(F("DifficultyPill", [0, 230, 0, 38], [0.5, 0, 0, 92], "header",
                    anchor=[0.5, 0], corner=19, children=[
        L("TierName", "Insane", [0, 116, 0, 30], [0, 14, 0.5, 0], [0, 0.5],
          colour="green", scale=0.9, stroke=2, samples=["Nightmare"]),
        L("TierMult", "x1.45", [0, 56, 0, 30], [1, -12, 0.5, 0], [1, 0.5],
          scale=0.8, stroke=2, align="left", samples=["x9.99"], children=[
              I("Icon", "IconSilver", 26, [0, -6, 0.5, 0], [1, 0.5], overhang=True)]),
    ]), "swarm")


def next_chest():
    return F("NextChest", [0, 150, 0, 40], [1, -232, 0, 42], anchor=[1, 0], children=[
        I("Icon", "IconChest", 36, [0, 0, 0.5, 0], [0, 0.5]),
        L("Price", "1,346", [0, 104, 0, 34], [0, 46, 0.5, 0], [0, 0.5],
          colour="gold", align="left", samples=["99,999"]),
    ])


# ----------------------------------------------------------------- bars

def bar(name, y, colour, text, value):
    return F(name, [0, 250, 0, 30], [0, 20, 0, y], "dark", children=[
        F("Fill", [value, 0, 1, 0], [0, 0, 0, 0], colour, outline=False, z=1),
        L("Text", text, [1, 0, 1, 0], scale=0.8, stroke=2, z=2, overhang=True,
          samples=["9,999/9,999"]),
    ])


def loadout_slot(icon, level):
    return F("LoadoutSlot", [0, 58, 0, 62], children=[
        F("Tile", [0, 50, 0, 50], [0.5, 0, 0, 0], "slot", anchor=[0.5, 0]),
        I("Icon", icon, 50, [0.5, 0, 0, 0], [0.5, 0], z=1, overhang=True),
        L("Level", level, [0, 58, 0, 20], [0.5, 0, 1, 0], [0.5, 1], scale=0.9,
          stroke=2, z=2, overhang=True, samples=["LVL 28"]),
    ])


def loadout_row(name, y, slots):
    return F(name, [0, 288, 0, 62], [0, 20, 0, y],
             layout={"type": "list", "dir": "x", "gap": 8, "align": "start"},
             children=[loadout_slot(i, lv) for i, lv in slots])


# ----------------------------------------------------------------- quests, squad

def quest_line(text, done):
    check = I("Check", "IconCheck", 30, [0, 25, 0.5, 0], CENTRE, z=2, overhang=True)
    if not done:
        hidden(check)
    return F("QuestLine", [1, 0, 0, 48], colour="cardCommon" if done else "dark", children=[
        F("Box", [0, 26, 0, 26], [0, 12, 0.5, 0], "green" if done else "cream",
          anchor=[0, 0.5], corner=6, z=1),
        check,
        L("Text", text, [0, 258, 0, 30], [0, 50, 0.5, 0], [0, 0.5], title=False,
          scale=0.8, align="left", samples=["Find the Boss Portal"]),
    ])


def teammate(portrait, name, hp, downed=False):
    return F("Teammate", [1, 0, 0, 52], children=[
        I("Portrait", portrait, 48, [0, 0, 0.5, 0], [0, 0.5]),
        L("Name", name, [0, 200, 0, 24], [0, 58, 0, 0], align="left", scale=0.85,
          stroke=2, samples=["xX_BonkMaster_2014Xx"]),
        F("HPBack", [0, 200, 0, 14], [0, 58, 0, 34], "dark", corner=7, children=[
            F("HPFill", [hp, 0, 1, 0], [0, 0, 0, 0], "red", corner=7, outline=False)]),
        hidden(L("DownedTag", "DOWN", [0, 60, 0, 24], [0, 266, 0, 0], colour="red",
                 scale=0.85, stroke=2), "swarm"),
    ])


def vlist(gap=8):
    return {"type": "list", "dir": "y", "gap": gap, "align": "start"}


# ----------------------------------------------------------------- minimap

def minimap():
    def letter(t, pos):
        return L(t, t, [0, 26, 0, 26], pos, CENTRE, scale=0.85, stroke=2, z=4,
                 overhang=True)

    def dot(colour, x, y):
        return F("MapDot", [0, 10, 0, 10], [x, 0, y, 0], colour, anchor=CENTRE,
                 corner=3, outline=False, overhang=True)

    inner = [1, -12, 1, -12]
    return F("Minimap", [0, 240, 0, 240], [1, -23, 0, 118], anchor=[1, 0], children=[
        F("Ring", [1, 0, 1, 0], [0, 0, 0, 0], "tan", corner=0.5),
        F("Field", inner, [0.5, 0, 0.5, 0], "#0E1626", anchor=CENTRE, corner=0.5,
          outline=False, z=1, overhang=True),
        F("Dots", inner, [0.5, 0, 0.5, 0], anchor=CENTRE, z=2, overhang=True,
          props={"ClipsDescendants": True}, round=0.5, children=[
              dot("gold", 0.66, 0.16), dot("green", 0.60, 0.76), dot("red", 0.74, 0.46)]),
        I("PlayerArrow", "IconArrowPlayer", 30, [0.5, 0, 0.5, 0], CENTRE, z=3,
          overhang=True),
        letter("N", [0.5, 0, 0, -2]), letter("E", [1, 2, 0.5, 0]),
        letter("S", [0.5, 0, 1, 2]), letter("W", [0, -2, 0.5, 0]),
    ])


# ----------------------------------------------------------------- items, bosses

def item_slot(icon, count):
    return F("ItemSlot", [0, 56, 0, 56], children=[
        I("Icon", icon, 48, [0.5, 0, 0.5, 0], CENTRE),
        L("Count", count, [0, 30, 0, 20], [1, 0, 1, 0], [1, 1], scale=0.95,
          stroke=2, align="right", z=2, overhang=True, samples=["x99"]),
    ])


def item_strip():
    return F("ItemStrip", [0, 1200, 0, 56], [0.5, 0, 1, -37], anchor=[0.5, 1],
             layout={"type": "list", "dir": "x", "gap": 19, "align": "center",
                     "wraps": True, "valign": "Bottom"},
             children=[item_slot("IconItemZoomSocks", "x1"),
                       item_slot("IconItemLuckyClover", "x2"),
                       item_slot("IconItemStinkyCheese", "x3")])


def boss_bar(name, w, title, text, value, name_h, extra=None):
    kids = [
        L("Name", title, [1, 0, 0, name_h], samples=["Chunkham the Terrible"],
          scale=0.9, stroke=2 if name_h < 30 else 3),
        F("Back", [1, 0, 0, 30], [0, 0, 0, name_h + 8], "dark", children=[
            F("Fill", [value, 0, 1, 0], [0, 0, 0, 0], "red", outline=False)]),
        L("Text", text, [1, 0, 0, 30], [0, 0, 0, name_h + 8], scale=0.8, stroke=2,
          z=2, overhang=True, samples=["17,5K / 18,4K"]),
    ]
    return F(name, [0, w, 0, name_h + 38], **(extra or {}), children=kids)


def boss_bars():
    minis = F("Minis", [1, 0, 0, 64],
              layout={"type": "list", "dir": "x", "gap": 20, "align": "center"},
              children=[boss_bar("MiniBar", 385, "Lil Bark", "17,1K / 18,4K", 0.93, 26),
                        boss_bar("MiniBar", 385, "Lil Bark", "17,5K / 18,4K", 0.95, 26),
                        boss_bar("MiniBar", 385, "Chunkham the Terrible",
                                 "4.509 / 4.736", 0.95, 26)])
    main = boss_bar("Main", 1196, "Chunkham the Terrible", "4.432 / 4.736", 0.936, 30,
                    extra={"pos": [0, 0, 0, 76]})
    return hidden(F("BossBars", [0, 1196, 0, 144], [0.5, 0, 0, 140], anchor=[0.5, 0],
                    children=[minis, main]), "swarm")


# ----------------------------------------------------------------- prompts, cards

def interact_prompt():
    return hidden(F("InteractPrompt", [0, 470, 0, 56], [0.5, 0, 1, -180], "panel",
                    anchor=[0.5, 1], corner=PANEL_R, children=[
        F("KeyCap", [0, 40, 0, 40], [0, 10, 0.5, 0], "grey", anchor=[0, 0.5]),
        L("Key", "E", [0, 40, 0, 40], [0, 10, 0.5, 0], [0, 0.5], scale=0.75,
          stroke=2, z=2, overhang=True),
        L("Text", "Open chest (1,346 gold)", [0, 396, 0, 36], [0, 62, 0.5, 0],
          [0, 0.5], title=False, scale=0.8, align="left"),
    ]), "levelup")


def banner():
    return hidden(F("Banner", [0, 1200, 0, 112], [0.5, 0, 0, 304], anchor=[0.5, 0],
                    z=6, children=[
        L("BannerText", "FINAL HORDE INCOMING!", [1, 0, 0, 72], colour="red",
          scale=0.95),
        L("BannerSub", "Hold out until the portal opens", [1, 0, 0, 32],
          [0, 0, 0, 80], title=False, scale=0.85),
    ]), "swarm")


def stage_title():
    def rule(name, y):
        return F(name, [0, 620, 0, 4], [0.5, 0, 0, y], "cream", anchor=[0.5, 0],
                 corner=2, outline=False)

    return hidden(F("StageTitle", [0, 1000, 0, 208], [0.5, 0, 0.5, 0], anchor=CENTRE,
                    z=7, overhang=True, children=[
        L("TierLabel", "Tier 1", [1, 0, 0, 40], colour="tan", scale=0.9),
        rule("RuleTop", 52),
        L("StageName", "MOSSY WOODS", [1, 0, 0, 84], [0, 0, 0, 66], scale=0.95,
          samples=["CRUMBLY GRAVEYARD"]),
        rule("RuleBottom", 160),
        L("StageJoke", "Now with 40% more moss than the leading forest",
          [1, 0, 0, 34], [0, 0, 0, 174], title=False, colour="inkSoft", scale=0.85),
    ]), "stage")


def letterbox():
    def strip(name, pos, anchor):
        return F(name, [1, 0, 0, 110], pos, "#000000", anchor=anchor, corner=0,
                 outline=False, flat=True)

    return hidden(F("Letterbox", [1, 0, 1, 0], z=5, overhang=True, children=[
        strip("Top", [0, 0, 0, 0], [0, 0]),
        strip("Bottom", [0, 0, 1, 0], [0, 1]),
    ]), "stage")


def toast():
    def rivet(x, y, ax, ay):
        return F("Rivet", [0, 8, 0, 8], [ax, x, ay, y], "grey", anchor=[ax, ay],
                 corner=0.5, outline=False, overhang=True)

    return hidden(F("Toast", [0, 390, 0, 112], [0, 10, 0, 8], "panel", corner=PANEL_R,
                    z=10, overhang=True, children=[
        I("ToastPortrait", "IconSkull", 88, [0, 14, 0.5, 0], [0, 0.5]),
        L("ToastTitle", "Calcium", [0, 258, 0, 34], [0, 114, 0, 14], colour="tan",
          align="left", samples=["Certified Bonker"]),
        L("ToastText", "Kill 1,000 skeletons", [0, 258, 0, 44], [0, 114, 0, 56],
          title=False, align="left", scale=0.5, wrap=True,
          samples=["Open 25 chests without dying once"]),
        rivet(6, 6, 0, 0), rivet(-6, 6, 1, 0), rivet(6, -6, 0, 1), rivet(-6, -6, 1, 1),
    ]), "swarm")


def downed_overlay():
    return hidden(F("DownedOverlay", [1, 0, 1, 0], colour="#000000", corner=0,
                    outline=False, flat=True, alpha=0.45, z=20, overhang=True, children=[
        L("DownedLabel", "YOU ARE DOWN", [0, 1000, 0, 110], [0.5, 0, 0.36, 0],
          CENTRE, colour="red", scale=0.9),
        F("ReviveBack", [0, 520, 0, 30], [0.5, 0, 0.36, 75], "dark", anchor=[0.5, 0],
          children=[F("ReviveFill", [0.4, 0, 1, 0], [0, 0, 0, 0], "green",
                      outline=False)]),
        L("SpectateName", "Spectating xX_BonkMaster_2014Xx", [0, 800, 0, 40],
          [0.5, 0, 0.36, 115], [0.5, 0], scale=0.85),
    ]), "downed")


# ----------------------------------------------------------------- the page

def children():
    return [
        xp_bar(),
        stat("RunClock", "IconClock", 22, "12:34", ["59:59"]),
        stat("SilverCount", "IconSilver", 180, "9,999", ["9,999"]),
        stat("GoldCount", "IconGold", 340, "99,999", ["99,999"]),
        stat("KillCount", "IconSkull", 500, "99,999", ["99,999"]),
        L("StageTimer", "9:37", [0, 240, 0, 44], [0.5, 0, 0, 40], [0.5, 0],
          scale=1.0, samples=["10:00"]),
        difficulty_pill(),
        next_chest(),
        L("LevelLabel", "LVL 101", [0, 200, 0, 44], [1, -20, 0, 40], [1, 0],
          scale=1.0, align="right"),
        bar("ShieldBar", 95, "shield", "205/205", 1.0),
        bar("HPBar", 133, "red", "199/199", 0.86),
        loadout_row("WeaponRow", 171, [("IconSword", "LVL 28"),
                                       ("IconLightningStaff", "LVL 6"),
                                       ("IconBoomernana", "LVL 2")]),
        loadout_row("TomeRow", 241, [("IconTomeDamage", "LVL 7"),
                                     ("IconTomeAgility", "LVL 5")]),
        F("QuestTracker", [0, 320, 0, 160], [0, 20, 0, 311], layout=vlist(),
          children=[quest_line("Find the Boss Portal", False),
                    quest_line("Defeat the Boss", True)]),
        F("TeammateBars", [0, 326, 0, 172], [0, 20, 0, 480], layout=vlist(),
          children=[teammate("PortraitFox", "FoxyMcBonk", 0.8),
                    teammate("PortraitFrostling", "xX_BonkMaster_2014Xx", 0.35),
                    teammate("PortraitKnight", "SirClonkALot", 0.0, True)]),
        minimap(),
        item_strip(),
        boss_bars(),
        interact_prompt(),
        banner(),
        stage_title(),
        letterbox(),
        toast(),
        hidden(L("PickupToast", "MAGNET", [0, 420, 0, 44], [0.5, 0, 0.41, 0], CENTRE,
                 colour="gold", z=8, overhang=True), "levelup"),
        downed_overlay(),
        F("HurtFlash", [1, 0, 1, 0], colour="red", corner=0, outline=False,
          flat=True, alpha=1, z=30, overhang=True),
        hidden(L("LevelUpText", "LEVEL UP!", [0, 800, 0, 110], [0.5, 0, 0.33, 0],
                 CENTRE, colour="gold", z=9, overhang=True), "levelup"),
    ]


def page(name, kids):
    return {"name": name, "theme": "../ui_theme.json", "resolution": [1920, 1080],
            "kind": "hud", "displayOrder": 10, "ignoreGuiInset": True,
            "enabled": True, "children": kids}


def for_state(nodes, state):
    out = []
    for n in nodes:
        if n.get("visible") is False and state not in n.get("show", []):
            continue
        n = dict(n)
        if n.get("children"):
            n["children"] = for_state(n["children"], state)
        out.append(n)
    return out


STATES = ["play", "swarm", "stage", "downed", "levelup"]


def main():
    full = children()
    (HERE / "Hud.json").write_text(json.dumps(page("Hud", full), indent=1),
                                   encoding="utf-8")
    for st in STATES:
        kids = for_state(copy.deepcopy(full), st)
        (HERE / f"Hud_{st}.json").write_text(
            json.dumps(page(f"Hud_{st}", kids), indent=1), encoding="utf-8")
    print("wrote Hud.json and", ", ".join(f"Hud_{s}.json" for s in STATES))


if __name__ == "__main__":
    main()

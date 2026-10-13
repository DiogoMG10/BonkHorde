"""Build the Menu, EndScreens and Overlay ScreenGuis for Bonk Horde.

    D:\\Forge\\system\\python\\python.exe design/ui_specs/Menu_build.py

One run does everything, from one resolved tree per screen:
  1. writes one roblox-ui spec per screen       design/ui_specs/<Gui>.<Screen>.json
  2. renders one mockup per screen               assets/ui/mockups/<Gui>.<Screen>.png
  3. emits and MERGES the screens per ScreenGui  src/ui/<Gui>.model.json
  4. emits the Luau builder per ScreenGui        design/ui_specs/<Gui>.build.lua
  5. writes assets/ui/manifest.Menu.json
  6. runs verify_ui.check on every spec and the contract name check

The PNG, the .model.json and the Luau all come out of the skill's ui_build.py
functions (resolve / render / to_instances). What this file adds on top is listed
in assets/ui/NOTES.Menu.md: spec keys the skill does not know (font, cls, attrs,
props, clips, mockShow) are applied in a wrapper round ui_build.to_instances, so
they still reach the model and the Luau from the same node.
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

SKILL = Path(r"C:\Users\diogo\.claude\skills\roblox-ui\scripts")
sys.path.insert(0, str(SKILL))
import ui_build as ub  # noqa: E402
import verify_ui as vu  # noqa: E402
from PIL import ImageDraw  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SPECS = ROOT / "design" / "ui_specs"
MOCKS = ROOT / "assets" / "ui" / "mockups"
UI = ROOT / "src" / "ui"
RES = [1920, 1080]
THEME_REF = "../ui_theme.json"
TITLE = "LuckiestGuy"
WHITE = ["#FFFFFF", "#FFFFFF"]
BLACK = ["#000000", "#000000"]
DARKINK = "#101512"

# ------------------------------------------------------------------ spec helpers


def lab(name, text, size, pos=None, anchor=None, px=28, h=None, font="body",
        colour="ink", align="left", stroke=None, samples=None, **kw):
    """A label. px is the designed text height; h is the box height in pixels
    (taken from the offset size unless the size is scale based)."""
    h = h or size[3]
    node = {"type": "label", "name": name, "text": text, "size": size,
            "textColour": colour, "align": align,
            "textScale": round(px / h, 4)}
    if pos:
        node["pos"] = pos
    if anchor:
        node["anchor"] = anchor
    smp = list(samples or [])
    if font == "title":
        node["font"] = TITLE
        # LuckiestGuy draws lower case as capitals, and the preview font is
        # Fredoka, so the fit is measured on the upper-cased string as well.
        smp += [s.upper() for s in [text] + smp if s.upper() != s]
        node["textStroke"] = stroke if stroke is not None else (3 if px >= 32 else 2)
    else:
        node["textStroke"] = stroke if stroke is not None else 0
    if smp:
        node["samples"] = smp
    node.update(kw)
    return node


def ico(name, key, side, pos=None, anchor=None, **kw):
    node = {"type": "icon", "name": name, "icon": key, "size": [0, side, 0, side]}
    if pos:
        node["pos"] = pos
    if anchor:
        node["anchor"] = anchor
    node.update(kw)
    return node


def fr(name, size, pos=None, anchor=None, colour=None, children=None, **kw):
    node = {"type": "frame", "name": name, "size": size}
    if pos:
        node["pos"] = pos
    if anchor:
        node["anchor"] = anchor
    if colour:
        node["colour"] = colour
    else:
        node["transparent"] = True
    if children:
        node["children"] = children
    node.update(kw)
    return node


def btn(name, text, colour, size, pos=None, anchor=None, px=44, children=None, **kw):
    node = {"type": "button", "name": name, "colour": colour, "size": size,
            "corner": 8, "font": TITLE, "textStroke": 3,
            "textScale": round(px / size[3], 4)}
    if text:
        node["text"] = text
    if pos:
        node["pos"] = pos
    if anchor:
        node["anchor"] = anchor
    if children:
        node["children"] = children
    node.update(kw)
    return node


def rivets():
    out = []
    for ax, ay in ((0, 0), (1, 0), (0, 1), (1, 1)):
        out.append(fr("Rivet", [0, 10, 0, 10],
                      [ax, 14 if ax == 0 else -14, ay, 14 if ay == 0 else -14], [ax, ay],
                      colour=["#B9BCB5", "#7C7F79"], corner=0.5, outline=False,
                      overhang=True))
    return out


def brackets(name="Focus", out=10, arm=22, t=5, **kw):
    """Four white corner brackets round the parent."""
    kids = []
    for ax, ay in ((0, 0), (1, 0), (0, 1), (1, 1)):
        for w, h in ((arm, t), (t, arm)):
            kids.append(fr("Bracket", [0, w, 0, h], [ax, 0, ay, 0], [ax, ay],
                           colour=WHITE, corner=0, outline=False, overhang=True))
    return fr(name, [1, 2 * out, 1, 2 * out], [0.5, 0, 0.5, 0], [0.5, 0.5],
              children=kids, overhang=True, **kw)


def panel(name, size, pos, anchor, children=None, title=None, **kw):
    kids = []
    if title:
        kids.append(fr("Header", [1, -20, 0, 64], [0, 10, 0, 10], colour="header",
                       corner=8, children=[
                           lab("Title", title, [1, -150, 1, 0], [0, 24, 0, 0], px=36,
                               h=64, font="title")]))
    kids += rivets()
    kids += children or []
    return {"type": "panel", "name": name, "colour": "panel", "corner": 12,
            "size": size, "pos": pos, "anchor": anchor, "children": kids, **kw}


def screen(name, children, visible, colour=None, **kw):
    node = fr(name, [1, 0, 1, 0], colour=colour, children=children, modal=True, **kw)
    if colour:
        node.update({"corner": 0, "outline": False})
    if not visible:
        node.update({"visible": False, "mockShow": True})
    return node


def chip(name, text, colour, w, pos=None, anchor=None, **kw):
    return fr(name, [0, w, 0, 40], pos, anchor, colour=colour, corner=8, children=[
        lab("Text", text, [1, -16, 1, 0], [0.5, 0, 0.5, 0], [0.5, 0.5], px=30, h=40,
            colour=DARKINK, align="center")],
        **kw)


# ------------------------------------------------------------------ Menu

def main_menu():
    def squad_row(player, hero, portrait, host, ready):
        tag_kw_h = {} if host else {"visible": False}
        tag_kw_r = {} if ready else {"visible": False}
        return {"type": "panel", "name": "SquadRow", "colour": "panel", "corner": 8,
                "size": [0, 540, 0, 104], "children": [
                    ico("Portrait", portrait, 80, [0, 12, 0.5, 0], [0, 0.5]),
                    lab("Name", player, [0, 424, 0, 38], [0, 104, 0, 8], px=30,
                        samples=["xX_BonkMaster2012_Xx"]),
                    lab("Hero", hero, [0, 166, 0, 40], [0, 104, 0, 54], px=30,
                        colour="tan", samples=["Sir Clonk"]),
                    chip("ReadyTag", "READY", "green", 132, [0, 278, 0, 54], **tag_kw_r),
                    chip("HostTag", "HOST", "gold", 110, [0, 418, 0, 54], **tag_kw_h),
                ]}

    logo = fr("LogoBanner", [0, 720, 0, 170], [0, 80, 0, 120], rotation=-5, children=[
        fr("Lip", [1, 0, 1, 0], [0, 8, 0, 12], colour=[DARKINK, DARKINK], corner=14,
           outline=False, overhang=True),
        fr("Strip", [1, 0, 1, 0], colour=["#FFFFFF", "#E6EAE3"], corner=14, children=[
            lab("Wordmark", "BONK HORDE", [1, -56, 1, -28], [0.5, 0, 0.5, 0], [0.5, 0.5],
                px=104, h=142, font="title", colour=DARKINK, align="center", stroke=0)]),
    ])
    kids = [
        logo,
        btn("PlayButton", "PLAY", "blue", [0, 420, 0, 132], [0, 120, 0.5, 90], [0, 0.5],
            px=80),
        lab("SquadTitle", "SQUAD", [0, 540, 0, 48], [1, -60, 0.5, -208], [1, 0.5],
            px=40, font="title"),
        fr("SquadList", [0, 540, 0, 336], [1, -60, 0.5, 0], [1, 0.5],
           layout={"type": "list", "dir": "y", "gap": 12}, children=[
               squad_row("xX_BonkMaster2012_Xx", "Sir Clonk", "PortraitKnight", True, True),
               squad_row("Zibby", "Zib", "PortraitFox", False, True),
               squad_row("mint_enjoyer", "Mint", "PortraitFrostling", False, False)]),
        lab("SilverTotal", "9,999", [0, 170, 0, 52], [1, -36, 0, 44], [1, 0], px=44,
            font="title", samples=["99,999"], children=[
                ico("Icon", "IconSilver", 48, [0, -58, 0.5, 0], [0, 0.5], overhang=True)]),
        lab("VersionLabel", "version 0.1.0", [0, 280, 0, 36], [1, -16, 1, -12], [1, 1],
            px=30, align="right", stroke=2),
    ]
    return screen("MainMenu", kids, True)


HEROES = [("Sir Clonk", "PortraitKnight"), ("Zib", "PortraitFox"),
          ("Mint", "PortraitFrostling")]


def character_select():
    def portrait_tile(name, key, focus):
        fkw = {"visible": False}
        if focus:
            fkw["mockShow"] = True
        return btn("PortraitTile", "", "panelAlt", [0, 126, 0, 126], aspect=1.0, children=[
            ico("Portrait", key, 84, [0.5, 0, 0, 4], [0.5, 0]),
            lab("Name", name, [1, -8, 0, 26], [0.5, 0, 1, -4], [0.5, 1], px=22,
                font="title", align="center", samples=["Sir Clonk"]),
            brackets("Focus", out=8, **fkw)])

    def locked_tile():
        sil = ["#070A08", "#070A08"]
        return btn("LockedTile", "", "slot", [0, 126, 0, 126], aspect=1.0, children=[
            fr("Silhouette", [0, 84, 0, 84], [0.5, 0, 0, 4], [0.5, 0], children=[
                fr("Head", [0, 40, 0, 40], [0.5, 0, 0, 6], [0.5, 0], colour=sil,
                   corner=0.5, outline=False, overhang=True),
                fr("Shoulders", [0, 72, 0, 36], [0.5, 0, 1, 0], [0.5, 1], colour=sil,
                   corner=16, outline=False)]),
            lab("Name", "??", [1, -8, 0, 26], [0.5, 0, 1, -4], [0.5, 1], px=22,
                font="title", colour="inkSoft", align="center"),
            ico("Padlock", "IconPadlock", 36, [0.5, 0, 0, 28], [0.5, 0], overhang=True)])

    tiles = [portrait_tile(n, k, i == 0) for i, (n, k) in enumerate(HEROES)]
    tiles += [locked_tile() for _ in range(17)]

    def ability_row(name, key, title, text, y, samples):
        return fr(name, [0, 509, 0, 88], [0, 28, 0, y], children=[
            fr("Well", [0, 88, 0, 88], colour="slot", corner=8, overhang=True),
            ico("Icon", key, 72, [0, 8, 0, 8]),
            lab("Name", title, [0, 405, 0, 38], [0, 104, 0, 2], px=32, font="title",
                colour="gold"),
            lab("Text", text, [0, 405, 0, 38], [0, 104, 0, 48], px=30, colour="inkSoft",
                samples=samples)])

    card = panel("DetailCard", [0, 565, 0, 744], [1, -77, 0.5, 0], [1, 0.5], children=[
        fr("PortraitWell", [0, 124, 0, 124], [0, 28, 0, 28], colour="slot", corner=8,
           overhang=True),
        ico("Portrait", "PortraitKnight", 108, [0, 36, 0, 36]),
        lab("CharacterName", "Sir Clonk", [0, 365, 0, 52], [0, 172, 0, 28], px=44,
            font="title"),
        lab("RunCount", "5 Runs", [0, 300, 0, 38], [0, 216, 0, 96], px=30,
            colour="inkSoft", samples=["999 Runs"], children=[
                ico("Icon", "IconRun", 36, [0, -44, 0.5, 0], [0, 0.5], overhang=True)]),
        lab("Blurb", "Slow as a fridge, but all that armor makes him very hard to bonk.",
            [0, 509, 0, 72], [0, 28, 0, 164], px=30, wrap=True),
        ability_row("StartWeaponRow", "IconSword", "Sword",
                    "Slashes through multiple enemies", 248, []),
        ability_row("PassiveRow", "IconPassive", "Thick Plating",
                    "Gain 1% Armor per level.", 348,
                    ["Gain 0.5% Freeze Chance per level."]),
        btn("UnlockButton", "", "skip", [0, 340, 0, 116], [0.5, 0, 0, 452], [0.5, 0],
            visible=False, mockShow=True, children=[
                ico("Icon", "IconSilver", 56, [0, 22, 0.5, 0], [0, 0.5]),
                lab("Label", "UNLOCK 150", [0, 230, 0, 116], [0, 90, 0, 0], px=40,
                    font="title", samples=["UNLOCK 9,999"])]),
        btn("ConfirmButton", "CONFIRM", "blue", [0, 340, 0, 116], [0.5, 0, 1, -34],
            [0.5, 1], px=52),
    ])
    kids = [
        panel("ListPanel", [0, 640, 0, 862], [0, 65, 0.5, 0], [0, 0.5],
              title="CHARACTER SELECTION", overhang=True),
        btn("CloseButton", "X", "banish", [0, 116, 0, 116], [0, 609, 0.5, -397], [0, 0.5],
            px=64),
        fr("CharacterGrid", [0, 567, 0, 714], [0, 101, 0.5, 31], [0, 0.5],
           layout={"type": "grid", "cell": [126, 126], "cols": 4, "gap": 21},
           children=tiles),
        card,
    ]
    return screen("CharacterSelect", kids, False)


MAPS = [
    ("Mossy Woods", "ThumbMossyWoods",
     "A green place full of trees, birds and great vibes. Also everything will try to bonk you.",
     False),
    ("Dusty Dunes", "ThumbDesert", "A hot, dry and dusty place. Coming soon.", True),
    ("Spooky Yard", "ThumbGraveyard", "The home of ghosts and other spooks. Coming soon.",
     True),
]


def map_select():
    def map_row(name, key, blurb, locked):
        lkw = {"visible": False}
        if locked:
            lkw["mockShow"] = True
        return btn("MapRow", "", "slot", [0, 576, 0, 160], children=[
            ico("Thumb", key, 136, [0, 12, 0.5, 0], [0, 0.5]),
            lab("Name", name, [0, 244, 0, 40], [0, 164, 0, 12], px=32, font="title"),
            lab("Blurb", blurb, [0, 400, 0, 88], [0, 164, 0, 60], px=24,
                colour="inkSoft", wrap=True),
            chip("LockTag", "LOCKED", "banish", 148, [1, -12, 0, 12], [1, 0], **lkw)])

    def ready_row(player, state, colour):
        return fr("ReadyRow", [0, 509, 0, 56], colour="slot", corner=8, children=[
            lab("Name", player, [0, 316, 0, 38], [0, 16, 0.5, 0], [0, 0.5], px=30,
                samples=["xX_BonkMaster2012_Xx"]),
            lab("State", state, [0, 150, 0, 38], [1, -16, 0.5, 0], [1, 0.5], px=30,
                colour=colour, align="right", samples=["choosing"])])

    card = panel("DetailCard", [0, 565, 0, 744], [1, -77, 0.5, 0], [1, 0.5], children=[
        lab("MapName", "Mossy Woods", [0, 509, 0, 56], [0, 28, 0, 28], px=48,
            font="title", colour="gold"),
        lab("TierLabel", "Tier 1", [0, 300, 0, 38], [0, 28, 0, 92], px=30, font="title",
            colour="tan"),
        fr("ScoreBox", [0, 509, 0, 112], [0, 28, 0, 142], colour="slot", corner=8,
           overhang=True),
        lab("HighscoreCaption", "Highscore", [0, 220, 0, 36], [0, 48, 0, 148], px=30,
            colour="inkSoft"),
        lab("BestTimeCaption", "Best time", [0, 200, 0, 36], [0, 300, 0, 148], px=30,
            colour="inkSoft"),
        lab("Highscore", "5,864", [0, 180, 0, 48], [0, 96, 0, 192], px=40, font="title",
            colour="gold", samples=["99,999"], children=[
                ico("Icon", "IconSkull", 40, [0, -48, 0.5, 0], [0, 0.5], overhang=True)]),
        lab("BestTime", "8:42", [0, 200, 0, 48], [0, 300, 0, 192], px=40, font="title",
            samples=["59:59"]),
        lab("StageCount", "Stages: 1", [0, 400, 0, 38], [0.5, 0, 0, 268], [0.5, 0],
            px=30, align="center"),
        lab("ReadyTitle", "SQUAD", [0, 300, 0, 36], [0, 28, 0, 318], px=30, font="title",
            colour="tan"),
        fr("ReadyList", [0, 509, 0, 184], [0, 28, 0, 362],
           layout={"type": "list", "dir": "y", "gap": 8}, children=[
               ready_row("xX_BonkMaster2012_Xx", "ready", "green"),
               ready_row("Zibby", "ready", "green"),
               ready_row("mint_enjoyer", "choosing", "tan")]),
        btn("ConfirmButton", "READY", "blue", [0, 340, 0, 116], [0.5, 0, 1, -34],
            [0.5, 1], px=52),
    ])
    kids = [
        panel("ListPanel", [0, 640, 0, 816], [0, 65, 0.5, 0], [0, 0.5],
              title="MAP SELECTION", overhang=True),
        btn("CloseButton", "X", "banish", [0, 116, 0, 116], [0, 609, 0.5, -374], [0, 0.5],
            px=64),
        fr("MapList", [0, 576, 0, 512], [0, 97, 0.5, -50], [0, 0.5],
           layout={"type": "list", "dir": "y", "gap": 16},
           children=[map_row(*m) for m in MAPS]),
        card,
    ]
    return screen("MapSelect", kids, False)


# ------------------------------------------------------------------ EndScreens

def death_screen():
    kids = [
        lab("DeathTitle", "you got bonked", [0, 1000, 0, 96], [0.5, 0, 0, 70], [0.5, 0],
            px=80, font="title", colour="#D8DAD6", align="center"),
        lab("DeathJoke", "maybe try bonking them first?", [0, 1200, 0, 40],
            [0.5, 0, 0, 176], [0.5, 0], px=30, colour="inkSoft", align="center",
            samples=["the goblins would like to thank you for your contribution"]),
        fr("HeroViewport", [0, 500, 0, 600], [0.5, 0, 0.5, 0], [0.5, 0.5],
           cls="ViewportFrame"),
        btn("ConfirmButton", "CONFIRM", "grey", [0, 320, 0, 116], [0.5, 0, 1, -104],
            [0.5, 1], px=52, children=[brackets("Focus", out=14)]),
    ]
    return screen("DeathScreen", kids, False, colour=BLACK)


def results():
    def stat(name, caption, value, samples):
        return fr(name, [0, 218, 0, 116], colour="slot", corner=8, children=[
            lab("Label", caption, [1, -16, 0, 36], [0.5, 0, 0, 6], [0.5, 0], px=30,
                colour="tan", align="center"),
            lab("Value", value, [1, -16, 0, 56], [0.5, 0, 0, 52], [0.5, 0], px=46,
                font="title", align="center", samples=samples)])

    def player_row(player, portrait, kills, dmg, silver):
        return fr("PlayerRow", [0, 920, 0, 84], colour="slot", corner=8, children=[
            ico("Portrait", portrait, 64, [0, 12, 0.5, 0], [0, 0.5]),
            lab("Name", player, [0, 308, 0, 40], [0, 92, 0.5, 0], [0, 0.5], px=30,
                samples=["xX_BonkMaster2012_Xx"]),
            lab("Kills", kills, [0, 120, 0, 44], [0, 416, 0.5, 0], [0, 0.5], px=34,
                font="title", samples=["99,999"]),
            lab("Damage", dmg, [0, 176, 0, 44], [0, 552, 0.5, 0], [0, 0.5], px=34,
                font="title", samples=["1,234,567"]),
            lab("Silver", silver, [0, 112, 0, 44], [0, 796, 0.5, 0], [0, 0.5], px=34,
                font="title", samples=["9,999"], children=[
                    ico("Icon", "IconSilver", 40, [0, -48, 0.5, 0], [0, 0.5],
                        overhang=True)]),
        ])

    heads = fr("ColumnHeads", [0, 920, 0, 36], [0.5, 0, 0.5, -124], [0.5, 0.5], children=[
        lab("HeadPlayer", "PLAYER", [0, 308, 0, 36], [0, 92, 0, 0], px=30, colour="tan"),
        lab("HeadKills", "KILLS", [0, 120, 0, 36], [0, 416, 0, 0], px=30, colour="tan"),
        lab("HeadDamage", "DAMAGE", [0, 176, 0, 36], [0, 552, 0, 0], px=30, colour="tan"),
        lab("HeadSilver", "SILVER", [0, 112, 0, 36], [0, 796, 0, 0], px=30, colour="tan"),
    ])
    kids = [
        panel("Panel", [0, 1000, 0, 780], [0.5, 0, 0.5, 0], [0.5, 0.5], overhang=True),
        lab("ResultTitle", "VICTORY", [0, 800, 0, 88], [0.5, 0, 0.5, -324], [0.5, 0.5],
            px=76, font="title", colour="gold", align="center",
            samples=["YOU GOT BONKED"]),
        fr("StatTable", [0, 920, 0, 116], [0.5, 0, 0.5, -208], [0.5, 0.5],
           layout={"type": "list", "dir": "x", "gap": 16, "align": "center"}, children=[
               stat("Kills", "Kills", "12,345", ["99,999"]),
               stat("Level", "Level", "LVL 24", ["LVL 101"]),
               stat("Time", "Time", "14:19", ["59:59"]),
               stat("BossTime", "Boss time", "9:37", ["59:59"])]),
        heads,
        fr("PlayerRows", [0, 920, 0, 268], [0.5, 0, 0.5, 38], [0.5, 0.5],
           layout={"type": "list", "dir": "y", "gap": 8}, children=[
               player_row("xX_BonkMaster2012_Xx", "PortraitKnight", "6,204", "412,880",
                          "312"),
               player_row("Zibby", "PortraitFox", "4,117", "288,402", "240"),
               player_row("mint_enjoyer", "PortraitFrostling", "2,024", "97,115", "121")]),
        lab("ContinueLabel", "Back to the lobby in 12", [0, 800, 0, 40],
            [0.5, 0, 0.5, 340], [0.5, 0.5], px=30, colour="inkSoft", align="center"),
    ]
    return screen("Results", kids, False, colour=BLACK, alpha=0.45)


# ------------------------------------------------------------------ Overlay

def big_map():
    def letter(ch, pos):
        return lab(ch, ch, [0, 44, 0, 44], pos, [0.5, 0.5], px=36, font="title",
                   align="center", overhang=True)

    def legend_item(key, text):
        return fr("LegendItem", [0, 164, 0, 36], children=[
            ico("Icon", key, 28, [0, 0, 0.5, 0], [0, 0.5]),
            lab("Text", text, [0, 128, 0, 36], [0, 36, 0, 0], px=30, colour="inkSoft")])

    return fr("BigMap", [0, 760, 0, 760], [0, 20, 0.5, 50], [0, 0.5],
              colour=["#101815", "#0A0F0D"], corner=12, visible=False, mockShow=True,
              children=[
                  fr("Dots", [1, -12, 1, -12], [0.5, 0, 0.5, 0], [0.5, 0.5], clips=True),
                  ico("PlayerArrow", "IconArrowPlayer", 36, [0.5, 0, 0.5, 0], [0.5, 0.5],
                      overhang=True),
                  letter("N", [0.5, 0, 0, 0]), letter("E", [1, 0, 0.5, 0]),
                  letter("S", [0.5, 0, 1, 0]), letter("W", [0, 0, 0.5, 0]),
                  fr("Legend", [0, 188, 0, 236], [0, 24, 1, -34], [0, 1], colour="panel",
                     corner=8, alpha=0.15, overhang=True, padding=12,
                     layout={"type": "list", "dir": "y", "gap": 8, "align": "start"},
                     children=[legend_item("IconMapChest", "Chest"),
                               legend_item("IconMapShrine", "Shrine"),
                               legend_item("IconMapBoss", "Boss"),
                               legend_item("IconMapVendor", "Vendor"),
                               legend_item("IconMapTeammate", "Squad")]),
              ])


def pause_menu():
    def slider(name, caption, value, y):
        return [
            lab(name.replace("Slider", "Label"), caption, [0, 480, 0, 36],
                [0.5, 0, 0.5, y], [0.5, 0.5], px=30, colour="tan"),
            fr(name, [0, 480, 0, 36], [0.5, 0, 0.5, y + 44], [0.5, 0.5], colour="slot",
               corner=0.5, children=[
                   fr("Fill", [value, 0, 1, 0], colour="blue", corner=0.5, outline=False),
                   fr("Knob", [0, 52, 0, 52], [value, 0, 0.5, 0], [0.5, 0.5],
                      colour=["#FFFFFF", "#D4DAD4"], corner=0.5, overhang=True)]),
        ]

    kids = [
        panel("Panel", [0, 620, 0, 840], [0.5, 0, 0.5, 0], [0.5, 0.5], title="PAUSED",
              overhang=True),
        btn("ResumeButton", "RESUME", "blue", [0, 480, 0, 116], [0.5, 0, 0.5, -268],
            [0.5, 0.5], px=46),
        *slider("MusicSlider", "Music", 0.7, -172),
        *slider("SfxSlider", "Sound effects", 0.8, -68),
        *slider("SensitivitySlider", "Camera sensitivity", 0.5, 36),
        btn("DamageNumbersToggle", "", "slot", [0, 480, 0, 116], [0.5, 0, 0.5, 184],
            [0.5, 0.5], children=[
                fr("Box", [0, 56, 0, 56], [0, 20, 0.5, 0], [0, 0.5], colour="dark",
                   corner=8),
                ico("Check", "IconCheck", 44, [0, 26, 0.5, 0], [0, 0.5], overhang=True),
                lab("Label", "Damage numbers", [0, 360, 0, 116], [0, 96, 0, 0], px=32)]),
        btn("LeaveButton", "LEAVE RUN", "banish", [0, 480, 0, 116], [0.5, 0, 0.5, 328],
            [0.5, 0.5], px=46),
    ]
    return screen("PauseMenu", kids, False, colour=BLACK, alpha=0.5)


def touch_controls():
    def pad(name, text, side, pos, anchor, px):
        return btn(name, text, "grey", [0, side, 0, side], pos, anchor, px=px,
                   corner=0.5, alpha=0.25)

    node = fr("TouchControls", [1, 0, 1, 0], visible=False, mockShow=True, children=[
        pad("JumpButton", "JUMP", 140, [1, -70, 1, -70], [1, 1], 38),
        pad("SlideButton", "SLIDE", 132, [1, -234, 1, -50], [1, 1], 34),
        pad("InteractButton", "USE", 132, [1, -54, 1, -234], [1, 1], 38),
        pad("TabButton", "MAP", 116, [1, -30, 0, 380], [1, 0], 34),
    ])
    return node


GUIS = {
    "Menu": (30, [main_menu, character_select, map_select]),
    "EndScreens": (40, [death_screen, results]),
    "Overlay": (50, [big_map, pause_menu, touch_controls]),
}


def mark_centre(node):
    """An element at 0.5 scale PLUS an offset is anchored to the screen centre, not
    asking to be centred. verify_ui's written-down opt-out for that is centre:false.
    It is set here, mechanically, only on nodes that carry such an offset."""
    pos = node.get("pos")
    if pos and "centre" not in node:
        if (pos[0] == 0.5 and pos[1] != 0) or (pos[2] == 0.5 and pos[3] != 0):
            node["centre"] = False
    for c in node.get("children") or []:
        mark_centre(c)


# ------------------------------------------------------------------ ui_build hooks

_orig_to_instances = ub.to_instances


def _font(name):
    return {"Font": {"family": f"rbxasset://fonts/families/{name}.json",
                     "weight": "Regular", "style": "Normal"}}


def to_instances(spec, theme, palette, counter=None):
    out = _orig_to_instances(spec, theme, palette, counter)
    node = out[0]
    kind = spec.get("type", "frame")
    if spec.get("font"):
        if kind == "label":
            node["properties"]["FontFace"] = _font(spec["font"])
        elif kind == "button":
            for c in node.get("children") or []:
                if c.get("className") == "TextLabel" and c.get("name") == spec.get(
                        "captionName", "Label"):
                    c["properties"]["FontFace"] = _font(spec["font"])
    if kind == "icon":
        # the contract asks for IconName only
        node["attributes"] = {"IconName": spec["icon"]}
    if spec.get("cls"):
        node["className"] = spec["cls"]
    if spec.get("clips"):
        node["properties"]["ClipsDescendants"] = True
    if spec.get("props"):
        node["properties"].update(spec["props"])
    if spec.get("attrs"):
        node.setdefault("attributes", {}).update(spec["attrs"])
    return out


ub.to_instances = to_instances

_orig_lua_value = ub.lua_value


def lua_value(v, prop=None, is_attribute=False):
    if isinstance(v, dict) and "Font" in v:
        f = v["Font"]
        return (f'Font.new("{f["family"]}", Enum.FontWeight.{f["weight"]}, '
                f'Enum.FontStyle.{f["style"]})')
    return _orig_lua_value(v, prop=prop, is_attribute=is_attribute)


ub.lua_value = lua_value

ICON_TINT = {"Silver": (196, 206, 214), "Gold": (255, 210, 58), "Skull": (232, 232, 224),
             "Padlock": (214, 220, 214), "Check": (53, 208, 74), "Run": (232, 232, 224),
             "Sword": (170, 184, 196), "Passive": (46, 127, 209), "Arrow": (17, 180, 244),
             "MapChest": (255, 210, 58), "MapShrine": (53, 208, 74),
             "MapBoss": (229, 18, 27), "MapVendor": (176, 77, 255),
             "MapTeammate": (61, 139, 255), "Knight": (160, 170, 180),
             "Fox": (236, 140, 60), "Frostling": (120, 210, 235),
             "Mossy": (70, 150, 80), "Desert": (214, 170, 100), "Graveyard": (96, 96, 120)}


def _icon_placeholder(img, s, box, icons):
    """Preview only: icons are made in a later step, so the mockup draws a tinted
    rounded tile with the first letters of the key."""
    x, y, w, h = box
    side = int(min(w, h))
    if side <= 0:
        return
    key = s["icon"]
    tint = next((c for k, c in ICON_TINT.items() if k in key), (217, 180, 90))
    d = ImageDraw.Draw(img)
    x0, y0 = x + (w - side) / 2, y + (h - side) / 2
    d.rounded_rectangle([x0, y0, x0 + side, y0 + side], radius=side * 0.28,
                        fill=tint + (255,), outline=(16, 21, 18, 255),
                        width=max(2, int(side * 0.07)))
    tag = key
    for pre in ("IconMap", "IconArrow", "Icon", "Portrait", "Thumb"):
        if tag.startswith(pre) and len(tag) > len(pre):
            tag = tag[len(pre):]
            break
    tag = tag[:2]
    f = ub.load_font(max(8, int(side * 0.42)))
    bb = d.textbbox((0, 0), tag, font=f)
    d.text((x0 + (side - (bb[2] - bb[0])) / 2 - bb[0],
            y0 + (side - (bb[3] - bb[1])) / 2 - bb[1]), tag, font=f, fill=(16, 21, 18, 255))


ub._icon = _icon_placeholder

_orig_draw_node = ub.draw_node


def draw_node(img, draw, node, theme, palette, icons):
    if node.spec.get("cls") == "ViewportFrame":
        x, y, w, h = (v * ub.SS for v in node.rect)
        draw.rounded_rectangle([x, y, x + w, y + h], radius=16, outline=(70, 80, 74),
                               width=3)
        f = ub.load_font(44)
        txt = f"{node.spec['name']} (ViewportFrame)"
        bb = draw.textbbox((0, 0), txt, font=f)
        draw.text((x + (w - (bb[2] - bb[0])) / 2, y + h / 2 - 22), txt, font=f,
                  fill=(90, 100, 94))
        return
    _orig_draw_node(img, draw, node, theme, palette, icons)


ub.draw_node = draw_node


def prune_for_mock(node):
    """The mockup hides what ships hidden, unless the node says mockShow."""
    n = dict(node)
    kids = []
    for c in node.get("children") or []:
        if c.get("visible") is False and not c.get("mockShow"):
            continue
        kids.append(prune_for_mock(c))
    if "children" in node:
        n["children"] = kids
    return n


LAYOUTISH = {"UIPadding", "UIListLayout", "UIGridLayout"}
DECOR = LAYOUTISH | {"UICorner", "UIGradient", "UIStroke", "UIAspectRatioConstraint",
                     "UITextSizeConstraint"}


def hoist(node):
    """Lift a depth-stack panel's content out of its Face frame, so the names the
    game binds are direct children of the named element (DetailCard.CharacterName,
    not DetailCard.Face.CharacterName). Face is the same rectangle as its wrapper,
    so nothing moves; ZIndex is raised by 2 so the content stays above the Face."""
    kids = node.get("children") or []
    for i, face in enumerate(kids):
        if face.get("name") == "Face" and face.get("className") == "Frame":
            fk = face.get("children") or []
            if any(k["className"] in LAYOUTISH for k in fk):
                break
            move = [k for k in fk if k["className"] not in DECOR]
            face["children"] = [k for k in fk if k["className"] in DECOR]
            for k in move:
                p = k.setdefault("properties", {})
                p["ZIndex"] = p.get("ZIndex", 0) + 2
            node["children"] = kids[:i + 1] + move + kids[i + 1:]
            break
    for c in node.get("children") or []:
        hoist(c)


def luau_scoped(root):
    """ui_build.luau declares one local per instance, and Luau allows 200 locals in
    a function; these ScreenGuis have far more instances. Same statements, same
    lua_value, but each instance lives in its own do-block."""
    name = root["name"]
    lines = ["-- generated by design/ui_specs/Menu_build.py from the same tree as "
             f"src/ui/{name}.model.json; paste into execute_luau",
             "local StarterGui = game:GetService('StarterGui')",
             f"local old = StarterGui:FindFirstChild('{name}')",
             "if old then old:Destroy() end", ""]

    def emit(node, parent, depth):
        ind = "\t" * depth
        v = f"n{depth}"
        lines.append(f"{ind}do")
        lines.append(f"{ind}\tlocal {v} = Instance.new('{node['className']}')")
        if node.get("name"):
            lines.append(f"{ind}\t{v}.Name = {ub.lua_value(node['name'], prop='Name')}")
        for k, val in (node.get("properties") or {}).items():
            lines.append(f"{ind}\t{v}.{k} = {ub.lua_value(val, prop=k)}")
        for k, val in (node.get("attributes") or {}).items():
            lines.append(f'{ind}\t{v}:SetAttribute("{k}", '
                         f'{ub.lua_value(val, is_attribute=True)})')
        for c in node.get("children") or []:
            emit(c, v, depth + 1)
        lines.append(f"{ind}\t{v}.Parent = {parent}")
        if depth == 0:
            lines.append(f"{ind}\tprint('[ui] built {name} with', "
                         f"#{v}:GetDescendants(), 'descendants')")
        lines.append(f"{ind}end")

    emit(root, "StarterGui", 0)
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------------ contract

V, H = True, False
CONTRACT = {
    "Menu": [
        ("MainMenu", "Frame", V), ("MainMenu/LogoBanner", None, None),
        ("MainMenu/PlayButton", "TextButton", None), ("MainMenu/SquadList", "Frame", None),
        ("MainMenu/SquadList/SquadRow", "Frame", None),
        ("MainMenu/SquadList/SquadRow/Portrait", "ImageLabel", None),
        ("MainMenu/SquadList/SquadRow/Name", "TextLabel", None),
        ("MainMenu/SquadList/SquadRow/Hero", "TextLabel", None),
        ("MainMenu/SquadList/SquadRow/ReadyTag", None, None),
        ("MainMenu/SquadList/SquadRow/HostTag", None, None),
        ("MainMenu/SilverTotal", None, None), ("MainMenu/VersionLabel", "TextLabel", None),
        ("CharacterSelect", "Frame", H), ("CharacterSelect/CloseButton", "TextButton", None),
        ("CharacterSelect/CharacterGrid", "Frame", None),
        ("CharacterSelect/CharacterGrid/PortraitTile", "TextButton", None),
        ("CharacterSelect/CharacterGrid/PortraitTile/Portrait", "ImageLabel", None),
        ("CharacterSelect/CharacterGrid/PortraitTile/Name", "TextLabel", None),
        ("CharacterSelect/CharacterGrid/PortraitTile/Focus", None, H),
        ("CharacterSelect/CharacterGrid/LockedTile", "TextButton", None),
        ("CharacterSelect/CharacterGrid/LockedTile/Name", "TextLabel", None),
        ("CharacterSelect/CharacterGrid/LockedTile/Padlock", "ImageLabel", None),
        ("CharacterSelect/DetailCard", "Frame", None),
        ("CharacterSelect/DetailCard/Portrait", "ImageLabel", None),
        ("CharacterSelect/DetailCard/CharacterName", "TextLabel", None),
        ("CharacterSelect/DetailCard/RunCount", "TextLabel", None),
        ("CharacterSelect/DetailCard/Blurb", "TextLabel", None),
        ("CharacterSelect/DetailCard/StartWeaponRow/Icon", "ImageLabel", None),
        ("CharacterSelect/DetailCard/StartWeaponRow/Name", "TextLabel", None),
        ("CharacterSelect/DetailCard/StartWeaponRow/Text", "TextLabel", None),
        ("CharacterSelect/DetailCard/PassiveRow/Icon", "ImageLabel", None),
        ("CharacterSelect/DetailCard/PassiveRow/Name", "TextLabel", None),
        ("CharacterSelect/DetailCard/PassiveRow/Text", "TextLabel", None),
        ("CharacterSelect/DetailCard/UnlockButton", "TextButton", H),
        ("CharacterSelect/DetailCard/ConfirmButton", "TextButton", None),
        ("MapSelect", "Frame", H), ("MapSelect/CloseButton", "TextButton", None),
        ("MapSelect/MapList", "Frame", None), ("MapSelect/MapList/MapRow", "TextButton", None),
        ("MapSelect/MapList/MapRow/Thumb", "ImageLabel", None),
        ("MapSelect/MapList/MapRow/Name", "TextLabel", None),
        ("MapSelect/MapList/MapRow/Blurb", "TextLabel", None),
        ("MapSelect/MapList/MapRow/LockTag", None, H),
        ("MapSelect/DetailCard", "Frame", None),
        ("MapSelect/DetailCard/MapName", "TextLabel", None),
        ("MapSelect/DetailCard/TierLabel", "TextLabel", None),
        ("MapSelect/DetailCard/Highscore", "TextLabel", None),
        ("MapSelect/DetailCard/BestTime", "TextLabel", None),
        ("MapSelect/DetailCard/StageCount", "TextLabel", None),
        ("MapSelect/DetailCard/ReadyList", "Frame", None),
        ("MapSelect/DetailCard/ReadyList/ReadyRow", "Frame", None),
        ("MapSelect/DetailCard/ReadyList/ReadyRow/Name", "TextLabel", None),
        ("MapSelect/DetailCard/ReadyList/ReadyRow/State", "TextLabel", None),
        ("MapSelect/DetailCard/ConfirmButton", "TextButton", None),
    ],
    "EndScreens": [
        ("DeathScreen", "Frame", H), ("DeathScreen/DeathTitle", "TextLabel", None),
        ("DeathScreen/DeathJoke", "TextLabel", None),
        ("DeathScreen/HeroViewport", "ViewportFrame", None),
        ("DeathScreen/ConfirmButton", "TextButton", None),
        ("Results", "Frame", H), ("Results/ResultTitle", "TextLabel", None),
        ("Results/StatTable", "Frame", None),
        *[(f"Results/StatTable/{n}{s}", c, None) for n in ("Kills", "Level", "Time", "BossTime")
          for s, c in (("", "Frame"), ("/Label", "TextLabel"), ("/Value", "TextLabel"))],
        ("Results/PlayerRows", "Frame", None), ("Results/PlayerRows/PlayerRow", "Frame", None),
        ("Results/PlayerRows/PlayerRow/Portrait", "ImageLabel", None),
        *[(f"Results/PlayerRows/PlayerRow/{n}", "TextLabel", None)
          for n in ("Name", "Kills", "Damage", "Silver")],
        ("Results/ContinueLabel", "TextLabel", None),
    ],
    "Overlay": [
        ("BigMap", "Frame", H), ("BigMap/Dots", "Frame", None),
        ("BigMap/PlayerArrow", "ImageLabel", None),
        *[(f"BigMap/{n}", "TextLabel", None) for n in "NESW"], ("BigMap/Legend", "Frame", None),
        ("PauseMenu", "Frame", H), ("PauseMenu/ResumeButton", "TextButton", None),
        *[(f"PauseMenu/{n}{s}", "Frame", None)
          for n in ("MusicSlider", "SfxSlider", "SensitivitySlider")
          for s in ("", "/Fill", "/Knob")],
        ("PauseMenu/DamageNumbersToggle", "TextButton", None),
        ("PauseMenu/DamageNumbersToggle/Check", "ImageLabel", None),
        ("PauseMenu/LeaveButton", "TextButton", None),
        ("TouchControls", "Frame", H),
        *[(f"TouchControls/{n}", "TextButton", None)
          for n in ("JumpButton", "SlideButton", "InteractButton", "TabButton")],
    ],
}


def find(node, path):
    cur = node
    for part in path.split("/"):
        cur = next((c for c in cur.get("children") or [] if c.get("name") == part), None)
        if cur is None:
            return None
    return cur


def check_contract(gui, root):
    bad = []
    for path, cls, vis in CONTRACT[gui]:
        n = find(root, path)
        if n is None:
            bad.append(f"MISSING {gui}/{path}")
            continue
        if cls and n["className"] != cls:
            bad.append(f"CLASS {gui}/{path}: {n['className']} (want {cls})")
        if vis is not None:
            got = n.get("properties", {}).get("Visible", True)
            if got != vis:
                bad.append(f"VISIBLE {gui}/{path}: {got} (want {vis})")
    return bad


GUI_CLASSES = {"Frame", "TextLabel", "TextButton", "ImageLabel", "ViewportFrame"}
INTERNAL = {"Shadow", "Face", "Rivet", "Bracket"}


def manifest_for(root):
    elements, icons = [], {}
    seen = set()  # sample children share a path; list the element once, walk all

    def walk(node, path):
        for c in node.get("children") or []:
            if c["className"] not in GUI_CLASSES or c.get("name") in INTERNAL:
                continue
            p = f"{path}/{c['name']}" if path else c["name"]
            key = (c.get("attributes") or {}).get("IconName")
            if key:
                icons.setdefault(key, [])
                if p not in icons[key]:
                    icons[key].append(p)
            if p not in seen:
                seen.add(p)
                e = {"path": p, "class": c["className"]}
                if c.get("properties", {}).get("Visible") is False:
                    e["visible"] = False
                if key:
                    e["icon"] = key
                elements.append(e)
            walk(c, p)

    walk(root, "")
    return elements, icons


# ------------------------------------------------------------------ main

def main() -> int:
    SPECS.mkdir(parents=True, exist_ok=True)
    MOCKS.mkdir(parents=True, exist_ok=True)
    UI.mkdir(parents=True, exist_ok=True)
    theme = json.loads((ROOT / "design" / "ui_theme.json").read_text(encoding="utf-8"))
    palette = theme["palette"]
    ub.set_style(theme)
    keep = []  # keep every spec alive: ui_build caches heights by id()
    manifest = {"_note": "Menu, EndScreens and Overlay. Paths are instance paths inside "
                         "the ScreenGui. Builder internals (Shadow, Face, Rivet, Bracket) "
                         "and UI modifiers are left out.", "screenGuis": {}, "icons": {}}
    verdicts, contract_bad = {}, []

    for gui, (order, makers) in GUIS.items():
        tree = []
        for make in makers:
            top = make()
            mark_centre(top)
            stem = f"{gui}.{top['name']}"
            spec = {"name": stem, "theme": THEME_REF, "resolution": RES, "kind": "page",
                    "screenGui": gui, "displayOrder": order, "children": [top]}
            path = SPECS / f"{stem}.json"
            path.write_text(json.dumps(spec, indent=1), encoding="utf-8")
            spec = json.loads(path.read_text(encoding="utf-8"))  # build from the file
            keep.append(spec)

            mock = {"type": "root", "name": stem, "size": [1, 0, 1, 0],
                    "children": [prune_for_mock(c) for c in spec["children"]]}
            keep.append(mock)
            node = ub.resolve(mock, (0, 0, RES[0], RES[1]), theme)
            ub.render(node, theme, palette, {}, RES).convert("RGB").save(MOCKS / f"{stem}.png")

            ub.RESOLVED_H.clear()
            root_spec = {"type": "root", "name": stem, "size": [1, 0, 1, 0],
                         "children": spec["children"]}
            keep.append(root_spec)
            ub.measure_heights(root_spec, theme, RES)
            for c in spec["children"]:
                tree += ub.to_instances(c, theme, palette)

            issues = vu.check(spec, theme, None, path.name)
            saved = vu.DEVICES
            vu.DEVICES = [d for d in saved if d[0] != "phone-small"]
            issues896 = vu.check(spec, theme, None, path.name)
            vu.DEVICES = saved
            verdicts[stem] = (issues, issues896)

        root = ub.instance(gui, "ScreenGui", {
            "DisplayOrder": order, "ResetOnSpawn": False, "ZIndexBehavior": "Sibling",
            "IgnoreGuiInset": True, "Enabled": True}, tree)
        hoist(root)
        contract_bad += check_contract(gui, root)

        rojo_root = ub.strip_content_for_rojo(copy.deepcopy(root))
        rojo_root.pop("name", None)
        (UI / f"{gui}.model.json").write_text(json.dumps(rojo_root, indent=1),
                                              encoding="utf-8")
        (SPECS / f"{gui}.build.lua").write_text(
            luau_scoped(ub.qualify_enums(copy.deepcopy(root))), encoding="utf-8")

        elements, icons = manifest_for(root)
        manifest["screenGuis"][gui] = {"displayOrder": order,
                                       "file": f"src/ui/{gui}.model.json",
                                       "elements": elements}
        for k, paths in icons.items():
            manifest["icons"].setdefault(k, []).extend(f"{gui}/{p}" for p in paths)
        n = sum(1 for _ in _walk(root))
        print(f"[build] {gui}: {n} instances")

    (ROOT / "assets" / "ui" / "manifest.Menu.json").write_text(
        json.dumps(manifest, indent=1), encoding="utf-8")

    print("\n== verify_ui (stock devices) ==")
    total_fail = 0
    for stem, (issues, issues896) in verdicts.items():
        f = [i for i in issues if i["level"] == "fail"]
        w = [i for i in issues if i["level"] == "warn"]
        f2 = [i for i in issues896 if i["level"] == "fail"]
        total_fail += len(f)
        by = {}
        for i in f:
            by[i["check"]] = by.get(i["check"], 0) + 1
        print(f"\n{stem}: {len(f)} fail {by}, {len(w)} warn; "
              f"without the 640x360 device: {len(f2)} fail")
        if "-v" in sys.argv:
            for i in f + w:
                print(f"  [{i['level']}] {i['check']}: {i['msg']}")
        else:
            for i in w + f2:
                print(f"  [{i['level']}] {i['check']}: {i['msg']}")
            for i in f:
                if i["check"] not in ("text_fit", "touch_target") and i not in f2:
                    print(f"  [{i['level']}] {i['check']}: {i['msg']}")

    print("\n== contract ==")
    print("all names present with the right class and Visible" if not contract_bad
          else "\n".join(contract_bad))
    return 1 if contract_bad else 0


def _walk(n):
    yield n
    for c in n.get("children") or []:
        yield from _walk(c)


if __name__ == "__main__":
    raise SystemExit(main())

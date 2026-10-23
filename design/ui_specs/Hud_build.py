#!/usr/bin/env python3
"""T2 HUD: builds src/ui/Hud.model.json and its preview PNGs from one tree.

    python design/ui_specs/Hud_build.py [--fonts DIR] [--no-png]

Run from the project root. Writes:
    src/ui/Hud.model.json         the shipped ScreenGui (Rojo model)
    assets/ui/manifest.Hud.json   every named element, its class and path
    assets/ui/mockups/Hud_*.png   previews, laid out by the game's own
                                  Core/HudLayout (through lune) and drawn over a
                                  Wardwood backdrop with the real icons

The previews need Pillow, `lune` on PATH, and the LuckiestGuy and Fredoka TTFs
(Google Fonts, OFL/Apache) in --fonts; without the fonts PIL's default face is
used. They are a guide for layout and colour, not a Studio capture: Roblox's
text metrics, strokes and gradients differ in detail.

The HudController changes sizes at runtime for small screens (Core/HudLayout);
`apply_layout` below mirrors exactly those changes for the previews. Keep the
two in step.
"""

import argparse
import copy
import json
import math
import os
import re
import subprocess
import sys

ROOT = os.getcwd()

# ---------------------------------------------------------------- tokens

PANEL = "#16231B"  # deep moss: every panel
TRACK = "#0A110D"  # bar tracks and tiles
RIM = "#D9B85C"  # the thin gold rim
TEAL = "#63D2C1"  # tome tiles
INK = "#FFF7E8"  # warm white text
SOFT = "#D7CFBC"  # secondary text
TAN = "#D9B45A"  # captions
OUTLINE = "#0D1410"  # text outline
HP = "#F2554D"
HP_TRAIL = "#FFD7A1"
SHIELD = "#9EE6F7"
XP = "#45A3FF"
GOLD = "#FFCB45"
SILVER = "#DCE6EE"
DONE = "#7BD957"
DANGER = "#FF6A4D"
DANGER_BG = "#3A1411"
BOSS = "#E5453C"
BOSS_RIM = "#FF8A5C"
PARCHMENT = "#F3E6C4"

DISPLAY = "rbxasset://fonts/families/LuckiestGuy.json"
BODY = "rbxasset://fonts/families/FredokaOne.json"

RARITY = {"Common": "#35D07A", "Uncommon": "#3D8BFF", "Rare": "#B04DFF", "Epic": "#FF4D9A", "Legendary": "#FFD23A"}

# ---------------------------------------------------------------- property values


def U2(xs, xo, ys, yo):
    # offsets are whole pixels (Roblox stores them as integers; Rojo insists)
    return {"UDim2": [[xs, int(round(xo))], [ys, int(round(yo))]]}


def V2(x, y):
    return {"Vector2": [x, y]}


def C3(hexcode):
    h = hexcode.lstrip("#")
    return {"Color3": [round(int(h[i : i + 2], 16) / 255, 4) for i in (0, 2, 4)]}


def UD(s, o):
    return {"UDim": [s, o]}


def FONT(family):
    return {"Font": {"family": family, "weight": "Regular", "style": "Normal"}}


ICON_IDS = {}


def load_icon_ids():
    path = os.path.join(ROOT, "src/shared/Config/Icons.luau")
    with open(path, encoding="utf-8") as f:
        for key, asset in re.findall(r'^\s*(\w+)\s*=\s*"(rbxassetid://\d+)"', f.read(), re.M):
            ICON_IDS[key] = asset


# ---------------------------------------------------------------- nodes


def node(cls, name, props=None, children=None, attrs=None):
    n = {"className": cls, "name": name, "properties": props or {}, "children": [c for c in (children or []) if c]}
    if attrs:
        n["attributes"] = attrs
    return n


def corner(radius):
    """radius: pixels, or 'pill' for a half-height radius."""
    return node("UICorner", "Corner", {"CornerRadius": UD(0.5, 0) if radius == "pill" else UD(0, radius)})


def stroke(colour, thickness, transparency=0.0, contextual=False):
    return node(
        "UIStroke",
        "Stroke",
        {
            "Color": C3(colour),
            "Thickness": thickness,
            "Transparency": transparency,
            "ApplyStrokeMode": "Contextual" if contextual else "Border",
            "LineJoinMode": "Round",
        },
    )


def shade(bottom=0.8):
    """A soft top-to-bottom shade: UIGradient multiplies BackgroundColor3, so
    code can still tint the frame."""
    return node(
        "UIGradient",
        "Shade",
        {
            "Rotation": 90,
            "Color": {
                "ColorSequence": {
                    "keypoints": [{"time": 0, "color": [1, 1, 1]}, {"time": 1, "color": [bottom, bottom, bottom]}]
                }
            },
        },
    )


def fade():
    """Left and right ends fade out (a ribbon)."""
    keys = [(0, 1), (0.22, 0), (0.78, 0), (1, 1)]
    return node(
        "UIGradient",
        "Fade",
        {"Transparency": {"NumberSequence": {"keypoints": [{"time": t, "value": v, "envelope": 0} for t, v in keys]}}},
    )


def fit(max_px):
    """TextScaled up to max_px: long names shrink instead of spilling."""
    return node("UITextSizeConstraint", "Fit", {"MaxTextSize": max_px, "MinTextSize": 12})


def listing(direction, padding, h="Left", v="Top", name="Layout"):
    return node(
        "UIListLayout",
        name,
        {
            "FillDirection": direction,
            "Padding": UD(0, padding),
            "HorizontalAlignment": h,
            "VerticalAlignment": v,
            "SortOrder": "LayoutOrder",
        },
    )


def padding(left, top=None, right=None, bottom=None):
    top = left if top is None else top
    right = left if right is None else right
    bottom = top if bottom is None else bottom
    return node(
        "UIPadding",
        "Padding",
        {
            "PaddingLeft": UD(0, left),
            "PaddingTop": UD(0, top),
            "PaddingRight": UD(0, right),
            "PaddingBottom": UD(0, bottom),
        },
    )


def gui(props, name, size, pos=(0, 0, 0, 0), anchor=(0, 0), z=1, visible=True, order=None, auto=None):
    props.update({"Size": U2(*size), "Position": U2(*pos), "AnchorPoint": V2(*anchor), "ZIndex": z})
    if not visible:
        props["Visible"] = False
    if order is not None:
        props["LayoutOrder"] = order
    if auto:
        props["AutomaticSize"] = auto
    return props


def frame(name, size, pos=(0, 0, 0, 0), anchor=(0, 0), z=1, fill=None, alpha=0.0, children=(), **kw):
    props = {"BackgroundTransparency": 1, "BorderSizePixel": 0}
    if fill:
        props["BackgroundColor3"] = C3(fill)
        props["BackgroundTransparency"] = alpha
    if kw.pop("clip", False):
        props["ClipsDescendants"] = True
    return node("Frame", name, gui(props, name, size, pos, anchor, z, **kw), list(children))


def panel(name, size, pos=(0, 0, 0, 0), anchor=(0, 0), z=1, alpha=0.2, radius=12, rim=RIM, rim_alpha=0.5, children=(), **kw):
    """A moss panel with the thin gold rim."""
    kids = [corner(radius), shade(0.78)]
    if rim:
        kids.append(stroke(rim, 1.5, rim_alpha))
    return frame(name, size, pos, anchor, z, fill=PANEL, alpha=alpha, children=kids + list(children), **kw)


def label(
    name,
    text,
    size,
    pos=(0, 0, 0, 0),
    anchor=(0, 0),
    z=2,
    font=DISPLAY,
    px=20,
    colour=INK,
    align="Center",
    valign="Center",
    outline=2.0,
    truncate=False,
    children=(),
    fill=None,
    fill_alpha=0.0,
    scaled=None,
    **kw,
):
    props = {
        "BackgroundTransparency": 1,
        "BorderSizePixel": 0,
        "Text": text,
        "TextSize": px,
        "TextScaled": False,
        "FontFace": FONT(font),
        "TextColor3": C3(colour),
        "TextXAlignment": align,
        "TextYAlignment": valign,
    }
    if fill:
        props["BackgroundColor3"] = C3(fill)
        props["BackgroundTransparency"] = fill_alpha
    if truncate:
        props["TextTruncate"] = "AtEnd"
    kids = [stroke(OUTLINE, outline, 0.1, contextual=True)] if outline else []
    if scaled:
        props["TextScaled"] = True
        kids.append(fit(scaled))
    return node("TextLabel", name, gui(props, name, size, pos, anchor, z, **kw), kids + list(children))


def icon(name, key, size, pos=(0, 0, 0, 0), anchor=(0, 0), z=3, children=(), **kw):
    props = {"BackgroundTransparency": 1, "BorderSizePixel": 0, "ScaleType": "Fit"}
    if key in ICON_IDS:
        props["Image"] = ICON_IDS[key]
    return node("ImageLabel", name, gui(props, name, (0, size, 0, size), pos, anchor, z, **kw), list(children), {"IconName": key})


def bar(name, size, pos, colour, radius, z, children=(), trail=False, fraction=0.7, **kw):
    """A track with a scale-width Fill (and a pale Trail behind it)."""
    kids = [corner(radius)]
    if trail:
        kids.append(frame("Trail", (min(1, fraction + 0.12), 0, 1, 0), z=z + 1, fill=HP_TRAIL, children=[corner(radius)]))
    kids.append(frame("Fill", (fraction, 0, 1, 0), z=z + 2, fill=colour, children=[corner(radius), shade(0.72)]))
    return frame(name, size, pos, z=z, fill=TRACK, alpha=0.15, children=kids + list(children), **kw)


# ---------------------------------------------------------------- the tree


def vitals():
    """Level, shield and HP. XP runs along the top of the screen (xp_bar)."""
    badge = frame(
        "LevelBadge",
        (0, 76, 0, 76),
        (0, 10, 0.5, 0),
        (0, 0.5),
        z=2,
        fill="#0E1712",
        alpha=0.05,
        children=[
            corner("pill"),
            shade(0.7),
            stroke(RIM, 2.5, 0.05),
            label("LevelCaption", "LVL", (1, 0, 0, 16), (0.5, 0, 0, 10), (0.5, 0), z=3, font=BODY, px=14, colour=TAN, outline=0),
            label("LevelLabel", "12", (1, -8, 0, 38), (0.5, 0, 0.5, 8), (0.5, 0.5), z=3, px=34, outline=2.5),
        ],
    )
    bars = frame(
        "Bars",
        (1, -114, 0, 76),
        (0, 100, 0.5, 0),
        (0, 0.5),
        z=2,
        children=[
            listing("Vertical", 6, v="Center"),
            bar(
                "ShieldBar",
                (1, 0, 0, 18),
                (0, 0, 0, 0),
                SHIELD,
                "pill",
                3,
                fraction=0.75,
                order=1,
                children=[label("Text", "45 / 60", (1, -12, 1, 0), (0.5, 0, 0.5, 0), (0.5, 0.5), z=6, px=15, align="Right", outline=1.5)],
            ),
            bar(
                "HPBar",
                (1, 0, 0, 34),
                (0, 0, 0, 0),
                HP,
                8,
                3,
                trail=True,
                fraction=0.78,
                order=2,
                children=[
                    stroke(OUTLINE, 1.5, 0.35),
                    label("Text", "156 / 200", (1, 0, 1, 0), z=6, px=23),
                ],
            ),
        ],
    )
    return panel("Vitals", (0, 440, 0, 96), order=1, z=1, children=[badge, bars])


RAINBOW = ["#35D04A", "#11B4F4", "#B04DFF", "#FF4D9A", "#FF9F1A", "#FFD23A"]  # Core/XpStrip.Colours


def rainbow_keys(phase=0.0, blend=0.35):
    """Core/XpStrip.rainbow, for the model's resting gradient and the previews."""
    n = len(RAINBOW)
    cols = [C3(c)["Color3"] for c in RAINBOW]

    def at(u):
        x = ((u - phase) * n) % n
        k = min(int(math.floor(x)), n - 1)
        f = x - k
        a = cols[k]
        if f <= 1 - blend:
            return a
        b = cols[(k + 1) % n]
        t = (f - (1 - blend)) / blend
        return [round(a[i] + (b[i] - a[i]) * t, 4) for i in range(3)]

    times = {0.0, 1.0}
    for k in range(n):
        for edge in ((k + 1 - blend) / n, (k + 1) / n):
            u = (edge + phase) % 1
            if 1e-4 < u < 1 - 1e-4:
                times.add(round(u, 5))
    return [{"time": t, "color": at(t)} for t in sorted(times)]


def xp_bar():
    """The XpBar ScreenGui: one thin strip the whole width of the screen, edge to
    edge just under Roblox's top bar, over the level-up panels (DisplayOrder 21)
    so its rainbow shows while a choice waits. Its screen ignores every inset, so
    the strip's left edge is the screen's; square ends, as it runs off both
    sides. HudController places it from Core/HudLayout and draws the fill and
    the rainbow."""
    strip = frame(
        "Strip",
        (1, 0, 0, 14),
        (0, 0, 0, 62),
        z=1,
        children=[
            frame("Back", (1, 0, 1, 0), z=1, fill=TRACK, alpha=0.18, children=[shade(0.8), stroke(RIM, 1.5, 0.3)]),
            frame(
                "Fill",
                (0.62, 0, 1, 0),
                z=2,
                fill=XP,
                children=[
                    shade(0.7),
                    frame("Shine", (1, 0, 0, 3), (0, 0, 0, 2), z=3, fill="#FFFFFF", alpha=0.55),
                ],
            ),
            frame(
                "Rainbow",
                (1, 0, 1, 0),
                z=4,
                fill="#FFFFFF",
                visible=False,
                children=[
                    node("UIGradient", "Gradient", {"Color": {"ColorSequence": {"keypoints": rainbow_keys()}}}),
                ],
            ),
        ],
    )
    return node(
        "ScreenGui",
        "XpBar",
        {"DisplayOrder": 21, "ResetOnSpawn": False, "ZIndexBehavior": "Sibling", "IgnoreGuiInset": True, "ScreenInsets": "None", "Enabled": True},
        [strip],
    )


def chip(name, key, value_name, value, colour, px=20, order=0, icon_px=24):
    return frame(
        name,
        (0, 0, 0, 40),
        z=2,
        order=order,
        auto="X",
        children=[
            listing("Horizontal", 6, v="Center"),
            icon("Icon", key, icon_px, z=3, order=1),
            label(value_name, value, (0, 0, 0, 40), z=3, px=px, colour=colour, align="Left", order=2, auto="X"),
        ],
    )


def purse():
    chest = frame(
        "NextChest",
        (0, 0, 0, 30),
        z=2,
        order=2,
        auto="X",
        fill="#2A2214",
        alpha=0.25,
        children=[
            corner("pill"),
            stroke(RIM, 1.5, 0.6),
            padding(8, 0, 10, 0),
            listing("Horizontal", 5, v="Center"),
            icon("Icon", "IconChest", 22, z=3, order=1),
            label("Price", "30", (0, 0, 0, 30), z=3, px=18, colour=TAN, align="Left", order=2, auto="X"),
        ],
    )
    return frame(
        "Purse",
        (0, 0, 0, 44),
        z=1,
        order=2,
        auto="X",
        fill=PANEL,
        alpha=0.32,
        children=[
            corner(10),
            stroke(RIM, 1, 0.75),
            padding(12, 0, 14, 0),
            listing("Horizontal", 16, v="Center"),
            chip("Gold", "IconGold", "GoldCount", "1,240", GOLD, px=22, order=1, icon_px=26),
            chest,
            chip("Silver", "IconSilver", "SilverCount", "85", SILVER, order=3),
            chip("Kills", "IconSkull", "KillCount", "412", SOFT, order=4),
        ],
    )


def quest_line(text, done, order):
    return frame(
        "QuestLine",
        (1, 0, 0, 28),
        z=2,
        order=order,
        children=[
            frame(
                "Box",
                (0, 20, 0, 20),
                (0, 2, 0.5, 0),
                (0, 0.5),
                z=3,
                fill=DONE if done else TRACK,
                alpha=0.0 if done else 0.2,
                children=[corner(5), stroke(DONE if done else TAN, 2, 0.15)],
            ),
            icon("Check", "IconCheck", 22, (0, 12, 0.5, 0), (0.5, 0.5), z=4, visible=done),
            label(
                "Text",
                text,
                (1, -34, 1, 0),
                (0, 32, 0.5, 0),
                (0, 0.5),
                z=3,
                font=BODY,
                px=18,
                colour=SOFT if done else INK,
                align="Left",
                outline=1.5,
                truncate=True,
            ),
        ],
    )


def side_panel(name, title, rows, order):
    return panel(
        name,
        (0, 380, 0, 0),
        z=1,
        alpha=0.3,
        radius=10,
        rim_alpha=0.72,
        order=order,
        auto="Y",
        children=[
            padding(12, 8, 12, 10),
            listing("Vertical", 4),
            label("Header", title, (1, 0, 0, 18), z=2, font=BODY, px=15, colour=TAN, align="Left", outline=0, order=0),
        ]
        + rows,
    )


def teammate(name, hero, hp, order, downed=False):
    return frame(
        "Teammate",
        (1, 0, 0, 40),
        z=2,
        order=order,
        children=[
            icon(
                "Portrait",
                "Portrait" + hero,
                36,
                (0, 0, 0.5, 0),
                (0, 0.5),
                z=3,
                children=[corner("pill"), stroke(RIM, 1.5, 0.3)],
            ),
            label("Name", name, (0, 190, 0, 20), (0, 46, 0, 1), z=3, font=BODY, px=17, align="Left", outline=1.5, truncate=True),
            frame(
                "HPBack",
                (0, 190, 0, 9),
                (0, 46, 0, 26),
                z=3,
                fill=TRACK,
                alpha=0.15,
                children=[
                    corner("pill"),
                    frame("HPFill", (hp, 0, 1, 0), z=4, fill=HP, children=[corner("pill")]),
                    frame("ShieldFill", (0.5 if not downed else 0, 0, 0.4, 0), z=5, fill=SHIELD, children=[corner("pill")]),
                ],
            ),
            label(
                "DownedTag",
                "DOWN",
                (0, 96, 0, 24),
                (1, -2, 0.5, 0),
                (1, 0.5),
                z=3,
                px=15,
                colour=DANGER,
                outline=0,
                fill=DANGER_BG,
                fill_alpha=0.1,
                visible=downed,
                children=[corner("pill")],
            ),
        ],
    )


def top_left():
    quests = side_panel(
        "QuestTracker",
        "OBJECTIVES",
        [quest_line("Find the Boss Portal", False, 1), quest_line("Defeat the Boss", False, 2)],
        3,
    )
    team = side_panel(
        "TeammateBars",
        "TEAM",
        [
            teammate("FoxyMcBonk", "Fox", 0.8, 1),
            teammate("xX_BonkMaster_2014Xx", "Frostling", 0.35, 2),
            teammate("SirClonkALot", "Knight", 0.0, 3, downed=True),
        ],
        4,
    )
    return frame(
        "TopLeft",
        (0, 440, 0, 0),
        (0, 16, 0, 16),
        z=2,
        auto="Y",
        children=[listing("Vertical", 10), vitals(), purse(), quests, team],
    )


def timer_plate():
    run_clock = label(
        "RunClock",
        "4:23",
        (0, 0, 0, 28),
        (1, 8, 0.5, 0),
        (0, 0.5),
        z=2,
        px=18,
        colour=SOFT,
        align="Left",
        outline=1.5,
        auto="X",
        fill=PANEL,
        fill_alpha=0.35,
        children=[corner("pill"), padding(30, 0, 12, 0), icon("Icon", "IconClock", 20, (0, -24, 0.5, 0), (0, 0.5), z=3)],
    )
    # LuckiestGuy's digits stand taller than their line: the caption keeps to the
    # top 22 px and the digits' box starts at 30, so they never touch
    return panel(
        "TimerPlate",
        (0, 248, 0, 76),
        z=1,
        radius=14,
        rim_alpha=0.4,
        order=1,
        children=[
            label("TimerCaption", "FINAL HORDE IN", (1, 0, 0, 16), (0.5, 0, 0, 6), (0.5, 0), z=2, font=BODY, px=14, colour=TAN, outline=0),
            label("StageTimer", "5:37", (1, 0, 0, 42), (0.5, 0, 1, -4), (0.5, 1), z=2, px=40, outline=3),
            run_clock,
        ],
    )


def difficulty_pill():
    return frame(
        "DifficultyPill",
        (0, 0, 0, 32),
        z=1,
        order=3,
        auto="X",
        visible=False,
        fill=DANGER_BG,
        alpha=0.1,
        children=[
            corner("pill"),
            stroke(DANGER, 1.5, 0.25),
            padding(14, 0, 14, 0),
            listing("Horizontal", 10, v="Center"),
            label("TierName", "HARD", (0, 0, 0, 30), z=2, px=18, colour="#FFB59E", order=1, auto="X"),
            label(
                "TierMult",
                "x1.6",
                (0, 0, 0, 30),
                z=2,
                px=18,
                order=2,
                auto="X",
                align="Left",
                children=[padding(26, 0, 0, 0), icon("Icon", "IconSkull", 20, (0, -26, 0.5, 0), (0, 0.5), z=3)],
            ),
        ],
    )


def mini_bar(name, fraction, order):
    return frame(
        "MiniBar",
        (0, 240, 0, 40),
        z=2,
        order=order,
        children=[
            label("Name", name, (1, 0, 0, 17), z=3, px=15, colour="#FFE1C9", outline=1.5, scaled=15),
            bar("Back", (1, 0, 0, 16), (0, 0, 0, 22), BOSS, "pill", 3, fraction=fraction, children=[stroke(BOSS_RIM, 1, 0.4)]),
            label("Text", "1,840 / 2,400", (1, 0, 0, 16), (0, 0, 0, 22), z=7, px=13, outline=1.5),
        ],
    )


def boss_bars():
    main = frame(
        "Main",
        (1, 0, 0, 56),
        z=2,
        order=1,
        children=[
            label("Name", "OLD MAN TIMBER", (1, 0, 0, 26), (0.5, 0, 0, 0), (0.5, 0), z=3, px=24, colour="#FFE1C9", outline=2.5, scaled=24),
            bar("Back", (1, 0, 0, 24), (0, 0, 0, 30), BOSS, "pill", 3, trail=True, fraction=0.82, children=[stroke(BOSS_RIM, 1.5, 0.35)]),
            label("Text", "7,412 / 9,000", (1, 0, 0, 24), (0, 0, 0, 30), z=7, px=17, outline=2),
        ],
    )
    minis = frame(
        "Minis",
        (1, 0, 0, 40),
        z=2,
        order=2,
        children=[listing("Horizontal", 14, h="Center"), mini_bar("BIG BONE", 0.65, 1), mini_bar("GOBLIN CHIEF", 0.4, 2)],
    )
    return frame(
        "BossBars",
        (0, 760, 0, 0),
        z=1,
        order=4,
        auto="Y",
        visible=False,
        children=[listing("Vertical", 8, h="Center"), main, minis],
    )


def banner():
    return frame(
        "Banner",
        (0, 900, 0, 96),
        z=3,
        order=5,
        visible=False,
        children=[
            frame("Band", (1, 0, 1, 0), z=1, fill=PANEL, alpha=0.1, children=[fade()]),
            frame("RuleTop", (0.8, 0, 0, 2), (0.5, 0, 0, 0), (0.5, 0), z=2, fill=RIM, alpha=0.1, children=[fade()]),
            frame("RuleBottom", (0.8, 0, 0, 2), (0.5, 0, 1, 0), (0.5, 1), z=2, fill=RIM, alpha=0.1, children=[fade()]),
            label("BannerText", "SLIME SWARM", (1, -40, 0, 54), (0.5, 0, 0, 8), (0.5, 0), z=3, px=50, colour=GOLD, outline=3, scaled=50),
            label("BannerSub", "Coming from the north!", (1, 0, 0, 24), (0.5, 0, 0, 64), (0.5, 0), z=3, font=BODY, px=20, outline=1.5),
        ],
    )


def toast():
    return panel(
        "Toast",
        (0, 400, 0, 70),
        z=3,
        radius=12,
        rim_alpha=0.45,
        alpha=0.12,
        order=6,
        visible=False,
        children=[
            frame(
                "PortraitBack",
                (0, 46, 0, 46),
                (0, 12, 0.5, 0),
                (0, 0.5),
                z=2,
                fill="#0E1712",
                children=[corner("pill"), stroke(RIM, 1.5, 0.3)],
            ),
            icon("ToastPortrait", "IconExclaim", 34, (0, 35, 0.5, 0), (0.5, 0.5), z=3),
            label("ToastTitle", "Challenge", (1, -82, 0, 22), (0, 70, 0, 11), z=2, px=19, colour=GOLD, align="Left", truncate=True),
            label(
                "ToastText",
                "Clear the elites for a free chest.",
                (1, -82, 0, 22),
                (0, 70, 0, 37),
                z=2,
                font=BODY,
                px=16,
                align="Left",
                outline=1.5,
                truncate=True,
            ),
        ],
    )


def top_centre():
    """One column for everything in the top centre, so nothing there can cover
    anything else: the plate, LEVEL UP! right under it (above the level-up
    panel), the overtime pill, boss bars, banner and toast, and last the pickup
    popup, which therefore never moves what is above it."""
    level_up = label("LevelUpText", "LEVEL UP!", (1, 0, 0, 58), z=5, px=52, colour=GOLD, outline=4, order=2, visible=False, scaled=52)
    pickup = label("PickupToast", "MAGNET", (1, 0, 0, 48), z=5, px=40, colour=GOLD, outline=3, order=10, visible=False, scaled=40)
    return frame(
        "TopCenter",
        (0, 900, 0, 0),
        (0.5, 0, 0, 16),
        (0.5, 0),
        z=3,
        auto="Y",
        children=[listing("Vertical", 8, h="Center"), timer_plate(), level_up, difficulty_pill(), boss_bars(), banner(), toast(), pickup],
    )


def minimap():
    letters = []
    for letter, pos in [("N", (0.5, 0, 0, 0)), ("E", (1, 0, 0.5, 0)), ("S", (0.5, 0, 1, 0)), ("W", (0, 0, 0.5, 0))]:
        letters.append(label(letter, letter, (0, 24, 0, 24), pos, (0.5, 0.5), z=6, px=18, colour=GOLD if letter == "N" else SOFT))
    dots = frame(
        "Dots",
        (1, -8, 1, -8),
        (0.5, 0, 0.5, 0),
        (0.5, 0.5),
        z=3,
        clip=True,
        children=[
            frame("MapDot", (0, 10, 0, 10), (0.66, 0, 0.18, 0), (0.5, 0.5), z=4, fill="#FFD23A", children=[corner("pill")]),
            frame("MapDot", (0, 10, 0, 10), (0.3, 0, 0.7, 0), (0.5, 0.5), z=4, fill="#B04DFF", children=[corner("pill")]),
            frame("MapDot", (0, 10, 0, 10), (0.74, 0, 0.5, 0), (0.5, 0.5), z=4, fill="#4DE1FF", children=[corner("pill")]),
        ],
    )
    mini = frame(
        "Minimap",
        (1, 0, 1, 0),
        z=1,
        children=[
            frame("Ring", (1, 0, 1, 0), z=1, fill=RIM, alpha=0.15, children=[corner("pill"), stroke(OUTLINE, 2, 0.3)]),
            frame("Field", (1, -8, 1, -8), (0.5, 0, 0.5, 0), (0.5, 0.5), z=2, fill="#12201A", alpha=0.12, children=[corner("pill"), shade(0.75)]),
            dots,
            icon("PlayerArrow", "IconArrowPlayer", 28, (0.5, 0, 0.5, 0), (0.5, 0.5), z=5),
        ]
        + letters,
    )
    return frame("TopRight", (0, 220, 0, 220), (1, -16, 0, 16), (1, 0), z=2, children=[mini])


def loadout_slot(key, level, rim, order, max_level=False):
    return frame(
        "LoadoutSlot",
        (0, 56, 0, 60),
        z=2,
        order=order,
        children=[
            frame("Tile", (0, 56, 0, 56), z=2, fill="#0F1913", alpha=0.1, children=[corner(10), shade(0.7), stroke(rim, 2, 0.25)]),
            icon("Icon", key, 44, (0.5, 0, 0, 28), (0.5, 0.5), z=3),
            label(
                "Level",
                "MAX" if max_level else str(level),
                (0, 36 if max_level else 28, 0, 18),
                (1, 3, 1, 0),
                (1, 1),
                z=4,
                px=14,
                colour=GOLD,
                outline=0,
                fill="#0B120E",
                fill_alpha=0.05,
                children=[corner("pill")],
            ),
        ],
    )


def empty_slot(rim, order, slot=56):
    """An unused weapon or tome socket (HudController clones the slot and empties it)."""
    s = loadout_slot("IconSword", 1, rim, order)
    s["properties"]["Size"] = U2(0, slot, 0, slot + 4)
    tile = find(s, "Tile")
    tile["properties"]["BackgroundTransparency"] = 0.55
    find(tile, "Stroke")["properties"]["Transparency"] = 0.78
    find(s, "Icon")["properties"]["Visible"] = False
    find(s, "Level")["properties"]["Visible"] = False
    return s


def fill_sockets(tree):
    for row, rim in (("WeaponRow", RIM), ("TomeRow", TEAL)):
        r = find(tree, row)
        have = len([c for c in r["children"] if c["name"] == "LoadoutSlot"])
        for i in range(have, 4):
            r["children"].append(empty_slot(rim, i + 1))


def item_slot(key, rarity, count, order):
    return frame(
        "ItemSlot",
        (0, 40, 0, 40),
        z=2,
        order=order,
        fill=TRACK,
        alpha=0.25,
        children=[
            corner(8),
            stroke(RARITY[rarity], 1.5, 0.35),
            icon("Icon", key, 34, (0.5, 0, 0.5, 0), (0.5, 0.5), z=3),
            label("Count", f"x{count}", (0, 30, 0, 16), (1, 3, 1, 3), (1, 1), z=4, px=13, align="Right", visible=count > 1),
        ],
    )


def bottom_centre():
    weapons = frame(
        "WeaponRow",
        (0, 242, 0, 60),
        z=2,
        order=1,
        children=[
            listing("Horizontal", 6),
            loadout_slot("IconSword", 7, RIM, 1),
            loadout_slot("IconFireStaff", 3, RIM, 2),
            loadout_slot("IconFrostRing", 0, RIM, 3, max_level=True),
        ],
    )
    tomes = frame(
        "TomeRow",
        (0, 242, 0, 60),
        z=2,
        order=3,
        children=[
            listing("Horizontal", 6),
            loadout_slot("IconTomeDamage", 4, TEAL, 1),
            loadout_slot("IconTomeAgility", 2, TEAL, 2),
        ],
    )
    loadout = frame(
        "Loadout",
        (0, 506, 0, 60),
        (0.5, 0, 1, -10),
        (0.5, 1),
        z=2,
        children=[
            listing("Horizontal", 10, h="Center", v="Center"),
            weapons,
            frame("Divider", (0, 2, 0, 44), z=2, order=2, fill=RIM, alpha=0.6),
            tomes,
        ],
    )
    items = frame(
        "ItemStrip",
        (1, -20, 0, 40),
        (0.5, 0, 0, 10),
        (0.5, 0),
        z=2,
        children=[
            item_slot("IconItemLuckyClover", "Common", 3, 1),
            item_slot("IconItemZoomSocks", "Common", 1, 2),
            item_slot("IconItemFrostShard", "Rare", 2, 3),
        ],
    )
    tray = panel("BuildTray", (0, 526, 0, 128), z=1, alpha=0.25, radius=14, rim_alpha=0.6, order=2, children=[items, loadout])
    prompt = frame(
        "InteractPrompt",
        (0, 0, 0, 52),
        z=3,
        order=1,
        auto="X",
        visible=False,
        fill=PANEL,
        alpha=0.12,
        children=[
            corner("pill"),
            shade(0.8),
            stroke(RIM, 1.5, 0.35),
            padding(8, 0, 20, 0),
            listing("Horizontal", 12, v="Center"),
            frame(
                "KeyCap",
                (0, 38, 0, 38),
                z=4,
                order=1,
                fill=PARCHMENT,
                children=[
                    corner(9),
                    shade(0.82),
                    stroke(OUTLINE, 2, 0.1),
                    label("Key", "E", (1, 0, 1, 0), z=5, px=22, colour="#2A2214", outline=0),
                ],
            ),
            label("Text", "Open chest (30 gold)", (0, 0, 0, 40), z=4, font=BODY, px=20, align="Left", order=2, auto="X"),
        ],
    )
    return frame(
        "BottomCenter",
        (0, 900, 0, 320),
        (0.5, 0, 1, -16),
        (0.5, 1),
        z=2,
        children=[listing("Vertical", 10, h="Center", v="Bottom"), prompt, tray],
    )


def stage_title():
    return frame(
        "StageTitle",
        (0, 1000, 0, 208),
        (0.5, 0, 0.3, 0),  # above the hero stepping out of the portal (T8)
        (0.5, 0.5),
        z=6,
        visible=False,
        children=[
            label("TierLabel", "Tier 1", (1, 0, 0, 40), z=2, font=BODY, px=30, colour=TAN, outline=2),
            frame("RuleTop", (0, 620, 0, 3), (0.5, 0, 0, 54), (0.5, 0), z=2, fill=RIM, alpha=0.15),
            label("StageName", "THE WARDWOOD", (1, 0, 0, 84), (0, 0, 0, 64), z=2, px=80, outline=4, scaled=80),
            frame("RuleBottom", (0, 620, 0, 3), (0.5, 0, 0, 158), (0.5, 0), z=2, fill=RIM, alpha=0.15),
            label("StageJoke", "Mind the roots.", (1, 0, 0, 34), (0, 0, 0, 172), z=2, font=BODY, px=26, colour=SOFT, outline=2),
        ],
    )


def build_tree():
    safe = frame(
        "Safe",
        (0, 1920, 0, 1022),
        (0, 0, 0, 58),
        z=2,
        children=[
            top_left(),
            top_centre(),
            minimap(),
            bottom_centre(),
            stage_title(),
        ],
    )
    downed = frame(
        "DownedOverlay",
        (1, 0, 1, 0),
        z=3,
        fill="#0A0606",
        alpha=0.45,
        visible=False,
        children=[
            label("DownedLabel", "YOU ARE DOWN", (0, 1000, 0, 84), (0.5, 0, 0.36, 0), (0.5, 0.5), z=4, px=72, colour=DANGER, outline=4),
            frame(
                "ReviveBack",
                (0, 520, 0, 24),
                (0.5, 0, 0.36, 64),
                (0.5, 0),
                z=4,
                fill=TRACK,
                alpha=0.1,
                children=[
                    corner("pill"),
                    stroke(RIM, 1.5, 0.3),
                    frame("ReviveFill", (0.4, 0, 1, 0), z=5, fill=GOLD, children=[corner("pill"), shade(0.75)]),
                ],
            ),
            label(
                "SpectateName",
                "A teammate can revive you: hold on",
                (0, 800, 0, 32),
                (0.5, 0, 0.36, 102),
                (0.5, 0),
                z=4,
                font=BODY,
                px=24,
                outline=2,
            ),
        ],
    )
    letterbox = frame(
        "Letterbox",
        (1, 0, 1, 0),
        z=4,
        visible=False,
        children=[
            frame("Top", (1, 0, 0, 110), z=4, fill="#000000"),
            frame("Bottom", (1, 0, 0, 110), (0, 0, 1, 0), (0, 1), z=4, fill="#000000"),
        ],
    )
    hurt = frame("HurtFlash", (1, 0, 1, 0), z=1, fill="#E5121B", alpha=1)
    return node(
        "ScreenGui",
        "Hud",
        {"DisplayOrder": 10, "ResetOnSpawn": False, "ZIndexBehavior": "Sibling", "IgnoreGuiInset": True, "Enabled": True},
        [hurt, safe, downed, letterbox],
    )


# ---------------------------------------------------------------- the model and its manifest


def strip_names(n):
    """Rojo's model format keeps the root's name out of the file."""
    out = {k: v for k, v in n.items() if k != "name"}
    return out


def manifest(tree):
    rows = []

    def walk(n, path):
        if n["className"].startswith("UI"):
            return
        p = f"{path}.{n['name']}" if path else n["name"]
        rows.append({"path": p, "class": n["className"], "visible": n["properties"].get("Visible", True)})
        for c in n["children"]:
            walk(c, p)

    for c in tree["children"]:
        walk(c, "")
    return rows


# ---------------------------------------------------------------- previews

FONT_FILES = {}


def find_fonts(folder):
    if not folder or not os.path.isdir(folder):
        return
    for f in os.listdir(folder):
        low = f.lower()
        if "luckiest" in low:
            FONT_FILES[DISPLAY] = os.path.join(folder, f)
        elif "fredoka" in low:
            FONT_FILES[BODY] = os.path.join(folder, f)


def apply_layout(tree, L, margin, strip=None):
    """What HudController._layout does at runtime, for the previews."""
    sz = L["sizes"]
    safe = find(tree, "Safe")
    s = L["safe"]
    safe["properties"]["Position"] = U2(0, s["x"], 0, s["y"])
    safe["properties"]["Size"] = U2(0, s["w"], 0, s["h"])
    col = sz["column"]
    top_left = find(tree, "TopLeft")
    top_left["properties"]["Position"] = U2(0, margin, 0, L["topLeft"])
    top_left["properties"]["Size"] = U2(0, col, 0, 0)
    find(tree, "Vitals")["properties"]["Size"] = U2(0, col, 0, sz["vitals"])
    for name in ("QuestTracker", "TeammateBars"):
        find(tree, name)["properties"]["Size"] = U2(0, min(380, col - 20), 0, 0)
    centre = find(tree, "TopCenter")
    centre["properties"]["Position"] = U2(0.5, 0, 0, L["topCentre"])
    centre["properties"]["Size"] = U2(0, L["centreWidth"], 0, 0)
    if strip is not None:
        xp = L["xp"]
        bar = find(strip, "Strip")
        bar["properties"]["Position"] = U2(0, xp["x"], 0, xp["y"])
        bar["properties"]["Size"] = U2(0, xp["w"], 0, xp["h"])  # the runtime sets (1 / scale) of the screen
    find(tree, "TimerPlate")["properties"]["Size"] = U2(0, sz["plate"], 0, sz["plateHeight"])
    find(tree, "BossBars")["properties"]["Size"] = U2(0, min(760, L["centreWidth"]), 0, 0)
    for mini in find_all(tree, "MiniBar"):
        mini["properties"]["Size"] = U2(0, min(240, (L["centreWidth"] - 14) / 2), 0, 40)
    find(tree, "Banner")["properties"]["Size"] = U2(0, L["centreWidth"], 0, 96)
    find(tree, "Toast")["properties"]["Size"] = U2(0, min(400, L["centreWidth"]), 0, 70)
    right = find(tree, "TopRight")
    right["properties"]["Position"] = U2(1, -(margin + L["shiftRight"]), 0, L["topRight"])
    right["properties"]["Size"] = U2(0, sz["minimap"], 0, sz["minimap"])
    tray_layout(tree, sz)
    if L["compact"]:
        quests = [c for c in find(tree, "QuestTracker")["children"] if c["name"] == "QuestLine"]
        for q in quests[sz["quests"] :]:
            q["properties"]["Visible"] = False


def tray_layout(tree, sz):
    """The build tray's size from its slot and item sizes (HudController._layoutTray)."""
    slot, gap = sz["slot"], 6
    row_w = 4 * slot + 3 * gap
    for row in ("WeaponRow", "TomeRow"):
        r = find(tree, row)
        r["properties"]["Size"] = U2(0, row_w, 0, slot + 4)
        for c in r["children"]:
            if c["name"] == "LoadoutSlot":
                c["properties"]["Size"] = U2(0, slot, 0, slot + 4)
                find(c, "Tile")["properties"]["Size"] = U2(0, slot, 0, slot)
                find(c, "Icon")["properties"]["Size"] = U2(0, slot - 12, 0, slot - 12)
                find(c, "Icon")["properties"]["Position"] = U2(0.5, 0, 0, slot / 2)
    loadout_w = 2 * row_w + 22
    find(tree, "Loadout")["properties"]["Size"] = U2(0, loadout_w, 0, slot + 4)
    strip = find(tree, "ItemStrip")
    slots = [c for c in strip["children"] if c["name"] == "ItemSlot" and c["properties"].get("Visible", True)]
    tile, igap = sz["item"], 4
    per_row = max(1, int((loadout_w + igap) // (tile + igap)))
    count = len(slots)
    room = per_row * sz["itemRows"]
    rows = math.ceil(min(count, room) / per_row) if count else 0
    if count > room:
        # HudLayout.strip: the last tile becomes "+N"
        chip = slots[room - 1]
        find(chip, "Icon")["properties"]["Visible"] = False
        more = find(chip, "Count")["properties"]
        more.update({"Visible": True, "Text": f"+{count - room + 1}", "TextSize": 16, "TextXAlignment": "Center"})
        more.update({"AnchorPoint": V2(0.5, 0.5), "Position": U2(0.5, 0, 0.5, 0), "Size": U2(1, 0, 1, 0)})
    for i, c in enumerate(slots):
        if i >= room:
            c["properties"]["Visible"] = False
            continue
        row, col = divmod(i, per_row)
        in_row = min(per_row, min(count, room) - row * per_row)
        x = (loadout_w - (in_row * tile + (in_row - 1) * igap)) / 2 + col * (tile + igap)
        c["properties"]["Size"] = U2(0, tile, 0, tile)
        c["properties"]["Position"] = U2(0, x, 0, row * (tile + igap))
        find(c, "Icon")["properties"]["Size"] = U2(0, tile - 6, 0, tile - 6)
    strip_h = rows * (tile + igap) - igap if rows else 0
    strip["properties"]["Size"] = U2(0, loadout_w, 0, max(strip_h, 0))
    strip["properties"]["Visible"] = rows > 0
    tray_h = 10 + (strip_h + 8 if rows else 0) + slot + 4 + 10
    find(tree, "BuildTray")["properties"]["Size"] = U2(0, loadout_w + 20, 0, tray_h)


def find(n, name):
    if n.get("name") == name:
        return n
    for c in n.get("children", []):
        r = find(c, name)
        if r:
            return r
    return None


def find_all(n, name, out=None):
    out = [] if out is None else out
    if n.get("name") == name:
        out.append(n)
    for c in n.get("children", []):
        find_all(c, name, out)
    return out


class Renderer:
    def __init__(self, Image, ImageDraw, ImageFont, icons_dir):
        self.Image, self.ImageDraw, self.ImageFont = Image, ImageDraw, ImageFont
        self.icons_dir = icons_dir
        self.font_cache = {}
        self.icon_cache = {}

    # -------- helpers

    def font(self, family, px):
        px = max(6, int(round(px)))
        key = (family, px)
        if key not in self.font_cache:
            path = FONT_FILES.get(family)
            if path:
                f = self.ImageFont.truetype(path, px)
                if family == BODY:
                    try:
                        f.set_variation_by_name("SemiBold")  # the closest cut to Fredoka One
                    except Exception:
                        pass
            else:
                f = self.ImageFont.load_default()
            self.font_cache[key] = f
        return self.font_cache[key]

    def icon(self, key, size):
        size = max(1, int(round(size)))
        ck = (key, size)
        if ck not in self.icon_cache:
            path = os.path.join(self.icons_dir, key + ".png")
            if os.path.exists(path):
                im = self.Image.open(path).convert("RGBA")
                im.thumbnail((size, size), self.Image.LANCZOS)
            else:
                im = None
            self.icon_cache[ck] = im
        return self.icon_cache[ck]

    @staticmethod
    def rgb(c3, mult=1.0):
        r, g, b = c3["Color3"]
        return (int(r * 255 * mult), int(g * 255 * mult), int(b * 255 * mult))

    @staticmethod
    def kids(n, cls):
        return [c for c in n["children"] if c["className"] == cls]

    @staticmethod
    def kid(n, cls):
        for c in n["children"]:
            if c["className"] == cls:
                return c
        return None

    def text_of(self, n):
        p = n["properties"]
        return p.get("Text", "")

    def text_width(self, n, s):
        p = n["properties"]
        f = self.font(p["FontFace"]["Font"]["family"], p.get("TextSize", 14) * s)
        return f.getlength(self.text_of(n))

    # -------- layout

    def pad(self, n, s):
        pd = self.kid(n, "UIPadding")
        if not pd:
            return 0, 0, 0, 0
        p = pd["properties"]
        return (p["PaddingLeft"]["UDim"][1] * s, p["PaddingTop"]["UDim"][1] * s, p["PaddingRight"]["UDim"][1] * s, p["PaddingBottom"]["UDim"][1] * s)

    @staticmethod
    def visible(n):
        return n["properties"].get("Visible", True) and not n["className"].startswith("UI")

    def measure(self, n, pw, ph, s):
        """The size of n inside a parent pw x ph, AutomaticSize included."""
        p = n["properties"]
        (xs, xo), (ys, yo) = p["Size"]["UDim2"]
        w, h = xs * pw + xo * s, ys * ph + yo * s
        auto = p.get("AutomaticSize")
        if not auto:
            return w, h
        l, t, r, b = self.pad(n, s)
        cw = ch = 0
        if n["className"] == "TextLabel":
            cw = self.text_width(n, s)
            ch = p.get("TextSize", 14) * s
        lay = self.kid(n, "UIListLayout")
        if lay:
            horiz = lay["properties"]["FillDirection"] == "Horizontal"
            gap = lay["properties"]["Padding"]["UDim"][1] * s
            sizes = [self.measure(c, w - l - r, h - t - b, s) for c in n["children"] if self.visible(c)]
            if sizes:
                if horiz:
                    cw = sum(x for x, _ in sizes) + gap * (len(sizes) - 1)
                    ch = max(y for _, y in sizes)
                else:
                    ch = sum(y for _, y in sizes) + gap * (len(sizes) - 1)
                    cw = max(x for x, _ in sizes)
        if "X" in auto:
            w = max(w, cw + l + r)
        if "Y" in auto:
            h = max(h, ch + t + b)
        return w, h

    def layout(self, n, rect, s):
        """Give every GuiObject under n its rect (x, y, w, h) in pixels."""
        n["_rect"] = rect
        x, y, w, h = rect
        l, t, r, b = self.pad(n, s)
        ix, iy, iw, ih = x + l, y + t, w - l - r, h - t - b
        lay = self.kid(n, "UIListLayout")
        children = [c for c in n["children"] if self.visible(c)]
        if lay:
            lp = lay["properties"]
            horiz = lp["FillDirection"] == "Horizontal"
            gap = lp["Padding"]["UDim"][1] * s
            children.sort(key=lambda c: c["properties"].get("LayoutOrder", 0))
            sizes = [self.measure(c, iw, ih, s) for c in children]
            total = sum((sw if horiz else sh) for sw, sh in sizes) + gap * max(0, len(sizes) - 1)
            main_align = lp["HorizontalAlignment"] if horiz else lp["VerticalAlignment"]
            space = iw if horiz else ih
            start = {"Left": 0, "Top": 0, "Center": (space - total) / 2, "Right": space - total, "Bottom": space - total}[main_align]
            cursor = start
            for c, (cw, ch) in zip(children, sizes):
                if horiz:
                    va = lp["VerticalAlignment"]
                    cy = {"Top": 0, "Center": (ih - ch) / 2, "Bottom": ih - ch}[va]
                    self.layout(c, (ix + cursor, iy + cy, cw, ch), s)
                    cursor += cw + gap
                else:
                    ha = lp["HorizontalAlignment"]
                    cx = {"Left": 0, "Center": (iw - cw) / 2, "Right": iw - cw}[ha]
                    self.layout(c, (ix + cx, iy + cursor, cw, ch), s)
                    cursor += ch + gap
        else:
            for c in children:
                cw, ch = self.measure(c, iw, ih, s)
                (pxs, pxo), (pys, pyo) = c["properties"]["Position"]["UDim2"]
                ax, ay = c["properties"]["AnchorPoint"]["Vector2"]
                cx = ix + pxs * iw + pxo * s - ax * cw
                cy = iy + pys * ih + pyo * s - ay * ch
                self.layout(c, (cx, cy, cw, ch), s)

    # -------- drawing

    def radius(self, n, w, h, s):
        c = self.kid(n, "UICorner")
        if not c:
            return 0
        sc, off = c["properties"]["CornerRadius"]["UDim"]
        return min(min(w, h) / 2, sc * min(w, h) + off * s)

    def draw_frame(self, img, n, s):
        Image, ImageDraw = self.Image, self.ImageDraw
        p = n["properties"]
        x, y, w, h = n["_rect"]
        if w < 1 or h < 1:
            return
        rad = self.radius(n, w, h, s)
        alpha = 1 - p.get("BackgroundTransparency", 0)
        box = (int(round(x)), int(round(y)), int(round(x + w)) - 1, int(round(y + h)) - 1)
        if alpha > 0.003 and "BackgroundColor3" in p:
            base = self.rgb(p["BackgroundColor3"])
            grad = self.kid(n, "UIGradient")
            bw, bh = box[2] - box[0] + 1, box[3] - box[1] + 1
            if bw < 1 or bh < 1:
                return
            fill = Image.new("RGBA", (bw, bh), base + (255,))
            if grad and "Color" in grad["properties"] and grad["properties"].get("Rotation", 0) == 90:
                kps = grad["properties"]["Color"]["ColorSequence"]["keypoints"]
                top, bot = kps[0]["color"][0], kps[-1]["color"][0]
                col = Image.new("RGBA", (1, bh))
                for yy in range(bh):
                    m = top + (bot - top) * (yy / max(1, bh - 1))
                    col.putpixel((0, yy), tuple(int(c * m) for c in base) + (255,))
                fill = col.resize((bw, bh))
            elif grad and "Color" in grad["properties"]:
                kps = grad["properties"]["Color"]["ColorSequence"]["keypoints"]
                row = Image.new("RGBA", (bw, 1))
                for xx in range(bw):
                    t = xx / max(1, bw - 1)
                    for a, b2 in zip(kps, kps[1:]):
                        if a["time"] <= t <= b2["time"]:
                            k = (t - a["time"]) / max(1e-6, b2["time"] - a["time"])
                            c = [a["color"][i] + (b2["color"][i] - a["color"][i]) * k for i in range(3)]
                            break
                    row.putpixel((xx, 0), tuple(int(c[i] * base[i]) for i in range(3)) + (255,))
                fill = row.resize((bw, bh))
            mask = Image.new("L", (bw, bh), 0)
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, bw - 1, bh - 1), radius=int(rad), fill=int(255 * alpha))
            fade = next((g for g in self.kids(n, "UIGradient") if "Transparency" in g["properties"]), None)
            if fade:
                kps = fade["properties"]["Transparency"]["NumberSequence"]["keypoints"]
                row = Image.new("L", (bw, 1))
                for xx in range(bw):
                    t = xx / max(1, bw - 1)
                    v = kps[-1]["value"]
                    for a, b2 in zip(kps, kps[1:]):
                        if a["time"] <= t <= b2["time"]:
                            v = a["value"] + (b2["value"] - a["value"]) * (t - a["time"]) / max(1e-6, b2["time"] - a["time"])
                            break
                    row.putpixel((xx, 0), int(255 * (1 - v)))
                from PIL import ImageChops

                mask = ImageChops.multiply(mask, row.resize((bw, bh)))
            img.alpha_composite(Image.composite(fill, Image.new("RGBA", (bw, bh), (0, 0, 0, 0)), mask), (box[0], box[1]))
        for st in self.kids(n, "UIStroke"):
            sp = st["properties"]
            if sp.get("ApplyStrokeMode") == "Contextual" and n["className"] == "TextLabel":
                continue
            t = max(1, sp.get("Thickness", 1) * s)
            a = 1 - sp.get("Transparency", 0)
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            ImageDraw.Draw(layer).rounded_rectangle(
                (box[0] - t, box[1] - t, box[2] + t, box[3] + t),
                radius=int(rad + t),
                outline=self.rgb(sp["Color"]) + (int(255 * a),),
                width=int(round(t)),
            )
            img.alpha_composite(layer)

    def draw_text(self, img, n, s):
        p = n["properties"]
        text = self.text_of(n)
        if not text:
            return
        x, y, w, h = n["_rect"]
        l, t, r, b = self.pad(n, s)
        x, y, w, h = x + l, y + t, w - l - r, h - t - b
        size = p.get("TextSize", 14) * s
        family = p["FontFace"]["Font"]["family"]
        if p.get("TextScaled"):
            cap = self.kid(n, "UITextSizeConstraint")
            size = min(h, cap["properties"]["MaxTextSize"] * s if cap else h)
            while size > 6 and self.font(family, size).getlength(text) > w:
                size -= 1
        f = self.font(family, size)
        if p.get("TextTruncate") == "AtEnd" and f.getlength(text) > w:
            while text and f.getlength(text + "...") > w:
                text = text[:-1]
            text += "..."
        ha = {"Left": "l", "Center": "m", "Right": "r"}[p.get("TextXAlignment", "Center")]
        va = {"Top": "a", "Center": "m", "Bottom": "d"}[p.get("TextYAlignment", "Center")]
        px = {"l": x, "m": x + w / 2, "r": x + w}[ha]
        py = {"a": y, "m": y + h / 2, "d": y + h}[va]
        alpha = 1 - p.get("TextTransparency", 0)
        colour = self.rgb(p.get("TextColor3", C3(INK))) + (int(255 * alpha),)
        st = None
        for k in self.kids(n, "UIStroke"):
            if k["properties"].get("ApplyStrokeMode") == "Contextual":
                st = k
        layer = self.Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = self.ImageDraw.Draw(layer)
        if st:
            sw = max(1, int(round(st["properties"]["Thickness"] * s)))
            sa = (1 - st["properties"].get("Transparency", 0)) * alpha
            d.text((px, py), text, font=f, fill=colour, anchor=ha + va, stroke_width=sw, stroke_fill=self.rgb(st["properties"]["Color"]) + (int(255 * sa),))
        else:
            d.text((px, py), text, font=f, fill=colour, anchor=ha + va)
        img.alpha_composite(layer)

    def draw_image(self, img, n, s):
        p = n["properties"]
        key = n.get("attributes", {}).get("IconName")
        x, y, w, h = n["_rect"]
        im = self.icon(key, min(w, h)) if key else None
        if im is None:
            return
        if p.get("ImageTransparency", 0) >= 0.999:
            return
        if "ImageColor3" in p:
            r, g, b = p["ImageColor3"]["Color3"]
            px = im.load()
            im = im.copy()
            px = im.load()
            for yy in range(im.size[1]):
                for xx in range(im.size[0]):
                    pr, pg, pb, pa = px[xx, yy]
                    px[xx, yy] = (int(pr * r), int(pg * g), int(pb * b), pa)
        ox = int(round(x + (w - im.size[0]) / 2))
        oy = int(round(y + (h - im.size[1]) / 2))
        if self.kid(n, "UICorner"):
            rad = self.radius(n, im.size[0], im.size[1], s)
            mask = self.Image.new("L", im.size, 0)
            self.ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.size[0] - 1, im.size[1] - 1), radius=int(rad), fill=255)
            a = im.getchannel("A")
            from PIL import ImageChops

            im.putalpha(ImageChops.multiply(a, mask))
        layer = self.Image.new("RGBA", img.size, (0, 0, 0, 0))
        layer.paste(im, (ox, oy), im)
        img.alpha_composite(layer)
        # the image's own border stroke (portraits)
        for st in self.kids(n, "UIStroke"):
            sp = st["properties"]
            t = max(1, sp.get("Thickness", 1) * s)
            rad = self.radius(n, w, h, s)
            ring = self.Image.new("RGBA", img.size, (0, 0, 0, 0))
            self.ImageDraw.Draw(ring).rounded_rectangle(
                (x - t, y - t, x + w + t - 1, y + h + t - 1),
                radius=int(rad + t),
                outline=self.rgb(sp["Color"]) + (int(255 * (1 - sp.get("Transparency", 0))),),
                width=int(round(t)),
            )
            img.alpha_composite(ring)

    def draw(self, img, n, s):
        if not self.visible(n) and n["className"] != "ScreenGui":
            return
        if "_rect" in n:
            if n["className"] in ("Frame", "TextLabel"):
                self.draw_frame(img, n, s)
            if n["className"] == "TextLabel":
                self.draw_text(img, n, s)
            if n["className"] == "ImageLabel":
                self.draw_image(img, n, s)
        kids = [c for c in n["children"] if self.visible(c)]
        kids.sort(key=lambda c: c["properties"].get("ZIndex", 1))
        if n["properties"].get("ClipsDescendants") and "_rect" in n:
            layer = self.Image.new("RGBA", img.size, (0, 0, 0, 0))
            for c in kids:
                self.draw(layer, c, s)
            x, y, w, h = n["_rect"]
            mask = self.Image.new("L", img.size, 0)
            self.ImageDraw.Draw(mask).rectangle((x, y, x + w, y + h), fill=255)
            from PIL import ImageChops

            layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
            img.alpha_composite(layer)
        else:
            for c in kids:
                self.draw(img, c, s)

    def render(self, tree, size, s):
        for c in tree["children"]:
            if self.visible(c):
                w, h = self.measure(c, size[0], size[1], s)
                (pxs, pxo), (pys, pyo) = c["properties"]["Position"]["UDim2"]
                ax, ay = c["properties"]["AnchorPoint"]["Vector2"]
                self.layout(c, (pxs * size[0] + pxo * s - ax * w, pys * size[1] + pyo * s - ay * h, w, h), s)
        img = self.Image.new("RGBA", size, (0, 0, 0, 0))
        self.draw(img, tree, s)
        return img


# ---------------------------------------------------------------- preview states


def set_text(tree, path_names, text):
    n = tree
    for nm in path_names:
        n = find(n, nm)
    n["properties"]["Text"] = text


def show(tree, name, on=True):
    find(tree, name)["properties"]["Visible"] = on


def state_play(tree):
    """Solo, minute five: no team panel, no boss."""
    show(tree, "TeammateBars", False)
    fill_sockets(tree)


def state_boss(tree):
    """Co-op overtime with the stage boss, a surge banner and a chest prompt."""
    show(tree, "DifficultyPill")
    show(tree, "BossBars")
    show(tree, "Banner")
    show(tree, "InteractPrompt")
    plate = find(tree, "TimerPlate")
    find(plate, "Stroke")["properties"]["Color"] = C3(DANGER)
    find(plate, "Stroke")["properties"]["Transparency"] = 0.2
    find(tree, "TimerCaption")["properties"]["Text"] = "OVERTIME"
    find(tree, "TimerCaption")["properties"]["TextColor3"] = C3(DANGER)
    find(tree, "StageTimer")["properties"]["Text"] = "1:12"
    find(tree, "StageTimer")["properties"]["TextColor3"] = C3("#FF8C73")
    find(tree, "RunClock")["properties"]["Text"] = "11:12"
    # a fuller build: four weapons, four tomes, a long item strip
    weapons = find(tree, "WeaponRow")
    tomes = find(tree, "TomeRow")
    weapons["children"].append(loadout_slot("IconLightningStaff", 9, RIM, 4))
    tomes["children"] += [loadout_slot("IconTomeCooldown", 6, TEAL, 3), loadout_slot("IconTomeLuck", 0, TEAL, 4, max_level=True)]
    strip = find(tree, "ItemStrip")
    extra = [
        ("IconItemProteinGoop", "Common", 4),
        ("IconItemSusJuice", "Common", 2),
        ("IconItemDodgyBattery", "Uncommon", 1),
        ("IconItemBandageBox", "Common", 5),
        ("IconItemStinkyCheese", "Uncommon", 2),
        ("IconItemGiantSlayerPin", "Rare", 1),
        ("IconItemEchoGem", "Epic", 1),
        ("IconItemPocketCampfire", "Uncommon", 3),
        ("IconItemFeatherweight", "Common", 2),
        ("IconItemStaticMitts", "Rare", 1),
        ("IconItemSkeletonKey", "Legendary", 1),
        ("IconItemCrackedGoggles", "Common", 6),
        ("IconItemBigIceCube", "Rare", 1),
    ]
    for i, (k, r, c) in enumerate(extra):
        strip["children"].append(item_slot(k, r, c, 4 + i))
    fill_sockets(tree)
    find(tree, "Price")["properties"]["TextColor3"] = C3(GOLD)
    find(find(tree, "NextChest"), "Stroke")["properties"]["Transparency"] = 0.05
    find(tree, "GoldCount")["properties"]["Text"] = "1,906"
    find(tree, "Price")["properties"]["Text"] = "112"
    quests = find(tree, "QuestTracker")
    first = [c for c in quests["children"] if c["name"] == "QuestLine"][0]
    done = quest_line("Find the Boss Portal", True, 1)
    quests["children"][quests["children"].index(first)] = done
    # Sir Clonk is being revived
    tag = find_all(tree, "DownedTag")[2]
    tag["properties"]["Visible"] = True
    tag["properties"]["Text"] = "REVIVING"
    tag["properties"]["TextColor3"] = C3(GOLD)
    tag["properties"]["BackgroundColor3"] = C3("#2A2214")
    fills = find_all(tree, "HPFill")
    fills[2]["properties"]["Size"] = U2(0.55, 0, 1, 0)
    fills[2]["properties"]["BackgroundColor3"] = C3(GOLD)
    portraits = find_all(tree, "Portrait")
    portraits[2]["properties"]["ImageColor3"] = C3("#8A8A8A")


def state_levelup(tree):
    state_play(tree)
    show(tree, "LevelUpText")
    show(tree, "Toast")
    find(tree, "LevelLabel")["properties"]["Text"] = "13"


STRIP_STATES = {"Hud_levelup": "rainbow", "Hud_play": 0.62, "Hud_boss": 0.35, "Hud_phone": 0.8}


def strip_state(strip, how):
    """The strip in a preview: a fill share, or the level-up rainbow."""
    if how == "rainbow":
        find(strip, "Rainbow")["properties"]["Visible"] = True
    else:
        find(strip, "Fill")["properties"]["Size"] = U2(how, 0, 1, 0)


def draw_chrome(img, ImageDraw, screen, phone=False):
    """Roblox's own top bar (left buttons), approximated, and on a phone the
    notch and the Overlay's touch buttons, so the previews show the clearance."""
    d = ImageDraw.Draw(img)
    k = img.size[0] / screen["width"]
    tb = screen.get("topbar")
    bar_h = (tb["y1"] if tb else 58) * k
    pad = 6 * k
    btn = bar_h - 2 * pad
    x0 = pad + screen["core"]["left"] * k
    d.rounded_rectangle((x0, pad, x0 + btn, pad + btn), radius=int(btn / 2), fill=(20, 20, 24, 200))
    end = (tb["x0"] if tb else 250) * k - pad
    d.rounded_rectangle((x0 + btn + pad, pad, end, pad + btn), radius=int(btn / 2), fill=(20, 20, 24, 200))
    for i in range(3):
        cx = x0 + btn + pad + btn * (0.7 + i * 1.1)
        if cx + btn * 0.3 < end:
            d.ellipse((cx - btn * 0.22, pad + btn * 0.28, cx + btn * 0.22, pad + btn * 0.72), fill=(235, 235, 235, 220))
    if phone:
        notch = 30 * k
        d.rounded_rectangle((-notch, img.size[1] * 0.3, notch * 0.9, img.size[1] * 0.7), radius=int(notch), fill=(0, 0, 0, 255))
        d.rounded_rectangle((img.size[0] * 0.38, img.size[1] - 9 * k, img.size[0] * 0.62, img.size[1] - 5 * k), radius=int(3 * k), fill=(255, 255, 255, 200))
        s = min(screen["width"] / 1920, screen["height"] / 1080)
        W, H = screen["width"], screen["height"]
        for size, right, top, bottom in [(140, 70, None, 70), (132, 234, None, 50), (132, 54, None, 234), (116, 30, 380, None), (116, 30, 512, None)]:
            x1 = (W - right * s) * k
            if top is not None:
                y0 = top * s * k
            else:
                y0 = (H - bottom * s) * k - size * s * k
            sz = size * s * k
            d.ellipse((x1 - sz, y0, x1, y0 + sz), fill=(255, 255, 255, 60), outline=(255, 255, 255, 140), width=max(1, int(2 * k)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts", default=os.environ.get("BONK_FONTS", ""))
    ap.add_argument("--no-png", action="store_true")
    args = ap.parse_args()

    load_icon_ids()
    tree = build_tree()
    strip = xp_bar()
    # the shipped samples sit where the runtime would put them on a 1080p screen
    tray_layout(tree, {"slot": 56, "item": 40, "itemRows": 2})

    for model, name in ((tree, "Hud"), (strip, "XpBar")):
        model_path = os.path.join(ROOT, f"src/ui/{name}.model.json")
        with open(model_path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(strip_names(model), f, indent=1, ensure_ascii=False)
            f.write("\n")
        print(f"wrote {model_path}")
    rows = manifest(tree) + [dict(r, path="XpBar." + r["path"]) for r in manifest(strip)]
    with open(os.path.join(ROOT, "assets/ui/manifest.Hud.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(rows, f, indent=1)
        f.write("\n")

    if args.no_png:
        return
    try:
        from PIL import Image, ImageDraw, ImageFilter, ImageFont
    except ImportError:
        print("Pillow missing: no previews")
        return
    find_fonts(args.fonts)
    cases = json.loads(subprocess.run(["lune", "run", "design/ui_specs/hud_cases.luau"], capture_output=True, text=True, check=True, stdin=subprocess.DEVNULL).stdout)
    margin = cases["margin"]
    backdrop_sheet = Image.open(os.path.join(ROOT, "work/map/preview_sheet.jpg")).convert("RGB")
    tile = backdrop_sheet.crop((480 + 2, 18, 960 - 2, 270)).resize((1920, 1080), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.2))
    renderer = Renderer(Image, ImageDraw, ImageFont, os.path.join(ROOT, "assets/ui/icons"))
    out_dir = os.path.join(ROOT, "assets/ui/mockups")
    shots = []
    for name, case, state, dpr in [
        ("Hud_play", "desktop", state_play, 1),
        ("Hud_boss", "desktop", state_boss, 1),
        ("Hud_levelup", "laptop", state_levelup, 1),
        ("Hud_phone", "phone", state_boss, 2),
    ]:
        c = cases[case]
        screen, L = c["screen"], c["layout"]
        W, H = int(screen["width"] * dpr), int(screen["height"] * dpr)
        t = copy.deepcopy(tree)
        st = copy.deepcopy(strip)
        state(t)
        strip_state(st, STRIP_STATES.get(name, 0.62))
        apply_layout(t, L, margin, st)
        hud = renderer.render(t, (W, H), L["scale"] * dpr)
        bar = renderer.render(st, (W, H), L["scale"] * dpr)
        img = tile.resize((W, H), Image.LANCZOS).convert("RGBA")
        draw_chrome(img, ImageDraw, screen, phone=(case == "phone"))
        img.alpha_composite(hud)
        img.alpha_composite(bar)
        path = os.path.join(out_dir, name + ".png")
        img.convert("RGB").save(path)
        shots.append((name, img))
        print(f"wrote {path} ({W}x{H}, scale {L['scale']:.3f}{', compact' if L['compact'] else ''})")
    # a contact sheet of all four
    sheet = Image.new("RGB", (1920, 1080 + 540), (12, 16, 14))
    sheet.paste(shots[0][1].convert("RGB").resize((960, 540)), (0, 0))
    sheet.paste(shots[1][1].convert("RGB").resize((960, 540)), (960, 0))
    sheet.paste(shots[2][1].convert("RGB").resize((960, 540)), (0, 540))
    ph = shots[3][1].convert("RGB")
    ph = ph.resize((960, int(960 * ph.size[1] / ph.size[0])))
    sheet.paste(ph, (960, 540))
    sheet = sheet.crop((0, 0, 1920, 1080))
    sheet.save(os.path.join(out_dir, "Hud_sheet.png"))


if __name__ == "__main__":
    sys.exit(main())

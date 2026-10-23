#!/usr/bin/env python3
"""T3 screens: builds the pause menu and the end screens from one tree each.

    python design/ui_specs/Screens_build.py [--fonts DIR] [--no-png]

Run from the project root. The look, the node helpers and the preview renderer
are T2's (Hud_build.py), so these screens match the HUD. Writes:
    src/ui/Pause.model.json         the pause menu: build, actions, stats,
                                    settings and map (PauseMenuController)
    src/ui/EndScreens.model.json    the death screen and the results (MenuController)
    assets/ui/manifest.Pause.json, assets/ui/manifest.EndScreens.json
    assets/ui/mockups/Pause_*.png, EndScreens_*.png, Screens_sheet.png

The previews take their screens from the game's own Core/PanelLayout and
their words and numbers (inspector cards, stats sheet, Silver) from Core/Inspect
and Core/Progress, through `lune run design/ui_specs/screens_cases.luau`.
The controllers re-lay these screens at runtime; `pause_layout` and
`end_layout` below mirror exactly that for the previews. Keep them in step
with PauseMenuController._layout and MenuController._layoutEnd.

This replaces Menu_build.py for EndScreens (Menu_build.py is behind the shipped
Menu and Overlay models and must not be run; assets/ui/NOTES.Menu.md).
"""

import argparse
import copy
import json
import os
import subprocess
import sys

sys.dont_write_bytecode = True  # no __pycache__ next to the specs
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import Hud_build as kit  # noqa: E402  (T2: tokens, nodes, renderer)
from Hud_build import (  # noqa: E402
    BODY,
    C3,
    DANGER,
    DONE,
    GOLD,
    INK,
    OUTLINE,
    RARITY,
    RIM,
    SILVER,
    SOFT,
    TAN,
    TEAL,
    TRACK,
    U2,
    V2,
    corner,
    find,
    find_all,
    frame,
    gui,
    icon,
    label,
    listing,
    node,
    padding,
    panel,
    shade,
    stroke,
)

ROOT = os.getcwd()

# ---------------------------------------------------------------- tokens (T2's, plus three)

WARN = "#FFB347"  # the world is still running
CALM = "#7FD6C2"  # the world is paused
DOWN = "#FF9C8A"  # a stat below its default
SCRIM = "#050A07"
TILE = "#0F1913"

# fill, rim, rim transparency, label ink
BUTTON = {
    "gold": ("#B98A2C", "#FFE3A3", 0.2, INK),
    "moss": ("#1C2C22", RIM, 0.45, INK),
    "quiet": ("#111A15", RIM, 0.72, SOFT),
    "danger": ("#5E231D", DANGER, 0.35, INK),
}

# ---------------------------------------------------------------- design sizes (PauseMenuController reads the same)

MARGIN = 24
BUILD_W, CENTRE_W, STATS_W = 560, 520, 470
COL_H_MAX, SPAN_MAX = 980, 1860
WEAPON_TILE, TILE_GAP = 92, 12
ITEM_TILE, ITEM_GAP = 64, 8
DETAILS_H = 310
GRID_Y = 354
RAIL_W, TABS_H = 300, 52
TAB_TILE, TAB_ITEM, TAB_LEFT = 84, 60, 400
MAP_W = 720

# ---------------------------------------------------------------- helpers


def text(name, value, size, pos=(0, 0, 0, 0), anchor=(0, 0), z=4, px=19, colour=SOFT, align="Left", valign="Top", wrapped=True, **kw):
    """Body text in Fredoka, no outline, wrapped unless told otherwise."""
    n = label(name, value, size, pos, anchor, z=z, font=BODY, px=px, colour=colour, align=align, valign=valign, outline=0, **kw)
    if wrapped:
        n["properties"]["TextWrapped"] = True
    return n


def focus_ring(z, radius=14, grow=12):
    """Gold ring shown on hover and gamepad selection (UiKit.button), or by code."""
    return frame("Focus", (1, grow, 1, grow), (0.5, 0, 0.5, 0), (0.5, 0.5), z=z, visible=False, children=[corner(radius), stroke(GOLD, 3, 0)])


def key_cap(z, key="Enter"):
    """The key that presses a button, at its right end (hidden on touch)."""
    return label(
        "KeyCap",
        key,
        (0, 0, 0, 26),
        (1, -12, 0.5, 0),
        (1, 0.5),
        z=z,
        font=BODY,
        px=15,
        colour=INK,
        outline=0,
        fill="#0B120E",
        fill_alpha=0.25,
        auto="X",
        children=[corner(7), stroke(SOFT, 1.5, 0.45), padding(8, 0)],
    )


# room kept clear for a key cap at each end of a button's caption, so the
# caption stays centred and keeps a clear gap from the cap ("Enter" is the
# widest: 12 from the edge, about 52 wide, then 28 of air)
KEY_ROOM = 92


def button(name, caption, size, pos=(0, 0, 0, 0), anchor=(0, 0), z=4, style="moss", px=28, order=None, visible=True, children=()):
    fill, rim, rim_alpha, ink = BUTTON[style]
    props = {
        "BackgroundColor3": C3(fill),
        "BackgroundTransparency": 0.04,
        "BorderSizePixel": 0,
        "Text": "",
        "AutoButtonColor": False,
        "Selectable": True,
    }
    kids = [corner(12), shade(0.74), stroke(rim, 2, rim_alpha)]
    if caption is not None:
        capped = any(c.get("name") == "KeyCap" for c in children)
        width = -2 * KEY_ROOM if capped else -24
        kids.append(label("Label", caption, (1, width, 1, -8), (0.5, 0, 0.5, 0), (0.5, 0.5), z=z + 1, px=px, colour=ink, scaled=px))
    kids += list(children)
    kids.append(focus_ring(z + 3))
    return node("TextButton", name, gui(props, name, size, pos, anchor, z, visible=visible, order=order), kids)


def scroller(name, size, pos=(0, 0, 0, 0), anchor=(0, 0), z=3, selectable=False, children=()):
    props = {
        "BackgroundTransparency": 1,
        "BorderSizePixel": 0,
        "ClipsDescendants": True,
        "CanvasSize": U2(0, 0, 0, 0),
        "AutomaticCanvasSize": "Y",
        "ScrollingDirection": "Y",
        "ScrollBarThickness": 6,
        "ScrollBarImageColor3": C3(RIM),
        "ScrollBarImageTransparency": 0.35,
        "VerticalScrollBarInset": "ScrollBar",
        "Selectable": selectable,
    }
    return node("ScrollingFrame", name, gui(props, name, size, pos, anchor, z), list(children))


def grid(cell, gap, name="Grid"):
    return node(
        "UIGridLayout",
        name,
        {
            "CellSize": U2(0, cell[0], 0, cell[1]),
            "CellPadding": U2(0, gap[0], 0, gap[1]),
            "SortOrder": "LayoutOrder",
            "FillDirection": "Horizontal",
            "HorizontalAlignment": "Left",
            "VerticalAlignment": "Top",
            "StartCorner": "TopLeft",
        },
    )


def viewport(name, size, pos, anchor, z):
    props = {"BackgroundTransparency": 1, "BorderSizePixel": 0, "Ambient": C3("#46505F"), "LightColor": C3("#EBF0FF")}
    return node("ViewportFrame", name, gui(props, name, size, pos, anchor, z))


def chip(name, value, colour, z, order=None, fill="#0B120E", visible=True, px=15):
    return label(
        name,
        value,
        (0, 0, 0, 26),
        z=z,
        px=px,
        colour=colour,
        outline=1.5,
        fill=fill,
        fill_alpha=0.1,
        auto="X",
        order=order,
        visible=visible,
        children=[corner("pill"), stroke(colour, 1.5, 0.55), padding(10, 0)],
    )


def rim_of(kind, rarity=None):
    if kind == "tome":
        return TEAL
    if kind == "item":
        return RARITY.get(rarity or "Common", RARITY["Common"])
    return RIM


def icon_key(kind, ident):
    return {"weapon": "Icon", "tome": "IconTome", "item": "IconItem"}[kind] + ident


def tile(name, key, tag, rim, side, order, empty=False):
    """A loadout or item tile: a button the inspector reads."""
    props = {
        "BackgroundColor3": C3(TILE),
        "BackgroundTransparency": 0.55 if empty else 0.06,
        "BorderSizePixel": 0,
        "Text": "",
        "AutoButtonColor": False,
        "Selectable": not empty,
    }
    kids = [
        corner(12),
        shade(0.7),
        stroke(rim, 2, 0.8 if empty else 0.15),
        icon("Icon", key or "IconSword", int(side * 0.66), (0.5, 0, 0.5, -5), (0.5, 0.5), z=5, visible=not empty),
        label(
            "Tag",
            tag or "",
            (0, 0, 0, 22),
            (1, -4, 1, -4),
            (1, 1),
            z=6,
            px=15,
            colour=GOLD,
            outline=1.5,
            fill="#0B120E",
            fill_alpha=0.12,
            auto="X",
            visible=bool(tag) and not empty,
            children=[corner("pill"), padding(7, 0)],
        ),
        focus_ring(7, radius=15, grow=10),
    ]
    return node("TextButton", name, gui(props, name, (0, side, 0, side), z=4, order=order), kids)


# ---------------------------------------------------------------- the pause menu


def level_tag(level, cap):
    return "MAX" if level >= cap else f"LVL {level}"


def build_column(run):
    cap = run["maxLevel"]
    weapons = [tile("Slot", icon_key("weapon", w["id"]), level_tag(w["level"], cap), RIM, WEAPON_TILE, i + 1) for i, w in enumerate(run["weapons"])]
    tomes = [tile("Slot", icon_key("tome", t["id"]), level_tag(t["level"], cap), TEAL, WEAPON_TILE, i + 1) for i, t in enumerate(run["tomes"])]
    rarity = {c["id"]: c.get("rarity") for c in run["cards"] if c["kind"] == "item"}
    items = [
        tile("ItemTile", icon_key("item", it["id"]), f"x{it['count']}", rim_of("item", rarity.get(it["id"])), ITEM_TILE, i + 1)
        for i, it in enumerate(run["items"])
    ]
    caption = dict(font=BODY, px=17, colour=TAN, align="Left", outline=0)
    return panel(
        "Build",
        (0, BUILD_W, 0, 964),
        (0, 0, 0, 0),
        z=3,
        alpha=0.16,
        children=[
            label("Title", "BUILD", (0, 300, 0, 36), (0, 22, 0, 14), z=4, px=30, align="Left"),
            label("Counts", "4 weapons  ·  4 tomes  ·  14 items", (0, 300, 0, 24), (1, -22, 0, 22), (1, 0), z=4, **{**caption, "align": "Right", "colour": SOFT, "px": 16}),
            frame("Rule", (1, -40, 0, 2), (0, 20, 0, 60), z=4, fill=RIM, alpha=0.6),
            label("WeaponsCaption", "WEAPONS", (0, 300, 0, 22), (0, 22, 0, 68), z=4, **caption),
            frame("WeaponRow", (0, 520, 0, WEAPON_TILE), (0, 20, 0, 98), z=3, children=[listing("Horizontal", TILE_GAP)] + weapons),
            label("TomesCaption", "TOMES", (0, 300, 0, 22), (0, 22, 0, 196), z=4, **caption),
            frame("TomeRow", (0, 520, 0, WEAPON_TILE), (0, 20, 0, 226), z=3, children=[listing("Horizontal", TILE_GAP)] + tomes),
            label("ItemsCaption", "ITEMS", (0, 300, 0, 22), (0, 22, 0, 324), z=4, **caption),
            scroller(
                "ItemGrid",
                (0, 528, 0, 280),
                (0, 20, 0, GRID_Y),
                z=3,
                children=[grid((ITEM_TILE, ITEM_TILE), (ITEM_GAP, ITEM_GAP)), padding(2, 2, 0, 2)] + items,
            ),
            text("NoItems", "No items yet: chests, shops and statues give them.", (0, 500, 0, 26), (0, 22, 0, GRID_Y + 4), px=18, visible=False),
            details_card(run["cards"][0]),
        ],
    )


def detail_line(name, value, order):
    return frame(
        "Line",
        (0, 232, 0, 22),
        z=4,
        order=order,
        children=[
            text("Label", name, (1, -70, 1, 0), px=16, colour=SOFT, valign="Center", wrapped=False),
            label("Value", value, (0, 68, 1, 0), (1, 0, 0, 0), (1, 0), z=5, px=18, align="Right", outline=1.5),
        ],
    )


def details_layout(card, w, h):
    """The details card's inside for a card w x h (PauseMenuController._layoutDetails)."""
    inner = w - 32
    setp(find(card, "Name"), "Size", w - 122, 36)
    setp(find(card, "Tags"), "Size", w - 122, 26)
    text_h = 48 if h < 340 else 72
    setp(find(card, "Text"), "Size", inner, text_h)
    lines_y = 100 + text_h + 6
    lines = find(card, "Lines")
    setp(lines, "Position", 16, lines_y)
    setp(lines, "Size", inner, h - lines_y - 52)
    cols = 2 if inner >= 440 else 1
    lines["children"][0]["properties"]["CellSize"] = U2(0, (inner - 24 * (cols - 1)) / cols, 0, 22)
    setp(find(card, "Note"), "Size", inner, 40)
    setp(find(card, "Empty"), "Size", inner, 60)


def details_card(card):
    kind = card["kind"]
    lines = [detail_line(line["label"], line["value"], i + 1) for i, line in enumerate(card["lines"])]
    kind_text = (card.get("rarity") or "ITEM").upper() if kind == "item" else kind.upper()
    return panel(
        "Details",
        (0, 520, 0, DETAILS_H),
        (0, 20, 1, -20),
        (0, 1),
        z=3,
        alpha=0.06,
        radius=12,
        rim_alpha=0.45,
        children=[
            frame(
                "IconTile",
                (0, 76, 0, 76),
                (0, 16, 0, 16),
                z=4,
                fill=TILE,
                alpha=0.05,
                children=[corner(12), shade(0.7), stroke(rim_of(kind, card.get("rarity")), 2, 0.1), icon("Icon", icon_key(kind, card["id"]), 58, (0.5, 0, 0.5, 0), (0.5, 0.5), z=5)],
            ),
            label("Name", card["name"].upper(), (0, 396, 0, 36), (0, 106, 0, 14), z=4, px=30, align="Left", scaled=30),
            frame(
                "Tags",
                (0, 396, 0, 26),
                (0, 106, 0, 56),
                z=4,
                children=[
                    listing("Horizontal", 8, v="Center"),
                    chip("KindTag", kind_text, rim_of(kind, card.get("rarity")), 5, order=1),
                    chip("LevelTag", card["tag"], GOLD, 5, order=2),
                ],
            ),
            text("Text", card["text"], (0, 488, 0, 48), (0, 16, 0, 100), px=19, colour=INK),
            frame("Lines", (0, 488, 0, 94), (0, 16, 0, 154), z=4, children=[grid((232, 22), (24, 2))] + lines),
            text("Note", card.get("note") or "", (0, 488, 0, 40), (0, 16, 1, -12), (0, 1), px=16, colour=TAN, valign="Bottom"),
            text("Empty", "Point at, tap or select a weapon, tome or item to read about it.", (0, 488, 0, 60), (0, 16, 0, 110), px=19, visible=False),
        ],
    )


def status_pill():
    return frame(
        "Status",
        (0, 0, 0, 40),
        (0.5, 0, 0, 92),
        (0.5, 0),
        z=4,
        fill="#14302B",
        alpha=0.08,
        auto="X",
        children=[
            corner("pill"),
            stroke(CALM, 1.5, 0.3),
            padding(16, 0),
            listing("Horizontal", 10, h="Center", v="Center"),
            frame("Dot", (0, 12, 0, 12), z=5, fill=CALM, order=1, children=[corner("pill")]),
            label("Text", "WORLD PAUSED", (0, 0, 0, 40), z=5, px=20, colour=CALM, outline=1.5, auto="X", order=2),
        ],
    )


def fact(name, value, order, key=None):
    kids = [listing("Horizontal", 6, v="Center")]
    if key:
        kids.append(icon("Icon", key, 24, z=5, order=1))
    kids.append(label("Value", value, (0, 0, 0, 30), z=5, px=20, outline=1.5, auto="X", order=2))
    return frame(name, (0, 0, 0, 30), z=4, order=order, auto="X", children=kids)


def run_card():
    return panel(
        "RunCard",
        (0, 440, 0, 128),
        (0.5, 0, 0, 196),
        (0.5, 0),
        z=3,
        alpha=0.18,
        children=[
            label("MapName", "MOSSY WOODS", (0, 400, 0, 34), (0.5, 0, 0, 12), (0.5, 0), z=4, px=28, scaled=28),
            text("Phase", "Stage  ·  1:48 to the final horde", (0, 400, 0, 24), (0.5, 0, 0, 48), (0.5, 0), px=19, colour=TAN, align="Center", valign="Center", wrapped=False),
            frame(
                "Facts",
                (0, 400, 0, 32),
                (0.5, 0, 1, -14),
                (0.5, 1),
                z=4,
                children=[listing("Horizontal", 22, h="Center", v="Center"), fact("Level", "LVL 14", 1), fact("Kills", "1,204", 2, "IconSkull"), fact("Gold", "312", 3, "IconGold")],
            ),
        ],
    )


def actions():
    return frame(
        "Actions",
        (0, 400, 0, 0),
        (0.5, 0, 0, 352),
        (0.5, 0),
        z=3,
        auto="Y",
        children=[
            listing("Vertical", 14, h="Center"),
            button("PrimaryButton", "RESUME", (0, 400, 0, 84), z=4, style="gold", px=36, order=1, children=[key_cap(6, "P")]),
            text("VoteInfo", "Zib wants to pause  ·  1/2 agreed  ·  12s", (0, 400, 0, 22), px=17, colour=WARN, align="Center", valign="Center", wrapped=False, order=2, visible=False),
            button("MapButton", "MAP", (0, 400, 0, 68), z=4, px=28, order=3, children=[key_cap(6, "Tab")]),
            button("SettingsButton", "SETTINGS", (0, 400, 0, 68), z=4, px=28, order=4),
            button("CancelButton", "CANCEL REQUEST", (0, 400, 0, 60), z=4, style="danger", px=24, order=5, visible=False),
            button("CloseButton", "CLOSE", (0, 400, 0, 60), z=4, style="quiet", px=24, order=6, visible=False),
        ],
    )


def setting_row(key, caption, value, fraction, order):
    """A slider row: its name and value over the track (OverlayController's settings)."""
    return frame(
        f"{key}Row",
        (0, 400, 0, 72),
        z=4,
        order=order,
        children=[
            text(f"{key}Label", caption, (0, 290, 0, 26), (0, 2, 0, 0), px=20, colour=TAN, valign="Center", wrapped=False),
            label(f"{key}Value", value, (0, 100, 0, 26), (1, -2, 0, 0), (1, 0), z=5, px=20, align="Right", outline=1.5),
            frame(
                f"{key}Slider",
                (1, -36, 0, 24),
                (0.5, 0, 0, 38),
                (0.5, 0),
                z=5,
                fill=TRACK,
                alpha=0.1,
                children=[
                    corner("pill"),
                    stroke(RIM, 1.5, 0.6),
                    frame("Fill", (fraction, 0, 1, 0), z=6, fill=GOLD, children=[corner("pill"), shade(0.75)]),
                    frame("Knob", (0, 34, 0, 34), (fraction, 0, 0.5, 0), (0.5, 0.5), z=7, fill=INK, children=[corner("pill"), stroke(OUTLINE, 2, 0.2), shade(0.8)]),
                    focus_ring(8, radius=16, grow=18),
                ],
            ),
        ],
    )


def toggle(name, caption, on, order):
    return button(
        name,
        None,
        (0, 400, 0, 56),
        z=4,
        style="moss",
        order=order,
        children=[
            frame("Box", (0, 34, 0, 34), (0, 14, 0.5, 0), (0, 0.5), z=5, fill=TRACK, alpha=0.05, children=[corner(8), stroke(RIM, 2, 0.3)]),
            icon("Check", "IconCheck", 30, (0, 16, 0.5, 0), (0, 0.5), z=6, visible=on),
            text("Label", caption, (0, 320, 1, 0), (0, 62, 0, 0), z=5, px=22, colour=INK, valign="Center", wrapped=False),
        ],
    )


def settings_view():
    rows = [
        setting_row(key, caption, value, fraction, i + 1)
        for i, (key, caption, value, fraction) in enumerate(
            [("Master", "Master volume", "70%", 0.7), ("Music", "Music", "45%", 0.45), ("Sfx", "Sound effects", "55%", 0.55), ("Sensitivity", "Camera sensitivity", "1x", 0.44)]
        )
    ]
    rows += [
        toggle("DamageNumbersToggle", "Damage numbers", True, 5),
        toggle("EnemyOutlinesToggle", "Enemy outlines", False, 6),
        button("BackButton", "BACK", (0, 400, 0, 58), z=4, style="quiet", px=26, order=7),
    ]
    return panel(
        "SettingsView",
        (0, 460, 0, 640),
        (0.5, 0, 0, 180),
        (0.5, 0),
        z=3,
        alpha=0.12,
        visible=False,
        children=[
            label("Title", "SETTINGS", (0, 420, 0, 36), (0.5, 0, 0, 14), (0.5, 0), z=4, px=30),
            scroller("List", (0, 436, 0, 568), (0.5, 0, 0, 62), (0.5, 0), z=4, children=[listing("Vertical", 12, h="Center"), padding(4, 8, 4, 10)] + rows),
        ],
    )


def centre_column():
    return frame(
        "Centre",
        (0, CENTRE_W, 0, 964),
        z=3,
        children=[
            label("Heading", "PAUSED", (0, 520, 0, 86), (0.5, 0, 0, 0), (0.5, 0), z=4, px=76, outline=3, scaled=76),
            status_pill(),
            text("Sub", "The world is paused.", (0, 500, 0, 44), (0.5, 0, 0, 138), (0.5, 0), px=19, colour=SOFT, align="Center", valign="Top"),
            run_card(),
            actions(),
            settings_view(),
            text("Hints", "P to resume  ·  Tab for the map", (0, 500, 0, 24), (0.5, 0, 1, -4), (0.5, 1), px=16, colour=SOFT, align="Center", valign="Center", wrapped=False),
        ],
    )


def stat_row(row, order):
    colour = {"up": DONE, "down": DOWN, "harder": WARN}.get(row.get("tone"), INK)
    return frame(
        "StatRow",
        (0, 424, 0, 22),
        z=4,
        order=order,
        children=[
            text("Name", row["name"], (1, -130, 1, 0), (0, 6, 0, 0), px=18, colour=SOFT, valign="Center", wrapped=False),
            label("Value", row["value"], (0, 120, 1, 0), (1, -6, 0, 0), (1, 0), z=5, px=19, colour=colour, align="Right", outline=1.5),
        ],
    )


def stat_section(section, order):
    kids = [listing("Vertical", 1), label("Title", section["title"].upper(), (0, 424, 0, 24), z=4, font=BODY, px=15, colour=TAN, align="Left", outline=0, order=0)]
    kids += [stat_row(row, i + 1) for i, row in enumerate(section["rows"])]
    return frame("StatSection", (0, 424, 0, 0), z=4, order=order, auto="Y", children=kids)


def stats_column(run):
    return panel(
        "Stats",
        (0, STATS_W, 0, 964),
        z=3,
        alpha=0.16,
        children=[
            label("Title", "STATS", (0, 200, 0, 36), (0, 22, 0, 14), z=4, px=30, align="Left"),
            frame(
                "Hero",
                (0, 0, 0, 40),
                (1, -18, 0, 12),
                (1, 0),
                z=4,
                auto="X",
                children=[
                    listing("Horizontal", 10, h="Right", v="Center"),
                    label("HeroName", run["heroName"].upper(), (0, 0, 0, 40), z=5, px=22, auto="X", order=1),
                    icon("Portrait", "Portrait" + run["hero"], 40, z=5, order=2, children=[corner(10), stroke(RIM, 1.5, 0.3)]),
                ],
            ),
            frame("Rule", (1, -40, 0, 2), (0, 20, 0, 62), z=4, fill=RIM, alpha=0.6),
            scroller(
                "StatList",
                (0, STATS_W - 24, 0, 880),
                (0, 12, 0, 72),
                z=4,
                selectable=True,
                children=[listing("Vertical", 8), padding(8, 2, 14, 6)] + [stat_section(s, i + 1) for i, s in enumerate(run["sections"])],
            ),
        ],
    )


def tabs_bar():
    def tab(name, caption, order):
        return button(name, caption, (0, 180, 0, TABS_H), z=5, style="quiet", px=24, order=order)

    return frame(
        "Tabs",
        (0, 600, 0, TABS_H),
        z=4,
        visible=False,
        children=[listing("Horizontal", 10, v="Center"), tab("BuildTab", "BUILD", 1), tab("StatsTab", "STATS", 2), tab("SettingsTab", "SETTINGS", 3)],
    )


LEGEND = [("IconMapChest", "Chest"), ("IconMapShrine", "Shrine"), ("IconMapBoss", "Boss"), ("IconMapVendor", "Vendor"), ("IconMapTeammate", "Squad")]


def map_view():
    letters = []
    for letter, pos in [("N", (0.5, 0, 0, 0)), ("E", (1, 0, 0.5, 0)), ("S", (0.5, 0, 1, 0)), ("W", (0, 0, 0.5, 0))]:
        letters.append(label(letter, letter, (0, 40, 0, 40), pos, (0.5, 0.5), z=10, px=26, colour=GOLD if letter == "N" else SOFT))
    legend = [listing("Horizontal", 18, h="Center", v="Center")]
    for i, (key, word) in enumerate(LEGEND):
        legend.append(
            frame(
                "LegendItem",
                (0, 0, 0, 30),
                z=7,
                order=i + 1,
                auto="X",
                children=[listing("Horizontal", 6, v="Center"), icon("Icon", key, 24, z=8, order=1), text("Text", word, (0, 0, 0, 30), z=8, px=18, valign="Center", wrapped=False, auto="X", order=2)],
            )
        )
    return panel(
        "MapView",
        (0, MAP_W, 0, 900),
        z=6,
        alpha=0.06,
        visible=False,
        children=[
            label("Title", "MAP", (0, 300, 0, 36), (0, 22, 0, 14), z=7, px=30, align="Left"),
            frame(
                "Map",
                (0, 680, 0, 680),
                (0.5, 0, 0, 62),
                (0.5, 0),
                z=7,
                fill="#0E1A13",
                alpha=0.02,
                children=[
                    corner(14),
                    stroke(RIM, 1.5, 0.5),
                    shade(0.85),
                    frame("Dots", (1, -12, 1, -12), (0.5, 0, 0.5, 0), (0.5, 0.5), z=8, clip=True),
                    icon("PlayerArrow", "IconArrowPlayer", 36, (0.5, 0, 0.5, 0), (0.5, 0.5), z=9),
                ]
                + letters,
            ),
            frame("Legend", (0, 680, 0, 32), (0.5, 0, 0, 756), (0.5, 0), z=7, children=legend),
            button("BackButton", "BACK", (0, 320, 0, 60), (0.5, 0, 1, -18), (0.5, 1), z=7, style="quiet", px=26, children=[key_cap(9, "Tab")]),
        ],
    )


def running_edge():
    bar = dict(z=2, fill=WARN, alpha=0.35)
    return frame(
        "Edge",
        (1, 0, 1, 0),
        z=2,
        visible=False,
        children=[
            frame("Top", (1, 0, 0, 6), **bar),
            frame("Bottom", (1, 0, 0, 6), (0, 0, 1, 0), (0, 1), **bar),
            frame("Left", (0, 6, 1, 0), **bar),
            frame("Right", (0, 6, 1, 0), (1, 0, 0, 0), (1, 0), **bar),
        ],
    )


def pause_tree(run):
    root = frame(
        "Root",
        (0, 1920, 0, 1080),
        z=1,
        visible=False,
        children=[
            frame("Scrim", (1, 0, 1, 0), z=1, fill=SCRIM, alpha=0.38),
            running_edge(),
            frame(
                "Safe",
                (0, 1920, 0, 1022),
                (0, 0, 0, 58),
                z=3,
                children=[build_column(run), centre_column(), stats_column(run), tabs_bar(), map_view()],
            ),
        ],
    )
    props = {"DisplayOrder": 45, "ResetOnSpawn": False, "ZIndexBehavior": "Sibling", "IgnoreGuiInset": True, "ScreenInsets": "None", "Enabled": True}
    return node("ScreenGui", "Pause", props, [root])


# ---------------------------------------------------------------- the end screens


def death_screen():
    stage = frame(
        "Stage",
        (0, 900, 0, 660),
        (0.5, 0, 0.5, 0),
        (0.5, 0.5),
        z=2,
        children=[
            label("DeathTitle", "you got bonked", (0, 900, 0, 96), (0.5, 0, 0, 0), (0.5, 0), z=3, font=BODY, px=88, outline=3, scaled=88),
            text("DeathJoke", "the horde says gg", (0, 900, 0, 40), (0.5, 0, 0, 98), (0.5, 0), px=30, colour=SOFT, align="Center", valign="Center", wrapped=False),
            frame("Halo", (0, 380, 0, 380), (0.5, 0, 0, 166), (0.5, 0), z=2, fill="#1C3326", alpha=0.55, children=[corner("pill"), stroke(RIM, 1.5, 0.75)]),
            viewport("HeroViewport", (0, 360, 0, 400), (0.5, 0, 0, 150), (0.5, 0), 3),
            button("SkipButton", "SKIP", (0, 300, 0, 72), (0.5, 0, 0, 566), (0.5, 0), z=4, style="moss", px=32, children=[key_cap(6, "Enter")]),
            frame("AutoBar", (0, 300, 0, 6), (0.5, 0, 0, 648), (0.5, 0), z=4, fill=TRACK, alpha=0.2, children=[corner("pill"), frame("Fill", (0.6, 0, 1, 0), z=5, fill=RIM, children=[corner("pill")])]),
        ],
    )
    return frame(
        "DeathScreen",
        (0, 1920, 0, 1080),
        z=1,
        visible=False,
        children=[frame("Backdrop", (1, 0, 1, 0), z=1, fill="#040806", alpha=0.04), frame("Safe", (0, 1920, 0, 1022), (0, 0, 0, 58), z=2, children=[stage])],
    )


def stat_chip(name, caption, value, order, best=False):
    return frame(
        name,
        (0, 278, 0, 92),
        z=4,
        order=order,
        fill=TRACK,
        alpha=0.3,
        children=[
            corner(12),
            stroke(RIM, 1.5, 0.6),
            text("Label", caption, (1, 0, 0, 24), (0.5, 0, 0, 8), (0.5, 0), px=18, colour=TAN, align="Center", valign="Center", wrapped=False),
            label("Value", value, (1, -16, 0, 46), (0.5, 0, 0, 34), (0.5, 0), z=5, px=38, outline=2, scaled=38),
            label("Best", "NEW BEST", (0, 0, 0, 22), (1, -8, 0, -11), (1, 0), z=6, px=13, colour="#1A1406", outline=0, fill=GOLD, fill_alpha=0, auto="X", visible=best, children=[corner("pill"), padding(8, 0)]),
        ],
    )


def part_row(word, value, order):
    return frame(
        "Part",
        (0, 183, 0, 24),
        z=5,
        order=order,
        children=[
            text("Label", word, (0, 112, 1, 0), px=17, colour=SOFT, valign="Center", wrapped=False),
            label("Value", value, (0, 66, 1, 0), (1, 0, 0, 0), (1, 0), z=6, px=18, align="Right", outline=1.5),
        ],
    )


PART_WORDS = [("stage", "Survival"), ("kills", "Kills"), ("minibosses", "Minibosses"), ("boss", "Boss"), ("escape", "Escape"), ("overtime", "Overtime")]


def fmt_part(v):
    v = round(v, 1)
    return f"+{int(v)}" if abs(v - round(v)) < 1e-9 else f"+{v}"


def silver_card(res):
    parts = [part_row(word, fmt_part(res["parts"][key]), i + 1) for i, (key, word) in enumerate(PART_WORDS) if res["parts"][key] > 0 or key in ("stage", "kills")]
    return panel(
        "SilverCard",
        (0, 430, 0, 270),
        (0, 40, 0, 240),
        z=3,
        alpha=0.1,
        children=[
            text("Title", "SILVER EARNED", (0, 300, 0, 24), (0, 20, 0, 14), px=18, colour=TAN, valign="Center", wrapped=False),
            icon("Icon", "IconSilver", 46, (0, 20, 0, 48), z=5),
            label("Amount", f"+{res['silver']}", (0, 200, 0, 60), (0, 76, 0, 42), z=5, px=56, colour=SILVER, align="Left", outline=2.5),
            text("Total", "You have 412", (0, 180, 0, 24), (1, -20, 0, 60), (1, 0), px=18, colour=SOFT, align="Right", valign="Center", wrapped=False),
            frame("Breakdown", (0, 390, 0, 80), (0, 20, 0, 112), z=4, children=[grid((183, 24), (24, 2))] + parts),
            text("Gain", f"x{res['gain']} Silver Gain  ·  a run pays at most {res['cap']}", (0, 390, 0, 22), (0, 20, 1, -16), (0, 1), px=16, colour=TAN, valign="Center", wrapped=False),
        ],
    )


def player_row(name, hero, kills, damage, gold, silver, order, ready=False, mine=False):
    return frame(
        "PlayerRow",
        (0, 730, 0, 72),
        z=4,
        order=order,
        fill=TRACK,
        alpha=0.35,
        children=[
            corner(10),
            stroke(GOLD if mine else RIM, 1.5, 0.3 if mine else 0.8),
            icon("Portrait", "Portrait" + hero, 52, (0, 10, 0.5, 0), (0, 0.5), z=5, children=[corner(10)]),
            frame("ReadyTag", (0, 26, 0, 26), (0, 60, 0, 60), (0.5, 0.5), z=7, fill=DONE, visible=ready, children=[corner("pill"), stroke(OUTLINE, 2, 0.2), icon("Icon", "IconCheck", 20, (0.5, 0, 0.5, 0), (0.5, 0.5), z=8)]),
            text("Name", name, (0, 260, 0, 28), (0, 76, 0, 8), z=5, px=21, colour=INK, valign="Center", wrapped=False, truncate=True),
            text("Hero", {"Knight": "Sir Clonk", "Fox": "Zib", "Frostling": "Minty"}[hero], (0, 200, 0, 22), (0, 76, 0, 40), z=5, px=16, colour=SOFT, valign="Center", wrapped=False),
            label("Kills", kills, (0, 100, 1, 0), (0, 340, 0, 0), z=5, px=24, align="Right", outline=2),
            label("Damage", damage, (0, 130, 1, 0), (0, 450, 0, 0), z=5, px=24, align="Right", outline=2),
            label("Gold", gold, (0, 60, 1, 0), (0, 590, 0, 0), z=5, px=22, colour=GOLD, align="Right", outline=2),
            label("Silver", silver, (0, 66, 1, 0), (0, 656, 0, 0), z=5, px=22, colour=SILVER, align="Right", outline=2),
        ],
    )


def results_screen(res):
    heads = [
        ("HeadPlayer", "PLAYER", 76, 200, "Left"),
        ("HeadKills", "KILLS", 340, 100, "Right"),
        ("HeadDamage", "DAMAGE", 450, 130, "Right"),
        ("HeadGold", "GOLD", 590, 60, "Right"),
        ("HeadSilver", "SILVER", 656, 66, "Right"),
    ]
    head_nodes = [text(n, w, (0, wd, 1, 0), (0, x, 0, 0), px=15, colour=TAN, align=al, valign="Center", wrapped=False) for n, w, x, wd, al in heads]
    squad = frame(
        "Squad",
        (0, 730, 0, 270),
        (1, -40, 0, 240),
        (1, 0),
        z=3,
        children=[
            frame("ColumnHeads", (0, 730, 0, 26), z=4, children=head_nodes),
            frame(
                "PlayerRows",
                (0, 730, 0, 240),
                (0, 0, 0, 30),
                z=4,
                children=[
                    listing("Vertical", 8),
                    player_row("LeafZi", "Knight", "1,240", "184,330", "312", f"+{res['silver']}", 1, ready=False, mine=True),
                    player_row("mint_enjoyer", "Frostling", "900", "121,045", "268", f"+{res['mateSilver']}", 2, ready=True),
                ],
            ),
        ],
    )
    the_panel = panel(
        "Panel",
        (0, 1240, 0, 620),
        (0.5, 0, 0.5, 0),
        (0.5, 0.5),
        z=2,
        alpha=0.12,
        children=[
            label("ResultTitle", "VICTORY", (0, 900, 0, 78), (0.5, 0, 0, 14), (0.5, 0), z=4, px=70, colour=GOLD, outline=3, scaled=70),
            text("Subtitle", "Mossy Woods  ·  Sir Clonk  ·  9:48", (0, 1100, 0, 26), (0.5, 0, 0, 94), (0.5, 0), px=21, colour=SOFT, align="Center", valign="Center", wrapped=False),
            frame(
                "StatTable",
                (0, 1160, 0, 92),
                (0.5, 0, 0, 132),
                (0.5, 0),
                z=3,
                children=[
                    listing("Horizontal", 16, h="Center"),
                    stat_chip("Kills", "Kills", "2,140", 1, best=True),
                    stat_chip("Level", "Level", "LVL 16", 2),
                    stat_chip("Time", "Survived", "9:48", 3),
                    stat_chip("BossTime", "Boss down at", "8:56", 4),
                ],
            ),
            silver_card(res),
            squad,
            button("ContinueButton", "CONTINUE", (0, 420, 0, 74), (0.5, 0, 1, -18), (0.5, 1), z=4, style="gold", px=32, children=[key_cap(6, "Enter")]),
            text("ContinueLabel", "Back to Skyhold in 12", (0, 360, 0, 24), (1, -40, 1, -55), (1, 0.5), px=18, colour=SOFT, align="Right", valign="Center", wrapped=False),
        ],
    )
    return frame(
        "Results",
        (0, 1920, 0, 1080),
        z=1,
        visible=False,
        children=[frame("Backdrop", (1, 0, 1, 0), z=1, fill=SCRIM, alpha=0.3), frame("Safe", (0, 1920, 0, 1022), (0, 0, 0, 58), z=2, children=[the_panel])],
    )


def end_tree(res):
    props = {"DisplayOrder": 40, "ResetOnSpawn": False, "ZIndexBehavior": "Sibling", "IgnoreGuiInset": True, "ScreenInsets": "None", "Enabled": True}
    return node("ScreenGui", "EndScreens", props, [death_screen(), results_screen(res)])


# ---------------------------------------------------------------- runtime layouts, mirrored for the previews


def setp(n, prop, x, y):
    n["properties"][prop] = U2(0, x, 0, y)


def pause_layout(tree, L, screen, tab="build"):
    """What PauseMenuController._layout does at runtime."""
    s = L["scale"]
    root = find(tree, "Root")
    setp(root, "Size", screen["width"] / s, screen["height"] / s)
    safe = find(root, "Safe")
    sf = L["safe"]
    setp(safe, "Position", sf["x"], sf["y"])
    setp(safe, "Size", sf["w"], sf["h"])
    build, centre, stats = find(safe, "Build"), find(safe, "Centre"), find(safe, "Stats")
    m = MARGIN
    if L["mode"] == "wide":
        col_h = min(sf["h"] - 2 * m, COL_H_MAX)
        top = (sf["h"] - col_h) / 2
        span = min(sf["w"] - 2 * m, SPAN_MAX)
        left = (sf["w"] - span) / 2
        setp(build, "Position", left, top)
        setp(build, "Size", BUILD_W, col_h)
        setp(stats, "Position", left + span - STATS_W, top)
        setp(stats, "Size", STATS_W, col_h)
        setp(centre, "Position", left + span / 2 - CENTRE_W / 2, top)
        setp(centre, "Size", CENTRE_W, col_h)
        setp(find(build, "ItemGrid"), "Size", 528, col_h - GRID_Y - DETAILS_H - 32)
        details_layout(find(build, "Details"), 520, DETAILS_H)
        setp(find(stats, "StatList"), "Size", STATS_W - 24, col_h - 84)
        settings_layout(find(centre, "SettingsView"), 460, min(640, col_h - 220), True)
        return
    # tabs: a rail of actions on the left, the tabs and their page on the right
    area_w, area_h = sf["w"] - 2 * m, sf["h"] - 2 * m
    setp(centre, "Position", m, m)
    setp(centre, "Size", RAIL_W, area_h)
    heading = find(centre, "Heading")
    heading["properties"]["TextSize"] = 44
    find(heading, "Fit")["properties"]["MaxTextSize"] = 44
    setp(heading, "Size", RAIL_W, 52)
    pill = find(centre, "Status")
    pill["properties"]["Position"] = U2(0.5, 0, 0, 56)
    sub = find(centre, "Sub")
    sub["properties"]["Position"] = U2(0.5, 0, 0, 104)
    sub["properties"]["TextSize"] = 16
    setp(sub, "Size", RAIL_W, 44)
    acts = find(centre, "Actions")
    acts["properties"]["Position"] = U2(0.5, 0, 0, 156)
    setp(acts, "Size", RAIL_W, 0)
    for b in ("PrimaryButton", "MapButton", "CancelButton", "CloseButton"):
        btn = find(acts, b)
        h = 66 if b == "PrimaryButton" else 54
        setp(btn, "Size", RAIL_W, h)
    find(acts, "SettingsButton")["properties"]["Visible"] = False
    find(acts, "VoteInfo")["properties"]["TextSize"] = 15
    setp(find(acts, "VoteInfo"), "Size", RAIL_W, 20)
    card = find(centre, "RunCard")
    card["properties"]["Position"] = U2(0.5, 0, 1, 0)
    card["properties"]["AnchorPoint"] = V2(0.5, 1)
    setp(card, "Size", RAIL_W, 112)
    find(card, "MapName")["properties"]["TextSize"] = 24
    setp(find(card, "MapName"), "Size", RAIL_W - 24, 30)
    find(card, "Phase")["properties"]["TextSize"] = 16
    setp(find(card, "Phase"), "Size", RAIL_W - 24, 22)
    find(card, "Phase")["properties"]["Position"] = U2(0.5, 0, 0, 42)
    setp(find(card, "Facts"), "Size", RAIL_W - 24, 30)
    find(card, "Facts")["children"][0]["properties"]["Padding"] = {"UDim": [0, 12]}
    find(centre, "Hints")["properties"]["Visible"] = False

    rx, rw = m + RAIL_W + 24, area_w - RAIL_W - 24
    tabs = find(safe, "Tabs")
    tabs["properties"]["Visible"] = True
    setp(tabs, "Position", rx, m)
    setp(tabs, "Size", rw, TABS_H)
    for name, key in (("BuildTab", "build"), ("StatsTab", "stats"), ("SettingsTab", "settings")):
        t = find(tabs, name)
        if key == tab:
            find(t, "Stroke")["properties"]["Color"] = C3(GOLD)
            find(t, "Stroke")["properties"]["Transparency"] = 0
            find(t, "Label")["properties"]["TextColor3"] = C3(GOLD)
    cy, ch = m + TABS_H + 12, area_h - TABS_H - 12
    build["properties"]["Visible"] = tab == "build"
    stats["properties"]["Visible"] = tab == "stats"
    if tab == "build":
        setp(build, "Position", rx, cy)
        setp(build, "Size", rw, ch)
        for n in ("Title", "Counts", "Rule"):
            find(build, n)["properties"]["Visible"] = False
        rows_w = 4 * TAB_TILE + 3 * 10
        for cap_name, y in (("WeaponsCaption", 10), ("TomesCaption", 132), ("ItemsCaption", 252)):
            setp(find(build, cap_name), "Position", 22, y)
        for row_name, y in (("WeaponRow", 38), ("TomeRow", 158)):
            r = find(build, row_name)
            setp(r, "Position", 20, y)
            setp(r, "Size", rows_w, TAB_TILE)
            r["children"][0]["properties"]["Padding"] = {"UDim": [0, 10]}
            for c in r["children"][1:]:
                setp(c, "Size", TAB_TILE, TAB_TILE)
                setp(find(c, "Icon"), "Size", int(TAB_TILE * 0.66), int(TAB_TILE * 0.66))
        g = find(build, "ItemGrid")
        setp(g, "Position", 20, 276)
        setp(g, "Size", TAB_LEFT + 8, ch - 276 - 14)
        g["children"][0]["properties"]["CellSize"] = U2(0, TAB_ITEM, 0, TAB_ITEM)
        for c in find_all(g, "ItemTile"):
            setp(find(c, "Icon"), "Size", int(TAB_ITEM * 0.66), int(TAB_ITEM * 0.66))
        d = find(build, "Details")
        dx = 20 + TAB_LEFT + 28
        d["properties"]["Position"] = U2(0, dx, 0, 14)
        d["properties"]["AnchorPoint"] = V2(0, 0)
        setp(d, "Size", rw - dx - 16, ch - 28)
        details_layout(d, rw - dx - 16, ch - 28)
    find(acts, "SettingsButton")["properties"]["Visible"] = False
    view = find(centre, "SettingsView")
    view["properties"]["Visible"] = tab == "settings"
    set_w = min(rw, 520)
    view["properties"]["Position"] = U2(0, rx - m + (rw - set_w) / 2, 0, cy - m)
    view["properties"]["AnchorPoint"] = V2(0, 0)
    settings_layout(view, set_w, ch, False)
    find(view, "BackButton")["properties"]["Visible"] = False
    if tab == "stats":
        w = min(rw, 560)
        setp(stats, "Position", rx + (rw - w) / 2, cy)
        setp(stats, "Size", w, ch)
        setp(find(stats, "StatList"), "Size", w - 24, ch - 84)
        for sec in find_all(stats, "StatSection"):
            setp(sec, "Size", w - 46, 0)
            for n in sec["children"]:
                if n["name"] in ("Title", "StatRow"):
                    setp(n, "Size", w - 46, n["properties"]["Size"]["UDim2"][1][1])


def settings_layout(view, w, h, with_title):
    """PauseMenuController._layoutSettings: the panel, its title, its scrolling list."""
    setp(view, "Size", w, h)
    find(view, "Title")["properties"]["Visible"] = with_title
    top = 62 if with_title else 12
    lst = find(view, "List")
    lst["properties"]["Position"] = U2(0.5, 0, 0, top)
    setp(lst, "Size", w - 24, h - top - 10)


def end_layout(tree, L, screen, which):
    """What MenuController._layoutEnd does at runtime."""
    s = L["scale"]
    screen_frame = find(tree, which)
    setp(screen_frame, "Size", screen["width"] / s, screen["height"] / s)
    safe = find(screen_frame, "Safe")
    sf = L["safe"]
    setp(safe, "Position", sf["x"], sf["y"])
    setp(safe, "Size", sf["w"], sf["h"])


# ---------------------------------------------------------------- manifest, output


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


def write_model(tree, name):
    path = os.path.join(ROOT, f"src/ui/{name}.model.json")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(kit.strip_names(tree), f, indent=1, ensure_ascii=False)
        f.write("\n")
    with open(os.path.join(ROOT, f"assets/ui/manifest.{name}.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest(tree), f, indent=1)
        f.write("\n")
    print(f"wrote {path}")


# ---------------------------------------------------------------- the preview renderer: T2's, taught T3's classes


class Renderer(kit.Renderer):
    """Also draws TextButtons (like a label), ScrollingFrames (a frame that clips,
    with its bar), UIGridLayout, wrapped text and a ViewportFrame placeholder."""

    def layout(self, n, rect, s):
        g = self.kid(n, "UIGridLayout")
        if not g:
            return super().layout(n, rect, s)
        n["_rect"] = rect
        x, y, w, h = rect
        left, top, right, _ = self.pad(n, s)
        ix, iy, iw = x + left, y + top, w - left - right
        gp = g["properties"]
        (_, cxo), (_, cyo) = gp["CellSize"]["UDim2"]
        (_, pxo), (_, pyo) = gp["CellPadding"]["UDim2"]
        cw, ch, pw, ph = cxo * s, cyo * s, pxo * s, pyo * s
        per_row = max(1, int((iw + pw + 0.5) // (cw + pw)))
        kids = sorted([c for c in n["children"] if self.visible(c)], key=lambda c: c["properties"].get("LayoutOrder", 0))
        for i, c in enumerate(kids):
            row, col = divmod(i, per_row)
            self.layout(c, (ix + col * (cw + pw), iy + row * (ch + ph), cw, ch), s)

    def draw_text(self, img, n, s):
        p = n["properties"]
        if not p.get("TextWrapped") or not p.get("Text"):
            return super().draw_text(img, n, s)
        x, y, w, h = n["_rect"]
        left, top, right, bottom = self.pad(n, s)
        x, y, w, h = x + left, y + top, w - left - right, h - top - bottom
        size = p.get("TextSize", 14) * s
        f = self.font(p["FontFace"]["Font"]["family"], size)
        lines, line = [], ""
        for word in p["Text"].split(" "):
            trial = (line + " " + word).strip()
            if f.getlength(trial) <= w or not line:
                line = trial
            else:
                lines.append(line)
                line = word
        if line:
            lines.append(line)
        step = size * 1.18
        total = step * len(lines)
        va = p.get("TextYAlignment", "Center")
        cy = {"Top": y, "Center": y + (h - total) / 2, "Bottom": y + h - total}[va]
        ha = p.get("TextXAlignment", "Center")
        colour = self.rgb(p.get("TextColor3", C3(INK))) + (int(255 * (1 - p.get("TextTransparency", 0))),)
        layer = self.Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = self.ImageDraw.Draw(layer)
        for i, ln in enumerate(lines):
            lw = f.getlength(ln)
            lx = {"Left": x, "Center": x + (w - lw) / 2, "Right": x + w - lw}[ha]
            d.text((lx, cy + i * step), ln, font=f, fill=colour)
        img.alpha_composite(layer)

    def draw(self, img, n, s):
        cls = n["className"]
        if cls not in ("TextButton", "ScrollingFrame", "ViewportFrame"):
            return super().draw(img, n, s)
        if not self.visible(n) or "_rect" not in n:
            return
        self.draw_frame(img, n, s)
        if cls == "TextButton":
            self.draw_text(img, n, s)
        if cls == "ViewportFrame":
            self.draw_viewport(img, n)
        kids = sorted([c for c in n["children"] if self.visible(c)], key=lambda c: c["properties"].get("ZIndex", 1))
        if cls != "ScrollingFrame":
            for c in kids:
                self.draw(img, c, s)
            return
        from PIL import ImageChops

        layer = self.Image.new("RGBA", img.size, (0, 0, 0, 0))
        for c in kids:
            self.draw(layer, c, s)
        x, y, w, h = n["_rect"]
        mask = self.Image.new("L", img.size, 0)
        self.ImageDraw.Draw(mask).rectangle((x, y, x + w, y + h), fill=255)
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
        img.alpha_composite(layer)
        bottom = max([c["_rect"][1] + c["_rect"][3] for c in kids if "_rect" in c] or [y])
        content = bottom - y + 8 * s
        if content > h + 1:
            bar_h = max(30 * s, h * h / content)
            t = 6 * s
            d = self.ImageDraw.Draw(img)
            d.rounded_rectangle((x + w - t, y, x + w, y + bar_h), radius=int(t / 2), fill=self.rgb(C3(RIM)) + (165,))

    def icon(self, key, size):
        return super().icon("IconTomeCooldown" if key == "IconItemAutoTrigger" else key, size)

    def draw_viewport(self, img, n):
        x, y, w, h = n["_rect"]
        im = self.icon("PortraitKnight", min(w, h) * 0.8)
        if im is None:
            return
        im = im.rotate(-14, resample=self.Image.BICUBIC, expand=True)
        layer = self.Image.new("RGBA", img.size, (0, 0, 0, 0))
        layer.paste(im, (int(x + (w - im.size[0]) / 2), int(y + h - im.size[1] - 10)), im)
        img.alpha_composite(layer)


def draw_chrome(img, ImageDraw, screen, phone=False):
    """Roblox's top bar and, on a phone, the notch and home bar. The Overlay's
    touch buttons are hidden while these screens are up, so they are not drawn."""
    d = ImageDraw.Draw(img)
    k = img.size[0] / screen["width"]
    tb = screen["topbar"]
    pad = 6 * k
    btn = tb["y1"] * k - 2 * pad
    x0 = pad + screen["core"]["left"] * k
    d.rounded_rectangle((x0, pad, x0 + btn, pad + btn), radius=int(btn / 2), fill=(20, 20, 24, 200))
    end = tb["x0"] * k - pad
    d.rounded_rectangle((x0 + btn + pad, pad, end, pad + btn), radius=int(btn / 2), fill=(20, 20, 24, 200))
    for i in range(3):
        cx = x0 + btn + pad + btn * (0.7 + i * 1.1)
        if cx + btn * 0.3 < end:
            d.ellipse((cx - btn * 0.22, pad + btn * 0.28, cx + btn * 0.22, pad + btn * 0.72), fill=(235, 235, 235, 220))
    if phone:
        notch = 30 * k
        d.rounded_rectangle((-notch, img.size[1] * 0.3, notch * 0.9, img.size[1] * 0.7), radius=int(notch), fill=(0, 0, 0, 255))
        d.rounded_rectangle((img.size[0] * 0.38, img.size[1] - 9 * k, img.size[0] * 0.62, img.size[1] - 5 * k), radius=int(3 * k), fill=(255, 255, 255, 200))


# ---------------------------------------------------------------- preview states


def set_props(tree, name, **props):
    n = find(tree, name)
    for k, v in props.items():
        n["properties"][k] = v
    return n


def show(tree, name, on=True):
    find(tree, name)["properties"]["Visible"] = on


def set_card(tree, card):
    build = find(tree, "Build")
    old = find(build, "Details")
    new = details_card(card)
    new["properties"]["Position"] = old["properties"]["Position"]
    new["properties"]["AnchorPoint"] = old["properties"]["AnchorPoint"]
    new["properties"]["Size"] = old["properties"]["Size"]
    build["children"][build["children"].index(old)] = new
    return new


def ring_tile(tree, row_name, index):
    row = find(tree, row_name)
    tiles = [c for c in row["children"] if c["className"] == "TextButton"]
    find(tiles[index], "Focus")["properties"]["Visible"] = True


def pause_open(tree):
    show(tree, "Root")


def state_solo(tree, run):
    pause_open(tree)
    ring_tile(tree, "WeaponRow", 0)


def state_coop(tree, run):
    """Co-op, the world still running: a teammate has asked to pause."""
    pause_open(tree)
    show(tree, "Edge")
    find(tree, "Scrim")["properties"]["BackgroundTransparency"] = 0.62
    set_props(tree, "Heading", Text="GAME STILL RUNNING", TextColor3=C3(WARN), TextSize=52)
    find(find(tree, "Heading"), "Fit")["properties"]["MaxTextSize"] = 52
    pill = find(tree, "Status")
    pill["properties"]["BackgroundColor3"] = C3("#3A2A0E")
    find(pill, "Stroke")["properties"]["Color"] = C3(WARN)
    find(pill, "Dot")["properties"]["BackgroundColor3"] = C3(WARN)
    set_props(pill, "Text", Text="ZIB WANTS TO PAUSE  ·  12s", TextColor3=C3(WARN))
    set_props(tree, "Sub", Text="You can still be hit. Agree to pause the game.")
    acts = find(tree, "Actions")
    find(find(acts, "PrimaryButton"), "Label")["properties"]["Text"] = "ACCEPT PAUSE"
    find(find(acts, "PrimaryButton"), "KeyCap")["properties"]["Text"] = "Enter"
    show(acts, "VoteInfo")
    set_props(acts, "VoteInfo", Text="1 of 2 agreed")
    show(acts, "CloseButton")
    set_props(tree, "Hints", Text="P to close  ·  closing keeps the vote")
    # an item is under the cursor
    card = next(c for c in run["cards"] if c["id"] == "ZoomSocks")
    set_card(tree, card)
    grid_tiles = [c for c in find(tree, "ItemGrid")["children"] if c["className"] == "TextButton"]
    find(grid_tiles[0], "Focus")["properties"]["Visible"] = True


def state_settings(tree, run):
    pause_open(tree)
    for n in ("RunCard", "Actions"):
        show(tree, n, False)
    show(tree, "SettingsView")
    set_props(tree, "Hints", Text="Changes apply at once and are kept")
    tomes = find(tree, "TomeRow")
    find([c for c in tomes["children"] if c["className"] == "TextButton"][0], "Focus")["properties"]["Visible"] = True
    set_card(tree, next(c for c in run["cards"] if c["id"] == "Damage"))


def touch_keys(tree):
    """A touch screen shows no key caps (PauseMenuController._renderKeys)."""
    for cap in find_all(tree, "KeyCap"):
        cap["properties"]["Visible"] = False


def state_phone_build(tree, run):
    state_solo(tree, run)
    touch_keys(tree)


def state_phone_stats(tree, run):
    pause_open(tree)
    touch_keys(tree)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts", default=os.environ.get("BONK_FONTS", ""))
    ap.add_argument("--no-png", action="store_true")
    args = ap.parse_args()

    kit.load_icon_ids()
    cases = json.loads(subprocess.run(["lune", "run", "design/ui_specs/screens_cases.luau"], capture_output=True, text=True, check=True, stdin=subprocess.DEVNULL).stdout)
    run, res = cases["run"], cases["results"]
    pause = pause_tree(run)
    ends = end_tree(res)
    write_model(pause, "Pause")
    write_model(ends, "EndScreens")
    if args.no_png:
        return 0
    try:
        from PIL import Image, ImageDraw, ImageFilter, ImageFont
    except ImportError:
        print("Pillow missing: no previews")
        return 0
    kit.find_fonts(args.fonts)
    backdrop = Image.open(os.path.join(ROOT, "work/map/preview_sheet.jpg")).convert("RGB")
    world = backdrop.crop((480 + 2, 18, 960 - 2, 270)).resize((1920, 1080), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.2))
    renderer = Renderer(Image, ImageDraw, ImageFont, os.path.join(ROOT, "assets/ui/icons"))
    out_dir = os.path.join(ROOT, "assets/ui/mockups")
    shots = []

    def shoot(name, tree, case, dpr, layout, phone=False, dim=False):
        c = cases["screens"][case]
        screen = c["screen"]
        W, H = int(screen["width"] * dpr), int(screen["height"] * dpr)
        L = layout(tree, c, screen)
        img = world.resize((W, H), Image.LANCZOS).convert("RGBA")
        if dim:
            img = Image.blend(img, Image.new("RGBA", img.size, (8, 12, 10, 255)), 0.25)
        draw_chrome(img, ImageDraw, screen, phone=phone)
        img.alpha_composite(renderer.render(tree, (W, H), L["scale"] * dpr))
        path = os.path.join(out_dir, name + ".png")
        img.convert("RGB").save(path)
        shots.append((name, img))
        print(f"wrote {path} ({W}x{H}, scale {L['scale']:.3f}, {L['mode']})")

    def pause_case(state, tab="build"):
        def go(tree, c, screen):
            state(tree, run)
            pause_layout(tree, c["pause"], screen, tab)
            return c["pause"]

        return go

    def end_case(which, state):
        def go(tree, c, screen):
            state(tree)
            L = c["death" if which == "DeathScreen" else "results"]
            end_layout(tree, L, screen, which)
            return L

        return go

    def death(tree):
        show(tree, "DeathScreen")

    def results_coop(tree):
        show(tree, "Results")
        set_props(tree, "ContinueLabel", Text="1/2 ready  ·  back to Skyhold in 9")

    def results_solo_phone(tree):
        show(tree, "Results")
        panel_node = find(tree, "Panel")
        old_card = find(panel_node, "SilverCard")
        defeat = cases["defeat"]
        new_card = silver_card(defeat)
        set_props(new_card, "Gain", Text=f"a run pays at most {defeat['cap']}")
        panel_node["children"][panel_node["children"].index(old_card)] = new_card
        find(find(tree, "PlayerRows"), "Silver")["properties"]["Text"] = f"+{defeat['silver']}"
        set_props(tree, "ResultTitle", Text="BONKED", TextColor3=C3("#F2554D"))
        set_props(tree, "Subtitle", Text="Mossy Woods  ·  Sir Clonk  ·  6:12")
        rows = find(tree, "PlayerRows")
        rows["children"] = [c for c in rows["children"] if not (c["name"] == "PlayerRow" and c["properties"].get("LayoutOrder") == 2)]
        find(tree, "Kills")["children"][-1]["properties"]["Visible"] = False
        set_props(find(tree, "BossTime"), "Label", Text="Minibosses")
        set_props(find(tree, "BossTime"), "Value", Text="1")
        for cap in find_all(tree, "KeyCap"):
            cap["properties"]["Visible"] = False
        set_props(find(tree, "Time"), "Value", Text="6:12")
        set_props(find(tree, "Kills"), "Value", Text="1,240")
        set_props(tree, "ContinueLabel", Text="Back to Skyhold in 12")

    shoot("Pause_solo", copy.deepcopy(pause), "desktop", 1, pause_case(state_solo))
    shoot("Pause_coop", copy.deepcopy(pause), "desktop", 1, pause_case(state_coop))
    shoot("Pause_settings", copy.deepcopy(pause), "laptop", 1, pause_case(state_settings))
    shoot("Pause_phone", copy.deepcopy(pause), "phone", 2, pause_case(state_phone_build, "build"), phone=True)
    shoot("Pause_phone_stats", copy.deepcopy(pause), "phone", 2, pause_case(state_phone_stats, "stats"), phone=True)
    shoot("EndScreens_death", copy.deepcopy(ends), "desktop", 1, end_case("DeathScreen", death))
    shoot("EndScreens_results", copy.deepcopy(ends), "desktop", 1, end_case("Results", results_coop), dim=True)
    shoot("EndScreens_phone", copy.deepcopy(ends), "phone", 2, end_case("Results", results_solo_phone), phone=True, dim=True)

    sheet = Image.new("RGB", (1920, 1620), (12, 16, 14))
    tiles = [shots[0], shots[1], shots[2], shots[3], shots[6], shots[7]]
    for i, (_, im) in enumerate(tiles):
        im = im.convert("RGB")
        im = im.resize((960, int(960 * im.size[1] / im.size[0])))
        sheet.paste(im, ((i % 2) * 960, (i // 2) * 540))
    sheet.save(os.path.join(out_dir, "Screens_sheet.png"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

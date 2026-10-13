"""Post-process the Hud tree ui_build.py emitted so it meets design/ui_contract.md.

    python Hud_post.py <raw Hud.model.json from ui_build.py> <project root>

Reads  design/ui_specs/Hud.json   (the spec, for the keys ui_build ignores)
Writes src/ui/Hud.model.json      the shipped tree
       design/ui_specs/Hud.lua    the Luau builder, emitted from the SAME final tree
       assets/ui/manifest.Hud.json

What it does, and why ui_build.py cannot:
  1. Flattens CanvasFrame and drops its UIScale: the contract wants the named
     elements directly inside the ScreenGui, and the game adds its own UIScale.
  2. Per-label font ("font" key): ui_build has one font per theme.
  3. Every coloured Frame becomes BackgroundColor3 = the colour + a neutral
     gradient (white to 92% grey), instead of white + a coloured gradient.
     UIGradient MULTIPLIES BackgroundColor3, so with ui_build's form a controller
     that tints a frame (quest box, map dot, card) gets its colour times the old one.
     ui_build only offers this ("paintable") on panel and button.
  4. Vertical UIListLayouts: ui_build always emits VerticalAlignment=Center, while
     its own preview packs a vertical list from the top. Fixed to Top / Left.
  5. "wraps", "valign" on a layout; "props"; "flat"; "rainbow"; "round".
  6. Drops the PendingIcon attribute; IconName stays.
Then it checks the contract table and fails loudly on a miss.
"""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

GUI = {"Frame", "TextLabel", "ImageLabel", "TextButton", "ImageButton"}
LOW = 0.92

RAINBOW = ["#35D04A", "#11B4F4", "#E63CF0", "#E5121B", "#FF8A1E", "#FFD23A", "#35D04A"]

# name -> (class, default Visible, required child names)
CONTRACT = {
    "XPBar": ("Frame", True, ["Fill", "Rainbow"]),
    "RunClock": ("TextLabel", True, ["Icon"]),
    "SilverCount": ("TextLabel", True, ["Icon"]),
    "GoldCount": ("TextLabel", True, ["Icon"]),
    "KillCount": ("TextLabel", True, ["Icon"]),
    "StageTimer": ("TextLabel", True, []),
    "DifficultyPill": ("Frame", False, ["TierName", "TierMult"]),
    "LevelLabel": ("TextLabel", True, []),
    "NextChest": ("Frame", True, ["Icon", "Price"]),
    "ShieldBar": ("Frame", True, ["Fill", "Text"]),
    "HPBar": ("Frame", True, ["Fill", "Text"]),
    "WeaponRow": ("Frame", True, ["LoadoutSlot"]),
    "TomeRow": ("Frame", True, ["LoadoutSlot"]),
    "QuestTracker": ("Frame", True, ["QuestLine"]),
    "TeammateBars": ("Frame", True, ["Teammate"]),
    "Minimap": ("Frame", True, ["Dots", "Ring", "N", "E", "S", "W", "PlayerArrow"]),
    "ItemStrip": ("Frame", True, ["ItemSlot"]),
    "BossBars": ("Frame", False, ["Main", "Minis"]),
    "InteractPrompt": ("Frame", False, ["Key", "Text"]),
    "Banner": ("Frame", False, ["BannerText", "BannerSub"]),
    "StageTitle": ("Frame", False, ["TierLabel", "StageName", "StageJoke"]),
    "Letterbox": ("Frame", False, ["Top", "Bottom"]),
    "Toast": ("Frame", False, ["ToastPortrait", "ToastTitle", "ToastText"]),
    "PickupToast": ("TextLabel", False, []),
    "DownedOverlay": ("Frame", False, ["DownedLabel", "ReviveBack", "SpectateName"]),
    "HurtFlash": ("Frame", True, []),
    "LevelUpText": ("TextLabel", False, []),
}
# sample child -> (class, required child names); found anywhere in the tree
SAMPLES = {
    "LoadoutSlot": ("Frame", ["Icon", "Level"]),
    "QuestLine": ("Frame", ["Check", "Box", "Text"]),
    "Teammate": ("Frame", ["Portrait", "Name", "HPBack", "DownedTag"]),
    "MapDot": ("Frame", []),
    "ItemSlot": ("Frame", ["Icon", "Count"]),
    "MiniBar": ("Frame", ["Name", "Back", "Text"]),
    "Main": ("Frame", ["Name", "Back", "Text"]),
    "Back": ("Frame", ["Fill"]),
    "HPBack": ("Frame", ["HPFill"]),
    "ReviveBack": ("Frame", ["ReviveFill"]),
    "Minis": ("Frame", ["MiniBar"]),
    "Dots": ("Frame", ["MapDot"]),
}


def hex3(h):
    h = h.lstrip("#")
    return [round(int(h[i:i + 2], 16) / 255, 4) for i in (0, 2, 4)]


def kids(node):
    return node.setdefault("children", [])


def child(node, name):
    for c in node.get("children") or []:
        if c.get("name") == name:
            return c
    return None


def gui_children(node):
    return [c for c in node.get("children") or [] if c["className"] in GUI]


def apply(spec, inst, path):
    props = inst.setdefault("properties", {})

    # 3. tintable colour
    grad = child(inst, "Gradient")
    if grad is not None and inst["className"] == "Frame":
        kp = grad["properties"]["Color"]["ColorSequence"]["keypoints"]
        props["BackgroundColor3"] = {"Color3": kp[-1]["color"]}
        if spec.get("flat"):
            inst["children"].remove(grad)
        elif spec.get("rainbow"):
            props["BackgroundColor3"] = {"Color3": [1, 1, 1]}
            n = len(RAINBOW)
            pts = []
            for i, h in enumerate(RAINBOW):
                a, b = i / n, (i + 1) / n
                pts.append({"time": round(a if i == 0 else a + 0.001, 4), "color": hex3(h)})
                pts.append({"time": round(b, 4), "color": hex3(h)})
            grad["properties"] = {"Rotation": 0,
                                  "Color": {"ColorSequence": {"keypoints": pts}}}
        else:
            grad["properties"]["Color"] = {"ColorSequence": {"keypoints": [
                {"time": 0, "color": [LOW, LOW, LOW]},
                {"time": 1, "color": [1, 1, 1]}]}}

    # 2. font
    if spec.get("font") and "FontFace" in props:
        props["FontFace"] = {"Font": {
            "family": f"rbxasset://fonts/families/{spec['font']}.json",
            "weight": "Regular", "style": "Normal"}}

    # 4, 5. layouts
    lay, lay_inst = spec.get("layout"), child(inst, "Layout")
    if lay and lay_inst is not None and lay_inst["className"] == "UIListLayout":
        lp = lay_inst["properties"]
        if lay.get("dir", "y") != "x":
            lp["VerticalAlignment"] = {"start": "Top", "center": "Center",
                                       "end": "Bottom"}[lay.get("align", "start")]
            lp["HorizontalAlignment"] = "Left"
        if lay.get("valign"):
            lp["VerticalAlignment"] = lay["valign"]
        if lay.get("wraps"):
            lp["Wraps"] = True

    if spec.get("round") is not None:
        kids(inst).insert(0, {"className": "UICorner", "name": "Corner", "properties": {
            "CornerRadius": {"UDim": [spec["round"], 0]}}})
    props.update(spec.get("props") or {})

    # 6. icons
    if inst["className"] == "ImageLabel":
        attrs = inst.setdefault("attributes", {})
        attrs.pop("PendingIcon", None)
        attrs["IconName"] = spec["icon"]

    sk, ik = spec.get("children") or [], gui_children(inst)
    if len(sk) != len(ik):
        raise SystemExit(f"tree mismatch at {path}: {len(sk)} spec children, "
                         f"{len(ik)} instances")
    for s, i in zip(sk, ik):
        if s.get("name") != i.get("name"):
            raise SystemExit(f"name mismatch at {path}: {s.get('name')} vs {i.get('name')}")
        apply(s, i, f"{path}.{s['name']}")


def visible(inst):
    return inst.get("properties", {}).get("Visible", True)


def walk(node, path=""):
    for c in node.get("children") or []:
        p = f"{path}.{c['name']}" if path else c.get("name", c["className"])
        yield p, c
        yield from walk(c, p)


def check_contract(root):
    bad = []
    top = {c.get("name"): c for c in root["children"]}
    for name, (cls, vis, need) in CONTRACT.items():
        n = top.get(name)
        if n is None:
            bad.append(f"missing {name}")
            continue
        if n["className"] != cls:
            bad.append(f"{name} is {n['className']}, wants {cls}")
        if visible(n) != vis:
            bad.append(f"{name} Visible={visible(n)}, wants {vis}")
        for k in need:
            if child(n, k) is None:
                bad.append(f"{name} has no child {k}")
    seen = {}
    for p, n in walk(root):
        seen.setdefault(n.get("name"), []).append(n)
    for name, (cls, need) in SAMPLES.items():
        if name not in seen:
            bad.append(f"missing sample {name}")
        for n in seen.get(name, []):
            if n["className"] != cls:
                bad.append(f"{name} is {n['className']}, wants {cls}")
            for k in need:
                if child(n, k) is None:
                    bad.append(f"{name} has no child {k}")
    # specifics
    xp = top["XPBar"]
    if visible(child(xp, "Rainbow")):
        bad.append("Rainbow must ship hidden")
    if child(child(xp, "Rainbow"), "Gradient") is None:
        bad.append("Rainbow has no UIGradient")
    if top["HurtFlash"]["properties"].get("BackgroundTransparency") != 1:
        bad.append("HurtFlash BackgroundTransparency must be 1")
    for p, n in walk(root):
        if n["className"] == "ImageLabel":
            if not n.get("attributes", {}).get("IconName"):
                bad.append(f"{p} has no IconName")
            if n.get("properties", {}).get("Image"):
                bad.append(f"{p} has an Image")
    for key in ("ResetOnSpawn", "IgnoreGuiInset", "ZIndexBehavior", "Enabled", "DisplayOrder"):
        if key not in root["properties"]:
            bad.append(f"ScreenGui lacks {key}")
    return bad


def main():
    raw_path, project = Path(sys.argv[1]), Path(sys.argv[2])
    here = Path(__file__).resolve().parent
    spec = json.loads((here / "Hud.json").read_text(encoding="utf-8"))
    root = json.loads(raw_path.read_text(encoding="utf-8"))

    canvas = child(root, "CanvasFrame")
    tree = gui_children(canvas)
    if len(tree) != len(spec["children"]):
        raise SystemExit("top-level count mismatch")
    for s, i in zip(spec["children"], tree):
        apply(s, i, s["name"])

    root["children"] = tree
    root["properties"].update({"DisplayOrder": 10, "ResetOnSpawn": False,
                               "IgnoreGuiInset": True, "ZIndexBehavior": "Sibling",
                               "Enabled": True})
    root.pop("attributes", None)

    bad = check_contract(root)
    for b in bad:
        print("CONTRACT:", b)
    if bad:
        raise SystemExit(f"{len(bad)} contract failures")

    out = project / "src" / "ui" / "Hud.model.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(root, indent=1), encoding="utf-8")
    print("wrote", out)

    # Luau builder from the same final tree
    sys.path.insert(0, str(Path(sys.argv[3])))
    import ui_build
    base_value = ui_build.lua_value

    def lua_value(v, prop=None, is_attribute=False):
        if isinstance(v, dict) and "Font" in v:
            f = v["Font"]
            return (f'Font.new("{f["family"]}", Enum.FontWeight.{f["weight"]}, '
                    f'Enum.FontStyle.{f["style"]})')
        return base_value(v, prop=prop, is_attribute=is_attribute)

    ui_build.lua_value = lua_value
    ui_build.ENUM_PROPS.update({"VerticalAlignment", "HorizontalAlignment"})
    lroot = copy.deepcopy(root)
    lroot["name"] = "Hud"
    lua = here / "Hud.lua"
    lua.write_text(ui_build.luau(ui_build.qualify_enums(lroot)), encoding="utf-8")
    print("wrote", lua)

    elements, icons = [], {}
    for p, n in walk(root):
        if n["className"] in GUI:
            elements.append({"path": "Hud." + p, "name": n["name"],
                             "class": n["className"], "visible": visible(n)})
        if n["className"] == "ImageLabel":
            icons.setdefault(n["attributes"]["IconName"], []).append("Hud." + p)
    man = project / "assets" / "ui" / "manifest.Hud.json"
    man.write_text(json.dumps({
        "screenGui": "Hud", "displayOrder": 10,
        "model": "src/ui/Hud.model.json",
        "note": "Sample children (LoadoutSlot, QuestLine, Teammate, MapDot, ItemSlot, "
                "MiniBar) repeat; the code clones the first. Icon keys on samples are "
                "placeholders the code overwrites.",
        "elements": elements,
        "icons": {k: sorted(set(v)) for k, v in sorted(icons.items())},
    }, indent=1), encoding="utf-8")
    print("wrote", man, f"({len(elements)} elements, {len(icons)} icon keys)")


if __name__ == "__main__":
    main()

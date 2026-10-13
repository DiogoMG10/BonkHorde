"""Bake uploaded icon ids into the interface trees.

The interface stage left every icon ImageLabel empty with a `PendingIcon` (or
`IconName`) attribute naming the icon it wants, and the controllers fill them at
runtime. That leaves the place itself full of empty images, which is exactly
what the wiring check exists to catch. This writes the real id into `Image` for
every label that names its icon, and removes `PendingIcon`. Controllers still
overwrite the dynamic ones (offer cards, inventory slots) with live data.

    py tools/ui/bake_icons.py
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IDS = json.loads((ROOT / "assets" / "ui" / "icon_ids.json").read_text(encoding="utf-8"))

# labels that carry no attribute but have one obvious icon
BY_NAME = {"Check": "IconCheck", "ChestIcon": "IconChest", "IconGold": "IconGold", "Padlock": "IconPadlock"}
IMAGE = {"ImageLabel", "ImageButton"}


def walk(node, counts, path=""):
    cls = node.get("className")
    name = node.get("name", "")
    here = f"{path}.{name}" if path else name
    if cls in IMAGE:
        props = node.setdefault("properties", {})
        attrs = node.get("attributes") if isinstance(node.get("attributes"), dict) else {}
        key = attrs.get("PendingIcon") or attrs.get("IconName") or BY_NAME.get(name) or (name if name in IDS else None)
        if isinstance(key, dict):  # rojo attribute form {"String": "IconX"}
            key = next(iter(key.values()))
        if key in IDS:
            props["Image"] = f"rbxassetid://{IDS[key]}"
            if "PendingIcon" in attrs:
                attrs.pop("PendingIcon")
                attrs["IconName"] = key
            counts["baked"] += 1
        elif not props.get("Image"):
            counts["empty"].append(here)
    for child in node.get("children") or []:
        walk(child, counts, here)


def main():
    for path in sorted((ROOT / "src" / "ui").glob("*.model.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        counts = {"baked": 0, "empty": []}
        walk(doc, counts, path.stem.split(".")[0])
        path.write_text(json.dumps(doc, indent=1), encoding="utf-8", newline="\n")
        print(f"{path.name}: {counts['baked']} baked, {len(counts['empty'])} still empty")
        for e in counts["empty"]:
            print("   empty:", e)


if __name__ == "__main__":
    main()

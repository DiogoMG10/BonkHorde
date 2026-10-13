"""Make every UIStroke under a text element outline the GLYPHS, not the label box.

A UIStroke with ApplyStrokeMode = Border under a TextLabel draws a rectangle
round the label (seen in Studio on 2026-10-13: every HUD number sat in a box).
Contextual is what outlines the text. Run after any rebuild of src/ui.

    python tools/ui/fix_strokes.py
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEXT = {"TextLabel", "TextButton", "TextBox"}


def walk(node, parent_class, counts):
    cls = node.get("className") or node.get("ClassName")
    if cls == "UIStroke" and parent_class in TEXT:
        props = node.setdefault("properties", {})
        if props.get("ApplyStrokeMode") != "Contextual":
            props["ApplyStrokeMode"] = "Contextual"
            counts[0] += 1
    for child in node.get("children") or []:
        walk(child, cls, counts)


def main():
    for path in sorted((ROOT / "src" / "ui").glob("*.model.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        counts = [0]
        walk(doc, None, counts)
        path.write_text(json.dumps(doc, indent=1), encoding="utf-8")
        print(f"{path.name}: {counts[0]} strokes set to Contextual")


if __name__ == "__main__":
    main()

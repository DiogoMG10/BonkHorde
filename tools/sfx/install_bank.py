"""Install the sound bank into the Rojo tree as real Sound instances.

roblox-sfx emits a data module and a runtime that builds Sounds on first use,
which leaves the place itself with no Sound in it. This writes
src/shared/Sounds.model.json (ReplicatedStorage.Shared.Sounds, one Sound per
role) from the measured manifest, and points the generated Sfx runtime at it so
the instances in the place are the ones that play.

Run after every emit_bank.py:
    py tools/sfx/install_bank.py
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    manifest = json.loads((ROOT / "assets" / "sfx" / "manifest.json").read_text(encoding="utf-8"))
    children = []
    for s in manifest["sounds"]:
        children.append({
            "name": s["role"],
            "className": "Sound",
            "properties": {
                "SoundId": f"rbxassetid://{s['id']}",
                "Volume": s["volume"],
                "Looped": bool(s.get("looped")),
            },
        })
    tree = {"className": "Folder", "children": children}
    (ROOT / "src" / "shared" / "Sounds.model.json").write_text(json.dumps(tree, indent=1), encoding="utf-8", newline="\n")

    sfx = ROOT / "src" / "shared" / "Sfx.luau"
    text = sfx.read_text(encoding="utf-8")
    marker = "	local folder = templates()\n	local existing = folder:FindFirstChild(role)"
    if "script.Parent:FindFirstChild(\"Sounds\")" not in text:
        assert marker in text, "Sfx.luau changed shape; update install_bank.py"
        text = text.replace(marker, """	-- the bank installed in the place (tools/sfx/install_bank.py) comes first
	local installed = script.Parent:FindFirstChild("Sounds")
	local ready = installed and installed:FindFirstChild(role)
	if ready and ready:IsA("Sound") then
		return ready
	end
""" + marker, 1)
        sfx.write_text(text, encoding="utf-8", newline="\n")
    print(f"installed {len(children)} sounds into src/shared/Sounds.model.json")


if __name__ == "__main__":
    main()

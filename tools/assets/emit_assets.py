"""Turn assets/meshes/manifest.json into assets/models/Assets.rbxmx.

The manifest is measured in Studio (tools/studio bridge): for every generated
model, each MeshPart's mesh id, texture id, size, natural mesh size and CFrame
relative to the model's bounding-box centre. This script writes one rbxmx holding
a Folder `Assets` with a sub-folder per class, which Rojo puts in
ReplicatedStorage. `MeshId` cannot be set from a .model.json, so rbxmx it is.

Every model gets an invisible 0.2-stud `Root` part as its PrimaryPart:
  - enemies, heroes, pickups, weapons, markers: Root at the bounding-box CENTRE
  - props and interactables: Root at the BOTTOM centre, so they sit on the ground
`yaw` in design/mesh_jobs.json (degrees) turns a model so its front faces -Z.

    python tools/assets/emit_assets.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[2]
FOLDER = {"enemy": "Enemies", "miniboss": "Enemies", "boss": "Enemies", "hero": "Heroes", "weapon": "Weapons",
          "pickup": "Pickups", "marker": "Pickups", "interactable": "Interactables", "prop": "Props"}
LIMB = {"body": "Body", "head": "Head", "left arm": "ArmL", "right arm": "ArmR", "left leg": "LegL", "right leg": "LegR"}
GROUNDED = {"interactable", "prop"}
SOLID = {"interactable", "prop"}


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def cframe_xml(name, pos, rot):
    r = [rot[i][j] for i in range(3) for j in range(3)]
    tags = ["R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    body = "".join(f"<{t}>{v:.6f}</{t}>" for t, v in zip(tags, r))
    return f'<CoordinateFrame name="{name}"><X>{pos[0]:.4f}</X><Y>{pos[1]:.4f}</Y><Z>{pos[2]:.4f}</Z>{body}</CoordinateFrame>'


def vec(name, v):
    return f'<Vector3 name="{name}"><X>{v[0]:.4f}</X><Y>{v[1]:.4f}</Y><Z>{v[2]:.4f}</Z></Vector3>'


class Ref:
    n = 0

    @classmethod
    def new(cls):
        cls.n += 1
        return f"RBX{cls.n}"


def part_xml(name, ref, pos, rot, size, mesh=None, texture=None, mesh_size=None, collide=False, transparency=0.0):
    cls = "MeshPart" if mesh else "Part"
    props = [
        f'<string name="Name">{escape(name)}</string>',
        '<bool name="Anchored">true</bool>',
        f'<bool name="CanCollide">{"true" if collide else "false"}</bool>',
        f'<bool name="CanQuery">{"true" if collide else "false"}</bool>',
        '<bool name="CanTouch">false</bool>',
        f'<float name="Transparency">{transparency}</float>',
        cframe_xml("CFrame", pos, rot),
        vec("size", size),
    ]
    if mesh:
        props.append(vec("InitialSize", mesh_size or size))
        props.append(f'<Content name="MeshId"><url>{escape(mesh)}</url></Content>')
        if texture:
            props.append(f'<Content name="TextureID"><url>{escape(texture)}</url></Content>')
        # Hull is cheap and good enough for a rock or a tree trunk
        props.append(f'<token name="CollisionFidelity">{1 if collide else 0}</token>')
    return f'<Item class="{cls}" referent="{ref}"><Properties>{"".join(props)}</Properties></Item>'


def main() -> None:
    manifest = json.loads((ROOT / "assets/meshes/manifest.json").read_text(encoding="utf-8"))["assets"]
    jobs = {j["name"]: j for j in json.loads((ROOT / "design/mesh_jobs.json").read_text(encoding="utf-8"))["jobs"]}
    folders: dict[str, list[str]] = {}
    count = 0
    for name in sorted(manifest):
        asset = manifest[name]
        cls = asset.get("class") or jobs.get(name, {}).get("class", "prop")
        yaw = math.radians(jobs.get(name, {}).get("yaw", 0))
        c, s = math.cos(yaw), math.sin(yaw)
        turn = [[c, 0, s], [0, 1, 0], [-s, 0, c]]
        half_h = asset["bounds_studs"][1] / 2
        lift = half_h if cls in GROUNDED else 0.0
        root_ref = Ref.new()
        items = [part_xml("Root", root_ref, (0, 0, 0), [[1, 0, 0], [0, 1, 0], [0, 0, 1]], (0.2, 0.2, 0.2), transparency=1.0)]
        used: dict[str, int] = {}
        for p in asset["parts"]:
            cf = p["cframe"]
            pos = cf[0:3]
            rot = [cf[3:6], cf[6:9], cf[9:12]]
            # rotate about the model centre, then lift grounded models so Root is at their feet
            new_pos = [sum(turn[i][k] * pos[k] for k in range(3)) for i in range(3)]
            new_pos[1] += lift
            new_rot = matmul(turn, rot)
            pname = LIMB.get(p["name"], "Body" if len(asset["parts"]) == 1 else p["name"].title().replace(" ", ""))
            used[pname] = used.get(pname, 0) + 1
            if used[pname] > 1:
                pname = f"{pname}{used[pname]}"
            items.append(part_xml(pname, Ref.new(), new_pos, new_rot, p["size"], p["mesh"], p["texture"], p["meshSize"], collide=cls in SOLID))
        model = (
            f'<Item class="Model" referent="{Ref.new()}"><Properties><string name="Name">{escape(name)}</string>'
            f'<Ref name="PrimaryPart">{root_ref}</Ref></Properties>{"".join(items)}</Item>'
        )
        folders.setdefault(FOLDER.get(cls, "Props"), []).append(model)
        count += 1
    body = "".join(
        f'<Item class="Folder" referent="{Ref.new()}"><Properties><string name="Name">{f}</string></Properties>{"".join(models)}</Item>'
        for f, models in sorted(folders.items())
    )
    xml = f'<roblox version="4"><Item class="Folder" referent="{Ref.new()}"><Properties><string name="Name">Assets</string></Properties>{body}</Item></roblox>'
    out = ROOT / "assets/models/Assets.rbxmx"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(xml, encoding="utf-8")
    print(f"wrote {out.relative_to(ROOT)}: {count} models in {len(folders)} folders, {len(xml) // 1024} KB")


if __name__ == "__main__":
    main()

"""Turn work/map/layout.json (written by tools/map/prove.luau) into:

  work/map/plan.png   top-down plan: height shading, unreachable ground hatched
                      red, anchors as dots, props coloured by kind
  work/map/map.rbxmx  the dressing as a Roblox model: one marker part per prop
                      and per anchor, named by kind, at its real position
  work/map/build.lua  a command-bar script that builds terrain and props in
                      Studio edit mode from the same shared module

Needs Pillow, so run it with the Forge Python:
    D:\\Forge\\system\\python\\python.exe tools/map/emit_map.py
"""

import json
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "work" / "map"

COLOURS = {
    "TreeLeaning": (46, 160, 80),
    "TreeTwin": (36, 140, 70),
    "TreeSapling": (90, 190, 100),
    "Bush": (120, 200, 90),
    "BoulderLarge": (120, 126, 140),
    "BoulderFlat": (150, 154, 165),
    "RockSmall": (170, 172, 180),
    "FallenLog": (140, 96, 60),
    "Stump": (120, 84, 54),
    "LanternPost": (255, 196, 90),
    "RuinWall": (200, 190, 170),
    "RuinArch": (220, 210, 190),
    "RuinTower": (240, 230, 210),
}


def plan(layout):
    heights = layout["heights"]
    n = len(heights)
    scale = 8
    img = Image.new("RGB", (n * scale, n * scale))
    px = img.load()
    lo = min(min(r) for r in heights)
    hi = max(max(r) for r in heights)
    for iz in range(n):
        for ix in range(n):
            h = (heights[iz][ix] - lo) / (hi - lo)
            # hillshade from the north-west so slopes read
            dx = heights[iz][min(ix + 1, n - 1)] - heights[iz][max(ix - 1, 0)]
            dz = heights[min(iz + 1, n - 1)][ix] - heights[max(iz - 1, 0)][ix]
            shade = max(0.55, min(1.3, 1 - (dx + dz) * 0.035))
            r, g, b = 40 + 70 * h, 96 + 90 * h, 60 + 50 * h
            if layout["reach"][iz][ix] == "0":
                r, g, b = 120, 50, 50
            col = tuple(int(max(0, min(255, v * shade))) for v in (r, g, b))
            for sy in range(scale):
                for sx in range(scale):
                    px[ix * scale + sx, iz * scale + sy] = col
    draw = ImageDraw.Draw(img)
    half, cell = layout["half"], layout["cell"]

    def at(x, z):
        return ((x + half) / cell * scale, (z + half) / cell * scale)

    for prop in layout["props"]:
        x, y = at(prop["x"], prop["z"])
        r = max(2, prop["radius"] / cell * scale) if prop["radius"] > 0 else 1.5
        draw.ellipse((x - r, y - r, x + r, y + r), fill=COLOURS.get(prop["kind"], (255, 0, 255)))
    for a in layout["anchors"]:
        x, y = at(a["x"], a["z"])
        draw.rectangle((x - 1, y - 1, x + 1, y + 1), fill=(255, 235, 120))
    x, y = at(0, 0)
    draw.ellipse((x - 6, y - 6, x + 6, y + 6), outline=(255, 255, 255), width=2)
    img.save(OUT / "plan.png")
    return img.size


def part(ref, name, x, y, z, size, colour, transparency=0.0):
    r, g, b = colour
    return f"""<Item class="Part" referent="R{ref}"><Properties>
<string name="Name">{escape(name)}</string><bool name="Anchored">true</bool><bool name="CanCollide">false</bool>
<CoordinateFrame name="CFrame"><X>{x:.2f}</X><Y>{y:.2f}</Y><Z>{z:.2f}</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>
<Vector3 name="size"><X>{size[0]:.2f}</X><Y>{size[1]:.2f}</Y><Z>{size[2]:.2f}</Z></Vector3>
<Color3uint8 name="Color3uint8">{(255 << 24) | (r << 16) | (g << 8) | b}</Color3uint8>
<float name="Transparency">{transparency}</float>
</Properties></Item>"""


def height_at(layout, x, z):
    half, cell = layout["half"], layout["cell"]
    n = len(layout["heights"])
    ix = max(0, min(n - 1, round((x + half) / cell)))
    iz = max(0, min(n - 1, round((z + half) / cell)))
    return layout["heights"][iz][ix]


def rbxmx(layout):
    ref = 0
    out = ['<roblox version="4">', '<Item class="Folder" referent="R0"><Properties><string name="Name">MapLayout</string></Properties>']
    out.append('<Item class="Folder" referent="RP"><Properties><string name="Name">Props</string></Properties>')
    for prop in layout["props"]:
        ref += 1
        w = max(2.0, prop["radius"] * 2) if prop["radius"] > 0 else 2.0
        tall = 6.0 * prop["scale"]
        y = height_at(layout, prop["x"], prop["z"]) + tall / 2
        out.append(part(ref, prop["kind"], prop["x"], y, prop["z"], (w, tall, w), COLOURS.get(prop["kind"], (255, 0, 255))))
    out.append("</Item>")
    out.append('<Item class="Folder" referent="RA"><Properties><string name="Name">Anchors</string></Properties>')
    for a in layout["anchors"]:
        ref += 1
        y = height_at(layout, a["x"], a["z"]) + 0.5
        out.append(part(ref, "Anchor", a["x"], y, a["z"], (3, 1, 3), (255, 235, 120), 0.3))
    out.append("</Item></Item></roblox>")
    (OUT / "map.rbxmx").write_text("\n".join(out), encoding="utf-8", newline="\n")
    return ref


BUILD = """-- Build the Forest Grove in Studio EDIT mode, for looking at the map without
-- pressing Play. Paste into the command bar. It runs the same shared module
-- the server runs, so what you see here is what a run gets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)

local VOXEL, FLOOR_Y = 4, -8
local map = MapGen.build(GameConfig.MapSizeStuds, GameConfig.HeightCellStuds, GameConfig.WallHeight)
local anchors = MapGen.anchors(map, 26, 0.35)
local props = MapGen.props(map, anchors)

local terrain = workspace.Terrain
terrain:Clear()
local half = map.half
for x0 = -half, half - 1, 64 do
	for z0 = -half, half - 1, 64 do
		for x = x0, x0 + 60, VOXEL do
			for z = z0, z0 + 60, VOXEL do
				local h = MapGen.heightAt(map, x + 2, z + 2)
				local slope = MapGen.slopeAt(map, x + 2, z + 2)
				local material = Enum.Material.LeafyGrass
				if slope > GameConfig.CliffSlope then
					material = Enum.Material.Rock
				elseif slope > 0.6 then
					material = Enum.Material.Ground
				end
				terrain:FillBlock(CFrame.new(x + 2, (h + FLOOR_Y) / 2, z + 2), Vector3.new(VOXEL, h - FLOOR_Y, VOXEL), material)
			end
		end
		task.wait()
	end
end

local old = workspace:FindFirstChild("Map")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "Map"
local source = ReplicatedStorage.Assets.Props
for i, prop in props do
	local template = source:FindFirstChild(prop.kind)
	if template then
		local model = template:Clone()
		model:ScaleTo(prop.scale)
		model:PivotTo(CFrame.new(prop.x, MapGen.heightAt(map, prop.x, prop.z) - 0.4 * prop.scale, prop.z) * CFrame.Angles(0, prop.yaw, 0))
		model.Parent = folder
	end
	if i % 100 == 0 then
		task.wait()
	end
end
folder.Parent = workspace
print(("Forest Grove built: %d anchors, %d props"):format(#anchors, #props))
"""


def main():
    layout = json.loads((OUT / "layout.json").read_text(encoding="utf-8"))
    size = plan(layout)
    count = rbxmx(layout)
    (OUT / "build.lua").write_text(BUILD, encoding="utf-8", newline="\n")
    print(f"plan.png {size[0]}x{size[1]}, map.rbxmx {count} markers, build.lua written")


if __name__ == "__main__":
    main()

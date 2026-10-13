-- Build the Forest Grove in Studio EDIT mode, for looking at the map without
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

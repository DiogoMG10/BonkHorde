--!nonstrict
-- MapService - owns the loaded map: its heightfield, the reachable-cell grid and
-- the anchor points interactables and spawns are placed on.
--
-- The map is a pure function (Shared.Core.MapGen), so the server can simulate on
-- it without physics and every client can rebuild the same heights. This service
-- also writes that heightfield into Roblox Terrain so characters have ground.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)

local MapService = Knit.CreateService({ Name = "MapService" })

local VOXEL = 4
local FLOOR_Y = -8

function MapService:KnitInit()
	local c = GameConfig
	self._map = MapGen.build(c.MapSizeStuds, c.HeightCellStuds, c.WallHeight)
	self._anchors = MapGen.anchors(self._map, 26, 0.35)
	-- scenery first, so "reachable" already knows what a tree is
	self._props = MapGen.props(self._map, self._anchors)
	MapGen.block(self._map, self._props)
	self._reach = MapGen.reachable(self._map, 0, 0, c.CliffSlope)
	self._terrainReady = false
end

function MapService:KnitStart()
	self:_light()
	task.spawn(function()
		local ok, err = pcall(function()
			self:_writeTerrain()
		end)
		if not ok then
			warn(`[MapService] terrain write failed: {err}`)
		end
		local okProps, errProps = pcall(function()
			self:_placeProps()
		end)
		if not okProps then
			warn(`[MapService] prop placement failed: {errProps}`)
		end
		self._terrainReady = true
		print(`[MapService] terrain ready, {#self._anchors} anchors, {#self._props} props`)
	end)
end

function MapService:GetMap()
	return self._map
end

function MapService:HeightAt(x: number, z: number): number
	return MapGen.heightAt(self._map, x, z)
end

function MapService:CanStep(x: number, z: number, nx: number, nz: number): boolean
	return MapGen.canStep(self._map, x, z, nx, nz, GameConfig.CliffSlope)
end

function MapService:IsReachable(x: number, z: number): boolean
	return MapGen.isReachable(self._map, self._reach, x, z)
end

function MapService:GetAnchors()
	return self._anchors
end

function MapService:IsTerrainReady(): boolean
	return self._terrainReady
end

function MapService:SpawnPoint(index: number): Vector3
	local angle = (index - 1) * (math.pi * 2 / 3)
	local x, z = math.cos(angle) * 5, math.sin(angle) * 5
	return Vector3.new(x, self:HeightAt(x, z) + 4, z)
end

-- The twilight forest look: cool moonlight, teal haze, saturated grade. Built in
-- code so the place file carries no hand-set lighting to drift out of step.
function MapService:_light()
	for _, child in Lighting:GetChildren() do
		child:Destroy()
	end
	Lighting.ClockTime = 0.6
	Lighting.GeographicLatitude = 38
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(92, 130, 166)
	Lighting.OutdoorAmbient = Color3.fromRGB(104, 142, 178)
	Lighting.ColorShift_Top = Color3.fromRGB(150, 200, 255)
	Lighting.ColorShift_Bottom = Color3.fromRGB(40, 70, 100)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.ExposureCompensation = 0.55
	Lighting.ShadowSoftness = 0.6
	Lighting.GlobalShadows = true

	local sky = Instance.new("Sky")
	sky.StarCount = 3000
	sky.MoonAngularSize = 14
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local haze = Instance.new("Atmosphere")
	haze.Density = 0.34
	haze.Offset = 0.2
	haze.Color = Color3.fromRGB(70, 150, 190)
	haze.Decay = Color3.fromRGB(30, 80, 120)
	haze.Glare = 0
	haze.Haze = 2.4
	haze.Parent = Lighting

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Saturation = 0.28
	grade.Contrast = 0.1
	grade.TintColor = Color3.fromRGB(232, 244, 255)
	grade.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 26
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	local terrain = Workspace.Terrain
	-- soft puffy clouds lit by the moon, the reference's dark cloud bank in cartoon form
	local oldClouds = terrain:FindFirstChildOfClass("Clouds")
	if oldClouds then
		oldClouds:Destroy()
	end
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.62
	clouds.Density = 0.75
	clouds.Color = Color3.fromRGB(120, 175, 215)
	clouds.Parent = terrain
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(74, 150, 78))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(112, 92, 66))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(96, 104, 122))
end

-- Dress the map: clone each prop model from ReplicatedStorage.Assets.Props onto
-- its spot. A kind with no model yet is skipped, so the game runs either way.
function MapService:_placeProps()
	local old = Workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Map"
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assets:FindFirstChild("Props")
	local placed = 0
	if source then
		for i, prop in self._props do
			local template = source:FindFirstChild(prop.kind)
			if template and template:IsA("Model") then
				local model = template:Clone()
				model:ScaleTo(prop.scale)
				local y = MapGen.heightAt(self._map, prop.x, prop.z) - 0.4 * prop.scale
				model:PivotTo(CFrame.new(prop.x, y, prop.z) * CFrame.Angles(0, prop.yaw, 0))
				if prop.kind == "LanternPost" then
					local glow = Instance.new("PointLight")
					glow.Color = Color3.fromRGB(255, 190, 110)
					glow.Brightness = 2.2
					glow.Range = 34
					glow.Shadows = false
					glow.Parent = model.PrimaryPart
				end
				model.Parent = folder
				placed += 1
			end
			if i % 150 == 0 then
				task.wait()
			end
		end
	end
	folder.Parent = Workspace
	self._propsPlaced = placed
end

-- Write the heightfield into Terrain, a slab of columns at a time so the server
-- never stalls. Grass on gentle ground, Ground on slopes, Rock on cliffs.
function MapService:_writeTerrain()
	local terrain = Workspace.Terrain
	terrain:Clear()
	pcall(function()
		terrain.GrassLength = 0.25 -- short grass, so gems, coins and feet stay visible
	end)
	local map = self._map
	local half = map.half
	local topY = GameConfig.WallHeight + VOXEL
	local layers = math.floor((topY - FLOOR_Y) / VOXEL)
	local chunk = 32 -- columns per side per write
	local columns = math.floor(map.size / VOXEL)
	local air = Enum.Material.Air

	for cx = 0, columns - 1, chunk do
		for cz = 0, columns - 1, chunk do
			local nx = math.min(chunk, columns - cx)
			local nz = math.min(chunk, columns - cz)
			local materials = table.create(nx)
			local occupancy = table.create(nx)
			for ix = 1, nx do
				local matX, occX = table.create(layers), table.create(layers)
				for iy = 1, layers do
					matX[iy] = table.create(nz, air)
					occX[iy] = table.create(nz, 0)
				end
				materials[ix], occupancy[ix] = matX, occX
				local x = -half + (cx + ix - 1) * VOXEL + VOXEL / 2
				for iz = 1, nz do
					local z = -half + (cz + iz - 1) * VOXEL + VOXEL / 2
					local h = MapGen.heightAt(map, x, z)
					local slope = MapGen.slopeAt(map, x, z)
					local material = Enum.Material.LeafyGrass -- no tall decoration blades hiding gems and feet
					if slope > 1.1 or h > GameConfig.WallHeight - 14 then
						material = Enum.Material.Rock
					elseif slope > 0.55 then
						material = Enum.Material.Ground
					end
					for iy = 1, layers do
						local bottom = FLOOR_Y + (iy - 1) * VOXEL
						local fill = math.clamp((h - VOXEL / 2 - bottom) / VOXEL, 0, 1) -- the drawn surface sits half a voxel above the fill
						if fill > 0 then
							occX[iy][iz] = fill
							-- only the top couple of voxels carry the surface material
							matX[iy][iz] = if h - bottom <= VOXEL * 2 then material else Enum.Material.Ground
						end
					end
				end
			end
			local minV = Vector3.new(-half + cx * VOXEL, FLOOR_Y, -half + cz * VOXEL)
			local maxV = minV + Vector3.new(nx * VOXEL, layers * VOXEL, nz * VOXEL)
			terrain:WriteVoxels(Region3.new(minV, maxV), VOXEL, materials, occupancy)
		end
		task.wait()
	end
end

return MapService

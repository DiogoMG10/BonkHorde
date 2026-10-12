--!nonstrict
-- MapService - owns the loaded map: its heightfield, the reachable-cell grid and
-- the anchor points interactables and spawns are placed on.
--
-- The map is a pure function (Shared.Core.MapGen), so the server can simulate on
-- it without physics and every client can rebuild the same heights. This service
-- also writes that heightfield into Roblox Terrain so characters have ground.

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
	self._reach = MapGen.reachable(self._map, 0, 0, c.CliffSlope)
	self._anchors = MapGen.anchors(self._map, 26, 0.35)
	self._terrainReady = false
end

function MapService:KnitStart()
	task.spawn(function()
		local ok, err = pcall(function()
			self:_writeTerrain()
		end)
		if not ok then
			warn(`[MapService] terrain write failed: {err}`)
		end
		self._terrainReady = true
		print(`[MapService] terrain ready, {#self._anchors} anchors`)
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
					local material = Enum.Material.Grass
					if slope > 1.1 or h > GameConfig.WallHeight - 14 then
						material = Enum.Material.Rock
					elseif slope > 0.55 then
						material = Enum.Material.Ground
					end
					for iy = 1, layers do
						local bottom = FLOOR_Y + (iy - 1) * VOXEL
						local fill = math.clamp((h - bottom) / VOXEL, 0, 1)
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

--!nonstrict
-- MapService - owns the loaded map: its heightfield, the reachable-cell grid and
-- the anchor points interactables and spawns are placed on.
--
-- The map is the Wardwood (Shared.Core.World over Shared.Core.MapGen): a pure
-- function, so the server can simulate on it without physics and every client
-- can rebuild the same heights. This service writes that heightfield into
-- Roblox Terrain so characters have ground, lights it (Wardwood/Look) and
-- builds its scenery (Wardwood/Builder).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)
local World = require(ReplicatedStorage.Shared.Core.World)

local Builder = require(script.Parent.Parent.Wardwood.Builder)
local Look = require(script.Parent.Parent.Wardwood.Look)

local MapService = Knit.CreateService({ Name = "MapService" })

local VOXEL = 4
local FLOOR_Y = -8

function MapService:KnitInit()
	-- scenery is placed (and blocked) by World.build, so "reachable" already knows what a tree is
	self._world = World.build(GameConfig)
	self._map = self._world.map
	self._anchors = self._world.anchors
	self._props = self._world.props
	self._reach = MapGen.reachable(self._map, 0, 0, GameConfig.CliffSlope)
	self._terrainReady = false
end

function MapService:KnitStart()
	Look.apply()
	task.spawn(function()
		local ok, err = pcall(function()
			self:_writeTerrain()
		end)
		if not ok then
			warn(`[MapService] terrain write failed: {err}`)
		end
		local okProps, errProps = pcall(function()
			self._propsPlaced = Builder.build(self._world)
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

-- Write the heightfield into Terrain, a slab of columns at a time so the server
-- never stalls. Each column's surface comes from World.surface (meadow grass,
-- lush grass, forest floor, worn paths, rock on the cliffs, sand at the pond).
function MapService:_writeTerrain()
	local terrain = Workspace.Terrain
	terrain:Clear()
	local map = self._map
	local world = self._world
	local half = map.half
	local chunk = 32 -- columns per side per write
	local columns = math.floor(map.size / VOXEL)
	local air = Enum.Material.Air

	for cx = 0, columns - 1, chunk do
		for cz = 0, columns - 1, chunk do
			local nx = math.min(chunk, columns - cx)
			local nz = math.min(chunk, columns - cz)
			-- only as many layers as this chunk's highest column needs: the
			-- mountains are tall, the playable world mostly is not
			local topH = 0
			for ix = 1, nx do
				for iz = 1, nz do
					local x = -half + (cx + ix - 1) * VOXEL + VOXEL / 2
					local z = -half + (cz + iz - 1) * VOXEL + VOXEL / 2
					topH = math.max(topH, MapGen.heightAt(map, x, z))
				end
			end
			local layers = math.ceil((topH + VOXEL - FLOOR_Y) / VOXEL)
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
					local surface = Look.Surfaces[Builder.surface(world, x, z)]
					local material = if surface then surface[1] else Enum.Material.LeafyGrass
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

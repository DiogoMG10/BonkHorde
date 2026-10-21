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
local Signal = require(ReplicatedStorage.Packages.Signal)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)
local Wardwood = require(ReplicatedStorage.Shared.Config.Wardwood)
local World = require(ReplicatedStorage.Shared.Core.World)

local Builder = require(script.Parent.Parent.Wardwood.Builder)
local ArtKit = require(script.Parent.Parent.Wardwood.ArtKit)
local ArtPlan = require(ReplicatedStorage.Shared.Core.ArtPlan)
local Look = require(ReplicatedStorage.Shared.Look)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)

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
	-- the Wardwood's terrain was (re)written; it clears all terrain first, so
	-- the island hub writes its own again after it (HubService)
	self.TerrainWritten = Signal.new()
	self._artReady = false -- the kit's templates are baked (the island hub uses its trees too)
	self._grass = Wardwood.Grass
	self._rng = Random.new()
	-- the prop kinds the M3.B art kit dresses; a kind falls back to its old
	-- models if one of its variations will not bake
	self._art = Wardwood.Art
	self._classic = {}
end

-- the kinds the kit dresses now: none with the art off, else every family
-- that baked whole
function MapService:_artKinds(): { [string]: boolean }?
	if not self._art then
		return nil
	end
	local kinds = {}
	for kind in ArtPlan.Families do
		if not self._classic[kind] then
			kinds[kind] = true
		end
	end
	return kinds
end

function MapService:_publishArt()
	local classic = {}
	for kind in self._classic do
		table.insert(classic, kind)
	end
	table.sort(classic)
	Workspace:SetAttribute("BonkArt", self._art)
	Workspace:SetAttribute("BonkArtClassic", table.concat(classic, ","))
end

-- bake the kit; any family with a variation that will not bake goes back to
-- its old models, on the server and on every client
function MapService:_bakeArt()
	local failed = ArtKit.bakeAll()
	if #failed == 0 then
		return
	end
	local bad = {}
	for _, name in failed do
		bad[(string.gsub(name, "_[LF][OA][DR]$", ""))] = true
	end
	for kind, family in ArtPlan.Families do
		for _, asset in family do
			if bad[asset] then
				self._classic[kind] = true
			end
		end
	end
	self:_publishArt()
	if self._propsPlaced then
		self._propsPlaced = Builder.build(self._world, self:_artKinds())
	end
end

--- Studio only (DevService `art`): the art kit on, or the old props back.
function MapService:SetArt(on: boolean)
	self._art = on
	self:_publishArt()
	self._propsPlaced = Builder.build(self._world, self:_artKinds())
end

function MapService:GetWorld()
	return self._world
end

function MapService:KnitStart()
	-- the server's light never changes after this: every client wears the sky
	-- of where it is (SkyController), so a run cannot darken the island hub
	Look.apply(Skyhold.Sky)
	self:_publishArt()
	if self._art then
		task.spawn(function()
			self:_bakeArt()
			self._artReady = true
		end)
	else
		self._artReady = true
	end
	task.spawn(function()
		local ok, err = pcall(function()
			self:_writeTerrain()
		end)
		if not ok then
			warn(`[MapService] terrain write failed: {err}`)
		end
		local okProps, errProps = pcall(function()
			self._propsPlaced = Builder.build(self._world, self:_artKinds())
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

--- Studio only (DevService `grass`): rewrite the terrain with another grass
--- mode, to compare them in place. The heights do not change, so nothing on
--- the ground moves.
function MapService:SetGrass(mode: string)
	self._grass = mode
	Look.paint(mode)
	self:_writeTerrain()
end

--- A run's start: draw its sky from Wardwood.RunSkies. Nothing changes here:
--- the run's players wear it (the Phase message carries it to them).
function MapService:DrawRunSky(): string
	local name = Wardwood.runSky(self._rng:NextNumber())
	return if Look.Skies[name] then name else "golden"
end

function MapService:GetAnchors()
	return self._anchors
end

function MapService:IsTerrainReady(): boolean
	return self._terrainReady
end

--- Have the art kit's templates finished baking (ReplicatedStorage.WardwoodArt)?
function MapService:IsArtReady(): boolean
	return self._artReady
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
					local surface = Look.Surfaces[Builder.surface(world, x, z, self._grass)]
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
	self.TerrainWritten:Fire()
end

return MapService

--!strict
-- ArtShowcase - where the M3.B art kit stands in for the old props, as a
-- plan anyone can check headless (server/Wardwood/ArtShowcase builds it): in the
-- Old Grove's clearing, every prop the kit has an answer for, on the same
-- spot, turn and size, plus low 3D grass patches over the grassy ground.

local Blueprints = require(script and script.Parent.Blueprints or "./Blueprints")
local MapGen = require(script and script.Parent.MapGen or "./MapGen")
local Wardwood = require(script and script.Parent.Parent.Config.Wardwood or "../Config/Wardwood")
local World = require(script and script.Parent.World or "./World")

local ArtShowcase = {}

ArtShowcase.Centre = { x = -390, z = -40 }
ArtShowcase.Radius = 52

-- old prop kind -> the kit asset that stands in for it
ArtShowcase.Swap = {
	Oak = "Oak",
	OakLeaning = "OakLeaning",
	Beech = "Beech",
	Birch = "Birch",
	Sapling = "Sapling",
	Spruce = "Spruce",
	SpruceFar = "Spruce",
	SpruceRidge = "Spruce",
	Pine = "Pine",
	AncientOak = "AncientOak",
	BoulderLarge = "BoulderLarge",
	RockSmall = "RockSmall",
	BoulderFlat = "BoulderFlat",
	Pillar = "Pillar",
	PillarBroken = "PillarBroken",
}

-- the kit's rocks sit like the mesh props they replace: a little sunk
local SUNK = { BoulderLarge = true, RockSmall = true, BoulderFlat = true }

local GRASS = { "GrassA", "GrassB", "GrassC" }
local GRASS_STEP = 5
local GRASSY = { Carpet = true, Meadow = true, Lush = true }

export type Placement = { asset: string, x: number, y: number, z: number, yaw: number, scale: number, prop: number?, up: { number }? }

local function inside(x: number, z: number, r: number): boolean
	return (x - ArtShowcase.Centre.x) ^ 2 + (z - ArtShowcase.Centre.z) ^ 2 < r * r
end

--- What the showcase puts where (pure, so the specs can check it): the props
--- it re-skins, by index into world.props, and the grass patches.
function ArtShowcase.plan(world): { Placement }
	local map = world.map
	local out = {}
	for i, p in world.props do
		local asset = ArtShowcase.Swap[p.kind]
		if asset and inside(p.x, p.z, ArtShowcase.Radius) then
			local ground = MapGen.heightAt(map, p.x, p.z) + (p.lift or 0)
			if SUNK[p.kind] then
				ground -= 0.4 * p.scale
			end
			table.insert(out, { asset = asset, x = p.x, y = ground, z = p.z, yaw = p.yaw, scale = p.scale, prop = i })
		end
	end
	-- grass on a staggered lattice, every patch turned and sized a little apart
	local r = ArtShowcase.Radius
	local row = 0
	for z = ArtShowcase.Centre.z - r, ArtShowcase.Centre.z + r, GRASS_STEP * 0.87 do
		row += 1
		local shift = if row % 2 == 0 then GRASS_STEP / 2 else 0
		for x = ArtShowcase.Centre.x - r + shift, ArtShowcase.Centre.x + r, GRASS_STEP do
			local jx = (Blueprints.hash(x, z, 11) - 0.5) * 1.6
			local jz = (Blueprints.hash(x, z, 13) - 0.5) * 1.6
			local gx, gz = x + jx, z + jz
			if inside(gx, gz, r) and GRASSY[World.surface(world, gx, gz, Wardwood.Grass)] then
				local h = MapGen.heightAt(map, gx, gz)
				local dx = MapGen.heightAt(map, gx + 2, gz) - MapGen.heightAt(map, gx - 2, gz)
				local dz = MapGen.heightAt(map, gx, gz + 2) - MapGen.heightAt(map, gx, gz - 2)
				local up = { -dx / 4, 1, -dz / 4 }
				table.insert(out, {
					asset = GRASS[1 + math.floor(Blueprints.hash(gx, gz, 17) * 3)],
					x = gx,
					y = h,
					z = gz,
					yaw = Blueprints.hash(gx, gz, 19) * math.pi * 2,
					scale = 0.9 + 0.25 * Blueprints.hash(gx, gz, 23),
					up = up,
				})
			end
		end
	end
	return out
end

return ArtShowcase

--!strict
-- ArtPlan - which Blender art kit model (M3.B, tools/art) each Wardwood prop
-- wears, and where the short 3D grass grows. Pure and deterministic: the
-- server reads it to keep only the colliders of what the kit replaces
-- (Wardwood/Builder), every client reads it to draw the same art and grass
-- (client ArtController), and the specs check it headless.

local Blueprints = require(script and script.Parent.Blueprints or "./Blueprints")
local MapGen = require(script and script.Parent.MapGen or "./MapGen")
local Wardwood = require(script and script.Parent.Parent.Config.Wardwood or "../Config/Wardwood")
local World = require(script and script.Parent.World or "./World")

local ArtPlan = {}

local SPRUCES = { "SpruceA", "SpruceB", "SpruceC" }

-- prop kind -> the kit's variations of it; a prop wears one, picked from its seed
ArtPlan.Families = {
	Oak = { "OakA", "OakB", "OakC" },
	OakLeaning = { "OakLeaningA", "OakLeaningB" },
	Beech = { "BeechA", "BeechB" },
	Birch = { "BirchA", "BirchB" },
	Sapling = { "SaplingA", "SaplingB" },
	Spruce = SPRUCES,
	SpruceFar = SPRUCES,
	SpruceRidge = SPRUCES,
	Pine = { "PineA", "PineB" },
	AncientOak = { "AncientOakA", "AncientOakB" },
	AncientPine = { "AncientPine" },
	Elder = { "Elder" },
	Bush = { "BushA", "BushB", "BushC" },
	Fern = { "FernA", "FernB" },
	Stump = { "StumpA", "StumpB" },
	FallenLog = { "FallenLog" },
	BoulderLarge = { "BoulderLargeA", "BoulderLargeB" },
	RockSmall = { "RockSmallA", "RockSmallB" },
	BoulderFlat = { "BoulderFlat" },
	Menhir = { "MenhirA", "MenhirB" },
	RuinWall = { "RuinWallA", "RuinWallB" },
	Pillar = { "PillarA", "PillarB" },
	PillarBroken = { "PillarBrokenA", "PillarBrokenB" },
}

-- old props the kit makes redundant, left out while it is on: the Elder's
-- part-built root spread (the kit's Elder grows its own roots; it never collided)
ArtPlan.Retired = { ElderRoots = true }

-- the families with a far-away version, "<asset>_LOD" (trees and bushes)
local LOD = {
	Oak = true,
	OakLeaning = true,
	Beech = true,
	Birch = true,
	Sapling = true,
	Spruce = true,
	SpruceFar = true,
	SpruceRidge = true,
	Pine = true,
	AncientOak = true,
	AncientPine = true,
	Elder = true,
	Bush = true,
}

ArtPlan.Grass = { "GrassA", "GrassB", "GrassC" }

--- The kit model a prop wears (nil: the kit has none, the old model stays).
function ArtPlan.asset(prop: World.Prop): string?
	local family = ArtPlan.Families[prop.kind]
	if not family then
		return nil
	end
	if prop.art then
		return prop.art
	end
	return family[1 + math.floor(Blueprints.hash(prop.x, prop.z, 911) * #family) % #family]
end

--- Whether a prop's kind has a far-away model.
function ArtPlan.hasLod(prop: World.Prop): boolean
	return LOD[prop.kind] == true
end

--- Where its model's foot goes: on the ground, mesh props (the rocks, bushes,
--- logs and walls the kit replaces) a little sunk as the old ones were.
function ArtPlan.footY(world: World.World, prop: World.Prop): number
	local ground = MapGen.heightAt(world.map, prop.x, prop.z) + (prop.lift or 0)
	if Blueprints.get(prop.kind) == nil then
		ground -= 0.4 * prop.scale
	end
	return ground
end

--- A small, fixed colour shift per plant, so a wood of the same few models
--- never reads as copies: a little lighter or darker, warmer or cooler.
function ArtPlan.tint(prop: World.Prop): (number, number, number)
	local k = 0.9 + 0.2 * Blueprints.hash(prop.x, prop.z, 919)
	local warm = (Blueprints.hash(prop.x, prop.z, 929) - 0.5) * 0.12
	return k * (1 + warm), k, k * (1 - warm)
end

-- ------------------------------------------------------------------ grass

local GRASSY = { Carpet = true, Meadow = true, Lush = true }

export type GrassPatch = { asset: string, x: number, y: number, z: number, yaw: number, scale: number, up: { number } }

--- A grass field over a world: `field(cx, cz)` is the patch that grows in grid
--- cell (cx, cz) (Config/Wardwood.ArtGrass.cell studs a side), or nil where
--- the ground is not grassy, or a trunk, rock or wall stands. Cached per cell.
function ArtPlan.grassField(world: World.World): (number, number) -> GrassPatch?
	local cell = Wardwood.ArtGrass.cell
	local map = world.map
	local B = 24
	local solids: { [number]: { { number } } } = {}
	local function addSolid(x: number, z: number, r: number)
		local k = math.floor(x / B) * 4096 + math.floor(z / B)
		local list = solids[k]
		if not list then
			list = {}
			solids[k] = list
		end
		table.insert(list, { x, z, r })
	end
	for _, p in world.props do
		if p.blocks then
			for _, b in p.blocks do
				addSolid(b[1], b[2], b[3])
			end
		elseif p.radius > 0 then
			addSolid(p.x, p.z, p.radius)
		end
	end
	local function blocked(x: number, z: number): boolean
		local cx, cz = math.floor(x / B), math.floor(z / B)
		for ix = cx - 1, cx + 1 do
			for iz = cz - 1, cz + 1 do
				for _, s in solids[ix * 4096 + iz] or {} do
					local r = s[3] + 0.5
					if (s[1] - x) ^ 2 + (s[2] - z) ^ 2 < r * r then
						return true
					end
				end
			end
		end
		return false
	end
	local cache: { [number]: GrassPatch | false } = {}
	return function(cx: number, cz: number): GrassPatch?
		local key = cx * 65536 + cz
		local known = cache[key]
		if known ~= nil then
			return known or nil
		end
		local x = (cx + 0.5 + (Blueprints.hash(cx, cz, 11) - 0.5) * 0.4) * cell
		local z = (cz + 0.5 + (Blueprints.hash(cx, cz, 13) - 0.5) * 0.4) * cell
		local patch: GrassPatch | false = false
		if MapGen.outside(x, z) < -2 and GRASSY[World.surface(world, x, z, Wardwood.Grass)] and not blocked(x, z) then
			local dx = MapGen.heightAt(map, x + 2, z) - MapGen.heightAt(map, x - 2, z)
			local dz = MapGen.heightAt(map, x, z + 2) - MapGen.heightAt(map, x, z - 2)
			patch = {
				asset = ArtPlan.Grass[1 + math.floor(Blueprints.hash(cx, cz, 17) * 3) % 3],
				x = x,
				y = MapGen.heightAt(map, x, z),
				z = z,
				yaw = Blueprints.hash(cx, cz, 19) * math.pi * 2,
				scale = 0.9 + 0.25 * Blueprints.hash(cx, cz, 23),
				up = { -dx / 4, 1, -dz / 4 },
			}
		end
		cache[key] = patch
		return patch or nil
	end
end

return ArtPlan

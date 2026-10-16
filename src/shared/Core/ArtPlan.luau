--!strict
-- ArtPlan - which Blender art kit model (M3.B, tools/art) each Wardwood prop
-- wears. Pure and deterministic: the server reads it to keep only the
-- colliders of what the kit replaces (Wardwood/Builder), every client reads
-- it to draw the same art (client ArtController), and the specs check it.

local Blueprints = require(script and script.Parent.Blueprints or "./Blueprints")
local MapGen = require(script and script.Parent.MapGen or "./MapGen")
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
	FallenGiant = { "FallenGiant" },
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

--- Where a prop's model goes: its pivot (x, y, z), its turn and its tilt about
--- its own length (radians). The Fallen Giant lies bank to bank across its
--- gully, tilted as Blueprints.FallenGiant lays the trunk its collider follows.
function ArtPlan.place(world: World.World, prop: World.Prop): (number, number, number, number, number)
	if prop.kind == "FallenGiant" then
		local c, s = math.cos(prop.yaw), math.sin(prop.yaw)
		local function h(lx: number): number
			return MapGen.heightAt(world.map, prop.x + lx * c, prop.z - lx * s)
		end
		local yA, yB = h(-33), h(33)
		return prop.x, (yA + yB) / 2 + 9.5 / 2 - 0.8, prop.z, prop.yaw, math.atan((yB - yA) / 66)
	end
	return prop.x, ArtPlan.footY(world, prop), prop.z, prop.yaw, 0
end

--- A small, fixed colour shift per plant, so a wood of the same few models
--- never reads as copies: a little lighter or darker, warmer or cooler.
function ArtPlan.tint(prop: World.Prop): (number, number, number)
	local k = 0.9 + 0.2 * Blueprints.hash(prop.x, prop.z, 919)
	local warm = (Blueprints.hash(prop.x, prop.z, 929) - 0.5) * 0.12
	return k * (1 + warm), k, k * (1 - warm)
end

return ArtPlan

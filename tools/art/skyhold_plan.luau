--!nonstrict
-- The island hub's plan for the Blender kit (T6/T7): Skyhold's rim, its ground
-- heights and every gameplay anchor, from the very modules the game runs
-- (Config/Skyhold, Core/SkyholdGen), so the cliffs Blender hangs from the rim
-- meet the Terrain the server writes.
--
--     lune run tools/art/skyhold_plan.luau [out.json]     (default work/skyhold/plan.json)
--
-- Coordinates are island-local Roblox studs (x east, z south, y up); the
-- Blender side turns them into its own (x, -z, y).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Skyhold = require("../../src/shared/Config/Skyhold")
local SkyholdGen = require("../../src/shared/Core/SkyholdGen")

local out = process.args[1] or "work/skyhold/plan.json"
local plan = SkyholdGen.build(Skyhold)

local function poly(points)
	local list = {}
	for _, p in points do
		local h = SkyholdGen.heightAt(plan, p.x * 0.995, p.z * 0.995)
		table.insert(list, { p.x, p.z, h or 0 })
	end
	return list
end

-- the ground on a 2-stud grid over both pieces of land (false: open sky)
local STEP = 2
local x0, x1, z0, z1 = -150, 196, -134, 178
local grid = {}
for iz = 0, (z1 - z0) // STEP do
	for ix = 0, (x1 - x0) // STEP do
		local h = SkyholdGen.heightAt(plan, x0 + ix * STEP, z0 + iz * STEP)
		table.insert(grid, if h then math.floor(h * 100 + 0.5) / 100 else false)
	end
end

local surfaces = {}
for iz = 0, (z1 - z0) // STEP do
	for ix = 0, (x1 - x0) // STEP do
		local x, z = x0 + ix * STEP, z0 + iz * STEP
		table.insert(surfaces, if SkyholdGen.land(plan, x, z) then SkyholdGen.surfaceAt(plan, x, z) else false)
	end
end

local data = {
	origin = Skyhold.Origin,
	outline = poly(plan.outline),
	islet = poly(plan.islet),
	grid = { x0 = x0, z0 = z0, step = STEP, nx = (x1 - x0) // STEP + 1, nz = (z1 - z0) // STEP + 1, h = grid, surface = surfaces },
	anchors = {
		spawn = Skyhold.Spawn,
		["return"] = Skyhold.Return,
		portal = Skyhold.Portal,
		portalRadius = Skyhold.PortalRadius,
		portalCentreHeight = Skyhold.PortalCentreHeight,
		plaza = Skyhold.PlazaCentre,
		circles = Skyhold.Circles,
		circleRadius = Skyhold.CircleRadius,
		plinths = Skyhold.Plinths,
		lookout = Skyhold.Lookout,
		tree = Skyhold.Tree,
		trophy = Skyhold.Trophy,
		bridge = Skyhold.Bridge,
		plateaus = Skyhold.Plateaus,
		paths = Skyhold.Paths,
		squad = Skyhold.SquadSize,
		isletHeight = Skyhold.IsletHeight,
	},
}

local dir = string.match(out, "^(.*)[/\\]")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(out, serde.encode("json", data, false))
print(`[skyhold_plan] {#data.outline} rim points, {#data.islet} islet points, {data.grid.nx}x{data.grid.nz} ground samples -> {out}`)

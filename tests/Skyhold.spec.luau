--!strict
-- Specs for T6/T7: Skyhold's ground (Core/SkyholdGen over Config/Skyhold). Every
-- place a player is sent to or stands at must be on the island and on ground a
-- hero can walk, and the ground must be continuous from the spawn to all of them.

local Skyhold = require("../src/shared/Config/Skyhold")
local SkyholdGen = require("../src/shared/Core/SkyholdGen")

local plan = SkyholdGen.build(Skyhold)

local function places()
	local list = {
		{ "spawn", Skyhold.Spawn.x, Skyhold.Spawn.z },
		{ "return", Skyhold.Return.x, Skyhold.Return.z },
		{ "portal", Skyhold.Portal.x, Skyhold.Portal.z },
		{ "lookout", Skyhold.Lookout.x, Skyhold.Lookout.z },
		{ "tree", Skyhold.Tree.x, Skyhold.Tree.z },
		{ "trophy", Skyhold.Trophy.x, Skyhold.Trophy.z },
	}
	for i, c in Skyhold.Circles do
		table.insert(list, { `circle {i}`, c.x, c.z })
	end
	for i, p in Skyhold.Plinths do
		table.insert(list, { `plinth {i}`, p.x, p.z })
	end
	return list
end

return {
	["every place is on the main island, well inside its rim"] = function()
		for _, p in places() do
			local name, x, z = p[1], p[2], p[3]
			assert(SkyholdGen.land(plan, x, z) == "main", `{name} is off the island`)
			assert(SkyholdGen.rimDistance(plan.outline, x, z) > 8, `{name} is too close to the edge`)
		end
	end,

	["the circles and the plaza are flat, the plinths level"] = function()
		local plaza = SkyholdGen.heightAt(plan, Skyhold.PlazaCentre.x, Skyhold.PlazaCentre.z)
		for i, c in Skyhold.Circles do
			for _, o in { { 0, 0 }, { 5, 0 }, { -5, 0 }, { 0, 5 }, { 0, -5 } } do
				local h = SkyholdGen.heightAt(plan, c.x + o[1], c.z + o[2])
				assert(h and plaza and math.abs(h - plaza) < 0.01, `circle {i} is not on the flat plaza`)
			end
		end
		for i, p in Skyhold.Plinths do
			local h = SkyholdGen.heightAt(plan, p.x, p.z)
			local h2 = SkyholdGen.heightAt(plan, p.x + 4, p.z)
			assert(h and h2 and math.abs(h - h2) < 0.01, `plinth {i} stands on a slope`)
		end
	end,

	["the circles do not overlap and leave room to walk between them"] = function()
		for i, a in Skyhold.Circles do
			for j, b in Skyhold.Circles do
				if i < j then
					local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
					assert(d >= Skyhold.CircleRadius * 2 + 4, `circles {i} and {j} are too close ({d})`)
				end
			end
		end
	end,

	["the ground is walkable: no step between neighbouring cells steeper than a hero climbs"] = function()
		-- the last stretch before the rim is under the rock lip and behind the
		-- edge wall: nobody walks it
		local band = Skyhold.RimWidth + 4
		local worst = 0
		for x = -150, 150, 4 do
			for z = -130, 130, 4 do
				local h = if SkyholdGen.rimDistance(plan.outline, x, z) > band
						and SkyholdGen.rimDistance(plan.outline, x + 4, z) > band
						and SkyholdGen.rimDistance(plan.outline, x, z + 4) > band
					then SkyholdGen.heightAt(plan, x, z)
					else nil
				local e = SkyholdGen.heightAt(plan, x + 4, z)
				local s = SkyholdGen.heightAt(plan, x, z + 4)
				if h and e then
					worst = math.max(worst, math.abs(h - e) / 4)
				end
				if h and s then
					worst = math.max(worst, math.abs(h - s) / 4)
				end
			end
		end
		assert(worst < 1.0, `a slope of {worst} is a wall, not a hill`)
	end,

	["every place can be walked to from the spawn"] = function()
		local cell = 4
		local function key(ix: number, iz: number): string
			return `{ix},{iz}`
		end
		local function ixOf(v: number): number
			return math.floor(v / cell + 0.5)
		end
		local seen = {}
		local queue = { { ixOf(Skyhold.Spawn.x), ixOf(Skyhold.Spawn.z) } }
		seen[key(queue[1][1], queue[1][2])] = true
		local head = 1
		while head <= #queue do
			local c = queue[head]
			head += 1
			local h = SkyholdGen.heightAt(plan, c[1] * cell, c[2] * cell)
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local nx, nz = c[1] + d[1], c[2] + d[2]
				local k = key(nx, nz)
				if not seen[k] then
					local nh = SkyholdGen.heightAt(plan, nx * cell, nz * cell)
					if h and nh and SkyholdGen.land(plan, nx * cell, nz * cell) == "main" and math.abs(nh - h) <= cell then
						seen[k] = true
						table.insert(queue, { nx, nz })
					end
				end
			end
		end
		for _, p in places() do
			assert(seen[key(ixOf(p[2]), ixOf(p[3]))], `{p[1]} cannot be reached from the spawn`)
		end
	end,

	["the islet is its own ground, off the main island"] = function()
		local cx, cz = 155, 140
		assert(SkyholdGen.land(plan, cx, cz) == "islet")
		local h = SkyholdGen.heightAt(plan, cx, cz)
		assert(h and math.abs(h - Skyhold.IsletHeight) < 1.5)
		assert(SkyholdGen.land(plan, 115, 110) == nil, "open sky between the island and the islet")
	end,

	["paths are paths and the meadow is turf"] = function()
		assert(SkyholdGen.surfaceAt(plan, 0, 60) == "Path")
		assert(SkyholdGen.surfaceAt(plan, -60, 60) == "Turf")
	end,

	["no grass grows through the paving"] = function()
		for _, p in { { 0, -40 }, { 30, -40 }, { 0, -88 }, { 6, 2 }, { -96, -18 }, { -120, 20 } } do
			assert(SkyholdGen.surfaceAt(plan, p[1], p[2]) == "Path", `grass under the paving at {p[1]}, {p[2]}`)
		end
		assert(SkyholdGen.surfaceAt(plan, 50, -40) == "Turf", "the meadow past the plaza is turf")
	end,
}

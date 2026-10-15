--!strict
-- Specs for the Wardwood (M3.A): the promises its layout makes to movement and
-- to the eye, checked on the real world the server builds.

local Blueprints = require("../src/shared/Core/Blueprints")
local GameConfig = require("../src/shared/Config/GameConfig")
local MapGen = require("../src/shared/Core/MapGen")
local World = require("../src/shared/Core/World")

local world = World.build(GameConfig)
local map = world.map
local F = MapGen.Features

-- every solid footprint: { x, z, r, kind }
local solids = {}
for _, p in world.props do
	if p.blocks then
		for _, b in p.blocks do
			table.insert(solids, { b[1], b[2], b[3], p.kind })
		end
	elseif p.radius > 0 then
		table.insert(solids, { p.x, p.z, p.radius, p.kind })
	end
end

return {
	["nothing solid stands on the chute, a path or ramp A"] = function()
		for _, s in solids do
			local dc = MapGen.alongPolyline(F.chute.points, s[1], s[2])
			assert(dc > F.chute.core + s[3], `{s[4]} at {s[1]}, {s[2]} stands in the chute`)
			assert(World.pathDistance(s[1], s[2]) > s[3], `{s[4]} at {s[1]}, {s[2]} stands on a path`)
			local onRampA = math.abs(s[1] + 95) < 14 + s[3] and s[2] > 70 and s[2] < 160
			assert(not onRampA, `{s[4]} at {s[1]}, {s[2]} stands on ramp A`)
		end
	end,

	["the chute is steep enough for a slide to gain speed, then runs out gently"] = function()
		-- a slide gains when along x SlideDownhillAccel / base beats the flat decay:
		-- over a grade of about 0.2 for this game's numbers
		local pts = F.chute.points
		local function heightAlong(s: number): number
			local walked = 0
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
				if walked + len >= s then
					local t = (s - walked) / len
					return MapGen.heightAt(map, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
				end
				walked += len
			end
			local last = pts[#pts]
			return MapGen.heightAt(map, last[1], last[2])
		end
		local _, _, total = MapGen.alongPolyline(pts, pts[1][1], pts[1][2])
		local steep = (heightAlong(10) - heightAlong(total * 0.4)) / (total * 0.4 - 10)
		assert(steep > 0.22, `the drop-in averages a grade of {steep}`)
		local drop = heightAlong(0) - heightAlong(total)
		assert(drop > 35, `the whole run drops only {drop} studs`)
		for s = 0, total - 8, 8 do
			assert(heightAlong(s + 8) <= heightAlong(s) + 0.5, `the chute climbs at {s} studs`)
		end
	end,

	["the Moonwell's water never floats above its shore"] = function()
		local pond = F.pond
		for k = 0, 35 do
			local a = k / 36 * math.pi * 2
			-- just outside the water disc the ground stands above the surface
			local r = pond.r + 3.5
			local h = MapGen.heightAt(map, pond.x + math.cos(a) * r, pond.z + math.sin(a) * r)
			assert(h > pond.level, `ground at {math.deg(a)} deg is {h}, under the water at {pond.level}`)
		end
		-- and inside it is shallow enough to wade, never to swim
		local floor = MapGen.heightAt(map, pond.x, pond.z)
		assert(pond.level - floor < 3.2, `the pond is {pond.level - floor} deep`)
	end,

	["the first view from spawn sees the Ward stone"] = function()
		local ward = World.Sites[2]
		local y0 = MapGen.heightAt(map, 0, -6) + 7
		local y1 = MapGen.heightAt(map, ward.x, ward.z) + 6
		assert(MapGen.sightClear(map, 0, y0, -6, ward.x, y1, ward.z), "the ground hides the Ward from the spawn")
	end,

	["every landmark is dressed"] = function()
		local kinds = {}
		for _, p in world.props do
			kinds[p.kind] = true
		end
		for _, k in
			{ "Ward", "Gate", "RuinTower", "ElderRoots", "MoonStone", "Cairn", "RuneStone", "Brazier", "Spruce", "Birch", "Flowers" }
		do
			assert(kinds[k], `no {k} in the world`)
		end
	end,

	["the scenery stays inside its part budget"] = function()
		local instances = 0
		for _, p in world.props do
			local parts = World.parts(world, p)
			instances += if parts then #parts else 1
		end
		assert(instances < 13000, `{instances} scenery instances`)
	end,

	["spruce grows where it is cool, oak and birch where it is warm"] = function()
		local warmSpruce, coolOak = 0, 0
		for _, p in world.props do
			if p.kind == "Spruce" and World.coolness(p.x, p.z) < 0.05 and math.abs(p.z - 165) > 40 then
				warmSpruce += 1 -- (the escarpment's lip is dressed with spruce on purpose)
			elseif (p.kind == "TreeTwin" or p.kind == "Birch") and World.coolness(p.x, p.z) > 0.97 then
				coolOak += 1
			end
		end
		assert(warmSpruce == 0, `{warmSpruce} spruce out in the warm meadows`)
		assert(coolOak == 0, `{coolOak} oaks and birches deep in the cold forest`)
	end,

	["every part-built kind builds, and every part has a sane size"] = function()
		for _, kind in
			{
				"Spruce",
				"SpruceFar",
				"Birch",
				"Menhir",
				"RuneStone",
				"MoonStone",
				"Pillar",
				"PillarBroken",
				"Brazier",
				"Ward",
				"Gate",
				"Cairn",
				"ElderRoots",
				"Fern",
				"Flowers",
				"Glowcaps",
			}
		do
			local bp = Blueprints.get(kind)
			assert(bp, `no blueprint for {kind}`)
			local parts = bp(7, function()
				return 0
			end)
			assert(#parts > 0, `{kind} has no parts`)
			for _, p in parts do
				for _, v in p.size do
					assert(v > 0.05 and v < 80, `{kind} has a part of size {v}`)
				end
			end
		end
	end,
}

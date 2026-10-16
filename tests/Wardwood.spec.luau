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

	["the falls run in front of the cliff all the way down, never through it"] = function()
		local fall
		for _, p in world.props do
			if p.kind == "Waterfall" then
				fall = p
			end
		end
		assert(fall, "no waterfall")
		local t, b = (fall :: any).top, (fall :: any).bottom
		assert(t[2] - b[2] > 30, "the falls should be a long drop")
		for k = 1, 19 do
			local f = k / 20
			local x, y, z = b[1] + (t[1] - b[1]) * f, b[2] + (t[2] - b[2]) * f, b[3] + (t[3] - b[3]) * f
			local ground = MapGen.heightAt(map, x, z)
			assert(y > ground + 0.5, `the water runs inside the rock {f * 100} % of the way up ({y} vs {ground})`)
		end
	end,

	["a horde can follow a hero to every landmark, the Sun Temple's summit too"] = function()
		local reach = MapGen.reachable(map, 0, 0, GameConfig.CliffSlope)
		for _, site in World.Sites do
			-- the site itself may be a pond or a dais: somewhere within a few studs is enough
			local found = false
			for dx = -12, 12, 4 do
				for dz = -12, 12, 4 do
					if MapGen.isReachable(map, reach, site.x + dx, site.z + dz) then
						found = true
					end
				end
			end
			assert(found, `{site.name} cannot be walked to`)
		end
		-- Sunspire from three sides, not one
		local ss = F.sunspire
		local sides = 0
		for _, a in { 0, 90, 180, 270 } do
			local r = math.rad(a)
			if MapGen.isReachable(map, reach, ss.x + math.cos(r) * 60, ss.z + math.sin(r) * 60) then
				sides += 1
			end
		end
		assert(sides >= 3, `Sunspire can be climbed from only {sides} sides`)
	end,

	["the barrier is a closed ring just outside the playable edge"] = function()
		local segs = world.barrier
		assert(#segs >= 120, "too few barrier segments")
		for i, seg in segs do
			local nextSeg = segs[i % #segs + 1]
			assert(seg[3] == nextSeg[1] and seg[4] == nextSeg[2], "the ring has a gap")
			local len = math.sqrt((seg[3] - seg[1]) ^ 2 + (seg[4] - seg[2]) ^ 2)
			assert(len < 30, `a segment {len} studs long`)
			local o = MapGen.outside(seg[1], seg[2])
			assert(o > 2 and o < 9, `a barrier post {o} studs from the edge`)
		end
	end,

	["the world is bigger, and the forest is never a wall"] = function()
		assert(map.size >= 1100, "the world did not grow")
		-- sample the playable world: deep forest (density over 0.7) stays a small share
		local deep, total = 0, 0
		for x = -440, 440, 10 do
			for z = -440, 440, 10 do
				if MapGen.outside(x, z) < -20 then
					total += 1
					if World.forest(x, z) > 0.7 then
						deep += 1
					end
				end
			end
		end
		assert(deep / total < 0.12, `{deep / total * 100} % of the world is deep forest`)
	end,

	["grass grows in drifts, and the fights' clearings are worn"] = function()
		local Wardwood = require("../src/shared/Config/Wardwood")
		local function grassShare(mode: string?, near: number?): number
			local grassy, total = 0, 0
			for x = -440, 440, 8 do
				for z = -440, 440, 8 do
					if MapGen.outside(x, z) < -8 and (not near or x * x + z * z < near * near) then
						total += 1
						local m = Wardwood.Surfaces[World.surface(world, x, z, mode)].material
						if m == "Grass" or m == "LeafyGrass" then
							grassy += 1
						end
					end
				end
			end
			return grassy / total
		end
		assert(Wardwood.Grass == "less")
		local less, full = grassShare("less"), grassShare("full")
		assert(full > 0.85 and less < 0.62 and less > 0.4, `grass {less} less, {full} full`)
		assert(grassShare("less", 60) < 0.4, "the spawn clearing is still a lawn")
	end,

	["every landmark is dressed"] = function()
		local kinds = {}
		for _, p in world.props do
			kinds[p.kind] = true
		end
		for _, k in
			{
				"Ward",
				"Gate",
				"RuinTower",
				"ElderRoots",
				"MoonStone",
				"Cairn",
				"RuneStone",
				"Brazier",
				"Spruce",
				"SpruceFar",
				"SpruceRidge",
				"Pine",
				"Beech",
				"Oak",
				"OakLeaning",
				"Sapling",
				"Birch",
				"Elder",
				"Flowers",
				"SunTemple",
				"FallenGiant",
				"AncientOak",
				"AncientPine",
			}
		do
			assert(kinds[k], `no {k} in the world`)
		end
	end,

	["the scenery stays inside its part budget"] = function()
		-- every Part counts, and so does the sphere mesh inside each ellipsoid
		local parts, meshes = 0, 0
		for _, p in world.props do
			local prims = World.parts(world, p)
			parts += if prims then #prims else 1
			for _, q in prims or {} do
				if q.shape == "ellipsoid" then
					meshes += 1
				end
			end
		end
		assert(parts < 15500, `{parts} scenery parts`)
		assert(parts + meshes < 17000, `{parts + meshes} scenery instances`)
	end,

	["no tree is a perch and no crown is solid"] = function()
		local trees = {
			Beech = true,
			Oak = true,
			OakLeaning = true,
			Sapling = true,
			Birch = true,
			Spruce = true,
			SpruceFar = true,
			Pine = true,
			AncientOak = true,
			AncientPine = true,
			Elder = true,
		}
		for _, p in world.props do
			if trees[p.kind] then
				local ground = MapGen.heightAt(map, p.x, p.z) + (p.lift or 0)
				local top, thick = -math.huge, 0
				for _, q in World.parts(world, p) :: any do
					if q.collide then
						assert(q.shape == "cylinder", `{p.kind} has a solid {q.shape}`)
						-- a cylinder's axis is its local x: the matrix's first column
						local up = math.abs(q.cf[7])
						local y = q.cf[2] + up * q.size[1] / 2 + math.sqrt(1 - up * up) * q.size[2] / 2 - ground
						if y > top then
							top, thick = y, q.size[2]
						end
					end
				end
				-- the trunk's top is out of a jump's reach, or too thin to stand on
				local perch = top < GameConfig.PlayerJumpHeight + 2 and thick > 1.4
				assert(not perch, `a {p.kind} at {p.x}, {p.z} has a solid top {top} studs up`)
			end
		end
	end,

	["spruce grows where it is cool, oak and birch where it is warm"] = function()
		local warmSpruce, coolOak = 0, 0
		for _, p in world.props do
			if p.kind == "Spruce" and World.coolness(p.x, p.z) < 0.05 and math.abs(p.z - 165) > 40 then
				warmSpruce += 1 -- (the escarpment's lip is dressed with spruce on purpose)
			elseif (p.kind == "Beech" or p.kind == "Oak" or p.kind == "Birch") and World.coolness(p.x, p.z) > 0.97 then
				coolOak += 1
			end
		end
		assert(warmSpruce == 0, `{warmSpruce} spruce out in the warm meadows`)
		assert(coolOak == 0, `{coolOak} oaks and birches deep in the cold forest`)
	end,

	["every part-built kind builds, and every part has a sane size"] = function()
		for _, kind in
			{
				"Paving",
				"AncientOak",
				"AncientPine",
				"FallenGiant",
				"SunTemple",
				"Spruce",
				"SpruceFar",
				"SpruceRidge",
				"Pine",
				"Beech",
				"Oak",
				"OakLeaning",
				"Sapling",
				"Birch",
				"Elder",
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
					assert(v > 0.05 and v < 120, `{kind} has a part of size {v}`)
				end
			end
		end
	end,
}

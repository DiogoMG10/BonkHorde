--!strict
-- Specs for the Skyhold kit (T6/T7, tools/art/skyhold.py): every packed mesh
-- decodes whole, with its vertex colours, inside EditableMesh's limits; every
-- placement names a real asset; and the pieces the game drives at runtime (a
-- circle's glow, slots and board, a plinth's banner, the portal and its
-- orbiting monoliths) are there, under the names the client looks for.

local ArtKit = require("../src/server/Wardwood/ArtKit")
local Layout = require("../src/server/Skyhold/Layout")
local Roster = require("../src/shared/Config/Roster")
local Skyhold = require("../src/shared/Config/Skyhold")
local SkyholdDecor = require("../src/shared/Config/SkyholdDecor")

local fs = require("@lune/fs")

local KIT = {}
for _, file in fs.readDir("src/server/Skyhold/Meshes") do
	local name = string.match(file, "^(.+)%.luau$")
	if name then
		KIT[name] = require(`../src/server/Skyhold/Meshes/{name}`) :: any
	end
end

local WARDWOOD = {}
for _, file in fs.readDir("src/server/Wardwood/ArtMeshes") do
	local name = string.match(file, "^(.+)%.luau$")
	if name then
		WARDWOOD[name] = true
	end
end

local function partNames(asset: string): { [string]: boolean }
	local out = {}
	for _, part in KIT[asset].parts do
		out[part.name] = true
	end
	return out
end

return {
	["every part decodes whole, coloured, inside EditableMesh's limits"] = function()
		local count = 0
		for name, data in KIT do
			for _, part in data.parts do
				assert(part.tris <= 20000, `{name}.{part.name}: {part.tris} triangles`)
				assert(part.verts < 60000, `{name}.{part.name}: {part.verts} vertices`)
				local mesh = ArtKit.decode(part)
				assert(#mesh.idx == part.tris * 3, `{name}.{part.name}: triangles lost`)
				for _, i in mesh.idx do
					assert(i >= 0 and i < part.verts, `{name}.{part.name}: a triangle points past the vertices`)
				end
				if part.vc then
					assert(mesh.col and #mesh.col == part.verts * 3, `{name}.{part.name}: colours missing`)
				end
			end
			count += 1
		end
		assert(count >= 30, `only {count} kit assets`)
	end,

	["every placement names a real asset"] = function()
		for _, entry in Layout do
			if entry.kit == "wardwood" then
				assert(WARDWOOD[entry.asset], `the Wardwood kit has no {entry.asset}`)
			else
				assert(KIT[entry.asset], `the Skyhold kit has no {entry.asset}`)
			end
			assert(#entry.cf == 6, `{entry.asset}: a placement is x, y, z and three angles`)
		end
		for _, entry in SkyholdDecor do
			assert(KIT[entry.asset], `the decor names {entry.asset}, which the kit lacks`)
		end
	end,

	["the pieces the game drives are there, by name"] = function()
		local named = {}
		for _, entry in Layout do
			if entry.name then
				named[entry.name] = entry.asset
			end
		end
		assert(named.Portal == "Portal", "no portal")
		for i in Skyhold.Circles do
			assert(named[`Circle{i}`] == "RuneCircle", `no rune circle {i}`)
		end
		for i in Roster.HeroOrder do
			assert(named[`Plinth{i}`] == "HeroPlinth", `no plinth for hero {i}`)
		end
		for k = 1, 8 do
			assert(named[`Orbit{k}`] == "RuneStone", `no orbiting monolith {k}`)
		end
		local circle = partNames("RuneCircle")
		assert(circle.Glow and circle.Board, "a circle needs its Glow and its Board")
		for k = 1, Skyhold.SquadSize do
			assert(circle[`Slot{k}`], `a circle needs Slot{k}`)
		end
		assert(partNames("HeroPlinth").Banner, "a plinth needs its Banner")
	end,

	["glowing and tinted parts are plain colours, the rest carry vertex colours"] = function()
		local runtime = { Glow = true, Banner = true, Glass = true, Embers = true }
		for name, data in KIT do
			for _, part in data.parts do
				if runtime[part.name] or string.match(part.name, "^Slot%d$") then
					assert(not part.vc, `{name}.{part.name} is coloured at runtime: no vertex colours`)
				end
			end
		end
	end,

	["the island's heaviest pieces stay within a sane budget"] = function()
		local total = 0
		for _, data in KIT do
			for _, part in data.parts do
				total += part.tris
			end
		end
		assert(total < 120000, `{total} triangles in the whole kit`)
	end,
}

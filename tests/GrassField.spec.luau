--!strict
-- Specs for the grass options: B (static chunks, Core/GrassField) covers its
-- ground evenly, meets its neighbours without seams and stays low; A ("native")
-- puts Roblox's bladed Grass on exactly the ground the short carpet covers.

local GameConfig = require("../src/shared/Config/GameConfig")
local GrassField = require("../src/shared/Core/GrassField")
local MapGen = require("../src/shared/Core/MapGen")
local Wardwood = require("../src/shared/Config/Wardwood")
local World = require("../src/shared/Core/World")

local world = World.build(GameConfig)
local T = Wardwood.GrassTest

-- every blade of a set of chunk meshes, as its foot (x, z) and its height above the ground
local function blades(meshes: { GrassField.Mesh }): { { number } }
	local out = {}
	for _, m in meshes do
		for t = 0, m.tris - 1, 2 do -- each blade is two triangles over the same three corners
			local a, c = m.idx[t * 3 + 1], m.idx[t * 3 + 3]
			local ax = m.pos[a * 3 + 1] + m.centre[1]
			local az = m.pos[a * 3 + 3] + m.centre[3]
			local bx = m.pos[(a + 1) * 3 + 1] + m.centre[1]
			local bz = m.pos[(a + 1) * 3 + 3] + m.centre[3]
			local x, z = (ax + bx) / 2, (az + bz) / 2
			local tipY = m.pos[c * 3 + 2] + m.centre[2]
			table.insert(out, { x, z, tipY - MapGen.heightAt(world.map, x, z) })
		end
	end
	return out
end

return {
	["static grass chunks meet without seams or overlaps"] = function()
		local x0, z0 = T.x, T.z
		local whole = blades(GrassField.chunk(world, x0, z0, 64, T.spacing, "short"))
		local parts = 0
		local seen = {}
		for _, o in { { 0, 0 }, { 32, 0 }, { 0, 32 }, { 32, 32 } } do
			for _, b in blades(GrassField.chunk(world, x0 + o[1], z0 + o[2], 32, T.spacing, "short")) do
				parts += 1
				assert(b[1] >= x0 + o[1] - T.spacing and b[1] <= x0 + o[1] + 32 + T.spacing, "a blade strayed from its chunk")
				local key = `{math.floor(b[1] * 1000)},{math.floor(b[2] * 1000)}`
				assert(not seen[key], "a blade grows in two chunks")
				seen[key] = true
			end
		end
		assert(parts == #whole, `four chunks hold {parts} blades, the same ground in one {#whole}`)
	end,

	["static grass covers the meadow evenly: no islands, no holes, no rows"] = function()
		local bs = blades(GrassField.chunk(world, T.x, T.z, 32, T.spacing, "short"))
		-- blades per 2x2-stud square, across the chunk
		local counts = {}
		for _, b in bs do
			local k = math.floor((b[1] - T.x) / 2) * 100 + math.floor((b[2] - T.z) / 2)
			counts[k] = (counts[k] or 0) + 1
		end
		local n, sum, sq, empty = 0, 0, 0, 0
		for i = 0, 15 do
			for j = 0, 15 do
				local c = counts[i * 100 + j] or 0
				n += 1
				sum += c
				sq += c * c
				if c == 0 then
					empty += 1
				end
			end
		end
		local mean = sum / n
		local cv = math.sqrt(sq / n - mean * mean) / mean
		-- the old streamed patches measured 0.61 here, with bare squares
		assert(cv < 0.15, `blades per 2x2 studs vary by {cv} of their mean`)
		assert(empty == 0, `{empty} bare squares in a grassy meadow`)
	end,

	["static grass stays low and inside Roblox's mesh limits"] = function()
		local meshes = GrassField.chunk(world, T.x, T.z, T.chunk, T.spacing, "short")
		local tris = 0
		for _, m in meshes do
			assert(m.tris <= 20000 and m.verts <= 60000, "a chunk mesh is over the EditableMesh limit")
			tris += m.tris
		end
		assert(tris <= 9000, `{tris} triangles in a {T.chunk}-stud chunk`)
		for _, b in blades(meshes) do
			assert(b[3] >= 0.19 and b[3] <= 0.51, `a blade stands {b[3]} studs tall`)
		end
	end,

	["native grass covers exactly the ground the short carpet covers"] = function()
		local native, carpet = 0, 0
		for x = -400, 400, 16 do
			for z = -400, 400, 16 do
				if MapGen.outside(x, z) < -8 then
					local short, nat = World.surface(world, x, z, "short"), World.surface(world, x, z, "native")
					if short == "Carpet" then
						carpet += 1
						assert(nat == "Turf", `{nat} where the carpet would be`)
					else
						assert(nat == short, `native changes {short} to {nat}`)
					end
					if nat == "Turf" then
						native += 1
					end
				end
			end
		end
		assert(native == carpet and carpet > 1000, `{native} native, {carpet} carpet`)
		assert(Wardwood.Surfaces.Turf.material == "Grass", "native grass is not Roblox's bladed Grass")
	end,
}

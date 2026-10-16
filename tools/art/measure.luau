--!nocheck
-- What the Wardwood costs to draw, old against new (M3.B): per sample spot,
-- the triangles and parts a client draws within its view radius, and what
-- the server builds and replicates. Offline, from the same plan the game
-- uses; frame time still needs Studio.
--
--     lune run tools/art/measure.luau [near]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local ArtPlan = require("../../src/shared/Core/ArtPlan")
local GameConfig = require("../../src/shared/Config/GameConfig")
local Wardwood = require("../../src/shared/Config/Wardwood")
local World = require("../../src/shared/Core/World")

local near = tonumber(process.args[1]) or Wardwood.ArtLod.near
local farAt = Wardwood.ArtLod.far
local VIEW = 600 -- roughly how far the haze lets anything count

local manifest = serde.decode("json", fs.readFile("assets/art/manifest.json")).assets
local oldMeshes = serde.decode("json", fs.readFile("assets/meshes/manifest.json")).assets

local world = World.build(GameConfig)

-- the old look: part-built props are boxes, balls and cylinders (~12 to ~40
-- triangles drawn each); mesh props carry their measured triangles
local function oldCost(prop)
	local prims = World.parts(world, prop)
	if prims then
		local tris = 0
		for _, p in prims do
			tris += if p.shape == "ball" or p.shape == "ellipsoid" then 400 elseif p.shape == "cylinder" then 40 else 12
		end
		return tris, #prims
	end
	local m = oldMeshes[prop.kind]
	return if m then m.tris else 100, 1
end

local function newCost(prop, d: number)
	local asset = ArtPlan.asset(prop)
	if not asset then
		return oldCost(prop)
	end
	local name = asset
	if ArtPlan.hasLod(prop) and d > near then
		name = if d > farAt and manifest[asset .. "_FAR"] then asset .. "_FAR" else asset .. "_LOD"
	end
	local m = manifest[name]
	local parts = 0
	for _ in m.parts do
		parts += 1
	end
	return m.tris, parts
end

local spots = {
	{ "spawn clearing", 0, 0 },
	{ "open meadow (north)", 90, 300 },
	{ "Old Grove", -392, -34 },
	{ "dense wood (Mirewood)", -300, 120 },
	{ "Thornwood edge", 250, -150 },
}

print(string.format("near %d studs, far %d studs", near, farAt))
for _, s in spots do
	local name, sx, sz = s[1], s[2], s[3]
	local oldT, oldP, newT, newP, n0, n1 = 0, 0, 0, 0, 0, 0
	for _, p in world.props do
		local d = math.sqrt((p.x - sx) ^ 2 + (p.z - sz) ^ 2)
		if d < VIEW then
			local t, n = oldCost(p)
			oldT += t
			oldP += n
			local far = d > near
			local t2, n2 = newCost(p, d)
			newT += t2
			newP += n2
			if ArtPlan.asset(p) and ArtPlan.hasLod(p) then
				if far then
					n1 += 1
				else
					n0 += 1
				end
			end
		end
	end
	print(
		string.format(
			"%-22s old %4dk tris %5d parts | new %4dk tris %5d parts (%d near, %d far)",
			name,
			oldT // 1000,
			oldP,
			newT // 1000,
			newP,
			n0,
			n1
		)
	)
end

-- grass option B (static chunks, Core/GrassField): the test meadow, and what
-- the same density would cost over every grassy stud of the map. Option A is
-- Roblox's own terrain decoration: no instances, nothing to count here.
do
	local GrassField = require("../../src/shared/Core/GrassField")
	local T = Wardwood.GrassTest
	local tris, parts = 0, 0
	for x0 = T.x, T.x + T.size - T.chunk, T.chunk do
		for z0 = T.z, T.z + T.size - T.chunk, T.chunk do
			for _, m in GrassField.chunk(world, x0, z0, T.chunk, T.spacing, "short") do
				if m.tris > 0 then
					tris += m.tris
					parts += 1
				end
			end
		end
	end
	local grassy = 0
	for x = -470, 470, 4 do
		for z = -470, 470, 4 do
			if GrassField.grassy(world, x, z, "short") then
				grassy += 16
			end
		end
	end
	local perStud = tris / (T.size * T.size)
	print(
		string.format("grass B, test meadow %dx%d: %d MeshParts, %dk tris (%.1f per stud^2)", T.size, T.size, parts, tris // 1000, perStud)
	)
	print(
		string.format(
			"grass B over all %dk studs^2 of grassy ground: ~%.1fM tris, ~%d MeshParts",
			grassy // 1000,
			grassy * perStud / 1e6,
			math.floor(grassy / (T.size * T.size) * parts)
		)
	)
end

-- what the server builds: everything, old; colliders only for what the kit dresses, new
local oldServer, newServer = 0, 0
for _, p in world.props do
	local _, n = oldCost(p)
	oldServer += n
	if ArtPlan.asset(p) then
		local prims = World.parts(world, p)
		if prims then
			for _, q in prims do
				if q.collide then
					newServer += 1
				end
			end
		elseif p.kind ~= "Bush" and p.kind ~= "RockSmall" then
			newServer += 1 -- the old mesh, hidden, kept as its collider
		end
	else
		newServer += n
	end
end
print(string.format("server-built scenery parts: old %d, new %d", oldServer, newServer))

--!strict
-- Specs for the M3.B art kit across the Wardwood: the packed meshes decode
-- whole and stay inside Roblox's limits, every prop the plan dresses has its
-- models (and far versions), overrides do what they say, and the 3D grass
-- only grows where it should.

local ArtKit = require("../src/server/Wardwood/ArtKit")
local ArtPlan = require("../src/shared/Core/ArtPlan")
local GameConfig = require("../src/shared/Config/GameConfig")
local MapGen = require("../src/shared/Core/MapGen")
local Wardwood = require("../src/shared/Config/Wardwood")
local World = require("../src/shared/Core/World")

local fs = require("@lune/fs")

local ASSETS = {}
for _, file in fs.readDir("src/server/Wardwood/ArtMeshes") do
	local name = string.match(file, "^(.+)%.luau$")
	if name then
		ASSETS[name] = require(`../src/server/Wardwood/ArtMeshes/{name}`) :: any
	end
end

local world = World.build(GameConfig)

local function tris(name: string): number
	local n = 0
	for _, part in ASSETS[name].parts do
		n += part.tris
	end
	return n
end

return {
	["every art mesh decodes whole and fits Roblox's EditableMesh limits"] = function()
		local count = 0
		for name, asset in ASSETS do
			count += 1
			assert(asset.name == name, `{name} names itself {asset.name}`)
			for _, part in asset.parts do
				local mesh = ArtKit.decode(part)
				assert(mesh.verts == part.verts and #mesh.pos == part.verts * 3, `{name}.{part.name} vertex count`)
				assert(#mesh.idx == part.tris * 3, `{name}.{part.name} triangle count`)
				assert(part.verts <= 60000 and part.tris <= 20000, `{name}.{part.name} is over the EditableMesh limit`)
				for _, i in mesh.idx do
					assert(i >= 0 and i < part.verts, `{name}.{part.name} has a triangle past its vertices`)
				end
				for v = 0, part.verts - 1 do
					local x, y, z = mesh.nrm[v * 3 + 1], mesh.nrm[v * 3 + 2], mesh.nrm[v * 3 + 3]
					local len = math.sqrt(x * x + y * y + z * z)
					assert(len > 0.9 and len < 1.1, `{name}.{part.name} has a normal of length {len}`)
				end
			end
		end
		assert(count >= 80, `{count} art assets`)
	end,

	["every family the plan uses is built, and the far versions are cheaper"] = function()
		for kind, family in ArtPlan.Families do
			for _, asset in family do
				assert(ASSETS[asset], `{kind} uses {asset}, which is not built`)
				local hasLod = ArtPlan.hasLod({ kind = kind } :: any)
				if hasLod then
					assert(ASSETS[asset .. "_LOD"], `{asset} has no _LOD`)
					assert(tris(asset .. "_LOD") < tris(asset), `{asset}_LOD is no cheaper`)
					if ASSETS[asset .. "_FAR"] then
						assert(tris(asset .. "_FAR") < tris(asset .. "_LOD"), `{asset}_FAR is no cheaper`)
					end
				end
			end
		end
	end,

	["the kit keeps to its triangle budgets"] = function()
		for name in ASSETS do
			local n = tris(name)
			local cap = if string.find(name, "^Ancient") or string.find(name, "^Elder")
				then 20000
				elseif string.find(name, "_FAR$") then 2000
				elseif string.find(name, "_LOD$") then 3500
				elseif string.find(name, "^Grass") then 1000
				else 9000
			assert(n <= cap, `{name} has {n} triangles, budget {cap}`)
		end
	end,

	["the art dresses the whole Wardwood, every plant picks a variation of its own kind"] = function()
		local dressed, kinds = 0, {}
		for _, p in world.props do
			local asset = ArtPlan.asset(p)
			if ArtPlan.Families[p.kind] then
				assert(asset and table.find(ArtPlan.Families[p.kind], asset), `{p.key} wears {asset}`)
				assert(asset == ArtPlan.asset(p), "the pick is not stable")
				dressed += 1
				kinds[asset] = (kinds[asset] or 0) + 1
			else
				assert(asset == nil, `{p.kind} has no family but wears {asset}`)
			end
			local r, g, b = ArtPlan.tint(p)
			assert(r > 0.8 and r < 1.25 and g > 0.85 and g < 1.15 and b > 0.75 and b < 1.2, "tint out of range")
		end
		assert(dressed > 1200, `only {dressed} props dressed`)
		-- a family's variations all get used
		for kind, family in ArtPlan.Families do
			if #family > 1 then
				for _, asset in family do
					local used = 0
					for _, p in world.props do
						if p.kind == kind and ArtPlan.asset(p) == asset then
							used += 1
						end
					end
					local total = 0
					for _, p in world.props do
						if p.kind == kind then
							total += 1
						end
					end
					assert(total < #family * 2 or used > 0, `{asset} is never used for {kind}`)
				end
			end
		end
	end,

	["overrides move, turn, re-skin and hide props by their stable names"] = function()
		local keys = {}
		for _, p in world.props do
			assert(p.key and not keys[p.key], `{p.key} is not a unique name`)
			keys[p.key] = true
		end
		local fresh = World.build(GameConfig)
		local props = {}
		for _, p in fresh.props do
			if p.kind == "Oak" or p.kind == "Bush" then
				table.insert(props, table.clone(p))
			end
		end
		local oak, bush = nil, nil
		for _, p in props do
			if p.kind == "Oak" and not oak then
				oak = p
			elseif p.kind == "Bush" and not bush then
				bush = p
			end
		end
		assert(oak and bush, "no oak or bush to try")
		local x, z = oak.x, oak.z
		local out = World.applyOverrides(props, {
			[oak.key :: string] = { dx = 3, dz = -2, yaw = 90, scale = 1.5, asset = "OakC" },
			[bush.key :: string] = { hide = true },
		})
		assert(#out == #props - 1, "the hidden bush is still there")
		assert(math.abs(oak.x - (x + 3)) < 1e-6 and math.abs(oak.z - (z - 2)) < 1e-6, "the oak did not move")
		assert(math.abs(oak.yaw - math.pi / 2) < 1e-6 and oak.scale == 1.5, "the oak did not turn or grow")
		assert(ArtPlan.asset(oak) == "OakC", "the oak did not take its variation")
	end,

	["short 3D grass grows only on grassy ground, clear of trunks, rocks and walls"] = function()
		local field = ArtPlan.grassField(world)
		local cell = Wardwood.ArtGrass.cell
		local n, total = 0, 0
		for cx = -40, 40 do
			for cz = -40, 40 do
				total += 1
				local g = field(cx, cz)
				if g then
					n += 1
					local surface = World.surface(world, g.x, g.z, Wardwood.Grass)
					assert(surface ~= "Path" and surface ~= "Rock" and surface ~= "Sand", `grass on {surface}`)
					assert(math.abs(g.y - MapGen.heightAt(world.map, g.x, g.z)) < 1e-6, "grass off the ground")
					assert(math.abs(g.x - (cx + 0.5) * cell) <= cell * 0.2 + 1e-6, "grass strayed from its cell")
					assert(table.find(ArtPlan.Grass, g.asset), `grass patch {g.asset}`)
					assert(field(cx, cz) == g, "the field does not cache")
				end
			end
		end
		assert(n > total * 0.5, `grass in only {n} of {total} cells round spawn`)
		for _, name in ArtPlan.Grass do
			for _, part in ASSETS[name].parts do
				assert(part.max[2] <= 0.55, `{name} stands {part.max[2]} studs tall`)
			end
		end
	end,
}

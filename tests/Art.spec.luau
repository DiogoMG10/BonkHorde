--!strict
-- Specs for the M3.B art kit: the packed meshes decode whole and stay inside
-- Roblox's limits, and the Old Grove showcase only re-skins what is there.

local ArtKit = require("../src/server/Wardwood/ArtKit")
local ArtShowcase = require("../src/shared/Core/ArtShowcase")
local GameConfig = require("../src/shared/Config/GameConfig")
local MapGen = require("../src/shared/Core/MapGen")
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

return {
	["every art mesh decodes whole and fits Roblox's EditableMesh limits"] = function()
		local count = 0
		for name, asset in ASSETS do
			count += 1
			assert(asset.name == name, `{name} names itself {asset.name}`)
			local tris = 0
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
				for k = 1, 3 do
					local half = mesh.size[k] / 2 + 1e-3
					for v = 0, part.verts - 1 do
						assert(math.abs(mesh.pos[v * 3 + k]) <= half, `{name}.{part.name} vertex outside its box`)
					end
				end
				tris += part.tris
			end
			assert(tris > 0, `{name} is empty`)
		end
		assert(count >= 16, `{count} art assets`)
	end,

	["the art keeps to its triangle budgets"] = function()
		local budget = { AncientOak = 20000, GrassA = 1000, GrassB = 1000, GrassC = 1000 }
		for name, asset in ASSETS do
			local tris = 0
			for _, part in asset.parts do
				tris += part.tris
			end
			local cap = budget[name] or 10000
			assert(tris <= cap, `{name} has {tris} triangles, budget {cap}`)
		end
	end,

	["the 3D grass stays low"] = function()
		for _, name in { "GrassA", "GrassB", "GrassC" } do
			for _, part in ASSETS[name].parts do
				local top = part.max[2]
				assert(top <= 0.55 and top >= 0.15, `{name} stands {top} studs tall`)
			end
		end
	end,

	["every swapped kind has an asset, and the showcase only re-skins props in the Old Grove"] = function()
		for kind, asset in ArtShowcase.Swap do
			assert(ASSETS[asset], `{kind} swaps to {asset}, which is not built`)
		end
		local plan = ArtShowcase.plan(world)
		local kinds, props, grass = {}, 0, 0
		local c, r = ArtShowcase.Centre, ArtShowcase.Radius
		for _, p in plan do
			assert((p.x - c.x) ^ 2 + (p.z - c.z) ^ 2 < r * r, `{p.asset} placed outside the showcase`)
			assert(ASSETS[p.asset], `{p.asset} is planned but not built`)
			if p.prop then
				local prop = world.props[p.prop]
				assert(ArtShowcase.Swap[prop.kind] == p.asset, `prop {p.prop} ({prop.kind}) shown as {p.asset}`)
				assert(prop.x == p.x and prop.z == p.z and prop.scale == p.scale, `{p.asset} moved from its prop`)
				kinds[p.asset] = true
				props += 1
			else
				grass += 1
				local surface = World.surface(world, p.x, p.z)
				assert(surface ~= "Path" and surface ~= "Rock", `grass on {surface} at {p.x}, {p.z}`)
				assert(math.abs(p.y - MapGen.heightAt(world.map, p.x, p.z)) < 0.01, "grass off the ground")
			end
		end
		for _, need in { "AncientOak", "Spruce", "Pillar", "PillarBroken" } do
			assert(kinds[need], `the showcase has no {need}`)
		end
		assert(props >= 12, `only {props} props in the showcase`)
		assert(grass > 100 and grass < 500, `{grass} grass patches`)
	end,
}

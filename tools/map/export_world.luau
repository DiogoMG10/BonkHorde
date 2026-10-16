--!nocheck
-- World exporter for offline previews. Builds the same map the server builds
-- (heights, terrain surfaces, every prop) and writes it as JSON for
-- tools/map/preview_blender.py, so the preview is drawn from the same tree as
-- the game and cannot disagree with it.
--
--     lune run tools/map/export_world.luau [out.json] [grass mode] [art]
--
-- The grass mode is Config/Wardwood.Grass unless given. With `art`, the M3.B
-- showcase is drawn as the game builds it (Core/ArtShowcase): the props it
-- re-skins are left out and the kit's meshes (server/Wardwood/ArtMeshes) go
-- in their place, once per mesh with an instance per placement.
--
-- Part-built props are exported as their exact primitives (Core/Blueprints);
-- mesh props as proxies with their measured bounds (assets/meshes/manifest.json).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local GameConfig = require("../../src/shared/Config/GameConfig")
local MapGen = require("../../src/shared/Core/MapGen")
local Wardwood = require("../../src/shared/Config/Wardwood")
local World = require("../../src/shared/Core/World")

local out = process.args[1] or "work/map/world.json"
local grass = process.args[2] or Wardwood.Grass
local withArt = process.args[3] == "art"
local c = GameConfig
local world = World.build(c)
local map = world.map

-- heights and surfaces on the height grid
local heights, surfaces = {}, {}
for iz = 0, map.n - 1 do
	local z = -map.half + iz * map.cell
	for ix = 0, map.n - 1 do
		local x = -map.half + ix * map.cell
		table.insert(heights, math.floor(map.heights[iz * map.n + ix + 1] * 100 + 0.5) / 100)
		table.insert(surfaces, World.surface(world, x, z, grass))
	end
end

local manifest = serde.decode("json", fs.readFile("assets/meshes/manifest.json")).assets
local props = {}
local counts = {}

-- the art showcase: which props it re-skins, and the kit's meshes
local art, swapped = nil, {}
if withArt then
	local ArtKit = require("../../src/server/Wardwood/ArtKit")
	local ArtShowcase = require("../../src/shared/Core/ArtShowcase")
	local meshes, instances = {}, {}
	for _, p in ArtShowcase.plan(world) do
		if p.prop then
			swapped[p.prop] = true
		end
		local asset = require(`../../src/server/Wardwood/ArtMeshes/{p.asset}`) :: any
		local parts = {}
		for _, part in asset.parts do
			local key = `{p.asset}.{part.name}`
			if not meshes[key] then
				local m = ArtKit.decode(part)
				local pos = table.create(#m.pos)
				for i = 0, m.verts - 1 do
					for k = 1, 3 do
						pos[i * 3 + k] = math.floor((m.pos[i * 3 + k] + m.centre[k]) * 1000 + 0.5) / 1000
					end
				end
				local nrm = table.create(#m.nrm)
				for i, v in m.nrm do
					nrm[i] = math.floor(v * 1000 + 0.5) / 1000
				end
				meshes[key] = { pos = pos, nrm = nrm, idx = m.idx, color = part.color }
			end
			table.insert(parts, key)
		end
		table.insert(instances, { parts = parts, x = p.x, y = p.y, z = p.z, yaw = p.yaw, scale = p.scale })
	end
	art = { meshes = meshes, instances = instances }
end

for i, prop in world.props do
	if swapped[i] then
		continue
	end
	counts[prop.kind] = (counts[prop.kind] or 0) + 1
	local ground = MapGen.heightAt(map, prop.x, prop.z)
	local entry = { kind = prop.kind, x = prop.x, z = prop.z, y = ground + (prop.lift or 0), yaw = prop.yaw, scale = prop.scale }
	local parts = World.parts(world, prop)
	if prop.kind == "Waterfall" then
		-- the preview draws the falling water as a thin pale slab from spring to pool
		local t, b = prop.top, prop.bottom
		local dy, dz = t[2] - b[2], t[3] - b[3]
		local len = math.sqrt(dy * dy + dz * dz)
		local uy, uz = dy / len, dz / len
		entry.parts = {
			{
				shape = "block",
				size = { 7, len, 0.6 },
				cf = { (t[1] + b[1]) / 2, (t[2] + b[2]) / 2, (t[3] + b[3]) / 2, 1, 0, 0, 0, uy, -uz, 0, uz, uy },
				color = { 230, 246, 246 },
				mat = "Water",
			},
		}
	elseif parts then
		entry.parts = parts
	else
		local m = manifest[prop.kind]
		entry.bounds = if m then m.bounds_studs else { 4, 4, 4 }
	end
	table.insert(props, entry)
end

local anchors = {}
for _, a in world.anchors do
	table.insert(anchors, { a.x, a.z })
end

fs.writeFile(
	out,
	serde.encode("json", {
		n = map.n,
		cell = map.cell,
		half = map.half,
		heights = heights,
		surfaces = surfaces,
		props = props,
		anchors = anchors,
		water = world.water,
		palette = Wardwood.Surfaces,
		paths = world.paths,
		sites = world.sites,
		art = art,
	})
)
local parts = 0
for _, p in props do
	parts += if p.parts then #p.parts else 1
end
print(`[export] {#props} props ({parts} instances), {#anchors} anchors -> {out}`)
local names = {}
for k in counts do
	table.insert(names, k)
end
table.sort(names)
for _, k in names do
	print(`  {k} {counts[k]}`)
end

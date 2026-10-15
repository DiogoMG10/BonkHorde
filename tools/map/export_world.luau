--!nocheck
-- World exporter for offline previews. Builds the same map the server builds
-- (heights, terrain surfaces, every prop) and writes it as JSON for
-- tools/map/preview_blender.py, so the preview is drawn from the same tree as
-- the game and cannot disagree with it.
--
--     lune run tools/map/export_world.luau [out.json]
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
		table.insert(surfaces, World.surface(world, x, z))
	end
end

local manifest = serde.decode("json", fs.readFile("assets/meshes/manifest.json")).assets
local props = {}
local counts = {}
for _, prop in world.props do
	counts[prop.kind] = (counts[prop.kind] or 0) + 1
	local ground = MapGen.heightAt(map, prop.x, prop.z)
	local entry = { kind = prop.kind, x = prop.x, z = prop.z, y = ground + (prop.lift or 0), yaw = prop.yaw, scale = prop.scale }
	local parts = World.parts(world, prop)
	if parts then
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

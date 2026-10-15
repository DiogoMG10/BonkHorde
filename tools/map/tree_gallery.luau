--!nocheck
-- Tree gallery for offline previews: every tree blueprint on flat meadow, a
-- small stand of each at the scales the forest uses, written in the same JSON
-- as export_world.luau, with a views file framing each stand.
--
--     lune run tools/map/tree_gallery.luau [out.json] [views.json]
--     "$BLENDER" -b -P tools/map/preview_blender.py -- work/map/trees.json out work/map/views_trees.json

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Wardwood = require("../../src/shared/Config/Wardwood")
local World = require("../../src/shared/Core/World")

local out = process.args[1] or "work/map/trees.json"
local viewsOut = process.args[2] or "work/map/views_trees.json"
local n, cell = 201, 4
local half = (n - 1) * cell / 2
local heights, surfaces = table.create(n * n, 0), table.create(n * n, "Meadow")
local map = { n = n, cell = cell, half = half, heights = heights }
local world = { map = map }

-- { name, kind, scales }: a stand of three of each, in a row of stands
local STANDS = {
	{ "beech", "Beech", { 1.7, 2.2, 2.8 } },
	{ "oak", "Oak", { 1.6, 2.0, 2.5 } },
	{ "oakleaning", "OakLeaning", { 1.5, 1.9, 2.4 } },
	{ "sapling", "Sapling", { 1.2, 1.5, 1.8 } },
	{ "birch", "Birch", { 0.9, 1.15, 1.5 } },
	{ "spruce", "Spruce", { 0.9, 1.15, 1.6 } },
	{ "sprucefar", "SpruceFar", { 1.0, 1.3, 1.7 } },
	{ "pine", "Pine", { 1.0, 1.25, 1.6 } },
	{ "ridge", "SpruceRidge", { 1.2, 1.5, 1.8 } },
}
local props, views = {}, {}
local function put(kind, x, z, scale, seed)
	local prop = { kind = kind, x = x, z = z, yaw = (seed * 1.3) % 6.28, scale = scale, radius = 0, seed = seed }
	table.insert(props, { kind = kind, x = x, z = z, y = 0, yaw = prop.yaw, scale = scale, parts = World.parts(world, prop) })
end
for i, stand in STANDS do
	local cx = -330 + ((i - 1) % 5) * 150
	local cz = if i <= 5 then -200 else 0
	for k, scale in stand[3] do
		local a = k * 2.2
		put(stand[2], cx + math.cos(a) * 16, cz + math.sin(a) * 16, scale, 1000 + i * 17 + k * 101)
	end
	-- framed from where a hero stands: a little way off, eye at head height
	table.insert(
		views,
		{ name = `{string.format("%02d", i)}_{stand[1]}`, eye = { cx - 18, 9, cz - 62 }, target = { cx, 13, cz }, fov = 70 }
	)
end
-- the ancients and the Elder
local big = {
	{ "ancientoak", "AncientOak", 1.1, 1104 },
	{ "ancientpine", "AncientPine", 1, 1107 },
	{ "elder", "Elder", 1.1, 41 },
}
for i, b in big do
	local cx, cz = -300 + (i - 1) * 260, 260
	put(b[2], cx, cz, b[3], b[4])
	if b[2] == "Elder" then
		put("ElderRoots", cx, cz, 1.25, 42)
	end
	table.insert(views, { name = `{10 + i}_{b[1]}`, eye = { cx - 30, 10, cz - 125 }, target = { cx, 42, cz }, fov = 70 })
end
-- the gameplay camera among a mixed stand
table.insert(views, { name = "20_game_beech", x = -330, z = -232, yaw = 180 })
table.insert(views, { name = "21_game_spruce", x = -180, z = -32, yaw = 180 })
table.insert(views, { name = "22_aerial", eye = { 0, 160, -420 }, target = { 0, 0, -60 }, fov = 70 })

fs.writeFile(
	out,
	serde.encode("json", {
		n = n,
		cell = cell,
		half = half,
		heights = heights,
		surfaces = surfaces,
		props = props,
		anchors = {},
		water = {},
		palette = Wardwood.Surfaces,
	})
)
fs.writeFile(viewsOut, serde.encode("json", views, true))
local parts = 0
for _, p in props do
	parts += #p.parts
end
print(`[gallery] {#props} trees, {parts} parts -> {out}, {#views} views -> {viewsOut}`)

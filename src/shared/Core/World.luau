--!strict
-- World - the Wardwood: the map and everything standing on it, from one call.
-- Pure and deterministic.
--
-- The server writes the terrain and builds the scenery from it, the enemy
-- simulation walks its heightfield, and tools/map/export_world.luau draws the
-- offline previews from it, so the three can never disagree.
--
-- Composition (north is +z; the lobby and the first gameplay camera look north):
--   Sunmeadow   the open basin round the spawn clearing (ringed by the paving
--               of an old ward circle), scattered oaks and birch
--   the Ward    a ruined rune platform north-west of spawn, the first landmark
--   the falls   a spring spilling down the Highwatch's face into a wading pool,
--               dead ahead of the first view
--   Highwatch   the plateau: the ruined tower on its knoll, behind the Runic Gate
--               at the top of ramp A
--   the Chute   the long half-pipe from the plateau's shoulder into the basin
--   Ridge Run   standing stones along the east spine above its long slide face
--   Elder Hill  the giant elder tree south-west of spawn, seen from everywhere
--   the Gardens curved terraces lined with ruined walls, one smooth ramp through
--   Mirewood    dense dark spruce round the Moonwell and its ring of teal stones
--   the rim     forest at the foot of a broken mountain skyline
-- Warm light (braziers, amber runes, lanterns) marks safety and the wards; the
-- one cool magic is the Moonwell's teal.

local Blueprints = require(script and script.Parent.Blueprints or "./Blueprints")
local MapGen = require(script and script.Parent.MapGen or "./MapGen")

local World = {}

export type Prop = {
	kind: string, -- a blueprint name, or a model in Assets.Props
	x: number,
	z: number,
	yaw: number, -- radians
	scale: number,
	radius: number, -- what enemies walk round (0: walked through)
	seed: number,
	blocks: { { number } }?, -- several solid footprints { x, z, r } instead of one
	lift: number?, -- raise (or sink) from the ground
	collider: number?, -- a mesh tree: an invisible trunk of this radius is its only solid part
}

export type World = {
	map: MapGen.Map,
	anchors: { MapGen.Anchor },
	props: { Prop },
	water: { any },
	paths: { any },
	sites: { any },
	barrier: { { number } }, -- segments { x1, z1, x2, z2 } of the invisible wall at the mountains' foot
}

--- The invisible wall round the playable world: a closed ring of segments a
--- few studs past the edge, where the mountains have only just begun to rise.
function World.barrier(): { { number } }
	local points = {}
	local count = 180
	for k = 0, count - 1 do
		local a = k / count * math.pi * 2
		local c, s = math.cos(a), math.sin(a)
		-- walk out along the ray to where the edge is 5 studs behind
		local lo, hi = 100, 900
		for _ = 1, 30 do
			local mid = (lo + hi) / 2
			if MapGen.outside(c * mid, s * mid) < 5 then
				lo = mid
			else
				hi = mid
			end
		end
		table.insert(points, { c * lo, s * lo })
	end
	local segments = {}
	for k = 1, count do
		local a, b = points[k], points[k % count + 1]
		table.insert(segments, { a[1], a[2], b[1], b[2] })
	end
	return segments
end

local F = MapGen.Features

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local hash = Blueprints.hash

-- ------------------------------------------------------------------ the layout

-- Landmarks: where they stand and how much open ground they keep round them.
World.Sites = {
	{ name = "Spawn", x = 0, z = 0, clear = 52 },
	{ name = "Ward", x = -34, z = 72, clear = 26 },
	{ name = "Elder", x = F.elderHill.x, z = F.elderHill.z, clear = 22 },
	{ name = "Highwatch", x = F.watchKnoll.x, z = F.watchKnoll.z, clear = 30 },
	{ name = "Gate", x = -95, z = 166, clear = 16 },
	{ name = "ChuteTop", x = 204, z = 252, clear = 14 },
	{ name = "Moonwell", x = F.pond.x, z = F.pond.z, clear = 40 },
	{ name = "GardenTop", x = F.gardenRampX, z = -306, clear = 14 },
	{ name = "Falls", x = F.falls.x, z = F.falls.z, clear = 20 },
	-- the wider world
	{ name = "SunTemple", x = F.sunspire.x, z = F.sunspire.z, clear = 34 },
	{ name = "OldGrove", x = -392, z = -34, clear = 22 },
	{ name = "FallenGiant", x = 318, z = -276, clear = 24 },
	{ name = "Stoneglen", x = F.glen.x, z = F.glen.z, clear = 40 },
	{ name = "Windhill", x = 330, z = 340, clear = 22 },
	{ name = "NorthVale", x = -56, z = 404, clear = 26 },
}

-- Paths: dirt tracks between the landmarks, kept clear of trunks and rocks.
World.Paths = {
	-- round the Ward's east side (seen, not walked through), up ramp A, under the Gate
	{
		name = "to the Highwatch",
		half = 3.2,
		points = {
			{ 0, 0 },
			{ -4, 34 },
			{ -6, 64 },
			{ -12, 100 },
			{ -58, 112 },
			{ -95, 116 },
			{ -95, 150 },
			{ -95, 176 },
			{ -62, 214 },
			{ -20, 200 },
			{ 38, 194 },
			{ 38, 214 }, -- between the two columns, up to the Highwatch's arch
		},
	},
	{ name = "to the Chute", half = 2.8, points = { { 0, 0 }, { 48, 14 }, { 112, 30 } } },
	{ name = "to the Ridge", half = 2.8, points = { { 0, 0 }, { 66, -22 }, { 138, -38 }, { 196, -30 } } },
	{ name = "to the Elder", half = 3, points = { { 0, 0 }, { -44, -42 }, { -92, -82 } } },
	{ name = "to the Gardens", half = 3.2, points = { { -100, -104 }, { -72, -130 }, { -58, -176 }, { -58, -300 } } },
	{ name = "to the Moonwell", half = 2.8, points = { { 0, 0 }, { -58, 10 }, { -128, 20 }, { -190, 28 } } },
	{ name = "to Sunspire", half = 3.4, points = { { 196, -30 }, { 238, -14 }, { 296, 2 }, { 336, 14 }, { 352, 20 } } },
	{ name = "to the North Vale", half = 3.2, points = { { -95, 176 }, { -76, 262 }, { -56, 330 }, { -50, 380 } } },
	{ name = "to Windhill", half = 3, points = { { 226, 252 }, { 252, 298 }, { 300, 330 }, { 316, 336 } } },
	{ name = "to the Old Grove", half = 3, points = { { -190, 28 }, { -196, -16 }, { -250, -32 }, { -326, -34 }, { -368, -34 } } },
	{ name = "to Stoneglen", half = 3.2, points = { { -72, -296 }, { -110, -334 }, { -186, -354 }, { -250, -366 } } },
	{
		name = "to the Fallen Giant",
		half = 3,
		points = { { 138, -38 }, { 168, -110 }, { 194, -170 }, { 228, -206 }, { 266, -228 }, { 294, -250 } },
	},
}

-- Groves of broadleaf and birch out in the meadows (the rest of the forest is
-- spruce, in the cool bands). { x, z, radius, density, birch share }
local GROVES = {
	{ 96, -72, 34, 0.75, 0.6 },
	{ 64, 118, 22, 0.6, 0.3 },
	{ -176, -168, 34, 0.7, 0.4 },
	{ 34, -150, 24, 0.55, 0.7 },
	{ -30, 196, 30, 0.6, 0.3 },
	{ 132, -258, 34, 0.7, 0.3 },
	{ 192, -122, 30, 0.6, 0.5 },
	{ -196, -64, 30, 0.65, 0.7 },
	{ 120, 214, 26, 0.6, 0.2 },
	{ 156, 70, 18, 0.5, 0.6 },
	-- the wider world: groves on the slopes and in the vales
	{ -150, 400, 40, 0.6, 0.6 },
	{ 40, 430, 36, 0.55, 0.7 },
	{ 230, 400, 34, 0.6, 0.3 },
	{ 290, 110, 40, 0.55, 0.3 },
	{ 300, -80, 34, 0.55, 0.5 },
	{ 420, 120, 34, 0.6, 0.3 },
	{ 120, -380, 44, 0.6, 0.6 },
	{ -60, -420, 36, 0.55, 0.7 },
	{ -390, -230, 40, 0.5, 0.4 },
	{ -430, 70, 36, 0.45, 0.3 },
	{ 380, -260, 36, 0.55, 0.3 },
}

-- Lone great oaks: the meadow's silhouettes. { x, z, scale, kind }; an oak is
-- wider than it is tall, so these are scaled a little under the old meshes
local OAKS = {
	{ 72, 56, 2.5, "Oak" },
	{ -64, -6, 2.2, "OakLeaning" },
	{ 128, -118, 2.6, "Oak" },
	{ -150, 96, 2.4, "OakLeaning" },
	{ 38, -92, 2.2, "OakLeaning" },
	{ 170, 6, 2.4, "Oak" },
	{ -24, 128, 2.1, "Oak" },
	{ -150, -118, 2.3, "Oak" },
	{ 100, 168, 2.3, "OakLeaning" },
	{ -84, 238, 2.4, "Oak" },
	{ 256, 64, 2.6, "OakLeaning" },
	{ 330, -40, 2.7, "Oak" },
	{ -40, 362, 2.5, "Oak" },
	{ 110, 330, 2.6, "OakLeaning" },
	{ -240, -300, 2.6, "Oak" },
	{ 70, -330, 2.4, "OakLeaning" },
	{ 200, -350, 2.7, "Oak" },
	{ -360, 230, 2.5, "OakLeaning" },
}

-- The ancients: a handful of enormous trees, each the mark of its region.
-- { x, z, kind, scale }
local ANCIENTS = {
	{ -420, 46, "AncientOak", 1.05 }, -- the Old Grove
	{ -348, -96, "AncientOak", 0.95 },
	{ -436, -130, "AncientOak", 1.1 },
	{ -398, -34, "AncientOak", 1.2 }, -- over the grove's shrine
	{ 318, 86, "AncientOak", 1 }, -- framing Sunspire from below
	{ 432, -44, "AncientOak", 0.9 },
	{ 352, 372, "AncientPine", 1 }, -- Windhill
	{ -318, 352, "AncientPine", 1.05 }, -- Thornwood
	{ -252, 420, "AncientPine", 0.9 },
	{ -252, -414, "AncientOak", 1 }, -- above Stoneglen
	{ 74, 404, "AncientOak", 0.9 }, -- the North Vale
	{ 176, -262, "AncientPine", 0.85 }, -- by the gully
}

-- Rock outcrops: a big boulder, a couple of smaller ones, loose stones.
local OUTCROPS = {
	{ 118, -14 },
	{ -86, -150 },
	{ 52, 88 },
	{ -170, 132 },
	{ 214, -64 },
	{ 176, 164 },
	{ -14, -212 },
	{ 104, -186 },
	{ -228, -100 },
	{ -268, 110 },
	{ 74, 296 },
	{ -150, 286 },
	{ 262, -200 },
	{ 230, 120 },
	{ -60, 300 },
	{ 156, -318 },
	{ -126, -282 },
	{ -30, 62 },
	{ 150, 110 },
	{ -200, 210 },
	{ 280, 180 },
	{ -300, 140 },
	{ 410, -90 },
	{ 240, -320 },
	{ -120, -440 },
	{ 20, 440 },
	{ -440, -40 },
	{ 400, 260 },
	{ -360, 410 },
	{ 330, -370 },
}

-- Small ruins found out in the open: { x, z, yaw }
local RUINS = {
	{ 150, -64, 20 },
	{ -22, -164, -10 },
	{ 88, -232, 35 },
	{ -164, -246, 0 },
	{ -186, 196, 60 },
	{ 132, 196, -30 },
	{ -268, -118, 15 },
	{ 18, 302, 0 },
	{ 250, 250, 40 },
	{ -260, 280, -20 },
	{ 200, -420, 10 },
	{ -420, -300, 30 },
	{ 420, 200, -15 },
	{ 120, 440, 0 },
}

-- ------------------------------------------------------------------ fields

-- broad, smooth value noise in [0, 1]
local function noise(x: number, z: number): number
	return 0.5
		+ 0.24 * math.sin(x * 0.031 + 1.7) * math.cos(z * 0.027 - 0.6)
		+ 0.16 * math.sin(x * 0.071 - z * 0.053 + 0.9)
		+ 0.1 * math.sin((x + 2 * z) * 0.113 + 2.3)
end
World.noise = noise

local function distToSegment(px: number, pz: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((px - a[1]) * dx + (pz - a[2]) * dz) / len2, 0, 1) else 0
	return math.sqrt((px - a[1] - t * dx) ^ 2 + (pz - a[2] - t * dz) ^ 2)
end

--- Distance to the nearest path's edge (negative inside a path).
function World.pathDistance(x: number, z: number): number
	local best = math.huge
	for _, path in World.Paths do
		local pts = path.points
		for i = 1, #pts - 1 do
			best = math.min(best, distToSegment(x, z, pts[i], pts[i + 1]) - path.half)
		end
	end
	return best
end

local function chuteDistance(x: number, z: number): number
	return (MapGen.alongPolyline(F.chute.points, x, z))
end

-- 1 where the ground must stay open: the spawn clearing, round landmarks, on
-- paths, the chute's running surface, the two ramps, the pond and its shore.
local function openness(x: number, z: number): number
	local keep = 1
	keep = math.min(keep, smooth((math.sqrt(x * x + z * z) - 56) / 26))
	for _, site in World.Sites do
		if site.name ~= "Spawn" then
			local d = math.sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2)
			keep = math.min(keep, smooth((d - site.clear) / 12))
		end
	end
	keep = math.min(keep, smooth((World.pathDistance(x, z) - 2) / 5))
	keep = math.min(keep, smooth((chuteDistance(x, z) - F.chute.core - 4) / 6))
	keep = math.min(keep, smooth(((MapGen.alongPolyline(F.gully.points, x, z)) - F.gully.core - 3) / 6))
	if z > 56 and z < 182 then
		keep = math.min(keep, smooth((math.abs(x + 95) - 24) / 6))
		keep = math.min(keep, smooth((math.abs(x - 115 - 10 * math.sin(z * 0.03)) - 24) / 6))
	end
	return keep
end

-- Mirewood's extent, 0..1: a ragged blob round the dell and the Moonwell, its
-- edge wandering with the noise, never a straight band
local function mirewood(x: number, z: number): number
	local d = math.sqrt((x + 228) ^ 2 + (z - 18) ^ 2)
	local reach = 118 + 34 * (noise(x * 0.6 + 50, z * 0.6 - 20) - 0.5) * 2
	return smooth((reach - d) / 36)
end

-- How much colder (spruce) than warmer (oak, birch) the forest is here, 0..1.
local function coolness(x: number, z: number): number
	local out = MapGen.outside(x, z)
	local c = 0
	c = math.max(c, mirewood(x, z)) -- Mirewood
	c = math.max(c, smooth((-110 - x) / 40) * smooth((z - 160) / 30) * smooth((330 - z) / 40)) -- the plateau's west woods
	c = math.max(c, smooth((-150 - x) / 80) * smooth((z - 210) / 60)) -- Thornwood, north-west
	c = math.max(c, smooth(1 - math.sqrt((x - 330) ^ 2 + (z - 340) ^ 2) / 130) * 0.85) -- Windhill
	c = math.max(c, smooth((out + 70) / 50) * 0.85) -- the foothills, and the mountains beyond
	return c
end
World.coolness = coolness

-- dense patches where the noise runs high, open glades between them
local function patches(x: number, z: number): number
	return smooth((noise(x * 1.4 + 31, z * 1.4 - 17) - 0.5) / 0.14)
end

-- Winding lanes through the woods, 0 in a lane and 1 away from one: where
-- either of two slow, smooth fields crosses its middle. The two cross each
-- other, so the lanes form a sparse network about 12 studs wide that wanders
-- like a deer trail, not a road.
local function lanes(x: number, z: number): number
	local a = 0.5 + 0.3 * math.sin(x * 0.021 + 1.3) * math.cos(z * 0.017 - 0.4) + 0.2 * math.sin((x - z) * 0.013 + 2.1)
	local b = 0.5 + 0.3 * math.sin(z * 0.02 - 2.2) * math.cos(x * 0.016 + 0.9) + 0.2 * math.sin((x + z) * 0.012 - 1.7)
	local d = math.min(math.abs(a - 0.5), math.abs(b - 0.5))
	return smooth((d - 0.03) / 0.03)
end

-- Glades, 0 inside one and 1 clear of them: a clearing in most cells of a
-- jittered 96-stud lattice, 24 to 48 studs across, room to turn and fight in.
local GLADE = 96
local function glades(x: number, z: number): number
	local keep = 1
	local cx, cz = math.floor(x / GLADE), math.floor(z / GLADE)
	for ix = cx - 1, cx + 1 do
		for iz = cz - 1, cz + 1 do
			if hash(ix, iz, 401) < 0.6 then
				local gx = (ix + 0.2 + hash(ix, iz, 403) * 0.6) * GLADE
				local gz = (iz + 0.2 + hash(ix, iz, 407) * 0.6) * GLADE
				local r = 12 + 12 * hash(ix, iz, 409)
				local d = math.sqrt((x - gx) ^ 2 + (z - gz) ^ 2)
				keep = math.min(keep, smooth((d - r) / 10))
			end
		end
	end
	return keep
end

--- Forest density, 0 (open meadow) to 1 (deep forest). Dense forest is kept
--- to chosen places, Mirewood and Thornwood's patches; the rest of the world
--- is meadow, groves and open woodland, broken by lanes and glades, so a hero
--- can always see and move.
function World.forest(x: number, z: number): number
	local n = noise(x, z)
	local out = MapGen.outside(x, z)
	local f = 0.1 * n -- the meadows: a tree here and there
	-- Mirewood: dark and close, broken by glades
	f = math.max(f, mirewood(x, z) * (0.4 + 0.45 * patches(x, z)) * (0.75 + 0.3 * n))
	-- the plateau's west woods: stands of spruce along its bank, not a block
	local westWoods = smooth((-112 - x) / 36) * smooth((z - 172) / 30) * smooth((330 - z) / 40)
	f = math.max(f, westWoods * (0.2 + 0.5 * patches(x, z)))
	-- the wider world: open woodland in drifts between the meadows
	local wider = smooth((math.sqrt(x * x + z * z) - 290) / 90)
	f = math.max(f, wider * (0.06 + 0.42 * smooth((noise(x * 0.8 - 40, z * 0.8 + 70) - 0.48) / 0.18)))
	-- Thornwood: dense stands round clearings
	local thorn = smooth((-150 - x) / 80) * smooth((z - 220) / 50)
	f = math.max(f, thorn * (0.2 + 0.6 * patches(x, z)))
	-- the Old Grove: open woodland under the ancients
	f = math.max(f, smooth((-316 - x) / 30) * (0.16 + 0.1 * n))
	-- the foothills: a loose fringe of forest at the mountains' feet, never a wall
	f = math.max(f, smooth((out + 60) / 40) * (0.3 + 0.25 * patches(x, z)))
	for _, g in GROVES do
		local d = math.sqrt((x - g[1]) ^ 2 + (z - g[2]) ^ 2)
		f = math.max(f, g[4] * smooth(1 - d / g[3]) * (0.75 + 0.5 * n))
	end
	-- lanes and glades open the woodland, never the meadows' lone trees
	if f > 0.15 then
		f = 0.15 + (f - 0.15) * (0.12 + 0.88 * lanes(x, z) * glades(x, z))
	end
	return math.clamp(f, 0, 1) * openness(x, z)
end

-- ------------------------------------------------------------------ surfaces

-- Ground patches 20 to 40 studs across, in [0, 1]: three samples of the
-- broad noise, turned 60 degrees apart, so no direction wins and the patches
-- read as rounded drifts (one sample alone lays them out in diagonal stripes)
local function patchNoise(x: number, z: number): number
	local acc = 0
	for k = 0, 2 do
		local a = k * math.pi / 3 + 0.4
		local c, s = math.cos(a), math.sin(a)
		acc += noise((x * c + z * s) * 2.2 + 71 * k, (z * c - x * s) * 2.2 - 43 * k)
	end
	return math.clamp(0.5 + (acc / 3 - 0.5) * 1.7, 0, 1)
end

-- How worn the ground is where fights gather, 0..1: the spawn clearing and
-- the landmarks' clearings, trampled to earth and moss in their middles.
local function wear(x: number, z: number): number
	local w = smooth((72 - math.sqrt(x * x + z * z)) / 30)
	for _, site in World.Sites do
		if site.name ~= "Spawn" then
			local d = math.sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2)
			w = math.max(w, smooth((site.clear + 8 - d) / 16))
		end
	end
	return w
end

--- The terrain surface at a point, as a material key (MapService maps keys to
--- Roblox materials and colours; the preview to swatches).
---
--- `grass` "less" (Config/Wardwood.Grass, the default) keeps grass, which
--- Roblox grows blades on, to drifts: mossy hollows and worn earth between
--- them in the meadows, a moss-and-litter floor under the trees with leafy
--- tufts in patches, and the clearings where fights gather mostly trampled.
--- "full" is the earlier all-grass look, for comparison (`grass full` in BonkDev).
function World.surface(world: World, x: number, z: number, grass: string?): string
	local map = world.map
	local h = MapGen.heightAt(map, x, z)
	local slope = MapGen.slopeAt(map, x, z)
	local n = noise(x * 1.7, z * 1.7)
	for _, pond in { F.pond, F.falls } do
		local dp = math.sqrt((x - pond.x) ^ 2 + (z - pond.z) ^ 2)
		if dp < pond.r + 4 then
			return if dp > pond.r - 5 then "Sand" else "Mud"
		end
	end
	-- the mountains: alpine grass low down, rock and slate above, snow on the tops
	local out = MapGen.outside(x, z)
	if out > 2 then
		if h > 185 and slope < 1.1 then
			return "Snow"
		elseif slope > 1.0 then
			return if n > 0.5 then "Slate" else "Rock"
		elseif h > 120 then
			return if n > 0.45 then "Rock" else "Slate"
		end
		return if n > 0.42 then "Lush" else "Rock"
	end
	if slope > 1.25 then
		return "Rock"
	end
	-- paths: worn earth with a ragged edge, fading out inside the spawn clearing
	local edge = World.pathDistance(x, z) + (n - 0.5) * 2.4
	local fromSpawn = math.sqrt(x * x + z * z)
	if fromSpawn > 30 and edge < 0 then
		return "Path"
	end
	if chuteDistance(x, z) < 2.2 then
		return "Path" -- a worn line down the middle of the chute
	end
	if slope > 0.82 then
		-- a weathered face: bare stone, moss clinging in patches, a little earth
		return if n > 0.58 then "Lush" elseif n > 0.3 then "Rock" else "Ground"
	end
	local f = World.forest(x, z)
	local cool = coolness(x, z)
	if grass == "full" then
		if f > 0.5 and cool > 0.5 then
			return "ForestFloor"
		elseif f > 0.32 or (cool > 0.6 and n > 0.35) then
			return "Lush"
		end
		return "Meadow"
	end
	local fine = patchNoise(x, z)
	if f > 0.5 and cool > 0.5 then
		return "ForestFloor"
	elseif f > 0.38 then
		return if fine > 0.64 then "Lush" else "ForestFloor"
	elseif f > 0.25 or (cool > 0.6 and n > 0.35) then
		return if fine > 0.5 then "Lush" elseif fine > 0.36 then "Meadow" else "ForestFloor"
	end
	local bare = fine - 0.3 * wear(x, z)
	if bare < 0.24 then
		return "Ground"
	elseif bare < 0.44 then
		return "ForestFloor"
	end
	return "Meadow"
end

-- ------------------------------------------------------------------ placing things

-- a coarse bucket grid over solid footprints, so spacing tests stay cheap
local Solids = {}
Solids.__index = Solids

local function newSolids()
	return setmetatable({ cells = {}, size = 24 }, Solids)
end

function Solids:key(x: number, z: number): number
	return math.floor(x / self.size) * 4096 + math.floor(z / self.size)
end

function Solids:add(x: number, z: number, r: number)
	local k = self:key(x, z)
	local list = self.cells[k]
	if not list then
		list = {}
		self.cells[k] = list
	end
	table.insert(list, { x, z, r })
end

function Solids:clear(x: number, z: number, r: number, gap: number): boolean
	local s = self.size
	local cx, cz = math.floor(x / s), math.floor(z / s)
	for ix = cx - 1, cx + 1 do
		for iz = cz - 1, cz + 1 do
			local list = self.cells[ix * 4096 + iz]
			if list then
				for _, o in list do
					local need = o[3] + r + gap
					if (o[1] - x) ^ 2 + (o[2] - z) ^ 2 < need * need then
						return false
					end
				end
			end
		end
	end
	return true
end

local GAP = 7 -- the walkable gap kept between any two solids, as MapGen always kept

--- Interactable anchors: the open, gentle ground. Deep forest, landmarks, the
--- pond and the paths themselves are left to the scenery.
function World.anchors(map: MapGen.Map): { MapGen.Anchor }
	local out = {}
	for _, a in MapGen.anchors(map, 26, 0.35) do
		local open = World.forest(a.x, a.z) < 0.42
		local onPath = World.pathDistance(a.x, a.z) < 3
		local site = false
		for _, s in World.Sites do
			if s.name ~= "Spawn" and (a.x - s.x) ^ 2 + (a.z - s.z) ^ 2 < (s.clear - 4) ^ 2 then
				site = true
				break
			end
		end
		local inChute = chuteDistance(a.x, a.z) < F.chute.core + 3
		if open and not onPath and not site and not inChute then
			table.insert(out, a)
		end
	end
	return out
end

-- The shared state of one build: what has been placed so far and the rules
-- for placing more.
local function newContext(map: MapGen.Map, anchors: { MapGen.Anchor })
	local ctx = { map = map, anchors = anchors, props = {} :: { Prop }, solids = newSolids(), limit = map.half - 8 }

	function ctx.nearAnchor(x: number, z: number, r: number): boolean
		for _, a in anchors do
			local need = 9 + r
			if (a.x - x) ^ 2 + (a.z - z) ^ 2 < need * need then
				return true
			end
		end
		return false
	end

	function ctx.add(p: Prop): Prop
		table.insert(ctx.props, p)
		if p.blocks then
			for _, b in p.blocks do
				ctx.solids:add(b[1], b[2], b[3])
			end
		elseif p.radius > 0 then
			ctx.solids:add(p.x, p.z, p.radius)
		end
		return p
	end

	-- a footprint `r` may stand at (x, z): inside the map, clear of solids and
	-- (unless it is a landmark piece) of anchors and of spawn
	function ctx.free(x: number, z: number, r: number, landmark: boolean?): boolean
		if math.abs(x) > ctx.limit or math.abs(z) > ctx.limit then
			return false
		end
		if x * x + z * z < (44 + r) ^ 2 then
			return false
		end
		if not landmark and ctx.nearAnchor(x, z, r) then
			return false
		end
		-- landmark pieces may stand closer, but never closer than the 4 studs an enemy needs
		return ctx.solids:clear(x, z, r, if landmark then 4.5 else GAP)
	end

	-- on a slope, sink a footprint so its downhill edge does not float
	function ctx.sink(x: number, z: number, r: number): number
		return -MapGen.slopeAt(map, x, z) * r * 0.6
	end

	return ctx
end

local function seedOf(x: number, z: number): number
	return math.floor(hash(x, z, 1) * 100000)
end

local function placeLandmarks(ctx)
	local add, free, sink = ctx.add, ctx.free, ctx.sink
	-- ---------------------------------------------------------- landmarks

	-- the Ward, facing the spawn clearing
	do
		local s = World.Sites[2]
		local yaw = math.atan2(s.x, s.z) -- local +z points away from spawn
		local blocks = {}
		local c, sn = math.cos(yaw), math.sin(yaw)
		local function at(lx: number, lz: number): (number, number)
			return s.x + lx * c + lz * sn, s.z - lx * sn + lz * c
		end
		local half = 2 * 6.2 + 1.5
		for _, k in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			local x, z = at(k[1] * half, k[2] * half)
			table.insert(blocks, { x, z, 2.2 })
		end
		local bx, bz = at(0, 0)
		table.insert(blocks, { bx, bz, 2.4 })
		local wx, wz = at(0, 2 * 6.2 + 6.2 + 1)
		table.insert(blocks, { wx, wz, 3 })
		add({ kind = "Ward", x = s.x, z = s.z, yaw = yaw, scale = 1, radius = 0, seed = 11, blocks = blocks })
	end

	-- the Runic Gate over the top of ramp A, its keystone facing down the ramp
	do
		local x, z = -95, 166
		add({
			kind = "Gate",
			x = x,
			z = z,
			yaw = 0,
			scale = 1,
			radius = 0,
			seed = 17,
			blocks = { { x - 14.6, z, 3.2 }, { x + 14.6, z, 3.2 } },
		})
	end

	-- the Highwatch: the tower on its knoll, a broken ring of walls, an arch
	-- facing south down to the basin, a brazier at the tower's foot
	do
		local s = World.Sites[4]
		add({ kind = "RuinTower", x = s.x, z = s.z + 4, yaw = 0.4, scale = 1.25, radius = 11, seed = 21 })
		for k = 0, 9 do
			if k ~= 2 and k ~= 6 and k ~= 7 then
				local a = k / 10 * math.pi * 2 + 0.3
				local r = 29
				local x, z = s.x + math.cos(a) * r, s.z + math.sin(a) * r
				add({
					kind = "RuinWall",
					x = x,
					z = z,
					yaw = -a + math.pi / 2,
					scale = 1.35,
					radius = 2.6,
					seed = 22 + k,
					lift = sink(x, z, 3),
				})
			end
		end
		local ax, az = s.x - 2, s.z - 31
		add({
			kind = "RuinArch",
			x = ax,
			z = az,
			yaw = 0,
			scale = 1.6,
			radius = 0,
			seed = 33,
			blocks = { { ax - 6, az, 2 }, { ax + 6, az, 2 } },
		})
		add({ kind = "Brazier", x = s.x - 3, z = s.z - 17, yaw = 0, scale = 1.2, radius = 2.2, seed = 34 })
		add({ kind = "Pillar", x = s.x - 16, z = s.z - 44, yaw = 0, scale = 1.1, radius = 2.2, seed = 35 })
		add({ kind = "PillarBroken", x = s.x + 13, z = s.z - 46, yaw = 1, scale = 1.1, radius = 2.2, seed = 36 })
	end

	-- the Elder: a giant tree on its hill, roots spreading into the slope
	do
		local s = World.Sites[3]
		add({ kind = "Elder", x = s.x, z = s.z, yaw = 2.2, scale = 1.15, radius = 7, seed = 41, lift = -1.5 })
		add({ kind = "ElderRoots", x = s.x, z = s.z, yaw = 0, scale = 1.25, radius = 0, seed = 42 })
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2 + 0.4
			add({
				kind = "Flowers",
				x = s.x + math.cos(a) * 18,
				z = s.z + math.sin(a) * 18,
				yaw = a,
				scale = 1.2,
				radius = 0,
				seed = 43 + k,
			})
		end
	end

	-- the Moonwell: a ring of teal-runed stones round the pond, open towards the path
	do
		local s = World.Sites[7]
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			if math.abs(((a + math.pi) % (2 * math.pi)) - math.pi) > 0.35 then -- leave the east side open
				local x, z = s.x + math.cos(a) * (F.pond.r + 9), s.z + math.sin(a) * (F.pond.r + 9)
				local kind = if k % 2 == 0 then "MoonStone" else "Menhir"
				add({ kind = kind, x = x, z = z, yaw = -a + math.pi / 2, scale = 1.15, radius = 2.2, seed = 51 + k })
				local gx, gz = s.x + math.cos(a + 0.18) * (F.pond.r + 6), s.z + math.sin(a + 0.18) * (F.pond.r + 6)
				add({ kind = "Glowcaps", x = gx, z = gz, yaw = a, scale = 1, radius = 0, seed = 61 + k })
			end
		end
	end

	-- the top of the chute: a cairn and two stones marking the drop-in
	do
		local s = World.Sites[6]
		add({ kind = "Cairn", x = s.x, z = s.z + 16, yaw = 0.3, scale = 1.3, radius = 2.6, seed = 71 })
		add({ kind = "RuneStone", x = s.x - 17, z = s.z - 6, yaw = 0.2, scale = 1.2, radius = 2.2, seed = 72 })
		add({ kind = "RuneStone", x = s.x + 17, z = s.z - 8, yaw = -0.2, scale = 1.2, radius = 2.2, seed = 73 })
	end

	-- the Highwatch's face: boulders along the foot of the cliff, spruce on its
	-- lip, so the wall seen from the spawn reads as a weathered escarpment
	for i = 0, 26 do
		local x = -224 + i * 17.3 + (hash(i, 1, 75) - 0.5) * 8
		local nearRamp = math.abs(x + 95) < 34 or math.abs(x - 115) < 36 or math.abs(x) < 10
		if not nearRamp then
			local wander = 13 * math.sin(x * 0.021 + 0.6) * math.min(math.max((math.abs(x) - 30) / 50, 0), 1)
			local edge = 150 + wander
			local s = 1.1 + hash(i, 2, 77) * 0.9
			local fx, fz = x, edge - 9 - hash(i, 3, 79) * 5
			if hash(i, 4, 81) < 0.75 and openness(fx, fz) > 0.9 and free(fx, fz, 4.2 * s, true) then
				local rock: Prop = {
					kind = "BoulderLarge",
					x = fx,
					z = fz,
					yaw = hash(i, 5, 83) * 6.3,
					scale = s,
					radius = 4.2 * s,
					seed = 140 + i,
					lift = -0.6 * s,
				}
				add(rock)
			end
			local tx, tz = x + (hash(i, 6, 85) - 0.5) * 10, edge + 12 + hash(i, 7, 87) * 8
			if hash(i, 8, 89) < 0.6 and openness(tx, tz) > 0.9 and free(tx, tz, 1.2, true) then
				local tree: Prop = {
					kind = "Spruce",
					x = tx,
					z = tz,
					yaw = hash(i, 9, 91) * 6.3,
					scale = 0.9 + hash(i, 10, 93) * 0.5,
					radius = 1.1,
					seed = 170 + i,
				}
				add(tree)
			end
		end
	end

	-- the old ward circle round the spawn clearing: paving set flush in the
	-- ground (never a trip at speed) and three broken columns in its gaps
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2 + 0.13
		local gap = k % 8 == 3
		local x, z = math.cos(a) * 58, math.sin(a) * 58
		if gap then
			if World.pathDistance(x, z) > 4 and free(x, z, 2.2, true) then
				local stump: Prop = { kind = "PillarBroken", x = x, z = z, yaw = a, scale = 0.9, radius = 2.2, seed = 180 + k }
				add(stump)
			end
		elseif World.pathDistance(x, z) > 1 and hash(k, 1, 279) < 0.8 then
			local slab: Prop = { kind = "Paving", x = x, z = z, yaw = -a + math.pi / 2, scale = 1, radius = 0, seed = 190 + k }
			add(slab)
		end
	end

	-- the falls: a spring over the Highwatch's face, its pool at the foot with
	-- rocks and ferns round it, a rune stone marking the spring on the top
	do
		local f = F.falls
		local topY = MapGen.heightAt(ctx.map, f.x, f.topZ)
		local fall: Prop = {
			kind = "Waterfall",
			x = f.x,
			z = f.z + f.r,
			yaw = 0,
			scale = 1,
			radius = 0,
			seed = 120,
			-- from just in front of the lip, landing well out in the pool: the face is
			-- convex at the top, so a ribbon from the very lip would run through it
			top = { f.x, topY + 1.5, f.topZ },
			bottom = { f.x, f.level + 0.2, f.z + 3 },
		}
		add(fall)
		for k, spot in { { -13, 6, 1.5 }, { 12, 8, 1.2 }, { -9, -12, 0.9 }, { 14, -6, 0.8 } } do
			local x, z = f.x + spot[1], f.z + spot[2]
			add({
				kind = "BoulderLarge",
				x = x,
				z = z,
				yaw = k * 1.7,
				scale = spot[3],
				radius = 4.2 * spot[3],
				seed = 121 + k,
				lift = -0.5 * spot[3],
			})
		end
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2 + 0.5
			add({
				kind = "Fern",
				x = f.x + math.cos(a) * (f.r + 4),
				z = f.z + math.sin(a) * (f.r + 4),
				yaw = a,
				scale = 1.3,
				radius = 0,
				seed = 126 + k,
			})
		end
		add({ kind = "RuneStone", x = f.x + 8, z = f.topZ + 6, yaw = 0.3, scale = 0.9, radius = 2, seed = 133 })
	end

	-- the Ridge Run: standing stones along the spine
	for i = 0, 8 do
		local z = -170 + i * 36
		local x = 235 + 16 * math.sin(z * 0.013 + 0.8) + (hash(i, 3, 81) - 0.5) * 6
		local kind = if i % 3 == 0 then "RuneStone" else "Menhir"
		if free(x, z, 2.2, true) then
			local scale = 1.25 + hash(i, 5, 85) * 0.4
			local yaw = hash(i, 4, 83) * math.pi
			local stone: Prop = { kind = kind, x = x, z = z, yaw = yaw, scale = scale, radius = 2.2, seed = 90 + i }
			add(stone)
		end
	end
end

local function placeGardens(ctx)
	local add, free, sink = ctx.add, ctx.free, ctx.sink
	-- the Gardens: ruined walls along each terrace lip, lanterns up the ramp,
	-- stone steps flanking its foot and a brazier at its top
	for k = 1, 4 do
		for x = -220, 220, 26 do
			if math.abs(x - F.gardenRampX) > 24 and hash(x, k, 87) < 0.55 then
				local tz = 42 * k - 30 -- just behind the lip
				local z = -(130 + tz - 16 * math.sin(x * 0.018 + 0.4))
				if World.pathDistance(x, z) > 4 and free(x, z, 2.6, true) then
					add({
						kind = "RuinWall",
						x = x,
						z = z,
						yaw = (hash(x, k, 89) - 0.5) * 0.3,
						scale = 1.2,
						radius = 2.6,
						seed = 100 + k * 50 + x,
						lift = sink(x, z, 3),
					})
				end
			end
		end
	end
	-- a pair of lanterns at the foot of the ramp and a pair at its head
	for _, k in { 0, 5 } do
		local z = -150 - k * 30
		for side = -1, 1, 2 do
			local x = F.gardenRampX + side * 12
			add({
				kind = "LanternPost",
				x = x,
				z = z + side * 6,
				yaw = if side < 0 then math.pi / 2 else -math.pi / 2,
				scale = 1.3,
				radius = 0,
				seed = 300 + k * 2 + side,
			})
		end
	end
	for side = -1, 1, 2 do
		add({ kind = "StoneSteps", x = F.gardenRampX + side * 21, z = -160, yaw = math.pi, scale = 1.3, radius = 0, seed = 320 + side })
	end
	do
		local s = World.Sites[8]
		add({ kind = "Brazier", x = s.x, z = s.z, yaw = 0, scale = 1.3, radius = 2.4, seed = 330 })
		add({ kind = "Pillar", x = s.x - 10, z = s.z + 4, yaw = 0, scale = 1, radius = 2.2, seed = 331 })
		add({ kind = "Pillar", x = s.x + 10, z = s.z + 4, yaw = 0, scale = 1, radius = 2.2, seed = 332 })
	end
end

local function placeRuins(ctx)
	local add, free, sink = ctx.add, ctx.free, ctx.sink
	-- small ruins out in the open, for whoever wanders
	for i, r in RUINS do
		local x, z, yaw = r[1], r[2], math.rad(r[3])
		local c, sn = math.cos(yaw), math.sin(yaw)
		local pieces = {
			{ "PillarBroken", 0, 0, 2.2 },
			{ "Pillar", 9, 2, 2.2 },
			{ "RuinWall", -6, 8, 2.6 },
		}
		for j, piece in pieces do
			if j < 3 or hash(i, j, 91) < 0.6 then
				local px, pz = x + piece[2] * c + piece[3] * sn, z - piece[2] * sn + piece[3] * c
				if openness(px, pz) > 0.9 and free(px, pz, piece[4], true) then
					add({
						kind = piece[1],
						x = px,
						z = pz,
						yaw = yaw + hash(i, j, 93),
						scale = 1 + hash(i, j, 95) * 0.25,
						radius = piece[4],
						seed = 400 + i * 10 + j,
						lift = sink(px, pz, 2),
					})
				end
			end
		end
	end
end

-- Lanterns where they mean something, not every few strides: where one path
-- leaves another, on the approach to a landmark, at a sharp bend, and now and
-- then along a long stretch, at uneven gaps, so the warm pools of light lead
-- the way without lining a path like a street. Never two close together.
local LANTERN_GAP = 34

local function placeLanterns(ctx)
	local add, free = ctx.add, ctx.free
	local placed = {}
	for _, p in ctx.props do
		if p.kind == "LanternPost" then
			table.insert(placed, { p.x, p.z })
		end
	end
	local function clearOfLanterns(x: number, z: number): boolean
		for _, l in placed do
			if (l[1] - x) ^ 2 + (l[2] - z) ^ 2 < LANTERN_GAP * LANTERN_GAP then
				return false
			end
		end
		return true
	end
	-- a lantern beside `path` at (x, z), on `side` of the way it runs (dx, dz)
	local function beside(pi: number, path, x: number, z: number, dx: number, dz: number, side: number, seed: number)
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-3 then
			return
		end
		local nx, nz = -dz / len * side, dx / len * side
		local lx, lz = x + nx * (path.half + 2.5), z + nz * (path.half + 2.5)
		if lx * lx + lz * lz > 60 * 60 and clearOfLanterns(lx, lz) and free(lx, lz, 0.8, true) then
			table.insert(placed, { lx, lz })
			add({ kind = "LanternPost", x = lx, z = lz, yaw = math.atan2(-nx, -nz), scale = 1.25, radius = 0, seed = 500 + pi * 40 + seed })
		end
	end
	local function pointAt(pts, along: number): (number, number, number, number)
		for i = 1, #pts - 1 do
			local p, q = pts[i], pts[i + 1]
			local dx, dz = q[1] - p[1], q[2] - p[2]
			local len = math.sqrt(dx * dx + dz * dz)
			if along <= len or i == #pts - 1 then
				local t = math.clamp(along / len, 0, 1)
				return p[1] + dx * t, p[2] + dz * t, dx, dz
			end
			along -= len
		end
		return pts[1][1], pts[1][2], 1, 0
	end
	local function length(pts): number
		local total = 0
		for i = 1, #pts - 1 do
			total += math.sqrt((pts[i + 1][1] - pts[i][1]) ^ 2 + (pts[i + 1][2] - pts[i][2]) ^ 2)
		end
		return total
	end

	-- 1. where a path branches off another: a lantern just along the branch
	for pi, path in World.Paths do
		local x, z, dx, dz = pointAt(path.points, path.half + 10)
		beside(pi, path, x, z, dx, dz, if hash(pi, 1, 521) < 0.5 then 1 else -1, 1)
	end
	-- 2. the approach to a landmark at a path's end
	for pi, path in World.Paths do
		local pts = path.points
		local last = pts[#pts]
		for _, site in World.Sites do
			local d = math.sqrt((site.x - last[1]) ^ 2 + (site.z - last[2]) ^ 2)
			if d < site.clear + 24 then
				local total = length(pts)
				local x, z, dx, dz = pointAt(pts, total - math.max(0, site.clear + 8 - d))
				beside(pi, path, x, z, dx, dz, if hash(pi, 2, 523) < 0.5 then 1 else -1, 2)
				break
			end
		end
	end
	-- 3. a sharp bend, on its outer side
	for pi, path in World.Paths do
		local pts = path.points
		for i = 2, #pts - 1 do
			local ax, az = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
			local bx, bz = pts[i + 1][1] - pts[i][1], pts[i + 1][2] - pts[i][2]
			local la, lb = math.sqrt(ax * ax + az * az), math.sqrt(bx * bx + bz * bz)
			local turn = math.acos(math.clamp((ax * bx + az * bz) / (la * lb), -1, 1))
			if turn > math.rad(35) then
				-- the outer side is away from the turn
				local cross = ax * bz - az * bx
				beside(pi, path, pts[i][1], pts[i][2], ax + bx, az + bz, if cross > 0 then -1 else 1, 2 + i)
			end
		end
	end
	-- 4. now and then along a long stretch, at uneven gaps
	for pi, path in World.Paths do
		local total = length(path.points)
		local at = 60 + hash(pi, 3, 527) * 30
		local k = 0
		while at < total - 20 do
			k += 1
			local x, z, dx, dz = pointAt(path.points, at)
			beside(pi, path, x, z, dx, dz, if hash(pi, k, 529) < 0.5 then 1 else -1, 10 + k)
			at += 85 + hash(pi, k, 531) * 55
		end
	end
end

local function placeNature(ctx)
	local add, free, sink = ctx.add, ctx.free, ctx.sink
	-- ---------------------------------------------------------- nature

	-- the lone great oaks
	for i, o in OAKS do
		local scale = o[3] * 0.85
		local r = 1.15 * scale
		if openness(o[1], o[2]) > 0.9 and free(o[1], o[2], r) then
			add({
				kind = o[4],
				x = o[1],
				z = o[2],
				yaw = hash(i, 1, 97) * math.pi * 2,
				scale = scale,
				radius = r,
				seed = 600 + i,
				lift = sink(o[1], o[2], r),
			})
		end
	end

	-- outcrops: one big boulder, smaller ones round it, loose stones
	for i, o in OUTCROPS do
		local big = 1.5 + hash(i, 1, 101) * 1.1
		local r = 4.2 * big
		if openness(o[1], o[2]) > 0.9 and free(o[1], o[2], r, true) then
			add({
				kind = "BoulderLarge",
				x = o[1],
				z = o[2],
				yaw = hash(i, 2, 103) * 6.3,
				scale = big,
				radius = r,
				seed = 700 + i,
				lift = sink(o[1], o[2], r) - 0.5 * big,
			})
			for k = 1, 3 do
				local a = hash(i, k, 107) * math.pi * 2
				local d = r + 3 + hash(i, k, 109) * 5
				local x, z = o[1] + math.cos(a) * d, o[2] + math.sin(a) * d
				local s = 0.6 + hash(i, k, 113) * 0.7
				if k == 1 and openness(x, z) > 0.9 and free(x, z, 4.2 * s, true) then
					add({
						kind = "BoulderLarge",
						x = x,
						z = z,
						yaw = a,
						scale = s,
						radius = 4.2 * s,
						seed = 710 + i * 5 + k,
						lift = sink(x, z, 4 * s) - 0.4 * s,
					})
				else
					add({ kind = "RockSmall", x = x, z = z, yaw = a, scale = 1 + hash(i, k, 127) * 1.2, radius = 0, seed = 720 + i * 5 + k })
				end
			end
		end
	end
end

-- The wider world's landmarks and its ancient trees.
local function placeWider(ctx)
	local add, free, sink = ctx.add, ctx.free, ctx.sink
	local function site(name: string)
		for _, s in World.Sites do
			if s.name == name then
				return s
			end
		end
		error(name)
	end

	-- the Sun Temple on Sunspire's summit: a ring of columns round a dais and
	-- its great brazier, an open circle a fight can sweep through
	do
		local s = site("SunTemple")
		local blocks = {}
		for k = 0, 11 do
			if k ~= 2 and k ~= 7 then -- two columns long fallen: gaps to run through
				local a = k / 12 * math.pi * 2
				table.insert(blocks, { s.x + math.cos(a) * 20, s.z + math.sin(a) * 20, 2.2 })
			end
		end
		table.insert(blocks, { s.x, s.z, 3 })
		local temple: Prop = { kind = "SunTemple", x = s.x, z = s.z, yaw = 0, scale = 1, radius = 0, seed = 1001, blocks = blocks }
		add(temple)
	end

	-- the Fallen Giant: an ancient tree come down across its gully, a trunk you
	-- can run along, its root plate reared up on the far bank
	do
		local s = site("FallenGiant")
		-- across the gully: the gully runs roughly east-south-east here
		local yaw = math.rad(-58)
		local c, sn = math.cos(yaw), math.sin(yaw)
		-- solid where the trunk rests on each bank; the gully under it stays open
		local blocks = {}
		for _, lx in { -28, 28 } do
			table.insert(blocks, { s.x + lx * c, s.z - lx * sn, 4.5 })
		end
		local giant: Prop = { kind = "FallenGiant", x = s.x, z = s.z, yaw = yaw, scale = 1, radius = 0, seed = 1002, blocks = blocks }
		add(giant)
	end

	-- Stoneglen: a great circle of standing stones in its bowl, a flat altar
	do
		local s = site("Stoneglen")
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2 + 0.2
			local x, z = s.x + math.cos(a) * 31, s.z + math.sin(a) * 31
			if World.pathDistance(x, z) > 4 then
				local stone: Prop = {
					kind = if k % 3 == 0 then "RuneStone" else "Menhir",
					x = x,
					z = z,
					yaw = -a + math.pi / 2,
					scale = 1.35,
					radius = 2.4,
					seed = 1010 + k,
				}
				add(stone)
			end
		end
		local altar: Prop = { kind = "Paving", x = s.x, z = s.z, yaw = 0.3, scale = 1.6, radius = 0, seed = 1030 }
		add(altar)
		local brazier: Prop = { kind = "Brazier", x = s.x, z = s.z + 2, yaw = 0, scale = 1.2, radius = 2.2, seed = 1031 }
		add(brazier)
	end

	-- Windhill: a cairn and its stones on the crown of the hill
	do
		local s = site("Windhill")
		local cairn: Prop = { kind = "Cairn", x = s.x, z = s.z, yaw = 0.7, scale = 1.6, radius = 3, seed = 1040 }
		add(cairn)
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + 0.5
			local stone: Prop = {
				kind = "RuneStone",
				x = s.x + math.cos(a) * 12,
				z = s.z + math.sin(a) * 12,
				yaw = -a,
				scale = 1.1,
				radius = 2.2,
				seed = 1041 + k,
			}
			add(stone)
		end
	end

	-- the North Vale: a broken wall and old columns in the long grass
	do
		local s = site("NorthVale")
		for k, piece in
			{ { "RuinWall", -14, 4 }, { "RuinWall", -2, 10 }, { "Pillar", 12, -2 }, { "PillarBroken", 18, 10 }, { "RuinArch", 0, -12 } }
		do
			local x, z = s.x + piece[2], s.z + piece[3]
			local kind = piece[1]
			local r = if kind == "RuinArch" then 0 else 2.4
			local ruin: Prop = { kind = kind, x = x, z = z, yaw = 0.25 * k, scale = 1.3, radius = r, seed = 1050 + k, lift = sink(x, z, 2) }
			if kind == "RuinArch" then
				ruin.blocks = { { x - 7, z, 2 }, { x + 7, z, 2 } }
			end
			add(ruin)
		end
	end

	-- the ancients: each the mark of its region. Their trunks are the only
	-- solid part, their crowns begin far overhead.
	for i, a in ANCIENTS do
		local x, z = a[1], a[2]
		if free(x, z, 6, true) then
			local tree: Prop = {
				kind = a[3],
				x = x,
				z = z,
				yaw = hash(i, 1, 331) * math.pi * 2,
				scale = a[4],
				radius = 6 * a[4],
				seed = 1100 + i,
				lift = sink(x, z, 5),
			}
			add(tree)
		end
	end

	-- the Old Grove's shrine, round the foot of the greatest of its ancients
	do
		local s = site("OldGrove")
		for k, piece in
			{ { "RuneStone", 17, 8 }, { "PillarBroken", -16, 12 }, { "Pillar", 12, -18 }, { "Glowcaps", -8, -15 }, { "Glowcaps", 19, -6 } }
		do
			local x, z = s.x + piece[2], s.z + piece[3]
			local solid = piece[1] ~= "Glowcaps"
			local bit: Prop =
				{ kind = piece[1], x = x, z = z, yaw = k * 1.1, scale = 1.1, radius = if solid then 2.2 else 0, seed = 1060 + k }
			add(bit)
		end
	end
end

-- how far a crown reaches at scale 1, about (measured from the blueprints)
local CROWN = {
	Spruce = 8,
	SpruceFar = 8.5,
	Pine = 9,
	Beech = 8.5,
	Oak = 10,
	OakLeaning = 10,
	Birch = 6.5,
	Sapling = 3,
	AncientOak = 26, -- about half the limbs' spread: the ancients keep a clearing
	AncientPine = 14,
	Elder = 22,
}

local function placeForest(ctx)
	local add, free, sink, map, limit = ctx.add, ctx.free, ctx.sink, ctx.map, ctx.limit
	-- the forest: a jittered lattice, thinned by the forest field; spruce where
	-- it is cool (pines along its warmer edges), beech, oak, birch and saplings
	-- where it is warm. Sizes vary: young trees crowd the woodland's thin
	-- edges, old ones stand in its heart, about one in ten grown large.
	--
	-- Trunks keep their walking gap (ctx.free), and crowns keep a gap of their
	-- own: in open woodland they barely touch, so there is sky between them;
	-- only in deep forest do they close into a roof.
	local crowns = {}
	local CELL = 32
	local function crownKey(x: number, z: number): number
		return math.floor(x / CELL) * 4096 + math.floor(z / CELL)
	end
	local function addCrown(x: number, z: number, c: number)
		local k = crownKey(x, z)
		local list = crowns[k]
		if not list then
			list = {}
			crowns[k] = list
		end
		table.insert(list, { x, z, c })
	end
	local function crownRoom(x: number, z: number, c: number, overlap: number): boolean
		local cx, cz = math.floor(x / CELL), math.floor(z / CELL)
		for ix = cx - 1, cx + 1 do
			for iz = cz - 1, cz + 1 do
				for _, o in crowns[ix * 4096 + iz] or {} do
					local need = (o[3] + c) * overlap
					if (o[1] - x) ^ 2 + (o[2] - z) ^ 2 < need * need then
						return false
					end
				end
			end
		end
		return true
	end
	for _, p in ctx.props do
		if CROWN[p.kind] then
			addCrown(p.x, p.z, CROWN[p.kind] * p.scale)
		end
	end

	local step = 8.5
	local count = math.floor(limit / step)
	for iz = -count, count do
		for ix = -count, count do
			local x = ix * step + (hash(ix, iz, 131) - 0.5) * step * 0.9
			local z = iz * step + (hash(ix, iz, 137) - 0.5) * step * 0.9
			local out = MapGen.outside(x, z)
			if out > -8 then
				continue -- the mountains are dressed separately
			end
			local f = World.forest(x, z)
			if hash(ix, iz, 139) >= f * 0.9 then
				continue
			end
			if MapGen.slopeAt(map, x, z) > 1.0 then
				continue
			end
			local cool = coolness(x, z)
			local roll = hash(ix, iz, 149)
			-- young at the thin edges of a wood, old in its heart
			local edge = smooth((0.5 - f) / 0.3)
			local young = hash(ix, iz, 163) < 0.15 + 0.3 * edge
			local mature = not young and hash(ix, iz, 151) < 0.06 + 0.1 * (1 - edge)
			local grow = hash(ix, iz, 153)
			local kind, scale, r
			if roll < cool or cool > 0.9 then
				scale = if mature then 1.5 + grow * 0.4 else 0.8 + grow * 0.6
				if cool < 0.85 and hash(ix, iz, 155) < 0.3 then
					-- a pine among the firs: a tall column with a high, ragged crown
					kind, scale = "Pine", 0.95 + grow * 0.6
				else
					-- fuller firs near the heart; lighter ones, standing a little more
					-- apart, out in the wider world
					local near = math.sqrt(x * x + z * z) < 330 and scale < 1.5
					if not near and hash(ix, iz, 154) < 0.3 then
						continue
					end
					kind = if near then "Spruce" else "SpruceFar"
				end
				r = 1.0 * scale
			else
				local w = hash(ix, iz, 157)
				local birchShare = 0.35
				for _, g in GROVES do
					if (x - g[1]) ^ 2 + (z - g[2]) ^ 2 < g[3] * g[3] then
						birchShare = g[5]
						break
					end
				end
				if w < birchShare then
					kind, scale = "Birch", 0.85 + grow * 0.5 + (if mature then 0.35 else 0)
					r = 0.6 * scale
				elseif f < 0.35 and w > 0.82 then
					kind, scale = "Sapling", 1.2 + grow * 0.6
					r = 0.6 * scale
				elseif w > 0.6 then
					kind = if hash(ix, iz, 159) < 0.6 then "Oak" else "OakLeaning"
					scale = if mature then 1.9 + grow * 0.5 else 1.3 + grow * 0.6
					r = 1.1 * scale
				else
					kind, scale = "Beech", if mature then 2.3 + grow * 0.6 else 1.5 + grow * 0.8
					r = 0.9 * scale
				end
			end
			if young and kind ~= "Sapling" then
				scale *= 0.58 + 0.17 * hash(ix, iz, 165)
				r *= 0.7
			end
			-- crowns in open woodland barely touch; in deep forest they close in
			if not crownRoom(x, z, CROWN[kind] * scale, 0.78 - 0.33 * f) then
				continue
			end
			-- the crown must clear a route, not only the trunk: a spruce's lowest
			-- whorl hangs at head height and would close over a path at speed (a
			-- broadleaf's crown and a pine's stand well overhead)
			local spruce = kind == "Spruce" or kind == "SpruceFar"
			local crown = if spruce then 9.2 * scale elseif kind == "Pine" then 2 * scale else 4.5 * scale
			local clearOfRoutes = World.pathDistance(x, z) > crown * (if spruce then 1 else 0.85)
				and chuteDistance(x, z) > F.chute.core + crown * 0.85
				and (MapGen.alongPolyline(F.gully.points, x, z)) > F.gully.core + crown * 0.85
			if clearOfRoutes and free(x, z, r) then
				local p: Prop = {
					kind = kind,
					x = x,
					z = z,
					yaw = hash(ix, iz, 181) * math.pi * 2,
					scale = scale,
					radius = r,
					seed = seedOf(x, z),
					lift = sink(x, z, r),
				}
				add(p)
				addCrown(x, z, CROWN[kind] * scale)
			end
		end
	end
end

-- The mountains' lower slopes, beyond the barrier: a thinning forest climbing
-- them, scenery only (no anchors, no solid footprint: nothing walks there).
local function placeMountainTrees(ctx)
	local add, map = ctx.add, ctx.map
	local step = 23
	local count = math.floor(map.half / step)
	for iz = -count, count do
		for ix = -count, count do
			local x = ix * step + (hash(ix, iz, 301) - 0.5) * step * 0.8
			local z = iz * step + (hash(ix, iz, 307) - 0.5) * step * 0.8
			local out = MapGen.outside(x, z)
			if out < 10 or out > 175 or math.abs(x) > map.half - 6 or math.abs(z) > map.half - 6 then
				continue
			end
			local h = MapGen.heightAt(map, x, z)
			-- thinner as it climbs, in stands rather than evenly
			local chance = 0.5 * smooth((140 - h) / 60) * (0.35 + 0.65 * patches(x, z))
			if hash(ix, iz, 311) < chance and MapGen.slopeAt(map, x, z) < 1.3 then
				local tree: Prop = {
					kind = "SpruceRidge",
					x = x,
					z = z,
					yaw = hash(ix, iz, 313) * math.pi * 2,
					scale = 1.2 + hash(ix, iz, 317) * 0.8,
					radius = 0,
					seed = seedOf(x, z),
					lift = -MapGen.slopeAt(map, x, z) * 1.5,
				}
				add(tree)
			end
		end
	end
end

-- low teal mist in the cold forest: invisible hosts the client fills with
-- slow, faint drifts (the one place the Wardwood's air turns cool)
local function placeMist(ctx)
	local add = ctx.add
	local count = 0
	for iz = -11, 11 do
		for ix = -11, 11 do
			local x = ix * 44 + (hash(ix, iz, 271) - 0.5) * 20
			local z = iz * 44 + (hash(ix, iz, 277) - 0.5) * 20
			if MapGen.outside(x, z) < -20 and World.forest(x, z) > 0.55 and coolness(x, z) > 0.7 and hash(ix, iz, 281) < 0.75 then
				count += 1
				add({ kind = "Mist", x = x, z = z, yaw = 0, scale = 1, radius = 0, seed = 900 + count })
			end
		end
	end
	local pond = F.pond
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + 0.4
		add({
			kind = "Mist",
			x = pond.x + math.cos(a) * 16,
			z = pond.z + math.sin(a) * 16,
			yaw = 0,
			scale = 0.8,
			radius = 0,
			seed = 960 + k,
		})
	end
end

local function placeCover(ctx)
	local add, map, solids, limit = ctx.add, ctx.map, ctx.solids, ctx.limit
	-- ground cover, walked through: ferns, glowcaps, bushes, logs, stumps, flowers
	local cover = 6.5
	local cn = math.floor(limit / cover)
	for iz = -cn, cn do
		for ix = -cn, cn do
			local x = ix * cover + (hash(ix, iz, 191) - 0.5) * cover
			local z = iz * cover + (hash(ix, iz, 193) - 0.5) * cover
			if x * x + z * z < 46 * 46 or MapGen.slopeAt(map, x, z) > 0.7 or MapGen.outside(x, z) > -6 then
				continue
			end
			local f = World.forest(x, z)
			local open = openness(x, z)
			local roll = hash(ix, iz, 197)
			local cool = coolness(x, z)
			local kind, scale
			if f > 0.5 and cool > 0.5 then
				if roll < 0.075 then
					kind, scale = "Fern", 1 + hash(ix, iz, 199)
				elseif roll < 0.088 and x < -150 then
					kind, scale = "Glowcaps", 0.9 + hash(ix, iz, 211) * 0.5
				elseif roll < 0.098 then
					kind, scale = "FallenLog", 1.2 + hash(ix, iz, 223) * 0.6
				elseif roll < 0.11 then
					kind, scale = "Stump", 1 + hash(ix, iz, 227) * 0.5
				end
			elseif f > 0.22 then
				if roll < 0.06 then
					kind, scale = "Bush", 0.7 + hash(ix, iz, 229) * 0.6
				elseif roll < 0.07 then
					kind, scale = "Stump", 1 + hash(ix, iz, 233) * 0.4
				elseif roll < 0.085 then
					kind, scale = "Fern", 0.9 + hash(ix, iz, 239) * 0.6
				end
			elseif open > 0.6 and World.pathDistance(x, z) > 1.5 then
				-- the meadows: flowers in drifts, following the noise
				if roll < 0.028 + 0.05 * smooth((noise(x * 2.3, z * 2.3) - 0.55) / 0.2) then
					kind, scale = "Flowers", 0.9 + hash(ix, iz, 241) * 0.5
				elseif roll > 0.988 then
					kind, scale = "Bush", 0.6 + hash(ix, iz, 251) * 0.5
				end
			end
			if kind and solids:clear(x, z, 0.5, 0.5) then
				add({ kind = kind, x = x, z = z, yaw = hash(ix, iz, 257) * math.pi * 2, scale = scale, radius = 0, seed = seedOf(x, z) })
			end
		end
	end
end

function World.build(cfg: any): World
	local map = MapGen.build(cfg.MapSizeStuds, cfg.HeightCellStuds, cfg.WallHeight)
	local anchors = World.anchors(map)
	local ctx = newContext(map, anchors)
	placeLandmarks(ctx)
	placeWider(ctx)
	placeGardens(ctx)
	placeRuins(ctx)
	placeLanterns(ctx)
	placeNature(ctx)
	placeForest(ctx)
	placeCover(ctx)
	placeMist(ctx)
	placeMountainTrees(ctx)
	local props = ctx.props
	MapGen.block(map, props)
	-- landmark pieces were placed without regard to anchors: drop any anchor a
	-- solid now crowds, so no chest or shrine is ever built into a rock
	local kept = {}
	for _, a in anchors do
		if ctx.solids:clear(a.x, a.z, 0, 6) then
			table.insert(kept, a)
		end
	end
	anchors = kept
	local pond = F.pond
	local sites = {}
	for _, s in World.Sites do
		table.insert(sites, { name = s.name, x = s.x, z = s.z })
	end
	local paths = {}
	for _, p in World.Paths do
		table.insert(paths, { name = p.name, half = p.half, points = p.points })
	end
	return {
		map = map,
		anchors = anchors,
		props = props,
		water = {
			{ x = pond.x, z = pond.z, r = pond.r + 2, level = pond.level, glow = true },
			{ x = F.falls.x, z = F.falls.z, r = F.falls.r + 2, level = F.falls.level, glow = false },
		},
		paths = paths,
		sites = sites,
		barrier = World.barrier(),
	}
end

-- ------------------------------------------------------------------ parts

--- A part-built prop's primitives in world space, or nil for a mesh prop. Each
--- comes back with `cf` = { x, y, z, then the rotation row by row }.
function World.parts(world: World, prop: Prop): { any }?
	local bp = Blueprints.get(prop.kind)
	if not bp then
		return nil
	end
	local map = world.map
	local s = prop.scale
	local yawDeg = math.deg(prop.yaw)
	local cy, sy = math.cos(prop.yaw), math.sin(prop.yaw)
	local ground = MapGen.heightAt(map, prop.x, prop.z) + (prop.lift or 0)
	local function g(lx: number, lz: number): number
		local wx = prop.x + (lx * cy + lz * sy) * s
		local wz = prop.z + (-lx * sy + lz * cy) * s
		return (MapGen.heightAt(map, wx, wz) - ground) / s
	end
	local Y = Blueprints.matrix(yawDeg, 0, 0)
	local out = {}
	for _, p in bp(prop.seed, g) do
		local lx, ly, lz = p.pos[1] * s, p.pos[2] * s, p.pos[3] * s
		local wx = prop.x + Y[1] * lx + Y[2] * ly + Y[3] * lz
		local wy = ground + ly
		local wz = prop.z + Y[7] * lx + Y[8] * ly + Y[9] * lz
		local rot = p.rot or { 0, 0, 0 }
		local R = Blueprints.matrix(rot[1], rot[2], rot[3])
		local M = table.create(9, 0)
		for i = 0, 2 do
			for j = 0, 2 do
				local acc = 0
				for k = 0, 2 do
					acc += Y[i * 3 + k + 1] * R[k * 3 + j + 1]
				end
				M[i * 3 + j + 1] = acc
			end
		end
		table.insert(out, {
			shape = p.shape,
			size = { p.size[1] * s, p.size[2] * s, p.size[3] * s },
			cf = { wx, wy, wz, M[1], M[2], M[3], M[4], M[5], M[6], M[7], M[8], M[9] },
			color = p.color,
			mat = p.material,
			collide = p.collide == true,
			shadow = p.shadow ~= false,
			neon = p.neon == true,
			light = p.light,
			tag = p.tag,
		})
	end
	return out
end

return World

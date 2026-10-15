--!strict
-- World - the Wardwood: the map and everything standing on it, from one call.
-- Pure and deterministic.
--
-- The server writes the terrain and builds the scenery from it, the enemy
-- simulation walks its heightfield, and tools/map/export_world.luau draws the
-- offline previews from it, so the three can never disagree.
--
-- Composition (north is +z; the lobby and the first gameplay camera look north):
--   Sunmeadow   the open basin round the spawn clearing, scattered oaks and birch
--   the Ward    a ruined rune platform north-west of spawn, the first landmark
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
	collider: number?, -- mesh trees: an invisible trunk of this radius is the only solid part
}

export type World = {
	map: MapGen.Map,
	anchors: { MapGen.Anchor },
	props: { Prop },
	water: { any },
	paths: { any },
	sites: { any },
}

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
}

-- Lone great oaks: the meadow's silhouettes. { x, z, scale, kind }
local OAKS = {
	{ 72, 56, 2.5, "TreeTwin" },
	{ -64, -6, 2.2, "TreeLeaning" },
	{ 128, -118, 2.6, "TreeTwin" },
	{ -150, 96, 2.4, "TreeLeaning" },
	{ 38, -92, 2.2, "TreeLeaning" },
	{ 170, 6, 2.4, "TreeTwin" },
	{ -24, 128, 2.1, "TreeTwin" },
	{ -150, -118, 2.3, "TreeTwin" },
	{ 100, 168, 2.3, "TreeLeaning" },
	{ -84, 238, 2.4, "TreeTwin" },
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
	local d = MapGen.alongPolyline(F.chute.points, x, z)
	return d
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
	if z > 56 and z < 182 then
		keep = math.min(keep, smooth((math.abs(x + 95) - 24) / 6))
		keep = math.min(keep, smooth((math.abs(x - 115 - 10 * math.sin(z * 0.03)) - 24) / 6))
	end
	return keep
end

-- How much colder (spruce) than warmer (oak, birch) the forest is here, 0..1.
local function coolness(x: number, z: number): number
	local e = math.max(math.abs(x), math.abs(z))
	local c = smooth((-120 - x) / 70) -- the west: Mirewood
	c = math.max(c, smooth((e - 262) / 30) * 0.9) -- the rim
	c = math.max(c, smooth((z - 268) / 30) * 0.85) -- the back of the plateau
	c = math.max(c, smooth((-110 - x) / 40) * smooth((z - 160) / 30)) -- the plateau's west woods
	c = math.max(c, smooth((x - 256) / 24) * 0.8) -- behind the ridge
	return c
end
World.coolness = coolness

--- Forest density, 0 (open meadow) to 1 (deep forest).
function World.forest(x: number, z: number): number
	local n = noise(x, z)
	local e = math.max(math.abs(x), math.abs(z))
	local f = 0.1 * n -- the meadows: a tree here and there
	f = math.max(f, smooth((-150 - x) / 60) * (0.62 + 0.3 * n)) -- Mirewood
	f = math.max(f, smooth((-112 - x) / 36) * smooth((z - 172) / 30) * 0.78) -- plateau's west woods
	f = math.max(f, smooth((z - 286) / 22) * 0.72) -- the north rim
	f = math.max(f, smooth((e - 268) / 26) * 0.95) -- the rim all round
	f = math.max(f, smooth((x - 262) / 20) * 0.75) -- behind the ridge
	f = math.max(f, smooth((-270 - z) / 30) * 0.7) -- below the top terrace
	for _, g in GROVES do
		local d = math.sqrt((x - g[1]) ^ 2 + (z - g[2]) ^ 2)
		f = math.max(f, g[4] * smooth(1 - d / g[3]) * (0.75 + 0.5 * n))
	end
	return math.clamp(f, 0, 1) * openness(x, z)
end

-- ------------------------------------------------------------------ surfaces

--- The terrain surface at a point, as a material key (MapService maps keys to
--- Roblox materials and colours; the preview to swatches).
function World.surface(world: World, x: number, z: number): string
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
	if slope > 1.25 then
		return if h > map.wall - 24 then "Slate" else "Rock"
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
	if f > 0.5 and cool > 0.5 then
		return "ForestFloor"
	elseif f > 0.32 or (cool > 0.6 and n > 0.35) then
		return "Lush"
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
		add({ kind = "TreeTwin", x = s.x, z = s.z, yaw = 2.2, scale = 5.4, radius = 6.5, seed = 41, collider = 6, lift = -1.5 })
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
	for k = 0, 5 do
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

local function placeLanterns(ctx)
	local add, free = ctx.add, ctx.free
	-- lanterns along the paths, alternating sides, every so often
	for pi, path in World.Paths do
		local pts = path.points
		local carry = 20
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local dx, dz = b[1] - a[1], b[2] - a[2]
			local len = math.sqrt(dx * dx + dz * dz)
			local t = carry
			while t < len do
				local x, z = a[1] + dx * t / len, a[2] + dz * t / len
				local side = if (math.floor(t) + pi) % 2 == 0 then 1 else -1
				local nx, nz = -dz / len * side, dx / len * side
				local lx, lz = x + nx * (path.half + 2.5), z + nz * (path.half + 2.5)
				if lx * lx + lz * lz > 60 * 60 and free(lx, lz, 0.8, true) then
					add({
						kind = "LanternPost",
						x = lx,
						z = lz,
						yaw = math.atan2(-nx, -nz),
						scale = 1.25,
						radius = 0,
						seed = 500 + pi * 40 + i,
					})
				end
				t += 46
			end
			carry = t - len
		end
	end
end

local function placeNature(ctx)
	local add, free, sink = ctx.add, ctx.free, ctx.sink
	-- ---------------------------------------------------------- nature

	-- the lone great oaks
	for i, o in OAKS do
		local r = 1.15 * o[3]
		if openness(o[1], o[2]) > 0.9 and free(o[1], o[2], r) then
			add({
				kind = o[4],
				x = o[1],
				z = o[2],
				yaw = hash(i, 1, 97) * math.pi * 2,
				scale = o[3],
				radius = r,
				seed = 600 + i,
				collider = r,
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

local function placeForest(ctx)
	local add, free, sink, map, limit = ctx.add, ctx.free, ctx.sink, ctx.map, ctx.limit
	-- the forest: a jittered lattice, thinned by the forest field; spruce where
	-- it is cool, oak, birch and saplings where it is warm
	local step = 8.5
	local count = math.floor(limit / step)
	for iz = -count, count do
		for ix = -count, count do
			local x = ix * step + (hash(ix, iz, 131) - 0.5) * step * 0.9
			local z = iz * step + (hash(ix, iz, 137) - 0.5) * step * 0.9
			local f = World.forest(x, z)
			if hash(ix, iz, 139) >= f * 0.9 then
				continue
			end
			local slope = MapGen.slopeAt(map, x, z)
			local e = math.max(math.abs(x), math.abs(z))
			if slope > (if e > 290 then 1.7 else 1.0) then
				continue
			end
			local cool = coolness(x, z)
			local roll = hash(ix, iz, 149)
			local kind, scale, r
			local grown = 0.8 + hash(ix, iz, 151) * 0.6 + smooth((e - 260) / 60) * 0.35
			if roll < cool or cool > 0.9 then
				kind, scale = if e > 292 then "SpruceFar" else "Spruce", grown
				-- on the far rim, fewer and larger: only the silhouette is seen there
				r = if e > 292 then 2.4 * scale else 1.0 * scale
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
					kind, scale = "Birch", 0.85 + hash(ix, iz, 163) * 0.5
					r = 0.6 * scale
				elseif f < 0.35 and w > 0.82 then
					kind, scale = "TreeSapling", 1.2 + hash(ix, iz, 167) * 0.6
					r = 0.6 * scale
				elseif w > 0.6 then
					kind, scale = "TreeLeaning", 1.35 + hash(ix, iz, 173) * 0.75
					r = 1.0 * scale
				else
					kind, scale = "TreeTwin", 1.4 + hash(ix, iz, 179) * 0.8
					r = 1.1 * scale
				end
			end
			if free(x, z, r) then
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
				if kind ~= "Spruce" and kind ~= "SpruceFar" and kind ~= "Birch" then
					p.collider = r
				end
				add(p)
			end
		end
	end
end

-- low teal mist in the cold forest: invisible hosts the client fills with
-- slow, faint drifts (the one place the Wardwood's air turns cool)
local function placeMist(ctx)
	local add = ctx.add
	local count = 0
	for iz = -7, 7 do
		for ix = -7, 7 do
			local x = ix * 44 + (hash(ix, iz, 271) - 0.5) * 20
			local z = iz * 44 + (hash(ix, iz, 277) - 0.5) * 20
			local e = math.max(math.abs(x), math.abs(z))
			if e < 300 and World.forest(x, z) > 0.55 and coolness(x, z) > 0.7 and hash(ix, iz, 281) < 0.75 then
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
			if x * x + z * z < 46 * 46 or MapGen.slopeAt(map, x, z) > 0.7 then
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
	placeGardens(ctx)
	placeRuins(ctx)
	placeLanterns(ctx)
	placeNature(ctx)
	placeForest(ctx)
	placeCover(ctx)
	placeMist(ctx)
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

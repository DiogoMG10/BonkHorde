--!strict
-- MapGen - Mossy Woods as a heightfield, and the questions the game asks of it.
--
-- The map is a function of (x, z): the server simulates enemies on it without
-- physics, every client rebuilds the same heights locally, and the terrain is
-- written from it. Nothing about the layout is random per run; only what gets
-- PLACED on the anchors is. Pure.
--
-- Layout (north is +z), the Wardwood. The heart: a meadow basin round the
-- spawn clearing; the Highwatch plateau to the north, reached by two ramps and
-- the long curving Thunder Chute down its north-east shoulder; the Ridge Run to
-- the east; the Elder Hill to the south-west; the curved Terraced Gardens to
-- the south with one smooth ramp through them; the Mirewood dell to the west
-- round the shallow Moonwell pond.
-- The wider world round it: the plateau's long north slope down to the North
-- Vale; Thornwood and its hills to the north-west and Windhill to the
-- north-east; Sunspire Hill beyond the ridge to the east, the Sun Temple on
-- its summit; the Fallen Giant's gully to the south-east; the long descent
-- from the top terrace to Stoneglen in the south; the raised floor of the Old
-- Grove to the west. All of it gentle enough for a horde to follow a hero.
-- Round the playable world (a rounded, wandering boundary) mountains rise
-- straight from its edge: scenery only, walled off by an invisible barrier.
-- Core/World dresses it; the features below are shared with it.

local MapGen = {}

export type Map = {
	size: number,
	half: number,
	cell: number,
	n: number, -- samples per side
	heights: { number },
	wall: number,
	play: { boolean }, -- samples at least PLAY_MARGIN inside the playable edge
	blocked: { boolean }?, -- samples a prop stands on; set by MapGen.block
}
export type Prop = { kind: string, x: number, z: number, yaw: number, scale: number, radius: number }
export type Anchor = { x: number, z: number, d: number }

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- The landforms that dressing and terrain painting need to know about.
MapGen.Features = {
	-- the Moonwell: a shallow wading pond in the Mirewood dell
	pond = { x = -232, z = 30, r = 26, level = 6, depth = 2.4, lip = 20 },
	-- the falls: a spring spilling over the Highwatch's face into a small pool,
	-- straight ahead of the first view from the spawn
	falls = { x = 0, z = 138, r = 9, level = 5.4, depth = 1.5, lip = 10, topZ = 163 },
	-- the Elder Hill and the knoll the Highwatch tower stands on
	elderHill = { x = -112, z = -96, r = 62, rise = 14 },
	watchKnoll = { x = 40, z = 252, r = 46, rise = 9 },
	-- the Thunder Chute: a graded half-pipe from the plateau to the basin
	chute = {
		points = { { 204, 246 }, { 188, 180 }, { 168, 124 }, { 140, 72 }, { 124, 48 } },
		top = 52, -- a raised drop-in above the plateau...
		bottom = 8, -- ...down to the basin floor
		steep = 0.45, -- the first 45 % of the run takes 60 % of the drop
		core = 13, -- half-width of the running surface
		shoulder = 24, -- and of the bank blending it into the ground
	},
	-- the garden ramp: one smooth slope through the terrace risers
	gardenRampX = -58,
	gardenRampHalf = 15,
	-- Sunspire Hill: a broad hill beyond the ridge, a flat summit for the temple
	sunspire = { x = 378, z = 24, top = 30, r = 120, rise = 40 },
	-- the Fallen Giant's gully: a valley with gentle banks, a fallen tree across it
	gully = { points = { { 248, -196 }, { 300, -262 }, { 360, -300 }, { 430, -320 } }, depth = 10, core = 14, bank = 30 },
	-- rolling hills of the wider world: { x, z, radius, rise }
	hills = {
		{ 330, 340, 92, 20 }, -- Windhill
		{ -330, 330, 84, 16 }, -- Thornback
		{ -385, -40, 120, 10 }, -- the Old Grove's raised floor
		{ 150, 380, 70, 9 },
		{ -170, -400, 70, 8 },
		{ 430, -150, 60, 10 },
		{ -440, 190, 70, 12 },
	},
	-- Stoneglen: a shallow bowl below the terraces' long descent
	glen = { x = -296, z = -372, r = 64, depth = 6 },
}

-- The playable world: a rounded square (a superellipse) whose edge wanders a
-- little with the angle, so the mountains round it never form a straight wall.
MapGen.Bound = { p = 4, r = 455 }
-- enemies (and anchors) keep this far inside the edge
MapGen.PLAY_MARGIN = 12

--- How far (x, z) lies outside the playable edge, in studs (negative inside).
function MapGen.outside(x: number, z: number): number
	local b = MapGen.Bound
	local ax, az = math.abs(x), math.abs(z)
	local d = (ax ^ b.p + az ^ b.p) ^ (1 / b.p)
	local a = math.atan2(z, x)
	local r = b.r * (1 + 0.035 * math.sin(3 * a + 0.7) + 0.03 * math.sin(5 * a + 2.1) + 0.02 * math.sin(8 * a + 0.4))
	return d - r
end

-- A ridged mountain height for the backdrop beyond the edge: higher the
-- further out, broken into peaks and saddles, lower in a few passes so the
-- world seems to carry on past them.
local function mountain(x: number, z: number, out: number): number
	local ridge = 1 - math.abs(math.sin(x * 0.011 + z * 0.007 + 1.3) * math.cos(x * 0.006 - z * 0.013 + 0.4))
	local fine = math.sin(x * 0.031 + 0.4) * math.sin(z * 0.027 - 0.8)
	local a = math.atan2(z, x)
	local pass = 0.62 + 0.38 * smooth((math.cos(2 * a + 0.9) + 0.3) / 0.9)
	return (62 + 100 * smooth(out / 180) + 58 * ridge + 16 * fine) * pass
end

-- distance from (x, z) to a polyline, and how far along it (studs) the closest point is
local function alongPolyline(points: { { number } }, x: number, z: number): (number, number, number)
	local best, bestS, total = math.huge, 0, 0
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		local t = math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / (len * len), 0, 1)
		local cx, cz = a[1] + dx * t, a[2] + dz * t
		local d = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
		if d < best then
			best, bestS = d, total + len * t
		end
		total += len
	end
	return best, bestS, total
end
MapGen.alongPolyline = alongPolyline

--- The analytic height at a point. Everything else samples this.
function MapGen.rawHeight(x: number, z: number, _half: number, wall: number): number
	local F = MapGen.Features
	-- rolling ground, plus a long low swell that gives a run of hops a rhythm
	local h = 8
		+ 4.5 * math.sin(x * 0.021 + 1.3) * math.cos(z * 0.017 - 0.4)
		+ 2.5 * math.sin((x + z) * 0.043)
		+ 1.8 * math.cos((x - 2 * z) * 0.031)
		+ 1.4 * math.sin(x * 0.068 + 0.5) * math.sin(z * 0.061 + 1.1)

	-- central basin: flatten towards the spawn clearing
	local d0 = math.sqrt(x * x + z * z)
	h = lerp(h, 6, smooth(1 - d0 / 130) * 0.9)

	-- the wider world: broad, gentle hills that fade out towards the heart
	local out = MapGen.outside(x, z)
	local wide = smooth((d0 - 280) / 120)
	h += wide * (9 * math.sin(x * 0.012 + 0.6) * math.cos(z * 0.014 - 1.1) + 5 * math.sin((x - z) * 0.019 + 2) + 5)
	for _, hill in F.hills do
		local dh = math.sqrt((x - hill[1]) ^ 2 + (z - hill[2]) ^ 2)
		h += hill[4] * smooth(1 - dh / hill[3]) ^ 1.2
	end
	-- Sunspire Hill: a flat summit and long even slopes on every side
	local ss = F.sunspire
	local dsun = math.sqrt((x - ss.x) ^ 2 + (z - ss.z) ^ 2)
	h += ss.rise * smooth(1 - (dsun - ss.top) / (ss.r - ss.top)) ^ 1.1
	-- Stoneglen: a shallow bowl
	local gl = F.glen
	local dgl = math.sqrt((x - gl.x) ^ 2 + (z - gl.z) ^ 2)
	h -= gl.depth * smooth(1 - dgl / gl.r)

	-- the Elder Hill: a broad round rise south-west of spawn
	local eh = F.elderHill
	local de = math.sqrt((x - eh.x) ^ 2 + (z - eh.z) ^ 2)
	h += eh.rise * smooth(1 - de / eh.r) ^ 1.3

	-- the Highwatch plateau. Its south edge wanders (but not at x = 0, where the
	-- face is a known landmark), it has rounded flanks, and two long ramps; ramp A
	-- stays dead straight along x = -95.
	local wander = 13 * math.sin(x * 0.021 + 0.6) * smooth((math.abs(x) - 30) / 50)
	-- its east and west flanks steep in the south, a broad bank in the north;
	-- its north side one long slope down to the North Vale
	local fall = lerp(16, 64, smooth((z - 230) / 70))
	local inX = smooth((232 + 9 * math.sin(z * 0.031) - math.abs(x) + (fall - 16) / 2) / fall)
	local inZNorth = smooth((432 - z) / 100)
	local edge = smooth((z - 150 - wander) / 14)
	-- broad shoulders, so a ramp reads as a slope up the hill, not a causeway
	local rampA = smooth(1 - (math.abs(x + 95) - 8) / 26) * smooth((z - 70) / 88)
	local rampB = smooth(1 - (math.abs(x - 115 - 10 * math.sin(z * 0.03)) - 8) / 26) * smooth((z - 70) / 88)
	local plateau = math.max(edge, rampA, rampB) * inX * inZNorth
	local top = 36 + 2.2 * math.sin(x * 0.047 + 0.3) * math.cos(z * 0.041)
	local wk = F.watchKnoll
	local dk = math.sqrt((x - wk.x) ^ 2 + (z - wk.z) ^ 2)
	top += wk.rise * smooth(1 - dk / wk.r) ^ 1.5
	h += top * plateau

	-- the Ridge Run: a sinuous spine with a long slideable western face
	local spine = 235 + 16 * math.sin(z * 0.013 + 0.8)
	local rx = (x - spine) / 42
	h += (26 + 4 * math.sin(z * 0.037)) * math.exp(-rx * rx) * smooth((300 - math.abs(z + 20)) / 70)

	-- the Terraced Gardens: four curved steps, each riser steep but walkable,
	-- with one smooth ramp running straight through them all
	local tz = -z - 130 + 16 * math.sin(x * 0.018 + 0.4)
	if tz > 0 then
		local t = tz / 42
		local whole = math.floor(t)
		local frac = t - whole
		local steps = math.min(whole + smooth(frac / 0.3), 4)
		local ramp = smooth(1 - math.abs(x - F.gardenRampX) / F.gardenRampHalf)
		steps = lerp(steps, math.min(t, 4), ramp)
		-- gentle flanks east and west, and a long descent south to Stoneglen
		h += 9 * steps * smooth((290 - math.abs(x)) / 80) * smooth((z + 452) / 110)
	end

	-- the Mirewood dell: a shallow bowl...
	local dx, dz = x + 225, z - 25
	local dd = math.sqrt(dx * dx + dz * dz)
	h -= 7 * smooth(1 - dd / 75)
	-- ...with the Moonwell in it, and the falls' pool at the foot of the
	-- Highwatch: shallow pools you wade across. A low lip keeps the ground round
	-- each above its water, so the surface never shows outside the shore.
	for _, pond in { F.pond, F.falls } do
		local dp = math.sqrt((x - pond.x) ^ 2 + (z - pond.z) ^ 2)
		if dp < pond.r + pond.lip then
			h = math.max(h, lerp(pond.level + 1.2, h, smooth((dp - pond.r) / pond.lip)))
		end
		local floor = pond.level - pond.depth * smooth(1 - dp / pond.r) - 0.3
		h = lerp(h, floor, smooth(1 - (dp - pond.r + 3) / 6))
	end

	-- the Thunder Chute: a graded half-pipe cut down the plateau's shoulder
	local ch = F.chute
	local dc, sc, lc = alongPolyline(ch.points, x, z)
	if dc < ch.core + ch.shoulder then
		-- steep enough to build a slide's speed (over about 0.2 the slide gains),
		-- then a gentler run-out that carries it into the basin
		local t = sc / lc
		local drop = if t < ch.steep then t / ch.steep * 0.6 else 0.6 + (t - ch.steep) / (1 - ch.steep) * 0.4
		local grade = lerp(ch.top, ch.bottom, drop)
		local pipe = 2.2 * (math.min(dc, ch.core) / ch.core) ^ 2 -- banked: the edges ride higher
		local w = 1 - smooth((dc - ch.core) / ch.shoulder)
		h = lerp(h, grade + pipe, w)
	end

	-- the Fallen Giant's gully: a valley with walkable banks
	local gu = F.gully
	local dg = alongPolyline(gu.points, x, z)
	if dg < gu.core + gu.bank then
		h -= gu.depth * (1 - smooth((dg - gu.core) / gu.bank))
	end

	-- the mountains: rising straight from the playable edge, so there is no
	-- reachable shelf between the world and the backdrop
	if out > 0 then
		h = lerp(h, mountain(x, z, out), smooth(out / 46))
	end

	return math.clamp(h, 2, wall)
end

--- Sample the whole map once.
function MapGen.build(size: number, cell: number, wall: number): Map
	local half = size / 2
	local n = math.floor(size / cell) + 1
	local heights = table.create(n * n, 0)
	local play = table.create(n * n, false)
	for iz = 0, n - 1 do
		local z = -half + iz * cell
		for ix = 0, n - 1 do
			local x = -half + ix * cell
			heights[iz * n + ix + 1] = MapGen.rawHeight(x, z, half, wall)
			play[iz * n + ix + 1] = MapGen.outside(x, z) < -MapGen.PLAY_MARGIN
		end
	end
	return { size = size, half = half, cell = cell, n = n, heights = heights, wall = wall, play = play }
end

--- Height at a point, bilinear over the sampled grid, clamped to the map.
function MapGen.heightAt(map: Map, x: number, z: number): number
	local fx = math.clamp((x + map.half) / map.cell, 0, map.n - 1.001)
	local fz = math.clamp((z + map.half) / map.cell, 0, map.n - 1.001)
	local ix, iz = math.floor(fx), math.floor(fz)
	local tx, tz = fx - ix, fz - iz
	local n = map.n
	local i = iz * n + ix + 1
	local h00, h10 = map.heights[i], map.heights[i + 1]
	local h01, h11 = map.heights[i + n], map.heights[i + n + 1]
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)
end

--- Steepness at a point as rise over run.
function MapGen.slopeAt(map: Map, x: number, z: number): number
	local c = map.cell
	local gx = (MapGen.heightAt(map, x + c, z) - MapGen.heightAt(map, x - c, z)) / (2 * c)
	local gz = (MapGen.heightAt(map, x, z + c) - MapGen.heightAt(map, x, z - c)) / (2 * c)
	return math.sqrt(gx * gx + gz * gz)
end

--- Downhill direction (unit x, z) and steepness at a point.
function MapGen.downhill(map: Map, x: number, z: number): (number, number, number)
	local c = map.cell
	local gx = (MapGen.heightAt(map, x + c, z) - MapGen.heightAt(map, x - c, z)) / (2 * c)
	local gz = (MapGen.heightAt(map, x, z + c) - MapGen.heightAt(map, x, z - c)) / (2 * c)
	local m = math.sqrt(gx * gx + gz * gz)
	if m < 1e-4 then
		return 0, 0, 0
	end
	return -gx / m, -gz / m, m
end

--- Can a ground enemy step from (x, z) to (nx, nz)? Not up or down a cliff,
--- and not out of the playable area.
function MapGen.canStep(map: Map, x: number, z: number, nx: number, nz: number, cliffSlope: number): boolean
	-- nothing walks within 12 studs of the playable edge, let alone past it
	local px = math.clamp(math.floor((nx + map.half) / map.cell + 0.5), 0, map.n - 1)
	local pz = math.clamp(math.floor((nz + map.half) / map.cell + 0.5), 0, map.n - 1)
	if not map.play[pz * map.n + px + 1] then
		return false
	end
	local run = math.sqrt((nx - x) ^ 2 + (nz - z) ^ 2)
	if run < 1e-3 then
		return true
	end
	local blocked = map.blocked
	if blocked then
		local ix = math.floor((nx + map.half) / map.cell + 0.5)
		local iz = math.floor((nz + map.half) / map.cell + 0.5)
		if blocked[iz * map.n + ix + 1] then
			-- stepping onto a prop is refused, but an enemy already inside one may walk out
			local jx = math.floor((x + map.half) / map.cell + 0.5)
			local jz = math.floor((z + map.half) / map.cell + 0.5)
			if not blocked[jz * map.n + jx + 1] then
				return false
			end
		end
	end
	local rise = math.abs(MapGen.heightAt(map, nx, nz) - MapGen.heightAt(map, x, z))
	return rise / run <= cliffSlope
end

--- Is the straight line between two points in space clear of the ground?
--- This is a question about the terrain's shape, not about where an enemy may
--- walk (`canStep`): a steep bank that stops an enemy does not hide what is
--- standing on it, and a rise an enemy strolls over can. The line is sampled
--- every half cell and is blocked where the ground stands more than `margin`
--- above it. The two ends are not sampled, so standing on the ground is not
--- being inside it. Props are not part of the heightfield and never block.
function MapGen.sightClear(map: Map, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, margin: number?): boolean
	local run = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local steps = math.ceil(run / (map.cell * 0.5))
	local allow = margin or 0.5
	for i = 1, steps - 1 do
		local t = i / steps
		local ground = MapGen.heightAt(map, lerp(x0, x1, t), lerp(z0, z1, t))
		if ground > lerp(y0, y1, t) + allow then
			return false
		end
	end
	return true
end

-- a stable hash in [0, 1) for anchor jitter
local function hash(ix: number, iz: number, salt: number): number
	local v = math.sin(ix * 127.1 + iz * 311.7 + salt * 74.7) * 43758.5453
	return v - math.floor(v)
end

--- Candidate points for interactables: gentle ground, inside the wall, spread
--- on a jittered lattice. `d` is the distance from the spawn point (0, 0).
function MapGen.anchors(map: Map, spacing: number, maxSlope: number): { Anchor }
	local out: { Anchor } = {}
	local limit = map.half
	local steps = math.floor(limit / spacing)
	for iz = -steps, steps do
		for ix = -steps, steps do
			local x = ix * spacing + (hash(ix, iz, 1) - 0.5) * spacing * 0.6
			local z = iz * spacing + (hash(ix, iz, 2) - 0.5) * spacing * 0.6
			local d = math.sqrt(x * x + z * z)
			if d > 22 and MapGen.outside(x, z) < -40 and MapGen.slopeAt(map, x, z) <= maxSlope then
				table.insert(out, { x = x, z = z, d = d })
			end
		end
	end
	return out
end

--- Mark the samples under solid props so `canStep` refuses them.
function MapGen.block(map: Map, props: { Prop })
	local n = map.n
	local blocked: { boolean } = table.create(n * n, false)
	local function mark(px: number, pz: number, r: number)
		-- the nearest sample always: a slim trunk can sit between samples
		local cx = math.clamp(math.floor((px + map.half) / map.cell + 0.5), 0, n - 1)
		local cz = math.clamp(math.floor((pz + map.half) / map.cell + 0.5), 0, n - 1)
		blocked[cz * n + cx + 1] = true
		local x0 = math.floor((px - r + map.half) / map.cell + 0.5)
		local x1 = math.floor((px + r + map.half) / map.cell + 0.5)
		local z0 = math.floor((pz - r + map.half) / map.cell + 0.5)
		local z1 = math.floor((pz + r + map.half) / map.cell + 0.5)
		for iz = math.max(z0, 0), math.min(z1, n - 1) do
			for ix = math.max(x0, 0), math.min(x1, n - 1) do
				local sx, sz = -map.half + ix * map.cell, -map.half + iz * map.cell
				if (sx - px) ^ 2 + (sz - pz) ^ 2 <= r * r then
					blocked[iz * n + ix + 1] = true
				end
			end
		end
	end
	for _, prop in props do
		local blocks = (prop :: any).blocks
		if blocks then
			-- a landmark made of several solid pieces (columns round a platform)
			for _, b in blocks do
				mark(b[1], b[2], b[3])
			end
		elseif prop.radius > 0 then
			mark(prop.x, prop.z, prop.radius)
		end
	end
	map.blocked = blocked
end

--- Flood-fill from (fromX, fromZ) over the height grid using `canStep`.
--- Returns a boolean grid (same indexing as map.heights) of reachable samples.
function MapGen.reachable(map: Map, fromX: number, fromZ: number, cliffSlope: number): { boolean }
	local n = map.n
	local seen: { boolean } = table.create(n * n, false)
	local function index(ix: number, iz: number): number
		return iz * n + ix + 1
	end
	local sx = math.clamp(math.floor((fromX + map.half) / map.cell + 0.5), 0, n - 1)
	local sz = math.clamp(math.floor((fromZ + map.half) / map.cell + 0.5), 0, n - 1)
	local queue = { sx, sz }
	local head = 1
	seen[index(sx, sz)] = true
	while head < #queue do
		local ix, iz = queue[head], queue[head + 1]
		head += 2
		local x, z = -map.half + ix * map.cell, -map.half + iz * map.cell
		for step = 1, 4 do
			local jx = ix + (if step == 1 then 1 elseif step == 2 then -1 else 0)
			local jz = iz + (if step == 3 then 1 elseif step == 4 then -1 else 0)
			if jx >= 0 and jx < n and jz >= 0 and jz < n and not seen[index(jx, jz)] then
				local nx, nz = -map.half + jx * map.cell, -map.half + jz * map.cell
				if MapGen.canStep(map, x, z, nx, nz, cliffSlope) then
					seen[index(jx, jz)] = true
					table.insert(queue, jx)
					table.insert(queue, jz)
				end
			end
		end
	end
	return seen
end

--- Is the sample nearest (x, z) marked in a grid returned by `reachable`?
function MapGen.isReachable(map: Map, grid: { boolean }, x: number, z: number): boolean
	local ix = math.clamp(math.floor((x + map.half) / map.cell + 0.5), 0, map.n - 1)
	local iz = math.clamp(math.floor((z + map.half) / map.cell + 0.5), 0, map.n - 1)
	return grid[iz * map.n + ix + 1] == true
end

return MapGen

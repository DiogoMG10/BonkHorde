--!strict
-- MapGen - Mossy Woods as a heightfield, and the questions the game asks of it.
--
-- The map is a function of (x, z): the server simulates enemies on it without
-- physics, every client rebuilds the same heights locally, and the terrain is
-- written from it. Nothing about the layout is random per run; only what gets
-- PLACED on the anchors is. Pure.
--
-- Layout (north is +z): a central basin with the spawn clearing, a plateau to
-- the north reached by two ramps, a long ridge to the east, stepped terraces
-- to the south, a sunken dell to the west, and a cliff wall round the edge.

local MapGen = {}

export type Map = {
	size: number,
	half: number,
	cell: number,
	n: number, -- samples per side
	heights: { number },
	wall: number,
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

--- The analytic height at a point. Everything else samples this.
function MapGen.rawHeight(x: number, z: number, half: number, wall: number): number
	-- rolling ground
	local h = 8
		+ 4.5 * math.sin(x * 0.021 + 1.3) * math.cos(z * 0.017 - 0.4)
		+ 2.5 * math.sin((x + z) * 0.043)
		+ 1.8 * math.cos((x - 2 * z) * 0.031)

	-- central basin: flatten towards the spawn clearing
	local d0 = math.sqrt(x * x + z * z)
	h = lerp(h, 6, smooth(1 - d0 / 130) * 0.9)

	-- north plateau, with a hard southern edge and two long ramps cut into it
	local inX = smooth((235 - math.abs(x)) / 14)
	local inZNorth = smooth((335 - z) / 22)
	local edge = smooth((z - 150) / 14)
	local rampA = smooth(1 - math.abs(x + 95) / 20) * smooth((z - 70) / 88)
	local rampB = smooth(1 - math.abs(x - 115) / 20) * smooth((z - 70) / 88)
	local plateau = math.max(edge, rampA, rampB) * inX * inZNorth
	h += 34 * plateau

	-- east ridge: a long gaussian spine with a slideable western face
	local rx = (x - 235) / 40
	h += 26 * math.exp(-rx * rx) * smooth((300 - math.abs(z + 20)) / 70)

	-- south terraces: four steps, each riser steep but walkable
	if z < -130 then
		local t = (-z - 130) / 42
		local whole = math.floor(t)
		local frac = t - whole
		local steps = math.min(whole + smooth(frac / 0.3), 4)
		h += 9 * steps * smooth((270 - math.abs(x)) / 40)
	end

	-- west dell: a shallow bowl
	local dx, dz = x + 225, z - 25
	local dd = math.sqrt(dx * dx + dz * dz)
	h -= 7 * smooth(1 - dd / 75)

	-- boundary wall
	local e = math.max(math.abs(x), math.abs(z))
	h = lerp(h, wall, smooth((e - (half - 34)) / 22))

	return math.max(h, 2)
end

--- Sample the whole map once.
function MapGen.build(size: number, cell: number, wall: number): Map
	local half = size / 2
	local n = math.floor(size / cell) + 1
	local heights = table.create(n * n, 0)
	for iz = 0, n - 1 do
		local z = -half + iz * cell
		for ix = 0, n - 1 do
			local x = -half + ix * cell
			heights[iz * n + ix + 1] = MapGen.rawHeight(x, z, half, wall)
		end
	end
	return { size = size, half = half, cell = cell, n = n, heights = heights, wall = wall }
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
	local limit = map.half - 30
	if math.abs(nx) > limit or math.abs(nz) > limit then
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
	local limit = map.half - 50
	local steps = math.floor(limit / spacing)
	for iz = -steps, steps do
		for ix = -steps, steps do
			local x = ix * spacing + (hash(ix, iz, 1) - 0.5) * spacing * 0.6
			local z = iz * spacing + (hash(ix, iz, 2) - 0.5) * spacing * 0.6
			local d = math.sqrt(x * x + z * z)
			if d > 22 and math.abs(x) < limit and math.abs(z) < limit and MapGen.slopeAt(map, x, z) <= maxSlope then
				table.insert(out, { x = x, z = z, d = d })
			end
		end
	end
	return out
end

-- what the forest is dressed with: kind, how many per 10,000 square studs, the
-- radius an enemy must walk round (0 = walk through), and the scale range
local SCATTER = {
	{ kind = "TreeLeaning", density = 2.4, radius = 2.5, min = 0.85, max = 1.25 },
	{ kind = "TreeTwin", density = 1.8, radius = 3, min = 0.85, max = 1.2 },
	{ kind = "TreeSapling", density = 1.6, radius = 1.5, min = 0.8, max = 1.3 },
	{ kind = "Bush", density = 2.2, radius = 0, min = 0.8, max = 1.4 },
	{ kind = "BoulderLarge", density = 0.7, radius = 5, min = 0.7, max = 1.3 },
	{ kind = "BoulderFlat", density = 0.5, radius = 0, min = 0.8, max = 1.3 },
	{ kind = "RockSmall", density = 1.4, radius = 0, min = 0.7, max = 1.5 },
	{ kind = "FallenLog", density = 0.35, radius = 0, min = 0.9, max = 1.2 },
	{ kind = "Stump", density = 0.5, radius = 0, min = 0.8, max = 1.2 },
	{ kind = "LanternPost", density = 0.25, radius = 0, min = 1, max = 1 },
	{ kind = "RuinWall", density = 0.12, radius = 0, min = 0.9, max = 1.1 },
	{ kind = "RuinArch", density = 0.06, radius = 0, min = 1, max = 1 },
	{ kind = "RuinTower", density = 0.05, radius = 9, min = 0.9, max = 1.1 },
}

--- Where the scenery goes. Deterministic. Keeps clear of the spawn clearing, of
--- every anchor (so nothing grows through a chest) and of steep ground.
function MapGen.props(map: Map, anchors: { Anchor }): { Prop }
	local out: { Prop } = {}
	local limit = map.half - 44
	local area = (2 * limit) * (2 * limit) / 10000
	for index, row in SCATTER do
		local count = math.floor(row.density * area + 0.5)
		local placed, tries = 0, 0
		while placed < count and tries < count * 12 do
			tries += 1
			local x = (hash(tries, index, 11) * 2 - 1) * limit
			local z = (hash(tries, index, 23) * 2 - 1) * limit
			if x * x + z * z < 42 * 42 or MapGen.slopeAt(map, x, z) > 0.45 then
				continue
			end
			local clear = true
			for _, a in anchors do
				if (a.x - x) ^ 2 + (a.z - z) ^ 2 < (9 + row.radius) ^ 2 then
					clear = false
					break
				end
			end
			if clear and row.radius > 0 then
				-- solid props keep their distance from each other so there is always a way through
				for _, other in out do
					if other.radius > 0 and (other.x - x) ^ 2 + (other.z - z) ^ 2 < (other.radius + row.radius + 7) ^ 2 then
						clear = false
						break
					end
				end
			end
			if clear then
				placed += 1
				table.insert(out, {
					kind = row.kind,
					x = x,
					z = z,
					yaw = hash(tries, index, 37) * math.pi * 2,
					scale = row.min + hash(tries, index, 41) * (row.max - row.min),
					radius = row.radius * (row.min + hash(tries, index, 41) * (row.max - row.min)),
				})
			end
		end
	end
	return out
end

--- Mark the samples under solid props so `canStep` refuses them.
function MapGen.block(map: Map, props: { Prop })
	local n = map.n
	local blocked: { boolean } = table.create(n * n, false)
	for _, prop in props do
		if prop.radius > 0 then
			local r = prop.radius
			local x0 = math.floor((prop.x - r + map.half) / map.cell + 0.5)
			local x1 = math.floor((prop.x + r + map.half) / map.cell + 0.5)
			local z0 = math.floor((prop.z - r + map.half) / map.cell + 0.5)
			local z1 = math.floor((prop.z + r + map.half) / map.cell + 0.5)
			for iz = math.max(z0, 0), math.min(z1, n - 1) do
				for ix = math.max(x0, 0), math.min(x1, n - 1) do
					local sx, sz = -map.half + ix * map.cell, -map.half + iz * map.cell
					if (sx - prop.x) ^ 2 + (sz - prop.z) ^ 2 <= r * r then
						blocked[iz * n + ix + 1] = true
					end
				end
			end
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

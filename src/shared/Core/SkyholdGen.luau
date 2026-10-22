--!strict
-- SkyholdGen - the island hub's ground as a pure function: its rim, its height
-- and its surface at any island-local point. The server writes Roblox Terrain
-- from it (Skyhold/Builder), the Blender kit hangs the cliffs from the same rim
-- (tools/art/skyhold_plan.luau exports it) and the specs walk it. Pure.

local SkyholdGen = {}

export type Point = { x: number, z: number }
export type Poly = { Point }

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- a small deterministic value noise, so the meadow rolls the same everywhere
local function hash(ix: number, iz: number, seed: number): number
	local n = math.sin(ix * 127.1 + iz * 311.7 + seed * 74.7) * 43758.5453
	return n - math.floor(n)
end

function SkyholdGen.noise(x: number, z: number, seed: number): number
	local ix, iz = math.floor(x), math.floor(z)
	local fx, fz = x - ix, z - iz
	local sx, sz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
	local a, b = hash(ix, iz, seed), hash(ix + 1, iz, seed)
	local c, d = hash(ix, iz + 1, seed), hash(ix + 1, iz + 1, seed)
	return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sz -- 0..1
end

--- A closed Catmull-Rom curve through `points` ({ x, z } pairs), sampled about
--- every `step` studs.
function SkyholdGen.curve(points: { { number } }, step: number): Poly
	local out: Poly = {}
	local n = #points
	for i = 1, n do
		local p0 = points[(i - 2) % n + 1]
		local p1 = points[i]
		local p2 = points[i % n + 1]
		local p3 = points[(i + 1) % n + 1]
		local length = math.sqrt((p2[1] - p1[1]) ^ 2 + (p2[2] - p1[2]) ^ 2)
		local count = math.max(1, math.ceil(length / step))
		for k = 0, count - 1 do
			local t = k / count
			local t2, t3 = t * t, t * t * t
			local function axis(a: number, b: number, c: number, d: number): number
				return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
			end
			table.insert(out, {
				x = axis(p0[1], p1[1], p2[1], p3[1]),
				z = axis(p0[2], p1[2], p2[2], p3[2]),
			})
		end
	end
	return out
end

function SkyholdGen.inside(poly: Poly, x: number, z: number): boolean
	local inside = false
	local j = #poly
	for i = 1, #poly do
		local a, b = poly[i], poly[j]
		if (a.z > z) ~= (b.z > z) and x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function segmentDistance(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) else 0
	local cx, cz = ax + dx * t - px, az + dz * t - pz
	return math.sqrt(cx * cx + cz * cz)
end

--- Distance from (x, z) to the nearest point of the closed polygon's rim.
function SkyholdGen.rimDistance(poly: Poly, x: number, z: number): number
	local best = math.huge
	local j = #poly
	for i = 1, #poly do
		local a, b = poly[j], poly[i]
		local d = segmentDistance(x, z, a.x, a.z, b.x, b.z)
		if d < best then
			best = d
		end
		j = i
	end
	return best
end

local function pathDistance(points: { { number } }, x: number, z: number): number
	local best = math.huge
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local d = segmentDistance(x, z, a[1], a[2], b[1], b[2])
		if d < best then
			best = d
		end
	end
	return best
end

export type Plan = {
	cfg: any,
	outline: Poly,
	islet: Poly,
}

function SkyholdGen.build(cfg: any): Plan
	return {
		cfg = cfg,
		outline = SkyholdGen.curve(cfg.Outline, 3),
		islet = SkyholdGen.curve(cfg.Islet, 3),
	}
end

--- Which ground (x, z) is on: "main", "islet" or nil (open sky).
function SkyholdGen.land(plan: Plan, x: number, z: number): string?
	if SkyholdGen.inside(plan.outline, x, z) then
		return "main"
	elseif SkyholdGen.inside(plan.islet, x, z) then
		return "islet"
	end
	return nil
end

local function plateauHeight(p, x: number, z: number): number
	local nx, nz = (x - p.x) / p.rx, (z - p.z) / p.rz
	local d = math.sqrt(nx * nx + nz * nz)
	if d <= 1 then
		return p.height
	end
	-- past the flat top: studs beyond its rim, measured along the smaller radius
	local beyond = (d - 1) * math.min(p.rx, p.rz)
	return p.height * (1 - smoothstep(beyond / p.blend))
end

--- The ground's height (island-local y) at (x, z); nil off the island.
function SkyholdGen.heightAt(plan: Plan, x: number, z: number): number?
	local land = SkyholdGen.land(plan, x, z)
	if not land then
		return nil
	end
	local cfg = plan.cfg
	local rim = if land == "main" then plan.outline else plan.islet
	local base = if land == "main" then 0 else cfg.IsletHeight
	local h = base + (SkyholdGen.noise(x / 26, z / 26, 7) - 0.5) * 2 * cfg.MeadowRoll
	if land == "main" then
		for _, p in cfg.Plateaus do
			h = math.max(h, plateauHeight(p, x, z))
		end
	end
	local edge = SkyholdGen.rimDistance(rim, x, z)
	if edge < cfg.RimWidth then
		local k = 1 - edge / cfg.RimWidth
		h -= cfg.RimDip * k * k
	end
	return h
end

--- The ground's surface key (Config/Wardwood.Surfaces) at (x, z).
function SkyholdGen.surfaceAt(plan: Plan, x: number, z: number): string
	local cfg = plan.cfg
	for _, pave in cfg.Paving do
		local under = if pave.r
			then (x - pave.x) ^ 2 + (z - pave.z) ^ 2 <= pave.r * pave.r
			else x >= pave.x0 and x <= pave.x1 and z >= pave.z0 and z <= pave.z1
		if under then
			return "Path"
		end
	end
	for _, path in cfg.Paths do
		if pathDistance(path.points, x, z) <= path.width / 2 then
			return "Path"
		end
	end
	local tree = cfg.Tree
	if (x - tree.x) ^ 2 + (z - tree.z) ^ 2 < 18 * 18 then
		return "ForestFloor"
	end
	return "Turf"
end

--- A point given in island-local studs, in the world.
function SkyholdGen.world(cfg: any, x: number, y: number, z: number): (number, number, number)
	local o = cfg.Origin
	return o[1] + x, o[2] + y, o[3] + z
end

return SkyholdGen

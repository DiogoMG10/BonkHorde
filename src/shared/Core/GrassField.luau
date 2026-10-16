--!strict
-- GrassField - static 3D grass in world-aligned chunks (M3.B, grass option B).
--
-- One blade per cell of a single global grid (`spacing` studs, turned against
-- the world's axes), anywhere within its cell: the density is the same
-- everywhere, there are no patches to overlap or leave gaps, and a blade
-- belongs to exactly one chunk (the one its foot stands in), so chunks meet
-- without seams. Each blade stands on
-- the terrain where it grows (0.2-0.5 studs above it, its foot a little under
-- so voxel terrain never leaves one floating), so a chunk is its own mesh,
-- built once by the server (Wardwood/GrassChunks) and left in place: nothing
-- follows the player, Roblox streams it like any other part.
--
-- Blades come in three tones by a per-blade hash, the same everywhere, so the
-- field reads as one meadow, never as islands of colour. Pure, so the specs
-- can check coverage and seams headless.

local Blueprints = require(script and script.Parent.Blueprints or "./Blueprints")
local MapGen = require(script and script.Parent.MapGen or "./MapGen")
local World = require(script and script.Parent.World or "./World")

local GrassField = {}

-- the blade tones, multiplying the grass colour: dark, mid, light
GrassField.Tones = { 0.78, 1, 1.12 }
GrassField.ToneNames = { "bladesDark", "bladesMid", "bladesLight" }

local GRASSY = { Carpet = true, Meadow = true, Lush = true, Turf = true }

export type Mesh = {
	verts: number,
	tris: number,
	pos: { number },
	nrm: { number },
	idx: { number },
	centre: { number },
	size: { number },
}

local hash = Blueprints.hash
local ANGLE = math.rad(27) -- the blade grid's turn against the world's axes

--- Whether grass grows at a point (the same test for every chunk).
function GrassField.grassy(world: World.World, x: number, z: number, mode: string): boolean
	return MapGen.outside(x, z) < -2 and GRASSY[World.surface(world, x, z, mode)] == true
end

--- The blades of the chunk whose corner is (x0, z0), `size` studs a side, as
--- three meshes (one per tone) in the shape ArtKit bakes: positions centred
--- on each mesh's box. Every chunk walks the same global grid.
function GrassField.chunk(world: World.World, x0: number, z0: number, size: number, spacing: number, mode: string): { Mesh }
	local map = world.map
	local raw = {}
	for t = 1, 3 do
		raw[t] = { pos = {}, nrm = {}, idx = {}, n = 0 }
	end
	-- the ground's grassiness, sampled every 2 studs (terrain materials change
	-- on 4-stud voxels; a blade looks up its sample)
	local grassyAt: { [number]: boolean } = {}
	local function grassy(x: number, z: number): boolean
		local key = math.floor(x / 2) * 65536 + math.floor(z / 2)
		local known = grassyAt[key]
		if known == nil then
			known = GrassField.grassy(world, (math.floor(x / 2) + 0.5) * 2, (math.floor(z / 2) + 0.5) * 2, mode)
			grassyAt[key] = known
		end
		return known
	end
	-- the grid runs at an angle to the world, and every blade wanders anywhere
	-- in its cell: no row lines up with a path, a chunk edge or the camera. A
	-- blade belongs to the chunk its foot stands in.
	local c, sn = math.cos(ANGLE), math.sin(ANGLE)
	local u0, u1, v0, v1 = math.huge, -math.huge, math.huge, -math.huge
	for _, corner in { { x0, z0 }, { x0 + size, z0 }, { x0, z0 + size }, { x0 + size, z0 + size } } do
		local u = corner[1] * c + corner[2] * sn
		local v = -corner[1] * sn + corner[2] * c
		u0, u1, v0, v1 = math.min(u0, u), math.max(u1, u), math.min(v0, v), math.max(v1, v)
	end
	for gi = math.floor(u0 / spacing) - 1, math.floor(u1 / spacing) + 1 do
		for gj = math.floor(v0 / spacing) - 1, math.floor(v1 / spacing) + 1 do
			local u = (gi + hash(gi, gj, 3)) * spacing
			local v = (gj + hash(gi, gj, 5)) * spacing
			local x, z = u * c - v * sn, u * sn + v * c
			if x >= x0 and x < x0 + size and z >= z0 and z < z0 + size and grassy(x, z) then
				local ground = MapGen.heightAt(map, x, z)
				local h = 0.2 + 0.3 * hash(gi, gj, 7) ^ 1.5
				local w = 0.1 + 0.06 * hash(gi, gj, 11)
				local face = hash(gi, gj, 13) * math.pi * 2
				local lean = (0.1 + 0.35 * hash(gi, gj, 17)) * h
				local la = hash(gi, gj, 19) * math.pi * 2
				local sx, sz = math.cos(face) * w * 0.5, math.sin(face) * w * 0.5
				local fx, fz = -math.sin(face), math.cos(face)
				-- lit toward the way it faces, so the sun catches some blades and not others
				local nx, ny, nz = fx * 0.55 + math.cos(la) * 0.12, 0.62, fz * 0.55 + math.sin(la) * 0.12
				local nl = math.sqrt(nx * nx + ny * ny + nz * nz)
				nx, ny, nz = nx / nl, ny / nl, nz / nl
				local roll = hash(gi, gj, 23)
				local m = raw[if roll < 0.3 then 1 elseif roll < 0.8 then 2 else 3]
				local base = m.n
				local p, nrm = m.pos, m.nrm
				for _, v in
					{
						{ x - sx, ground - 0.2, z - sz },
						{ x + sx, ground - 0.2, z + sz },
						{ x + math.cos(la) * lean, ground + h, z + math.sin(la) * lean },
					}
				do
					table.insert(p, v[1])
					table.insert(p, v[2])
					table.insert(p, v[3])
					table.insert(nrm, nx)
					table.insert(nrm, ny)
					table.insert(nrm, nz)
				end
				-- both faces: a blade seen from behind is still a blade
				for _, k in { base, base + 1, base + 2, base + 1, base, base + 2 } do
					table.insert(m.idx, k)
				end
				m.n += 3
			end
		end
	end
	local out = {}
	for t = 1, 3 do
		local m = raw[t]
		local lo = { math.huge, math.huge, math.huge }
		local hi = { -math.huge, -math.huge, -math.huge }
		for v = 0, m.n - 1 do
			for k = 1, 3 do
				local c = m.pos[v * 3 + k]
				lo[k] = math.min(lo[k], c)
				hi[k] = math.max(hi[k], c)
			end
		end
		local centre = { 0, 0, 0 }
		if m.n > 0 then
			centre = { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }
			for v = 0, m.n - 1 do
				for k = 1, 3 do
					m.pos[v * 3 + k] -= centre[k]
				end
			end
		end
		out[t] = {
			verts = m.n,
			tris = #m.idx // 3,
			pos = m.pos,
			nrm = m.nrm,
			idx = m.idx,
			centre = centre,
			size = if m.n > 0 then { hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3] } else { 0, 0, 0 },
		}
	end
	return out
end

return GrassField

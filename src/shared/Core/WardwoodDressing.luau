--!strict
-- WardwoodDressing - where the Wardwood prototype's scenery goes. Pure.
--
-- Takes the normal MossyWoods prop list and replaces the props inside one
-- region with Wardwood blockout props: a ward landmark (a ruined tile platform
-- round a brazier, with pillars and a ward stone), a dense forest band to the
-- west, a looser ring of trunks round the spawn clearing, mossy slabs and ferns.
--
-- It keeps every promise MapGen.props keeps: nothing solid near an anchor (so
-- nothing grows through a chest), solid props a walkable gap apart, nothing on
-- steep ground, the spawn clearing open. It also keeps the prototype's own
-- rules: paths and viewpoints free of trunks and rocks. The heightfield is not
-- touched, so the enemy simulation runs on the same ground.

local MapGen = require(script and script.Parent.MapGen or "./MapGen")

type Map = MapGen.Map
type Prop = MapGen.Prop
type Anchor = MapGen.Anchor

local WardwoodDressing = {}

export type Ward = { x: number, z: number, yaw: number }

-- a stable hash in [0, 1), salted apart from MapGen's
local function hash(ix: number, iz: number, salt: number): number
	local v = math.sin(ix * 91.7 + iz * 237.3 + salt * 53.1) * 31871.917
	return v - math.floor(v)
end

local function distToSegment(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) else 0
	local cx, cz = ax + t * dx, az + t * dz
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

--- Is (x, z) inside the dressed region?
function WardwoodDressing.inRegion(cfg: any, x: number, z: number): boolean
	local r = cfg.Region
	return x >= r.minX and x <= r.maxX and z >= r.minZ and z <= r.maxZ
end

--- How far (x, z) is from the nearest path centre line.
function WardwoodDressing.pathDistance(cfg: any, x: number, z: number): number
	local best = math.huge
	for _, path in cfg.Paths do
		for i = 1, #path - 1 do
			local a, b = path[i], path[i + 1]
			best = math.min(best, distToSegment(x, z, a[1], a[2], b[1], b[2]))
		end
	end
	return best
end

--- Where the ward's pieces sit, in world space, for a centre and a facing.
--- The ward stone stands on the far side from spawn; one pillar is broken.
function WardwoodDressing.wardPieces(cfg: any, ward: Ward): { Prop }
	local out: { Prop } = {}
	local cosY, sinY = math.cos(ward.yaw), math.sin(ward.yaw)
	local function at(lx: number, lz: number): (number, number)
		-- local +z points away from spawn
		return ward.x + lx * cosY + lz * sinY, ward.z - lx * sinY + lz * cosY
	end
	local n, size = cfg.WardTiles, cfg.WardTileSize
	local half = (n - 1) * size / 2
	for iz = 0, n - 1 do
		for ix = 0, n - 1 do
			-- a ruin: a few tiles are gone
			if hash(ix, iz, 3) < 0.16 and not (ix == (n - 1) / 2 and iz == (n - 1) / 2) then
				continue
			end
			local x, z = at(-half + ix * size, -half + iz * size)
			table.insert(out, { kind = "WW_Tile", x = x, z = z, yaw = ward.yaw, scale = 1, radius = 0 })
		end
	end
	local corners = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
	for i, c in corners do
		local x, z = at(c[1] * half, c[2] * half)
		local kind = if i == 2 then "WW_PillarBroken" else "WW_Pillar"
		table.insert(out, { kind = kind, x = x, z = z, yaw = ward.yaw, scale = 1, radius = cfg.WardPillarRadius })
	end
	table.insert(out, { kind = "WW_Brazier", x = ward.x, z = ward.z, yaw = ward.yaw, scale = 1, radius = cfg.WardBrazierRadius })
	local sx, sz = at(0, half + size)
	table.insert(out, { kind = "WW_WardStone", x = sx, z = sz, yaw = ward.yaw, scale = 1, radius = cfg.WardStoneRadius })
	return out
end

local function clearOfAnchors(anchors: { Anchor }, clearance: number, x: number, z: number, radius: number): boolean
	local need = clearance + radius
	for _, a in anchors do
		if (a.x - x) ^ 2 + (a.z - z) ^ 2 < need * need then
			return false
		end
	end
	return true
end

local function clearOfSolids(cfg: any, list: { Prop }, x: number, z: number, radius: number): boolean
	for _, other in list do
		if other.radius > 0 then
			local need = other.radius + radius + cfg.TrunkGap
			if (other.x - x) ^ 2 + (other.z - z) ^ 2 < need * need then
				return false
			end
		end
	end
	return true
end

local function nearViewpoint(cfg: any, x: number, z: number, radius: number): boolean
	for _, v in cfg.Viewpoints do
		if (v.x - x) ^ 2 + (v.z - z) ^ 2 < (6 + radius) ^ 2 then
			return true
		end
	end
	return false
end

--- Find a spot for the ward near cfg.WardCenter where every solid piece clears
--- the anchors by cfg.WardAnchorClearance and no piece comes within
--- cfg.SpawnKeepClear of spawn. Returns nil when no spot within 40 studs works.
function WardwoodDressing.placeWard(cfg: any, map: Map, anchors: { Anchor }): Ward?
	local cx, cz = cfg.WardCenter[1], cfg.WardCenter[2]
	for ring = 0, 10 do
		local r = ring * 4
		local steps = if ring == 0 then 1 else 12
		for k = 0, steps - 1 do
			local a = k / steps * math.pi * 2
			local x, z = cx + r * math.cos(a), cz + r * math.sin(a)
			if MapGen.slopeAt(map, x, z) > cfg.MaxSlope then
				continue
			end
			-- face away from spawn: local +z points from spawn through the centre
			local ward = { x = x, z = z, yaw = math.atan2(x, z) }
			local ok = true
			local keep = cfg.SpawnKeepClear + cfg.WardTileSize * 0.75 -- a tile's half diagonal, rounded up
			for _, piece in WardwoodDressing.wardPieces(cfg, ward) do
				local inClearing = piece.x * piece.x + piece.z * piece.z < keep * keep
				local onAnchor = piece.radius > 0 and not clearOfAnchors(anchors, cfg.WardAnchorClearance, piece.x, piece.z, piece.radius)
				if inClearing or onAnchor then
					ok = false
					break
				end
			end
			if ok then
				return ward
			end
		end
	end
	return nil
end

--- The full prop list for a Wardwood server: MossyWoods outside the region,
--- Wardwood inside it. Deterministic. Also returns the ward (nil if unplaced).
function WardwoodDressing.build(cfg: any, map: Map, anchors: { Anchor }, baseProps: { Prop }): ({ Prop }, Ward?)
	local out: { Prop } = {}
	for _, prop in baseProps do
		if not WardwoodDressing.inRegion(cfg, prop.x, prop.z) then
			table.insert(out, prop)
		end
	end

	local ward = WardwoodDressing.placeWard(cfg, map, anchors)
	local wardReach = 0
	if ward then
		for _, piece in WardwoodDressing.wardPieces(cfg, ward) do
			table.insert(out, piece)
		end
		wardReach = (cfg.WardTiles + 1) * cfg.WardTileSize / 2 * math.sqrt(2)
	end
	local function onWard(x: number, z: number, radius: number): boolean
		return ward ~= nil and (ward.x - x) ^ 2 + (ward.z - z) ^ 2 < (wardReach + radius + 2) ^ 2
	end

	local reg = cfg.Region
	local function solidOk(x: number, z: number, radius: number, clearing: number): boolean
		if not WardwoodDressing.inRegion(cfg, x, z) then
			return false
		end
		if x * x + z * z < (clearing + radius) ^ 2 then
			return false
		end
		if MapGen.slopeAt(map, x, z) > cfg.MaxSlope then
			return false
		end
		if WardwoodDressing.pathDistance(cfg, x, z) < cfg.PathHalfWidth + radius then
			return false
		end
		if onWard(x, z, radius) or nearViewpoint(cfg, x, z, radius) then
			return false
		end
		return clearOfAnchors(anchors, cfg.AnchorClearance, x, z, radius) and clearOfSolids(cfg, out, x, z, radius)
	end

	-- trunks on a jittered lattice: dense in the band, loose in the ring
	local grid = cfg.TrunkGrid
	local nx = math.floor((reg.maxX - reg.minX) / grid)
	local nz = math.floor((reg.maxZ - reg.minZ) / grid)
	local lo, hi = cfg.TrunkScale[1], cfg.TrunkScale[2]
	for iz = 0, nz - 1 do
		for ix = 0, nx - 1 do
			local x = reg.minX + (ix + 0.5) * grid + (hash(ix, iz, 5) - 0.5) * grid * 0.7
			local z = reg.minZ + (iz + 0.5) * grid + (hash(ix, iz, 7) - 0.5) * grid * 0.7
			local keep = if x < cfg.BandMaxX then cfg.TrunkKeepBand else cfg.TrunkKeepRing
			if hash(ix, iz, 9) >= keep then
				continue
			end
			local scale = lo + hash(ix, iz, 13) * (hi - lo)
			local radius = cfg.TrunkRadius * scale
			-- the ring starts a little back from the clearing's edge
			if solidOk(x, z, radius, cfg.ClearingRadius + 14) then
				table.insert(out, { kind = "WW_Trunk", x = x, z = z, yaw = hash(ix, iz, 17) * math.pi * 2, scale = scale, radius = radius })
			end
		end
	end

	-- mossy slabs at the clearing's edge and in the band
	local placed, tries = 0, 0
	while placed < cfg.SlabCount and tries < cfg.SlabCount * 40 do
		tries += 1
		local x = reg.minX + hash(tries, 1, 19) * (reg.maxX - reg.minX)
		local z = reg.minZ + hash(tries, 2, 23) * (reg.maxZ - reg.minZ)
		local scale = 0.7 + hash(tries, 3, 29) * 0.5
		local radius = cfg.SlabRadius * scale
		if solidOk(x, z, radius, cfg.ClearingRadius + 4) then
			placed += 1
			table.insert(out, { kind = "WW_Slab", x = x, z = z, yaw = hash(tries, 4, 31) * math.pi * 2, scale = scale, radius = radius })
		end
	end

	-- ferns: walk-through ground cover, kept out of the clearing and off the paths
	placed, tries = 0, 0
	while placed < cfg.FernCount and tries < cfg.FernCount * 20 do
		tries += 1
		local x = reg.minX + hash(tries, 5, 37) * (reg.maxX - reg.minX)
		local z = reg.minZ + hash(tries, 6, 41) * (reg.maxZ - reg.minZ)
		if
			x * x + z * z >= (cfg.ClearingRadius + 16) ^ 2
			and WardwoodDressing.pathDistance(cfg, x, z) >= cfg.PathHalfWidth
			and not onWard(x, z, 0)
			and MapGen.slopeAt(map, x, z) <= cfg.MaxSlope
			and clearOfAnchors(anchors, cfg.AnchorClearance, x, z, 0)
		then
			placed += 1
			table.insert(out, {
				kind = "WW_Fern",
				x = x,
				z = z,
				yaw = hash(tries, 7, 43) * math.pi * 2,
				scale = 0.8 + hash(tries, 8, 47) * 0.6,
				radius = 0,
			})
		end
	end

	return out, ward
end

return WardwoodDressing

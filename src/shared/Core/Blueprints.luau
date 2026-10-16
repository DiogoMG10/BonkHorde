--!strict
-- Blueprints - the Wardwood's part-built scenery, as data. Pure.
--
-- Each blueprint returns the primitives of one prop in its own space: +y up,
-- origin on the ground at the prop's position, before the prop's yaw and scale.
-- MapService turns them into Parts; tools/map/export_world.luau hands the same
-- list to the Blender preview, so the two cannot drift apart.
--
-- A primitive:
--   shape     "block" | "ball" | "cylinder" (axis along local x) | "wedge"
--             (vertical face at local +z, slope rising from -z to +z: measured
--             in Studio, see the roblox-map skill); no corner wedges, whose
--             orientation was never measured
--             | "ellipsoid": a sphere stretched to `size` (a block Part with a
--             sphere SpecialMesh), for foliage
--   size      { x, y, z }
--   pos       { x, y, z }        centre
--   rot       { yaw, pitch, roll } in degrees, applied yaw (about y) first,
--             then pitch (about x), then roll (about z)
--   color     { r, g, b }        0..255
--   material  a Roblox material name
--   collide   the hero bumps into it (default false: scenery is walked through)
--   shadow    casts a shadow (default true)
--   neon      glows
--   light     { color, brightness, range }
--   tag       "Flame" | "Rune" | "Glow" | "Pollen": the client adds the effect
--
-- `g(lx, lz)` gives the ground height under a local point relative to the
-- prop's own ground, for the pieces that have to follow the slope.

export type Prim = {
	shape: string,
	size: { number },
	pos: { number },
	rot: { number }?,
	color: { number },
	material: string,
	collide: boolean?,
	shadow: boolean?,
	neon: boolean?,
	light: any?,
	tag: string?,
}

local Blueprints = {}

-- ------------------------------------------------------------------ palette

local C = {
	bark = { 104, 76, 56 },
	barkDark = { 74, 56, 44 },
	barkGrey = { 118, 108, 96 },
	pineBark = { 138, 92, 64 },
	birch = { 232, 228, 212 },
	birchMark = { 52, 50, 48 },
	stone = { 128, 128, 120 },
	stoneLight = { 150, 148, 136 },
	stoneDark = { 96, 100, 98 },
	moss = { 96, 134, 58 },
	ember = { 255, 150, 60 },
	rune = { 255, 176, 92 },
	runeTeal = { 96, 230, 210 },
	fern = { 74, 122, 56 },
	fernLight = { 98, 146, 66 },
	stem = { 236, 226, 200 },
	iron = { 58, 56, 54 },
}

-- a stable hash in [0, 1) for per-prop variation
local function hash(a: number, b: number, salt: number): number
	local v = math.sin(a * 12.9898 + b * 78.233 + salt * 37.719) * 43758.5453
	return v - math.floor(v)
end
Blueprints.hash = hash

-- R = Ry * Rx * Rz for yaw, pitch, roll in degrees (row-major, 9 numbers)
local function matrix(yaw: number, pitch: number, roll: number): { number }
	local y, p, r = math.rad(yaw), math.rad(pitch), math.rad(roll)
	local cy, sy = math.cos(y), math.sin(y)
	local cp, sp = math.cos(p), math.sin(p)
	local cr, sr = math.cos(r), math.sin(r)
	local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Rx = { 1, 0, 0, 0, cp, -sp, 0, sp, cp }
	local Rz = { cr, -sr, 0, sr, cr, 0, 0, 0, 1 }
	local function mul(a: { number }, b: { number }): { number }
		local m = table.create(9, 0)
		for i = 0, 2 do
			for j = 0, 2 do
				local acc = 0
				for k = 0, 2 do
					acc += a[i * 3 + k + 1] * b[k * 3 + j + 1]
				end
				m[i * 3 + j + 1] = acc
			end
		end
		return m
	end
	return mul(mul(Ry, Rx), Rz)
end

-- `base` + the offset (x, y, z) turned by the rotation `rot`: how a piece rides
-- on a tilted body, so the two stay joined however the body leans
local function onBody(base: { number }, rot: { number }, x: number, y: number, z: number): { number }
	local m = matrix(rot[1], rot[2], rot[3])
	return {
		base[1] + m[1] * x + m[2] * y + m[3] * z,
		base[2] + m[4] * x + m[5] * y + m[6] * z,
		base[3] + m[7] * x + m[8] * y + m[9] * z,
	}
end

local function prim(shape: string, size: { number }, pos: { number }, rot: { number }?, color: { number }, material: string): Prim
	return { shape = shape, size = size, pos = pos, rot = rot, color = color, material = material }
end

local function solid(p: Prim): Prim
	p.collide = true
	return p
end

local function flat(p: Prim): Prim
	p.shadow = false
	return p
end

local function shade(c: { number }, k: number): { number }
	return { math.clamp(c[1] * k, 0, 255), math.clamp(c[2] * k, 0, 255), math.clamp(c[3] * k, 0, 255) }
end

-- an upright cylinder (Roblox cylinders run along local x)
local function column(height: number, diameter: number, base: { number }, yaw: number, color: { number }, material: string): Prim
	return prim("cylinder", { height, diameter, diameter }, { base[1], base[2] + height / 2, base[3] }, { yaw, 0, 90 }, color, material)
end

-- ------------------------------------------------------------------ trees
--
-- Every tree is built from the same few pieces, so the forest reads as one
-- world: a trunk of tapering segments that wanders a little, limbs that carry
-- the foliage out, and foliage in clumps - a flattened mass in the shade
-- colour with lit lobes riding on top where the sun catches - in a leafy
-- material. Only trunks collide, and every crown starts above a hero's head.

local LEAF = "LeafyGrass" -- broadleaf foliage: its texture reads as leaves
local NEEDLE = "Grass" -- conifer boughs: a finer, needled texture

-- foliage palettes, { shade, middle, lit }
local LEAVES = {
	beech = { { 70, 118, 50 }, { 100, 150, 58 }, { 146, 186, 74 } },
	oak = { { 64, 106, 46 }, { 92, 134, 52 }, { 134, 168, 66 } },
	birch = { { 108, 150, 58 }, { 140, 178, 70 }, { 184, 206, 94 } },
	golden = { { 150, 128, 54 }, { 188, 158, 62 }, { 226, 192, 90 } },
	ancient = { { 56, 98, 48 }, { 86, 132, 56 }, { 140, 176, 78 } },
	elder = { { 84, 114, 50 }, { 132, 160, 64 }, { 208, 196, 104 } },
	pine = { { 36, 72, 48 }, { 48, 90, 56 }, { 76, 116, 64 } },
	spruce = { { 28, 64, 50 }, { 36, 80, 58 }, { 54, 100, 68 } },
}

-- a palette nudged per tree: a little lighter or darker, warmer or cooler
local function tinted(pal: { { number } }, seed: number): { { number } }
	local k = 0.9 + hash(seed, 1, 491) * 0.18
	local warm = (hash(seed, 2, 493) - 0.5) * 16
	local out = {}
	for i, c in pal do
		out[i] = { math.clamp(c[1] * k + warm, 0, 255), math.clamp(c[2] * k, 0, 255), math.clamp(c[3] * k - warm * 0.5, 0, 255) }
	end
	return out
end

local function along(a: { number }, b: { number }, t: number): { number }
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- a round limb from `a` to `b`, `d` thick (Roblox cylinders run along local
-- x), overrunning both ends a little so the joints between segments close
local function limb(a: { number }, b: { number }, d: number, color: { number }, material: string): Prim
	local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	local yaw = math.deg(math.atan2(-dz, dx))
	local roll = math.deg(math.asin(math.clamp(dy / len, -1, 1)))
	return prim("cylinder", { len + d * 0.5, d, d }, along(a, b, 0.5), { yaw, 0, roll }, color, material)
end

-- A bough of a conifer: a wedge from the trunk out to `reach`, thick at the
-- trunk and thinning to its tip, drooping by `droop` degrees. Its tall face
-- (local +z) is turned back to the trunk; `top` is its height there.
local function bough(
	out: { Prim },
	a: number,
	reach: number,
	thick: number,
	width: number,
	top: number,
	droop: number,
	twist: number,
	color: { number }
)
	local c, s = math.cos(a), math.sin(a)
	local yaw = math.deg(math.atan2(-c, -s))
	local drop = math.sin(math.rad(droop)) * reach / 2
	local r = reach / 2 - 0.25
	table.insert(
		out,
		prim("wedge", { width, thick, reach }, { c * r, top - thick / 2 + drop, s * r }, { yaw, droop, twist }, color, NEEDLE)
	)
end

-- A spruce (Valheim's firs): a straight trunk and layered whorls of thin,
-- drooping boughs, three to a whorl, each whorl turned from the one below and
-- a gap of shade between them, so the outline steps and frays instead of
-- drawing one hard triangle. Five whorls near the heart, three (thicker) where
-- mostly the silhouette is seen.
local function spruce(seed: number, tiers: number, boughs: number, solidTrunk: boolean, leader: boolean): { Prim }
	local out = {}
	local h = 34
	local pal = tinted(LEAVES.spruce, seed)
	local trunk = column(h * 0.62, h * 0.05, { 0, -0.6, 0 }, 0, C.bark, "Wood")
	table.insert(out, if solidTrunk then solid(trunk) else trunk)
	local turn = hash(seed, 1, 581) * 120
	local thin = (6 / tiers) ^ 0.6
	local spread = 360 / boughs
	for k = 0, tiers - 1 do
		local t = k / (tiers - 1)
		local top = h * (0.36 + 0.56 * t)
		local reach = h * (0.27 - 0.18 * t) * (0.9 + hash(seed, k, 583) * 0.2)
		local thick = h * (0.085 - 0.03 * t) * thin
		local col = if k == 0 then pal[1] elseif k == tiers - 1 then pal[3] else pal[2]
		for j = 0, boughs - 1 do
			local i = k * 3 + j
			local a = math.rad(turn + k * spread * 0.5 + j * spread + (hash(seed, i, 587) - 0.5) * 30)
			local droop = -12 - hash(seed, i, 589) * 10 + t * 6
			local twist = (hash(seed, i, 591) - 0.5) * 12
			local width = reach * (if boughs == 2 then 1.35 else 1.05)
			bough(out, a, reach, thick, width, top, droop, twist, shade(col, 0.92 + hash(seed, i, 593) * 0.16))
		end
	end
	-- the leader
	if leader then
		local tip = column(h * 0.1, h * 0.025, { 0, h * 0.9, 0 }, 0, pal[3], NEEDLE)
		tip.shadow = false
		table.insert(out, tip)
	end
	return out
end

function Blueprints.Spruce(seed: number, _g): { Prim }
	return spruce(seed, 5, 3, true, true)
end

function Blueprints.SpruceFar(seed: number, _g): { Prim }
	return spruce(seed, 5, 2, true, true)
end

-- on the mountains, beyond the barrier: seen only from afar, nothing collides
function Blueprints.SpruceRidge(seed: number, _g): { Prim }
	return spruce(seed, 5, 2, false, false)
end

-- A pine: a tall, bare, reddish trunk with a kink in it, and a few limbs near
-- the top holding flat, dark clumps - a column with a ragged canopy rather
-- than a cone, so the cool woods are not all one shape.
function Blueprints.Pine(seed: number, _g): { Prim }
	local out = {}
	local h = 34
	local pal = tinted(LEAVES.pine, seed)
	local la = hash(seed, 1, 595) * math.pi * 2
	local lean = 0.8 + hash(seed, 2, 597) * 1.4
	local top = { math.cos(la) * lean, h * 0.8, math.sin(la) * lean }
	local mid = { top[1] * 0.3 - math.sin(la) * 0.5, h * 0.42, top[3] * 0.3 + math.cos(la) * 0.5 }
	table.insert(out, solid(limb({ 0, -0.6, 0 }, mid, h * 0.05, C.pineBark, "Wood")))
	table.insert(out, limb(mid, top, h * 0.038, C.pineBark, "Wood"))
	local turn = hash(seed, 3, 599) * 360
	for k = 1, 3 do
		local a = math.rad(turn + k * 120 + (hash(seed, k, 601) - 0.5) * 50)
		local from = along(mid, top, 0.45 + k * 0.15)
		local reach = h * (0.13 + hash(seed, k, 603) * 0.06)
		local tip = { from[1] + math.cos(a) * reach, from[2] + h * 0.06, from[3] + math.sin(a) * reach }
		table.insert(out, limb(from, tip, h * 0.017, C.pineBark, "Wood"))
		local w = h * (0.26 + hash(seed, k, 605) * 0.06)
		local spot = { tip[1], tip[2] + 0.6, tip[3] }
		table.insert(out, prim("ellipsoid", { w, w * 0.4, w * 0.86 }, spot, { hash(seed, k, 607) * 180, 0, 0 }, pal[1], NEEDLE))
		local d = w * 0.48
		local lobe = { tip[1] - math.cos(a) * w * 0.12, tip[2] + w * 0.16, tip[3] - math.sin(a) * w * 0.12 }
		table.insert(out, prim("ball", { d, d, d }, lobe, nil, pal[2], NEEDLE))
	end
	local w = h * 0.3
	table.insert(out, prim("ellipsoid", { w, w * 0.46, w * 0.9 }, { top[1], top[2] + 1.2, top[3] }, { turn, 0, 0 }, pal[2], NEEDLE))
	local d = w * 0.5
	table.insert(out, prim("ball", { d, d, d }, { top[1], top[2] + 1.2 + w * 0.2, top[3] }, nil, pal[3], NEEDLE))
	return out
end

-- A crown of foliage at `at`, `rx` in radius and `ry` tall: one broad mass in
-- the shade colour, so the whole canopy reads as one volume, broken by
-- `bumps` lobes - lit ones high where the sun catches, middle-toned ones round
-- the rim - so its outline is ragged and no two crowns match. The last lobe
-- caps the top.
local function crown(out: { Prim }, seed: number, k0: number, at: { number }, rx: number, ry: number, pal: { { number } }, bumps: number)
	table.insert(out, prim("ellipsoid", { rx * 2, ry * 2, rx * 1.8 }, at, { hash(seed, k0, 701) * 180, 0, 0 }, pal[1], LEAF))
	local turn = hash(seed, k0, 703) * math.pi * 2
	for b = 1, bumps do
		local i = k0 * 16 + b
		local az = turn + b / bumps * math.pi * 2 + (hash(seed, i, 705) - 0.5) * 0.9
		local cap = b == bumps
		local high = cap or b % 2 == 0
		local el = if cap
			then 1.25 + hash(seed, i, 707) * 0.3
			elseif high then 0.6 + hash(seed, i, 709) * 0.4
			else 0.02 + hash(seed, i, 711) * 0.3
		local d = rx * (if high then 0.86 + hash(seed, i, 713) * 0.26 else 0.72 + hash(seed, i, 717) * 0.26)
		local pos = {
			at[1] + math.cos(az) * math.cos(el) * rx * 0.8,
			at[2] + math.sin(el) * ry * 0.8,
			at[3] + math.sin(az) * math.cos(el) * rx * 0.72,
		}
		local lobe = prim("ball", { d, d, d }, pos, nil, if high then pal[3] else pal[2], LEAF)
		-- the rim's lobes add little to a crown's shadow: they cast none, which
		-- spares the shadow pass a good share of the forest
		lobe.shadow = high
		table.insert(out, lobe)
	end
end

-- A beech, the woods' broadleaf: some 18 studs at scale 1. A grey trunk
-- climbing into a rounded crown, a couple of limbs showing beneath it. One
-- in fourteen has already turned golden.
function Blueprints.Beech(seed: number, _g): { Prim }
	local out = {}
	local pal = tinted(if hash(seed, 1, 511) < 0.07 then LEAVES.golden else LEAVES.beech, seed)
	local lx, lz = (hash(seed, 2, 513) - 0.5) * 1.4, (hash(seed, 3, 517) - 0.5) * 1.4
	local mid, top = { lx * 0.4, 4.6, lz * 0.4 }, { lx, 10, lz }
	table.insert(out, solid(limb({ 0, -0.8, 0 }, mid, 1.6, C.barkGrey, "Wood")))
	table.insert(out, solid(limb(mid, top, 1.15, C.barkGrey, "Wood")))
	local turn = hash(seed, 4, 519) * 360
	for k = 1, 2 do
		local a = math.rad(turn + k * 150 + (hash(seed, k, 521) - 0.5) * 40)
		local tip = { mid[1] + math.cos(a) * 3.6, 8.6 + hash(seed, k, 527) * 1.2, mid[3] + math.sin(a) * 3.6 }
		table.insert(out, limb(along(mid, top, 0.15), tip, 0.6, C.barkGrey, "Wood"))
	end
	local rx = 6.4 + hash(seed, 5, 529) * 1.2
	crown(out, seed, 1, { lx * 1.1, 11.4, lz * 1.1 }, rx, rx * 0.68, pal, 5)
	-- a lower clump off to one side, so the crown is never a lollipop
	local a = math.rad(turn + 150 + hash(seed, 6, 531) * 60)
	local side = { lx + math.cos(a) * rx * 0.85, 9.4, lz + math.sin(a) * rx * 0.85 }
	table.insert(out, prim("ellipsoid", { rx * 1.1, rx * 0.66, rx * 0.95 }, side, { math.deg(a), 0, 0 }, pal[2], LEAF))
	return out
end

-- An oak, the meadow's tree: some 15 studs at scale 1 and wider than tall. A
-- short thick trunk splitting low into spreading limbs under a broad, uneven
-- dome, one limb reaching out beyond it with a clump of its own. `lean` tips
-- the whole tree off its foot.
local function oak(seed: number, lean: number): { Prim }
	local out = {}
	local pal = tinted(LEAVES.oak, seed)
	local la = hash(seed, 1, 541) * math.pi * 2
	local lx, lz = math.cos(la) * lean, math.sin(la) * lean
	local fork = { lx * 3.8, 3.8, lz * 3.8 }
	local cx, cz = fork[1] + lx * 3, fork[3] + lz * 3
	table.insert(out, solid(limb({ 0, -0.8, 0 }, fork, 2.1, C.bark, "Wood")))
	-- the trunk climbs on into the crown, solid, so its top is never a perch
	table.insert(out, solid(limb(fork, { cx, 8.6, cz }, 1.4, C.bark, "Wood")))
	local turn = hash(seed, 2, 543) * 360
	for k = 1, 3 do
		local a = math.rad(turn + k * 120 + (hash(seed, k, 547) - 0.5) * 40)
		local reach = if k == 1 then 8.4 else 4.4 + hash(seed, k, 549) * 1.4
		local tip = { cx + math.cos(a) * reach, fork[2] + 2.8 + hash(seed, k, 551) * 1.2, cz + math.sin(a) * reach }
		table.insert(out, limb(fork, tip, 1.0 - k * 0.1, C.bark, "Wood"))
		if k == 1 then
			-- the long limb's own clump, pushing the outline out on one side
			local spot = { tip[1], tip[2] + 1.6, tip[3] }
			table.insert(out, prim("ellipsoid", { 6.4, 3.6, 5.6 }, spot, { math.deg(a), 0, 0 }, pal[2], LEAF))
		end
	end
	local rx = 7 + hash(seed, 3, 553) * 1.2
	crown(out, seed, 1, { cx, 9.2, cz }, rx, rx * 0.5, pal, 6)
	return out
end

function Blueprints.Oak(seed: number, _g): { Prim }
	return oak(seed, 0.1)
end

function Blueprints.OakLeaning(seed: number, _g): { Prim }
	return oak(seed, 0.4)
end

-- A sapling: a slim stem and a small crown.
function Blueprints.Sapling(seed: number, _g): { Prim }
	local out = {}
	local pal = tinted(LEAVES.beech, seed + 7)
	local lx, lz = (hash(seed, 1, 561) - 0.5) * 0.8, (hash(seed, 2, 563) - 0.5) * 0.8
	table.insert(out, solid(limb({ 0, -0.5, 0 }, { lx, 6.4, lz }, 0.5, C.barkGrey, "Wood")))
	crown(out, seed, 1, { lx, 7, lz }, 2.6, 2.2, pal, 2)
	return out
end

-- A birch: a slender white stem (one in four a twin), dark marks on it, and
-- a light, open crown - an upright oval up the top of the stem.
function Blueprints.Birch(seed: number, _g): { Prim }
	local out = {}
	local h = 26
	local pal = tinted(LEAVES.birch, seed)
	local stems = if hash(seed, 1, 571) < 0.25 then 2 else 1
	for s = 1, stems do
		local a = hash(seed, s, 573) * math.pi * 2
		local lean = (if stems == 2 then 2.4 else 0.9) * (0.6 + hash(seed, s, 577) * 0.6)
		local foot = { (s - 1) * 0.7, -0.5, 0 }
		local tip = { foot[1] + math.cos(a) * lean, h * (if s == 1 then 0.74 else 0.6), math.sin(a) * lean }
		local d = if s == 1 then 1.05 else 0.85
		local stem = limb(foot, tip, d, C.birch, "SmoothPlastic")
		table.insert(out, if s == 1 then solid(stem) else stem)
		for m = 1, 2 - s + (if stems == 1 then 1 else 0) do
			local t = 0.2 + m * 0.2 + hash(seed, s * 3 + m, 579) * 0.08
			table.insert(out, flat(limb(along(foot, tip, t), along(foot, tip, t + 0.02), d * 1.08, C.birchMark, "SmoothPlastic")))
		end
		if s == 1 then
			local w = 4.6 + hash(seed, s, 581) * 0.8
			local low = along(foot, tip, 0.66)
			local side = a + math.pi / 2
			crown(out, seed, 1, { low[1] + math.cos(side) * 1.2, low[2], low[3] + math.sin(side) * 1.2 }, w, w * 0.95, pal, 3)
			crown(out, seed, 2, along(foot, tip, 0.95), w * 0.82, w * 1.05, pal, 2)
		else
			crown(out, seed, 3, along(foot, tip, 0.88), 3.6, 4.4, pal, 2)
		end
	end
	return out
end

-- ------------------------------------------------------------------ the ancients

-- An ancient oak, some 85 studs at scale 1 and wider than it is tall: a
-- massive, wandering trunk on buttress roots, five great elbowed limbs
-- spreading low and far, each carrying a crown of its own, and a high crown
-- over the trunk - all of it far overhead, so it never crowds a fight. Only
-- the trunk's foot is solid.
function Blueprints.AncientOak(seed: number, _g): { Prim }
	local out = {}
	local pal = tinted(LEAVES.ancient, seed)
	local segs = { { 15, 13 }, { 12.5, 12 }, { 10, 11 } }
	local at = { 0, -2.5, 0 }
	for k, seg in segs do
		local nxt = { at[1] + (hash(seed, k, 403) - 0.5) * 3.6, at[2] + seg[2], at[3] + (hash(seed, k, 407) - 0.5) * 3.6 }
		local part = limb(at, nxt, seg[1], shade(C.bark, 0.88 + k * 0.05), "Wood")
		table.insert(out, if k <= 2 then solid(part) else part)
		at = nxt
	end
	local top = at
	-- buttress roots fanning into the ground
	for k = 0, 5 do
		local a = math.rad(k * 60 + hash(seed, k, 409) * 30)
		local reach = 14 + hash(seed, k, 410) * 5
		local root = limb(
			{ math.cos(a) * 3, 9, math.sin(a) * 3 },
			{ math.cos(a) * reach, -0.8, math.sin(a) * reach },
			5.4,
			C.barkDark,
			"Wood"
		)
		table.insert(out, root)
	end
	-- five great limbs, each with an elbow, each ending in a crown
	for k = 1, 5 do
		local a = math.rad(k * 72 + hash(seed, k, 411) * 30)
		local c, s = math.cos(a), math.sin(a)
		local from = { top[1], top[2] - 8 + hash(seed, k, 419) * 8, top[3] }
		local reach = 24 + hash(seed, k, 417) * 8
		local elbow = { from[1] + c * reach * 0.5, from[2] + reach * 0.3, from[3] + s * reach * 0.5 }
		local tip = { from[1] + c * reach, from[2] + reach * 0.46, from[3] + s * reach }
		local d = 5.6 - k * 0.25
		table.insert(out, limb(from, elbow, d, C.bark, "Wood"))
		table.insert(out, limb(elbow, tip, d * 0.7, C.bark, "Wood"))
		local rx = 14 + hash(seed, k, 421) * 3.5
		crown(out, seed, k, { tip[1] + c * 2, tip[2] + 3.5, tip[3] + s * 2 }, rx, rx * 0.56, pal, 4)
	end
	-- the high crown over the trunk
	crown(out, seed, 9, { top[1], top[2] + 26, top[3] }, 22, 12, pal, 7)
	return out
end

-- An ancient fir, some 110 studs at scale 1: a great straight trunk on its
-- roots, bare for the first forty studs, then eight whorls of five drooping
-- boughs climbing to a spire.
function Blueprints.AncientPine(seed: number, _g): { Prim }
	local out = {}
	local h = 110
	local pal = tinted(LEAVES.spruce, seed)
	table.insert(out, solid(column(h * 0.45, 7.2, { 0, -2, 0 }, 0, C.bark, "Wood")))
	table.insert(out, column(h * 0.45, 4.8, { 0, h * 0.42, 0 }, 30, C.bark, "Wood"))
	for k = 0, 4 do
		local a = math.rad(k * 72 + hash(seed, k, 441) * 30)
		table.insert(
			out,
			limb({ math.cos(a) * 2, 5, math.sin(a) * 2 }, { math.cos(a) * 8.5, -0.6, math.sin(a) * 8.5 }, 3, C.barkDark, "Wood")
		)
	end
	local tiers = 8
	local turn = hash(seed, 9, 443) * 72
	for k = 0, tiers - 1 do
		local t = k / (tiers - 1)
		local top = h * (0.4 + 0.54 * t)
		local reach = h * (0.24 - 0.17 * t) * (0.92 + hash(seed, k, 445) * 0.16)
		local thick = h * (0.06 - 0.02 * t)
		local col = if k < 2 then pal[1] elseif k < tiers - 1 then pal[2] else pal[3]
		for j = 0, 4 do
			local i = k * 5 + j
			local a = math.rad(turn + k * 36 + j * 72 + (hash(seed, i, 447) - 0.5) * 24)
			local droop = -14 - hash(seed, i, 449) * 10 + t * 8
			bough(
				out,
				a,
				reach,
				thick,
				reach * 0.72,
				top,
				droop,
				(hash(seed, i, 451) - 0.5) * 14,
				shade(col, 0.92 + hash(seed, i, 453) * 0.16)
			)
		end
	end
	local tip = column(h * 0.08, 1.6, { 0, h * 0.93, 0 }, 0, pal[3], NEEDLE)
	tip.shadow = false
	table.insert(out, tip)
	return out
end

-- The Elder: the old tree on its hill at the heart of the Wardwood, some 70
-- studs at scale 1. A short, immense trunk that twists as it climbs, six limbs
-- spreading wide and low, each crowned, and a broad high crown touched with
-- gold, the warmest green in the forest. Its roots are ElderRoots; only the
-- trunk is solid.
function Blueprints.Elder(seed: number, _g): { Prim }
	local out = {}
	local pal = tinted(LEAVES.elder, seed)
	local at = { 0, -2, 0 }
	local segs = { { 12, 9 }, { 10.5, 9 }, { 9, 8 } }
	for k, seg in segs do
		local a = math.rad(k * 110)
		local nxt = { math.cos(a) * 1.8, at[2] + seg[2], math.sin(a) * 1.8 }
		local part = limb(at, nxt, seg[1], shade(C.bark, 0.86 + k * 0.05), "Wood")
		table.insert(out, if k == 1 then solid(part) else part)
		at = nxt
	end
	local top = at
	for k = 1, 6 do
		local a = math.rad(k * 60 + hash(seed, k, 461) * 24)
		local c, s = math.cos(a), math.sin(a)
		local from = { top[1], top[2] - 5 + (k % 2) * 4, top[3] }
		local reach = 22 + hash(seed, k, 463) * 7
		local elbow = { from[1] + c * reach * 0.55, from[2] + reach * 0.3, from[3] + s * reach * 0.55 }
		local tip = { from[1] + c * reach, from[2] + reach * 0.44, from[3] + s * reach }
		table.insert(out, limb(from, elbow, 4.4, C.bark, "Wood"))
		table.insert(out, limb(elbow, tip, 3, C.bark, "Wood"))
		local rx = 12 + hash(seed, k, 467) * 3
		crown(out, seed, k, { tip[1] + c * 2, tip[2] + 3.5, tip[3] + s * 2 }, rx, rx * 0.58, pal, 3)
	end
	crown(out, seed, 9, { top[1], top[2] + 22, top[3] }, 21, 11, pal, 7)
	return out
end

-- The Fallen Giant: an ancient trunk come down across its gully, resting bank
-- to bank (it lies along local x), its root plate reared up at one end, broken
-- limbs and moss along it. The trunk is solid: run along it, jump off it.
function Blueprints.FallenGiant(seed: number, g): { Prim }
	local out = {}
	local half = 33
	local yA, yB = g(-half, 0), g(half, 0)
	local d = 9.5
	local rise = math.deg(math.atan((yB - yA) / (2 * half)))
	local cy = (yA + yB) / 2 + d / 2 - 0.8
	table.insert(out, solid(prim("cylinder", { 2 * half + 6, d, d }, { 0, cy, 0 }, { 0, 0, rise }, C.bark, "Wood")))
	table.insert(out, flat(prim("cylinder", { 2 * half - 10, d * 1.03, d * 1.03 }, { -4, cy + 0.3, 0.6 }, { 0, 0, rise }, C.moss, "Grass")))
	-- the root plate, reared up at the +x end
	local rx = half + 5
	local ry = yB + d / 2 + 4
	table.insert(out, prim("cylinder", { 3.5, 26, 26 }, { rx, ry, 0 }, { 0, 0, rise }, C.barkDark, "Wood"))
	for k = 0, 6 do
		local a = k / 7 * 360 + hash(seed, k, 451) * 30
		local r = math.rad(a)
		table.insert(
			out,
			prim("cylinder", { 12, 2.6, 2.6 }, { rx + 4, ry + math.sin(r) * 10, math.cos(r) * 10 }, { 0, 0, rise + 20 }, C.barkDark, "Wood")
		)
	end
	table.insert(out, flat(prim("cylinder", { 3.6, 22, 22 }, { rx - 0.4, ry - 1.5, 0 }, { 0, 0, rise }, { 96, 78, 56 }, "Ground")))
	-- broken limbs along the trunk
	for k = 1, 3 do
		local lx = -half + 10 + k * 14
		local ly = cy + (lx / (2 * half)) * (yB - yA)
		local a = (hash(seed, k, 453) - 0.5) * 60
		table.insert(
			out,
			prim("cylinder", { 11, 3.2, 3.2 }, { lx, ly + d / 2 + 3.5, (hash(seed, k, 457) - 0.5) * 3 }, { a, 0, 70 }, C.bark, "Wood")
		)
	end
	-- the splintered crown end
	table.insert(
		out,
		prim("cylinder", { 6, d * 0.8, d * 0.8 }, { -half - 5, yA + d / 2 - 0.6, 0 }, { 14, 0, rise - 8 }, C.barkDark, "Wood")
	)
	return out
end

-- ------------------------------------------------------------------ stones

-- A standing stone, leaning a little, with a pointed top and a moss band.
function Blueprints.Menhir(seed: number, _g, rune: { number }?): { Prim }
	local out = {}
	local h = 9 + hash(seed, 1, 19) * 4
	local w, d = 3.2, 2.2
	local rot = { 0, (hash(seed, 2, 23) - 0.5) * 8, (hash(seed, 4, 31) - 0.5) * 10 }
	local foot = { 0, -1, 0 }
	local col = shade(C.stone, 0.88 + hash(seed, 3, 29) * 0.2)
	table.insert(out, solid(prim("block", { w, h, d }, onBody(foot, rot, 0, h / 2, 0), rot, col, "Slate")))
	local point = w * 0.7
	table.insert(out, prim("block", { point, point, d * 0.98 }, onBody(foot, rot, 0, h, 0), { rot[1], rot[2], rot[3] + 45 }, col, "Slate"))
	table.insert(out, flat(prim("block", { w * 1.02, 0.6, d * 1.04 }, onBody(foot, rot, 0, h * 0.58, 0), rot, C.moss, "Grass")))
	if rune then
		local strip = prim("block", { 0.5, h * 0.5, 0.12 }, onBody(foot, rot, 0, h * 0.42, -d / 2 - 0.04), rot, rune, "Neon")
		strip.neon = true
		strip.shadow = false
		strip.tag = "Rune"
		table.insert(out, strip)
	end
	return out
end

function Blueprints.RuneStone(seed: number, g)
	return Blueprints.Menhir(seed, g, C.rune)
end

function Blueprints.MoonStone(seed: number, g)
	return Blueprints.Menhir(seed, g, C.runeTeal)
end

-- drums of a ruined column, each a little off true, with a moss cap on top
local function drums(out: { Prim }, seed: number, at: { number }, count: number, diameter: number, drumH: number): number
	local top = at[2] - 0.5
	for k = 1, count do
		local ox = (hash(seed, k, 31) - 0.5) * 0.35
		local oz = (hash(seed, k, 37) - 0.5) * 0.35
		local col = shade(C.stoneLight, 0.88 + hash(seed, k, 41) * 0.16)
		table.insert(out, solid(column(drumH, diameter, { at[1] + ox, top, at[3] + oz }, k * 23, col, "Cobblestone")))
		top += drumH
	end
	table.insert(out, flat(column(0.5, diameter * 1.04, { at[1], top, at[3] }, 0, C.moss, "Grass")))
	return top
end

-- A ruined column: whole (with a capital) or broken (a drum fallen beside it).
function Blueprints.Pillar(seed: number, _g): { Prim }
	local out = {}
	local top = drums(out, seed, { 0, 0, 0 }, 4, 3.4, 4.4)
	table.insert(out, prim("block", { 4.6, 1.4, 4.6 }, { 0, top + 0.7, 0 }, { 45, 0, 0 }, C.stoneLight, "Cobblestone"))
	return out
end

function Blueprints.PillarBroken(seed: number, _g): { Prim }
	local out = {}
	drums(out, seed, { 0, 0, 0 }, 1 + math.floor(hash(seed, 1, 43) * 2), 3.4, 4.4)
	local a = hash(seed, 2, 47) * 360
	table.insert(
		out,
		prim(
			"cylinder",
			{ 4.4, 3.4, 3.4 },
			{ math.cos(math.rad(a)) * 4.5, 1.3, math.sin(math.rad(a)) * 4.5 },
			{ a + 90, 0, 0 },
			C.stoneLight,
			"Cobblestone"
		)
	)
	return out
end

-- A brazier: a squat stone plinth, an iron bowl, embers, a warm light.
local function brazier(out: { Prim }, at: { number }, scale: number)
	table.insert(
		out,
		solid(
			prim(
				"block",
				{ 3 * scale, 2.4 * scale, 3 * scale },
				{ at[1], at[2] + 1.2 * scale - 0.4, at[3] },
				{ 45, 0, 0 },
				C.stone,
				"Slate"
			)
		)
	)
	table.insert(out, column(1.1 * scale, 4.4 * scale, { at[1], at[2] + 2.0 * scale, at[3] }, 0, C.iron, "Metal"))
	local embers = column(0.4 * scale, 3.6 * scale, { at[1], at[2] + 3.0 * scale, at[3] }, 0, C.ember, "Neon")
	embers.neon = true
	embers.shadow = false
	embers.tag = "Flame"
	embers.light = { color = { 255, 168, 90 }, brightness = 2.2, range = 34 }
	table.insert(out, embers)
end

function Blueprints.Brazier(_seed: number, _g): { Prim }
	local out = {}
	brazier(out, { 0, 0, 0 }, 1)
	return out
end

-- ------------------------------------------------------------------ landmarks

-- The Ward: a ruined platform of slabs round a brazier, four columns at its
-- corners (one broken), the ward stone on the far side, a drum fallen across
-- the slabs. Local -z faces the spawn clearing. The slabs follow the ground.
function Blueprints.Ward(seed: number, g): { Prim }
	local out = {}
	local n, size = 5, 6.2
	local half = (n - 1) * size / 2
	for iz = 0, n - 1 do
		for ix = 0, n - 1 do
			local centre = ix == 2 and iz == 2
			if not centre and hash(ix, iz, seed + 3) < 0.14 then
				continue -- a ruin: a few slabs are gone
			end
			local lx, lz = -half + ix * size, -half + iz * size
			local y = g(lx, lz)
			local sx = (g(lx + size / 2, lz) - g(lx - size / 2, lz)) / size
			local sz = (g(lx, lz + size / 2) - g(lx, lz - size / 2)) / size
			local pitch = -math.deg(math.atan(sz))
			local roll = math.deg(math.atan(sx))
			local mossy = hash(ix, iz, seed + 5) > 0.62
			local col = if mossy then { 112, 128, 92 } else shade(C.stoneLight, 0.86 + hash(ix, iz, seed + 7) * 0.18)
			local sink = hash(ix, iz, seed + 9) * 0.25
			table.insert(
				out,
				solid(
					prim(
						"block",
						{ size - 0.35, 1.2, size - 0.35 },
						{ lx, y - 0.25 - sink, lz },
						{ hash(ix, iz, seed + 11) * 3 - 1.5, pitch, roll },
						col,
						"Slate"
					)
				)
			)
		end
	end
	local corners = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
	for i, c in corners do
		local lx, lz = c[1] * (half + 1.5), c[2] * (half + 1.5)
		local base = { lx, g(lx, lz), lz }
		if i == 2 then
			drums(out, seed + i, base, 2, 3.6, 4.6)
		else
			local top = drums(out, seed + i, base, 4, 3.6, 4.6)
			table.insert(out, prim("block", { 4.8, 1.4, 4.8 }, { lx, top + 0.7, lz }, { 45, 0, 0 }, C.stoneLight, "Cobblestone"))
		end
	end
	brazier(out, { 0, g(0, 0), 0 }, 1)
	-- the ward stone, its runes facing the clearing
	local sz = half + size + 1
	local foot = { 0, g(0, sz) - 0.8, sz }
	local lean = { 0, 4, 0 } -- leaning back, away from the clearing
	table.insert(out, solid(prim("block", { 5.4, 12, 1.8 }, onBody(foot, lean, 0, 6, 0), lean, C.stoneDark, "Slate")))
	table.insert(out, prim("block", { 3.8, 3.8, 1.78 }, onBody(foot, lean, 0, 12, 0), { 0, 4, 45 }, C.stoneDark, "Slate"))
	for k = 0, 2 do
		local strip = prim(
			"block",
			{ 0.55, 2.4, 0.14 },
			onBody(foot, lean, (k - 1) * 1.4, 6.2 + k * 0.6, -0.95),
			{ 0, 4, (k - 1) * 12 },
			C.rune,
			"Neon"
		)
		strip.neon = true
		strip.shadow = false
		strip.tag = "Rune"
		table.insert(out, strip)
	end
	local glow = prim("block", { 0.2, 0.2, 0.2 }, onBody(foot, lean, 0, 7, -1.6), nil, C.rune, "Neon")
	glow.shadow = false
	glow.light = { color = { 255, 176, 100 }, brightness = 1.3, range = 18 }
	table.insert(out, glow)
	-- a drum fallen across the slabs
	table.insert(
		out,
		prim(
			"cylinder",
			{ 4.6, 3.6, 3.6 },
			{ half - 3, g(half - 3, -half + 2) + 1.6, -half + 2 },
			{ 70, 0, 0 },
			C.stoneLight,
			"Cobblestone"
		)
	)
	return out
end

-- The Sun Temple on Sunspire's summit: a ring of twelve columns (two long
-- fallen, two broken) carrying lintels, round a two-step dais and its great
-- brazier, runes glowing on the dais rim. Open enough to fight in and run through.
function Blueprints.SunTemple(seed: number, g): { Prim }
	local out = {}
	local ring = 20
	local g0 = g(0, 0)
	table.insert(out, solid(column(1.6, 28, { 0, g0 - 1.1, 0 }, 0, shade(C.stoneLight, 0.94), "Slate")))
	table.insert(out, solid(column(1.4, 17, { 0, g0 + 0.4, 0 }, 15, C.stoneLight, "Slate")))
	brazier(out, { 0, g0 + 1.6, 0 }, 1.7)
	for k = 0, 3 do
		local a = math.rad(k * 90 + 45)
		local strip = prim(
			"block",
			{ 3.2, 0.2, 0.6 },
			{ math.cos(a) * 12.4, g0 + 0.55, math.sin(a) * 12.4 },
			{ -k * 90 - 45, 0, 0 },
			C.rune,
			"Neon"
		)
		strip.neon = true
		strip.shadow = false
		strip.tag = "Rune"
		table.insert(out, strip)
	end
	local tops = {}
	for k = 0, 11 do
		local a = math.rad(k * 30)
		local x, z = math.cos(a) * ring, math.sin(a) * ring
		if k == 2 or k == 7 then
			-- long fallen: its drums lie in the grass outside the ring
			local fa = math.rad(k * 30 + 12)
			for j = 0, 1 do
				local fx, fz = math.cos(fa) * (ring + 6 + j * 5), math.sin(fa) * (ring + 6 + j * 5)
				table.insert(
					out,
					prim("cylinder", { 4.8, 3.8, 3.8 }, { fx, g(fx, fz) + 1.5, fz }, { k * 30 + 60 * j, 0, 0 }, C.stoneLight, "Cobblestone")
				)
			end
		else
			local count = if k == 5 or k == 10 then 2 else 4
			tops[k] = drums(out, seed + k, { x, g(x, z), z }, count, 3.8, 5)
			if count == 4 then
				table.insert(out, prim("block", { 5, 1.5, 5 }, { x, tops[k] + 0.75, z }, { -k * 30, 0, 0 }, C.stoneLight, "Cobblestone"))
			end
		end
	end
	-- lintels between neighbouring whole columns
	for k = 0, 11 do
		local j = (k + 1) % 12
		local tk, tj = tops[k], tops[j]
		local whole = tk and tj and not (k == 5 or k == 10 or j == 5 or j == 10)
		if whole and hash(seed, k, 461) < 0.8 then
			local a = math.rad(k * 30 + 15)
			local y = math.min(tk, tj) + 2.2
			local lintel = prim(
				"block",
				{ 13, 1.9, 3.8 },
				{ math.cos(a) * ring, y, math.sin(a) * ring },
				{ 90 - (k * 30 + 15), 0, 0 },
				C.stone,
				"Slate"
			)
			table.insert(out, solid(lintel))
		end
	end
	return out
end

-- The Runic Gate: two great columns and a lintel over the top of ramp A, a
-- rune keystone facing down the ramp, lanterns hanging from the lintel. The
-- opening is 24 studs wide and 17 high: crowds and heroes pass under it.
function Blueprints.Gate(seed: number, g): { Prim }
	local out = {}
	local gap = 24
	local tops = {}
	for side = -1, 1, 2 do
		local lx = side * (gap / 2 + 2.6)
		tops[side] = drums(out, seed + side, { lx, g(lx, 0), 0 }, 4, 5.2, 4.6)
	end
	local y = math.min(tops[-1], tops[1]) + 0.2
	table.insert(out, solid(prim("block", { gap + 11, 3.6, 5.6 }, { 0, y + 1.8, 0 }, { 0, 0, 1.5 }, C.stone, "Slate")))
	table.insert(out, prim("block", { gap + 6, 1.4, 4.6 }, { 0, y + 4.3, 0 }, { 0, 0, -1 }, C.stoneDark, "Slate"))
	table.insert(out, flat(prim("block", { gap + 10, 0.4, 5.7 }, { 0, y + 3.7, 0 }, { 0, 0, 1.5 }, C.moss, "Grass")))
	local key = prim("block", { 3.2, 3.4, 0.3 }, { 0, y + 1.8, -2.95 }, { 0, 0, 45 }, C.rune, "Neon")
	key.neon = true
	key.shadow = false
	key.tag = "Rune"
	key.light = { color = { 255, 176, 100 }, brightness = 1.6, range = 22 }
	table.insert(out, key)
	for side = -1, 1, 2 do
		local lx = side * 7
		table.insert(out, flat(prim("block", { 0.2, 2.6, 0.2 }, { lx, y - 1.3, 0 }, nil, C.iron, "Metal")))
		local lamp = prim("block", { 1.1, 1.4, 1.1 }, { lx, y - 3.2, 0 }, { 45, 0, 0 }, { 255, 196, 120 }, "Neon")
		lamp.neon = true
		lamp.shadow = false
		lamp.tag = "Flame"
		lamp.light = { color = { 255, 186, 110 }, brightness = 1.4, range = 20 }
		table.insert(out, lamp)
	end
	return out
end

-- A paving fragment of the old circle round the spawn: three worn slabs set
-- flush in the ground, following its slope, so a hero at full speed never trips.
function Blueprints.Paving(seed: number, g): { Prim }
	local out = {}
	for k = 0, 2 do
		local lx = (k - 1) * 4.2 + (hash(seed, k, 251) - 0.5)
		local lz = (hash(seed, k, 257) - 0.5) * 1.6
		local y = g(lx, lz)
		local sx = (g(lx + 2, lz) - g(lx - 2, lz)) / 4
		local sz = (g(lx, lz + 2) - g(lx, lz - 2)) / 4
		local col = shade(C.stoneLight, 0.82 + hash(seed, k, 263) * 0.2)
		local slab = prim(
			"block",
			{ 3.8, 0.8, 3.4 + hash(seed, k, 269) },
			{ lx, y - 0.25, lz },
			{ (hash(seed, k, 271) - 0.5) * 14, -math.deg(math.atan(sz)), math.deg(math.atan(sx)) },
			col,
			"Slate"
		)
		slab.shadow = false
		table.insert(out, slab)
	end
	return out
end

-- A cairn: flat stones stacked off true, a rune on the top one.
function Blueprints.Cairn(seed: number, _g): { Prim }
	local out = {}
	local y = -0.3
	for k = 1, 5 do
		local w = 5.2 - k * 0.75
		local th = 1.3 - k * 0.08
		local col = shade(C.stone, 0.85 + hash(seed, k, 53) * 0.25)
		table.insert(
			out,
			solid(
				prim(
					"block",
					{ w, th, w * 0.85 },
					{ (hash(seed, k, 59) - 0.5) * 0.6, y + th / 2, 0 },
					{ k * 37, (hash(seed, k, 61) - 0.5) * 6, 0 },
					col,
					"Slate"
				)
			)
		)
		y += th * 0.92
	end
	local rune = prim("ball", { 0.9, 0.9, 0.9 }, { 0, y + 0.3, 0 }, nil, C.rune, "Neon")
	rune.neon = true
	rune.shadow = false
	rune.tag = "Rune"
	table.insert(out, rune)
	return out
end

-- The Elder's roots: great roots spreading from the foot of the elder tree,
-- reaching down into the hill. The tree itself is the Elder blueprint.
function Blueprints.ElderRoots(seed: number, g): { Prim }
	local out = {}
	-- a broad flare at the foot of the trunk...
	table.insert(out, column(4, 15, { 0, -1.5, 0 }, 0, C.barkDark, "Wood"))
	table.insert(out, column(3, 11, { 0, 1.5, 0 }, 20, C.bark, "Wood"))
	-- ...and great roots reaching out and down into the hill
	for k = 0, 7 do
		local a = k / 8 * 360 + hash(seed, k, 67) * 25
		local len = 16 + hash(seed, k, 71) * 9
		local r = math.rad(a)
		local reach = len * 0.5 + 3
		local cx, cz = math.cos(r) * reach, math.sin(r) * reach
		local thick = 3.6 + hash(seed, k, 73) * 1.6
		table.insert(out, prim("cylinder", { len, thick, thick }, { cx, g(cx, cz) + 0.9, cz }, { -a, 0, -10 }, C.barkDark, "Wood"))
	end
	return out
end

-- ------------------------------------------------------------------ ground cover

-- A fern: fronds fanned round the root, curling up and out.
function Blueprints.Fern(seed: number, _g): { Prim }
	local out = {}
	local count = 4
	for k = 1, count do
		local a = k / count * 360 + hash(seed, k, 73) * 40
		local len = 2.8 + hash(seed, k, 79) * 1.2
		local col = if k % 2 == 0 then C.fern else C.fernLight
		local r = math.rad(a)
		local p = prim(
			"wedge",
			{ 0.9, 0.18, len },
			{ math.sin(r) * len * 0.42, 0.75, math.cos(r) * len * 0.42 },
			{ a, -32, 0 },
			col,
			"SmoothPlastic"
		)
		p.shadow = false
		table.insert(out, p)
	end
	return out
end

-- A tuft of meadow flowers.
local FLOWERS = { { 255, 214, 74 }, { 246, 244, 232 }, { 176, 126, 226 }, { 236, 92, 76 }, { 255, 168, 60 } }
function Blueprints.Flowers(seed: number, _g): { Prim }
	local out = {}
	local col = FLOWERS[1 + math.floor(hash(seed, 1, 83) * #FLOWERS)]
	local count = 3 + math.floor(hash(seed, 2, 89) * 3)
	for k = 1, count do
		local a = math.rad(hash(seed, k, 97) * 360)
		local r = hash(seed, k, 101) * 2.2
		local d = 0.5 + hash(seed, k, 103) * 0.35
		local y = 0.7 + hash(seed, k, 107) * 0.6
		table.insert(out, flat(prim("ball", { d, d, d }, { math.cos(a) * r, y, math.sin(a) * r }, nil, col, "SmoothPlastic")))
	end
	return out
end

-- Glowcaps: a cluster of pale mushrooms with softly glowing caps (Mirewood).
function Blueprints.Glowcaps(seed: number, _g): { Prim }
	local out = {}
	for k = 1, 3 do
		local a = math.rad(k * 120 + hash(seed, k, 109) * 40)
		local r = 0.9 + hash(seed, k, 113)
		local h = 0.9 + hash(seed, k, 127) * 1.1
		local x, z = math.cos(a) * r, math.sin(a) * r
		table.insert(out, flat(column(h, 0.4, { x, -0.1, z }, 0, C.stem, "SmoothPlastic")))
		local cap = column(0.35, 1.3 + h * 0.4, { x, h - 0.15, z }, 0, C.runeTeal, "Neon")
		cap.neon = true
		cap.shadow = false
		cap.tag = "Glow"
		table.insert(out, cap)
	end
	return out
end

--- The blueprint for a prop kind, if it is part-built.
function Blueprints.get(kind: string): ((number, any) -> { Prim })?
	local fn = (Blueprints :: any)[kind]
	if type(fn) == "function" and kind ~= "get" and kind ~= "hash" then
		return fn
	end
	return nil
end

-- ------------------------------------------------------------------ space

--- A rotation matrix (row-major, 9 numbers) for yaw, pitch, roll in degrees:
--- yaw about y first, then pitch about x, then roll about z (R = Ry * Rx * Rz).
Blueprints.matrix = matrix

return Blueprints

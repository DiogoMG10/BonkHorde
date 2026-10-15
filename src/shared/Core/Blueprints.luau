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
	birch = { 232, 228, 212 },
	birchMark = { 52, 50, 48 },
	spruce = { { 30, 70, 56 }, { 36, 82, 62 }, { 46, 96, 70 } },
	birchLeaf = { { 156, 194, 74 }, { 136, 182, 66 }, { 176, 204, 88 } },
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

-- a gable: two wedges back to back, ridge along local x, `w` wide, `h` tall
local function gable(out: { Prim }, w: number, len: number, h: number, y0: number, yaw: number, color: { number }, material: string)
	local c, s = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
	local function at(lz: number): { number }
		-- rotate the local offset (0, lz) by yaw about y
		return { lz * s, y0 + h / 2, lz * c }
	end
	table.insert(out, prim("wedge", { len, h, w / 2 }, at(-w / 4), { yaw, 0, 0 }, color, material))
	table.insert(out, prim("wedge", { len, h, w / 2 }, at(w / 4), { yaw + 180, 0, 0 }, color, material))
end

-- ------------------------------------------------------------------ trees

-- A spruce: a short trunk under three tiers, each tier two crossed gables, so
-- from any side the silhouette is a stack of triangles. Only the trunk collides.
local function spruce(seed: number, tiers: number): { Prim }
	local out = {}
	local h = 34
	local jitter = hash(seed, 1, 3)
	local tint = 0.9 + hash(seed, 2, 5) * 0.22
	local trunkD = h * 0.055
	table.insert(out, solid(column(h * 0.36, trunkD, { 0, -0.6, 0 }, 0, C.bark, "Wood")))
	-- three tiers near the play area; two taller ones on the distant rim, where
	-- only the silhouette is seen and the part count matters more
	local widths = if tiers == 3 then { 0.48, 0.36, 0.24 } else { 0.46, 0.3 }
	local heights = if tiers == 3 then { 0.38, 0.34, 0.34 } else { 0.5, 0.48 }
	local bottoms = if tiers == 3 then { 0.15, 0.39, 0.62 } else { 0.15, 0.5 }
	for k = 1, tiers do
		local w = widths[k] * h * (0.94 + hash(seed, k, 7) * 0.12)
		local th = heights[k] * h
		local y0 = bottoms[k] * h
		local col = shade(C.spruce[k], tint)
		local yaw = k * 31 + jitter * 90
		gable(out, w, w, th, y0, yaw, col, "SmoothPlastic")
		gable(out, w, w, th, y0, yaw + 90, shade(col, 0.93), "SmoothPlastic")
	end
	return out
end

function Blueprints.Spruce(seed: number, _g): { Prim }
	return spruce(seed, 3)
end

function Blueprints.SpruceFar(seed: number, _g): { Prim }
	return spruce(seed, 2)
end

-- A birch: a pale trunk with dark marks, a light crown of three puffs.
function Blueprints.Birch(seed: number, _g): { Prim }
	local out = {}
	local h = 26
	local lean = (hash(seed, 1, 11) - 0.5) * 6
	table.insert(out, solid(prim("cylinder", { h * 0.78, 1.1, 1.1 }, { 0, h * 0.39 - 0.5, 0 }, { 0, lean, 90 }, C.birch, "SmoothPlastic")))
	for k = 1, 3 do
		local y = h * (0.18 + 0.17 * k) + hash(seed, k, 13) * 2
		table.insert(out, flat(column(0.5, 1.18, { 0, y - h * 0.01, 0 }, 0, C.birchMark, "SmoothPlastic")))
	end
	for k = 1, 3 do
		local a = math.rad(k * 120 + hash(seed, k, 17) * 60)
		local r = 2.4
		local d = h * (0.36 - k * 0.04)
		local col = C.birchLeaf[k]
		table.insert(out, prim("ball", { d, d, d }, { math.cos(a) * r, h * (0.7 + k * 0.07), math.sin(a) * r }, nil, col, "SmoothPlastic"))
	end
	return out
end

-- ------------------------------------------------------------------ the ancients

local OAK_LEAVES = { { 118, 168, 62 }, { 96, 150, 54 }, { 140, 182, 74 }, { 162, 178, 72 } }

-- An ancient oak, some 95 studs at scale 1: a massive, slightly wandering
-- trunk on buttress roots, five great limbs, a crown of leaf masses that
-- begins far overhead so it never crowds a fight. Only the trunk's foot is solid.
function Blueprints.AncientOak(seed: number, _g): { Prim }
	local out = {}
	local segs = { { 14, 15 }, { 12, 14 }, { 10, 13 }, { 8.2, 11 } }
	local y, ox, oz = -2.5, 0, 0
	for k, seg in segs do
		ox += (hash(seed, k, 403) - 0.5) * 1.6
		oz += (hash(seed, k, 407) - 0.5) * 1.6
		local part = column(seg[2] + 1.2, seg[1], { ox, y, oz }, k * 17, shade(C.bark, 0.9 + k * 0.04), "Wood")
		if k <= 2 then
			part.collide = true
		end
		table.insert(out, part)
		y += seg[2]
	end
	local top = { ox, y, oz }
	-- buttress roots fanning into the ground
	for k = 0, 5 do
		local a = k * 60 + hash(seed, k, 409) * 30
		local r = math.rad(a)
		table.insert(
			out,
			prim("cylinder", { 17, 4.2, 4.2 }, { math.cos(r) * 7.5, 1.4, math.sin(r) * 7.5 }, { -a, 0, -24 }, C.barkDark, "Wood")
		)
	end
	-- moss on the trunk's foot
	table.insert(out, flat(column(5, 14.3, { 0, 4, 0.6 }, 0, C.moss, "Grass")))
	-- five limbs reaching up and out, each ending in leaf masses
	for k = 1, 5 do
		local a = k * 72 + hash(seed, k, 411) * 30
		local tilt = 26 + hash(seed, k, 413) * 22
		local len = 28 + hash(seed, k, 417) * 9
		local by = top[2] - 16 + hash(seed, k, 419) * 10
		local r, t = math.rad(a), math.rad(tilt)
		local dx, dy, dz = math.cos(r) * math.cos(t), math.sin(t), math.sin(r) * math.cos(t)
		local cx, cy, cz = top[1] + dx * len / 2, by + dy * len / 2, top[3] + dz * len / 2
		local limb = 5.4 - k * 0.25
		table.insert(out, prim("cylinder", { len, limb, limb }, { cx, cy, cz }, { -a, 0, tilt }, C.bark, "Wood"))
		local ex, ey, ez = top[1] + dx * len, by + dy * len, top[3] + dz * len
		for j = 1, 3 do
			local d = 22 + hash(seed, k * 3 + j, 421) * 10
			local jx = (hash(seed, k * 3 + j, 423) - 0.5) * 14
			local jz = (hash(seed, k * 3 + j, 427) - 0.5) * 14
			local col = OAK_LEAVES[1 + (k + j) % #OAK_LEAVES]
			table.insert(out, prim("ball", { d, d, d }, { ex + jx, ey + 3 + j * 3, ez + jz }, nil, col, "SmoothPlastic"))
		end
	end
	-- the crown over the trunk
	for k = 1, 5 do
		local a = math.rad(k * 72 + hash(seed, k, 431) * 40)
		local d = 32 + hash(seed, k, 433) * 10
		local at = { top[1] + math.cos(a) * 12, top[2] + 16 + k * 2.5, top[3] + math.sin(a) * 12 }
		table.insert(out, prim("ball", { d, d, d }, at, nil, OAK_LEAVES[1 + k % #OAK_LEAVES], "SmoothPlastic"))
	end
	return out
end

-- An ancient pine, some 105 studs at scale 1: a tall bare trunk, then five
-- tiers of crossed gables; the lowest branches start 25 studs up.
function Blueprints.AncientPine(seed: number, _g): { Prim }
	local out = {}
	local h = 105
	table.insert(out, solid(column(h * 0.6, 6.4, { 0, -2, 0 }, 0, C.bark, "Wood")))
	table.insert(out, column(h * 0.3, 4.6, { 0, h * 0.56, 0 }, 30, C.bark, "Wood"))
	for k = 0, 3 do
		local a = k * 90 + hash(seed, k, 441) * 40
		local r = math.rad(a)
		table.insert(out, prim("cylinder", { 10, 2.8, 2.8 }, { math.cos(r) * 4, 1, math.sin(r) * 4 }, { -a, 0, -26 }, C.barkDark, "Wood"))
	end
	local widths = { 0.4, 0.34, 0.27, 0.2, 0.13 }
	local bottoms = { 0.24, 0.38, 0.52, 0.66, 0.78 }
	local tint = 0.92 + hash(seed, 9, 443) * 0.14
	for k = 1, 5 do
		local w = widths[k] * h
		local th = 0.23 * h
		local col = shade(C.spruce[math.min(k, 3)], tint)
		local yaw = k * 37 + hash(seed, k, 447) * 20
		gable(out, w, w, th, bottoms[k] * h, yaw, col, "SmoothPlastic")
		gable(out, w, w, th, bottoms[k] * h, yaw + 90, shade(col, 0.93), "SmoothPlastic")
	end
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
-- reaching down into the hill. The tree itself is the TreeTwin mesh, scaled.
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
	local count = 5
	for k = 1, count do
		local a = k / count * 360 + hash(seed, k, 73) * 30
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
	local count = 4 + math.floor(hash(seed, 2, 89) * 4)
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

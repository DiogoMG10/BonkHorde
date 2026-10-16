--!nonstrict
-- Vfx - the game's effect kit: particle bursts, flat ground shapes and beams,
-- built from the game's own cartoon textures (tools/vfx/make_textures.py).
--
-- Everything is pooled and nothing here can error into gameplay: callers wrap
-- effects in pcall, and an effect with a missing preset is simply skipped.
--
--   Vfx.burst("HitSpark", position)                 a particle burst
--   Vfx.burst("DeathPoof", position, { tint = c })  tinted
--   Vfx.ground(position, "ring", colour, 2, 14, 0.4) a flat shape that grows and fades
--   Vfx.bolt(from, to, colour)                      a lightning strip
--   Vfx.attach("FireTrail", part)                   a continuous emitter on a part

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Vfx = {}

Vfx.Tex = {
	beam = "rbxassetid://114031481080589",
	bolt = "rbxassetid://104447010833774",
	burst = "rbxassetid://87765611716980",
	confetti = "rbxassetid://76386719894460",
	crescent = "rbxassetid://134627825287974",
	dot = "rbxassetid://93327830389071",
	glow = "rbxassetid://101511447930755",
	leaf = "rbxassetid://120432521175251",
	plus = "rbxassetid://104512335820545",
	puff = "rbxassetid://103341265199303",
	ring = "rbxassetid://93877420201685",
	ring_thin = "rbxassetid://136208787434277",
	shard = "rbxassetid://96787596936523",
	star4 = "rbxassetid://138729166738433",
	star5 = "rbxassetid://104390310820076",
	streak = "rbxassetid://105801032795942",
	swirl = "rbxassetid://110730811881184",
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function grow(a: number, b: number, c: number?): NumberSequence
	if c then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, a),
			NumberSequenceKeypoint.new(0.35, b),
			NumberSequenceKeypoint.new(1, c),
		})
	end
	return NumberSequence.new(a, b)
end

-- visible for most of its life, then gone: the cartoon "pop" instead of a slow fade
local POP = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1) })
local SOFT =
	NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) })

-- One preset is a list of layers. Each layer: texture, how many, colour(s),
-- size curve, lifetime, speed, and the handful of emitter properties that matter.
local PRESETS: { [string]: { any } } = {
	HitSpark = {
		{
			tex = "star4",
			count = 1,
			colour = rgb(255, 255, 255),
			size = grow(0.6, 2.4, 0),
			life = { 0.12, 0.16 },
			speed = { 0, 0 },
			glow = 1,
			z = 2,
		},
		{
			tex = "streak",
			count = 4,
			colour = rgb(255, 250, 210),
			size = grow(0.9, 0),
			life = { 0.14, 0.22 },
			speed = { 16, 26 },
			glow = 1,
			facing = "velocity",
		},
	},
	CritBurst = {
		{
			tex = "burst",
			count = 1,
			colour = rgb(255, 225, 60),
			size = grow(1.2, 4.6, 3.4),
			life = { 0.2, 0.24 },
			speed = { 0, 0 },
			glow = 0.9,
			z = 2,
			rot = { -25, 25 },
		},
		{
			tex = "star5",
			count = 5,
			colour = rgb(255, 240, 120),
			size = grow(0.9, 0),
			life = { 0.3, 0.45 },
			speed = { 14, 22 },
			glow = 0.8,
			spin = { -260, 260 },
			drag = 4,
		},
	},
	DeathPoof = {
		{
			tex = "puff",
			count = 5,
			colour = rgb(255, 255, 255),
			size = grow(1.2, 3.2, 2.4),
			life = { 0.28, 0.42 },
			speed = { 5, 11 },
			alpha = SOFT,
			drag = 5,
			rot = { 0, 360 },
			glow = 0.25,
		},
		{
			tex = "star5",
			count = 3,
			colour = rgb(255, 235, 110),
			size = grow(0.8, 0),
			life = { 0.35, 0.5 },
			speed = { 10, 18 },
			spin = { -300, 300 },
			drag = 3,
			glow = 0.7,
			accel = Vector3.new(0, -18, 0),
		},
	},
	FireExplosion = {
		{
			tex = "burst",
			count = 1,
			colour = rgb(255, 235, 120),
			size = grow(2, 9, 7),
			life = { 0.2, 0.22 },
			speed = { 0, 0 },
			glow = 1,
			z = 2,
			rot = { 0, 360 },
		},
		{
			tex = "puff",
			count = 9,
			colour = ColorSequence.new(rgb(255, 170, 40), rgb(210, 70, 20)),
			size = grow(1.6, 4.2, 3),
			life = { 0.35, 0.55 },
			speed = { 9, 20 },
			alpha = SOFT,
			drag = 4,
			rot = { 0, 360 },
			glow = 0.6,
		},
		{
			tex = "puff",
			count = 5,
			colour = rgb(70, 62, 60),
			size = grow(1.5, 4.5),
			life = { 0.6, 0.9 },
			speed = { 3, 8 },
			alpha = SOFT,
			drag = 2,
			rot = { 0, 360 },
			accel = Vector3.new(0, 7, 0),
		},
		{
			tex = "dot",
			count = 8,
			colour = rgb(255, 215, 70),
			size = grow(0.5, 0),
			life = { 0.3, 0.5 },
			speed = { 20, 34 },
			glow = 1,
			drag = 3,
			accel = Vector3.new(0, -30, 0),
		},
	},
	RocketExplosion = {
		{
			tex = "burst",
			count = 1,
			colour = rgb(255, 255, 255),
			size = grow(2, 9, 7),
			life = { 0.2, 0.22 },
			speed = { 0, 0 },
			glow = 1,
			z = 2,
			rot = { 0, 360 },
		},
		{
			tex = "puff",
			count = 8,
			colour = ColorSequence.new(rgb(255, 130, 200), rgb(255, 240, 250)),
			size = grow(1.6, 4, 3),
			life = { 0.35, 0.55 },
			speed = { 9, 20 },
			alpha = SOFT,
			drag = 4,
			rot = { 0, 360 },
			glow = 0.5,
		},
		{
			tex = "confetti",
			count = 14,
			colour = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(255, 90, 170)),
				ColorSequenceKeypoint.new(0.5, rgb(255, 225, 70)),
				ColorSequenceKeypoint.new(1, rgb(90, 200, 255)),
			}),
			size = grow(0.55, 0.45),
			life = { 0.7, 1.1 },
			speed = { 16, 30 },
			spin = { -500, 500 },
			rot = { 0, 360 },
			drag = 3,
			accel = Vector3.new(0, -26, 0),
			alpha = POP,
			up = true,
		},
	},
	NightBurst = {
		{
			tex = "burst",
			count = 1,
			colour = rgb(255, 245, 180),
			size = grow(2, 10, 8),
			life = { 0.22, 0.24 },
			speed = { 0, 0 },
			glow = 1,
			z = 2,
			rot = { 0, 360 },
		},
		{
			tex = "star4",
			count = 10,
			colour = rgb(255, 250, 210),
			size = grow(1.1, 0),
			life = { 0.3, 0.5 },
			speed = { 14, 26 },
			glow = 1,
			drag = 3,
		},
	},
	MirrorBurst = {
		{
			tex = "ring",
			count = 1,
			colour = rgb(190, 230, 255),
			size = grow(1.5, 9),
			life = { 0.25, 0.25 },
			speed = { 0, 0 },
			glow = 1,
			z = 2,
		},
		{
			tex = "shard",
			count = 9,
			colour = rgb(210, 240, 255),
			size = grow(0.9, 0),
			life = { 0.3, 0.5 },
			speed = { 14, 24 },
			spin = { -400, 400 },
			rot = { 0, 360 },
			glow = 0.8,
			drag = 3,
		},
	},
	FreezeShatter = {
		{
			tex = "shard",
			count = 7,
			colour = rgb(190, 235, 255),
			size = grow(0.9, 0.2),
			life = { 0.3, 0.5 },
			speed = { 10, 18 },
			spin = { -400, 400 },
			rot = { 0, 360 },
			glow = 0.7,
			drag = 3,
			accel = Vector3.new(0, -24, 0),
		},
	},
	FrostSparkle = {
		{
			tex = "star4",
			count = 10,
			colour = rgb(200, 245, 255),
			size = grow(0.2, 1.1, 0),
			life = { 0.4, 0.7 },
			speed = { 1, 4 },
			glow = 1,
			ring = true,
			up = true,
		},
	},
	LightningImpact = {
		{
			tex = "burst",
			count = 1,
			colour = rgb(235, 250, 255),
			size = grow(1.5, 6.5, 5),
			life = { 0.14, 0.16 },
			speed = { 0, 0 },
			glow = 1,
			z = 2,
			rot = { 0, 360 },
		},
		{
			tex = "streak",
			count = 7,
			colour = rgb(170, 235, 255),
			size = grow(1.1, 0),
			life = { 0.16, 0.28 },
			speed = { 20, 34 },
			glow = 1,
			facing = "velocity",
		},
	},
	LevelUpBurst = {
		{
			tex = "star5",
			count = 14,
			colour = rgb(255, 225, 70),
			size = grow(0.4, 1.2, 0),
			life = { 0.6, 1 },
			speed = { 8, 16 },
			glow = 0.9,
			spin = { -200, 200 },
			ring = true,
			up = true,
			drag = 1.5,
		},
		{
			tex = "glow",
			count = 2,
			colour = rgb(255, 230, 110),
			size = grow(3, 12),
			life = { 0.4, 0.5 },
			speed = { 0, 0 },
			glow = 1,
			alpha = SOFT,
		},
	},
	HealPlus = {
		{
			tex = "plus",
			count = 6,
			colour = rgb(90, 235, 110),
			size = grow(0.5, 1.1, 0.7),
			life = { 0.7, 1 },
			speed = { 4, 8 },
			glow = 0.7,
			up = true,
			ring = true,
			alpha = POP,
		},
	},
	MagnetPull = {
		{
			tex = "streak",
			count = 16,
			colour = rgb(90, 170, 255),
			size = grow(1.6, 0.3),
			life = { 0.3, 0.45 },
			speed = { -34, -24 },
			glow = 1,
			facing = "velocity",
			far = 12,
		},
		{ tex = "ring_thin", count = 1, colour = rgb(120, 190, 255), size = grow(16, 1), life = { 0.4, 0.4 }, speed = { 0, 0 }, glow = 1 },
	},
	-- gems and coins reaching the hero: a small twinkle (tinted gold for coins)
	GemCollect = {
		{
			tex = "star4",
			count = 3,
			colour = rgb(130, 200, 255),
			size = grow(0.9, 0),
			life = { 0.18, 0.28 },
			speed = { 3, 7 },
			glow = 1,
			up = true,
		},
	},
	FrenzyFlare = {
		{
			tex = "burst",
			count = 1,
			colour = rgb(255, 120, 40),
			size = grow(2, 8, 6),
			life = { 0.25, 0.3 },
			speed = { 0, 0 },
			glow = 1,
			rot = { 0, 360 },
		},
		{
			tex = "streak",
			count = 10,
			colour = rgb(255, 90, 40),
			size = grow(1.4, 0),
			life = { 0.3, 0.5 },
			speed = { 10, 18 },
			glow = 1,
			facing = "velocity",
			up = true,
		},
	},
	DustPuff = {
		{
			tex = "puff",
			count = 3,
			colour = rgb(205, 195, 170),
			size = grow(0.7, 1.9),
			life = { 0.3, 0.5 },
			speed = { 2, 5 },
			alpha = SOFT,
			drag = 4,
			rot = { 0, 360 },
		},
	},
	BreakPuff = {
		{
			tex = "puff",
			count = 4,
			colour = rgb(200, 185, 160),
			size = grow(1, 2.8),
			life = { 0.3, 0.5 },
			speed = { 4, 9 },
			alpha = SOFT,
			drag = 4,
			rot = { 0, 360 },
		},
		{
			tex = "shard",
			count = 8,
			colour = rgb(170, 120, 80),
			size = grow(0.7, 0.3),
			life = { 0.4, 0.7 },
			speed = { 12, 20 },
			spin = { -500, 500 },
			rot = { 0, 360 },
			accel = Vector3.new(0, -40, 0),
			alpha = POP,
			up = true,
		},
	},
	ShrineCharged = {
		{
			tex = "star4",
			count = 18,
			colour = rgb(255, 255, 255),
			size = grow(0.4, 1.4, 0),
			life = { 0.7, 1.2 },
			speed = { 10, 22 },
			glow = 1,
			up = true,
			ring = true,
			drag = 1.5,
		},
	},
	RootBurst = {
		{
			tex = "puff",
			count = 6,
			colour = rgb(120, 90, 60),
			size = grow(1.5, 4),
			life = { 0.4, 0.6 },
			speed = { 5, 12 },
			alpha = SOFT,
			drag = 3,
			rot = { 0, 360 },
		},
		{
			tex = "shard",
			count = 10,
			colour = rgb(110, 75, 45),
			size = grow(1.2, 0.4),
			life = { 0.5, 0.8 },
			speed = { 16, 28 },
			spin = { -400, 400 },
			rot = { 0, 360 },
			accel = Vector3.new(0, -44, 0),
			alpha = POP,
			up = true,
		},
	},
	Confetti = {
		{
			tex = "confetti",
			count = 40,
			colour = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(255, 90, 110)),
				ColorSequenceKeypoint.new(0.33, rgb(255, 225, 70)),
				ColorSequenceKeypoint.new(0.66, rgb(90, 220, 120)),
				ColorSequenceKeypoint.new(1, rgb(90, 180, 255)),
			}),
			size = grow(0.6, 0.5),
			life = { 1.2, 2 },
			speed = { 18, 34 },
			spin = { -500, 500 },
			rot = { 0, 360 },
			drag = 2.5,
			accel = Vector3.new(0, -22, 0),
			alpha = POP,
			up = true,
		},
	},
}

-- continuous emitters that ride on a part (projectile trails, auras)
local ATTACHED: { [string]: { any } } = {
	FireTrail = {
		{
			tex = "puff",
			rate = 38,
			colour = ColorSequence.new(rgb(255, 215, 80), rgb(235, 90, 25)),
			size = grow(1.5, 0.3),
			life = { 0.22, 0.34 },
			speed = { 0, 2 },
			glow = 0.8,
			rot = { 0, 360 },
		},
	},
	RocketTrail = {
		{
			tex = "puff",
			rate = 30,
			colour = rgb(255, 255, 255),
			size = grow(0.6, 1.5),
			life = { 0.3, 0.45 },
			speed = { 0, 2 },
			alpha = SOFT,
			rot = { 0, 360 },
		},
		{ tex = "star4", rate = 22, colour = rgb(255, 120, 200), size = grow(0.8, 0), life = { 0.2, 0.3 }, speed = { 2, 6 }, glow = 1 },
	},
	PaleTrail = {
		{
			tex = "dot",
			rate = 30,
			colour = rgb(245, 240, 225),
			size = grow(0.55, 0),
			life = { 0.16, 0.22 },
			speed = { 0, 0 },
			glow = 0.3,
			alpha = grow(0.4, 1),
		},
	},
	ThornTrail = {
		{
			tex = "dot",
			rate = 30,
			colour = rgb(60, 140, 60),
			size = grow(0.45, 0),
			life = { 0.16, 0.22 },
			speed = { 0, 0 },
			alpha = grow(0.3, 1),
		},
	},
	FrenzyAura = {
		{
			tex = "streak",
			rate = 16,
			colour = ColorSequence.new(rgb(255, 150, 40), rgb(255, 60, 30)),
			size = grow(1.2, 0),
			life = { 0.3, 0.5 },
			speed = { 6, 10 },
			glow = 1,
			up = true,
			ring = true,
			facing = "velocity",
		},
	},
	PortalSwirl = {
		{
			tex = "swirl",
			rate = 3,
			colour = rgb(150, 215, 255),
			size = grow(3, 7.5, 6),
			life = { 1, 1.2 },
			speed = { 0, 0 },
			glow = 0.9,
			spin = { 200, 240 },
			alpha = SOFT,
		},
		{ tex = "star4", rate = 14, colour = rgb(235, 250, 255), size = grow(0.2, 0.9, 0), life = { 0.6, 1 }, speed = { 2, 6 }, glow = 1 },
	},
	BossPortalWind = {
		{
			tex = "streak",
			rate = 18,
			colour = rgb(255, 70, 60),
			size = grow(2.6, 0.6),
			life = { 0.9, 1.4 },
			speed = { 16, 24 },
			glow = 1,
			up = true,
			ring = true,
			far = 9,
			facing = "velocity",
		},
	},
	EliteGlint = {
		{ tex = "star4", rate = 5, colour = rgb(255, 225, 90), size = grow(0.2, 1.1, 0), life = { 0.4, 0.6 }, speed = { 0, 1 }, glow = 1 },
	},
	RunnerEmbers = {
		{
			tex = "dot",
			rate = 14,
			colour = ColorSequence.new(rgb(255, 196, 70), rgb(255, 70, 30)),
			size = grow(0.45, 0.1),
			life = { 0.3, 0.5 },
			speed = { 1, 3 },
			up = true,
			glow = 1,
		},
	},
	GhostWisp = {
		{
			tex = "puff",
			rate = 9,
			colour = rgb(235, 245, 255),
			size = grow(1.3, 0.2),
			life = { 0.5, 0.8 },
			speed = { 0, 1 },
			alpha = grow(0.55, 1),
			rot = { 0, 360 },
		},
	},
	PoisonBubbles = {
		{
			tex = "dot",
			rate = 7,
			colour = rgb(130, 220, 70),
			size = grow(0.25, 0.6, 0),
			life = { 0.5, 0.8 },
			speed = { 2, 4 },
			up = true,
			alpha = POP,
		},
	},
	-- the Wardwood's air: golden pollen and the odd leaf, carried with the camera
	Pollen = {
		{
			tex = "dot",
			rate = 8,
			colour = ColorSequence.new(rgb(255, 238, 176), rgb(255, 250, 226)),
			size = grow(0.2, 0),
			life = { 4, 6 },
			speed = { 0.5, 2 },
			glow = 0.6,
			far = 70,
			accel = Vector3.new(1.2, 0.3, 0.6),
			alpha = grow(0.15, 1),
		},
		{
			tex = "leaf",
			rate = 1.2,
			colour = ColorSequence.new(rgb(176, 204, 84), rgb(214, 170, 70)),
			size = grow(0.55, 0.45),
			life = { 5, 7 },
			speed = { 1, 2 },
			far = 60,
			accel = Vector3.new(1.5, -0.8, 0.4),
			rot = { 0, 360 },
			spin = { -90, 90 },
			alpha = grow(0, 1),
		},
	},
	-- a brazier's fire: flames licking up, sparks drifting off
	BrazierFlame = {
		{
			tex = "puff",
			rate = 22,
			colour = ColorSequence.new(rgb(255, 214, 110), rgb(240, 96, 36)),
			size = grow(1.7, 0.3),
			life = { 0.45, 0.75 },
			speed = { 3, 5 },
			up = true,
			glow = 1,
			rot = { 0, 360 },
			alpha = grow(0.1, 1),
		},
		{
			tex = "dot",
			rate = 5,
			colour = rgb(255, 210, 120),
			size = grow(0.28, 0),
			life = { 1, 1.8 },
			speed = { 4, 7 },
			up = true,
			glow = 1,
			accel = Vector3.new(0.8, 1.5, 0.3),
			alpha = grow(0, 1),
		},
	},
	-- a hanging lamp: a small steady flame
	LampFlame = {
		{
			tex = "puff",
			rate = 9,
			colour = ColorSequence.new(rgb(255, 226, 140), rgb(255, 140, 60)),
			size = grow(0.7, 0.1),
			life = { 0.3, 0.5 },
			speed = { 1, 2 },
			up = true,
			glow = 1,
			rot = { 0, 360 },
		},
	},
	-- glints rising off a ward rune
	RuneMotes = {
		{
			tex = "dot",
			rate = 2.5,
			colour = rgb(255, 190, 110),
			size = grow(0.3, 0),
			life = { 2, 3 },
			speed = { 0.6, 1.4 },
			up = true,
			glow = 1,
			alpha = grow(0.1, 1),
		},
	},
	-- low teal mist hanging in the cold forest: huge, faint, slow
	ForestMist = {
		{
			tex = "puff",
			rate = 1.2,
			colour = ColorSequence.new(rgb(150, 198, 196), rgb(176, 214, 210)),
			size = grow(10, 18),
			life = { 7, 11 },
			speed = { 0.3, 0.9 },
			up = true,
			drag = 0.4,
			rot = { 0, 360 },
			spin = { -6, 6 },
			alpha = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.86),
				NumberSequenceKeypoint.new(0.7, 0.88),
				NumberSequenceKeypoint.new(1, 1),
			}),
		},
	},
	-- the foot of the falls: spray rising and drifting off
	FallsMist = {
		{
			tex = "puff",
			rate = 14,
			colour = rgb(236, 248, 248),
			size = grow(2.4, 6),
			life = { 1.2, 2 },
			speed = { 2, 5 },
			up = true,
			rot = { 0, 360 },
			alpha = grow(0.55, 1),
		},
	},
	-- the Moonwell: teal motes drifting up off the water
	MoonMotes = {
		{
			tex = "dot",
			rate = 12,
			colour = ColorSequence.new(rgb(120, 240, 222), rgb(200, 255, 246)),
			size = grow(0.35, 0),
			life = { 3, 5 },
			speed = { 0.5, 1.5 },
			up = true,
			glow = 1,
			alpha = grow(0.2, 1),
		},
	},
}

local folder: Folder
local hosts: { [string]: { any } } = {}

local function root(): Folder
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "Vfx"
		folder.Parent = Workspace
	end
	return folder
end

local function emitter(layer: any, parent: Instance): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = Vfx.Tex[layer.tex] or layer.tex
	e.Color = if typeof(layer.colour) == "ColorSequence" then layer.colour else ColorSequence.new(layer.colour)
	e.Size = layer.size
	e.Transparency = layer.alpha or POP
	e.Lifetime = NumberRange.new(layer.life[1], layer.life[2])
	e.Speed = NumberRange.new(layer.speed[1], layer.speed[2])
	e.SpreadAngle = if layer.up then Vector2.new(35, 35) else Vector2.new(180, 180)
	e.LightEmission = layer.glow or 0
	e.LightInfluence = 0
	e.Brightness = 1.6
	e.Drag = layer.drag or 0
	e.Acceleration = layer.accel or Vector3.zero
	e.ZOffset = layer.z or 0
	if layer.rot then
		e.Rotation = NumberRange.new(layer.rot[1], layer.rot[2])
	end
	if layer.spin then
		e.RotSpeed = NumberRange.new(layer.spin[1], layer.spin[2])
	end
	if layer.facing == "velocity" then
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
	end
	if layer.ring or layer.far then
		-- start on a ring or shell round the point instead of at it
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = if layer.speed[1] < 0 then Enum.ParticleEmitterShapeInOut.Inward else Enum.ParticleEmitterShapeInOut.Outward
	end
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = layer.rate or 0
	e.Enabled = layer.rate ~= nil
	e.Parent = parent
	return e
end

local function host(size: number): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(size, size, size)
	p.Parent = root()
	return p
end

--- Fire a named burst at a position. `options.tint` recolours every layer,
--- `options.scale` grows or shrinks the emit shape.
function Vfx.burst(name: string, position: Vector3, options: { tint: Color3?, count: number? }?)
	local preset = PRESETS[name]
	if not preset then
		return
	end
	local pool = hosts[name]
	if not pool then
		pool = { next = 1, list = {} }
		hosts[name] = pool
	end
	-- a handful of hosts per preset, used in turn, so several bursts in one frame
	-- each keep their own position
	local slot = pool.list[pool.next]
	if not slot then
		local far = 1
		for _, layer in preset do
			far = math.max(far, layer.far or (if layer.ring then 3 else 1))
		end
		local p = host(far)
		slot = { part = p, emitters = {} }
		for i, layer in preset do
			slot.emitters[i] = emitter(layer, p)
		end
		pool.list[pool.next] = slot
	end
	pool.next = pool.next % 8 + 1
	slot.part.CFrame = CFrame.new(position)
	for i, layer in preset do
		local e = slot.emitters[i]
		if options and options.tint then
			e.Color = ColorSequence.new(options.tint)
		end
		e:Emit(if options and options.count then options.count else layer.count)
	end
end

--- Put a continuous effect on a part. Returns the emitters so the caller can
--- stop them; they are destroyed with the part.
function Vfx.attach(name: string, part: BasePart): { ParticleEmitter }
	local out = {}
	local preset = ATTACHED[name]
	if preset then
		for _, layer in preset do
			table.insert(out, emitter(layer, part))
		end
	end
	return out
end

--- A continuous effect at a place in the world. Returns its invisible host part;
--- destroy the part (or its parent) to stop it.
function Vfx.place(name: string, cframe: CFrame, size: number, parent: Instance?): Part
	local p = host(size)
	p.CFrame = cframe
	if parent then
		p.Parent = parent
	end
	Vfx.attach(name, p)
	return p
end

-- flat shapes: a SurfaceGui on a thin part, unlit so it stays bright at night
local flats: { any } = {}

local function flat(): any
	local f = table.remove(flats)
	if f then
		return f
	end
	local p = host(1)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(256, 256)
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.Parent = p
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = gui
	return { part = p, gui = gui, image = image }
end

--- A flat textured shape on the ground (or at any height) that grows from
--- `fromRadius` to `toRadius` over `seconds` and fades out at the end.
--- `options.yaw` turns it, `options.spin` (degrees) turns it while it lives,
--- `options.alpha` is its starting transparency, `options.hold` keeps it fully
--- visible for that share of its life before fading.
function Vfx.ground(
	position: Vector3,
	tex: string,
	colour: Color3,
	fromRadius: number,
	toRadius: number,
	seconds: number,
	options: any?
): any
	local f = flat()
	local yaw = options and options.yaw or 0
	local alpha = options and options.alpha or 0
	f.image.Image = Vfx.Tex[tex] or tex
	f.image.ImageColor3 = colour
	f.image.ImageTransparency = alpha
	f.image.Rotation = 0
	f.part.Size = Vector3.new(fromRadius * 2, 0.05, fromRadius * 2)
	f.part.CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(f.part, info, { Size = Vector3.new(toRadius * 2, 0.05, toRadius * 2) }):Play()
	if options and options.spin then
		TweenService:Create(f.image, info, { Rotation = options.spin }):Play()
	end
	local hold = (options and options.hold or 0.45) * seconds
	local fadeInfo = TweenInfo.new(seconds - hold, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold)
	TweenService:Create(f.image, fadeInfo, { ImageTransparency = 1 }):Play()
	task.delay(seconds + 0.03, function()
		f.image.ImageTransparency = 1
		f.part.CFrame = CFrame.new(0, -500, 0)
		table.insert(flats, f)
	end)
	return f
end

-- lanes: a flat pill on a thin part, a fill growing along it
local lanes: { any } = {}

local function lane(): any
	local l = table.remove(lanes)
	if l then
		return l
	end
	local p = host(1)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(64, 256)
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.Parent = p
	local back = Instance.new("Frame")
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 1)
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Parent = gui
	for _, f in { back, fill } do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
	end
	return { part = p, back = back, fill = fill }
end

--- A lane on the ground from `from` to `to`, `width` studs wide: its fill runs
--- the length of it over `fillSeconds` (a charge's windup), then the lane
--- fades by `seconds`. Tilted to the ground at both ends.
function Vfx.lane(from: Vector3, to: Vector3, width: number, colour: Color3, fillSeconds: number, seconds: number)
	local flatDir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if flatDir.Magnitude < 0.2 then
		return
	end
	local l = lane()
	local length = (to - from).Magnitude
	l.part.Size = Vector3.new(width, 0.05, length)
	l.part.CFrame = CFrame.lookAt((from + to) / 2, to)
	l.back.BackgroundColor3 = colour
	l.back.BackgroundTransparency = 0.72
	l.fill.BackgroundColor3 = colour
	l.fill.BackgroundTransparency = 0.4
	l.fill.Size = UDim2.fromScale(1, 0)
	TweenService:Create(l.fill, TweenInfo.new(fillSeconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
	local fade = TweenInfo.new(math.max(seconds - fillSeconds, 0.05), Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, fillSeconds)
	TweenService:Create(l.back, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(l.fill, fade, { BackgroundTransparency = 1 }):Play()
	task.delay(seconds + 0.03, function()
		l.part.CFrame = CFrame.new(0, -500, 0)
		table.insert(lanes, l)
	end)
end

--- A lightning strip between two points, gone in a blink.
function Vfx.bolt(from: Vector3, to: Vector3, colour: Color3, width: number?, seconds: number?)
	local p = host(0.2)
	p.CFrame = CFrame.new(from)
	local a0 = Instance.new("Attachment")
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.WorldPosition = to
	a1.Parent = p
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Texture = Vfx.Tex.bolt
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.TextureSpeed = 0
	beam.Width0 = width or 7
	beam.Width1 = width or 7
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Brightness = 3
	beam.Color = ColorSequence.new(colour)
	beam.Segments = 1
	beam.Parent = p
	local life = seconds or 0.14
	task.delay(life * 0.6, function()
		beam.Transparency = NumberSequence.new(0.5)
	end)
	Debris:AddItem(p, life)
end

--- Whether a burst preset exists (the manifest test uses this).
function Vfx.has(name: string): boolean
	return PRESETS[name] ~= nil or ATTACHED[name] ~= nil
end

function Vfx.names(): { string }
	local out = {}
	for name in PRESETS do
		table.insert(out, name)
	end
	for name in ATTACHED do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

return Vfx

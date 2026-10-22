--!strict
-- Skyhold - the island hub (T6/T7): where it floats, its shape, where everything
-- on it stands, and the party rules' timings. Plain data, so the headless tools
-- (the Blender kit's plan export, the specs) read the same numbers as the game.
--
-- Every position here is island-local, in studs: x east, z south, y up, with
-- (0, 0, 0) the meadow's ground under the spawn's latitude. The island floats at
-- `Origin` in the world, far from the Wardwood, so the two never stream together.

local Skyhold = {
	Origin = { 3200, 320, 0 },

	-- the sky everyone on the island sees (shared/Look; a run brings its own)
	Sky = "skyhold",

	-- ---------------------------------------------------------------- shape
	-- the walkable island's rim, clockwise from the north, smoothed into a curve
	-- (Core/SkyholdGen.outline); the Blender kit hangs the cliffs from it
	Outline = {
		{ -18, -124 },
		{ 22, -126 },
		{ 58, -114 },
		{ 88, -98 },
		{ 112, -70 },
		{ 128, -36 },
		{ 138, 2 },
		{ 130, 40 },
		{ 112, 70 },
		{ 92, 92 },
		{ 58, 110 },
		{ 22, 124 },
		{ -14, 128 },
		{ -50, 122 },
		{ -84, 118 },
		{ -116, 124 },
		{ -130, 98 },
		{ -132, 62 },
		{ -140, 24 },
		{ -142, -14 },
		{ -136, -52 },
		{ -114, -86 },
		{ -84, -106 },
		{ -50, -118 },
	},
	-- the market islet across the rope bridge (scenery for later shops)
	Islet = {
		{ 128, 120 },
		{ 146, 106 },
		{ 170, 108 },
		{ 186, 126 },
		{ 184, 152 },
		{ 164, 170 },
		{ 138, 168 },
		{ 122, 148 },
	},
	IsletHeight = -3,
	-- terrain heights: flat-topped mounds with soft shoulders (Core/SkyholdGen)
	Plateaus = {
		-- name, centre x, z, radius x, z (the flat top), height, shoulder width
		{ name = "plaza", x = 0, z = -40, rx = 36, rz = 36, height = 6, blend = 11 },
		{ name = "dais", x = 0, z = -84, rx = 22, rz = 16, height = 6, blend = 11 },
		{ name = "hall", x = -96, z = -18, rx = 30, rz = 50, height = 10, blend = 18 },
		{ name = "knoll", x = 90, z = -10, rx = 16, rz = 18, height = 20, blend = 36 },
		{ name = "trophy", x = 70, z = -82, rx = 16, rz = 12, height = 12, blend = 21 },
	},
	MeadowRoll = 0.9, -- studs of gentle unevenness on the open meadow
	RimDip = 1.6, -- the ground sinks this much over the last RimWidth studs to the edge
	RimWidth = 7,
	CrustDepth = 16, -- terrain this deep under the surface; the Blender rock is below and around it
	-- worn earth paths, as polylines of { x, z } with a width
	Paths = {
		{ width = 7, points = { { 0, 104 }, { 0, 60 }, { 0, 14 }, { 0, -4 } } },
		{ width = 5, points = { { 0, 60 }, { 40, 72 }, { 78, 84 }, { 98, 92 } } },
		{ width = 5, points = { { -6, 30 }, { -48, 14 }, { -68, -4 } } },
		{ width = 5, points = { { 8, 26 }, { 44, 14 }, { 66, 2 }, { 82, -6 } } },
		{ width = 4, points = { { -40, 70 }, { -80, 92 }, { -106, 108 } } },
	},
	-- bare earth under the kit's paving, so Roblox's grass blades do not grow
	-- through it: the plaza (a disc), the portal's dais, the stairs, the hall terrace
	Paving = {
		{ x = 0, z = -40, r = 35 },
		{ x0 = -21, x1 = 21, z0 = -98, z1 = -78 },
		{ x0 = -8, x1 = 8, z0 = -5, z1 = 9 },
		{ x0 = -126, x1 = -77, z0 = -65, z1 = 29 },
	},

	-- ---------------------------------------------------------------- places
	-- yaw in degrees about y: a character at 0 faces north (-z); a kit asset
	-- at 0 shows its front to the south (+z)
	Spawn = { x = 0, z = 100, yaw = 0 }, -- facing north, up the meadow to the portal
	-- where a party steps out of the portal after a run, facing back down the plaza
	Return = { x = 0, z = -62, yaw = 180 },
	Portal = { x = 0, z = -88, yaw = 0 }, -- its face looks south, down the plaza
	PortalRadius = 12.9, -- the glowing face inside the ring (the kit's ring opens at 13.4)
	PortalCentreHeight = 19.8, -- the ring's centre above the ground
	PlazaCentre = { x = 0, z = -40 },
	-- the rune circles, in an arc before the portal (id = index)
	Circles = {
		{ x = -24, z = -46 },
		{ x = -9, z = -30 },
		{ x = 9, z = -30 },
		{ x = 24, z = -46 },
	},
	CircleRadius = 6,
	-- the Hall of Heroes: one plinth per Roster.HeroOrder entry, facing east
	Plinths = {
		{ x = -100, z = -44, yaw = 90 },
		{ x = -106, z = -18, yaw = 90 },
		{ x = -100, z = 8, yaw = 90 },
	},
	Lookout = { x = -110, z = 112 },
	Tree = { x = 94, z = -14 }, -- the old tree on the knoll
	Trophy = { x = 72, z = -88 },
	Bridge = { from = { 96, 90 }, to = { 130, 122 } },

	-- ---------------------------------------------------------------- parties
	SquadSize = 3, -- the most a rune circle holds (GameConfig.MaxPlayers runs it)
	JoinRange = 13, -- studs from a circle's centre to join it, start a party, or ready up
	CountdownSeconds = 5, -- everyone READY: this long on the portal before it opens
	SoloCountdownSeconds = 3,
	ActionGap = 0.25, -- seconds between two party messages a player may send

	-- ---------------------------------------------------------------- safety
	FallDepth = 90, -- below the island's ground by this much: back to the meadow
	RimWallHeight = 11, -- the invisible wall around the edge, above the ground there
}

return Skyhold

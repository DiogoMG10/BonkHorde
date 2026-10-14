--!strict
-- Wardwood - tunables for the isolated Wardwood visual prototype (branch
-- proto/wardwood). Nothing here is read unless ProtoGate activates the
-- prototype, which only happens in an armed, unpublished local Studio file.
--
-- EVERY value below is a starting point for tuning in Studio, not a validated
-- specification. Budgets and thresholds come from the prototype's measurements.

local Wardwood = {
	-- activation: the marker the arm snippet (tools/proto/arm.luau) creates
	MarkerName = "BonkProto",
	MarkerValue = "wardwood",
	LivePlaceId = 125855916502243, -- the shared BonkHorde place; never activates there

	-- the dressed region (studs, spawn at 0, 0). MossyWoods props inside it are
	-- replaced; everything outside stays as it is.
	Region = { minX = -170, maxX = 70, minZ = -110, maxZ = 110 },

	-- combat space: no solid prop and no ground cover inside this radius of spawn
	ClearingRadius = 48,
	-- paths kept free of trunks and rocks: polylines of { x, z } points
	PathHalfWidth = 6,
	Paths = {
		{ { 0, 0 }, { -40, 24 }, { -95, 30 }, { -150, 26 } }, -- spawn, ward, into the forest band, the dell rim
		{ { 0, 0 }, { -60, -40 }, { -120, -70 } },
	},

	-- the forest band to the west and the looser ring round the clearing
	BandMaxX = -72, -- trunks west of this x get the band density
	TrunkGrid = 11, -- jittered lattice spacing for trunk candidates
	TrunkKeepBand = 0.8, -- share of lattice points that grow a trunk in the band
	TrunkKeepRing = 0.32, -- ... and in the ring round the clearing
	TrunkRadius = 2, -- what enemies walk round
	TrunkGap = 7, -- minimum clear gap between solid props, as in MapGen
	TrunkScale = { 0.85, 1.25 },
	TrunkHeight = 46, -- studs at scale 1
	CanopyMinHeight = 16, -- canopy never hangs lower than this
	SlabCount = 12,
	SlabRadius = 5,
	FernCount = 70,
	MaxSlope = 0.45,
	AnchorClearance = 9, -- plus the prop radius, as in MapGen

	-- the ward landmark: a ruined platform of tiles round a brazier
	WardCenter = { -60, 30 }, -- preferred; moved to the nearest spot clear of anchors
	SpawnKeepClear = 42, -- MapGen's promise: no prop of any kind this close to spawn
	-- the ward's solid pieces only need to clear an interactable's own footprint,
	-- not MapGen's full margin: a chest or shrine on the ruin floor is welcome
	WardAnchorClearance = 5,
	WardTiles = 5, -- tiles per side
	WardTileSize = 6,
	WardPillarRadius = 2,
	WardStoneRadius = 2.5,
	WardBrazierRadius = 2,

	-- fixed viewpoints for comparisons: where the hero stands and the point the
	-- camera turns to face (lookAt = "ward" faces wherever the ward was placed).
	-- Set with `look cam <n>`.
	Viewpoints = {
		{ name = "clearing to ward", x = 6, z = -14, lookAt = "ward" },
		{ name = "clearing to forest band", x = -30, z = -6, lookX = -120, lookZ = 0 },
		{ name = "inside the band, back to the clearing", x = -110, z = 10, lookX = 0, lookZ = 0 },
	},

	-- the perf probe: default sampling window in seconds
	PerfSeconds = 20,
}

return Wardwood

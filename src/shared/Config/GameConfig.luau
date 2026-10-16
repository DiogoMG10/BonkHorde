--!strict
-- GameConfig - every scalar tunable in the game, in one place.
--
-- A number that a designer might want to change lives here (or in the roster
-- tables next to this file), never inline in a Service or Controller. This is
-- what makes a balance pass a data edit.

local GameConfig = {
	BuildStamp = "bonk-0.13.1-m5a",

	-- squad
	MaxPlayers = 3,
	IntroSeconds = 3,
	ResultsSeconds = 12,
	ExitCountdownSeconds = 4,

	-- stage clock
	StageSeconds = 600,
	OvertimeTierSeconds = 30,
	OvertimeNames = { "Easy", "Normal", "Hard", "Brutal", "Insane", "Unfair", "Why" },
	-- past the stage clock every tier compounds on the last (Core/Spawn): the first
	-- minutes are a fight, ten minutes in it is a wall. Enemy counts stay capped.
	OvertimeHPGrowth = 1.2, -- enemy health x this per tier (x3 after 2 min, x57 after 10)
	OvertimeDamageGrowth = 1.13, -- enemy damage x this per tier (x1.8 after 2 min, x13 after 10)
	OvertimeElitePerTier = 0.015, -- more of each wave are elites...
	OvertimeEliteMax = 0.5, -- ...up to this share

	-- simulation
	SimHz = 20,
	SnapshotHz = 10,
	EnemyCapSolo = 250,
	EnemyCapPerExtraPlayer = 50,
	EnemyHardCap = 380,
	SpawnBasePerSecond = 1.2,
	SpawnPerMinute = 0.7,
	SpawnRatePerExtraPlayer = 0.6,
	SpawnRingMin = 70,
	SpawnRingMax = 110,
	LeashDistance = 190,
	EnemyHPPerMinute = 0.12,
	EnemyDamagePerMinute = 0.04,
	BossHPPerExtraPlayer = 0.75,
	EnemySpeedScale = 2.6,
	EnemyDamageScale = 0.7,
	EnemySeparation = 3.2,
	ContactCooldown = 0.8,
	-- contact reach (Core/Contact): enemy body radius (roster `body`) + hero body + margin
	HeroBodyRadius = 1.2, -- the hero model's torso half-width; arms and ears do not count
	HeroHeight = 5.4, -- every hero model is fitted to this height
	ContactMargin = 0.15, -- was 0.6 on top of the movement radii
	ContactHeightTolerance = 0.3, -- a hero's feet this far above an enemy's head still touch it
	-- camping out of reach (a tree, a roof): a telegraphed root strike from below
	CampHeight = 6.5, -- feet this far above the terrain are out of every regular enemy's reach
	CampSeconds = 4, -- that long, with enemies below, before the first strike
	CampEvery = 3.5, -- then at most one strike this often
	CampWatchRange = 14, -- an enemy within this (horizontally) counts as waiting below
	CampStrikeDelay = 1.2, -- the warning before it lands: move to dodge it
	CampStrikeRadius = 4.5,
	CampStrikeDamage = 1.5, -- x the contact damage of the enemy below that calls it
	CampStrikeBelow = 3, -- it reaches feet this far under the height it was drawn at...
	CampStrikeAbove = 7.5, -- ...and this far over it (a jump on the spot does not dodge it)
	EliteHPMultiplier = 8,
	EliteScale = 1.5,
	EliteBaseChance = 0.02,
	EliteXP = 10,
	-- defence: Armor and Evasion are capped in Roster.Stats; lifesteal heals at most
	-- this share of max HP per second however many enemies a weapon hits
	LifestealPerSecond = 0.04,
	FreezeChanceMax = 0.75, -- a hit's whole freeze chance (stat, weapon, items) stops here
	OvertimeSpawnMultiplier = 1.6,

	-- player
	PlayerWalkSpeed = 20,
	PlayerJumpHeight = 7,
	PlayerRadius = 1.5,
	SlideBoost = 1.35,
	SlideDecayPerSecond = 0.55,
	SlideDownhillAccel = 34,
	SlideMaxMultiplier = 2.8, -- above the hop cap, so a downhill slide is still the fastest thing
	SlideMinSeconds = 0.3,
	-- bunny hop (Core/Hop): momentum is a multiplier on the hero's base speed
	HopGain = 0.15, -- per chained hop: from a run, the cap is reached after 10 hops
	HopMaxMultiplier = 2.5, -- chained hops never go faster than this x base speed (50 at base 20)
	HopWindow = 0.2, -- seconds on the ground after landing that a jump still chains
	HopMinSpeed = 0.7, -- a hop only counts when moving at this share of the current speed
	HopGroundDecay = 2, -- multiplier lost per second on the ground after the window
	HopStopDecay = 6, -- ...and with no movement input
	HopOverCapDecay = 0.5, -- slide speed carried above the cap drains this fast, in the air too
	HopKeep = 1.25, -- a jump keeps its speed while real speed is within 1/1.25 of it (walls drop it)
	HopSlideAfterJump = 0.2, -- seconds after a jump before a held slide key can start a slide
	AirAccel = 90, -- studs/s^2 of speed gained in the air towards the hop speed
	AirBrake = 20, -- studs/s^2 of slowdown in the air with no input (momentum mostly kept)
	AirTurnRate = 220, -- degrees/s the heading turns while steering in the air; speed is kept
	AirReverseBrake = 70, -- studs/s^2 lost pulling back against the run (a 180 is gradual)
	AirReverseAngle = 120, -- input more than this many degrees off the heading is pulling back
	SpeedFovKick = 10, -- extra degrees of FOV at the hop cap (less below, none at 1x)
	CameraDistance = 18,
	SpawnCameraYaw = 180, -- degrees; the first view looks north, past the Ward to the Highwatch
	CameraHeight = 3.5,
	CameraFOV = 80,
	CameraSensitivity = 0.35,
	CameraPitchMin = -75, -- degrees; how far the camera (and a hand-aimed shot) can look down...
	CameraPitchMax = 45, -- ...and up
	ShieldRegenDelay = 4,
	ShieldRegenPerSecond = 0.2, -- fraction of max shield
	InvulnAfterHit = 0.25,
	ReviveSeconds = 3,
	ReviveRadius = 7,
	ReviveHPFraction = 0.5,
	AimRange = 70,
	-- what a stacked late build may put in the air (performance, not balance: a
	-- build past these is already overwhelming)
	MaxShotsPerFire = 24, -- projectiles or swings from one attack
	MaxProjectiles = 320, -- in flight at once across the squad; a shot past it is not fired

	-- primary weapon (the hero's starting weapon, fired by hand)
	ManualPrimaryHeroes = { Knight = true, Fox = true, Frostling = true }, -- heroes whose weapon in slot 1 waits for the attack button
	PrimaryClickBuffer = 0.25, -- how long one click during the cooldown is remembered
	PrimaryHeldTimeout = 1, -- a held button the client stops confirming is dropped after this
	PrimaryInputRate = 20, -- attack-button messages accepted per second, per player
	PrimaryInputBurst = 20,
	PrimaryReachY = 9, -- how far above or below the hero a primary melee swing can touch

	-- player pause (P / Start)
	PauseVoteSeconds = 15, -- a co-op request lapses after this unless everyone agrees
	PauseCoopSeconds = 60, -- the longest an agreed co-op pause lasts
	PauseResumeSeconds = 3, -- countdown after anyone resumes a co-op pause early
	PauseAskCooldown = 30, -- seconds between two co-op requests from the same player

	-- XP and offers
	XPBase = 4,
	XPLinear = 5.5,
	XPQuadratic = 0,
	GemMergeRadius = 5,
	GemCap = 400,
	GoldCap = 300, -- coins on the ground; past it their value rides on the next coin picked up
	VacuumSeconds = 1.2, -- a magnet or vacuum shrine sweeps the whole map, nearest first, over this long
	PickupFlySpeed = 60,
	OfferCount = 3,
	OfferChoiceSecondsCoop = 12,
	PanelSecondsCoop = 15,
	BanishCharges = 1,
	SkipCharges = 5,
	RefreshCharges = 3,
	WeaponSlots = 4,
	TomeSlots = 4,
	UpgradeMaxLevel = 20, -- every weapon and tome stops here, and every stackable item at this many
	MaxedOutGold = 15, -- what a level-up, chest or pick with nothing left to give pays instead
	SkipGold = 5,
	LateJoinLevelFraction = 0.75,

	-- economy
	GoldDropChance = 0.5,
	GoldMinutesPerStep = 3,
	ChestPriceBase = 30,
	ChestPriceLinear = 40,
	ChestPriceQuadratic = 3,
	ShopPrice = { Common = 60, Rare = 120, Epic = 200, Legendary = 290 },
	-- Silver (Core/Progress.silver): every part of a run pays, each with diminishing
	-- returns, and the run as a whole is capped, so no run is ever worth an unlock on
	-- its own (Minty is 150). tests/Rules.spec.luau pins the reference payouts.
	SilverPerStageMinute = 0.8, -- surviving the stage clock (up to its 10 minutes)
	SilverKillMax = 35, -- kills pay towards this...
	SilverKillScale = 2500, -- ...about two thirds of it by this many kills
	SilverPerMinibossKill = 3,
	SilverPerBossKill = 10,
	SilverForEscape = 4, -- leaving through the portal after the boss
	SilverOvertimeMax = 30, -- overtime survived pays towards this...
	SilverOvertimeHalfLife = 240, -- ...half of it in this many seconds
	SilverGainCap = 1.5, -- Silver Gain counts up to this multiplier
	SilverRunCap = 120, -- the most one run can pay

	-- interactables
	InteractRange = 9,
	ChargeShrineSeconds = 8,
	ChargeShrineRadius = 22,
	GreedDifficultyStep = 0.05,
	GreedGoldStep = 0.10,
	ChallengeEliteCount = 6,
	PotGold = 6,
	PotXP = 4,
	CratePowerupChance = 0.2,
	PowerupDropChance = 0.004,
	SnackHealFraction = 0.25,
	FrenzySeconds = 10,
	FrenzyBonus = 0.5,
	InteractablesPerRun = {
		-- scaled with the playable area (M3.A) so they are about as close together as before
		Chest = 22,
		ChargeShrine = 9,
		GreedShrine = 3,
		ChallengeShrine = 3,
		VacuumShrine = 2,
		SmugStatue = 3,
		DodgyDan = 1,
		Pot = 46,
		Crate = 24,
	},

	-- map
	MapSizeStuds = 1200, -- the terrain, mountains included
	PlaySizeStuds = 960, -- the playable world inside them (the big map shows this)
	HeightCellStuds = 4,
	MapSeed = 20261012,
	WallHeight = 230, -- the highest the mountain backdrop may rise
	CliffSlope = 1.2, -- rise over run above which a cell edge is a cliff for enemies
	BossPortalMinDistance = 220,
	BossPortalMaxDistance = 400, -- a bigger world, but finding the portal stays part of a run, not a trek
	PortalRevealDistance = 70,

	-- persistence
	DataStoreName = "BonkHorde_v1",
	AutosaveSeconds = 60,
}

return GameConfig

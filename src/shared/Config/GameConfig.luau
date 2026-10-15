--!strict
-- GameConfig - every scalar tunable in the game, in one place.
--
-- A number that a designer might want to change lives here (or in the roster
-- tables next to this file), never inline in a Service or Controller. This is
-- what makes a balance pass a data edit.

local GameConfig = {
	BuildStamp = "bonk-0.5.4-m2a",

	-- squad
	MaxPlayers = 3,
	IntroSeconds = 3,
	ResultsSeconds = 12,
	ExitCountdownSeconds = 4,

	-- stage clock
	StageSeconds = 600,
	OvertimeTierSeconds = 30,
	OvertimeNames = { "Easy", "Normal", "Hard", "Brutal", "Insane", "Unfair", "Why" },
	OvertimeSilverStep = 0.15,

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
	EliteHPMultiplier = 8,
	EliteScale = 1.5,
	EliteBaseChance = 0.02,
	EliteXP = 10,
	OvertimeSpawnMultiplier = 1.6,

	-- player
	PlayerWalkSpeed = 20,
	PlayerJumpHeight = 7,
	PlayerRadius = 1.5,
	SlideBoost = 1.35,
	SlideDecayPerSecond = 0.55,
	SlideDownhillAccel = 34,
	SlideMaxMultiplier = 2.4,
	SlideMinSeconds = 0.3,
	CameraDistance = 18,
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
	PickupFlySpeed = 60,
	OfferCount = 3,
	OfferChoiceSecondsCoop = 12,
	PanelSecondsCoop = 15,
	BanishCharges = 1,
	SkipCharges = 5,
	RefreshCharges = 3,
	WeaponSlots = 4,
	TomeSlots = 4,
	SkipGold = 5,
	LateJoinLevelFraction = 0.75,

	-- economy
	GoldDropChance = 0.5,
	GoldMinutesPerStep = 3,
	ChestPriceBase = 30,
	ChestPriceLinear = 40,
	ChestPriceQuadratic = 3,
	ShopPrice = { Common = 60, Rare = 120, Epic = 200, Legendary = 290 },
	SilverPerHundredKills = 1,
	SilverPerBossKill = 10,
	SilverPerMinibossKill = 3,

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
		Chest = 14,
		ChargeShrine = 6,
		GreedShrine = 2,
		ChallengeShrine = 2,
		VacuumShrine = 1,
		SmugStatue = 2,
		DodgyDan = 1,
		Pot = 30,
		Crate = 16,
	},

	-- map
	MapSizeStuds = 720,
	HeightCellStuds = 4,
	MapSeed = 20261012,
	WallHeight = 80,
	CliffSlope = 1.2, -- rise over run above which a cell edge is a cliff for enemies
	BossPortalMinDistance = 220,
	PortalRevealDistance = 70,

	-- persistence
	DataStoreName = "BonkHorde_v1",
	AutosaveSeconds = 60,
}

return GameConfig

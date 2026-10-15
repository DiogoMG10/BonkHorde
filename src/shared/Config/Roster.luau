--!strict
-- Roster - the content tables: stats, heroes, weapons, tomes, items, enemies,
-- bosses, shrine boosts and rarities. Pure data. design/game.json is where this
-- list was decided; this file is what the game reads.

local Roster = {}

-- ---------------------------------------------------------------- rarities
Roster.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
Roster.RarityWeights = { Common = 60, Uncommon = 25, Rare = 10, Epic = 4, Legendary = 1 }
Roster.RarityLuckFactor = { Common = 0, Uncommon = 1, Rare = 2, Epic = 3, Legendary = 4 }
Roster.RarityMultiplier = { Common = 1.0, Uncommon = 1.2, Rare = 1.4, Epic = 1.6, Legendary = 2.0 }
Roster.ItemRarityOrder = { "Common", "Rare", "Epic", "Legendary" }
Roster.ItemRarityWeights = { Common = 60, Rare = 28, Epic = 9, Legendary = 3 }

-- ---------------------------------------------------------------- stats
-- The 31 stats of the stats panel, in display order, with their defaults.
-- fmt: "int" plain number, "pct" value*100 + %, "mult" value + x, "permin" /min.
Roster.StatGroups = {
	{ "MaxHP", "HPRegen", "Overheal", "Shield", "Armor", "Evasion", "Lifesteal", "Thorns" },
	{ "Damage", "CritChance", "CritDamage", "AttackSpeed", "ProjectileCount", "ProjectileBounces" },
	{ "Size", "ProjectileSpeed", "Duration", "DamageToElites", "Knockback", "MoveSpeed" },
	{ "ExtraJumps", "JumpHeight", "Luck", "Difficulty" },
	{
		"PickupRange",
		"XPGain",
		"GoldGain",
		"SilverGain",
		"EliteSpawnIncrease",
		"PowerupMultiplier",
		"PowerupDropChance",
	},
}

Roster.Stats = {
	MaxHP = { name = "Max HP", default = 100, fmt = "int" },
	HPRegen = { name = "HP Regen", default = 10, fmt = "int" },
	Overheal = { name = "Overheal", default = 0, fmt = "int" },
	Shield = { name = "Shield", default = 0, fmt = "int" },
	Armor = { name = "Armor", default = 0, fmt = "pct" },
	Evasion = { name = "Evasion", default = 0, fmt = "pct" },
	Lifesteal = { name = "Lifesteal", default = 0, fmt = "pct" },
	Thorns = { name = "Thorns", default = 0, fmt = "int" },
	Damage = { name = "Damage", default = 1, fmt = "mult" },
	CritChance = { name = "Crit Chance", default = 0.01, fmt = "pct" },
	CritDamage = { name = "Crit Damage", default = 2, fmt = "mult" },
	AttackSpeed = { name = "Attack Speed", default = 1, fmt = "pct" },
	ProjectileCount = { name = "Projectile Count", default = 0, fmt = "int" },
	ProjectileBounces = { name = "Projectile Bounces", default = 0, fmt = "int" },
	Size = { name = "Size", default = 1, fmt = "mult" },
	ProjectileSpeed = { name = "Projectile Speed", default = 1, fmt = "mult" },
	Duration = { name = "Duration", default = 1, fmt = "mult" },
	DamageToElites = { name = "Damage to Elites", default = 1, fmt = "mult" },
	Knockback = { name = "Knockback", default = 1, fmt = "mult" },
	MoveSpeed = { name = "Movement Speed", default = 1, fmt = "mult" },
	ExtraJumps = { name = "Extra Jumps", default = 0, fmt = "int" },
	JumpHeight = { name = "Jump Height", default = 7, fmt = "int" },
	Luck = { name = "Luck", default = 0, fmt = "pct" },
	Difficulty = { name = "Difficulty", default = 0, fmt = "pct" },
	PickupRange = { name = "Pickup Range", default = 10, fmt = "int" },
	XPGain = { name = "XP Gain", default = 1, fmt = "mult" },
	GoldGain = { name = "Gold Gain", default = 1, fmt = "mult" },
	SilverGain = { name = "Silver Gain", default = 1, fmt = "mult" },
	EliteSpawnIncrease = { name = "Elite Spawn Increase", default = 1, fmt = "mult" },
	PowerupMultiplier = { name = "Powerup Multiplier", default = 1, fmt = "mult" },
	PowerupDropChance = { name = "Powerup Drop Chance", default = 1, fmt = "mult" },
	-- hidden: not shown in the panel
	FreezeChance = { name = "Freeze Chance", default = 0, fmt = "pct", hidden = true },
}

-- ---------------------------------------------------------------- heroes
Roster.HeroOrder = { "Knight", "Fox", "Frostling" }
Roster.Heroes = {
	Knight = {
		name = "Sir Clonk",
		blurb = "Slow, but all that armour makes him properly chunky.",
		weapon = "Sword",
		passiveName = "Thick Plating",
		passiveText = "Gain 1% Armor per level.",
		passive = { stat = "Armor", perLevel = 0.01 },
		base = { MaxHP = 50, Armor = 0.15, MoveSpeed = -0.1 }, -- deltas on the defaults
		unlockSilver = 0,
		colour = { 150, 156, 166 },
	},
	Fox = {
		name = "Zib",
		blurb = "A fox in a wizard hat. Luck does most of the work.",
		weapon = "FireStaff",
		passiveName = "Lucky Tail",
		passiveText = "Gain 1% Luck per level.",
		passive = { stat = "Luck", perLevel = 0.01 },
		base = { Luck = 0.05 },
		unlockSilver = 0,
		colour = { 232, 120, 40 },
	},
	Frostling = {
		name = "Minty",
		blurb = "Chilly hooded mage. Stand close, regret it.",
		weapon = "FrostRing",
		passiveName = "Brain Freeze",
		passiveText = "Gain 0.5% Freeze Chance per level.",
		passive = { stat = "FreezeChance", perLevel = 0.005 },
		base = { MaxHP = -10, Shield = 25, MoveSpeed = 0.05 },
		unlockSilver = 150,
		colour = { 70, 200, 190 },
	},
}

-- ---------------------------------------------------------------- weapons
-- kind is the behaviour the server runs. base holds the weapon's own numbers;
-- pool lists what a level-up can roll and the Common amount of each.
Roster.WeaponOrder = {
	"Sword",
	"FireStaff",
	"FrostRing",
	"LightningStaff",
	"Bone",
	"Boomernana",
	"Axe",
	"PartyRocket",
}
Roster.Weapons = {
	Sword = {
		name = "Sword",
		text = "Slashes through multiple enemies.",
		kind = "Arc",
		base = {
			Damage = 11,
			Cooldown = 1.1,
			Size = 1,
			ProjectileCount = 1,
			Knockback = 3,
			Range = 13,
			Arc = 140,
		},
		pool = { Damage = 2, Size = 0.2, ProjectileCount = 1, Knockback = 0.5, CritChance = 0.08 },
	},
	FireStaff = {
		name = "Fire Staff",
		text = "Lobs fireballs that explode on impact.",
		kind = "Fireball",
		base = {
			Damage = 9,
			Cooldown = 1.4,
			Size = 1,
			ProjectileCount = 1,
			ProjectileSpeed = 1,
			Range = 70,
			Speed = 60,
			Radius = 9,
			Knockback = 1,
		},
		pool = {
			Damage = 2,
			Size = 0.15,
			ProjectileCount = 1,
			ProjectileSpeed = 0.1,
			CritDamage = 0.4,
		},
	},
	FrostRing = {
		name = "Frost Ring",
		text = "Freezes and damages enemies around you.",
		kind = "Aura",
		base = {
			Damage = 9,
			Cooldown = 1.6,
			Size = 1,
			Duration = 1.6,
			Range = 14,
			Knockback = 0,
			Freeze = 0.12,
		},
		pool = { Damage = 2, Size = 0.1, Duration = 0.12, CritChance = 0.08 },
	},
	LightningStaff = {
		name = "Lightning Staff",
		text = "Summons lightning to smite nearby enemies.",
		kind = "Lightning",
		base = {
			Damage = 9.4,
			Cooldown = 1.5,
			Size = 1,
			ProjectileCount = 1,
			ProjectileBounces = 0,
			Range = 45,
			Radius = 5,
			Knockback = 0.5,
		},
		pool = {
			Damage = 2,
			Size = 0.2,
			ProjectileCount = 1,
			ProjectileBounces = 1,
			CritChance = 0.08,
		},
	},
	Bone = {
		name = "Bone",
		text = "Throws bones that bounce off enemies.",
		kind = "Bounce",
		base = {
			Damage = 8,
			Cooldown = 1.2,
			ProjectileCount = 1,
			ProjectileSpeed = 1,
			ProjectileBounces = 2,
			Range = 60,
			Speed = 55,
			Radius = 2.5,
			Knockback = 1,
			CritChance = 0.1,
		},
		pool = {
			Damage = 2,
			ProjectileCount = 1,
			ProjectileSpeed = 0.3,
			ProjectileBounces = 1,
			CritChance = 0.12,
			CritDamage = 0.4,
		},
	},
	Boomernana = {
		name = "Boomernana",
		text = "A banana that always comes back. Hits twice.",
		kind = "Boomerang",
		base = {
			Damage = 9,
			Cooldown = 1.8,
			ProjectileCount = 1,
			ProjectileSpeed = 1,
			Size = 1,
			Range = 42,
			Speed = 50,
			Radius = 4,
			Knockback = 1.5,
		},
		pool = {
			Damage = 2,
			ProjectileCount = 1,
			ProjectileSpeed = 0.1,
			Size = 0.2,
			Knockback = 0.5,
		},
	},
	Axe = {
		name = "Axe",
		text = "Hurls spinning axes that hang around and shred.",
		kind = "Linger",
		base = {
			Damage = 7,
			Cooldown = 2.2,
			ProjectileCount = 1,
			Duration = 2,
			Size = 1,
			Range = 35,
			Radius = 6,
			Tick = 0.4,
			Knockback = 0.5,
		},
		pool = { Damage = 2, ProjectileCount = 1, Duration = 0.25, Size = 0.15, CritChance = 0.08 },
	},
	PartyRocket = {
		name = "Party Rocket",
		text = "Fires homing rockets. Fashionably late, very loud.",
		kind = "Homing",
		base = {
			Damage = 14,
			Cooldown = 2.6,
			ProjectileCount = 1,
			ProjectileSpeed = 1,
			Size = 1,
			Range = 90,
			Speed = 48,
			Radius = 10,
			Knockback = 2,
		},
		pool = {
			Damage = 2,
			ProjectileCount = 1,
			ProjectileSpeed = 0.1,
			Size = 0.15,
			CritDamage = 0.4,
		},
	},
}

-- ---------------------------------------------------------------- tomes
Roster.TomeOrder = {
	"Damage",
	"Agility",
	"Cooldown",
	"Precision",
	"Size",
	"Shield",
	"Health",
	"Regen",
	"XP",
	"Luck",
	"Attraction",
	"Quantity",
}
Roster.Tomes = {
	Damage = { name = "Damage Tome", stat = "Damage", perLevel = 0.08 },
	Agility = { name = "Agility Tome", stat = "MoveSpeed", perLevel = 0.15 },
	Cooldown = { name = "Cooldown Tome", stat = "AttackSpeed", perLevel = 0.075 },
	Precision = { name = "Precision Tome", stat = "CritChance", perLevel = 0.07 },
	Size = { name = "Size Tome", stat = "Size", perLevel = 0.1 },
	Shield = { name = "Shield Tome", stat = "Shield", perLevel = 25 },
	Health = { name = "Health Tome", stat = "MaxHP", perLevel = 25 },
	Regen = { name = "Regen Tome", stat = "HPRegen", perLevel = 40 },
	XP = { name = "XP Tome", stat = "XPGain", perLevel = 0.07 },
	Luck = { name = "Luck Tome", stat = "Luck", perLevel = 0.07 },
	Attraction = { name = "Attraction Tome", stat = "PickupRange", perLevel = 7.5 },
	Quantity = { name = "Quantity Tome", stat = "ProjectileCount", perLevel = 1, noRarity = true },
}

-- ---------------------------------------------------------------- items
-- stats: flat deltas applied when the item is taken. proc: a named effect the
-- server's ItemService implements, with its numbers in `n`.
Roster.Items = {
	TickingBracelet = {
		name = "Ticking Bracelet",
		rarity = "Common",
		text = "+8% XP Gain. Definitely just a watch.",
		stats = { XPGain = 0.08 },
	},
	LuckyClover = {
		name = "Lucky Clover",
		rarity = "Common",
		text = "+7.5% Luck.",
		stats = { Luck = 0.075 },
	},
	ZoomSocks = {
		name = "Zoom Socks",
		rarity = "Common",
		text = "+8% Movement Speed.",
		stats = { MoveSpeed = 0.08 },
	},
	ProteinGoop = {
		name = "Protein Goop",
		rarity = "Common",
		text = "+8% Damage.",
		stats = { Damage = 0.08 },
	},
	SusJuice = {
		name = "Sus Juice",
		rarity = "Common",
		text = "+6% Crit Chance.",
		stats = { CritChance = 0.06 },
	},
	DodgyBattery = {
		name = "Dodgy Battery",
		rarity = "Common",
		text = "+8% Attack Speed.",
		stats = { AttackSpeed = 0.08 },
	},
	BandageBox = {
		name = "Bandage Box",
		rarity = "Common",
		text = "+10 Max HP and +30 HP Regen per minute.",
		stats = { MaxHP = 10, HPRegen = 30 },
	},
	StinkyCheese = {
		name = "Stinky Cheese",
		rarity = "Common",
		text = "25% chance to poison enemies on hit.",
		proc = "Poison",
		n = { chance = 0.25, dps = 0.3, seconds = 3 },
	},
	FrostShard = {
		name = "Frost Shard",
		rarity = "Common",
		text = "4% chance to freeze enemies on hit for 1.5s.",
		stats = { FreezeChance = 0.04 },
	},
	GiantSlayerPin = {
		name = "Giant Slayer Pin",
		rarity = "Common",
		text = "+15% Damage to Elites and Bosses.",
		stats = { DamageToElites = 0.15 },
	},
	ShrineWrench = {
		name = "Shrine Wrench",
		rarity = "Rare",
		text = "Charge Shrines charge 30% faster and give 10% bigger rewards.",
		proc = "Wrench",
		n = { speed = 0.3, bonus = 0.1 },
	},
	GildedSneakers = {
		name = "Gilded Sneakers",
		rarity = "Rare",
		text = "Earn 1 gold for every 25 studs you run.",
		proc = "Sneakers",
		n = { studs = 25 },
	},
	EchoGem = {
		name = "Echo Gem",
		rarity = "Rare",
		text = "8% chance for a kill to drop an extra XP gem.",
		proc = "EchoGem",
		n = { chance = 0.08 },
	},
	PocketCampfire = {
		name = "Pocket Campfire",
		rarity = "Rare",
		text = "Standing still for 1s heals 3 HP per second.",
		proc = "Campfire",
		n = { hps = 3, still = 1 },
	},
	Featherweight = {
		name = "Featherweight",
		rarity = "Rare",
		text = "+1 Extra Jump and +10% Jump Height.",
		stats = { ExtraJumps = 1, JumpHeight = 0.7 },
	},
	StaticMitts = {
		name = "Static Mitts",
		rarity = "Rare",
		text = "Every 6th hit calls a lightning strike for 120% damage.",
		proc = "StaticMitts",
		n = { every = 6, mult = 1.2, radius = 6 },
	},
	SkeletonKey = {
		name = "Skeleton Key",
		rarity = "Rare",
		text = "15% chance a chest opens for free.",
		proc = "SkeletonKey",
		n = { chance = 0.15 },
	},
	AutoTrigger = {
		name = "Auto-Trigger",
		rarity = "Rare",
		text = "Your main weapon attacks by itself when an enemy is in reach. Clicking still comes first.",
		proc = "AutoTrigger",
		unique = true, -- a second one would do nothing, so it is never offered again
	},
	VampireMitts = {
		name = "Vampire Mitts",
		rarity = "Epic",
		text = "+4% Lifesteal.",
		stats = { Lifesteal = 0.04 },
	},
	Nightlight = {
		name = "Nightlight",
		rarity = "Epic",
		text = "Every 9s a pulse of light deals 300% damage to everything within 22 studs.",
		proc = "Nightlight",
		n = { every = 9, mult = 3, radius = 22 },
	},
	CrackedGoggles = {
		name = "Cracked Goggles",
		rarity = "Epic",
		text = "+1% Damage for every 1% of HP you are missing.",
		proc = "Goggles",
		n = { perPercent = 0.01 },
	},
	PanicMirror = {
		name = "Panic Mirror",
		rarity = "Epic",
		text = "Getting hit reflects 200% of it and makes you untouchable for 0.6s. 3s cooldown.",
		proc = "Mirror",
		n = { mult = 2, invuln = 0.6, cooldown = 3, radius = 12 },
	},
	VolatileMeatball = {
		name = "Volatile Meatball",
		rarity = "Legendary",
		text = "Attacks have a 25% chance to explode for 65% damage to everything nearby.",
		proc = "Meatball",
		n = { chance = 0.25, mult = 0.65, radius = 9 },
	},
	BigIceCube = {
		name = "Big Ice Cube",
		rarity = "Legendary",
		text = "20% chance to deal 50% bonus ice damage on hit. Ice can freeze.",
		proc = "IceCube",
		n = { chance = 0.2, mult = 0.5, freeze = 0.35 },
	},
	ColossalFork = {
		name = "Colossal Fork",
		rarity = "Legendary",
		text = "Crits have a 12% chance to become Megacrits for triple crit damage.",
		proc = "Fork",
		n = { chance = 0.12, mult = 3 },
	},
	SecondWindClock = {
		name = "Second Wind Clock",
		rarity = "Legendary",
		text = "A killing blow leaves you at 30% HP and freezes every enemy for 4s. Breaks after one use.",
		proc = "SecondWind",
		n = { hp = 0.3, freeze = 4 },
	},
}
Roster.ItemOrder = {
	"TickingBracelet",
	"LuckyClover",
	"ZoomSocks",
	"ProteinGoop",
	"SusJuice",
	"DodgyBattery",
	"BandageBox",
	"StinkyCheese",
	"FrostShard",
	"GiantSlayerPin",
	"ShrineWrench",
	"GildedSneakers",
	"EchoGem",
	"PocketCampfire",
	"Featherweight",
	"StaticMitts",
	"SkeletonKey",
	"AutoTrigger",
	"VampireMitts",
	"Nightlight",
	"CrackedGoggles",
	"PanicMirror",
	"VolatileMeatball",
	"BigIceCube",
	"ColossalFork",
	"SecondWindClock",
}

-- ---------------------------------------------------------------- enemies
-- speed is in the reference's units; the sim multiplies by EnemySpeedScale.
-- Order matters: the index is the type id sent over the network.
Roster.EnemyOrder = {
	"GoblinRunt",
	"GoblinBruiser",
	"Slime",
	"Skeleton",
	"ShieldSkeleton",
	"RockGolem",
	"Ghost",
	"Twiglet",
	"BoulderBro",
	"Hamlet",
	"OldManTimber",
}
Roster.Enemies = {
	GoblinRunt = {
		name = "Goblin Runt",
		hp = 7,
		dmg = 15,
		speed = 5.0,
		radius = 1.3,
		height = 3.2,
		xp = 1,
		colour = { 96, 190, 60 },
	},
	GoblinBruiser = {
		name = "Goblin Bruiser",
		hp = 15,
		dmg = 25,
		speed = 5.5,
		radius = 1.7,
		height = 4.6,
		xp = 2,
		colour = { 60, 140, 50 },
	},
	Slime = {
		name = "Slime",
		hp = 6,
		dmg = 8,
		speed = 6.5,
		radius = 1.4,
		height = 2.4,
		xp = 1,
		hop = true,
		colour = { 140, 235, 60 },
	},
	Skeleton = {
		name = "Skeleton",
		hp = 20,
		dmg = 20,
		speed = 5.5,
		radius = 1.5,
		height = 4.8,
		xp = 2,
		colour = { 230, 225, 205 },
	},
	ShieldSkeleton = {
		name = "Shield Skeleton",
		hp = 30,
		dmg = 25,
		speed = 4.0,
		radius = 1.8,
		height = 5.0,
		xp = 3,
		kbResist = 0.5,
		colour = { 180, 180, 175 },
	},
	RockGolem = {
		name = "Rock Golem",
		hp = 20,
		dmg = 20,
		speed = 5.0,
		radius = 2.4,
		height = 6.0,
		xp = 3,
		kbResist = 1,
		hpScale = 2.2,
		colour = { 130, 135, 140 },
	},
	Ghost = {
		name = "Ghost",
		hp = 10,
		dmg = 10,
		speed = 6.0,
		radius = 1.6,
		height = 3.6,
		xp = 1,
		flying = true,
		colour = { 245, 245, 250 },
	},
	Twiglet = {
		name = "Twiglet",
		hp = 40,
		dmg = 18,
		speed = 6.0,
		radius = 1.5,
		height = 3.4,
		xp = 3,
		colour = { 120, 85, 50 },
	},
	BoulderBro = {
		name = "Boulder Bro",
		hp = 250,
		dmg = 40,
		speed = 6.0,
		radius = 5.5,
		height = 14,
		xp = 50,
		boss = "mini",
		kbResist = 1,
		hpScale = 6,
		colour = { 110, 125, 110 },
	},
	Hamlet = {
		name = "Hamlet the Hangry",
		hp = 320,
		dmg = 40,
		speed = 6.5,
		radius = 5,
		height = 13,
		xp = 50,
		boss = "mini",
		kbResist = 1,
		hpScale = 6,
		colour = { 235, 190, 175 },
	},
	OldManTimber = {
		name = "Old Man Timber",
		hp = 9000,
		dmg = 40,
		speed = 3.0,
		radius = 9,
		height = 26,
		xp = 200,
		boss = "stage",
		kbResist = 1,
		colour = { 125, 80, 45 },
	},
}

-- which regular types spawn from which second of the stage clock
Roster.SpawnTimeline = {
	{ from = 0, types = { "GoblinRunt" } },
	{ from = 90, types = { "GoblinRunt", "GoblinRunt", "Slime" } },
	{ from = 120, types = { "GoblinRunt", "Slime", "GoblinBruiser" } },
	{ from = 180, types = { "Slime", "GoblinBruiser", "Skeleton" } },
	{ from = 300, types = { "GoblinBruiser", "Skeleton", "Skeleton", "ShieldSkeleton" } },
	{ from = 420, types = { "Skeleton", "ShieldSkeleton", "RockGolem" } },
}
Roster.BossSpawnTypes = { "Twiglet", "Skeleton", "RockGolem" }
Roster.OvertimeTypes = { "Ghost", "Ghost", "Ghost", "ShieldSkeleton", "RockGolem" }
Roster.ChallengeTypes = { "GoblinBruiser", "Skeleton", "ShieldSkeleton" }
Roster.Minibosses = { "BoulderBro", "Hamlet" }
Roster.MinibossTimes = { 240, 450 }
Roster.StageBoss = "OldManTimber"

-- ---------------------------------------------------------------- charge shrine boosts
Roster.ShrineBoosts = {
	{ stat = "JumpHeight", amount = 0.7, text = "10% Jump Height" },
	{ stat = "CritChance", amount = 0.05, text = "5% Crit Chance" },
	{ stat = "EliteSpawnIncrease", amount = 0.15, text = "15% Elite Spawn Increase" },
	{ stat = "MoveSpeed", amount = 0.066, text = "6.6% Movement Speed" },
	{ stat = "HPRegen", amount = 30, text = "30 HP Regen" },
	{ stat = "SilverGain", amount = 0.08, text = "8% Silver Gain" },
	{ stat = "MaxHP", amount = 15, text = "15 Max HP" },
	{ stat = "Damage", amount = 0.05, text = "5% Damage" },
	{ stat = "AttackSpeed", amount = 0.05, text = "5% Attack Speed" },
	{ stat = "XPGain", amount = 0.06, text = "6% XP Gain" },
	{ stat = "GoldGain", amount = 0.08, text = "8% Gold Gain" },
	{ stat = "PickupRange", amount = 1.5, text = "15% Pickup Range" },
	{ stat = "Luck", amount = 0.04, text = "4% Luck" },
	{ stat = "Armor", amount = 0.03, text = "3% Armor" },
	{ stat = "Size", amount = 0.05, text = "5% Size" },
	{ stat = "Shield", amount = 10, text = "10 Shield" },
	{ stat = "Lifesteal", amount = 0.01, text = "1% Lifesteal" },
	{ stat = "Evasion", amount = 0.02, text = "2% Evasion" },
	{ stat = "CritDamage", amount = 0.1, text = "10% Crit Damage" },
	{ stat = "DamageToElites", amount = 0.08, text = "8% Damage to Elites" },
	{ stat = "Thorns", amount = 5, text = "5 Thorns" },
	{ stat = "Duration", amount = 0.05, text = "5% Duration" },
}

-- ---------------------------------------------------------------- interactables, pickups
-- Order matters: the index is the kind id sent over the network.
Roster.InteractableOrder = {
	"Chest",
	"ChargeShrine",
	"GreedShrine",
	"ChallengeShrine",
	"VacuumShrine",
	"SmugStatue",
	"DodgyDan",
	"BossPortal",
	"Pot",
	"Crate",
	"Tombstone",
}
Roster.InteractablePrompt = {
	Chest = "Open chest",
	ChargeShrine = "Stand in the dome",
	GreedShrine = "Get greedy",
	ChallengeShrine = "Start the challenge",
	VacuumShrine = "Pull every gem",
	SmugStatue = "Ask the statue",
	DodgyDan = "Browse Dan's deals",
	BossPortal = "Summon the boss",
}
Roster.PickupOrder = { "XPGem", "GoldCoin", "PowerupMagnet", "PowerupSnack", "PowerupFrenzy" }

Roster.Maps = {
	MossyWoods = {
		name = "Mossy Woods",
		joke = "Smells like wet goblin.",
		blurb = "Trees, ruins and great vibes. Everything here wants you gone.",
		locked = false,
	},
	Desert = {
		name = "Crusty Dunes",
		joke = "",
		blurb = "Hot, dry and dusty. Opens in a later update.",
		locked = true,
	},
	Graveyard = {
		name = "Spooky Yard",
		joke = "",
		blurb = "Ghosts and other spooks. Opens in a later update.",
		locked = true,
	},
}
Roster.MapOrder = { "MossyWoods", "Desert", "Graveyard" }

Roster.DeathJokes = {
	"the horde says gg",
	"skill issue? couldn't be.",
	"have you tried not dying?",
	"bonked. thoroughly.",
}

return Roster

--!strict
-- The preview cases for design/ui_specs/Screens_build.py, printed as JSON:
-- the screens the pause menu and the end screens are drawn on, laid out by the
-- game's own Core/PanelLayout, and a sample run's inspector cards, stats sheet
-- and Silver, written by the game's own Core/Inspect and Core/Progress, so the
-- previews show exactly what the game would.
--
--     lune run design/ui_specs/screens_cases.luau

local serde = require("@lune/serde")

local GameConfig = require("../../src/shared/Config/GameConfig")
local Inspect = require("../../src/shared/Core/Inspect")
local PanelLayout = require("../../src/shared/Core/PanelLayout")
local Progress = require("../../src/shared/Core/Progress")
local Roster = require("../../src/shared/Config/Roster")
local Stats = require("../../src/shared/Core/Stats")

-- topbar: the part of Roblox's bar its buttons leave free (drawn in the previews)
local screens = {
	desktop = {
		width = 1920,
		height = 1080,
		core = { left = 0, top = 58, right = 0, bottom = 0 },
		topbar = { x0 = 250, y0 = 0, x1 = 1920, y1 = 58 },
	},
	laptop = {
		width = 1366,
		height = 768,
		core = { left = 0, top = 58, right = 0, bottom = 0 },
		topbar = { x0 = 250, y0 = 0, x1 = 1366, y1 = 58 },
	},
	phone = {
		width = 844,
		height = 390,
		core = { left = 47, top = 36, right = 47, bottom = 21 },
		topbar = { x0 = 210, y0 = 0, x1 = 797, y1 = 36 },
	},
}

local out = { screens = {}, margin = PanelLayout.Margin }
for name, screen in screens do
	out.screens[name] = {
		screen = screen,
		pause = PanelLayout.pause(screen),
		death = PanelLayout.fit(screen, PanelLayout.Death.width, PanelLayout.Death.height),
		results = PanelLayout.fit(screen, PanelLayout.Results.width, PanelLayout.Results.height),
	}
end

-- a sample run: Sir Clonk at level 14, eight minutes in
local hero = Roster.Heroes.Knight
local function weapon(id: string, level: number, add: { [string]: number }, primary: boolean?)
	local s = table.clone(Roster.Weapons[id].base)
	for k, v in add do
		s[k] = (s[k] or 0) + v
	end
	return { id = id, level = level, s = s, primary = primary == true }
end
local weapons = {
	weapon("Sword", 7, { Damage = 8.4, Size = 0.4, CritChance = 0.08 }, true),
	weapon("Bone", 4, { Damage = 4, ProjectileBounces = 1 }),
	weapon("LightningStaff", 3, { ProjectileCount = 1 }),
	weapon("Axe", 2, { Damage = 2.4 }),
}
local tomes = {
	{ id = "Damage", level = 5, gained = 0.48 },
	{ id = "Health", level = 3, gained = 90 },
	{ id = "Cooldown", level = 2, gained = 0.165 },
	{ id = "Luck", level = 1, gained = 0.07 },
}
local items = {
	{ id = "ZoomSocks", count = 3 },
	{ id = "TickingBracelet", count = 2 },
	{ id = "ProteinGoop", count = 2 },
	{ id = "BandageBox", count = 2 },
	{ id = "FrostShard", count = 2 },
	{ id = "LuckyClover", count = 1 },
	{ id = "SusJuice", count = 1 },
	{ id = "StinkyCheese", count = 1 },
	{ id = "GiantSlayerPin", count = 1 },
	{ id = "ShrineWrench", count = 1 },
	{ id = "EchoGem", count = 1 },
	{ id = "StaticMitts", count = 1 },
	{ id = "Nightlight", count = 1 },
	{ id = "AutoTrigger", count = 1 },
}
local bonus = { Difficulty = 0.1 }
for _, t in tomes do
	Stats.add(bonus, Roster.Tomes[t.id].stat, t.gained)
end
for _, it in items do
	for stat, amount in Roster.Items[it.id].stats or {} do
		Stats.add(bonus, stat, amount * it.count)
	end
end
local stats = Stats.compute(Roster.Stats, hero.base, hero.passive.stat, hero.passive.perLevel, 14, bonus)

local cards = {}
for _, w in weapons do
	table.insert(cards, Inspect.weapon(w, true))
end
for _, t in tomes do
	table.insert(cards, Inspect.tome(t, stats))
end
for _, it in items do
	table.insert(cards, Inspect.item(it))
end

out.run = {
	hero = "Knight",
	heroName = hero.name,
	level = 14,
	weapons = weapons,
	tomes = tomes,
	items = items,
	sections = Inspect.sections(stats),
	cards = cards,
	maxLevel = GameConfig.UpgradeMaxLevel,
}

-- a co-op victory at 9:48 with the boss down, for the results
local summary = { stageSeconds = 588, overtimeSeconds = 0, kills = 2140, minibossKills = 2, bossKills = 1, escaped = true }
local total, parts = Progress.silver(summary, 1.08, GameConfig)
local mateTotal = Progress.silver(summary, 1, GameConfig)
out.results = { parts = parts, silver = total, gain = 1.08, mateSilver = mateTotal, cap = GameConfig.SilverRunCap }

-- and a solo wipe at 6:12, one miniboss down, for the phone
local wipe = { stageSeconds = 372, overtimeSeconds = 0, kills = 1240, minibossKills = 1, bossKills = 0, escaped = false }
local wipeTotal, wipeParts = Progress.silver(wipe, 1, GameConfig)
out.defeat = { parts = wipeParts, silver = wipeTotal, gain = 1, mateSilver = 0, cap = GameConfig.SilverRunCap }

print(serde.encode("json", out))

--!strict
-- Specs for T3: what the pause menu's inspector and stats sheet say (Core/Inspect).
-- The rule under test: every number shown is one the server sent or a fixed
-- roster value, never an estimate.

local GameConfig = require("../src/shared/Config/GameConfig")
local Inspect = require("../src/shared/Core/Inspect")
local Roster = require("../src/shared/Config/Roster")
local Stats = require("../src/shared/Core/Stats")

local function lineValue(card, label: string): string?
	for _, line in card.lines do
		if line.label == label then
			return line.value
		end
	end
	return nil
end

return {
	["the stats sheet shows every stat the panel lists, once, except Overheal"] = function()
		local seen = {}
		for _, section in Inspect.Sections do
			for _, key in section.stats do
				assert(Roster.Stats[key] ~= nil, "undefined stat " .. key)
				assert(not Roster.Stats[key].hidden, "a hidden stat on the sheet: " .. key)
				assert(not seen[key], "shown twice: " .. key)
				seen[key] = true
			end
		end
		for _, group in Roster.StatGroups do
			for _, key in group do
				if key ~= "Overheal" then
					assert(seen[key], "missing from the sheet: " .. key)
				end
			end
		end
		assert(not seen.Overheal, "Overheal does nothing in the game and must not be shown")
	end,

	["the sheet reads the resolved stats and marks what moved"] = function()
		local hero = Roster.Heroes.Knight
		local stats = Stats.compute(Roster.Stats, hero.base, hero.passive.stat, hero.passive.perLevel, 6, { Damage = 0.24 })
		local rows = {}
		for _, section in Inspect.sections(stats) do
			for _, row in section.rows do
				rows[row.key] = row
			end
		end
		assert(rows.Damage.value == "1.24x" and rows.Damage.tone == "up", rows.Damage.value)
		assert(rows.Armor.value == "20%" and rows.Armor.tone == "up", rows.Armor.value) -- 15% base + 5 levels of 1%
		assert(rows.MoveSpeed.value == "0.9x" and rows.MoveSpeed.tone == "down", rows.MoveSpeed.value)
		assert(rows.Luck.tone == nil, "an untouched stat is not marked")
		assert(rows.HPRegen.value == "10/min", rows.HPRegen.value)
	end,

	["more difficulty is marked harder, not better"] = function()
		local rows = {}
		for _, section in Inspect.sections({ Difficulty = 0.1, EliteSpawnIncrease = 1.15 }) do
			for _, row in section.rows do
				rows[row.key] = row
			end
		end
		assert(rows.Difficulty.tone == "harder" and rows.Difficulty.value == "10%")
		assert(rows.EliteSpawnIncrease.tone == "harder")
	end,

	["a weapon shows its own numbers as the server sent them"] = function()
		local s = table.clone(Roster.Weapons.Sword.base)
		s.Damage = 19
		s.CritChance = 0.08
		local card = Inspect.weapon({ id = "Sword", level = 5, s = s, primary = true }, false)
		assert(card.name == "Sword" and card.tag == "LVL 5")
		assert(lineValue(card, "Damage") == "19")
		assert(lineValue(card, "Cooldown") == "1.1s")
		assert(lineValue(card, "Size") == "100%")
		assert(lineValue(card, "Crit chance") == "+8%")
		assert(lineValue(card, "Arc") == nil, "internal values stay out")
		assert(string.find(card.note or "", "click or hold", 1, true), "the main weapon says how it attacks")
	end,

	["a capped weapon reads MAX, an automatic one says so"] = function()
		local card = Inspect.weapon({ id = "Bone", level = GameConfig.UpgradeMaxLevel, s = Roster.Weapons.Bone.base }, false)
		assert(card.tag == "MAX")
		assert(string.find(card.note or "", "by itself", 1, true))
		local lightning = Inspect.weapon({ id = "LightningStaff", level = 1, s = Roster.Weapons.LightningStaff.base }, false)
		assert(lineValue(lightning, "Bounces") == nil, "a zero says nothing and is left out")
	end,

	["a tome shows what it gave only when the server recorded it"] = function()
		local without = Inspect.tome({ id = "Damage", level = 4 }, { Damage = 1.46 })
		assert(lineValue(without, "Each level") == "+8%")
		assert(lineValue(without, "From this tome") == nil, "no total is guessed from level x base (rarity changes it)")
		assert(lineValue(without, "Your Damage") == "1.46x")
		local with = Inspect.tome({ id = "Damage", level = 4, gained = 0.46 }, nil)
		assert(lineValue(with, "From this tome") == "+46%")
		local health = Inspect.tome({ id = "Health", level = 2, gained = 60 }, nil)
		assert(lineValue(health, "From this tome") == "+60", lineValue(health, "From this tome"))
	end,

	["an item stack totals its flat stats exactly"] = function()
		local one = Inspect.item({ id = "TickingBracelet", count = 1 })
		assert(#one.lines == 0 and one.tag == "x1" and one.rarity == "Common")
		local three = Inspect.item({ id = "TickingBracelet", count = 3 })
		assert(lineValue(three, "XP Gain") == "+24%", lineValue(three, "XP Gain"))
		local bandages = Inspect.item({ id = "BandageBox", count = 2 })
		assert(lineValue(bandages, "Max HP") == "+20")
		assert(lineValue(bandages, "HP Regen") == "+60/min")
		local proc = Inspect.item({ id = "StaticMitts", count = 2 })
		assert(#proc.lines == 0, "a proc item's effect is described, not totalled")
		assert(Inspect.item({ id = "AutoTrigger", count = 1 }).tag == "UNIQUE")
	end,

	["unknown ids never break the inspector"] = function()
		assert(Inspect.weapon({ id = "Nope", level = 1 }, false).name == "Nope")
		assert(Inspect.tome({ id = "Nope", level = 1 }, nil).name == "Nope")
		assert(Inspect.item({ id = "Nope", count = 2 }).tag == "x2")
	end,
}

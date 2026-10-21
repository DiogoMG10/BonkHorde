--!strict
-- Inspect - what the pause menu says about one weapon, tome or item, and the
-- stats sheet in titled sections.
--
-- Pure, and it only reads: every number is one the server sent (a weapon's own
-- values, what a tome has given, the resolved stat block) or a fixed roster
-- value. Nothing is recomputed, and a number the client cannot know exactly
-- (a tome's total before the server recorded it) is left out, not estimated.

local GameConfig = require(script and script.Parent.Parent.Config.GameConfig or "../Config/GameConfig")
local Roster = require(script and script.Parent.Parent.Config.Roster or "../Config/Roster")
local Stats = require(script and script.Parent.Stats or "./Stats")

local Inspect = {}

export type Line = { label: string, value: string }
export type Card = {
	kind: string, -- "weapon" | "tome" | "item"
	id: string,
	name: string,
	tag: string, -- "LVL 5", "MAX", "x3", "UNIQUE"
	rarity: string?, -- items only
	text: string,
	lines: { Line },
	note: string?, -- one short line under the numbers
}
export type Row = { key: string, name: string, value: string, tone: string? } -- "up" | "down" | "harder"
export type Section = { title: string, rows: { Row } }

-- The stats sheet. Every stat the game reads, each once; Overheal is defined
-- but nothing in the game reads it, so it is not shown.
Inspect.Sections = {
	{ title = "Survival", stats = { "MaxHP", "HPRegen", "Shield", "Armor", "Evasion", "Thorns" } },
	{
		title = "Offense",
		stats = { "Damage", "CritChance", "CritDamage", "AttackSpeed", "ProjectileCount", "ProjectileBounces", "DamageToElites" },
	},
	{ title = "Weapon effects", stats = { "Size", "ProjectileSpeed", "Duration", "Knockback" } },
	{ title = "Movement", stats = { "MoveSpeed", "ExtraJumps", "JumpHeight" } },
	{ title = "Utility", stats = { "PickupRange", "XPGain", "GoldGain", "SilverGain", "Luck" } },
	{ title = "Run", stats = { "Difficulty", "EliteSpawnIncrease", "PowerupMultiplier", "PowerupDropChance" } },
}

-- more of these makes the run harder (and pays more), so it is not "better"
local HARDER = { Difficulty = true, EliteSpawnIncrease = true }
-- units the plain number would leave out
local SUFFIX = { HPRegen = "/min" }

-- A weapon's own numbers, in the order they are shown, with how each reads.
-- Its other values (projectile speed in studs, arc, tick) are internal.
local WEAPON_LINES = {
	{ key = "Damage", label = "Damage", fmt = "num" },
	{ key = "Cooldown", label = "Cooldown", fmt = "sec" },
	{ key = "ProjectileCount", label = "Projectiles", fmt = "int" },
	{ key = "ProjectileBounces", label = "Bounces", fmt = "int" },
	{ key = "Size", label = "Size", fmt = "pct" },
	{ key = "Range", label = "Range", fmt = "int" },
	{ key = "Duration", label = "Duration", fmt = "sec" },
	{ key = "Knockback", label = "Knockback", fmt = "num" },
	{ key = "CritChance", label = "Crit chance", fmt = "bonus" },
	{ key = "CritDamage", label = "Crit damage", fmt = "bonus" },
	{ key = "Freeze", label = "Freeze chance", fmt = "pct" },
	{ key = "FreezeSeconds", label = "Freeze for", fmt = "sec" },
}

local function trim(n: number): string
	local s = string.format("%.2f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

local function weaponValue(fmt: string, value: number): string
	if fmt == "sec" then
		return trim(value) .. "s"
	elseif fmt == "pct" then
		return trim(value * 100) .. "%"
	elseif fmt == "bonus" then
		return "+" .. trim(value * 100) .. "%"
	elseif fmt == "int" then
		return tostring(math.floor(value + 0.5))
	end
	return trim(value)
end

--- How a change to a stat reads: "+8%" for a share or a multiplier, "+25" for a
--- plain number (the way shrine boosts are worded).
function Inspect.delta(stat: string, amount: number): string
	local def = Roster.Stats[stat]
	local sign = if amount < 0 then "-" else "+"
	local body = if def and def.fmt == "int" then trim(math.abs(amount)) else trim(math.abs(amount) * 100) .. "%"
	return sign .. body .. (SUFFIX[stat] or "")
end

--- How a resolved stat reads on the sheet.
function Inspect.value(stat: string, value: number?): string
	local def = Roster.Stats[stat]
	if not def then
		return trim(value or 0)
	end
	return Stats.format(def.fmt, value or def.default) .. (SUFFIX[stat] or "")
end

local function levelTag(level: number?): string
	level = level or 1
	return if level >= GameConfig.UpgradeMaxLevel then "MAX" else `LVL {level}`
end

--- One weapon in the loadout. `entry` is the server's { id, level, s, primary };
--- `autoTrigger` whether the hero carries the Auto-Trigger item.
function Inspect.weapon(entry: any, autoTrigger: boolean?): Card
	local def = Roster.Weapons[entry.id]
	local own = entry.s or (def and def.base) or {}
	local lines = {}
	for _, spec in WEAPON_LINES do
		local v = own[spec.key]
		if typeof(v) == "number" and v ~= 0 then -- a zero (no bounces, no knockback) says nothing
			table.insert(lines, { label = spec.label, value = weaponValue(spec.fmt, v) })
		end
	end
	local note
	if entry.primary and autoTrigger then
		note = "Your main weapon: click or hold, or let Auto-Trigger fire it. Your stats boost these numbers."
	elseif entry.primary then
		note = "Your main weapon: click or hold to attack. Your stats boost these numbers."
	else
		note = "Attacks by itself. Your stats boost these numbers."
	end
	return {
		kind = "weapon",
		id = entry.id,
		name = if def then def.name else tostring(entry.id),
		tag = levelTag(entry.level),
		text = if def then def.text else "",
		lines = lines,
		note = note,
	}
end

--- One tome. `entry` is the server's { id, level, gained? }: `gained` is what
--- its level-ups have added, rarity included. `stats` is the resolved block.
function Inspect.tome(entry: any, stats: { [string]: number }?): Card
	local def = Roster.Tomes[entry.id]
	if not def then
		return { kind = "tome", id = entry.id, name = tostring(entry.id), tag = levelTag(entry.level), text = "", lines = {} }
	end
	local statDef = Roster.Stats[def.stat]
	local statName = if statDef then statDef.name else def.stat
	local lines = {
		{ label = "Each level", value = Inspect.delta(def.stat, def.perLevel) },
	}
	if typeof(entry.gained) == "number" then
		table.insert(lines, { label = "From this tome", value = Inspect.delta(def.stat, entry.gained) })
	end
	if stats and stats[def.stat] ~= nil then
		table.insert(lines, { label = `Your {statName}`, value = Inspect.value(def.stat, stats[def.stat]) })
	end
	return {
		kind = "tome",
		id = entry.id,
		name = def.name,
		tag = levelTag(entry.level),
		text = `Raises your {statName} with every level.`,
		lines = lines,
		note = if def.noRarity then "Every level adds the same." else "Rarer level-ups add more.",
	}
end

--- One item. `entry` is the server's { id, count }.
function Inspect.item(entry: any): Card
	local def = Roster.Items[entry.id]
	local count = math.max(1, tonumber(entry.count) or 1)
	if not def then
		return { kind = "item", id = entry.id, name = tostring(entry.id), tag = `x{count}`, text = "", lines = {} }
	end
	local lines = {}
	local note
	if def.stats and count > 1 then
		-- flat values: the total is exact, so it is worth showing
		local keys = {}
		for stat in def.stats do
			table.insert(keys, stat)
		end
		table.sort(keys)
		for _, stat in keys do
			local statDef = Roster.Stats[stat]
			table.insert(lines, {
				label = if statDef then statDef.name else stat,
				value = Inspect.delta(stat, def.stats[stat] * count),
			})
		end
		note = `Total from all {count}.`
	elseif count > 1 then
		note = `You carry {count}.`
	end
	return {
		kind = "item",
		id = entry.id,
		name = def.name,
		tag = if def.unique then "UNIQUE" else `x{count}`,
		rarity = def.rarity,
		text = def.text,
		lines = lines,
		note = note,
	}
end

--- The stats sheet: titled sections of rows, in display order. A value away
--- from its default is marked "up" or "down" ("harder" for difficulty).
function Inspect.sections(stats: { [string]: number }?): { Section }
	local out = {}
	for _, section in Inspect.Sections do
		local rows = {}
		for _, key in section.stats do
			local def = Roster.Stats[key]
			if def and not def.hidden then
				local value = if stats and stats[key] ~= nil then stats[key] else def.default
				local tone = nil
				if math.abs(value - def.default) > 1e-6 then
					tone = if HARDER[key] then "harder" elseif value > def.default then "up" else "down"
				end
				table.insert(rows, { key = key, name = def.name, value = Inspect.value(key, value), tone = tone })
			end
		end
		table.insert(out, { title = section.title, rows = rows })
	end
	return out
end

return Inspect

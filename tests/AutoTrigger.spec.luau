--!strict
-- Specs for the three manual primaries and the Auto-Trigger item, on the pure
-- cooldown rule: every hero's weapon keeps its automatic cadence, the item
-- shares that one cooldown, and the button always comes first.

local GameConfig = require("../src/shared/Config/GameConfig")
local PrimaryTrigger = require("../src/shared/Core/PrimaryTrigger")
local Roster = require("../src/shared/Config/Roster")

local STEP = 1 / GameConfig.SimHz
local BUFFER = GameConfig.PrimaryClickBuffer

-- Run a primary for `seconds`. `each(tick, simNow, input)` may press or
-- release before every tick; `target(tick)` says whether Auto-Trigger finds
-- something in reach (nil: no item). Returns attacks by hand, by the item, and
-- how many times the item was asked.
local function simulate(
	cooldown: number,
	seconds: number,
	each: (number, number, PrimaryTrigger.Input) -> (),
	target: ((number) -> boolean)?
): (number, number, number)
	local input = PrimaryTrigger.new()
	local cd = 0.4
	local hand, auto, asked = 0, 0, 0
	local now = 0
	for tick = 1, math.floor(seconds / STEP + 0.5) do
		now += STEP
		each(tick, now, input)
		local ask = nil
		if target then
			ask = function(): boolean
				asked += 1
				return target(tick)
			end
		end
		local left, fires, byHand = PrimaryTrigger.step(input, cd, STEP, cooldown, now, BUFFER, ask)
		cd = left
		if fires and byHand then
			hand += 1
		elseif fires then
			auto += 1
		end
	end
	return hand, auto, asked
end

local function idle() end
local function always(): boolean
	return true
end

local function hold(_tick: number, now: number, input: PrimaryTrigger.Input)
	PrimaryTrigger.press(input, 0, now, now)
end

-- what an automatic weapon fires in `seconds`, starting 0.4 s from ready
local function automatic(cooldown: number, seconds: number): number
	local cd, n = 0.4, 0
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		cd -= STEP
		if cd <= 0 then
			cd += cooldown
			n += 1
		end
	end
	return n
end

local HEROES = { "Knight", "Fox", "Frostling" }

return {
	["every hero's starting weapon is a manual primary"] = function()
		for _, id in HEROES do
			assert(GameConfig.ManualPrimaryHeroes[id], id .. " is not manual")
		end
	end,

	["holding each hero's primary keeps its automatic cadence"] = function()
		for _, id in HEROES do
			local cooldown = Roster.Weapons[Roster.Heroes[id].weapon].base.Cooldown
			local hand = simulate(cooldown, 60, hold)
			local expected = automatic(cooldown, 60)
			assert(math.abs(hand - expected) <= 1, `{id}: {hand} held vs {expected} automatic`)
		end
	end,

	["auto-trigger with a target always in reach fires at the automatic cadence"] = function()
		for _, id in HEROES do
			local cooldown = Roster.Weapons[Roster.Heroes[id].weapon].base.Cooldown
			local hand, auto = simulate(cooldown, 60, idle, always)
			local expected = automatic(cooldown, 60)
			assert(hand == 0, "no attack is by hand")
			assert(math.abs(auto - expected) <= 1, `{id}: {auto} auto vs {expected} automatic`)
		end
	end,

	["holding with auto-trigger never adds an attack, and every one is by hand"] = function()
		local cooldown = Roster.Weapons.Sword.base.Cooldown
		local held = simulate(cooldown, 60, hold)
		local hand, auto, asked = simulate(cooldown, 60, hold, always)
		assert(hand == held, `{hand} with the item vs {held} without`)
		assert(auto == 0 and asked == 0, "the item is never asked while the button is held")
	end,

	["clicking over auto-trigger is no faster than auto-trigger alone"] = function()
		local cooldown = Roster.Weapons.FireStaff.base.Cooldown
		local _, alone = simulate(cooldown, 30, idle, always)
		local hand, auto = simulate(cooldown, 30, function(tick, now, input)
			if tick % 2 == 1 then
				PrimaryTrigger.press(input, 0, now, now)
			else
				PrimaryTrigger.release(input, now)
			end
		end, always)
		assert(hand + auto <= alone, `{hand} + {auto} mixed vs {alone} alone`)
	end,

	["a click on a ready weapon is the player's, not the item's"] = function()
		local input = PrimaryTrigger.new()
		local asked = false
		PrimaryTrigger.press(input, 1, 1, 1)
		PrimaryTrigger.release(input, 1)
		local _, fires, byHand = PrimaryTrigger.step(input, 0, STEP, 1, 1, BUFFER, function()
			asked = true
			return true
		end)
		assert(fires and byHand and not asked)
	end,

	["auto-trigger is not asked while the weapon cools down"] = function()
		local _, auto, asked = simulate(1.6, 0.3, idle, always)
		assert(auto == 0 and asked == 0)
	end,

	["with nothing in reach auto-trigger waits, and banks nothing"] = function()
		-- nothing for 10 s, then a target for one tick only: one attack, not a backlog
		local _, auto = simulate(1.4, 12, idle, function(tick)
			return tick == math.floor(10 / STEP)
		end)
		assert(auto == 1, `{auto} attacks`)
	end,

	["auto-trigger is a unique rare item that is offered"] = function()
		local def = Roster.Items.AutoTrigger
		assert(def and def.rarity == "Rare" and def.unique)
		assert(table.find(Roster.ItemOrder, "AutoTrigger"))
	end,
}

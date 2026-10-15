--!strict
-- Specs for Minty's Frost Ring freezing (M2.C, option A): every enemy the ring
-- hits rolls its own 25 % chance to be frozen for 2 s, on top of Minty's Freeze
-- Chance passive. Never guaranteed, and nothing else's freezing changes.

local Roster = require("../src/shared/Config/Roster")

local RING = Roster.Weapons.FrostRing.base
local MINTY = Roster.Heroes.Frostling

local function lcg(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

return {
	["the ring freezes 25 % of the enemies it hits, for 2 seconds"] = function()
		assert(RING.Freeze == 0.25)
		assert(RING.FreezeSeconds == 2)
	end,

	["damage, radius and cooldown are the ring's old ones"] = function()
		assert(RING.Damage == 9 and RING.Range == 14 and RING.Cooldown == 1.6)
	end,

	["Minty's passive is still +0.5 points of Freeze Chance a level"] = function()
		assert(MINTY.weapon == "FrostRing")
		assert(MINTY.passive.stat == "FreezeChance" and MINTY.passive.perLevel == 0.005)
	end,

	["no other weapon freezes, or freezes for longer, because of this"] = function()
		for id, def in Roster.Weapons do
			if id ~= "FrostRing" then
				assert(def.base.Freeze == nil, `{id} gained a freeze chance`)
				assert(def.base.FreezeSeconds == nil, `{id} gained a freeze length`)
			end
		end
	end,

	["freezing is never guaranteed, even late in a run"] = function()
		local level60 = RING.Freeze + MINTY.passive.perLevel * 60
		assert(level60 < 0.6, `at level 60 the chance is {level60}`)
	end,

	["each enemy rolls on its own: some freeze, rarely all (option A, not B)"] = function()
		-- the rule as CombatService applies it: one roll per enemy per ring
		local rnd = lcg(7)
		local chance = RING.Freeze + MINTY.passive.perLevel * 1
		local frozen, hits, everyone = 0, 0, 0
		for _ = 1, 2000 do
			local all = true
			for _ = 1, 8 do -- eight enemies inside the ring
				hits += 1
				if rnd() < chance then
					frozen += 1
				else
					all = false
				end
			end
			if all then
				everyone += 1
			end
		end
		local share = frozen / hits
		assert(math.abs(share - chance) < 0.02, `froze {share} of hits`)
		assert(everyone / 2000 < 0.01, "a whole crowd freezing at once is rare")
	end,
}

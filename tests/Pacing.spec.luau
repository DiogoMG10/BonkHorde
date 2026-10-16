--!strict
-- Specs for the horde's rhythm (M4.B, Core/Pacing) and the packs that open
-- each surge (Roster.Packs), plus attacks taking turns on a hero (Attacks.turn).

local Attacks = require("../src/shared/Core/Attacks")
local GameConfig = require("../src/shared/Config/GameConfig")
local Pacing = require("../src/shared/Core/Pacing")
local Roster = require("../src/shared/Config/Roster")

local c = GameConfig
local CALM, CYCLE, RATES = c.PaceCalmSeconds, c.PaceCycle, c.PaceRates

return {
	["the run opens calm, then cycles build, surge, ebb, lull"] = function()
		assert(Pacing.phase(0, CALM, CYCLE, RATES) == "calm")
		assert(Pacing.phase(CALM - 0.1, CALM, CYCLE, RATES) == "calm")
		local order = {}
		local last = ""
		local total = CYCLE.build + CYCLE.surge + CYCLE.ebb + CYCLE.lull
		for t = CALM, CALM + total * 2 - 0.5, 0.5 do
			local phase, _, index = Pacing.phase(t, CALM, CYCLE, RATES)
			if phase ~= last then
				table.insert(order, `{phase}{index}`)
				last = phase
			end
		end
		local want = "build1 surge1 ebb1 lull1 build2 surge2 ebb2 lull2"
		assert(table.concat(order, " ") == want, table.concat(order, " "))
	end,

	["the first minute is gentle and the first spike comes after it"] = function()
		local first = Pacing.nextSurge(0, CALM, CYCLE)
		assert(first >= 60 and first <= 75, `the first surge at {first} s`)
		for t = 0, first - 1 do
			local _, mult = Pacing.phase(t, CALM, CYCLE, RATES)
			assert(mult <= 1.3, `x{mult} at {t} s, before the first surge`)
		end
	end,

	["a cycle with its packs is about as dense as the old steady rate"] = function()
		local avg = Pacing.average(CYCLE, RATES)
		local total = CYCLE.build + CYCLE.surge + CYCLE.ebb + CYCLE.lull
		-- two minutes in: the steady rate, and a pack of about a dozen
		local rate = c.SpawnBasePerSecond + c.SpawnPerMinute * 2
		local paced = avg * rate * total + 12
		local steady = rate * total
		assert(paced > steady * 0.9 and paced < steady * 1.12, `paced {paced} vs steady {steady} a cycle`)
		-- and the lull really is a breather, the surge a spike
		assert(RATES.lull <= 0.4 and RATES.surge >= 1.5)
		assert(CYCLE.lull >= 10, "a lull long enough for a chest or a shrine")
	end,

	["nextSurge finds the start of the coming surge"] = function()
		local total = CYCLE.build + CYCLE.surge + CYCLE.ebb + CYCLE.lull
		local first = CALM + CYCLE.build
		assert(Pacing.nextSurge(first, CALM, CYCLE) == first)
		assert(Pacing.nextSurge(first + 0.1, CALM, CYCLE) == first + total)
		local s = Pacing.nextSurge(300, CALM, CYCLE)
		assert(Pacing.phase(s, CALM, CYCLE, RATES) == "surge" and s >= 300 and s < 300 + total)
		assert(Pacing.phase(s - 0.1, CALM, CYCLE, RATES) == "build")
	end,

	["every pack is made of real enemies, and every stretch of a run has one"] = function()
		local ids = {}
		for _, pack in Roster.Packs do
			assert(not ids[pack.id], `two packs called {pack.id}`)
			ids[pack.id] = true
			assert(#pack.groups > 0)
			for _, group in pack.groups do
				local def = Roster.Enemies[group.type]
				assert(def and not def.boss, `{pack.id}: {group.type} is not a regular enemy`)
				assert(group.n >= 1)
			end
		end
		for t = 0, c.StageSeconds, 5 do
			assert(#Pacing.packsAt(Roster.Packs, t, false) > 0, `no pack at {t} s`)
		end
		assert(#Pacing.packsAt(Roster.Packs, 900, true) > 0, "no overtime pack")
		for _, pack in Pacing.packsAt(Roster.Packs, 900, true) do
			assert(pack.overtime, "a stage pack in overtime")
		end
		-- the opening's only pack is fodder: no charges or leaps in the first spike
		for _, pack in Pacing.packsAt(Roster.Packs, Pacing.nextSurge(0, CALM, CYCLE), false) do
			for _, group in pack.groups do
				assert(not Roster.Enemies[group.type].attack, `{pack.id} brings {group.type} into the first surge`)
			end
		end
	end,

	["each new pack is introduced on its own, then they vary"] = function()
		local seen, last = {}, nil
		local order = {}
		for t = 0, c.StageSeconds do
			if Pacing.phase(t, CALM, CYCLE, RATES) == "surge" and Pacing.phase(t - 1, CALM, CYCLE, RATES) ~= "surge" then
				local pack = Pacing.pick(Pacing.packsAt(Roster.Packs, t, false), seen, last, 0.5)
				assert(pack, `no pack for the surge at {t}`)
				assert(pack.id ~= last or #Pacing.packsAt(Roster.Packs, t, false) == 1, `{pack.id} twice in a row at {t}`)
				seen[pack.id] = true
				last = pack.id
				table.insert(order, pack.id)
			end
		end
		assert(order[1] == "mob", "the first spike is the goblin mob")
		assert(#order >= 9, `only {#order} surges in a stage`)
		local kinds = 0
		for _ in seen do
			kinds += 1
		end
		assert(kinds >= 6, `only {kinds} kinds of pack in a stage`)
	end,

	["packs grow a little with each cycle and each player, to a ceiling"] = function()
		local g, gmax, pp = c.PackGrowth, c.PackGrowthMax, c.PackPerExtraPlayer
		assert(Pacing.count(9, 1, 1, g, gmax, pp) == 9)
		assert(Pacing.count(9, 6, 1, g, gmax, pp) > 9)
		assert(Pacing.count(9, 100, 1, g, gmax, pp) == math.floor(9 * gmax + 0.5))
		assert(Pacing.count(9, 1, 2, g, gmax, pp) > Pacing.count(9, 1, 1, g, gmax, pp))
	end,

	["a pack's chargers and leapers take turns on a hero"] = function()
		local charge = Roster.Enemies.GoblinBruiser.attack
		local leap = Roster.Enemies.Slime.attack
		local gates = {}
		-- five Bruisers and six Slimes all ready at the same instant: they start one by one
		local starts = {}
		local waiting = {}
		for i = 1, 5 do
			table.insert(waiting, { kind = "charge", gap = charge.stagger, at = 10, id = `b{i}` })
		end
		for i = 1, 6 do
			table.insert(waiting, { kind = "leap", gap = leap.stagger, at = 10, id = `s{i}` })
		end
		for tick = 0, 200 do
			local now = 10 + tick * 0.05
			for _, w in waiting do
				if not w.started and now >= w.at then
					local ok, opens = Attacks.turn(gates, w.kind, now, w.gap, c.AttackGapAny)
					if ok then
						w.started = now
						table.insert(starts, { kind = w.kind, t = now })
					else
						w.at = opens
					end
				end
			end
		end
		assert(#starts == 11, `{#starts} of 11 started`)
		local lastOf = {}
		local lastAny = -math.huge
		for _, s in starts do
			assert(s.t - lastAny >= c.AttackGapAny - 1e-6, "two attacks started together")
			if lastOf[s.kind] then
				local gap = if s.kind == "charge" then charge.stagger else leap.stagger
				assert(s.t - lastOf[s.kind] >= gap - 1e-6, `two {s.kind}s too close`)
			end
			lastOf[s.kind] = s.t
			lastAny = s.t
		end
		-- and the queue clears within a few seconds: the pack still presses
		assert(starts[#starts].t - 10 < 5, `the last attack waited {starts[#starts].t - 10} s`)
	end,
}

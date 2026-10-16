--!strict
-- Specs for the small rule modules: Stats, Damage, Progress, Spawn, RunState.
-- Each test pins a boundary a designer would argue about, not the arithmetic.

local Damage = require("../src/shared/Core/Damage")
local GameConfig = require("../src/shared/Config/GameConfig")
local Progress = require("../src/shared/Core/Progress")
local Roster = require("../src/shared/Config/Roster")
local RunState = require("../src/shared/Core/RunState")
local Spawn = require("../src/shared/Core/Spawn")
local Stats = require("../src/shared/Core/Stats")

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

return {
	["every stat in a display group is defined"] = function()
		local n = 0
		for _, group in Roster.StatGroups do
			for _, key in group do
				assert(Roster.Stats[key] ~= nil, "undefined stat in a group: " .. key)
				n += 1
			end
		end
		assert(n == 30, "the stats panel shows 30 stats, got " .. n)
	end,

	["a hero passive gives nothing at level 1"] = function()
		-- "Gain 1% Armor per level" must not hand out a free 1% before any level-up.
		local hero = Roster.Heroes.Knight
		local s = Stats.compute(Roster.Stats, hero.base, hero.passive.stat, hero.passive.perLevel, 1, nil)
		assert(near(s.Armor, 0.15), "knight starts at his base 15% armor, got " .. s.Armor)
		local s11 = Stats.compute(Roster.Stats, hero.base, hero.passive.stat, hero.passive.perLevel, 11, nil)
		assert(near(s11.Armor, 0.25), "ten level-ups are ten percent")
	end,

	["lifesteal cannot be had: no item, no shrine, and the stat holds at zero"] = function()
		for _, id in Roster.ItemOrder do
			local stats = Roster.Items[id].stats
			assert(not (stats and stats.Lifesteal), id .. " still gives lifesteal")
		end
		for _, boost in Roster.ShrineBoosts do
			assert(boost.stat ~= "Lifesteal", "a shrine still boosts lifesteal")
		end
		local s = Stats.compute(Roster.Stats, nil, nil, nil, 1, { Lifesteal = 0.5 })
		assert(s.Lifesteal == 0, "lifesteal from a leftover source")
	end,

	["armor and evasion are capped so a tank can still be hurt"] = function()
		local s = Stats.compute(Roster.Stats, nil, nil, nil, 1, { Armor = 5, Evasion = 5 })
		assert(near(s.Armor, 0.7) and near(s.Evasion, 0.6), `{s.Armor} {s.Evasion}`)
		-- the Knight's passive alone reaches the cap, and stops there
		local hero = Roster.Heroes.Knight
		local k = Stats.compute(Roster.Stats, hero.base, hero.passive.stat, hero.passive.perLevel, 200, nil)
		assert(near(k.Armor, 0.7))
	end,

	["hero bases are deltas on the defaults"] = function()
		local s = Stats.compute(Roster.Stats, Roster.Heroes.Knight.base, nil, nil, 1, nil)
		assert(s.MaxHP == 150, "knight has 150 max HP, got " .. s.MaxHP)
		assert(near(s.MoveSpeed, 0.9))
	end,

	["stat formatting matches the panel"] = function()
		assert(Stats.format("pct", 0.18) == "18%")
		assert(Stats.format("mult", 1.08) == "1.08x")
		assert(Stats.format("int", 150) == "150")
	end,

	["a roll exactly on the crit chance is not a crit"] = function()
		local amount, crit = Damage.roll(10, 1, 0.25, 2, 0, 3, 0.25, 0)
		assert(crit == 0 and amount == 10)
		local a2, c2 = Damage.roll(10, 1, 0.25, 2, 0, 3, 0.2499, 0)
		assert(c2 == 1 and a2 == 20)
	end,

	["a megacrit needs a crit first"] = function()
		local _, crit = Damage.roll(10, 1, 0, 2, 1, 3, 0.5, 0)
		assert(crit == 0, "megacrit chance alone must not crit")
		local amount, c2 = Damage.roll(10, 1, 1, 2, 1, 3, 0.5, 0)
		assert(c2 == 2 and amount == 60)
	end,

	["armor never reduces a hit below 1"] = function()
		local amount, dodged = Damage.mitigate(2, 0.8, 0, 0.5)
		assert(amount == 1 and not dodged)
	end,

	["evasion avoids the whole hit"] = function()
		local amount, dodged = Damage.mitigate(40, 0, 0.3, 0.29)
		assert(amount == 0 and dodged)
	end,

	["damage spills from shield into health and reports the break"] = function()
		local hp, shield, broke = Damage.applyToPlayer(100, 25, 40)
		assert(hp == 85 and shield == 0 and broke)
		local hp2, shield2, broke2 = Damage.applyToPlayer(100, 25, 10)
		assert(hp2 == 100 and shield2 == 15 and not broke2)
	end,

	["a knockback-immune enemy does not move"] = function()
		assert(Damage.knockback(3, 1.5, 1) == 0)
	end,

	["the first level-up arrives after about ten gems"] = function()
		local need = Progress.xpToNext(1, GameConfig.XPBase, GameConfig.XPLinear, GameConfig.XPQuadratic)
		assert(need >= 8 and need <= 12, "first level needs " .. need)
	end,

	["level 16 costs roughly the 760 kills the reference shows"] = function()
		local total = 0
		for level = 1, 15 do
			total += Progress.xpToNext(level, GameConfig.XPBase, GameConfig.XPLinear, GameConfig.XPQuadratic)
		end
		assert(total > 600 and total < 900, "cumulative XP to 16 was " .. total)
	end,

	["one big gem can grant several levels and keeps the remainder"] = function()
		local level, xp, gained = Progress.addXP(1, 0, 35, 4, 5.5, 0)
		-- needs 10 then 15: 35 buys two levels with 10 left over
		assert(level == 3 and gained == 2 and xp == 10, `{level} {xp} {gained}`)
	end,

	["chest prices rise the way the reference does"] = function()
		local c = GameConfig
		assert(Progress.chestPrice(0, c.ChestPriceBase, c.ChestPriceLinear, c.ChestPriceQuadratic) == 30)
		assert(Progress.chestPrice(1, c.ChestPriceBase, c.ChestPriceLinear, c.ChestPriceQuadratic) == 73)
		assert(Progress.chestPrice(2, c.ChestPriceBase, c.ChestPriceLinear, c.ChestPriceQuadratic) == 122)
	end,

	["silver rewards a run in proportion, and never pays an unlock in one go"] = function()
		local c = GameConfig
		local function pay(stage, overtime, kills, minis, boss, escaped, gain)
			local run = {
				stageSeconds = stage,
				overtimeSeconds = overtime,
				kills = kills,
				minibossKills = minis,
				bossKills = boss,
				escaped = escaped,
			}
			return (Progress.silver(run, gain, c))
		end
		local early = pay(180, 0, 250, 0, 0, false, 1) -- an early defeat
		local mid = pay(480, 0, 1800, 2, 0, false, 1) -- a defeat before the boss
		local normal = pay(600, 30, 2500, 2, 1, true, 1) -- a normal completed run
		local strong = pay(600, 300, 6000, 2, 1, true, 1.16) -- a strong run with some overtime
		local long = pay(600, 1500, 30000, 2, 1, false, 1.4) -- a very long, high-kill survival
		local farmed = pay(600, 7200, 200000, 2, 1, true, 3) -- an absurd run with stacked Silver Gain
		assert(early >= 4 and early <= 10, `early defeat paid {early}`)
		assert(mid > early and mid <= 40, `mid defeat paid {mid}`)
		-- a normal win is a solid step towards Minty (150), not most of it
		assert(normal >= 45 and normal <= 60, `normal run paid {normal}`)
		assert(strong > normal and strong <= 100, `strong run paid {strong}`)
		assert(long > strong and long <= c.SilverRunCap, `long run paid {long}`)
		assert(farmed == c.SilverRunCap and farmed < Roster.Heroes.Frostling.unlockSilver, `farmed run paid {farmed}`)
	end,

	["overtime grows enemies faster and faster, and elites with it"] = function()
		local c = GameConfig
		assert(Spawn.overtimeHP(0, c.OvertimeHPGrowth) == 1 and Spawn.overtimeDamage(0, c.OvertimeDamageGrowth) == 1)
		assert(near(Spawn.overtimeHP(1, c.OvertimeHPGrowth), 1.5), "the first tier is as tough as it always was")
		-- each step of a minute adds more than the one before it
		local a, b, d =
			Spawn.overtimeHP(3, c.OvertimeHPGrowth), Spawn.overtimeHP(5, c.OvertimeHPGrowth), Spawn.overtimeHP(7, c.OvertimeHPGrowth)
		assert(d - b > b - a)
		-- the early minutes stay a fight; ten minutes in, a hit is many times harder
		assert(Spawn.overtimeDamage(4, c.OvertimeDamageGrowth) < 2.0)
		assert(Spawn.overtimeDamage(20, c.OvertimeDamageGrowth) > 8)
		local before = Spawn.eliteChance(c.EliteBaseChance, 1, 600)
		local deep = Spawn.eliteChance(c.EliteBaseChance, 1, 1200, 20, c.OvertimeElitePerTier, c.OvertimeEliteMax)
		assert(deep > before and deep <= c.OvertimeEliteMax)
		-- however long a run goes, the numbers stay finite
		assert(Spawn.overtimeHP(500, c.OvertimeHPGrowth, c.OvertimeHPMax) == c.OvertimeHPMax)
		assert(Spawn.overtimeDamage(500, c.OvertimeDamageGrowth, c.OvertimeDamageMax) == c.OvertimeDamageMax)
	end,

	["overtime pace: the horde quickens, and runners outgrow a walk and then a hop"] = function()
		local c = GameConfig
		local function at(minutes: number): (number, number, number)
			local tier = Spawn.overtimeTier(minutes * 60, c.OvertimeTierSeconds)
			local pace = Spawn.overtimeSpeed(tier, c.OvertimeSpeedPerTier, c.OvertimeSpeedMax)
			local share, boost = Spawn.runners(
				tier,
				c.OvertimeRunnerPerTier,
				c.OvertimeRunnerMax,
				c.OvertimeRunnerBoost,
				c.OvertimeRunnerBoostPerTier,
				c.OvertimeRunnerBoostMax
			)
			return pace, share, pace * boost
		end
		-- the fastest overtime enemy at its top random roll, in studs/s
		local fastest = 0
		for _, name in Roster.OvertimeTypes do
			fastest = math.max(fastest, Roster.Enemies[name].speed * c.EnemySpeedScale * 1.08)
		end
		local walk = c.PlayerWalkSpeed
		local hop = walk * c.HopMaxMultiplier
		local pace0, share0 = at(0.2)
		assert(pace0 == 1 and share0 == 0, "the first tier has no runners and no extra pace")
		-- the horde itself never outruns a walking hero by much: it can be kited
		local paceMax = at(30)
		assert(paceMax == c.OvertimeSpeedMax and fastest * paceMax < walk * 1.3)
		-- two minutes in, a runner beats a walk but not a hop
		local _, share2, run2 = at(2)
		assert(share2 > 0 and share2 < 0.1, `share at 2 min {share2}`)
		assert(fastest * run2 > walk and fastest * run2 < hop, `runner at 2 min {fastest * run2}`)
		-- twelve minutes in, the fastest runner outpaces a full bunny hop
		local _, share12, run12 = at(12)
		assert(fastest * run12 > hop, `runner at 12 min {fastest * run12}`)
		-- and never most of the horde
		assert(share12 <= c.OvertimeRunnerMax and c.OvertimeRunnerMax <= 0.35)
	end,

	["spawn rate grows through the stage and with the squad"] = function()
		local c = GameConfig
		local r0 = Spawn.rate(0, 1, 0, c.SpawnBasePerSecond, c.SpawnPerMinute, c.SpawnRatePerExtraPlayer)
		local r10 = Spawn.rate(600, 1, 0, c.SpawnBasePerSecond, c.SpawnPerMinute, c.SpawnRatePerExtraPlayer)
		local r10x3 = Spawn.rate(600, 3, 0, c.SpawnBasePerSecond, c.SpawnPerMinute, c.SpawnRatePerExtraPlayer)
		assert(near(r0, 1.2) and near(r10, 8.2), `{r0} {r10}`)
		assert(near(r10x3, 8.2 * 2.2, 1e-4))
	end,

	["the enemy cap respects the hard cap"] = function()
		local c = GameConfig
		assert(Spawn.cap(1, c.EnemyCapSolo, c.EnemyCapPerExtraPlayer, c.EnemyHardCap) == 250)
		assert(Spawn.cap(3, c.EnemyCapSolo, c.EnemyCapPerExtraPlayer, c.EnemyHardCap) == 350)
		assert(Spawn.cap(9, c.EnemyCapSolo, c.EnemyCapPerExtraPlayer, c.EnemyHardCap) == c.EnemyHardCap)
	end,

	["slimes arrive at 1:30 and not a second sooner"] = function()
		local function has(types: { string }, name: string): boolean
			return table.find(types, name) ~= nil
		end
		assert(not has(Spawn.typesAt(Roster.SpawnTimeline, 89), "Slime"))
		assert(has(Spawn.typesAt(Roster.SpawnTimeline, 90), "Slime"))
	end,

	["every spawnable type exists in the roster"] = function()
		local lists = { Roster.BossSpawnTypes, Roster.OvertimeTypes, Roster.ChallengeTypes, Roster.Minibosses, { Roster.StageBoss } }
		for _, row in Roster.SpawnTimeline do
			table.insert(lists, row.types)
		end
		for _, list in lists do
			for _, name in list do
				assert(Roster.Enemies[name] ~= nil, "unknown enemy " .. name)
				assert(table.find(Roster.EnemyOrder, name) ~= nil, name .. " has no network id")
			end
		end
	end,

	["overtime starts at tier 1 the moment the clock runs out"] = function()
		assert(Spawn.overtimeTier(0, 30) == 0)
		assert(Spawn.overtimeTier(0.05, 30) == 1)
		assert(Spawn.overtimeTier(30, 30) == 2)
	end,

	["a run cannot jump from the lobby straight to results"] = function()
		assert(not RunState.canMove(RunState.Lobby, RunState.Results))
		assert(RunState.canMove(RunState.Playing, RunState.Overtime))
		assert(RunState.canMove(RunState.Overtime, RunState.Wipe))
		assert(not RunState.canMove(RunState.Results, RunState.Playing))
	end,

	["the quest list grows the way the tracker does"] = function()
		assert(#RunState.quests(false, false, false) == 1)
		local q = RunState.quests(true, true, true)
		assert(#q == 3 and q[2].done and not q[3].done)
	end,

	["every item, weapon, hero and tome in an order list is defined"] = function()
		for _, id in Roster.ItemOrder do
			assert(Roster.Items[id] ~= nil, "undefined item " .. id)
		end
		assert(#Roster.ItemOrder == 25)
		for _, id in Roster.WeaponOrder do
			assert(Roster.Weapons[id] ~= nil, "undefined weapon " .. id)
		end
		for _, id in Roster.HeroOrder do
			local hero = Roster.Heroes[id]
			assert(hero ~= nil and Roster.Weapons[hero.weapon] ~= nil, "hero " .. id .. " has no valid starter")
		end
		for _, id in Roster.TomeOrder do
			local tome = Roster.Tomes[id]
			assert(tome ~= nil and Roster.Stats[tome.stat] ~= nil, "tome " .. id .. " boosts an unknown stat")
		end
	end,
}

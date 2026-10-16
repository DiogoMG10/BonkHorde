--!strict
-- Progress - the XP curve and the run economy: chest prices, coin values,
-- silver paid at the end. Pure; tunables are passed in.

local Progress = {}

--- XP needed to go from `level` to `level + 1`.
function Progress.xpToNext(level: number, base: number, linear: number, quadratic: number): number
	return math.floor(base + linear * level + quadratic * level * level + 0.5)
end

--- Add XP to a (level, xp) pair. Returns the new level, the XP carried into it,
--- and how many levels were gained.
function Progress.addXP(
	level: number,
	xp: number,
	gained: number,
	base: number,
	linear: number,
	quadratic: number
): (number, number, number)
	local levels = 0
	xp += math.max(gained, 0)
	local need = Progress.xpToNext(level, base, linear, quadratic)
	while xp >= need do
		xp -= need
		level += 1
		levels += 1
		need = Progress.xpToNext(level, base, linear, quadratic)
	end
	return level, xp, levels
end

--- Price of the next chest when `opened` chests have already been bought.
function Progress.chestPrice(opened: number, base: number, linear: number, quadratic: number): number
	return math.floor(base + linear * opened + quadratic * opened * opened + 0.5)
end

--- Value of one gold coin at `seconds` into the stage.
function Progress.coinValue(seconds: number, minutesPerStep: number): number
	return 1 + math.floor(seconds / 60 / minutesPerStep)
end

export type RunSummary = {
	stageSeconds: number, -- time survived on the stage clock, up to its end
	overtimeSeconds: number, -- time survived past it
	kills: number,
	minibossKills: number,
	bossKills: number,
	escaped: boolean, -- left through the portal after the boss
}

--- Silver paid when a run ends, and the parts that paid it. Kills and overtime
--- pay with diminishing returns towards a ceiling each, Silver Gain counts up
--- to its cap, and the run as a whole is capped: a long run earns more than a
--- short one, never without limit. `c` holds the GameConfig Silver* tunables.
function Progress.silver(run: RunSummary, silverGain: number, c: any): (number, { [string]: number })
	local parts = {
		stage = c.SilverPerStageMinute * math.clamp(run.stageSeconds, 0, c.StageSeconds) / 60,
		kills = c.SilverKillMax * (1 - math.exp(-math.max(run.kills, 0) / c.SilverKillScale)),
		minibosses = c.SilverPerMinibossKill * math.max(run.minibossKills, 0),
		boss = c.SilverPerBossKill * math.max(run.bossKills, 0),
		escape = if run.escaped then c.SilverForEscape else 0,
		overtime = c.SilverOvertimeMax * (1 - 0.5 ^ (math.max(run.overtimeSeconds, 0) / c.SilverOvertimeHalfLife)),
	}
	local raw = 0
	for _, v in parts do
		raw += v
	end
	local gain = math.clamp(silverGain, 0, c.SilverGainCap)
	return math.min(math.floor(raw * gain + 0.5), c.SilverRunCap), parts
end

return Progress

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

--- Silver paid when a run ends.
function Progress.silver(
	kills: number,
	minibossKills: number,
	bossKills: number,
	perHundredKills: number,
	perMiniboss: number,
	perBoss: number,
	silverGain: number,
	overtimeTier: number,
	overtimeStep: number
): number
	local raw = math.floor(kills / 100) * perHundredKills + minibossKills * perMiniboss + bossKills * perBoss
	local mult = math.max(silverGain, 0) * (1 + math.max(overtimeTier, 0) * overtimeStep)
	return math.floor(raw * mult + 0.5)
end

return Progress

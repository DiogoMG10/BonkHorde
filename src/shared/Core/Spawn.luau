--!strict
-- Spawn - how many enemies, of which kind, how tough. Pure.

local Spawn = {}

--- Enemies per second at `seconds` on the stage clock.
function Spawn.rate(
	seconds: number,
	players: number,
	difficulty: number,
	basePerSecond: number,
	perMinute: number,
	perExtraPlayer: number
): number
	local r = basePerSecond + perMinute * (math.max(seconds, 0) / 60)
	r *= 1 + perExtraPlayer * math.max(players - 1, 0)
	r *= 1 + math.max(difficulty, 0)
	return r
end

--- How many enemies may be alive at once.
function Spawn.cap(players: number, solo: number, perExtraPlayer: number, hardCap: number): number
	return math.min(solo + perExtraPlayer * math.max(players - 1, 0), hardCap)
end

--- The list of spawnable type names at `seconds`: the latest timeline row whose
--- `from` has passed.
function Spawn.typesAt(timeline: { { from: number, types: { string } } }, seconds: number): { string }
	local current = timeline[1].types
	for _, row in timeline do
		if seconds >= row.from then
			current = row.types
		end
	end
	return current
end

--- How much tougher overtime makes an enemy: 1 before it, then `growth` more
--- for every tier, compounding (tier 1 is x1.5 health, as it always was).
function Spawn.overtimeHP(overtimeTier: number, growth: number): number
	if overtimeTier <= 0 then
		return 1
	end
	return 1.5 * growth ^ (overtimeTier - 1)
end

--- How much harder overtime makes an enemy hit: `growth` per tier, compounding.
function Spawn.overtimeDamage(overtimeTier: number, growth: number): number
	return growth ^ math.max(overtimeTier, 0)
end

--- Health multiplier for an enemy spawned at `seconds`.
function Spawn.hpMult(seconds: number, difficulty: number, overtimeTier: number, perMinute: number, growth: number): number
	local m = 1 + perMinute * (math.max(seconds, 0) / 60)
	m *= 1 + math.max(difficulty, 0)
	m *= Spawn.overtimeHP(overtimeTier, growth)
	return m
end

--- Chance that a spawn is an elite. Overtime adds `perTier` for each tier and
--- lifts the ceiling to `overtimeMax`.
function Spawn.eliteChance(
	base: number,
	eliteSpawnIncrease: number,
	seconds: number,
	overtimeTier: number?,
	perTier: number?,
	overtimeMax: number?
): number
	local c = base * math.max(eliteSpawnIncrease, 0) * (1 + seconds / 300)
	local tier = math.max(overtimeTier or 0, 0)
	if tier > 0 and perTier and overtimeMax then
		return math.clamp(c + perTier * tier, 0, math.max(overtimeMax, 0.35))
	end
	return math.clamp(c, 0, 0.35)
end

--- Overtime tier for seconds past the end of the stage clock (0 before it).
function Spawn.overtimeTier(secondsPast: number, tierSeconds: number): number
	if secondsPast <= 0 then
		return 0
	end
	return 1 + math.floor(secondsPast / tierSeconds)
end

return Spawn

--!strict
-- Health - a worked example of what belongs in Core: pure functions over
-- numbers and tables, no Instances, no services, no yielding.
--
-- If a rule can be written without touching an Instance, it MUST be, because
-- that is what makes it testable when play-mode introspection is unreachable.
-- Delete this module once the game has real ones - but keep the shape.

local Health = {}

--- Clamp a damage application. Returns the new health, never below zero.
function Health.applyDamage(current: number, amount: number, max: number): number
	if amount <= 0 then
		return math.clamp(current, 0, max)
	end
	return math.clamp(current - amount, 0, max)
end

--- Fraction of maximum, for a health bar. Guards a zero max rather than
--- returning inf, because a UI reading inf is a crash and a UI reading 0 is a
--- visible bug.
function Health.fraction(current: number, max: number): number
	if max <= 0 then
		return 0
	end
	return math.clamp(current / max, 0, 1)
end

return Health

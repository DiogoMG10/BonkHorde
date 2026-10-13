--!strict
-- SimClock - gameplay time: the seconds the simulation has actually stepped.
--
-- Real time keeps running through a level-up pause; this does not, because it
-- only moves when the run director steps a tick. Everything that must wait
-- through a pause (a telegraphed strike, a freeze, a cooldown stamp) is timed
-- against this clock, so a timestamp taken before a pause is exactly as far
-- away after it. It is never reset, so a stamp left over from an earlier run
-- is always in the past. Pure.

local SimClock = {}

export type Clock = { t: number }

function SimClock.new(): Clock
	return { t = 0 }
end

--- Step the clock by one simulation tick. Returns the new time.
function SimClock.advance(clock: Clock, dt: number): number
	if dt > 0 then
		clock.t += dt
	end
	return clock.t
end

function SimClock.now(clock: Clock): number
	return clock.t
end

--- Has the moment `at` arrived?
function SimClock.due(clock: Clock, at: number): boolean
	return clock.t >= at
end

--- Gameplay seconds still to go before `at`, never negative.
function SimClock.remaining(clock: Clock, at: number): number
	return math.max(at - clock.t, 0)
end

return SimClock

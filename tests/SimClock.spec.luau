--!strict
-- Specs for the gameplay clock: what a pause must and must not do to a timer.

local SimClock = require("../src/shared/Core/SimClock")

local STEP = 1 / 20

local function near(a: number, b: number): boolean
	return math.abs(a - b) <= 1e-6
end

local function run(clock: SimClock.Clock, ticks: number)
	for _ = 1, ticks do
		SimClock.advance(clock, STEP)
	end
end

return {
	["the clock starts at zero and only moves when stepped"] = function()
		local clock = SimClock.new()
		assert(SimClock.now(clock) == 0)
		run(clock, 20)
		assert(near(SimClock.now(clock), 1), "twenty ticks are one second, got " .. SimClock.now(clock))
	end,

	["a strike warned before a pause keeps its whole warning"] = function()
		-- a boss telegraphs a 1.1 s strike, 0.5 s pass, then a level-up pauses the run
		local clock = SimClock.new()
		run(clock, 100)
		local at = SimClock.now(clock) + 1.1
		run(clock, 10)
		assert(near(SimClock.remaining(clock, at), 0.6))
		-- the pause: any amount of real time, no ticks
		assert(not SimClock.due(clock, at), "the strike must not land during the pause")
		assert(near(SimClock.remaining(clock, at), 0.6), "a pause must not eat the warning")
		run(clock, 11)
		assert(not SimClock.due(clock, at), "0.55 s after resuming is still too early")
		run(clock, 2)
		assert(SimClock.due(clock, at), "it lands once the rest of the warning has been played")
	end,

	["a stamp from an earlier run is already in the past"] = function()
		-- the clock is never reset, so nothing left over can sit in the future
		local clock = SimClock.new()
		run(clock, 200)
		local old = SimClock.now(clock) + 0.2
		run(clock, 40)
		assert(SimClock.due(clock, old) and SimClock.remaining(clock, old) == 0)
	end,

	["a zero or negative step never moves time"] = function()
		local clock = SimClock.new()
		run(clock, 4)
		local before = SimClock.now(clock)
		SimClock.advance(clock, 0)
		SimClock.advance(clock, -1)
		assert(SimClock.now(clock) == before)
	end,
}

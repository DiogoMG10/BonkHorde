--!strict
-- Specs for bunny-hop momentum: hops build speed to a cap, standing still or
-- dawdling bleeds it, a slide's speed carries but never stacks, and air
-- steering turns at a limited rate.

local GameConfig = require("../src/shared/Config/GameConfig")
local Hop = require("../src/shared/Core/Hop")

local CFG: Hop.Config = {
	gain = GameConfig.HopGain,
	cap = GameConfig.HopMaxMultiplier,
	window = GameConfig.HopWindow,
	minSpeed = GameConfig.HopMinSpeed,
	groundDecay = GameConfig.HopGroundDecay,
	stopDecay = GameConfig.HopStopDecay,
	overCapDecay = GameConfig.HopOverCapDecay,
	carryMax = GameConfig.SlideMaxMultiplier,
}
local BASE = GameConfig.PlayerWalkSpeed
local DT = 1 / 60

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

-- one clean hop: fly for `air` seconds, touch down for `down` seconds, jump
local function hop(s: Hop.State, down: number, air: number?)
	for _ = 1, math.floor((air or 0.5) / DT) do
		Hop.air(s, CFG, DT)
	end
	local t = 0
	while t < down do
		t += DT
		Hop.ground(s, CFG, DT, t, true)
	end
	return Hop.takeoff(s, CFG, down, BASE * s.mult, BASE, true)
end

return {
	["chained hops build speed gradually, up to the cap and no further"] = function()
		local s = Hop.new()
		Hop.takeoff(s, CFG, 5, BASE, BASE, true) -- a jump from a run starts nothing
		assert(near(s.mult, 1))
		local seen = { s.mult }
		for _ = 1, 12 do
			hop(s, 0.05)
			table.insert(seen, s.mult)
		end
		assert(seen[2] > 1 and seen[2] < 1.2, "one hop is not instant speed")
		for i = 2, #seen do
			assert(seen[i] >= seen[i - 1] - 1e-9, "never slower while hopping well")
		end
		assert(near(s.mult, CFG.cap), "hopping long enough reaches the cap")
		assert(s.mult <= CFG.cap + 1e-9)
	end,

	["holding jump (landing and leaving at once) chains"] = function()
		local s = Hop.new()
		for _ = 1, 8 do
			hop(s, 0)
		end
		assert(near(s.mult, CFG.cap))
	end,

	["a late jump breaks the chain and the speed bleeds away on the ground"] = function()
		local s = Hop.new()
		for _ = 1, 8 do
			hop(s, 0.05)
		end
		local was = s.mult
		assert(not hop(s, 1.0), "a jump after a second on the ground is not a hop")
		assert(s.mult < was and near(s.mult, 1), "a second on the ground drains it")
	end,

	["letting go of the stick on the ground stops it fast"] = function()
		local s = Hop.new()
		for _ = 1, 8 do
			hop(s, 0.05)
		end
		for _ = 1, math.floor(0.2 / DT) do
			Hop.ground(s, CFG, DT, 0.01, false)
		end
		assert(near(s.mult, 1), "a fifth of a second standing still")
	end,

	["momentum is kept through the air"] = function()
		local s = Hop.new()
		for _ = 1, 8 do
			hop(s, 0.05)
		end
		for _ = 1, 300 do
			Hop.air(s, CFG, DT)
		end
		assert(near(s.mult, CFG.cap), "five seconds of air time lose nothing at or below the cap")
	end,

	["jumping in place, or blocked by a wall, builds nothing"] = function()
		local s = Hop.new()
		for _ = 1, 10 do
			Hop.takeoff(s, CFG, 0.05, 0, BASE, true) -- pressing forward into a wall
		end
		assert(near(s.mult, 1))
		for _ = 1, 10 do
			Hop.takeoff(s, CFG, 0.05, BASE, BASE, false) -- no input
		end
		assert(near(s.mult, 1))
	end,

	["phantom speed is dropped when the hero is not really that fast"] = function()
		local s = Hop.new()
		for _ = 1, 8 do
			hop(s, 0.05)
		end
		Hop.takeoff(s, CFG, 0.05, BASE * 0.5, BASE, true) -- slowed by a crowd
		assert(s.mult <= 0.5 + 0.15 + 1e-9 or near(s.mult, 1))
	end,

	["a slide's speed carries into a hop, then drains back to the cap"] = function()
		local s = Hop.new()
		Hop.takeoff(s, CFG, 0, BASE * 2.2, BASE, true, 2.2)
		assert(s.mult > CFG.cap, "a fast downhill slide is not cut off by jumping")
		local t = 0
		while s.mult > CFG.cap + 1e-9 and t < 10 do
			Hop.air(s, CFG, DT)
			t += DT
		end
		assert(near(s.mult, CFG.cap) and t < 2, "the excess drains even in the air")
	end,

	["slides and hops never stack past the slide's own maximum"] = function()
		local s = Hop.new()
		for _ = 1, 20 do
			-- the most anyone could hand back and forth: max speed every time
			Hop.takeoff(s, CFG, 0, BASE * 10, BASE, true, 99)
		end
		assert(s.mult <= CFG.carryMax + 1e-9)
	end,

	["air steering turns at a limited rate, and lands exactly on target"] = function()
		local speed = BASE * CFG.cap
		local vx, vz = Hop.steer(speed, 0, -speed, 0, GameConfig.AirAccel, DT)
		assert(vx > 0, "one frame cannot reverse a full-speed run")
		local t = 0
		while not near(vx, -speed) and t < 5 do
			vx, vz = Hop.steer(vx, vz, -speed, 0, GameConfig.AirAccel, DT)
			t += DT
		end
		assert(near(vx, -speed) and near(vz, 0), "it gets there")
		assert(t > 0.3 and t < 1, `a full reversal takes a moment, not an age ({t} s)`)
		local x, z = Hop.steer(speed, 0, speed, 1, GameConfig.AirAccel, DT)
		assert(near(x, speed) and near(z, 1), "a small correction is immediate")
	end,
}

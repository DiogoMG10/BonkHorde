--!strict
-- Specs for T8: the crossing through Skyhold's portal (Core/Crossing).

local Crossing = require("../src/shared/Core/Crossing")
local Skyhold = require("../src/shared/Config/Skyhold")

local cfg = Skyhold.Crossing

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-3)
end

return {
	["the whole presentation stays short: about two to three seconds"] = function()
		local arrive = math.max(cfg.reveal, cfg.settle, cfg.release)
		assert(cfg.lead + arrive <= 3, `departure {cfg.lead} + arrival {arrive}`)
		assert(cfg.lead + arrive >= 2, "long enough to be felt")
		assert(cfg.flash < cfg.lead and cfg.release <= cfg.settle)
	end,

	["the portal idles, sleeps while the run is in use, and surges through a countdown"] = function()
		assert(near(Crossing.charge(nil, nil, false), Crossing.Idle))
		assert(Crossing.charge(nil, nil, true) < Crossing.Idle, "dimmer while a run is on")
		local start = Crossing.charge(5, 5, false)
		local mid = Crossing.charge(2.5, 5, false)
		local last = Crossing.charge(0.2, 5, false)
		assert(start > Crossing.Idle and mid > start and last > mid, `{start} {mid} {last}`)
		assert(near(Crossing.charge(0, 5, false), 1), "full as the party goes")
		-- a countdown for the next party while the run is still being left still charges
		assert(Crossing.charge(1, 3, true) > Crossing.Busy)
		-- a flare lights it whatever else is going on
		assert(near(Crossing.charge(nil, nil, true, 0.9), 0.9))
	end,

	["nothing happens to the party before the last moments of the countdown"] = function()
		local d = Crossing.departure(cfg.lead + 0.5, cfg)
		assert(not d.active and d.camera == 0 and d.light == 0 and d.dissolve == 0)
	end,

	["the departure holds the party, swings the camera, then closes in with light"] = function()
		local early = Crossing.departure(cfg.lead - 0.05, cfg)
		assert(early.active and early.light == 0, "held, no light yet")
		local late = Crossing.departure(0.1, cfg)
		assert(late.camera > 0.9 and late.light > 0.7 and late.dissolve > 0.6, `{late.camera} {late.light} {late.dissolve}`)
		local gone = Crossing.departure(0, cfg)
		assert(near(gone.light, 1) and near(gone.camera, 1) and near(gone.dissolve, 1), "all light as the portal opens")
		-- monotonic all the way
		local last = Crossing.departure(cfg.lead, cfg)
		for left = cfg.lead, 0, -0.05 do
			local d = Crossing.departure(left, cfg)
			assert(d.light >= last.light - 1e-6 and d.camera >= last.camera - 1e-6, `not monotonic at {left}`)
			last = d
		end
	end,

	["the arrival clears the light, settles the camera and gives the controls back"] = function()
		local first = Crossing.arrival(0, cfg)
		assert(near(first.light, 1) and near(first.camera, 1) and first.held and not first.done)
		assert(first.form == 0, "the heroes are not there yet")
		local after = Crossing.arrival(cfg.release + 0.01, cfg)
		assert(not after.held, "controls back")
		local settled = Crossing.arrival(cfg.settle, cfg)
		assert(near(settled.camera, 0) and near(settled.light, 0) and near(settled.form, 1))
		assert(Crossing.arrival(math.max(cfg.settle, cfg.reveal, cfg.release) + 0.1, cfg).done)
	end,

	["coming home clears the light"] = function()
		assert(near(Crossing.home(0, cfg), 1))
		assert(near(Crossing.home(cfg.homeReveal, cfg), 0))
		assert(Crossing.home(cfg.homeReveal / 2, cfg) < 0.5, "it clears quickly at first")
	end,
}

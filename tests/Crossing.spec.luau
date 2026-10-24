--!strict
-- Specs for T8: the crossing from Skyhold into the Wardwood and back through
-- portals on the ground (Core/Crossing).

local Crossing = require("../src/shared/Core/Crossing")
local Skyhold = require("../src/shared/Config/Skyhold")

local cfg = Skyhold.Crossing

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-3)
end

return {
	["a five-second countdown, then a short descent and a short rise"] = function()
		assert(Skyhold.CountdownSeconds == 5 and Skyhold.SoloCountdownSeconds == 5, "five seconds, solo or squad")
		assert(cfg.descent >= 1 and cfg.descent <= 2, `the descent takes {cfg.descent} s`)
		local rise = Crossing.emergeSeconds(cfg.arrive)
		assert(rise >= 1 and rise <= 2, `the rise takes {rise} s`)
		assert(Crossing.emergeSeconds(cfg.home) < rise, "coming home is quicker")
		local d = cfg.depart
		assert(d.lift + d.sink + d.collapse <= cfg.descent, "the portal has closed before the run takes the party")
		assert(d.darkTo < cfg.descent, "black before the world changes")
		assert(d.darkFrom > d.lift, "the first of the descent is seen")
	end,

	["the standing portal idles, sleeps while the run is in use, and surges through a countdown"] = function()
		assert(near(Crossing.charge(nil, nil, false), Crossing.Idle))
		assert(Crossing.charge(nil, nil, true) < Crossing.Idle, "dimmer while a run is on")
		local start = Crossing.charge(5, 5, false)
		local mid = Crossing.charge(2.5, 5, false)
		local last = Crossing.charge(0.2, 5, false)
		assert(start > Crossing.Idle and mid > start and last > mid, `{start} {mid} {last}`)
		assert(near(Crossing.charge(0, 5, false), 1), "full as the party goes")
		assert(Crossing.charge(1, 3, true) > Crossing.Busy)
		assert(near(Crossing.charge(nil, nil, true, 0.9), 0.9), "a flare lights it whatever else is going on")
	end,

	["the ground portal opens at the countdown's start and grows stronger to its end"] = function()
		local first = Crossing.gather(5, 5, cfg.portal.open)
		assert(near(first.open, 0), "closed as the countdown begins")
		local opened = Crossing.gather(5 - cfg.portal.open, 5, cfg.portal.open)
		assert(near(opened.open, 1), "fully open after its opening time")
		local last = Crossing.gather(5, 5, cfg.portal.open)
		for left = 5, 0, -0.1 do
			local g = Crossing.gather(left, 5, cfg.portal.open)
			assert(g.open >= last.open - 1e-6 and g.charge >= last.charge - 1e-6, `not growing at {left}`)
			last = g
		end
		assert(last.charge > 0.8, "strongest at the end")
	end,

	["the descent: a little rise, then under the surface, the camera framing, the black"] = function()
		local d = cfg.depart
		local start = Crossing.descent(0, d)
		assert(near(start.sink, 0) and near(start.camera, 0) and near(start.dark, 0) and not start.gone)
		local lifted = Crossing.descent(d.lift, d)
		assert(lifted.sink < 0, "a little above the ground first")
		assert(lifted.dark == 0, "the start of the descent is seen")
		local under = Crossing.descent(d.lift + d.sink, d)
		assert(under.gone and near(under.sink, 1), "out of sight")
		assert(under.open > 0.9, "the portal is still open as the last of them goes under")
		local framed = Crossing.descent(d.frame, d)
		assert(near(framed.camera, 1), "framed")
		local black = Crossing.descent(d.darkTo, d)
		assert(near(black.dark, 1), "black")
		local closed = Crossing.descent(d.lift + d.sink + d.collapse, d)
		assert(closed.done and near(closed.open, 0), "the portal has closed after them")
		-- after the rise, ever deeper; the black only ever thickens
		local last = lifted
		for t = d.lift, cfg.descent, 0.02 do
			local s = Crossing.descent(t, d)
			assert(s.sink >= last.sink - 1e-6 and s.dark >= last.dark - 1e-6, `not monotonic at {t}`)
			last = s
		end
	end,

	["the rise: black clears, heroes come up out of it, it closes, controls back"] = function()
		for name, r in { arrive = cfg.arrive, home = cfg.home } do
			local first = Crossing.emerge(0, r)
			assert(near(first.dark, 1) and near(first.sink, 1) and near(first.camera, 1), name)
			assert(first.held and not first.done, `{name}: held at first`)
			assert(near(first.open, 1), `{name}: the portal is open as the black lifts`)
			local cleared = Crossing.emerge(r.clear, r)
			assert(near(cleared.dark, 0), `{name}: the black has cleared`)
			assert(cleared.sink > 0.3, `{name}: the hero is still mostly under as it clears`)
			local risen = Crossing.emerge(r.riseFrom + r.rise, r)
			assert(near(risen.sink, 0), `{name}: exactly where they stand`)
			local peak = -1
			for t = r.riseFrom, r.riseFrom + r.rise, 0.01 do
				peak = math.max(peak, -Crossing.emerge(t, r).sink)
			end
			assert(peak > 0 and peak < 0.1, `{name}: a small hop out of it, {peak}`)
			assert(r.release >= r.riseFrom + r.rise, `{name}: controls back only once risen`)
			local free = Crossing.emerge(r.release + 0.01, r)
			assert(not free.held, `{name}: controls back`)
			local over = Crossing.emerge(Crossing.emergeSeconds(r), r)
			assert(over.done and near(over.open, 0) and near(over.camera, 0), `{name}: closed, the camera handed back`)
		end
	end,

	["the portal is big enough for its group"] = function()
		assert(near(Crossing.radius(0, cfg.portal), cfg.portal.radius), "one hero")
		assert(Crossing.radius(3.5, cfg.portal) >= 3.5 + 2.5, "a party a step apart, with room round each")
		assert(Skyhold.CircleRadius + 0.5 > 4, "the rune circle's portal holds a squad")
	end,

	["a cover waits for the hero, then the world, then the finishing touches"] = function()
		local gate = { min = 0.5, steady = 0.2, detail = 3, max = 8 }
		local w = Crossing.wait(10)
		local none = { placed = false, streamed = false, detail = false }
		local ok, why = Crossing.step(w, none, 11, gate)
		assert(not ok and why == "hero", why)
		ok, why = Crossing.step(w, { placed = true, streamed = false, detail = false }, 11.5, gate)
		assert(not ok and why == "world", why)
		ok, why = Crossing.step(w, { placed = true, streamed = true, detail = false }, 12, gate)
		assert(not ok and why == "detail", why)
		local all = { placed = true, streamed = true, detail = true }
		ok, why = Crossing.step(w, all, 12.1, gate)
		assert(not ok and why == "steady", "it holds a moment once everything is there")
		ok, why = Crossing.step(w, all, 12.31, gate)
		assert(ok and why == "ready", why)
	end,

	["a fast world still shows the cover for its minimum, and a moment steady"] = function()
		local gate = { min = 0.5, steady = 0.2, detail = 3, max = 8 }
		local w = Crossing.wait(0)
		local all = { placed = true, streamed = true, detail = true }
		assert(not Crossing.step(w, all, 0.05, gate))
		assert(not Crossing.step(w, all, 0.3, gate), "not before the minimum")
		assert(Crossing.step(w, all, 0.51, gate))
	end,

	["the finishing touches are given up on; the hero and the world only at the maximum"] = function()
		local gate = { min = 0.5, steady = 0.2, detail = 3, max = 8 }
		local w = Crossing.wait(0)
		local rough = { placed = true, streamed = true, detail = false }
		assert(not Crossing.step(w, rough, 2.9, gate))
		local ok = Crossing.step(w, rough, 3.0, gate)
		assert(not ok, "steady first")
		assert(Crossing.step(w, rough, 3.25, gate), "shown without the detail")
		local stuck = Crossing.wait(0)
		local nothing = { placed = false, streamed = false, detail = false }
		assert(not Crossing.step(stuck, nothing, 7.9, gate))
		local done, why = Crossing.step(stuck, nothing, 8, gate)
		assert(done and why == "timeout", "never past the maximum")
	end,

	["something going missing again starts the steady moment over"] = function()
		local gate = { min = 0, steady = 0.2, detail = 3, max = 8 }
		local w = Crossing.wait(0)
		local all = { placed = true, streamed = true, detail = true }
		assert(not Crossing.step(w, all, 1, gate))
		assert(not Crossing.step(w, { placed = true, streamed = false, detail = true }, 1.1, gate))
		assert(not Crossing.step(w, all, 1.25, gate), "the world went: steady again from here")
		assert(Crossing.step(w, all, 1.46, gate))
	end,

	["every cover has a firm maximum, the loading screen the longest"] = function()
		for name, gate in { arrive = cfg.arriveGate, home = cfg.homeGate, join = cfg.join } do
			assert(gate.min < gate.detail and gate.detail < gate.max, name)
			assert(gate.max <= 60, `{name}: nobody waits forever`)
		end
		assert(cfg.join.max > cfg.arriveGate.max and cfg.arriveGate.max >= cfg.homeGate.max)
		assert(cfg.revealMax > cfg.arriveGate.max, "the server waits for a slow client's own cover first")
	end,
}

--!strict
-- Specs for the XP strip's level-up rainbow (Core/XpStrip): it lasts exactly as
-- long as a level-up waits for the player's choice, and flows without a seam.

local XpStrip = require("../src/shared/Core/XpStrip")

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-3)
end

local function facts(over: { [string]: any }): XpStrip.Facts
	local f = { live = true, complete = false, pending = 0, offer = false }
	for k, v in over do
		(f :: any)[k] = v
	end
	return f
end

return {
	["a level-up waits while the server counts one or an offer is open"] = function()
		assert(XpStrip.waiting(facts({ pending = 1 })))
		assert(XpStrip.waiting(facts({ offer = true })), "the offer arrives before the count")
		assert(XpStrip.waiting(facts({ pending = 3, offer = true })))
		assert(not XpStrip.waiting(facts({})))
	end,

	["a finished build or a run that is over never shows it"] = function()
		assert(not XpStrip.waiting(facts({ pending = 2, complete = true })), "LVL MAX")
		assert(not XpStrip.waiting(facts({ pending = 1, offer = true, live = false })), "results, the island")
	end,

	["on at once, held through the gap between two offers, off after the hold"] = function()
		local l = XpStrip.latch()
		assert(XpStrip.step(l, true, 10))
		-- the first offer is answered; the next one arrives 0.05 s later
		assert(XpStrip.step(l, false, 11), "still on in the gap")
		assert(XpStrip.step(l, true, 11.05), "the next offer")
		-- the last one is answered
		assert(XpStrip.step(l, false, 12))
		assert(XpStrip.step(l, false, 12 + XpStrip.Hold * 0.5), "the hold")
		assert(not XpStrip.step(l, false, 12 + XpStrip.Hold + 0.01), "off once the hold has passed")
		assert(not XpStrip.step(l, false, 20))
	end,

	["Refresh and Banish keep it on: the level-up is still waiting"] = function()
		local l = XpStrip.latch()
		XpStrip.step(l, true, 0)
		for t = 0.1, 2, 0.1 do
			assert(XpStrip.step(l, true, t))
		end
	end,

	["the run ending turns it off at once"] = function()
		local l = XpStrip.latch()
		XpStrip.step(l, true, 0)
		assert(not XpStrip.step(l, false, 0.01, nil, true))
		assert(l.offAt == nil)
	end,

	["the rainbow's keypoints run from 0 to 1, strictly rising, within a ColorSequence's 20"] = function()
		for _, phase in { 0, 0.013, 0.25, 0.5, 0.9999, 1, 3.7 } do
			local keys = XpStrip.rainbow(phase)
			assert(#keys >= 2 and #keys <= 20, `{#keys} keys at phase {phase}`)
			assert(keys[1][1] == 0 and keys[#keys][1] == 1)
			for i = 2, #keys do
				assert(keys[i][1] > keys[i - 1][1], `keys out of order at phase {phase}`)
			end
			-- the two ends match: the flow has no seam
			local a, b = keys[1], keys[#keys]
			assert(near(a[2], b[2]) and near(a[3], b[3]) and near(a[4], b[4]), `seam at phase {phase}`)
		end
	end,

	["at rest each colour holds a band, in order"] = function()
		local keys = XpStrip.rainbow(0)
		-- the middle of the first band is the first colour
		local function colourAt(keyList, u: number): (number, number, number)
			for i = 2, #keyList do
				local k0, k1 = keyList[i - 1], keyList[i]
				if u <= k1[1] then
					local t = (u - k0[1]) / (k1[1] - k0[1])
					return k0[2] + (k1[2] - k0[2]) * t, k0[3] + (k1[3] - k0[3]) * t, k0[4] + (k1[4] - k0[4]) * t
				end
			end
			local l = keyList[#keyList]
			return l[2], l[3], l[4]
		end
		local n = #XpStrip.Colours
		for i, c in XpStrip.Colours do
			local r, g, b = colourAt(keys, (i - 1 + 0.25) / n)
			assert(near(r, c[1]) and near(g, c[2]) and near(b, c[3]), `band {i}`)
		end
		-- a sixth of a turn later, every band has moved one place right
		local moved = XpStrip.rainbow(1 / n)
		local r, g, b = colourAt(moved, (1 + 0.25) / n)
		local c = XpStrip.Colours[1]
		assert(near(r, c[1]) and near(g, c[2]) and near(b, c[3]), "the first colour moved right")
	end,
}

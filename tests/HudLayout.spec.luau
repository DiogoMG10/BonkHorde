--!strict
-- Specs for T2: the HUD's scale, safe area and columns on different screens (Core/HudLayout).

local HudLayout = require("../src/shared/Core/HudLayout")

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-3)
end

-- a desktop window under Roblox's 58 px top bar
local function desktop(width: number, height: number)
	return {
		width = width,
		height = height,
		core = { left = 0, top = 58, right = 0, bottom = 0 },
	}
end

-- a notched phone in landscape (points): cut-outs left and right, a home bar below
local function phone()
	return {
		width = 844,
		height = 390,
		core = { left = 47, top = 58, right = 47, bottom = 21 },
	}
end

local SCREENS = {
	desktop = desktop(1920, 1080),
	laptop = desktop(1366, 768),
	small = desktop(1024, 576),
	ultrawide = desktop(2560, 1080),
	phone = phone(),
}

-- the strip in screen pixels
local function stripOf(l)
	local s = l.scale
	return { x0 = l.xp.x * s, y0 = l.xp.y * s, x1 = (l.xp.x + l.xp.w) * s, y1 = (l.xp.y + l.xp.h) * s }
end

return {
	["a 1080p desktop draws the full HUD at design size, under the top bar"] = function()
		local l = HudLayout.compute(desktop(1920, 1080))
		assert(near(l.scale, 1), `scale {l.scale}`)
		assert(not l.compact)
		assert(near(l.safe.y, 58) and near(l.safe.x, 0), "the safe area starts under Roblox's top bar")
		assert(near(l.safe.h, 1022) and near(l.safe.w, 1920))
	end,

	["the XP strip spans the whole screen, edge to edge, just under Roblox's top bar"] = function()
		for name, screen in SCREENS do
			local l = HudLayout.compute(screen)
			local strip = stripOf(l)
			assert(near(strip.x0, 0) and near(strip.x1, screen.width), `{name}: strip from {strip.x0} to {strip.x1}`)
			assert(near((strip.x0 + strip.x1) / 2, screen.width / 2), `{name}: centred`)
			assert(strip.y0 >= screen.core.top - 1e-6, `{name}: under the top bar, at {strip.y0}`)
			assert(strip.y0 <= screen.core.top + 8 * l.scale, `{name}: right under it, at {strip.y0}`)
			assert(near(strip.y1 - strip.y0, l.sizes.xp * l.scale), `{name}: as thin as designed`)
		end
	end,

	["every column starts under the strip, the minimap's compass letters too"] = function()
		for name, screen in SCREENS do
			local l = HudLayout.compute(screen)
			local s = l.scale
			local strip = stripOf(l)
			for which, top in { left = l.topLeft, centre = l.topCentre } do
				local y = (l.safe.y + top) * s
				assert(y >= strip.y1 + HudLayout.Gap * s - 1e-6, `{name}: the {which} column at {y}, the strip ends {strip.y1}`)
			end
			local letters = (l.safe.y + l.topRight - HudLayout.RingLetter) * s
			assert(letters >= strip.y1 - 1e-6, `{name}: the minimap's letters at {letters}, the strip ends {strip.y1}`)
		end
	end,

	["laptops scale down like the other screens"] = function()
		local l = HudLayout.compute(desktop(1366, 768))
		assert(near(l.scale, 768 / 1080), `scale {l.scale}`)
		assert(not l.compact)
		l = HudLayout.compute(desktop(1280, 720))
		assert(near(l.scale, 720 / 1080), `scale {l.scale}`)
		assert(not l.compact)
	end,

	["a small window is drawn larger than a plain fit, never below legible"] = function()
		local l = HudLayout.compute(desktop(1024, 576))
		assert(l.scale >= HudLayout.Legible - 1e-6, `scale {l.scale}`)
		assert(l.scale > math.min(1024 / 1920, 576 / 1080))
	end,

	["a phone gets the compact HUD inside its cut-outs"] = function()
		local l = HudLayout.compute(phone())
		assert(l.compact, "compact on a phone")
		assert(l.scale >= 0.55, `scale {l.scale}: text would be too small`)
		assert(l.scale > math.min(844 / 1920, 390 / 1080), "larger than the plain fit")
		assert(near(l.safe.x * l.scale, 47) and near(l.safe.y * l.scale, 58), "inside the notch and under the bar")
		-- the compact arrangement fits the safe area at that scale
		assert(l.safe.w + 1e-6 >= HudLayout.Compact.width and l.safe.h + 1e-6 >= HudLayout.Compact.height)
	end,

	["a larger preferred text size draws larger, as far as the layout fits"] = function()
		local plain = HudLayout.compute(desktop(1366, 768))
		local screen = desktop(1366, 768)
		screen.boost = 1.2
		local big = HudLayout.compute(screen)
		assert(big.scale > plain.scale)
		assert(big.safe.w + 1e-6 >= HudLayout.Regular.width or big.compact)
	end,

	["the minimap steps left of a touch button it would cover"] = function()
		local screen = desktop(1280, 720)
		local l = HudLayout.compute(screen)
		local s = l.scale
		local x1 = 1280 - HudLayout.Margin * s
		local y0 = 58 + HudLayout.Margin * s
		local button = { x0 = x1 - 40, y0 = y0 + 20, x1 = 1280, y1 = y0 + 80 }
		screen.avoid = { button }
		local moved = HudLayout.compute(screen)
		assert(moved.shiftRight > 0)
		local right = 1280 - (HudLayout.Margin + moved.shiftRight) * s
		assert(right <= button.x0 + 1e-6, `minimap right edge {right}, button at {button.x0}`)
	end,

	["the boss bars and banners get the room between the columns"] = function()
		local wide = HudLayout.compute(desktop(1920, 1080))
		assert(wide.centreWidth == 900)
		local small = HudLayout.compute(phone())
		local room = small.safe.w - 2 * (HudLayout.Margin + small.sizes.column)
		assert(small.centreWidth <= math.max(room, 340), `centre {small.centreWidth} room {room}`)
	end,

	["items fill rows, and a +N chip takes the last tile when they overflow"] = function()
		local s = HudLayout.strip(5, 500, 40, 4, 2)
		assert(s.shown == 5 and s.overflow == 0 and s.rows == 1 and s.perRow == 11)
		s = HudLayout.strip(22, 500, 40, 4, 2)
		assert(s.shown == 22 and s.overflow == 0 and s.rows == 2)
		s = HudLayout.strip(25, 500, 40, 4, 2)
		assert(s.shown == 21 and s.overflow == 4 and s.rows == 2, `{s.shown} {s.overflow}`)
		s = HudLayout.strip(0, 500, 40, 4, 1)
		assert(s.shown == 0 and s.rows == 0)
	end,

	["item rows are centred"] = function()
		-- three tiles of 40 with gaps of 4 in a 200 wide strip: 128 wide, starting at 36
		local x, y = HudLayout.cell(1, 3, 11, 200, 40, 4)
		assert(near(x, 36) and y == 0)
		x = HudLayout.cell(3, 3, 11, 200, 40, 4)
		assert(near(x, 36 + 88))
		-- the second row of a 4-per-row strip holding 6
		local x5, y5 = HudLayout.cell(5, 6, 4, 200, 40, 4)
		assert(near(x5, (200 - 84) / 2) and y5 == 44)
	end,

	["objectives over the limit drop finished ones first, in order"] = function()
		local list = {
			{ text = "a", done = true },
			{ text = "b", done = false },
			{ text = "c", done = true },
			{ text = "d", done = false },
		}
		local out = HudLayout.quests(list, 2)
		assert(#out == 2 and out[1].text == "b" and out[2].text == "d")
		out = HudLayout.quests(list, 3)
		assert(#out == 3 and out[1].text == "a" and out[2].text == "b" and out[3].text == "d")
		out = HudLayout.quests(list, 5)
		assert(#out == 4)
		local open = { { text = "x" }, { text = "y" }, { text = "z" } }
		out = HudLayout.quests(open, 2)
		assert(#out == 2 and out[1].text == "x" and out[2].text == "y")
	end,
}

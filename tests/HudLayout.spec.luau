--!strict
-- Specs for T2: the HUD's scale, safe area and columns on different screens (Core/HudLayout).

local HudLayout = require("../src/shared/Core/HudLayout")

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-3)
end

-- a 1080p desktop: Roblox's 58 px top bar, its buttons on the left up to x 250
local function desktop(width: number, height: number)
	return {
		width = width,
		height = height,
		core = { left = 0, top = 58, right = 0, bottom = 0 },
		device = { left = 0, top = 0, right = 0, bottom = 0 },
		topbar = { x0 = 250, y0 = 0, x1 = width, y1 = 58 },
	}
end

-- a notched phone in landscape (points): cut-outs left and right, a home bar below
local function phone()
	return {
		width = 844,
		height = 390,
		core = { left = 47, top = 58, right = 47, bottom = 21 },
		device = { left = 47, top = 0, right = 47, bottom = 21 },
		topbar = { x0 = 180, y0 = 0, x1 = 844, y1 = 58 },
	}
end

return {
	["a 1080p desktop draws the full HUD at design size, under the top bar"] = function()
		local l = HudLayout.compute(desktop(1920, 1080))
		assert(near(l.scale, 1), `scale {l.scale}`)
		assert(not l.compact)
		assert(near(l.safe.y, 58) and near(l.safe.x, 0), "the safe area starts under Roblox's top bar")
		assert(near(l.safe.h, 1022) and near(l.safe.w, 1920))
	end,

	["the timer and minimap rise into the free top bar; the left column never does"] = function()
		local l = HudLayout.compute(desktop(1920, 1080))
		assert(near(l.liftRight, 58), `right lift {l.liftRight}`)
		assert(near(l.liftCentre, 58), `centre lift {l.liftCentre}`)
		-- the element under the plate still starts below the bar
		local under = l.safe.y - l.liftCentre + HudLayout.Margin + l.sizes.plateHeight + HudLayout.Gap
		assert(under * l.scale >= 58, `under the plate at {under * l.scale}`)
	end,

	["no free top bar reported: nothing rises"] = function()
		local screen = desktop(1920, 1080)
		screen.topbar = nil
		local l = HudLayout.compute(screen)
		assert(l.liftCentre == 0 and l.liftRight == 0)
	end,

	["Roblox's buttons spreading over the centre keep the timer below the bar"] = function()
		local screen = desktop(1920, 1080)
		screen.topbar = { x0 = 1100, y0 = 0, x1 = 1920, y1 = 58 } -- the unibar opened wide
		local l = HudLayout.compute(screen)
		assert(l.liftCentre == 0, `centre lift {l.liftCentre}`)
		assert(near(l.liftRight, 58), "the minimap is still clear")
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
		screen.topbar = nil
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

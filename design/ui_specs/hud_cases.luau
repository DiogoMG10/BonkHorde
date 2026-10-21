--!strict
-- The HUD preview screens, laid out by the game's own Core/HudLayout, printed
-- as JSON for Hud_build.py: `lune run design/ui_specs/hud_cases.luau`.

local serde = require("@lune/serde")
local HudLayout = require("../../src/shared/Core/HudLayout")

local function desktop(width: number, height: number)
	return {
		width = width,
		height = height,
		core = { left = 0, top = 58, right = 0, bottom = 0 },
		device = { left = 0, top = 0, right = 0, bottom = 0 },
		topbar = { x0 = 250, y0 = 0, x1 = width, y1 = 58 },
	}
end

-- a notched phone in landscape, in points; the touch buttons from the Overlay
-- model at its own plain-fit scale (min(844/1920, 390/1080))
local phoneScale = math.min(844 / 1920, 390 / 1080)
local function overlayButton(size: number, right: number, top: number)
	local x1 = 844 - right * phoneScale
	local y0 = top * phoneScale
	return { x0 = x1 - size * phoneScale, y0 = y0, x1 = x1, y1 = y0 + size * phoneScale }
end
local phone = {
	width = 844,
	height = 390,
	core = { left = 47, top = 58, right = 47, bottom = 21 },
	device = { left = 47, top = 0, right = 47, bottom = 21 },
	topbar = { x0 = 180, y0 = 0, x1 = 844, y1 = 58 },
	avoid = { overlayButton(116, 30, 380), overlayButton(116, 30, 512) },
}

local out = {}
for name, screen in
	{
		desktop = desktop(1920, 1080),
		laptop = desktop(1366, 768),
		phone = phone,
	}
do
	local layout = HudLayout.compute(screen)
	out[name] = { screen = screen, layout = layout }
end
out.margin = HudLayout.Margin
out.gap = HudLayout.Gap
print(serde.encode("json", out, false))

--!strict
-- Specs for T3: the pause menu's arrangement and the end screens' scale on
-- different screens (Core/PanelLayout).

local PanelLayout = require("../src/shared/Core/PanelLayout")

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-3)
end

local function desktop(width: number, height: number, boost: number?)
	return { width = width, height = height, core = { left = 0, top = 58, right = 0, bottom = 0 }, boost = boost }
end

-- an iPhone in landscape: the notch on the left, the home bar below, Roblox's bar on top
local phone = { width = 844, height = 390, core = { left = 47, top = 36, right = 47, bottom = 21 } }

return {
	["a 1080p desktop gets the three columns at full size"] = function()
		local L = PanelLayout.pause(desktop(1920, 1080))
		assert(L.mode == "wide" and near(L.scale, 1), `{L.mode} {L.scale}`)
		assert(near(L.safe.y, 58) and near(L.safe.h, 1022))
	end,

	["laptops keep the three columns at the plain fit"] = function()
		for _, size in { { 1366, 768 }, { 1280, 720 }, { 1440, 900 } } do
			local L = PanelLayout.pause(desktop(size[1], size[2]))
			assert(L.mode == "wide", `{size[1]}x{size[2]} went {L.mode}`)
			assert(near(L.scale, math.min(size[1] / 1920, size[2] / 1080)), `{size[1]}x{size[2]} scale {L.scale}`)
		end
	end,

	["a tablet keeps the columns at the legible floor"] = function()
		local L = PanelLayout.pause({ width = 1024, height = 768, core = { left = 0, top = 36, right = 0, bottom = 0 } })
		assert(L.mode == "wide" and near(L.scale, 0.6), `{L.mode} {L.scale}`)
	end,

	["a phone gets tabs, drawn larger than three columns could be"] = function()
		local L = PanelLayout.pause(phone)
		assert(L.mode == "tabs", L.mode)
		local wideFit = math.min((844 - 94) / PanelLayout.Wide.width, (390 - 57) / PanelLayout.Wide.height)
		assert(L.scale > wideFit + 0.1, `tabs {L.scale} vs columns {wideFit}`)
		assert(L.scale >= 0.55, `still close to legible: {L.scale}`)
		-- the safe frame keeps clear of the notch and Roblox's bar
		assert(near(L.safe.x, 47 / L.scale) and near(L.safe.y, 36 / L.scale))
	end,

	["a larger text size draws bigger and keeps the columns"] = function()
		local L = PanelLayout.pause(desktop(1920, 1080, 1.25))
		assert(L.mode == "wide" and L.scale > 1.1, `{L.mode} {L.scale}`)
		assert(L.scale * PanelLayout.Wide.height <= 1022 + 1e-6, "still fits under the top bar")
	end,

	["a single panel fits the safe area and is never cut"] = function()
		local L = PanelLayout.fit(phone, 1240, 620)
		assert(L.scale * 1240 <= 844 - 94 + 1e-6 and L.scale * 620 <= 390 - 57 + 1e-6)
		local big = PanelLayout.fit(desktop(3840, 2160), 1240, 620)
		assert(near(big.scale, 2), "a 4K screen draws it at twice the size")
	end,
}

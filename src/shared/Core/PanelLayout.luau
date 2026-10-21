--!strict
-- PanelLayout - how big the pause menu and the end screens are drawn on one
-- screen, and which arrangement the pause menu takes.
--
-- Pure, like Core/HudLayout: the controllers measure the screen (the viewport
-- and Roblox's CoreUISafeInsets) and this turns it into a UIScale and the safe
-- frame. Screen pixels in, design pixels (a 1920x1080 screen) out.
--
--   pause   the three columns (build, actions, stats) side by side wherever
--           they are still legible; otherwise one panel with tabs (BUILD /
--           STATS / SETTINGS) drawn larger, so a phone never gets three
--           shrunken columns
--   fit     one panel (the death screen, the results) as large as it fits

local PanelLayout = {}

PanelLayout.DesignWidth = 1920
PanelLayout.DesignHeight = 1080
PanelLayout.Legible = 0.6 -- the smallest scale chosen on purpose: a 20 px label stays 12 px
PanelLayout.Margin = 24 -- design pixels between the safe area's edge and a panel

-- the safe area each pause arrangement needs at scale 1, margins included
PanelLayout.Wide = { width = 1660, height = 880 }
PanelLayout.Tabs = { width = 1180, height = 560 }
-- ...and each end screen (one panel each)
PanelLayout.Death = { width = 900, height = 660 }
PanelLayout.Results = { width = 1300, height = 640 }

export type Insets = { left: number, top: number, right: number, bottom: number }
export type Screen = {
	width: number, -- the viewport, pixels
	height: number,
	core: Insets, -- CoreUISafeInsets: the top bar plus the device's cut-outs
	boost: number?, -- 1 normally; more for a larger preferred text size or a TV
}
export type Layout = {
	scale: number,
	mode: string, -- "wide" | "tabs" (pause only; "fit" for a single panel)
	safe: { x: number, y: number, w: number, h: number }, -- the safe frame, design pixels
}

local function safeSize(screen: Screen): (number, number)
	local core = screen.core
	return math.max(1, screen.width - core.left - core.right), math.max(1, screen.height - core.top - core.bottom)
end

-- the plain 1920x1080 fit, raised to stay legible, times the text boost
local function wanted(screen: Screen): number
	local plain = math.min(screen.width / PanelLayout.DesignWidth, screen.height / PanelLayout.DesignHeight)
	return math.max(plain, PanelLayout.Legible) * (screen.boost or 1)
end

local function result(screen: Screen, scale: number, mode: string): Layout
	scale = math.max(scale, 0.2)
	local core = screen.core
	local w, h = safeSize(screen)
	return { scale = scale, mode = mode, safe = { x = core.left / scale, y = core.top / scale, w = w / scale, h = h / scale } }
end

--- The pause menu: three columns while they stay legible, tabs otherwise.
function PanelLayout.pause(screen: Screen): Layout
	local w, h = safeSize(screen)
	local want = wanted(screen)
	local wide = math.min(want, w / PanelLayout.Wide.width, h / PanelLayout.Wide.height)
	if wide >= PanelLayout.Legible * (screen.boost or 1) - 1e-6 then
		return result(screen, wide, "wide")
	end
	local tabs = math.min(want, w / PanelLayout.Tabs.width, h / PanelLayout.Tabs.height)
	if tabs > wide + 1e-6 then
		return result(screen, tabs, "tabs")
	end
	return result(screen, wide, "wide")
end

--- One panel `width` x `height` design pixels (margins included), as large as
--- it fits up to the screen's plain size.
function PanelLayout.fit(screen: Screen, width: number, height: number): Layout
	local w, h = safeSize(screen)
	return result(screen, math.min(wanted(screen), w / width, h / height), "fit")
end

return PanelLayout

--!strict
-- HudLayout - how big the in-run HUD is drawn on one screen and where its
-- columns sit, from what Roblox reports about that screen.
--
-- Pure: HudController measures the screen (viewport, Roblox's safe insets, the
-- touch buttons) and this turns it into the Hud's scale and the handful of
-- sizes that change on small screens.
-- Screen pixels in, design pixels (a 1920x1080 screen) out.
--
--   scale    the Hud's UIScale: the plain 1920x1080 fit, raised to stay legible
--            on small screens, capped where the layout would no longer fit
--   compact  the small-screen arrangement: narrower column, smaller minimap,
--            one row of items, two objectives
--   safe     the Safe frame: Roblox's CoreUISafeInsets (top bar and device
--            cut-outs), in design pixels
--   xp       the XP strip: the whole width of the screen, edge to edge, flush
--            with the top of the viewport. Roblox's top-bar buttons are drawn
--            over it (CoreGui is always on top), so it never covers them, and
--            it is thin enough to sit in the margin above them
--   tops     where the left, centre and right columns start, under the strip
--            and never in the top bar where Roblox has its buttons
--   shift    how far the right column steps left to clear the touch buttons

local HudLayout = {}

HudLayout.DesignWidth = 1920
HudLayout.DesignHeight = 1080
HudLayout.Legible = 0.6 -- the smallest scale chosen on purpose: a 20 px label stays 12 px
HudLayout.Margin = 16 -- design pixels between the safe area's edge and a column
HudLayout.Gap = 8 -- design pixels between stacked elements
HudLayout.RingLetter = 12 -- design pixels the minimap's compass letters stand out of its ring

export type Sizes = {
	width: number, -- the safe area this arrangement needs, design pixels
	height: number,
	column: number, -- the left column
	vitals: number, -- the vitals card's height
	minimap: number,
	plate: number, -- the timer plate
	plateHeight: number,
	clock: number, -- the elapsed clock beside the plate
	xp: number, -- the XP strip's height
	slot: number, -- a weapon or tome tile
	item: number, -- an item tile
	itemRows: number,
	quests: number, -- objectives shown at once
}

HudLayout.Regular = {
	width = 1500,
	height = 660,
	column = 440,
	vitals = 96,
	minimap = 220,
	plate = 248,
	plateHeight = 76,
	clock = 110,
	xp = 12,
	slot = 56,
	item = 40,
	itemRows = 2,
	quests = 4,
} :: Sizes

HudLayout.Compact = {
	width = 1240,
	height = 500,
	column = 400,
	vitals = 96,
	minimap = 160,
	plate = 220,
	plateHeight = 76,
	clock = 96,
	xp = 14,
	slot = 50,
	item = 36,
	itemRows = 1,
	quests = 2,
} :: Sizes

export type Insets = { left: number, top: number, right: number, bottom: number }
export type Rect = { x0: number, y0: number, x1: number, y1: number }

export type Screen = {
	width: number, -- the viewport, pixels
	height: number,
	core: Insets, -- CoreUISafeInsets: the top bar plus the device's cut-outs
	avoid: { Rect }?, -- buttons the right column must keep clear of (touch controls)
	boost: number?, -- 1 normally; more for a larger preferred text size or a TV
}

export type Layout = {
	scale: number,
	compact: boolean,
	sizes: Sizes,
	safe: { x: number, y: number, w: number, h: number },
	-- the XP strip, design pixels from the screen's top-left corner
	xp: { x: number, y: number, w: number, h: number },
	-- where each column starts, design pixels below the Safe frame's top
	topLeft: number,
	topCentre: number,
	topRight: number,
	shiftRight: number,
	centreWidth: number, -- room between the left column and its mirror, for boss bars and banners
}

local function overlaps(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end

--- The scale one arrangement would be drawn at.
local function scaleFor(screen: Screen, sizes: Sizes, safeW: number, safeH: number): (number, number)
	local base = math.min(screen.width / HudLayout.DesignWidth, screen.height / HudLayout.DesignHeight)
	local target = math.max(base, HudLayout.Legible) * (screen.boost or 1)
	local fit = math.min(safeW / sizes.width, safeH / sizes.height)
	return math.max(math.min(target, fit), 0.2), target
end

function HudLayout.compute(screen: Screen): Layout
	local core = screen.core
	local safeW = math.max(1, screen.width - core.left - core.right)
	local safeH = math.max(1, screen.height - core.top - core.bottom)

	-- the full arrangement wherever it fits at a legible size; the compact one
	-- only when it lets the HUD be drawn larger
	local sizes = HudLayout.Regular
	local scale, target = scaleFor(screen, sizes, safeW, safeH)
	local compact = false
	if scale < target - 1e-6 then
		local compactScale = scaleFor(screen, HudLayout.Compact, safeW, safeH)
		if compactScale > scale + 1e-6 then
			sizes, scale, compact = HudLayout.Compact, compactScale, true
		end
	end

	local m, gap = HudLayout.Margin * scale, HudLayout.Gap * scale -- pixels from here on

	-- the XP strip runs the whole width of the screen, from its left edge to its
	-- right, along the very top of the viewport; every column starts below both
	-- it and Roblox's top bar
	local strip: Rect = { x0 = 0, y0 = 0, x1 = screen.width, y1 = sizes.xp * scale }
	local clear = math.max(strip.y1, core.top)
	local under = clear + gap -- the first row under the strip and the top bar

	-- right: the minimap's compass letters clear the strip and the top bar, and
	-- it steps left of any touch button it would cover
	local shiftRight = 0
	local rightTop = clear + (HudLayout.RingLetter + 2) * scale
	for _ = 1, 3 do
		local x1 = screen.width - core.right - m - shiftRight * scale
		local rect = { x0 = x1 - sizes.minimap * scale, y0 = rightTop, x1 = x1, y1 = rightTop + sizes.minimap * scale }
		local moved = false
		for _, button in screen.avoid or {} do
			if overlaps(rect, button) then
				shiftRight += (rect.x1 - button.x0) / scale + HudLayout.Gap
				moved = true
			end
		end
		if not moved then
			break
		end
	end

	local canvasW = safeW / scale
	local centreWidth = math.clamp(canvasW - 2 * (HudLayout.Margin + sizes.column + 24), 340, 900)

	return {
		scale = scale,
		compact = compact,
		sizes = sizes,
		safe = { x = core.left / scale, y = core.top / scale, w = canvasW, h = safeH / scale },
		xp = { x = 0, y = 0, w = screen.width / scale, h = sizes.xp },
		topLeft = (under - core.top) / scale,
		topCentre = (under - core.top) / scale,
		topRight = (rightTop - core.top) / scale,
		shiftRight = shiftRight,
		centreWidth = centreWidth,
	}
end

-- ---------------------------------------------------------------- the item strip

export type Strip = { shown: number, overflow: number, rows: number, perRow: number }

--- How many item tiles fit a strip `width` wide, in at most `rows` rows. When
--- they do not all fit, the last tile becomes a "+N" chip.
function HudLayout.strip(count: number, width: number, tile: number, gap: number, rows: number): Strip
	local perRow = math.max(1, math.floor((width + gap) / (tile + gap)))
	local room = perRow * rows
	if count <= room then
		return { shown = count, overflow = 0, rows = math.ceil(count / perRow), perRow = perRow }
	end
	return { shown = room - 1, overflow = count - (room - 1), rows = rows, perRow = perRow }
end

--- The top-left corner of tile `i` (1-based) of `total` tiles, rows centred in
--- a strip `width` wide; the first row is the top one.
function HudLayout.cell(i: number, total: number, perRow: number, width: number, tile: number, gap: number): (number, number)
	local row = (i - 1) // perRow
	local col = (i - 1) % perRow
	local inRow = math.min(perRow, total - row * perRow)
	local rowWidth = inRow * tile + (inRow - 1) * gap
	return (width - rowWidth) / 2 + col * (tile + gap), row * (tile + gap)
end

-- ---------------------------------------------------------------- objectives

--- The objectives to show when only `limit` fit: keep their order, and let
--- finished ones give way to unfinished ones first.
function HudLayout.quests(list: { any }, limit: number): { any }
	if #list <= limit then
		return table.clone(list)
	end
	local drop = #list - limit
	local keep = {}
	for i = #list, 1, -1 do
		if drop > 0 and list[i].done then
			drop -= 1
		else
			keep[i] = true
		end
	end
	local out = {}
	for i, quest in list do
		if keep[i] and #out < limit then
			table.insert(out, quest)
		end
	end
	return out
end

return HudLayout

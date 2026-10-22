--!strict
-- HudLayout - how big the in-run HUD is drawn on one screen and where its
-- columns sit, from what Roblox reports about that screen.
--
-- Pure: HudController measures the screen (viewport, Roblox's safe insets, the
-- part of the top bar Roblox leaves free, the touch buttons) and this turns it
-- into the Hud's scale and the handful of sizes that change on small screens.
-- Screen pixels in, design pixels (a 1920x1080 screen) out.
--
--   scale    the Hud's UIScale: the plain 1920x1080 fit, raised to stay legible
--            on small screens, capped where the layout would no longer fit
--   compact  the small-screen arrangement: narrower column, smaller minimap,
--            one row of items, two objectives
--   safe     the Safe frame: Roblox's CoreUISafeInsets (top bar and device
--            cut-outs), in design pixels
--   xp       the XP strip along the top of the screen: in the part of Roblox's
--            top bar it leaves free when the timer can sit under it there,
--            otherwise just under the bar across the whole safe width
--   tops     where the left, centre and right columns start, under the strip
--            and never in the top bar where Roblox has its buttons
--   shift    how far the right column steps left to clear the touch buttons

local HudLayout = {}

HudLayout.DesignWidth = 1920
HudLayout.DesignHeight = 1080
HudLayout.Legible = 0.6 -- the smallest scale chosen on purpose: a 20 px label stays 12 px
HudLayout.Margin = 16 -- design pixels between the safe area's edge and a column
HudLayout.Gap = 8 -- design pixels between stacked elements
HudLayout.StripTop = 6 -- design pixels above the XP strip
HudLayout.StripPad = 10 -- design pixels between the strip and Roblox's buttons beside it
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
	xp = 14,
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
	xp = 16,
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
	device: Insets?, -- DeviceSafeInsets alone (the top bar left out)
	topbar: Rect?, -- GuiService.TopbarInset: the part of the top bar Roblox leaves free
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
	xpInBar: boolean, -- the strip sits in the free part of Roblox's top bar
	-- where each column starts, design pixels below the Safe frame's top
	-- (negative: risen into the top bar)
	topLeft: number,
	topCentre: number,
	topRight: number,
	shiftRight: number,
	centreWidth: number, -- room between the left column and its mirror, for boss bars and banners
}

local function none(): Insets
	return { left = 0, top = 0, right = 0, bottom = 0 }
end

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
	local device = screen.device or none()
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
	local roomTop = math.max(0, core.top - device.top) -- the top bar's height
	local free = screen.topbar

	--- Whether a span of screen pixels lies wholly in the free part of the top bar.
	local function inFreeBar(x0: number, x1: number): boolean
		return free ~= nil and free.y1 - free.y0 > 0 and x0 >= free.x0 + 4 and x1 <= free.x1 - 4
	end

	-- the XP strip runs along the top of the screen in the free part of the top
	-- bar, with the timer plate under it, when that part spans the plate and its
	-- clock; otherwise (Roblox's buttons spread over the centre, no free bar
	-- reported, or the rise switched off) it runs just under the bar, the whole
	-- safe width, and every column starts below it
	local centreX = core.left + safeW / 2
	local plateLeft = centreX - sizes.plate / 2 * scale
	local plateRight = centreX + (sizes.plate / 2 + HudLayout.Gap + sizes.clock) * scale
	local stripTop, stripH = HudLayout.StripTop * scale, sizes.xp * scale
	local inBar = free ~= nil and roomTop >= stripTop + stripH + gap and inFreeBar(plateLeft, plateRight)
	local strip: Rect
	if inBar and free then
		local pad = HudLayout.StripPad * scale
		local y0 = math.max(free.y0, device.top) + stripTop
		strip = {
			x0 = math.max(free.x0 + pad, device.left + m),
			y0 = y0,
			x1 = math.min(free.x1 - pad, screen.width - device.right - m),
			y1 = y0 + stripH,
		}
	else
		local y0 = core.top + stripTop
		strip = { x0 = core.left + m, y0 = y0, x1 = screen.width - core.right - m, y1 = y0 + stripH }
	end
	local under = strip.y1 + gap -- the first row under the strip

	-- left: always under the bar, and under the strip when it runs there
	local leftTop = if inBar then core.top + m else under
	-- centre: the plate sits under the strip; whatever is stacked under the
	-- plate starts below the bar
	local centreTop = math.max(under, core.top - (sizes.plateHeight * scale + gap))

	-- right: the minimap rises beside the plate when its part of the bar is free
	-- too (its compass letters clear of the strip), and steps left of any touch
	-- button it would cover
	local shiftRight = 0
	local function rightRect(top: number): Rect
		local x1 = screen.width - core.right - m - shiftRight * scale
		return { x0 = x1 - sizes.minimap * scale, y0 = top, x1 = x1, y1 = top + sizes.minimap * scale }
	end
	local underRight = strip.y1 + (HudLayout.RingLetter + 2) * scale
	local rightTop = underRight
	for _ = 1, 3 do
		local rect = rightRect(underRight)
		rightTop = if not inBar or inFreeBar(rect.x0, rect.x1) then underRight else math.max(underRight, core.top + m)
		rect = rightRect(rightTop)
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
		xp = {
			x = strip.x0 / scale,
			y = strip.y0 / scale,
			w = math.max(0, strip.x1 - strip.x0) / scale,
			h = sizes.xp,
		},
		xpInBar = inBar,
		topLeft = (leftTop - core.top) / scale,
		topCentre = (centreTop - core.top) / scale,
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

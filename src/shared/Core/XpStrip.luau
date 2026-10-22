--!strict
-- XpStrip - the XP strip's level-up look: whether it wears the rainbow, and
-- the rainbow's colours at one moment of its flow.
--
-- Pure: HudController gathers what the server has said about this player's
-- level-ups (the waiting count in PlayerState, and an upgrade offer open on this
-- client) and draws what this returns. The rainbow has no timer of its own: it
-- lasts exactly as long as a level-up waits for this player's choice, with a
-- short hold so the moment between one answered offer and the next never
-- blinks it off.

local XpStrip = {}

XpStrip.Hold = 0.3 -- seconds the rainbow stays after the last waiting level-up clears

-- the bands, left to right: the game's rarity and pickup colours
XpStrip.Colours = {
	{ 0.208, 0.816, 0.29 }, -- green  #35D04A
	{ 0.067, 0.706, 0.957 }, -- sky    #11B4F4
	{ 0.69, 0.302, 1.0 }, -- violet #B04DFF
	{ 1.0, 0.302, 0.604 }, -- pink   #FF4D9A
	{ 1.0, 0.624, 0.102 }, -- orange #FF9F1A
	{ 1.0, 0.824, 0.227 }, -- gold   #FFD23A
}

export type Facts = {
	live: boolean, -- in a run that is on (playing or overtime, paused or not)
	complete: boolean, -- a finished build: LVL MAX, no level-up offers it anything
	pending: number, -- the server's count of this player's level-ups waiting for a choice
	offer: boolean, -- an upgrade offer is open on this client (shown, or waiting under a panel)
}

--- Does a level-up wait for this player's choice?
function XpStrip.waiting(f: Facts): boolean
	return f.live and not f.complete and (f.pending > 0 or f.offer)
end

export type Latch = { on: boolean, offAt: number? }

function XpStrip.latch(): Latch
	return { on = false, offAt = nil }
end

--- Feed the latch what is true at `now`; returns whether the rainbow shows.
--- On at once; off only after `hold` seconds without a waiting level-up, so one
--- that comes back in that time keeps it on without a blink. `hard` (the run
--- is over, or the build finished) turns it off at once.
function XpStrip.step(l: Latch, waiting: boolean, now: number, hold: number?, hard: boolean?): boolean
	if waiting then
		l.on, l.offAt = true, nil
	elseif l.on then
		local offAt = l.offAt
		if hard or (offAt ~= nil and now >= offAt) then
			l.on, l.offAt = false, nil
		elseif offAt == nil then
			l.offAt = now + (hold or XpStrip.Hold)
		end
	end
	return l.on
end

export type Key = { number } -- { time, r, g, b }

--- The rainbow across the strip at flow `phase` (0..1 is one full turn of the
--- colours, moving right as it grows): a band per colour that blends into the
--- next over `blend` of its width. Keypoints { time, r, g, b } from 0 to 1,
--- strictly increasing, at most 20 (a ColorSequence's limit) for up to nine
--- colours; the two ends always match, so the flow never shows a seam.
function XpStrip.rainbow(phase: number, colours: { { number } }?, blend: number?): { Key }
	local list = colours or XpStrip.Colours
	local n = #list
	local soft = math.clamp(blend or 0.35, 0.01, 1)
	phase %= 1

	local function at(u: number): (number, number, number)
		local x = ((u - phase) * n) % n
		local k = math.floor(x)
		if k >= n then
			k = n - 1
		end
		local f = x - k
		local a = list[k + 1]
		if f <= 1 - soft then
			return a[1], a[2], a[3]
		end
		local b = list[(k + 1) % n + 1]
		local t = (f - (1 - soft)) / soft
		return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
	end

	-- every band's flat end and blend end, carried along by the phase
	local times = { 0, 1 }
	for k = 0, n - 1 do
		for _, edge in { (k + 1 - soft) / n, (k + 1) / n } do
			local u = (edge + phase) % 1
			if u > 1e-4 and u < 1 - 1e-4 then
				table.insert(times, u)
			end
		end
	end
	table.sort(times)
	local out: { Key } = {}
	local last = -1
	for _, u in times do
		if u - last > 1e-4 then
			local r, g, b = at(u)
			table.insert(out, { u, r, g, b })
			last = u
		end
	end
	return out
end

return XpStrip

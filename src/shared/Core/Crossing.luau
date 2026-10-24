--!strict
-- Crossing - the party's way from Skyhold into the Wardwood and back (T8): how
-- far each part of it has gone at a given moment. Pure: the client measures the
-- time (the countdown left on the island, the seconds since the countdown ended
-- or since a cover began to lift) and draws what this returns.
--
--   charge      Skyhold's standing portal, 0..1: idle, surging through any
--               party's countdown, full as a party goes; sleepy while the run
--               is in use
--   gather      the countdown: a portal opening on the ground under the party,
--               its magic growing to the end
--   descent     after the countdown: the party held still, a little rise, then
--               sinking into the portal as the camera frames them and the
--               screen goes black; the portal closes after them
--   emerge      the arrival (and the way home): the black clearing, the heroes
--               rising out of a portal on the ground, the portal closing, the
--               camera handed back, the controls back
--   gate        how long a cover (the black, or the loading screen on joining)
--               stays up: until the world behind it is ready to be seen, with a
--               short minimum and a firm maximum
--
-- `sink` is how far under the portal's surface a hero is, as a share of their
-- whole height (1: out of sight; below 0: a little above the ground).
-- Timings come from Config/Skyhold.Crossing.

local Crossing = {}

export type Gate = {
	min: number, -- the cover stays up at least this long
	steady: number, -- and this long after everything it waits for is there
	detail: number, -- the finishing touches are waited for this long at most
	max: number, -- and nothing is waited for past this
}

export type Depart = {
	lift: number,
	sink: number,
	frame: number,
	darkFrom: number,
	darkTo: number,
	collapse: number,
}

export type Rise = {
	clear: number,
	riseFrom: number,
	rise: number,
	cameraFrom: number,
	camera: number,
	close: number,
	release: number,
}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

--- Ease in and out (smoothstep).
function Crossing.smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

--- Ease out: fast at first, settling.
function Crossing.out(x: number): number
	x = clamp01(x)
	return 1 - (1 - x) * (1 - x) * (1 - x)
end

--- Rising out of a portal, 0..1: eased in and out, so the black has cleared
--- while most of the rise is still to come, with a small hop past 1 near the
--- end before settling on it.
function Crossing.rise(x: number): number
	x = clamp01(x)
	return Crossing.smooth(x) + 0.1 * math.sin(math.pi * clamp01((x - 0.55) / 0.45))
end

Crossing.Idle = 0.22 -- the standing portal's charge with nothing happening
Crossing.Busy = 0.08 -- while a run is in use and nobody waits on the portal
Crossing.Lift = 0.05 -- how high the little rise before the sink goes (share of the height)

--- The standing portal's charge for this client: `left` and `total` are the
--- seconds left on the countdown nearest its end and its whole length (nil:
--- nobody counts down); `busy` whether the server's run is in use; `flare` 0..1
--- for a moment of extra light (a party just went, or came back).
function Crossing.charge(left: number?, total: number?, busy: boolean, flare: number?): number
	local base = if busy then Crossing.Busy else Crossing.Idle
	if left and total and total > 0 then
		-- rising all through the countdown, most of it in the last moments
		local k = 1 - clamp01(left / total)
		base = 0.35 + 0.65 * (k * k)
	end
	return math.max(base, clamp01(flare or 0))
end

export type Gather = {
	open: number, -- 0..1 of the ground portal's full size
	charge: number, -- 0..1 of its magic
}

--- The ground portal through a countdown with `left` of `total` seconds to go:
--- it opens over `openSeconds` from the start, and its magic grows to the end.
function Crossing.gather(left: number, total: number, openSeconds: number): Gather
	local since = math.max(0, total - left)
	local k = 1 - clamp01(left / math.max(total, 1e-3))
	return {
		open = Crossing.out(since / math.max(openSeconds, 1e-3)),
		charge = 0.25 + 0.6 * k * k,
	}
end

export type Descent = {
	sink: number, -- share of the hero's height under the surface
	camera: number, -- 0..1 of the way to the departure's framing
	dark: number, -- 0..1 of the screen gone black
	open: number, -- 0..1 of the portal's size: it closes after them
	charge: number, -- 0..1 of its magic
	gone: boolean, -- every hero is out of sight
	done: boolean, -- the portal has closed
}

--- Where the departure is `t` seconds after the countdown ended.
function Crossing.descent(t: number, d: Depart): Descent
	local sink
	if t < d.lift then
		sink = -Crossing.Lift * math.sin(t / d.lift * math.pi / 2)
	else
		local u = clamp01((t - d.lift) / d.sink)
		-- slow out of the rise, swallowed quickly at the end
		sink = -Crossing.Lift + (1 + Crossing.Lift) * u ^ 1.7
	end
	local under = d.lift + d.sink
	local closing = clamp01((t - under) / d.collapse)
	return {
		sink = sink,
		camera = Crossing.smooth(t / d.frame),
		dark = Crossing.smooth((t - d.darkFrom) / (d.darkTo - d.darkFrom)),
		open = 1 - Crossing.smooth(closing),
		charge = math.clamp(0.85 + 0.15 * clamp01(t / under) - 0.85 * closing, 0, 1),
		gone = t >= under,
		done = t >= under + d.collapse,
	}
end

export type Emerge = {
	sink: number, -- share of the hero's height under the surface
	camera: number, -- 1 at first (the arrival's framing), 0 once the hero's own camera has it
	dark: number, -- 1 at first, 0 once the black has cleared
	open: number, -- 0..1 of the portal's size
	charge: number,
	held: boolean, -- controls still held
	done: boolean,
}

--- Where an arrival is `t` seconds after its cover began to lift.
function Crossing.emerge(t: number, r: Rise): Emerge
	local up = (t - r.riseFrom) / r.rise
	local risen = r.riseFrom + r.rise
	local closing = clamp01((t - risen) / r.close)
	return {
		sink = 1 - Crossing.rise(up),
		camera = 1 - Crossing.smooth((t - r.cameraFrom) / r.camera),
		dark = 1 - Crossing.out(t / r.clear),
		open = 1 - Crossing.smooth(closing),
		charge = 0.9 * (1 - closing),
		held = t < r.release,
		done = t >= math.max(risen + r.close, r.cameraFrom + r.camera, r.release),
	}
end

--- How long an arrival takes from the cover lifting to its end.
function Crossing.emergeSeconds(r: Rise): number
	return math.max(r.riseFrom + r.rise + r.close, r.cameraFrom + r.camera, r.release)
end

--- The ground portal's radius round a group whose members stand `spread` studs
--- at most from its centre.
function Crossing.radius(spread: number, portal: { radius: number, margin: number }): number
	return math.max(portal.radius, spread + portal.margin)
end

-- ------------------------------------------------------------------ the gate

export type Facts = {
	placed: boolean, -- the hero stands where the server set them down
	streamed: boolean, -- the world round them has arrived (ground underfoot and around)
	detail: boolean, -- the finishing touches (the art near them, the portal, the others)
}

export type Wait = {
	since: number,
	steadySince: number?,
	last: number, -- the previous step
	spent: { [string]: number }, -- seconds spent awaiting each thing
}

--- A cover going up at `now`.
function Crossing.wait(now: number): Wait
	return { since = now, steadySince = nil, last = now, spent = {} }
end

--- Where a cover's time went, for the log: "hero 1.20  world 0.31 ...".
function Crossing.summary(w: Wait): string
	local parts = {}
	for _, key in { "hero", "world", "detail", "steady", "party" } do
		local t = w.spent[key]
		if t and t > 0.005 then
			table.insert(parts, string.format("%s %.2f", key, t))
		end
	end
	return table.concat(parts, "  ")
end

--- May the cover come down at `now`, given what the client sees? The hero and
--- the world round them are waited for up to `max`; the finishing touches up to
--- `detail`; once all is there it holds `steady` more (the first frames of the
--- new place) and never comes down before `min`. The second value is what is
--- still awaited: "hero", "world", "detail", "steady", or "ready" / "timeout".
function Crossing.step(w: Wait, facts: Facts, now: number, gate: Gate): (boolean, string)
	local waited = now - w.since
	local dt = math.max(0, now - w.last)
	w.last = now
	local function awaiting(key: string)
		w.spent[key] = (w.spent[key] or 0) + dt
	end
	if waited >= gate.max then
		return true, "timeout"
	end
	local missing = if not facts.placed
		then "hero"
		elseif not facts.streamed then "world"
		elseif not facts.detail and waited < gate.detail then "detail"
		else nil
	if missing then
		awaiting(missing)
		w.steadySince = nil
		return false, missing
	end
	w.steadySince = w.steadySince or now
	if now - (w.steadySince :: number) < gate.steady or waited < gate.min then
		awaiting("steady")
		return false, "steady"
	end
	return true, "ready"
end

--- Time spent after the cover was ready, waiting for the rest of the party
--- (the server's word that everyone is ready), for the log.
function Crossing.waitedFor(w: Wait, key: string, dt: number)
	w.spent[key] = (w.spent[key] or 0) + math.max(0, dt)
end

return Crossing

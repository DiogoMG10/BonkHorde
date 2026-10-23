--!strict
-- Crossing - the party's way through Skyhold's portal into the Wardwood and
-- back (T8): how far each part of it has gone at a given moment. Pure: the
-- client measures the time (the countdown left on the island, the seconds since
-- the light began to clear) and draws what this returns.
--
--   charge      the portal's surge, 0..1: idle, rising through a countdown,
--               full as the party goes; sleepy while the run is in use
--   departure   the last moments of the countdown: the party held still, the
--               camera swinging up to the portal, the light closing in
--   arrival     the light clearing round the hero in the Wardwood, the camera
--               dropping in behind them, the heroes taking shape, controls back
--
-- Timings come from Config/Skyhold.Crossing.

local Crossing = {}

export type Config = {
	lead: number,
	flash: number,
	hold: number,
	reveal: number,
	settle: number,
	release: number,
	materialise: number,
	homeHold: number,
	homeReveal: number,
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

Crossing.Idle = 0.22 -- the portal's charge with nothing happening
Crossing.Busy = 0.08 -- while a run is in use and nobody waits on the portal

--- The portal's charge for this client: `left` and `total` are the seconds left
--- on the countdown nearest its end and its whole length (nil: nobody counts
--- down); `busy` whether the server's run is in use; `flare` 0..1 for a moment
--- of extra light (a party just went through, or came back).
function Crossing.charge(left: number?, total: number?, busy: boolean, flare: number?): number
	local base = if busy then Crossing.Busy else Crossing.Idle
	if left and total and total > 0 then
		-- rising all through the countdown, most of it in the last moments
		local k = 1 - clamp01(left / total)
		base = 0.35 + 0.65 * (k * k)
	end
	return math.max(base, clamp01(flare or 0))
end

export type Departure = {
	active: boolean, -- inside the last `lead` seconds: the party is held still
	k: number, -- 0..1 through those seconds
	camera: number, -- 0..1 of the swing up to the portal
	light: number, -- 0..1 of the light closing in
	dissolve: number, -- 0..1 of the hero turning to light
}

--- Where the departure is with `left` seconds on the countdown.
function Crossing.departure(left: number, cfg: Config): Departure
	if left > cfg.lead then
		return { active = false, k = 0, camera = 0, light = 0, dissolve = 0 }
	end
	local k = clamp01(1 - left / cfg.lead)
	return {
		active = true,
		k = k,
		camera = Crossing.smooth(k),
		light = Crossing.smooth((cfg.flash - left) / cfg.flash),
		dissolve = Crossing.smooth((0.6 - left) / 0.6),
	}
end

export type Arrival = {
	light: number, -- 1 at first, 0 once the light has cleared
	camera: number, -- 1 at first (high and back), 0 settled behind the hero
	form: number, -- 0..1 the heroes taking shape
	held: boolean, -- controls still held
	done: boolean,
}

--- Where the arrival is `t` seconds after the light began to clear.
function Crossing.arrival(t: number, cfg: Config): Arrival
	local light = 1 - Crossing.out(t / cfg.reveal)
	local camera = 1 - Crossing.smooth(t / cfg.settle)
	return {
		light = light,
		camera = camera,
		form = Crossing.smooth((t - 0.05) / cfg.materialise),
		held = t < cfg.release,
		done = t >= math.max(cfg.reveal, cfg.settle, cfg.release, cfg.materialise + 0.05),
	}
end

--- Coming home from a run: the light clears over `homeReveal` seconds.
function Crossing.home(t: number, cfg: Config): number
	return 1 - Crossing.out(t / cfg.homeReveal)
end

return Crossing

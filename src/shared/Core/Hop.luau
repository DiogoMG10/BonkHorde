--!strict
-- Hop - the rules of bunny-hop momentum. Pure.
--
-- Momentum is one multiplier on the hero's own base speed. A jump made soon
-- after landing (a hop), while really moving, raises it a step towards a cap;
-- staying on the ground past that window, or letting go of the stick, bleeds
-- it back to 1. A slide's speed can be carried into a hop above the cap, but
-- anything above the cap drains away even in the air, so nothing stacks.
--
-- Air steering is a velocity chased at a limited acceleration: the hero can
-- turn and brake in the air, but cannot reverse a full-speed run in an instant.

local Hop = {}

export type Config = {
	gain: number, -- added to the multiplier per chained hop
	cap: number, -- chained hops never take it above this
	window: number, -- seconds on the ground after a landing that a jump still chains
	minSpeed: number, -- a hop only counts when moving at this share of the current target speed
	groundDecay: number, -- multiplier lost per second on the ground once the window has passed
	stopDecay: number, -- ...and per second with no movement input at all
	overCapDecay: number, -- multiplier lost per second above the cap, in the air too
	carryMax: number, -- the most a slide can hand to a hop
}

export type State = {
	mult: number,
	hops: number, -- hops chained so far (for feedback)
}

function Hop.new(): State
	return { mult = 1, hops = 0 }
end

--- Back to standing: respawn, a freeze, a downed hero.
function Hop.reset(s: State)
	s.mult = 1
	s.hops = 0
end

--- A jump from the ground. `groundFor` is how long the hero stood before it,
--- `speed` the horizontal speed at take-off, `base` the hero's base speed,
--- `moving` whether there is movement input. `carry` is a slide's multiplier
--- when the jump leaves a slide. Returns whether it counted as a chained hop.
function Hop.takeoff(s: State, cfg: Config, groundFor: number, speed: number, base: number, moving: boolean, carry: number?): boolean
	if carry then
		s.mult = math.clamp(math.max(s.mult, carry), 1, cfg.carryMax)
	end
	-- never keep momentum the hero is not actually carrying (a wall, a crowd)
	s.mult = math.max(1, math.min(s.mult, speed / math.max(base, 1e-3) + 0.15))
	local chained = moving and groundFor <= cfg.window and speed >= cfg.minSpeed * base * math.min(s.mult, cfg.cap)
	if not chained then
		s.hops = 0
		return false
	end
	-- the jump from a run starts a chain (it is not chained itself); each quick
	-- re-jump after it adds a step
	s.hops += 1
	if s.mult < cfg.cap then
		s.mult = math.min(s.mult + cfg.gain, cfg.cap)
	end
	return true
end

--- One frame on the ground.
function Hop.ground(s: State, cfg: Config, dt: number, groundFor: number, moving: boolean)
	if not moving then
		s.mult = math.max(1, s.mult - cfg.stopDecay * dt)
		s.hops = 0
	elseif groundFor > cfg.window then
		s.mult = math.max(1, s.mult - cfg.groundDecay * dt)
		s.hops = 0
	end
	if s.mult > cfg.cap then
		s.mult = math.max(cfg.cap, s.mult - cfg.overCapDecay * dt)
	end
end

--- One frame in the air: only what is above the cap drains.
function Hop.air(s: State, cfg: Config, dt: number)
	if s.mult > cfg.cap then
		s.mult = math.max(cfg.cap, s.mult - cfg.overCapDecay * dt)
	end
end

--- Chase the target horizontal velocity (tx, tz) from (vx, vz) with at most
--- `accel` studs per second per second. Returns the new velocity.
function Hop.steer(vx: number, vz: number, tx: number, tz: number, accel: number, dt: number): (number, number)
	local ex, ez = tx - vx, tz - vz
	local gap = math.sqrt(ex * ex + ez * ez)
	local step = accel * dt
	if gap <= step or gap < 1e-6 then
		return tx, tz
	end
	return vx + ex / gap * step, vz + ez / gap * step
end

return Hop

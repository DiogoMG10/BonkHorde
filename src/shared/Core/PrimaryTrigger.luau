--!strict
-- PrimaryTrigger - the rules of the manually fired primary weapon: what a
-- client may say about its attack button, how one click is remembered, and
-- when the weapon fires. Pure.
--
-- The client sends a STATE (button held or not, and the yaw it is aiming at),
-- never a request per attack. The server keeps one Input per hero and asks
-- `step` once a tick, so the cadence is the server's and clicking faster buys
-- nothing. At most ONE click is ever remembered.

local PrimaryTrigger = {}

export type Input = {
	held: boolean,
	yaw: number, -- the aim the next attack uses, radians, camera convention
	heardAt: number, -- real time of the last accepted message, for the stale check
	clickAt: number?, -- gameplay time of the one remembered click
	tokens: number, -- rate limit
	tokenAt: number,
}

local MAX_YAW = 1e4 -- far beyond any real camera; rejects garbage

function PrimaryTrigger.new(): Input
	return { held = false, yaw = 0, heardAt = 0, clickAt = nil, tokens = 0, tokenAt = -math.huge }
end

--- Check what a client sent. Returns ok, held, yaw wrapped to (-pi, pi].
function PrimaryTrigger.parse(held: unknown, yaw: unknown): (boolean, boolean, number)
	if type(held) ~= "boolean" or type(yaw) ~= "number" then
		return false, false, 0
	end
	local y = (yaw :: any) :: number
	if y ~= y or math.abs(y) > MAX_YAW then
		return false, false, 0 -- NaN, infinite or absurd
	end
	y = (y + math.pi) % (2 * math.pi) - math.pi
	return true, (held :: any) :: boolean, y
end

--- Rate limit: a bucket of `burst` messages refilled at `rate` a second.
--- A release is always let through, because it can only ever stop attacks.
function PrimaryTrigger.allow(input: Input, realNow: number, rate: number, burst: number, isRelease: boolean): boolean
	if isRelease then
		return true
	end
	local elapsed = math.max(realNow - input.tokenAt, 0)
	input.tokens = math.min(input.tokens + elapsed * rate, burst)
	input.tokenAt = realNow
	if input.tokens < 1 then
		return false
	end
	input.tokens -= 1
	return true
end

--- The button is down. A press that follows a release is a click: it is
--- remembered, replacing any click already remembered (never added to it).
function PrimaryTrigger.press(input: Input, yaw: number, simNow: number, realNow: number)
	if not input.held then
		input.clickAt = simNow
	end
	input.held = true
	input.yaw = yaw
	input.heardAt = realNow
end

--- The button is up. The remembered click survives, so a click shorter than a
--- simulation tick still attacks once, in the direction it was pressed at.
function PrimaryTrigger.release(input: Input, realNow: number)
	input.held = false
	input.heardAt = realNow
end

--- Forget everything: pause, downed, death, the run ending.
function PrimaryTrigger.clear(input: Input)
	input.held = false
	input.clickAt = nil
end

--- A client that has gone quiet (hung, crashed, lost its release) stops
--- holding. A live client repeats its state well inside `timeout`.
function PrimaryTrigger.expire(input: Input, realNow: number, timeout: number)
	if input.held and realNow - input.heardAt > timeout then
		input.held = false
	end
end

--- Does the player want an attack now? Drops a click older than `buffer`.
function PrimaryTrigger.wants(input: Input, simNow: number, buffer: number): boolean
	local at = input.clickAt
	if at and simNow - at > buffer then
		input.clickAt = nil
		at = nil
	end
	return input.held or at ~= nil
end

--- One tick of the primary weapon's cooldown. `cd` is the time left, `elapsed`
--- the tick already scaled by attack speed. Returns the new time left, whether
--- the weapon fires this tick, and whether that attack is the player's own.
---
--- A ready weapon waits at zero: waiting never banks a second attack. Firing on
--- the very tick it came ready keeps the fraction of the tick left over, which
--- is what gives a held button exactly the cadence of an automatic weapon.
---
--- `auto` (the Auto-Trigger item) is asked only when the weapon is ready and
--- the player is not attacking: the button always comes first, and both share
--- this one cooldown, so the item can never add an attack.
function PrimaryTrigger.step(
	input: Input,
	cd: number,
	elapsed: number,
	cooldown: number,
	simNow: number,
	buffer: number,
	auto: (() -> boolean)?
): (number, boolean, boolean)
	local left = cd - elapsed
	if left > 0 then
		-- still cooling down; an old click may time out while it does
		PrimaryTrigger.wants(input, simNow, buffer)
		return left, false, false
	end
	local byHand = PrimaryTrigger.wants(input, simNow, buffer)
	if not byHand and not (auto and auto()) then
		return 0, false, false
	end
	input.clickAt = nil -- the click, if there was one, is spent on this attack
	local carry = if cd > 0 then left else 0
	return math.max(cooldown + carry, 0), true, byHand
end

--- Unit direction (x, z) for a camera yaw.
function PrimaryTrigger.direction(yaw: number): (number, number)
	return -math.sin(yaw), -math.cos(yaw)
end

--- Where on a target a weapon swung at height `y` can touch it: the closest
--- point of the target's body (its ground to its top) to that height, or nil
--- when the whole body is more than `reach` above or below.
function PrimaryTrigger.touchHeight(y: number, reach: number, targetGround: number, targetHeight: number): number?
	local low, high = targetGround, targetGround + math.max(targetHeight, 0)
	local at = math.clamp(y, low, high)
	if math.abs(at - y) > reach then
		return nil
	end
	return at
end

return PrimaryTrigger

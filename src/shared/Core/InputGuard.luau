--!strict
-- InputGuard - which presses may answer a level-up panel that just opened (T1).
-- Pure.
--
-- A panel locks for a moment when it opens. While it is locked nothing on it
-- answers, and afterwards only a press that began after the lock counts: a
-- button held since before the panel opened, or pressed during the lock, stays
-- "stale" until it is let go, and its release (which is what fires a click)
-- never picks anything. Nothing is queued for later.
--
-- A key is whatever names one physical input: the mouse button, a gamepad or
-- keyboard key, or the InputObject of one touch (each finger has its own).

local InputGuard = {}
InputGuard.__index = InputGuard

-- a stale press's release can reach the button a moment after the input layer
-- reported it, so the release stays stale this long
local RELEASE_GRACE = 0.1

export type Guard = typeof(setmetatable(
	{} :: {
		_held: { [any]: boolean },
		_stale: { [any]: boolean | number },
		_unlockAt: number?,
	},
	InputGuard
))

function InputGuard.new(): Guard
	return setmetatable({ _held = {}, _stale = {}, _unlockAt = nil }, InputGuard)
end

--- Lock for `seconds` from `now`. Whatever is held right now turns stale.
function InputGuard.lock(self: Guard, seconds: number, now: number)
	self._unlockAt = now + math.max(0, seconds)
	table.clear(self._stale)
	for key in self._held do
		self._stale[key] = true
	end
end

--- No panel any more: nothing is locked and nothing is stale.
function InputGuard.clear(self: Guard)
	self._unlockAt = nil
	table.clear(self._stale)
end

function InputGuard.locked(self: Guard, now: number): boolean
	return self._unlockAt ~= nil and now < self._unlockAt
end

--- When the lock ends (nil when nothing is locked).
function InputGuard.unlockAt(self: Guard): number?
	return self._unlockAt
end

function InputGuard.press(self: Guard, key: any, now: number)
	self._held[key] = true
	if self:locked(now) then
		self._stale[key] = true
	else
		self._stale[key] = nil -- a fresh press after the lock
	end
end

function InputGuard.release(self: Guard, key: any, now: number)
	self._held[key] = nil
	if self._stale[key] == true then
		self._stale[key] = now
	end
end

--- The window lost focus: its button-ups will never arrive.
function InputGuard.dropHeld(self: Guard)
	table.clear(self._held)
end

--- May this input (nil when the caller cannot tell which) answer the panel now?
function InputGuard.accepts(self: Guard, key: any?, now: number): boolean
	if self:locked(now) then
		return false
	end
	if key == nil then
		return true
	end
	local stale = self._stale[key]
	if stale == true then
		return false
	elseif type(stale) == "number" then
		return now - stale > RELEASE_GRACE
	end
	return true
end

return InputGuard

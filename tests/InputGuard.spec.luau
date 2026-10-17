--!strict
-- Specs for T1: a level-up panel's lock and the fresh-press rule (Core/InputGuard).

local GameConfig = require("../src/shared/Config/GameConfig")
local InputGuard = require("../src/shared/Core/InputGuard")

local LOCK, FOLLOW = GameConfig.OfferLockSeconds, GameConfig.OfferLockFollowSeconds

return {
	["the locks are the agreed lengths"] = function()
		assert(LOCK == 0.7, `first lock {LOCK}`)
		assert(FOLLOW == 0.35, `follow-up lock {FOLLOW}`)
	end,

	["nothing answers during the lock, a fresh press does after it"] = function()
		local g = InputGuard.new()
		g:lock(LOCK, 10)
		assert(g:locked(10.69) and not g:accepts("mouse", 10.69))
		assert(not g:locked(10.7))
		g:press("mouse", 10.8)
		assert(g:accepts("mouse", 10.85))
		g:release("mouse", 10.85)
		assert(g:accepts("mouse", 10.85), "the release of a fresh press picks")
	end,

	["a button held since before the panel never picks on release"] = function()
		local g = InputGuard.new()
		g:press("mouse", 9.5) -- attacking when the level-up lands
		g:lock(LOCK, 10)
		assert(not g:accepts("mouse", 11), "still held after the lock")
		g:release("mouse", 11.2)
		assert(not g:accepts("mouse", 11.2), "its release, in the same moment")
		assert(not g:accepts("mouse", 11.25), "its release, a frame late")
		g:press("mouse", 11.5)
		assert(g:accepts("mouse", 11.5), "the next press is fresh")
	end,

	["a press made during the lock stays stale after it"] = function()
		local g = InputGuard.new()
		g:lock(LOCK, 10)
		g:press("ButtonA", 10.3) -- a hop on the controller
		assert(not g:accepts("ButtonA", 10.9))
		g:release("ButtonA", 11)
		assert(not g:accepts("ButtonA", 11.05))
		g:press("ButtonA", 11.4)
		assert(g:accepts("ButtonA", 11.4))
	end,

	["presses are not queued: a quick tap during the lock is simply gone"] = function()
		local g = InputGuard.new()
		g:lock(LOCK, 10)
		g:press("mouse", 10.2)
		g:release("mouse", 10.25)
		assert(not g:accepts("mouse", 10.25))
		assert(g:accepts("mouse", 10.8), "only a later input could answer, and it would be its own press")
	end,

	["one stale finger does not block another"] = function()
		local g = InputGuard.new()
		local stick, tap = {}, {}
		g:press(stick, 9) -- the thumb on the move stick
		g:lock(LOCK, 10)
		g:press(tap, 10.9)
		assert(g:accepts(tap, 10.95))
		assert(not g:accepts(stick, 10.95))
	end,

	["a follow-up offer locks again, and what is held then turns stale"] = function()
		local g = InputGuard.new()
		g:lock(LOCK, 10)
		g:press("mouse", 11) -- picks the first offer
		g:lock(FOLLOW, 11.01) -- the next one follows at once
		assert(g:locked(11.3) and not g:locked(11.37))
		assert(not g:accepts("mouse", 11.5), "the press that picked the last one")
	end,

	["the other panels lock for the agreed lengths"] = function()
		local p = GameConfig.PanelLockSeconds
		assert(p.shrine == 0.5, "the shrine opens by itself mid-fight")
		assert(p.statue == 0.35 and p.shop == 0.35 and p.chest == 0.35, "opened on purpose with E / X")
		assert(GameConfig.PanelLockAgainSeconds == 0.35, "after a purchase or a chest's Banish")
	end,

	["a panel re-sent with no lock still never takes a held press"] = function()
		local g = InputGuard.new()
		g:lock(0.35, 10)
		g:press("mouse", 10.5) -- buys, and keeps the button down
		g:lock(0, 10.55) -- the refused purchase comes back with no lock
		assert(not g:locked(10.55))
		assert(not g:accepts("mouse", 10.6), "the held button cannot buy again")
		g:release("mouse", 10.7)
		g:press("mouse", 10.9)
		assert(g:accepts("mouse", 10.9))
	end,

	["clearing the panel forgets the lock and stale keys"] = function()
		local g = InputGuard.new()
		g:press("mouse", 9)
		g:lock(LOCK, 10)
		g:clear()
		assert(g:unlockAt() == nil and g:accepts("mouse", 10))
	end,
}

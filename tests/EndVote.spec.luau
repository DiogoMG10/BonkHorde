--!strict
-- Specs for T3: CONTINUE on the results (Core/EndVote). One player must never
-- end the results for the others, and a stale press must never count.

local EndVote = require("../src/shared/Core/EndVote")

return {
	["solo: one press and the results are over"] = function()
		local s = EndVote.new(4, { 101 })
		assert(not EndVote.everyone(s, { 101 }))
		assert(EndVote.press(s, 4, 101))
		assert(EndVote.everyone(s, { 101 }))
	end,

	["co-op: every member still here must press"] = function()
		local s = EndVote.new(7, { 1, 2, 3 })
		assert(EndVote.press(s, 7, 1))
		assert(not EndVote.everyone(s, { 1, 2, 3 }), "one press does not end it for the squad")
		local ready, need = EndVote.count(s, { 1, 2, 3 })
		assert(ready == 1 and need == 3)
		assert(EndVote.press(s, 7, 3))
		assert(not EndVote.everyone(s, { 1, 2, 3 }))
		assert(EndVote.press(s, 7, 2))
		assert(EndVote.everyone(s, { 1, 2, 3 }))
	end,

	["a player who left no longer holds the squad"] = function()
		local s = EndVote.new(2, { 1, 2 })
		EndVote.press(s, 2, 1)
		assert(EndVote.everyone(s, { 1 }), "only the one still here had to press")
		local ready, need = EndVote.count(s, { 1 })
		assert(ready == 1 and need == 1)
	end,

	["a press counts once, for its own run, from a member"] = function()
		local s = EndVote.new(9, { 1, 2 })
		assert(not EndVote.press(s, 8, 1), "a press for the last run is stale")
		assert(not EndVote.press(s, 9, 55), "someone who joined after the run ended is not asked")
		assert(EndVote.press(s, 9, 1))
		assert(not EndVote.press(s, 9, 1), "pressing twice changes nothing")
		local ready, need = EndVote.count(s, { 1, 2, 55 })
		assert(ready == 1 and need == 2)
		assert(#EndVote.readyList(s, { 1, 2, 55 }) == 1)
	end,

	["nobody left: the fallback clock decides, not the vote"] = function()
		local s = EndVote.new(1, { 1, 2 })
		assert(not EndVote.everyone(s, {}))
		assert(not EndVote.everyone(s, { 77 }), "a newcomer alone does not end the results")
	end,
}

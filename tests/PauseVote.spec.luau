--!strict
-- Specs for a player-asked pause: solo pauses at once, co-op needs everyone.

local PauseVote = require("../src/shared/Core/PauseVote")

local CFG = { voteSeconds = 15, pauseSeconds = 60, resumeSeconds = 3, cooldown = 30 }
local A, B, C = 1, 2, 3

return {
	["solo: asking pauses at once, with no limit, and resume is immediate"] = function()
		local s = PauseVote.new()
		assert(PauseVote.request(s, A, { A }, 0, CFG))
		assert(s.mode == "paused" and s.ends == math.huge)
		assert(not PauseVote.step(s, { A }, 10000, CFG), "a solo pause never runs out")
		assert(s.mode == "paused")
		assert(PauseVote.resume(s, A, { A }, 10001, CFG))
		assert(s.mode == "none", "solo resume is immediate")
		assert(PauseVote.request(s, A, { A }, 10002, CFG), "solo has no cooldown")
	end,

	["co-op: one vote does not pause, two do"] = function()
		local s = PauseVote.new()
		assert(PauseVote.request(s, A, { A, B }, 0, CFG))
		assert(s.mode == "vote", "one vote of two must leave the game running")
		assert(PauseVote.accept(s, B, { A, B }, 2, CFG))
		assert(s.mode == "paused" and s.ends == 62)
	end,

	["co-op: asking while a vote is open is agreeing"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B, C }, 0, CFG)
		PauseVote.request(s, B, { A, B, C }, 1, CFG)
		assert(s.mode == "vote" and PauseVote.votes(s) == 2)
		PauseVote.request(s, C, { A, B, C }, 2, CFG)
		assert(s.mode == "paused")
	end,

	["co-op: a vote lapses after its time"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B }, 0, CFG)
		assert(not PauseVote.step(s, { A, B }, 14.9, CFG))
		assert(PauseVote.step(s, { A, B }, 15, CFG))
		assert(s.mode == "none")
		assert(not PauseVote.accept(s, B, { A, B }, 16, CFG), "a lapsed vote cannot be accepted")
	end,

	["co-op: play resumes only when everyone is ready, after a countdown"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B }, 0, CFG)
		PauseVote.accept(s, B, { A, B }, 0, CFG)
		assert(PauseVote.resume(s, B, { A, B }, 10, CFG))
		assert(not s.resuming and s.mode == "paused", "one ready of two keeps the pause")
		assert(PauseVote.readyCount(s) == 1)
		assert(PauseVote.resume(s, A, { A, B }, 12, CFG))
		assert(s.resuming and s.ends == 15, "everyone ready: a three second countdown")
		assert(not PauseVote.resume(s, A, { A, B }, 13, CFG), "the countdown cannot be stopped")
		assert(not PauseVote.step(s, { A, B }, 14.9, CFG))
		assert(s.mode == "paused", "the world stays frozen through the countdown")
		PauseVote.step(s, { A, B }, 15, CFG)
		assert(s.mode == "none")
	end,

	["co-op: pressing READY again takes it back"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B }, 0, CFG)
		PauseVote.accept(s, B, { A, B }, 0, CFG)
		PauseVote.resume(s, A, { A, B }, 1, CFG)
		PauseVote.resume(s, A, { A, B }, 2, CFG)
		assert(PauseVote.readyCount(s) == 0)
		PauseVote.resume(s, B, { A, B }, 3, CFG)
		assert(not s.resuming, "A is no longer ready")
	end,

	["co-op: at the limit the countdown starts by itself and ends on time"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B }, 0, CFG)
		PauseVote.accept(s, B, { A, B }, 0, CFG)
		assert(not PauseVote.step(s, { A, B }, 56.9, CFG))
		assert(PauseVote.step(s, { A, B }, 57, CFG))
		assert(s.resuming and s.ends == 60, "the countdown fits inside the sixty seconds")
		PauseVote.step(s, { A, B }, 60, CFG)
		assert(s.mode == "none")
	end,

	["co-op: everyone ready near the limit never runs past it"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B }, 0, CFG)
		PauseVote.accept(s, B, { A, B }, 0, CFG)
		PauseVote.resume(s, A, { A, B }, 56.5, CFG)
		PauseVote.resume(s, B, { A, B }, 56.8, CFG)
		assert(s.resuming and s.ends == 59.8)
	end,

	["co-op: a player who is not ready leaving starts the countdown"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B, C }, 0, CFG)
		PauseVote.accept(s, B, { A, B, C }, 0, CFG)
		PauseVote.accept(s, C, { A, B, C }, 0, CFG)
		PauseVote.resume(s, A, { A, B, C }, 5, CFG)
		PauseVote.resume(s, B, { A, B, C }, 6, CFG)
		assert(not s.resuming)
		assert(PauseVote.step(s, { A, B }, 7, CFG))
		assert(s.resuming and s.ends == 10)
	end,

	["co-op: a ready player leaving does not count any more"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B, C }, 0, CFG)
		PauseVote.accept(s, B, { A, B, C }, 0, CFG)
		PauseVote.accept(s, C, { A, B, C }, 0, CFG)
		PauseVote.resume(s, A, { A, B, C }, 5, CFG)
		PauseVote.step(s, { B, C }, 6, CFG)
		assert(PauseVote.readyCount(s) == 0 and not s.resuming)
	end,

	["co-op: a newcomer during a pause must also be ready"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B }, 0, CFG)
		PauseVote.accept(s, B, { A, B }, 0, CFG)
		PauseVote.resume(s, A, { A, B }, 5, CFG)
		PauseVote.step(s, { A, B, C }, 6, CFG)
		PauseVote.resume(s, B, { A, B, C }, 7, CFG)
		assert(not s.resuming, "two ready of three")
		PauseVote.resume(s, C, { A, B, C }, 8, CFG)
		assert(s.resuming)
	end,

	["co-op: asking again is limited by a cooldown"] = function()
		local s = PauseVote.new()
		assert(PauseVote.request(s, A, { A, B }, 0, CFG))
		assert(PauseVote.withdraw(s, A))
		assert(not PauseVote.request(s, A, { A, B }, 10, CFG), "spam is refused")
		assert(PauseVote.cooldownLeft(s, A, 10, CFG) == 20)
		assert(PauseVote.request(s, B, { A, B }, 10, CFG), "the cooldown is per player")
		PauseVote.withdraw(s, B)
		assert(PauseVote.request(s, A, { A, B }, 30, CFG))
	end,

	["co-op: only the asker can withdraw"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B, C }, 0, CFG)
		PauseVote.accept(s, B, { A, B, C }, 0, CFG)
		assert(not PauseVote.withdraw(s, B))
		assert(PauseVote.withdraw(s, A) and s.mode == "none")
	end,

	["leaving: the last holdout leaving completes the vote"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B, C }, 0, CFG)
		PauseVote.accept(s, B, { A, B, C }, 1, CFG)
		assert(PauseVote.step(s, { A, B }, 2, CFG))
		assert(s.mode == "paused" and s.ends == 62)
	end,

	["leaving: a vote whose voters all left is dropped"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B, C }, 0, CFG)
		assert(PauseVote.step(s, { B, C }, 1, CFG))
		assert(s.mode == "none")
	end,

	["leaving: an empty run never stays paused"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A }, 0, CFG)
		assert(PauseVote.step(s, {}, 1, CFG))
		assert(s.mode == "none")
	end,

	["joining: a solo pause gains the co-op limit when someone joins"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A }, 0, CFG)
		assert(PauseVote.step(s, { A, B }, 100, CFG))
		assert(s.ends == 160)
		PauseVote.step(s, { A, B }, 157, CFG)
		assert(s.resuming, "and the same countdown at its end")
		PauseVote.step(s, { A, B }, 160, CFG)
		assert(s.mode == "none")
	end,

	["joining: a newcomer must also agree"] = function()
		local s = PauseVote.new()
		PauseVote.request(s, A, { A, B }, 0, CFG)
		PauseVote.step(s, { A, B, C }, 1, CFG)
		PauseVote.accept(s, B, { A, B, C }, 2, CFG)
		assert(s.mode == "vote", "two of three is not everyone")
		PauseVote.accept(s, C, { A, B, C }, 3, CFG)
		assert(s.mode == "paused")
	end,

	["strangers cannot vote"] = function()
		local s = PauseVote.new()
		assert(not PauseVote.request(s, C, { A, B }, 0, CFG))
		PauseVote.request(s, A, { A, B }, 0, CFG)
		assert(not PauseVote.accept(s, C, { A, B }, 1, CFG))
		assert(s.mode == "vote")
	end,
}

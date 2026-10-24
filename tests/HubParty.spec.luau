--!strict
-- Specs for T6/T7: the rune circles on Skyhold (Core/HubParty). Membership only
-- changes on a deliberate call, the leader starts the preparation, everyone
-- must be READY, any leave or unready cancels safely, and only one party enters
-- the portal while the server's one run is busy.

local HubParty = require("../src/shared/Core/HubParty")

local function hub()
	return HubParty.new(4, 3, 5, 3)
end

return {
	["solo: one deliberate start, ready at once, a short countdown, then the portal"] = function()
		local h = hub()
		assert(HubParty.start(h, 1, 2, "solo", 0))
		local p = HubParty.partyOf(h, 1)
		assert(p and p.phase == "countdown" and p.ends == 3, "a solo party counts down from the solo time")
		assert(not HubParty.join(h, 2, 2), "nobody joins a solo party")
		assert(HubParty.step(h, 2.9, false) == nil)
		local launched = HubParty.step(h, 3, false)
		assert(launched == p and p.phase == "run")
	end,

	["a squad forms, the leader prepares, everyone readies, then the countdown"] = function()
		local h = hub()
		assert(HubParty.start(h, 1, 1, "squad", 0))
		assert(HubParty.join(h, 2, 1))
		assert(HubParty.join(h, 3, 1))
		assert(not HubParty.join(h, 4, 1), "three is a full squad")
		assert(not HubParty.prepare(h, 2, 0), "only the leader starts the preparation")
		assert(HubParty.prepare(h, 1, 0))
		local p = HubParty.partyOf(h, 1)
		assert(p and p.phase == "preparing" and p.ready[1], "the leader is ready by preparing")
		assert(HubParty.setReady(h, 2, true, 1))
		assert(p.phase == "preparing", "one member still to confirm")
		assert(HubParty.setReady(h, 3, true, 2))
		assert(p.phase == "countdown" and p.ends == 7)
	end,

	["an unready during the countdown stops it; readying again restarts it"] = function()
		local h = hub()
		HubParty.start(h, 1, 1, "squad", 0)
		HubParty.join(h, 2, 1)
		HubParty.prepare(h, 1, 0)
		HubParty.setReady(h, 2, true, 0)
		local p = HubParty.partyOf(h, 1)
		assert(p and p.phase == "countdown")
		assert(HubParty.setReady(h, 2, false, 2))
		assert(p.phase == "preparing" and p.ends == nil and p.ready[1], "the others stay ready")
		assert(HubParty.step(h, 10, false) == nil, "nothing launches without the countdown")
		assert(HubParty.setReady(h, 2, true, 11))
		assert(p.phase == "countdown" and p.ends == 16)
	end,

	["a leave cancels the preparation and passes the lead on"] = function()
		local h = hub()
		HubParty.start(h, 1, 3, "squad", 0)
		HubParty.join(h, 2, 3)
		HubParty.join(h, 3, 3)
		HubParty.prepare(h, 1, 0)
		HubParty.setReady(h, 2, true, 0)
		HubParty.setReady(h, 3, true, 0)
		assert(HubParty.leave(h, 1) == 3)
		local p = HubParty.partyOf(h, 2)
		assert(p and p.leader == 2, "the next member leads")
		assert(p.phase == "forming" and next(p.ready) == nil, "nobody is ready after a leave")
		assert(HubParty.leave(h, 2) == 3 and HubParty.leave(h, 3) == 3)
		assert(h.parties[3] == nil, "the last one out ends the party")
	end,

	["joining needs an open squad with room, not a countdown and not a second party"] = function()
		local h = hub()
		HubParty.start(h, 1, 1, "squad", 0)
		assert(not HubParty.start(h, 2, 1, "squad", 0), "one party per circle")
		assert(HubParty.start(h, 2, 2, "squad", 0))
		assert(not HubParty.join(h, 2, 1), "already in a party")
		assert(HubParty.join(h, 5, 1))
		HubParty.prepare(h, 1, 0)
		assert(HubParty.join(h, 3, 1), "a preparing squad still takes members")
		HubParty.setReady(h, 3, true, 0)
		HubParty.setReady(h, 5, true, 0)
		local p = HubParty.partyOf(h, 1)
		assert(p and p.phase == "countdown")
		assert(not HubParty.join(h, 4, 1), "a squad counting down is closed")
	end,

	["a busy portal makes a finished countdown wait; the longest wait goes first"] = function()
		local h = hub()
		HubParty.start(h, 1, 1, "solo", 0)
		HubParty.start(h, 2, 2, "solo", 1)
		assert(HubParty.step(h, 5, true) == nil, "a run is on")
		local a, b = HubParty.partyOf(h, 1), HubParty.partyOf(h, 2)
		assert(a and b and a.phase == "waiting" and b.phase == "waiting")
		assert(HubParty.step(h, 6, false) == nil, "a waiting party counts down again first")
		assert(a.phase == "countdown" and b.phase == "waiting", "the one that waited longest is first")
		assert(HubParty.step(h, 8.9, false) == nil)
		assert(HubParty.step(h, 9, false) == a)
		assert(HubParty.step(h, 20, true) == nil and b.phase == "waiting", "the next waits for the next free portal")
	end,

	["two countdowns ending together: one run, the other waits"] = function()
		local h = hub()
		HubParty.start(h, 1, 1, "solo", 0)
		HubParty.start(h, 2, 4, "solo", 0)
		local launched = HubParty.step(h, 3, false)
		assert(launched and launched.circle == 1)
		local other = HubParty.partyOf(h, 2)
		assert(other and other.phase == "waiting")
	end,

	["after a run the party stands on its circle again, nobody ready"] = function()
		local h = hub()
		HubParty.start(h, 1, 1, "squad", 0)
		HubParty.join(h, 2, 1)
		HubParty.prepare(h, 1, 0)
		HubParty.setReady(h, 2, true, 0)
		local p = HubParty.step(h, 5, false)
		assert(p and p.phase == "run")
		assert(not HubParty.setReady(h, 2, false, 6), "no readiness games mid-run")
		assert(HubParty.leave(h, 2) == 1, "a disconnect mid-run leaves the party")
		assert(p.phase == "run", "the run goes on for the others")
		HubParty.runEnded(h, 1)
		assert(p.phase == "forming" and #p.members == 1 and next(p.ready) == nil)
	end,

	["a solo player calling it off ends the party"] = function()
		local h = hub()
		HubParty.start(h, 7, 2, "solo", 0)
		assert(HubParty.setReady(h, 7, false, 1))
		assert(h.parties[2] == nil and HubParty.partyOf(h, 7) == nil)
	end,

	["the leader can call the preparation off"] = function()
		local h = hub()
		HubParty.start(h, 1, 1, "squad", 0)
		HubParty.join(h, 2, 1)
		assert(not HubParty.cancel(h, 1), "nothing to call off while forming")
		HubParty.prepare(h, 1, 0)
		HubParty.setReady(h, 2, true, 0)
		assert(not HubParty.cancel(h, 2), "only the leader calls it off")
		assert(HubParty.cancel(h, 1))
		local p = HubParty.partyOf(h, 1)
		assert(p and p.phase == "forming" and #p.members == 2)
	end,

	["the snapshot says who, who leads, who is ready and how long is left"] = function()
		local h = hub()
		HubParty.start(h, 5, 3, "squad", 0)
		HubParty.join(h, 6, 3)
		HubParty.prepare(h, 5, 0)
		HubParty.setReady(h, 6, true, 0)
		local snap = HubParty.snapshot(h, 2)
		assert(#snap == 1)
		local e = snap[1]
		assert(e.circle == 3 and e.leader == 5 and #e.members == 2 and #e.ready == 2)
		assert(e.phase == "countdown" and e.seconds == 3)
	end,

	-- T8: after the countdown the party departs (sinking into the portal on the
	-- ground) for `descent` seconds before it enters the run
	["with a descent, a finished countdown departs, committed, then enters the run"] = function()
		local h = HubParty.new(4, 3, 5, 5, 1.6, 3)
		assert(HubParty.start(h, 1, 2, "solo", 0))
		local p = HubParty.partyOf(h, 1)
		assert(p and p.ends == 5, "a solo countdown of five seconds")
		local launched, departed = HubParty.step(h, 5, false)
		assert(launched == nil and departed == p and p.phase == "departing", "departing, not yet in the run")
		assert(p.ends and math.abs(p.ends - 6.6) < 1e-9)
		assert(not HubParty.setReady(h, 1, false, 5.5), "no taking READY back once departing")
		assert(not HubParty.cancel(h, 1), "nor calling it off")
		assert(not HubParty.join(h, 9, 2), "nor joining")
		assert(HubParty.snapshot(h, 6)[1].phase == "departing")
		assert(HubParty.step(h, 6.5, false) == nil)
		local through, again = HubParty.step(h, 6.6, false)
		assert(through == p and again == nil and p.phase == "run")
	end,

	["a member leaving the server mid-departure drops out; the rest go on"] = function()
		local h = HubParty.new(4, 3, 5, 5, 1.6, 3)
		HubParty.start(h, 1, 1, "squad", 0)
		HubParty.join(h, 2, 1)
		HubParty.prepare(h, 1, 0)
		HubParty.setReady(h, 2, true, 0)
		local _, departed = HubParty.step(h, 5, false)
		assert(departed)
		assert(HubParty.leave(h, 1) == 1)
		local p = HubParty.partyOf(h, 2)
		assert(p and p.phase == "departing" and p.leader == 2 and p.ready[2], "still on its way, led by the next")
		assert(HubParty.step(h, 6.7, false) == p and p.phase == "run")
	end,

	["a departing party has the portal: another countdown ending meanwhile waits"] = function()
		local h = HubParty.new(4, 3, 5, 5, 1.6, 3)
		HubParty.start(h, 1, 1, "solo", 0)
		HubParty.start(h, 2, 2, "solo", 0.5)
		local _, a = HubParty.step(h, 5, false)
		assert(a and a.circle == 1)
		local launched, departed = HubParty.step(h, 5.5, false)
		assert(launched == nil and departed == nil)
		local b = HubParty.partyOf(h, 2)
		assert(b and b.phase == "waiting", "the portal is taken")
		assert(HubParty.step(h, 6.6, false) == a)
		HubParty.step(h, 7, true)
		assert(b.phase == "waiting", "and stays taken while the run is on")
		HubParty.step(h, 30, false)
		assert(b.phase == "countdown" and b.ends == 33, "its turn: the short countdown again")
	end,

	["the run could not start: a departed party stands on its circle again"] = function()
		local h = HubParty.new(4, 3, 5, 5, 1.6, 3)
		HubParty.start(h, 1, 3, "solo", 0)
		HubParty.step(h, 5, false)
		HubParty.launchFailed(h, 3)
		local p = HubParty.partyOf(h, 1)
		assert(p and p.phase == "forming" and next(p.ready) == nil)
		assert(HubParty.prepare(h, 1, 8), "and can go again")
	end,
}

--!strict
-- EndVote - who has pressed CONTINUE on a run's results. Pure.
--
-- One server is one squad, so a run's results end for all of it at once: when
-- every player who was in the run and is still here has pressed CONTINUE, or
-- when the fallback time runs out (the run director keeps that clock). Solo,
-- one press is everyone. A press counts once, only for the run it names, and
-- only from a player who was in that run: a late or repeated message can never
-- end a later run's results, and nobody can end them for somebody else.

local EndVote = {}

export type State = {
	run: number,
	members: { [number]: boolean }, -- userIds in the run when it ended
	ready: { [number]: boolean },
}

function EndVote.new(run: number, members: { number }): State
	local set = {}
	for _, id in members do
		set[id] = true
	end
	return { run = run, members = set, ready = {} }
end

--- `id` pressed CONTINUE on run `run`. True when it counted.
function EndVote.press(s: State, run: number, id: number): boolean
	if run ~= s.run or not s.members[id] or s.ready[id] then
		return false
	end
	s.ready[id] = true
	return true
end

--- How many of the members still `present` have pressed, and how many there are.
function EndVote.count(s: State, present: { number }): (number, number)
	local ready, need = 0, 0
	for _, id in present do
		if s.members[id] then
			need += 1
			if s.ready[id] then
				ready += 1
			end
		end
	end
	return ready, need
end

--- Has every member still here pressed? (Never true with nobody left: the
--- fallback clock ends an empty squad's results.)
function EndVote.everyone(s: State, present: { number }): boolean
	local ready, need = EndVote.count(s, present)
	return need > 0 and ready >= need
end

--- The members still here who have pressed, for the clients.
function EndVote.readyList(s: State, present: { number }): { number }
	local out = {}
	for _, id in present do
		if s.members[id] and s.ready[id] then
			table.insert(out, id)
		end
	end
	return out
end

return EndVote

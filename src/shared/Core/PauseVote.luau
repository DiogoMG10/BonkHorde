--!strict
-- PauseVote - the rules of a pause a player asks for. Pure.
--
-- Solo: asking pauses at once, with no time limit, and resuming is immediate.
-- Co-op: asking opens a vote that lapses after `voteSeconds`; the run only
-- pauses once every participant has agreed, and then for at most
-- `pauseSeconds`. Anyone in the run can end it early; that starts a short
-- `resumeSeconds` countdown so nobody is thrown back in mid-thought, and it
-- can never lengthen the pause, so one player cannot hold the others.
-- A player may ask once per `cooldown` seconds. Times are real seconds.

local PauseVote = {}

export type Mode = "none" | "vote" | "paused"

export type Config = {
	voteSeconds: number,
	pauseSeconds: number,
	resumeSeconds: number,
	cooldown: number,
}

export type State = {
	mode: Mode,
	by: number?, -- who asked
	votes: { [number]: boolean },
	need: number, -- how many participants there were when last settled
	ends: number, -- vote: when it lapses; paused: when it ends (math.huge solo)
	resuming: boolean,
	lastAsk: { [number]: number },
}

function PauseVote.new(): State
	return { mode = "none", by = nil, votes = {}, need = 0, ends = 0, resuming = false, lastAsk = {} }
end

local function clear(s: State)
	s.mode = "none"
	s.by = nil
	table.clear(s.votes)
	s.ends = 0
	s.resuming = false
end

--- Forget everything, cooldowns too (a run ended).
function PauseVote.reset(s: State)
	clear(s)
	s.need = 0
	table.clear(s.lastAsk)
end

local function has(list: { number }, id: number): boolean
	return table.find(list, id) ~= nil
end

local function count(s: State): number
	local n = 0
	for _ in s.votes do
		n += 1
	end
	return n
end

--- How many have agreed so far.
function PauseVote.votes(s: State): number
	return count(s)
end

local function startPause(s: State, participants: { number }, now: number, cfg: Config)
	s.mode = "paused"
	s.resuming = false
	s.ends = if #participants <= 1 then math.huge else now + cfg.pauseSeconds
end

-- Drop votes from people who left; pause when everyone left has agreed.
local function settle(s: State, participants: { number }, now: number, cfg: Config)
	for id in s.votes do
		if not has(participants, id) then
			s.votes[id] = nil
		end
	end
	s.need = #participants
	if s.mode == "vote" then
		local n = count(s)
		if n == 0 then
			clear(s)
		elseif n >= #participants then
			startPause(s, participants, now, cfg)
		end
	end
end

--- `id` asks for a pause. Returns whether anything changed. Asking while a
--- vote is open counts as agreeing to it.
function PauseVote.request(s: State, id: number, participants: { number }, now: number, cfg: Config): boolean
	if not has(participants, id) or s.mode == "paused" then
		return false
	end
	if s.mode == "vote" then
		return PauseVote.accept(s, id, participants, now, cfg)
	end
	if #participants <= 1 then
		s.by = id
		startPause(s, participants, now, cfg)
		s.need = #participants
		return true
	end
	local last = s.lastAsk[id]
	if last and now - last < cfg.cooldown then
		return false
	end
	s.lastAsk[id] = now
	s.mode = "vote"
	s.by = id
	table.clear(s.votes)
	s.votes[id] = true
	s.ends = now + cfg.voteSeconds
	settle(s, participants, now, cfg)
	return true
end

--- Seconds until `id` may ask again (0 when they may).
function PauseVote.cooldownLeft(s: State, id: number, now: number, cfg: Config): number
	local last = s.lastAsk[id]
	return if last then math.max(0, cfg.cooldown - (now - last)) else 0
end

function PauseVote.accept(s: State, id: number, participants: { number }, now: number, cfg: Config): boolean
	if s.mode ~= "vote" or not has(participants, id) or s.votes[id] then
		return false
	end
	s.votes[id] = true
	settle(s, participants, now, cfg)
	return true
end

--- The asker takes the request back.
function PauseVote.withdraw(s: State, id: number): boolean
	if s.mode ~= "vote" or s.by ~= id then
		return false
	end
	clear(s)
	return true
end

--- `id` wants to play again.
function PauseVote.resume(s: State, id: number, participants: { number }, now: number, cfg: Config): boolean
	if s.mode ~= "paused" or not has(participants, id) then
		return false
	end
	if #participants <= 1 then
		clear(s)
		return true
	end
	if s.resuming then
		return false
	end
	s.resuming = true
	s.ends = math.min(s.ends, now + cfg.resumeSeconds)
	return true
end

--- Every frame. Lapses votes, ends pauses on time and follows players
--- joining and leaving. Returns whether anything a client sees changed.
function PauseVote.step(s: State, participants: { number }, now: number, cfg: Config): boolean
	if s.mode == "none" then
		s.need = #participants
		return false
	end
	local before = `{s.mode}:{count(s)}:{s.need}:{s.ends}`
	if #participants == 0 or now >= s.ends then
		clear(s)
	else
		settle(s, participants, now, cfg)
		if s.mode == "paused" and #participants > 1 and s.ends == math.huge then
			-- someone joined a solo pause: it now has a limit like any co-op one
			s.ends = now + cfg.pauseSeconds
		end
	end
	s.need = #participants
	return `{s.mode}:{count(s)}:{s.need}:{s.ends}` ~= before
end

return PauseVote

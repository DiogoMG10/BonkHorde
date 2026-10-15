--!strict
-- PauseVote - the rules of a pause a player asks for. Pure.
--
-- Solo: asking pauses at once, with no time limit, and resuming is immediate.
-- Co-op: asking opens a vote that lapses after `voteSeconds`; the run only
-- pauses once every participant has agreed, and then for at most
-- `pauseSeconds`. To play on, every participant marks READY; once they all
-- have, a `resumeSeconds` countdown runs with the world still frozen. If time
-- runs out first, the same countdown starts on its own `resumeSeconds` before
-- the limit, so the pause never lasts longer than `pauseSeconds` and one
-- player can never hold the others. A player may ask once per `cooldown`
-- seconds. Times are real seconds.

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
	ready: { [number]: boolean }, -- paused: who is ready to play on
	resuming: boolean, -- paused: the final countdown is running
	lastAsk: { [number]: number },
}

function PauseVote.new(): State
	return { mode = "none", by = nil, votes = {}, need = 0, ends = 0, ready = {}, resuming = false, lastAsk = {} }
end

local function clear(s: State)
	s.mode = "none"
	s.by = nil
	table.clear(s.votes)
	table.clear(s.ready)
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

local function size(set: { [number]: boolean }): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

local function count(s: State): number
	return size(s.votes)
end

--- How many have agreed so far.
function PauseVote.votes(s: State): number
	return count(s)
end

--- How many are ready to play on.
function PauseVote.readyCount(s: State): number
	return size(s.ready)
end

local function startPause(s: State, participants: { number }, now: number, cfg: Config)
	s.mode = "paused"
	s.resuming = false
	table.clear(s.ready)
	s.ends = if #participants <= 1 then math.huge else now + cfg.pauseSeconds
end

-- The final countdown: never later than the pause's own limit.
local function startCountdown(s: State, now: number, cfg: Config)
	s.resuming = true
	s.ends = math.min(s.ends, now + cfg.resumeSeconds)
end

-- Drop votes and readies from people who left; pause when everyone left has
-- agreed; count down when everyone left is ready, or when time is nearly up.
local function settle(s: State, participants: { number }, now: number, cfg: Config)
	for _, set in { s.votes, s.ready } do
		for id in set do
			if not has(participants, id) then
				set[id] = nil
			end
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
	elseif s.mode == "paused" and not s.resuming and s.ends ~= math.huge then
		local n = size(s.ready)
		if (n > 0 and n >= #participants) or now >= s.ends - cfg.resumeSeconds then
			startCountdown(s, now, cfg)
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

--- `id` is ready to play on (or, pressed again, no longer is). Solo resumes
--- at once.
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
	s.ready[id] = if s.ready[id] then nil else true
	settle(s, participants, now, cfg)
	return true
end

--- Every frame. Lapses votes, ends pauses on time and follows players
--- joining and leaving. Returns whether anything a client sees changed.
function PauseVote.step(s: State, participants: { number }, now: number, cfg: Config): boolean
	if s.mode == "none" then
		s.need = #participants
		return false
	end
	local before = `{s.mode}:{count(s)}:{size(s.ready)}:{s.resuming}:{s.need}:{s.ends}`
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
	return `{s.mode}:{count(s)}:{size(s.ready)}:{s.resuming}:{s.need}:{s.ends}` ~= before
end

return PauseVote

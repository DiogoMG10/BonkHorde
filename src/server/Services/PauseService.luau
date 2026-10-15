--!nonstrict
-- PauseService - the pause a player asks for with P or Start. The rules are in
-- Core/PauseVote; this keeps the votes, holds the run director's "player"
-- pause reason while the vote says so, and tells every client where it stands.
--
-- It only ever sets its own reasons, so a level-up or a panel pause is never
-- lifted by a player resuming, and the other way round.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local PauseVote = require(ReplicatedStorage.Shared.Core.PauseVote)
local RunState = require(ReplicatedStorage.Shared.Core.RunState)

local PauseService = Knit.CreateService({ Name = "PauseService" })

local CFG = {
	voteSeconds = GameConfig.PauseVoteSeconds,
	pauseSeconds = GameConfig.PauseCoopSeconds,
	resumeSeconds = GameConfig.PauseResumeSeconds,
	cooldown = GameConfig.PauseAskCooldown,
}
local MESSAGE_GAP = 0.2 -- seconds between two messages a player may send

function PauseService:KnitInit()
	self._vote = PauseVote.new()
	self._lastMessage = {}
	self._event = Net.server("Pause")
end

function PauseService:KnitStart()
	self._director = Knit.GetService("RunDirectorService")
	self._players = Knit.GetService("PlayerStateService")

	Net.server("PauseAsk").OnServerEvent:Connect(function(player: Player, action: unknown)
		if typeof(action) ~= "string" then
			return
		end
		local now = os.clock()
		if now - (self._lastMessage[player] or 0) < MESSAGE_GAP then
			return
		end
		self._lastMessage[player] = now
		if not RunState.isLive(self._director:GetPhase()) or not self._players:Get(player) then
			return
		end
		local vote, id, list = self._vote, player.UserId, self:_participants()
		local changed = false
		if action == "request" then
			changed = PauseVote.request(vote, id, list, now, CFG)
			if not changed and vote.mode == "none" then
				self:_send(player) -- refused (cooldown): the asker sees why
			end
		elseif action == "accept" then
			changed = PauseVote.accept(vote, id, list, now, CFG)
		elseif action == "withdraw" then
			changed = PauseVote.withdraw(vote, id)
		elseif action == "resume" then
			changed = PauseVote.resume(vote, id, list, now, CFG)
		end
		if changed then
			self:_apply()
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.delay(1.5, function()
			if player.Parent == Players then
				self:_send(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self._lastMessage[player] = nil
	end)
end

function PauseService:_participants(): { number }
	local ids = {}
	for _, rec in self._players:All() do
		if rec.active and rec.player.Parent == Players then
			table.insert(ids, rec.player.UserId)
		end
	end
	return ids
end

--- Run every frame from the run director, paused or not.
function PauseService:Step(now: number)
	local vote = self._vote
	if not RunState.isLive(self._director:GetPhase()) then
		-- a run ending, wiping or never started: no request or pause survives it
		if vote.mode ~= "none" or next(vote.lastAsk) then
			PauseVote.reset(vote)
			self:_apply()
		end
		return
	end
	if PauseVote.step(vote, self:_participants(), now, CFG) then
		self:_apply()
	end
end

function PauseService:_apply()
	self._director:SetPause("player", self._vote.mode == "paused")
	self:_send(nil)
end

function PauseService:_payload(player: Player?)
	local vote = self._vote
	local now = os.clock()
	local votes, ready = {}, {}
	for id in vote.votes do
		table.insert(votes, id)
	end
	for id in vote.ready do
		table.insert(ready, id)
	end
	local asker = vote.by and Players:GetPlayerByUserId(vote.by)
	return {
		mode = vote.mode,
		by = vote.by,
		byName = if asker then asker.DisplayName else nil,
		votes = votes,
		ready = ready,
		need = vote.need,
		seconds = if vote.ends == math.huge then -1 else math.max(0, vote.ends - now),
		resuming = vote.resuming,
		cooldown = if player then PauseVote.cooldownLeft(vote, player.UserId, now, CFG) else 0,
	}
end

function PauseService:_send(player: Player?)
	if player then
		self._event:FireClient(player, self:_payload(player))
	else
		self._event:FireAllClients(self:_payload(nil))
	end
end

return PauseService

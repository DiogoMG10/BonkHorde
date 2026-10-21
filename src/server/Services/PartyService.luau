--!nonstrict
-- PartyService - the island hub's people and parties (T6/T7).
--
-- Everyone in the server is on Skyhold, each with a stable index (what goes on
-- the wire in byte fields) and the hero they wear. Parties form at the rune
-- circles by deliberate actions only (PartyAction, rules in Core/HubParty):
-- start one (PLAY SOLO or OPEN SQUAD), join, leave, the leader's PREPARE, each
-- member's READY. A finished countdown enters the portal through `Launch`,
-- unless the server's one Wardwood run is busy: then the party waits its turn.
-- Joining, starting and readying need the player at that circle; leaving works
-- from anywhere. A player's hero only changes while they are not READY.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local HubParty = require(ReplicatedStorage.Shared.Core.HubParty)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)
local SkyholdGen = require(ReplicatedStorage.Shared.Core.SkyholdGen)

local PartyService = Knit.CreateService({ Name = "PartyService" })

local STEP_EVERY = 0.1

local plan = SkyholdGen.build(Skyhold)

function PartyService:KnitInit()
	self._members = {} -- player -> { index, hero }
	self._order = {} -- players in join order
	self._map = Roster.MapOrder[1]
	self._hub = HubParty.new(
		#Skyhold.Circles,
		math.min(Skyhold.SquadSize, GameConfig.MaxPlayers),
		Skyhold.CountdownSeconds,
		Skyhold.SoloCountdownSeconds
	)
	self._lastAction = {}
	self._sig = nil
	self.Launch = Signal.new() -- (players, circle): a party enters the portal
	self.HeroChanged = Signal.new() -- (player, heroId)
	self.MemberLeft = Signal.new()
	for _, name in Net.All do
		Net.server(name) -- every remote exists before any client asks
	end
	self._rosterEvent = Net.server("Roster")
	self._hubEvent = Net.server("Hub")
end

function PartyService:KnitStart()
	local DataService = Knit.GetService("DataService")
	self._director = Knit.GetService("RunDirectorService")
	self._data = DataService

	local function add(player: Player)
		if self._members[player] then
			return
		end
		local used = {}
		for _, m in self._members do
			used[m.index] = true
		end
		local index = 1
		while used[index] do
			index += 1
		end
		self._members[player] = { index = index, hero = DataService:LastHero(player) }
		table.insert(self._order, player)
		self:Broadcast()
	end

	Players.PlayerAdded:Connect(add)
	for _, player in Players:GetPlayers() do
		add(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		HubParty.leave(self._hub, player.UserId)
		self._members[player] = nil
		self._lastAction[player] = nil
		local i = table.find(self._order, player)
		if i then
			table.remove(self._order, i)
		end
		self.MemberLeft:Fire(player)
		self:Broadcast()
	end)
	-- the profile decides which hero a newcomer wears: the last one chosen
	DataService.Loaded:Connect(function(player)
		local m = self._members[player]
		if m and not HubParty.isReady(self._hub, player.UserId) then
			local hero = DataService:LastHero(player)
			if hero ~= m.hero then
				m.hero = hero
				self.HeroChanged:Fire(player, hero)
			end
			self:Broadcast()
		end
	end)

	Net.server("PickHero").OnServerEvent:Connect(function(player: Player, heroId: unknown)
		local m = self._members[player]
		if not m or typeof(heroId) ~= "string" or not Roster.Heroes[heroId] or m.hero == heroId then
			return
		end
		if HubParty.isReady(self._hub, player.UserId) or self:IsInRun(player) then
			return -- a ready (or running) hero is locked in: unready first
		end
		if not DataService:Get(player).unlocked[heroId] then
			return
		end
		m.hero = heroId
		DataService:SetLastHero(player, heroId)
		self.HeroChanged:Fire(player, heroId)
		self:Broadcast()
	end)

	Net.server("UnlockHero").OnServerEvent:Connect(function(player: Player, heroId: unknown)
		if typeof(heroId) ~= "string" then
			return
		end
		if DataService:Unlock(player, heroId) then
			self:Broadcast()
		end
	end)

	Net.server("PartyAction").OnServerEvent:Connect(function(player: Player, action: unknown, circle: unknown)
		if typeof(action) ~= "string" then
			return
		end
		local now = os.clock()
		if now - (self._lastAction[player] or 0) < Skyhold.ActionGap then
			return
		end
		self._lastAction[player] = now
		if self._members[player] and self:_act(player, action, circle, now) then
			self:Broadcast()
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < STEP_EVERY then
			return
		end
		acc = 0
		local ok, err = pcall(function()
			self:_step()
		end)
		if not ok then
			warn(`[PartyService] step failed: {err}`)
		end
	end)
end

-- the world position of a circle's centre
local function circleAt(circle: number): Vector3?
	local c = Skyhold.Circles[circle]
	if not c then
		return nil
	end
	local h = SkyholdGen.heightAt(plan, c.x, c.z) or 0
	return Vector3.new(SkyholdGen.world(Skyhold, c.x, h, c.z))
end

--- Is the player standing at that circle (on the island, within reach)?
function PartyService:_near(player: Player, circle: number): boolean
	local at = circleAt(circle)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not at or not root then
		return false
	end
	local offset = root.Position - at
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= Skyhold.JoinRange and math.abs(offset.Y) < 12
end

function PartyService:_act(player: Player, action: string, circle: unknown, now: number): boolean
	local hub, uid = self._hub, player.UserId
	if self:IsInRun(player) then
		return false
	end
	if action == "leave" then
		return HubParty.leave(hub, uid) ~= nil
	elseif action == "prepare" then
		return HubParty.prepare(hub, uid, now)
	elseif action == "cancel" then
		return HubParty.cancel(hub, uid)
	elseif action == "ready" or action == "unready" then
		return HubParty.setReady(hub, uid, action == "ready", now)
	end
	if typeof(circle) ~= "number" or not self:_near(player, circle) then
		return false
	end
	if action == "solo" or action == "squad" then
		return HubParty.start(hub, uid, circle, action, now)
	elseif action == "join" then
		return HubParty.join(hub, uid, circle)
	end
	return false
end

function PartyService:_step()
	local launched = HubParty.step(self._hub, os.clock(), self._director:IsRunActive())
	if launched then
		local players = self:PlayersOf(launched)
		if #players == 0 then
			HubParty.runEnded(self._hub, launched.circle)
		else
			self.Launch:Fire(players, launched.circle)
		end
	end
	-- only a change goes out (the clients run the countdowns themselves)
	local sig = self:_signature()
	if sig ~= self._sig then
		self:Broadcast()
	end
end

function PartyService:_signature(): string
	local parts = { tostring(self._director:IsRunActive()) }
	for circle = 1, self._hub.circles do
		local p = self._hub.parties[circle]
		if p then
			local ready = 0
			for _ in p.ready do
				ready += 1
			end
			table.insert(parts, `{circle}:{p.phase}:{p.leader}:{table.concat(p.members, ",")}:{ready}`)
		end
	end
	return table.concat(parts, "|")
end

--- The players of a party, in join order (those still in the server).
function PartyService:PlayersOf(party): { Player }
	local out = {}
	for _, uid in party.members do
		local player = Players:GetPlayerByUserId(uid)
		if player then
			table.insert(out, player)
		end
	end
	return out
end

--- The run could not start after all: the party stands on its circle again.
function PartyService:LaunchFailed(circle: number)
	HubParty.runEnded(self._hub, circle)
	self:Broadcast()
end

--- The run of the party on `circle` is over: they stand on it again, unready.
function PartyService:RunEnded(circle: number)
	HubParty.runEnded(self._hub, circle)
	self:Broadcast()
end

function PartyService:IsInRun(player: Player): boolean
	local party = HubParty.partyOf(self._hub, player.UserId)
	return party ~= nil and party.phase == "run"
end

function PartyService:Broadcast()
	self._sig = self:_signature()
	local list = {}
	for _, player in self._order do
		local m = self._members[player]
		local party = HubParty.partyOf(self._hub, player.UserId)
		table.insert(list, {
			userId = player.UserId,
			name = player.DisplayName,
			hero = m.hero,
			index = m.index,
			circle = if party then party.circle else nil,
			leader = party ~= nil and party.leader == player.UserId,
			ready = party ~= nil and party.ready[player.UserId] == true,
		})
	end
	self._rosterEvent:FireAllClients({ players = list, map = self._map, max = GameConfig.MaxPlayers })
	local run = self._director:RunInfo()
	self._hubEvent:FireAllClients({
		circles = HubParty.snapshot(self._hub, os.clock()),
		run = run,
	})
end

--- Players in join order.
function PartyService:GetPlayers(): { Player }
	return table.clone(self._order)
end

function PartyService:GetHero(player: Player): string
	local m = self._members[player]
	return if m then m.hero else Roster.HeroOrder[1]
end

function PartyService:IndexOf(player: Player): number
	local m = self._members[player]
	return if m then m.index else 0
end

function PartyService:GetMap(): string
	return self._map
end

return PartyService

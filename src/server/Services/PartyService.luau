--!nonstrict
-- PartyService - owns the squad roster: who is in the server, each player's hero
-- pick and ready flag, and the host's map choice.
--
-- A server is one squad. The first player in is the host. Each player gets a
-- stable index 1..MaxPlayers, which is what goes on the wire in byte fields.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Signal = require(ReplicatedStorage.Packages.Signal)

local PartyService = Knit.CreateService({ Name = "PartyService" })

function PartyService:KnitInit()
	self._members = {} -- player -> { index, hero, ready, joined }
	self._order = {} -- players in join order
	self._map = "MossyWoods"
	self.ReadyChanged = Signal.new()
	self.MemberLeft = Signal.new()
	for _, name in Net.All do
		Net.server(name) -- every remote exists before any client asks
	end
	self._rosterEvent = Net.server("Roster")
end

function PartyService:KnitStart()
	local DataService = Knit.GetService("DataService")

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
		self._members[player] = { index = index, hero = Roster.HeroOrder[1], ready = false }
		-- no character exists in the lobby, so tell streaming where this player is looking
		local focus = Workspace:FindFirstChild("LobbyFocus")
		if not focus then
			focus = Instance.new("Part")
			focus.Name = "LobbyFocus"
			focus.Anchored = true
			focus.CanCollide = false
			focus.CanQuery = false
			focus.Transparency = 1
			focus.Size = Vector3.one
			focus.Position = Vector3.new(0, 12, 0)
			focus.Parent = Workspace
		end
		player.ReplicationFocus = focus
		table.insert(self._order, player)
		self:Broadcast()
	end

	Players.PlayerAdded:Connect(add)
	for _, player in Players:GetPlayers() do
		add(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		self._members[player] = nil
		local i = table.find(self._order, player)
		if i then
			table.remove(self._order, i)
		end
		self.MemberLeft:Fire(player)
		self:Broadcast()
	end)

	Net.server("PickHero").OnServerEvent:Connect(function(player: Player, heroId: unknown)
		local m = self._members[player]
		if not m or typeof(heroId) ~= "string" or not Roster.Heroes[heroId] then
			return
		end
		if m.ready then
			return -- unready first; a locked-in pick does not change under the squad
		end
		if not DataService:Get(player).unlocked[heroId] then
			return
		end
		m.hero = heroId
		self:Broadcast()
	end)

	Net.server("PickMap").OnServerEvent:Connect(function(player: Player, mapId: unknown)
		if player ~= self._order[1] or typeof(mapId) ~= "string" then
			return
		end
		local def = Roster.Maps[mapId]
		if not def or def.locked then
			return
		end
		self._map = mapId
		self:Broadcast()
	end)

	Net.server("SetReady").OnServerEvent:Connect(function(player: Player, ready: unknown)
		local m = self._members[player]
		if not m or typeof(ready) ~= "boolean" then
			return
		end
		if ready and not DataService:Get(player).unlocked[m.hero] then
			return
		end
		m.ready = ready
		self:Broadcast()
		self.ReadyChanged:Fire(player, ready)
	end)

	Net.server("UnlockHero").OnServerEvent:Connect(function(player: Player, heroId: unknown)
		if typeof(heroId) ~= "string" then
			return
		end
		if DataService:Unlock(player, heroId) then
			self:Broadcast()
		end
	end)
end

function PartyService:Broadcast()
	local list = {}
	for i, player in self._order do
		local m = self._members[player]
		table.insert(
			list,
			{ userId = player.UserId, name = player.DisplayName, hero = m.hero, ready = m.ready, host = i == 1, index = m.index }
		)
	end
	self._rosterEvent:FireAllClients({ players = list, map = self._map, max = GameConfig.MaxPlayers })
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

function PartyService:IsReady(player: Player): boolean
	local m = self._members[player]
	return m ~= nil and m.ready
end

function PartyService:GetMap(): string
	return self._map
end

--- True when there is at least one player and every one of them is ready.
function PartyService:AllReady(): boolean
	if #self._order == 0 then
		return false
	end
	for _, player in self._order do
		if not self._members[player].ready then
			return false
		end
	end
	return true
end

function PartyService:ClearReady()
	for _, m in self._members do
		m.ready = false
	end
	self:Broadcast()
end

return PartyService

--!nonstrict
-- StateController - the client's copy of what the server has told it: run
-- phase and clock, the squad, the local hero's state, XP and the profile, and
-- on the island hub (T6/T7) everyone's hero and the rune circles' parties.
--
-- The phase stays "Lobby" for a player on the island: run messages only ever
-- reach the party in the run (server/RunAudience).
--
-- Every other controller reads from here and listens to `Changed(key)`. Nothing
-- on the client decides any of these values; this is a mirror.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)
local SkyholdGen = require(ReplicatedStorage.Shared.Core.SkyholdGen)

local StateController = Knit.CreateController({ Name = "StateController" })

function StateController:KnitInit()
	self.Changed = Signal.new()
	self.phase = "Lobby"
	self.clock = 0
	self.stage = GameConfig.StageSeconds
	self.tier = 0
	self.paused = false
	self.kills = 0
	self.quests = {}
	self.portal = nil
	self.roster = { players = {}, map = "MossyWoods", max = GameConfig.MaxPlayers }
	self.hub = { circles = {}, run = nil } -- the rune circles' parties, and the server's run if one is on
	self.hubAt = os.clock() -- when `hub` arrived (its countdowns run from here)
	self.sky = nil -- the sky the run drew (Phase), worn while in it
	self.profile = nil
	self.me = nil
	self.squad = {}
	self.level = 1
	self.xp = 0
	self.need = 10
	self.clockAt = os.clock()
	-- the same heightfield the server simulates on
	self.map = MapGen.build(GameConfig.MapSizeStuds, GameConfig.HeightCellStuds, GameConfig.WallHeight)
	-- and the island hub's ground (T6/T7)
	self.island = SkyholdGen.build(Skyhold)
end

--- The way downhill on the ground under (x, z) (world), as MapGen.downhill:
--- the Wardwood's heightfield, or the island's while on the island.
function StateController:Downhill(x: number, z: number): (number, number, number)
	if not self:OnIsland() then
		return MapGen.downhill(self.map, x, z)
	end
	local o = Skyhold.Origin
	local lx, lz = x - o[1], z - o[3]
	local plan = self.island
	local function h(ax: number, az: number): number?
		return SkyholdGen.heightAt(plan, ax, az)
	end
	local c = 2
	local e, w, s, n = h(lx + c, lz), h(lx - c, lz), h(lx, lz + c), h(lx, lz - c)
	if not (e and w and s and n) then
		return 0, 0, 0
	end
	local gx, gz = (e - w) / (2 * c), (s - n) / (2 * c)
	local m = math.sqrt(gx * gx + gz * gz)
	if m < 1e-4 then
		return 0, 0, 0
	end
	return -gx / m, -gz / m, m
end

function StateController:HeightAt(x: number, z: number): number
	return MapGen.heightAt(self.map, x, z)
end

--- The stage clock, advanced locally between server updates so timers tick smoothly.
function StateController:Clock(): number
	if self.paused or (self.phase ~= "Playing" and self.phase ~= "Overtime") then
		return self.clock
	end
	return self.clock + (os.clock() - self.clockAt)
end

function StateController:IsLive(): boolean
	return self.phase == "Playing" or self.phase == "Overtime"
end

--- The local hero's root part, if they have one.
function StateController:Root(): BasePart?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

--- A hero's root part by squad index.
function StateController:RootOfIndex(index: number): BasePart?
	for _, entry in self.roster.players do
		if entry.index == index then
			local player = Players:GetPlayerByUserId(entry.userId)
			local character = player and player.Character
			return character and character:FindFirstChild("HumanoidRootPart")
		end
	end
	return nil
end

--- The local player's roster entry (hero, party circle, leader, ready).
function StateController:Mine()
	for _, entry in self.roster.players do
		if entry.userId == Players.LocalPlayer.UserId then
			return entry
		end
	end
	return nil
end

--- The party on rune circle `circle`, as the server last sent it, or nil.
function StateController:PartyAt(circle: number)
	for _, party in self.hub.circles do
		if party.circle == circle then
			return party
		end
	end
	return nil
end

--- Seconds left on a party's countdown, run on locally between messages.
function StateController:CountdownLeft(party): number?
	if not party or not party.seconds then
		return nil
	end
	return math.max(0, party.seconds - (os.clock() - self.hubAt))
end

--- On the island hub (not in a run)?
function StateController:OnIsland(): boolean
	return self.phase == "Lobby"
end

function StateController:MyIndex(): number
	for _, entry in self.roster.players do
		if entry.userId == Players.LocalPlayer.UserId then
			return entry.index
		end
	end
	return 0
end

function StateController:KnitStart()
	-- The game draws its own health and has no tools; the number keys belong to
	-- upgrade cards, not to a backpack.
	task.spawn(function()
		local StarterGui = game:GetService("StarterGui")
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)

	local function on(name, fn)
		local remote = Net.client(name)
		if remote then
			remote.OnClientEvent:Connect(fn)
		end
	end

	on("Phase", function(p)
		self.phase = p.phase
		self.clock = p.clock
		self.stage = p.stage
		self.tier = p.tier
		self.paused = p.paused
		self.kills = p.kills
		self.quests = p.quests
		self.portal = p.portal
		self.sky = p.sky
		self.clockAt = os.clock()
		if p.phase == "Lobby" then
			self.me = nil
			self.squad = {}
		end
		self.Changed:Fire("phase")
	end)
	on("Clock", function(clock, tier, paused, kills)
		self.clock, self.tier, self.paused, self.kills = clock, tier, paused, kills
		self.clockAt = os.clock()
		self.Changed:Fire("clock")
	end)
	on("Roster", function(roster)
		self.roster = roster
		self.Changed:Fire("roster")
	end)
	on("Hub", function(hub)
		self.hub = hub
		self.hubAt = os.clock()
		self.Changed:Fire("hub")
	end)
	on("Profile", function(profile)
		self.profile = profile
		self.Changed:Fire("profile")
	end)
	on("PlayerState", function(state)
		self.me = state
		self.Changed:Fire("me")
	end)
	on("Squad", function(squad)
		self.squad = squad
		self.Changed:Fire("squad")
	end)
	on("XP", function(level, xp, need)
		self.level, self.xp, self.need = level, xp, need
		self.Changed:Fire("xp")
	end)
end

return StateController

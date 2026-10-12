--!nonstrict
-- StateController - the client's copy of what the server has told it: run
-- phase and clock, the squad, the local hero's state, XP and the profile.
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
	self.profile = nil
	self.me = nil
	self.squad = {}
	self.level = 1
	self.xp = 0
	self.need = 10
	self.clockAt = os.clock()
	-- the same heightfield the server simulates on
	self.map = MapGen.build(GameConfig.MapSizeStuds, GameConfig.HeightCellStuds, GameConfig.WallHeight)
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

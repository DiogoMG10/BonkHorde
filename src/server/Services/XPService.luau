--!nonstrict
-- XPService - owns the squad's shared XP and level.
--
-- XP is shared so a squad levels together: whoever picks up a gem, everyone gets
-- the level, and everyone gets their own choice of upgrade.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Progress = require(ReplicatedStorage.Shared.Core.Progress)

local XPService = Knit.CreateService({ Name = "XPService" })

function XPService:KnitInit()
	self._level = 1
	self._xp = 0
	self._event = Net.server("XP")
end

function XPService:KnitStart()
	self._players = Knit.GetService("PlayerStateService")
	self._upgrades = Knit.GetService("UpgradeService")
end

function XPService:GetLevel(): number
	return self._level
end

function XPService:Need(): number
	local c = GameConfig
	return Progress.xpToNext(self._level, c.XPBase, c.XPLinear, c.XPQuadratic)
end

function XPService:Reset()
	self._level = 1
	self._xp = 0
	self:Broadcast()
end

function XPService:Broadcast()
	self._event:FireAllClients(self._level, self._xp, self:Need())
end

--- Add XP collected by `rec` (their XP Gain applies). Queues a level-up choice
--- for every player for each level gained.
function XPService:Add(amount: number, rec)
	local c = GameConfig
	local gain = amount * (if rec then rec.stats.XPGain else 1)
	local level, xp, gained = Progress.addXP(self._level, self._xp, gain, c.XPBase, c.XPLinear, c.XPQuadratic)
	self._level, self._xp = level, xp
	if gained > 0 then
		self._players:RecomputeAll() -- hero passives scale with level
		self._upgrades:QueueAll(gained)
		Net.server("Fx"):FireAllClients("LevelUp", level)
	end
	self:Broadcast()
end

return XPService

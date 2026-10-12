--!nonstrict
-- PickupService - owns XP gems, gold and powerups lying on the ground, and who
-- collected what.
--
-- Pickups are data, like the horde. Collection is a server-side range check
-- against each hero's Pickup Range; a client never claims a pickup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Progress = require(ReplicatedStorage.Shared.Core.Progress)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)

local PickupService = Knit.CreateService({ Name = "PickupService" })

local rng = Random.new()
local KIND = {}
for i, name in Roster.PickupOrder do
	KIND[name] = i
end
local MAX_ID = 4000

function PickupService:KnitInit()
	self._items = {} -- id -> { kind, value, x, z }
	self._nextId = 1
	self._gems = 0
	self._overflow = 0
	self._spawned = {}
	self._taken = {}
	self._spawnEvent = Net.server("PickupSpawn")
	self._takenEvent = Net.server("PickupTaken")
	self._fx = Net.server("Fx")
end

function PickupService:KnitStart()
	self._players = Knit.GetService("PlayerStateService")
	self._xp = Knit.GetService("XPService")
	self._director = Knit.GetService("RunDirectorService")
	self._map = Knit.GetService("MapService"):GetMap()
	Knit.GetService("EnemyService").Killed:Connect(function(info)
		self:_onKilled(info)
	end)
end

function PickupService:Clear()
	table.clear(self._items)
	table.clear(self._spawned)
	table.clear(self._taken)
	self._gems = 0
	self._overflow = 0
end

function PickupService:Drop(kind: string, x: number, z: number, value: number)
	if kind == "XPGem" and self._gems >= GameConfig.GemCap then
		self._overflow += value -- paid out with the next gem collected
		return
	end
	local id = self._nextId
	for _ = 1, MAX_ID do
		if not self._items[id] then
			break
		end
		id = id % MAX_ID + 1
	end
	self._nextId = id % MAX_ID + 1
	self._items[id] = { kind = kind, value = value, x = x, z = z }
	if kind == "XPGem" then
		self._gems += 1
	end
	table.insert(self._spawned, id)
end

function PickupService:_onKilled(info)
	local def = info.def
	local x, z = info.x, info.z
	local xp = def.xp * (if info.elite then GameConfig.EliteXP else 1)
	self:Drop("XPGem", x, z, xp)
	local killer = info.killer
	if killer then
		local echo = killer.itemIndex.EchoGem
		if echo and rng:NextNumber() < Roster.Items.EchoGem.n.chance * echo then
			self:Drop("XPGem", x + 2, z + 1, xp)
		end
	end
	local coin = Progress.coinValue(self._director:GetClock(), GameConfig.GoldMinutesPerStep)
	if info.bossKind > 0 then
		for i = 1, if info.bossKind == 2 then 14 else 6 do
			local a = i * 0.9
			self:Drop("GoldCoin", x + math.cos(a) * 5, z + math.sin(a) * 5, coin * 5)
		end
	elseif rng:NextNumber() < GameConfig.GoldDropChance or info.elite then
		self:Drop("GoldCoin", x + 1.5, z - 1, coin * (if info.elite then 6 else 1))
	end
	local chance = GameConfig.PowerupDropChance * (if killer then killer.stats.PowerupDropChance else 1)
	if info.elite then
		chance *= 8
	end
	if rng:NextNumber() < chance then
		self:DropPowerup(x - 1.5, z + 1.5)
	end
end

function PickupService:DropPowerup(x: number, z: number)
	local kinds = { "PowerupMagnet", "PowerupSnack", "PowerupFrenzy" }
	self:Drop(kinds[rng:NextInteger(1, #kinds)], x, z, 1)
end

function PickupService:_collect(id: number, item, rec, now: number)
	self._items[id] = nil
	table.insert(self._taken, id)
	table.insert(self._taken, rec.index)
	local kind = item.kind
	if kind == "XPGem" then
		self._gems -= 1
		self._xp:Add(item.value + self._overflow, rec)
		self._overflow = 0
	elseif kind == "GoldCoin" then
		for _, other in self._players:All() do
			self._players:AddGold(other, item.value)
		end
	elseif kind == "PowerupMagnet" then
		self:CollectAllGems(rec, now)
		self._fx:FireAllClients("Pickup", rec.index, "Magnet")
	elseif kind == "PowerupSnack" then
		for _, other in self._players:All() do
			self._players:Heal(other, other.stats.MaxHP * GameConfig.SnackHealFraction * other.stats.PowerupMultiplier)
		end
		self._fx:FireAllClients("Pickup", rec.index, "Snack")
	elseif kind == "PowerupFrenzy" then
		for _, other in self._players:All() do
			other.frenzyUntil = now + GameConfig.FrenzySeconds * other.stats.PowerupMultiplier
		end
		self._fx:FireAllClients("Pickup", rec.index, "Frenzy")
	end
end

--- Pull every gem on the map to one hero (magnet powerup, vacuum shrine).
function PickupService:CollectAllGems(rec, now: number)
	for id, item in self._items do
		if item.kind == "XPGem" then
			self:_collect(id, item, rec, now)
		end
	end
end

function PickupService:Step(_dt: number, now: number)
	for _, rec in self._players:All() do
		if rec.downed then
			continue
		end
		local range2 = rec.stats.PickupRange ^ 2
		local x, z = rec.x, rec.z
		for id, item in self._items do
			local dx, dz = item.x - x, item.z - z
			if dx * dx + dz * dz <= range2 then
				self:_collect(id, item, rec, now)
			end
		end
	end
	self:FlushNet()
end

local function quantise(v: number, half: number): number
	return math.clamp(math.floor((v + half) / (2 * half) * 65535 + 0.5), 0, 65535)
end

function PickupService:FlushNet()
	local half = self._map.half
	local spawned = self._spawned
	if #spawned > 0 then
		local live = {}
		for _, id in spawned do
			if self._items[id] then
				table.insert(live, id)
			end
		end
		table.clear(spawned)
		if #live > 0 then
			local b = buffer.create(#live * 8)
			for i, id in live do
				local item = self._items[id]
				local o = (i - 1) * 8
				buffer.writeu16(b, o, id)
				buffer.writeu8(b, o + 2, KIND[item.kind])
				buffer.writeu8(b, o + 3, math.clamp(item.value, 1, 255))
				buffer.writeu16(b, o + 4, quantise(item.x, half))
				buffer.writeu16(b, o + 6, quantise(item.z, half))
			end
			self._spawnEvent:FireAllClients(b)
		end
	end
	local taken = self._taken
	if #taken > 0 then
		local n = #taken / 2
		local b = buffer.create(n * 3)
		for i = 1, n do
			local o = (i - 1) * 3
			buffer.writeu16(b, o, taken[i * 2 - 1])
			buffer.writeu8(b, o + 2, taken[i * 2])
		end
		table.clear(taken)
		self._takenEvent:FireAllClients(b)
	end
end

return PickupService

--!nonstrict
-- PickupService - owns XP gems, gold and powerups lying on the ground, and who
-- collected what.
--
-- Pickups are data, like the horde. Collection is a server-side range check
-- against each hero's Pickup Range; a client never claims a pickup. A magnet
-- or a vacuum shrine starts a sweep: for VacuumSeconds the hero's reach grows
-- from their Pickup Range to the whole map, so every gem and coin is taken
-- nearest first and the XP and gold arrive with the wave the client draws.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Progress = require(ReplicatedStorage.Shared.Core.Progress)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)

local RunAudience = require(script.Parent.Parent.RunAudience)

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
	self._coins = 0
	self._goldOverflow = 0
	self._vacuums = {} -- rec -> when its sweep began
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
	table.clear(self._vacuums)
	self._gems = 0
	self._overflow = 0
	self._coins = 0
	self._goldOverflow = 0
end

function PickupService:Drop(kind: string, x: number, z: number, value: number)
	if kind == "XPGem" and self._gems >= GameConfig.GemCap then
		self._overflow += value -- paid out with the next gem collected
		return
	elseif kind == "GoldCoin" and self._coins >= GameConfig.GoldCap then
		self._goldOverflow += value -- paid out with the next coin collected
		return
	end
	local id = self._nextId
	local found = false
	for _ = 1, MAX_ID do
		if not self._items[id] then
			found = true
			break
		end
		id = id % MAX_ID + 1
	end
	if not found then
		-- every id is in use: never overwrite a pickup lying on the ground
		if kind == "XPGem" then
			self._overflow += value
		elseif kind == "GoldCoin" then
			self._goldOverflow += value
		end
		return
	end
	self._nextId = id % MAX_ID + 1
	self._items[id] = { kind = kind, value = value, x = x, z = z }
	if kind == "XPGem" then
		self._gems += 1
	elseif kind == "GoldCoin" then
		self._coins += 1
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
		self._coins -= 1
		local value = item.value + self._goldOverflow
		self._goldOverflow = 0
		for _, other in self._players:All() do
			self._players:AddGold(other, value)
		end
	elseif kind == "PowerupMagnet" then
		self:Vacuum(rec, now)
		RunAudience.fire(self._fx, "Pickup", rec.index, "Magnet")
	elseif kind == "PowerupSnack" then
		for _, other in self._players:All() do
			self._players:Heal(other, other.stats.MaxHP * GameConfig.SnackHealFraction * other.stats.PowerupMultiplier)
		end
		RunAudience.fire(self._fx, "Pickup", rec.index, "Snack")
	elseif kind == "PowerupFrenzy" then
		for _, other in self._players:All() do
			other.frenzyUntil = now + GameConfig.FrenzySeconds * other.stats.PowerupMultiplier
		end
		RunAudience.fire(self._fx, "Pickup", rec.index, "Frenzy")
	end
end

--- Pull every gem and coin on the map to one hero (magnet powerup, vacuum
--- shrine): a sweep from their feet out to the edge of the map.
function PickupService:Vacuum(rec, now: number)
	self._vacuums[rec] = now
end

local SWEEPABLE = { XPGem = true, GoldCoin = true }

function PickupService:Step(_dt: number, now: number)
	local sweep = GameConfig.VacuumSeconds
	local reachAll = GameConfig.MapSizeStuds * 1.5
	for _, rec in self._players:All() do
		local began = self._vacuums[rec]
		if rec.downed then
			self._vacuums[rec] = nil
			continue
		end
		local x, z = rec.x, rec.z
		local range = rec.stats.PickupRange
		local range2 = range * range
		local vacuum2 = -1
		if began then
			local f = math.clamp((now - began) / sweep, 0, 1)
			vacuum2 = (range + reachAll * f ^ 1.5) ^ 2
			if f >= 1 then
				self._vacuums[rec] = nil
			end
		end
		for id, item in self._items do
			local dx, dz = item.x - x, item.z - z
			local d2 = dx * dx + dz * dz
			if d2 <= range2 or (d2 <= vacuum2 and SWEEPABLE[item.kind]) then
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
			RunAudience.fire(self._spawnEvent, b)
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
		RunAudience.fire(self._takenEvent, b)
	end
end

return PickupService

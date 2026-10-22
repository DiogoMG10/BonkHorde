--!nonstrict
-- UpgradeService - owns the offers rolled for each pending level-up choice and
-- each player's banish, skip and refresh charges.
--
-- The client is sent three offers and answers with an index. The server only
-- ever applies an offer it rolled itself, so a forged choice is a no-op.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Offers = require(ReplicatedStorage.Shared.Core.Offers)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)

local UpgradeService = Knit.CreateService({ Name = "UpgradeService" })

local rng = Random.new()
local function rnd(): number
	return rng:NextNumber()
end

function UpgradeService:KnitInit()
	self._pending = {} -- rec -> count
	self._open = {} -- rec -> { id, offers, deadline }
	self._nextId = 1
	self._offersEvent = Net.server("Offers")
end

function UpgradeService:KnitStart()
	self._players = Knit.GetService("PlayerStateService")
	self._director = Knit.GetService("RunDirectorService")

	Net.server("ChooseOffer").OnServerEvent:Connect(function(player: Player, id: unknown, action: unknown, index: unknown)
		if typeof(id) ~= "number" or typeof(action) ~= "string" then
			return
		end
		local rec = self._players:Get(player)
		local open = rec and self._open[rec]
		if not open or open.id ~= id then
			return
		end
		local i = if typeof(index) == "number" then math.floor(index) else 0
		self:_choose(rec, open, action, i)
	end)
end

function UpgradeService:Reset()
	table.clear(self._pending)
	table.clear(self._open)
end

function UpgradeService:HasOpen(): boolean
	return next(self._open) ~= nil
end

--- One level-up for everyone in the run.
function UpgradeService:QueueAll(levels: number)
	for _, rec in self._players:All() do
		self:QueueFor(rec, levels)
	end
end

function UpgradeService:QueueFor(rec, levels: number)
	if rec.complete then
		-- a finished build: the level pays quietly, nothing opens
		self._players:MaxedOut(rec, levels)
		return
	end
	self._pending[rec] = (self._pending[rec] or 0) + levels
	self:_count(rec)
	self:_present(rec)
end

--- Keep the player's own count of level-ups waiting for a choice in their
--- state (PlayerState `levelUps`): the HUD's XP strip wears its rainbow for
--- exactly as long as it is above zero.
function UpgradeService:_count(rec)
	local waiting = self._pending[rec] or 0
	if rec.levelUps ~= waiting then
		rec.levelUps = waiting
		rec.dirty = true
	end
end

function UpgradeService:_roll(rec)
	local offers = Offers.levelUp(
		self._players:Loadout(rec),
		Roster.WeaponOrder,
		Roster.Weapons,
		Roster.TomeOrder,
		Roster.Tomes,
		Roster.RarityOrder,
		Roster.RarityWeights,
		Roster.RarityLuckFactor,
		Roster.RarityMultiplier,
		GameConfig.OfferCount,
		rnd
	)
	-- attach before/after values so the card can show "100% -> 120%"
	for _, offer in offers do
		for _, line in offer.lines do
			local from = 0
			if offer.kind == "weapon" then
				local entry = rec.weaponIndex[offer.id]
				from = if entry then (entry.s[line.stat] or 0) else 0
			else
				from = rec.stats[line.stat] or 0
			end
			line.from = from
			line.to = from + line.amount
		end
	end
	return offers
end

function UpgradeService:_present(rec, followUp: boolean?)
	if self._open[rec] or (self._pending[rec] or 0) <= 0 or not rec.active then
		return
	end
	local offers = self:_roll(rec)
	if #offers == 0 then
		-- nothing left to offer (every weapon and tome maxed, or banished): pay the
		-- levels out in gold instead of an empty panel
		self._players:MaxedOut(rec, self._pending[rec])
		self._pending[rec] = 0
		self:_count(rec)
		return
	end
	local solo = #self._players:All() <= 1
	-- the client locks the cards for a moment (T1); co-op gets that time back
	local lock = if followUp then GameConfig.OfferLockFollowSeconds else GameConfig.OfferLockSeconds
	local open = {
		id = self._nextId,
		offers = offers,
		lock = lock,
		deadline = if solo then math.huge else os.clock() + GameConfig.OfferChoiceSecondsCoop + lock,
	}
	self._nextId += 1
	self._open[rec] = open
	self._director:SetPause("levelup", true)
	self:_send(rec, open, solo)
end

function UpgradeService:_send(rec, open, solo: boolean)
	self._offersEvent:FireClient(rec.player, {
		id = open.id,
		offers = open.offers,
		seconds = if solo then 0 else math.max(0, open.deadline - os.clock()),
		charges = rec.charges,
		pending = self._pending[rec] or 0,
		lock = open.lock,
	})
end

function UpgradeService:_apply(rec, offer)
	local applied = true
	if offer.kind == "weapon" then
		if offer.isNew then
			self._players:GrantWeapon(rec, offer.id)
		else
			applied = self._players:UpgradeWeapon(rec, offer.id, offer.lines)
		end
	else
		applied = self._players:GrantTome(rec, offer.id, offer.lines)
	end
	if not applied then
		-- the cap was reached since the offer was rolled: never apply it twice
		self._players:MaxedOut(rec)
	end
end

-- after a banish or a refresh: a fresh hand, or (with nothing left to offer)
-- this level paid out in gold
function UpgradeService:_reroll(rec, open, solo: boolean)
	open.offers = self:_roll(rec)
	open.lock = GameConfig.OfferLockFollowSeconds
	if not solo then
		open.deadline += open.lock
	end
	rec.dirty = true
	if #open.offers == 0 then
		self._players:MaxedOut(rec)
		self:_resolve(rec)
	else
		self:_send(rec, open, solo)
	end
end

function UpgradeService:_choose(rec, open, action: string, index: number)
	local solo = #self._players:All() <= 1
	if action == "pick" then
		local offer = open.offers[index]
		if not offer then
			return
		end
		self:_apply(rec, offer)
		self:_resolve(rec)
	elseif action == "skip" then
		if rec.charges.skip <= 0 then
			return
		end
		rec.charges.skip -= 1
		self._players:AddGold(rec, GameConfig.SkipGold)
		self:_resolve(rec)
	elseif action == "banish" then
		local offer = open.offers[index]
		if not offer or rec.charges.banish <= 0 then
			return
		end
		rec.charges.banish -= 1
		rec.banished[offer.kind .. ":" .. offer.id] = true
		self._players:UpdateComplete(rec) -- banishing the last choices finishes a build too
		self:_reroll(rec, open, solo)
	elseif action == "refresh" then
		if rec.charges.refresh <= 0 then
			return
		end
		rec.charges.refresh -= 1
		self:_reroll(rec, open, solo)
	end
end

function UpgradeService:_resolve(rec)
	self._open[rec] = nil
	self._pending[rec] = math.max((self._pending[rec] or 1) - 1, 0)
	self:_count(rec)
	rec.dirty = true
	self._offersEvent:FireClient(rec.player, nil) -- close the panel
	if self._pending[rec] > 0 then
		self:_present(rec, true) -- the next card follows at once
	end
	if not self:HasOpen() then
		-- the last choice of the squad: straight back into the fight (level-ups are
		-- too frequent for a countdown; the paused-world colour eases back on its own)
		self._director:SetPause("levelup", false)
	end
end

--- Run every frame, even while paused: times out co-op choices and drops
--- choices that belong to players who left.
function UpgradeService:Step(now: number)
	for rec, open in self._open do
		if not rec.active then
			self._open[rec] = nil
			self._pending[rec] = nil
		elseif now >= open.deadline then
			-- out of time: take the first offer rather than waste the level
			self:_apply(rec, open.offers[1])
			self:_resolve(rec)
		end
	end
	if not self:HasOpen() then
		self._director:SetPause("levelup", false)
	end
end

return UpgradeService

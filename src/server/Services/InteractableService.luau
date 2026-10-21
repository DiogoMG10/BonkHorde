--!nonstrict
-- InteractableService - owns every chest, shrine, statue, vendor, pot, crate,
-- portal and tombstone placed this run: their state, per-player use and prices.
--
-- Loot is instanced per player: a chest can be opened once by each hero at that
-- hero's own price, so nobody can take a teammate's loot. The panels a player
-- sees (chest reveal, shrine reward, vendor, statue) are rolled and held here;
-- the client only ever sends back an index into what the server offered.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Offers = require(ReplicatedStorage.Shared.Core.Offers)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)

local RunAudience = require(script.Parent.Parent.RunAudience)

local InteractableService = Knit.CreateService({ Name = "InteractableService" })

local rng = Random.new()
local function rnd(): number
	return rng:NextNumber()
end

function InteractableService:KnitInit()
	self._list = {} -- id -> interactable
	self._nextId = 1
	self._panels = {} -- rec -> open panel
	self._nextPanel = 1
	self._chargeSentAt = 0
	self._portal = nil
	self._listEvent = Net.server("Interactables")
	self._stateEvent = Net.server("InteractableState")
	self._panelEvent = Net.server("Panel")
	self._toast = Net.server("Toast")
end

function InteractableService:KnitStart()
	self._players = Knit.GetService("PlayerStateService")
	self._mapService = Knit.GetService("MapService")
	self._director = Knit.GetService("RunDirectorService")
	self._enemies = Knit.GetService("EnemyService")
	self._pickups = Knit.GetService("PickupService")

	Net.server("Interact").OnServerEvent:Connect(function(player: Player, id: unknown)
		if typeof(id) ~= "number" then
			return
		end
		local rec = self._players:Get(player)
		local it = self._list[id]
		if not rec or not it or rec.downed or self._panels[rec] then
			return
		end
		local dx, dz = it.x - rec.x, it.z - rec.z
		if dx * dx + dz * dz > (GameConfig.InteractRange + 4) ^ 2 then
			return -- too far: the client asked for something it cannot reach
		end
		self:_interact(rec, it, self._director:Now())
	end)

	Net.server("PanelChoice").OnServerEvent:Connect(function(player: Player, id: unknown, action: unknown, index: unknown)
		if typeof(id) ~= "number" or typeof(action) ~= "string" then
			return
		end
		local rec = self._players:Get(player)
		local panel = rec and self._panels[rec]
		if not panel or panel.id ~= id then
			return
		end
		self:_panelChoice(rec, panel, action, if typeof(index) == "number" then math.floor(index) else 0)
	end)

	self._enemies.Killed:Connect(function(info)
		if info.tag then
			local it = self._list[info.tag]
			if it and it.kind == "ChallengeShrine" and it.remaining then
				it.remaining -= 1
				if it.remaining <= 0 then
					it.remaining = nil
					self:SpawnFreeChest(it.x + 5, it.z)
					RunAudience.fire(self._toast, "Challenge cleared", "A free chest appears.")
				end
			end
		end
		if info.bossKind == 1 then
			self:SpawnFreeChest(info.x, info.z)
		end
	end)

	self._players.Downed:Connect(function(rec)
		local it = self:_add("Tombstone", rec.x, rec.z)
		it.owner = rec
		it.progress = 0
		rec.tombId = it.id
		RunAudience.fire(self._stateEvent, it.id, "spawn", { kind = it.kind, x = it.x, y = it.y, z = it.z, owner = rec.player.UserId })
	end)
	self._players.Revived:Connect(function(rec)
		self:_removeTomb(rec)
	end)
end

-- ------------------------------------------------------------------ placement

function InteractableService:_add(kind: string, x: number, z: number)
	local it = { id = self._nextId, kind = kind, x = x, y = self._mapService:HeightAt(x, z), z = z, state = "idle", used = {} }
	self._nextId += 1
	self._list[it.id] = it
	return it
end

function InteractableService:Clear()
	table.clear(self._list)
	table.clear(self._panels)
	self._portal = nil
	RunAudience.fire(self._listEvent, {})
end

--- Place this run's interactables on randomly chosen anchors.
function InteractableService:Place()
	self:Clear()
	local anchors = table.clone(self._mapService:GetAnchors())
	for i = #anchors, 2, -1 do
		local j = rng:NextInteger(1, i)
		anchors[i], anchors[j] = anchors[j], anchors[i]
	end
	local taken = {}
	local function take(minD: number, maxD: number)
		for i, a in anchors do
			if a.d >= minD and a.d <= maxD then
				local clear = true
				for _, t in taken do
					if (t.x - a.x) ^ 2 + (t.z - a.z) ^ 2 < 22 * 22 then
						clear = false
						break
					end
				end
				if clear then
					table.remove(anchors, i)
					table.insert(taken, a)
					return a
				end
			end
		end
		return nil
	end

	local portalAt = take(GameConfig.BossPortalMinDistance, GameConfig.BossPortalMaxDistance) or take(150, math.huge)
	if portalAt then
		self._portal = self:_add("BossPortal", portalAt.x, portalAt.z)
	end
	-- the two placements the first minute relies on
	local firstChest = take(25, 60)
	if firstChest then
		self:_add("Chest", firstChest.x, firstChest.z)
	end
	local firstShrine = take(40, 120)
	if firstShrine then
		self:_add("ChargeShrine", firstShrine.x, firstShrine.z)
	end

	local counts = table.clone(GameConfig.InteractablesPerRun)
	counts.Chest -= 1
	counts.ChargeShrine -= 1
	for _, kind in { "Chest", "ChargeShrine", "GreedShrine", "ChallengeShrine", "VacuumShrine", "SmugStatue", "DodgyDan" } do
		for _ = 1, counts[kind] or 0 do
			local a = take(45, math.huge)
			if a then
				self:_add(kind, a.x, a.z)
			end
		end
	end
	-- breakables go in small clusters wherever there is room, including near other things
	local function cluster(kind: string, total: number, per: number)
		local placed = 0
		for _, a in self._mapService:GetAnchors() do
			if placed >= total then
				break
			end
			if rng:NextNumber() < 0.35 then
				for k = 1, per do
					local angle = k * 2.1 + a.x
					local x, z = a.x + math.cos(angle) * 6, a.z + math.sin(angle) * 6
					if self._mapService:IsReachable(x, z) then
						self:_add(kind, x, z)
						placed += 1
					end
				end
			end
		end
	end
	cluster("Pot", counts.Pot or 0, 3)
	cluster("Crate", counts.Crate or 0, 2)
	self:SendAll()
end

function InteractableService:_public(it)
	return { id = it.id, kind = it.kind, x = it.x, y = it.y, z = it.z, state = it.state, free = it.free }
end

--- Send the full list to the run's players.
function InteractableService:SendAll()
	local list = {}
	for _, it in self._list do
		table.insert(list, self:_public(it))
	end
	RunAudience.fire(self._listEvent, list)
end

function InteractableService:SpawnFreeChest(x: number, z: number)
	local it = self:_add("Chest", x, z)
	it.free = true
	RunAudience.fire(self._stateEvent, it.id, "spawn", { kind = it.kind, x = it.x, y = it.y, z = it.z, free = true })
end

function InteractableService:GetPortal()
	return self._portal
end

function InteractableService:SetState(it, state: string, data)
	it.state = state
	RunAudience.fire(self._stateEvent, it.id, state, data)
end

function InteractableService:_removeTomb(rec)
	local it = rec.tombId and self._list[rec.tombId]
	if it then
		self._list[it.id] = nil
		RunAudience.fire(self._stateEvent, it.id, "gone")
	end
	rec.tombId = nil
end

-- ------------------------------------------------------------------ panels

function InteractableService:_open(rec, kind: string, it, data)
	local solo = #self._players:All() <= 1
	-- the client locks the panel for a moment (T1); co-op gets that time back
	local lock = GameConfig.PanelLockSeconds[kind] or GameConfig.PanelLockAgainSeconds
	local panel = {
		id = self._nextPanel,
		kind = kind,
		it = it,
		data = data,
		lock = lock,
		deadline = if solo then math.huge else os.clock() + GameConfig.PanelSecondsCoop + lock,
	}
	self._nextPanel += 1
	self._panels[rec] = panel
	if solo then
		self._director:SetPause("panel", true)
	else
		rec.inMenu = true -- untouchable while choosing; the squad keeps fighting
	end
	self:_sendPanel(rec, panel)
end

function InteractableService:_sendPanel(rec, panel)
	self._panelEvent:FireClient(rec.player, {
		id = panel.id,
		kind = panel.kind,
		data = panel.data,
		charges = rec.charges,
		gold = rec.gold,
		seconds = if panel.deadline == math.huge then 0 else math.max(0, panel.deadline - os.clock()),
		lock = panel.lock,
	})
end

-- a panel that changed under the player (a purchase, a reroll) locks again, and
-- co-op's clock gets that back; a refused answer changes nothing and adds nothing
function InteractableService:_relock(panel)
	panel.lock = GameConfig.PanelLockAgainSeconds
	panel.deadline += panel.lock
end

function InteractableService:_close(rec)
	self._panels[rec] = nil
	rec.inMenu = false
	rec.dirty = true
	self._panelEvent:FireClient(rec.player, nil)
	if next(self._panels) == nil then
		self._director:SetPause("panel", false)
	end
end

function InteractableService:_rollItem(rec, forceRarity: string?): string?
	local ids = Offers.items(
		Roster.ItemOrder,
		Roster.Items,
		Roster.ItemRarityOrder,
		Roster.ItemRarityWeights,
		self._players:ItemBlocked(rec),
		rec.stats.Luck,
		1,
		forceRarity,
		rnd
	)
	return ids[1]
end

function InteractableService:_panelChoice(rec, panel, action: string, index: number)
	local data = panel.data
	if panel.kind == "chest" then
		if action == "take" then
			if not self._players:GrantItem(rec, data.item) then
				self._players:MaxedOut(rec)
			end
			self:_close(rec)
		elseif action == "banish" and rec.charges.banish > 0 and not data.rerolled then
			rec.charges.banish -= 1
			rec.banished["item:" .. data.item] = true
			local again = self:_rollItem(rec, nil)
			if again then
				data.item, data.rarity, data.rerolled = again, Roster.Items[again].rarity, true
				self:_relock(panel)
				self:_sendPanel(rec, panel)
			else
				self:_close(rec)
			end
		end
	elseif panel.kind == "shrine" then
		local pick = data.offers[index]
		if action == "pick" and pick then
			self._players:AddBonus(rec, pick.stat, pick.amount)
		end
		self:_close(rec)
	elseif panel.kind == "statue" then
		local id = data.items[index]
		if action == "pick" and id and not self._players:GrantItem(rec, id) then
			self._players:MaxedOut(rec)
		end
		self:_close(rec)
	elseif panel.kind == "shop" then
		local entry = data.stock[index]
		if action == "buy" and entry and not entry.sold then
			panel.lock = 0
			if not self._players:CanTakeItem(rec, entry.item) then
				-- maxed since Dan stocked it: never take gold for nothing
				self._toast:FireClient(rec.player, "Maxed out", "You can't carry any more of those.")
			elseif self._players:Spend(rec, entry.price) then
				entry.sold = true
				self._players:GrantItem(rec, entry.item)
				self:_relock(panel)
			end
			self:_sendPanel(rec, panel)
		else
			self:_close(rec)
		end
	else
		self:_close(rec)
	end
end

-- ------------------------------------------------------------------ interaction

function InteractableService:_interact(rec, it, now: number)
	local kind = it.kind
	local uid = rec.player.UserId
	if kind == "Chest" then
		if it.used[uid] then
			return
		end
		local price = if it.free then 0 else self._players:ChestPrice(rec)
		local keys = rec.itemIndex.SkeletonKey
		if price > 0 and keys and rng:NextNumber() < Roster.Items.SkeletonKey.n.chance * keys then
			price = 0
			self._toast:FireClient(rec.player, "Skeleton Key", "This one is on the house.")
		end
		if rec.gold < price then
			self._toast:FireClient(rec.player, "Not enough gold", `This chest costs {price}.`)
			return
		end
		-- roll before paying: with every item maxed the chest is free and pays out
		local item = self:_rollItem(rec, nil)
		if not item then
			it.used[uid] = true
			self._stateEvent:FireClient(rec.player, it.id, "used")
			self._players:MaxedOut(rec)
			self._toast:FireClient(rec.player, "Maxed out", "Nothing left you can carry. Have some gold.")
			return
		end
		self._players:Spend(rec, price)
		it.used[uid] = true
		if not it.free then
			rec.chestsOpened += 1
		end
		self._stateEvent:FireClient(rec.player, it.id, "used")
		self:_open(rec, "chest", it, { item = item, rarity = Roster.Items[item].rarity })
	elseif kind == "SmugStatue" then
		if it.used[uid] then
			return
		end
		it.used[uid] = true
		self._stateEvent:FireClient(rec.player, it.id, "used")
		local ids = Offers.items(
			Roster.ItemOrder,
			Roster.Items,
			Roster.ItemRarityOrder,
			Roster.ItemRarityWeights,
			self._players:ItemBlocked(rec),
			rec.stats.Luck,
			3,
			nil,
			rnd
		)
		self:_open(rec, "statue", it, { items = ids })
	elseif kind == "DodgyDan" then
		it.stock = it.stock or {}
		local stock = it.stock[uid]
		if not stock then
			stock = {}
			local ids = Offers.items(
				Roster.ItemOrder,
				Roster.Items,
				Roster.ItemRarityOrder,
				Roster.ItemRarityWeights,
				self._players:ItemBlocked(rec),
				rec.stats.Luck + 1.5,
				3,
				nil,
				rnd
			)
			for _, id in ids do
				local base = GameConfig.ShopPrice[Roster.Items[id].rarity] or 100
				table.insert(stock, { item = id, price = math.floor(base * (0.95 + rng:NextNumber() * 0.1)), sold = false })
			end
			it.stock[uid] = stock
		end
		self:_open(rec, "shop", it, { stock = stock })
	elseif kind == "GreedShrine" then
		it.uses = (it.uses or 0) + 1
		self._director:AddDifficulty(GameConfig.GreedDifficultyStep)
		self._players:AddBonus(rec, "GoldGain", GameConfig.GreedGoldStep)
		RunAudience.fire(
			self._toast,
			"Greed",
			`+{math.floor(GameConfig.GreedDifficultyStep * 100)}% Difficulty. {rec.player.DisplayName} gets richer.`
		)
		if it.uses >= 5 then
			self:SetState(it, "used")
		end
	elseif kind == "ChallengeShrine" then
		if it.state ~= "idle" then
			return
		end
		self:SetState(it, "used")
		local spawned = 0
		for i = 1, GameConfig.ChallengeEliteCount do
			local name = Roster.ChallengeTypes[rng:NextInteger(1, #Roster.ChallengeTypes)]
			local angle = i / GameConfig.ChallengeEliteCount * math.pi * 2
			local x, z = it.x + math.cos(angle) * 18, it.z + math.sin(angle) * 18
			if self._enemies:Spawn(name, x, z, { elite = true, tag = it.id, hpMult = 1 + self._director:GetClock() / 240 }) then
				spawned += 1
			end
		end
		it.remaining = if spawned > 0 then spawned else nil
		RunAudience.fire(self._toast, "Challenge", "Clear the elites for a free chest.")
	elseif kind == "VacuumShrine" then
		if it.state ~= "idle" then
			return
		end
		self:SetState(it, "used")
		self._pickups:Vacuum(rec, now)
		RunAudience.fire(Net.server("Fx"), "Pickup", rec.index, "Magnet")
	elseif kind == "BossPortal" then
		self._director:PortalUsed(it)
	end
end

-- ------------------------------------------------------------------ the tick

function InteractableService:Step(dt: number, now: number)
	local recs = self._players:All()
	local sendCharge = now >= self._chargeSentAt
	if sendCharge then
		self._chargeSentAt = now + 0.2
	end

	for id, it in self._list do
		local kind = it.kind
		if kind == "ChargeShrine" and it.state ~= "used" then
			local inside = {}
			local speed = 1
			for _, rec in recs do
				if not rec.downed and (rec.x - it.x) ^ 2 + (rec.z - it.z) ^ 2 <= GameConfig.ChargeShrineRadius ^ 2 then
					table.insert(inside, rec)
					local wrench = rec.itemIndex.ShrineWrench
					if wrench then
						speed = math.max(speed, 1 + Roster.Items.ShrineWrench.n.speed * wrench)
					end
				end
			end
			if #inside > 0 then
				it.progress = (it.progress or 0) + dt * speed
				if it.progress >= GameConfig.ChargeShrineSeconds then
					self:SetState(it, "used")
					for _, rec in inside do
						if not self._panels[rec] then
							local wrench = rec.itemIndex.ShrineWrench or 0
							local picks = Offers.shrine(
								Roster.ShrineBoosts,
								Roster.RarityOrder,
								Roster.RarityWeights,
								Roster.RarityLuckFactor,
								Roster.RarityMultiplier,
								rec.stats.Luck,
								Roster.Items.ShrineWrench.n.bonus * wrench,
								3,
								rnd
							)
							local offers = {}
							for _, pick in picks do
								table.insert(
									offers,
									{ stat = Roster.ShrineBoosts[pick.index].stat, amount = pick.amount, rarity = pick.rarity }
								)
							end
							self:_open(rec, "shrine", it, { offers = offers })
						end
					end
				elseif sendCharge then
					it.state = "charging"
					RunAudience.fire(self._stateEvent, id, "charging", it.progress / GameConfig.ChargeShrineSeconds)
				end
			elseif (it.progress or 0) > 0 then
				-- stepping out of the dome loses the charge
				it.progress = 0
				self:SetState(it, "idle")
			end
		elseif (kind == "Pot" or kind == "Crate") and it.state == "idle" then
			for _, rec in recs do
				if not rec.downed and (rec.x - it.x) ^ 2 + (rec.z - it.z) ^ 2 <= 25 then
					self:SetState(it, "broken")
					if kind == "Pot" then
						if rng:NextNumber() < 0.5 then
							self._pickups:Drop("GoldCoin", it.x, it.z, GameConfig.PotGold)
						else
							self._pickups:Drop("XPGem", it.x, it.z, GameConfig.PotXP)
						end
					else
						self._pickups:Drop("GoldCoin", it.x, it.z, GameConfig.PotGold)
						if rng:NextNumber() < GameConfig.CratePowerupChance then
							self._pickups:DropPowerup(it.x + 1, it.z + 1)
						end
					end
					break
				end
			end
		elseif kind == "Tombstone" then
			local owner = it.owner
			if not owner or not owner.active or not owner.downed then
				self._list[id] = nil
				RunAudience.fire(self._stateEvent, id, "gone")
			else
				local helping = false
				for _, rec in recs do
					if rec ~= owner and not rec.downed and (rec.x - it.x) ^ 2 + (rec.z - it.z) ^ 2 <= GameConfig.ReviveRadius ^ 2 then
						helping = true
						break
					end
				end
				if helping then
					it.progress += dt
					if it.progress >= GameConfig.ReviveSeconds then
						self._players:Revive(owner)
					elseif sendCharge then
						RunAudience.fire(self._stateEvent, id, "charging", it.progress / GameConfig.ReviveSeconds)
					end
				elseif it.progress > 0 then
					it.progress = math.max(0, it.progress - dt * 2)
				end
			end
		elseif kind == "BossPortal" and it.state == "idle" then
			for _, rec in recs do
				if (rec.x - it.x) ^ 2 + (rec.z - it.z) ^ 2 <= GameConfig.PortalRevealDistance ^ 2 then
					self:SetState(it, "found")
					self._director:PortalFound()
					break
				end
			end
		end
	end
end

--- Run every frame, even while paused: times out co-op panels and drops panels
--- whose owner left.
function InteractableService:StepPanels(now: number)
	for rec, panel in self._panels do
		if not rec.active then
			self._panels[rec] = nil
		elseif now >= panel.deadline then
			-- never lose a chest to the timer
			if panel.kind == "chest" and not self._players:GrantItem(rec, panel.data.item) then
				self._players:MaxedOut(rec)
			end
			self:_close(rec)
		end
	end
	if next(self._panels) == nil then
		self._director:SetPause("panel", false)
	end
end

return InteractableService

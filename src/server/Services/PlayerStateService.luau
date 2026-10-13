--!nonstrict
-- PlayerStateService - owns each player's run state: HP, shield, gold, downed
-- flag, weapons, tomes, items and the resolved stat block.
--
-- Everything else asks this service; nothing else writes a player's numbers.
-- Roblox's own Humanoid health is not used: a hero's HP lives here, so a hit is
-- one server-side rule (Shared.Core.Damage) and not two systems disagreeing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Damage = require(ReplicatedStorage.Shared.Core.Damage)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local PrimaryTrigger = require(ReplicatedStorage.Shared.Core.PrimaryTrigger)
local Progress = require(ReplicatedStorage.Shared.Core.Progress)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Stats = require(ReplicatedStorage.Shared.Core.Stats)

local PlayerStateService = Knit.CreateService({ Name = "PlayerStateService" })

local rng = Random.new()

function PlayerStateService:KnitInit()
	self._recs = {} -- player -> record
	self._list = {} -- active records, stable order
	self._flushAt = 0
	self._squadAt = 0
	self.Downed = Signal.new()
	self.Revived = Signal.new()
	self._stateEvent = Net.server("PlayerState")
	self._squadEvent = Net.server("Squad")
	self._hurtEvent = Net.server("Hurt")
	self._toastEvent = Net.server("Toast")
	Players.CharacterAutoLoads = false
end

function PlayerStateService:KnitStart()
	self._party = Knit.GetService("PartyService")
	self._map = Knit.GetService("MapService")
	self._enemies = Knit.GetService("EnemyService")
	self._xp = Knit.GetService("XPService")
	self._director = Knit.GetService("RunDirectorService")
	Players.PlayerRemoving:Connect(function(player)
		self:_remove(player)
	end)
end

-- ------------------------------------------------------------------ records

local function newRecord(player: Player, index: number, heroId: string)
	return {
		player = player,
		index = index,
		hero = heroId,
		heroDef = Roster.Heroes[heroId],
		bonus = {},
		stats = {},
		hp = 100,
		shield = 0,
		lastHitAt = -100,
		invulnUntil = 0,
		downed = false,
		inMenu = false,
		active = true,
		gold = 0,
		kills = 0,
		damage = 0,
		chestsOpened = 0,
		weapons = {},
		weaponIndex = {},
		primary = nil, -- the weapon in slot 1: the hero's own, whatever its type
		manual = false, -- true when that weapon waits for the attack button
		input = PrimaryTrigger.new(),
		tomes = {},
		tomeIndex = {},
		items = {},
		itemIndex = {},
		banished = {},
		charges = { banish = GameConfig.BanishCharges, skip = GameConfig.SkipCharges, refresh = GameConfig.RefreshCharges },
		x = 0,
		y = 0,
		z = 0,
		fx = 0,
		fz = -1,
		speed = 0,
		groundY = 0,
		frenzyUntil = 0,
		hitCounter = 0,
		mirrorAt = 0,
		travel = 0,
		stillFor = 0,
		nightAt = 0,
		greed = 0,
		dirty = true,
	}
end

function PlayerStateService:Get(player: Player)
	return self._recs[player]
end

--- Every player in the run, downed or not.
function PlayerStateService:All()
	return self._list
end

--- How many players are in the run and standing.
function PlayerStateService:AliveCount(): number
	local n = 0
	for _, rec in self._list do
		if not rec.downed then
			n += 1
		end
	end
	return n
end

function PlayerStateService:ItemCount(rec, id: string): number
	return rec.itemIndex[id] or 0
end

-- ------------------------------------------------------------------ run lifecycle

function PlayerStateService:BeginRun(players: { Player })
	self:EndRun()
	for _, player in players do
		self:_join(player, false)
	end
end

--- Add one player to a run already in progress.
function PlayerStateService:JoinRun(player: Player)
	if not self._recs[player] then
		self:_join(player, true)
	end
end

function PlayerStateService:_join(player: Player, late: boolean)
	local index = self._party:IndexOf(player)
	local rec = newRecord(player, index, self._party:GetHero(player))
	self._recs[player] = rec
	table.insert(self._list, rec)
	self:GrantWeapon(rec, rec.heroDef.weapon)
	-- primary is a matter of slot, not of weapon type: the same weapon picked up
	-- later by another hero is an ordinary automatic one
	rec.primary = rec.weapons[1]
	rec.manual = GameConfig.ManualPrimaryHeroes[rec.hero] == true
	self:Recompute(rec)
	rec.hp = rec.stats.MaxHP
	rec.shield = rec.stats.Shield
	task.spawn(function()
		self:_spawnCharacter(rec, late)
	end)
end

function PlayerStateService:_spawnCharacter(rec, late: boolean)
	local player = rec.player
	local ok, err = pcall(function()
		player.ReplicationFocus = nil -- follow the hero from here on
		player:LoadCharacter()
	end)
	if not ok then
		warn(`[PlayerStateService] LoadCharacter failed for {player.Name}: {err}`)
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not humanoid or not root then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.UseJumpPower = false
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local health = character:FindFirstChild("Health")
	if health then
		health:Destroy() -- Roblox's regen script; HP lives in this service
	end
	local okDress, errDress = pcall(function()
		self:_dress(rec, character, humanoid, root)
	end)
	if not okDress then
		warn(`[PlayerStateService] hero dressing failed, playing as the avatar: {errDress}`)
	end
	local at = self._map:SpawnPoint(rec.index)
	if late then
		-- drop in beside whoever is still standing
		for _, other in self._list do
			if other ~= rec and not other.downed then
				at = Vector3.new(other.x + 4, other.y + 3, other.z + 4)
				break
			end
		end
	end
	character:PivotTo(CFrame.new(at))
	rec.x, rec.y, rec.z = at.X, at.Y, at.Z
	self:_applyMovement(rec)
end

-- which avatar limb each piece of a hero model rides on, so the avatar's own
-- animations move the hero
local HERO_LIMB = {
	Body = "UpperTorso",
	Head = "Head",
	ArmL = "LeftUpperArm",
	ArmR = "RightUpperArm",
	LegL = "LeftUpperLeg",
	LegR = "RightUpperLeg",
}

-- Turn the player's avatar into the chosen hero: hide the avatar, then weld each
-- piece of ReplicatedStorage.Assets.Heroes.Hero<Id> to the matching limb, and
-- the starting weapon to the right hand. Without a hero model the avatar stays.
function PlayerStateService:_dress(rec, character: Model, humanoid: Humanoid, root: BasePart)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Heroes") and assets.Heroes:FindFirstChild("Hero" .. rec.hero)
	if not template then
		return
	end
	humanoid:RemoveAccessories()
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
		elseif d:IsA("Decal") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("CharacterMesh") then
			d:Destroy()
		end
	end

	local hero = template:Clone()
	local _, size = hero:GetBoundingBox()
	hero:ScaleTo(5.4 / math.max(size.Y, 0.1))
	local _, scaled = hero:GetBoundingBox()
	-- stand the model where the avatar stands: feet on the floor under the root
	local feet = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	hero:PivotTo(CFrame.new(root.Position.X, feet + scaled.Y / 2, root.Position.Z) * root.CFrame.Rotation)
	for _, part in hero:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "Root" then
			local limb = character:FindFirstChild(HERO_LIMB[part.Name] or "UpperTorso") or root
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local weld = Instance.new("Weld")
			weld.Part0 = limb
			weld.Part1 = part
			weld.C0 = limb.CFrame:ToObjectSpace(part.CFrame)
			weld.Parent = part
			part.Parent = character
		end
	end
	hero:Destroy()

	local weaponTemplate = assets:FindFirstChild("Weapons") and assets.Weapons:FindFirstChild("Weapon" .. rec.heroDef.weapon)
	local hand = character:FindFirstChild("RightHand")
	local mesh = weaponTemplate and weaponTemplate:FindFirstChild("Body")
	if hand and mesh then
		local weapon = mesh:Clone()
		weapon.Name = "HeldWeapon"
		weapon.Anchored = false
		weapon.CanCollide = false
		weapon.CanQuery = false
		weapon.CanTouch = false
		weapon.Massless = true
		local weld = Instance.new("Weld")
		weld.Part0 = hand
		weld.Part1 = weapon
		-- gripped a third of the way up, pointing forward and up out of the fist
		weld.C0 = CFrame.new(0, -0.2, -weapon.Size.Y * 0.3) * CFrame.Angles(math.rad(-90), 0, 0)
		weld.Parent = weapon
		weapon.Parent = character
	end
end

function PlayerStateService:EndRun()
	for _, rec in self._list do
		rec.active = false
		local character = rec.player.Character
		if character then
			character:Destroy()
			rec.player.Character = nil
			rec.player.ReplicationFocus = Workspace:FindFirstChild("LobbyFocus") -- keep the clearing streamed in behind the menu
		end
	end
	table.clear(self._list)
	table.clear(self._recs)
end

function PlayerStateService:_remove(player: Player)
	local rec = self._recs[player]
	if not rec then
		return
	end
	rec.active = false
	self._recs[player] = nil
	local i = table.find(self._list, rec)
	if i then
		table.remove(self._list, i)
	end
end

-- ------------------------------------------------------------------ stats

function PlayerStateService:Recompute(rec)
	local level = self._xp:GetLevel()
	local passive = rec.heroDef.passive
	local old = rec.stats
	rec.stats = Stats.compute(Roster.Stats, rec.heroDef.base, passive.stat, passive.perLevel, level, rec.bonus)
	-- gaining max HP or shield also gives the points, so a Health Tome is felt at once
	if old.MaxHP and rec.stats.MaxHP > old.MaxHP then
		rec.hp += rec.stats.MaxHP - old.MaxHP
	end
	if old.Shield and rec.stats.Shield > old.Shield then
		rec.shield += rec.stats.Shield - old.Shield
	end
	rec.hp = math.min(rec.hp, rec.stats.MaxHP)
	rec.shield = math.min(rec.shield, rec.stats.Shield)
	rec.dirty = true
	self:_applyMovement(rec)
end

function PlayerStateService:RecomputeAll()
	for _, rec in self._list do
		self:Recompute(rec)
	end
end

function PlayerStateService:_applyMovement(rec)
	local character = rec.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local frozen = rec.downed or rec.frozen
	local speed = if frozen then 0 else GameConfig.PlayerWalkSpeed * rec.stats.MoveSpeed
	character:SetAttribute("BaseSpeed", speed)
	character:SetAttribute("ExtraJumps", if frozen then 0 else math.floor(rec.stats.ExtraJumps))
	character:SetAttribute("Downed", rec.downed)
	humanoid.WalkSpeed = speed
	humanoid.JumpHeight = if frozen then 0 else rec.stats.JumpHeight
end

--- Freeze or release every hero in place (level-up pause, intro, results).
function PlayerStateService:SetFrozen(frozen: boolean)
	for _, rec in self._list do
		rec.frozen = frozen
		self:_applyMovement(rec)
		local character = rec.player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = frozen
		end
	end
end

function PlayerStateService:AddBonus(rec, stat: string, amount: number)
	Stats.add(rec.bonus, stat, amount)
	self:Recompute(rec)
end

-- ------------------------------------------------------------------ loadout

function PlayerStateService:GrantWeapon(rec, id: string)
	if rec.weaponIndex[id] then
		return
	end
	local def = Roster.Weapons[id]
	local entry = { id = id, level = 1, s = table.clone(def.base), cd = 0.4 }
	rec.weaponIndex[id] = entry
	table.insert(rec.weapons, entry)
	rec.dirty = true
end

function PlayerStateService:UpgradeWeapon(rec, id: string, lines)
	local entry = rec.weaponIndex[id]
	if not entry then
		return
	end
	entry.level += 1
	for _, line in lines do
		entry.s[line.stat] = (entry.s[line.stat] or 0) + line.amount
	end
	rec.dirty = true
end

function PlayerStateService:GrantTome(rec, id: string, lines)
	local entry = rec.tomeIndex[id]
	if not entry then
		entry = { id = id, level = 0 }
		rec.tomeIndex[id] = entry
		table.insert(rec.tomes, entry)
	end
	entry.level += 1
	for _, line in lines do
		Stats.add(rec.bonus, line.stat, line.amount)
	end
	self:Recompute(rec)
end

function PlayerStateService:GrantItem(rec, id: string)
	local def = Roster.Items[id]
	if not def then
		return
	end
	if rec.itemIndex[id] then
		rec.itemIndex[id] += 1
		for _, entry in rec.items do
			if entry.id == id then
				entry.count += 1
			end
		end
	else
		rec.itemIndex[id] = 1
		table.insert(rec.items, { id = id, count = 1 })
	end
	if def.stats then
		for stat, amount in def.stats do
			Stats.add(rec.bonus, stat, amount)
		end
	end
	self:Recompute(rec)
end

function PlayerStateService:RemoveItem(rec, id: string)
	local count = rec.itemIndex[id]
	if not count then
		return
	end
	rec.itemIndex[id] = if count > 1 then count - 1 else nil
	for i, entry in rec.items do
		if entry.id == id then
			entry.count -= 1
			if entry.count <= 0 then
				table.remove(rec.items, i)
			end
			break
		end
	end
	rec.dirty = true
end

--- The loadout shape Shared.Core.Offers wants.
function PlayerStateService:Loadout(rec)
	local weapons, tomes = {}, {}
	for _, w in rec.weapons do
		weapons[w.id] = w.level
	end
	for _, t in rec.tomes do
		tomes[t.id] = t.level
	end
	return {
		weapons = weapons,
		tomes = tomes,
		banished = rec.banished,
		luck = rec.stats.Luck,
		weaponSlots = GameConfig.WeaponSlots,
		tomeSlots = GameConfig.TomeSlots,
	}
end

-- ------------------------------------------------------------------ gold, health

function PlayerStateService:AddGold(rec, amount: number)
	if amount <= 0 then
		return
	end
	rec.gold += math.max(1, math.floor(amount * rec.stats.GoldGain + 0.5))
	rec.dirty = true
end

function PlayerStateService:Spend(rec, amount: number): boolean
	if rec.gold < amount then
		return false
	end
	rec.gold -= amount
	rec.dirty = true
	return true
end

function PlayerStateService:ChestPrice(rec): number
	local c = GameConfig
	return Progress.chestPrice(rec.chestsOpened, c.ChestPriceBase, c.ChestPriceLinear, c.ChestPriceQuadratic)
end

function PlayerStateService:Heal(rec, amount: number)
	if rec.downed or amount <= 0 then
		return
	end
	local before = rec.hp
	rec.hp = math.min(rec.hp + amount, rec.stats.MaxHP)
	if rec.hp ~= before then
		rec.dirty = true
	end
end

--- Damage from the horde. `sourceSlot` is the enemy that dealt it, if any.
function PlayerStateService:Hurt(rec, amount: number, sourceSlot: number?, now: number)
	if rec.downed or not rec.active or rec.inMenu or rec.frozen or now < rec.invulnUntil then
		return
	end
	local stats = rec.stats
	local landed, dodged = Damage.mitigate(amount, stats.Armor, stats.Evasion, rng:NextNumber())
	if dodged then
		self._hurtEvent:FireClient(rec.player, 0, true, false)
		return
	end
	local hp, shield, broke = Damage.applyToPlayer(rec.hp, rec.shield, landed)
	rec.hp, rec.shield = hp, shield
	rec.lastHitAt = now
	rec.invulnUntil = now + GameConfig.InvulnAfterHit
	rec.dirty = true

	if stats.Thorns > 0 and sourceSlot then
		self._enemies:Damage(sourceSlot, stats.Thorns, rec, 0, true)
	end
	local mirrors = rec.itemIndex.PanicMirror
	if mirrors and now >= rec.mirrorAt then
		local n = Roster.Items.PanicMirror.n
		rec.mirrorAt = now + n.cooldown
		rec.invulnUntil = now + n.invuln
		self._enemies:DamageCircle(rec.x, rec.z, n.radius, landed * n.mult * mirrors, rec, 0, true)
		Net.server("Fx"):FireAllClients("Burst", rec.x, rec.y, rec.z, n.radius, "mirror")
	end

	if rec.hp <= 0 then
		if rec.itemIndex.SecondWindClock then
			local n = Roster.Items.SecondWindClock.n
			self:RemoveItem(rec, "SecondWindClock")
			rec.hp = math.max(1, stats.MaxHP * n.hp)
			rec.invulnUntil = now + 1.5
			self._enemies:FreezeAll(n.freeze, now)
			self._toastEvent:FireClient(rec.player, "Second Wind", "The clock breaks. Everything stops.")
		else
			self:_down(rec)
		end
	end
	self._hurtEvent:FireClient(rec.player, landed, false, broke)
end

function PlayerStateService:_down(rec)
	rec.downed = true
	rec.hp = 0
	rec.shield = 0
	rec.dirty = true
	self:_applyMovement(rec)
	self.Downed:Fire(rec)
end

function PlayerStateService:Revive(rec)
	if not rec.downed then
		return
	end
	rec.downed = false
	rec.hp = math.max(1, rec.stats.MaxHP * GameConfig.ReviveHPFraction)
	rec.invulnUntil = self._director:Now() + 2
	rec.dirty = true
	self:_applyMovement(rec)
	self.Revived:Fire(rec)
end

-- ------------------------------------------------------------------ tick

--- Called by the run director every simulation tick while the run is live.
function PlayerStateService:Step(dt: number, now: number)
	for _, rec in self._list do
		local character = rec.player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local p = root.Position
			if p.Y < -40 then
				-- fell out of the world: put them back at spawn rather than lose the run
				local at = self._map:SpawnPoint(rec.index)
				character:PivotTo(CFrame.new(at))
				p = at
			end
			local moved = math.sqrt((p.X - rec.x) ^ 2 + (p.Z - rec.z) ^ 2)
			rec.x, rec.y, rec.z = p.X, p.Y, p.Z
			rec.speed = moved / dt
			local look = root.CFrame.LookVector
			local m = math.sqrt(look.X * look.X + look.Z * look.Z)
			if m > 0.01 then
				rec.fx, rec.fz = look.X / m, look.Z / m
			end
			rec.groundY = self._map:HeightAt(p.X, p.Z)

			if not rec.downed then
				local sneakers = rec.itemIndex.GildedSneakers
				if sneakers and moved < 30 then
					rec.travel += moved
					local per = Roster.Items.GildedSneakers.n.studs
					if rec.travel >= per then
						local coins = math.floor(rec.travel / per)
						rec.travel -= coins * per
						self:AddGold(rec, coins * sneakers)
					end
				end
				rec.stillFor = if rec.speed < 1 then rec.stillFor + dt else 0
				local campfire = rec.itemIndex.PocketCampfire
				if campfire and rec.stillFor >= Roster.Items.PocketCampfire.n.still then
					self:Heal(rec, Roster.Items.PocketCampfire.n.hps * campfire * dt)
				end
			end
		end

		if not rec.downed then
			local stats = rec.stats
			if rec.hp < stats.MaxHP and stats.HPRegen > 0 then
				rec.hp = math.min(rec.hp + stats.HPRegen / 60 * dt, stats.MaxHP)
				rec.dirty = true
			end
			if rec.shield < stats.Shield and now - rec.lastHitAt >= GameConfig.ShieldRegenDelay then
				rec.shield = math.min(rec.shield + stats.Shield * GameConfig.ShieldRegenPerSecond * dt, stats.Shield)
				rec.dirty = true
			end
		end
	end
	-- the send throttle is real time: it also runs while the run is paused
	self:Flush(os.clock())
end

--- Send dirty player state (at most 5 Hz) and the squad vitals (4 Hz).
function PlayerStateService:Flush(now: number)
	if now >= self._flushAt then
		self._flushAt = now + 0.2
		for _, rec in self._list do
			if rec.dirty then
				rec.dirty = false
				self:Push(rec)
			end
		end
	end
	if now >= self._squadAt then
		self._squadAt = now + 0.25
		local squad = {}
		for _, rec in self._list do
			table.insert(squad, {
				userId = rec.player.UserId,
				index = rec.index,
				hero = rec.hero,
				hp = math.ceil(rec.hp),
				maxHp = math.floor(rec.stats.MaxHP),
				shield = math.floor(rec.shield),
				maxShield = math.floor(rec.stats.Shield),
				downed = rec.downed,
			})
		end
		self._squadEvent:FireAllClients(squad)
	end
end

function PlayerStateService:Push(rec)
	local weapons = {}
	for _, w in rec.weapons do
		table.insert(weapons, { id = w.id, level = w.level, s = w.s, primary = rec.manual and w == rec.primary })
	end
	self._stateEvent:FireClient(rec.player, {
		hero = rec.hero,
		hp = rec.hp,
		maxHp = rec.stats.MaxHP,
		shield = rec.shield,
		maxShield = rec.stats.Shield,
		gold = rec.gold,
		downed = rec.downed,
		kills = rec.kills,
		weapons = weapons,
		tomes = rec.tomes,
		items = rec.items,
		stats = rec.stats,
		charges = rec.charges,
		chestPrice = self:ChestPrice(rec),
	})
end

return PlayerStateService

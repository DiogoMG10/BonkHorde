--!nonstrict
-- BossService - owns boss and miniboss entities, their attack timelines, the
-- telegraphs that warn of them and the thorns they throw.
--
-- A boss is an enemy slot in EnemyService with an attack script here. Every
-- attack is telegraphed: the client is told where and when, the damage lands
-- on the server when the delay is up.
--
-- It also answers camping (Core/Contact): a hero who stays up a tree or on a
-- roof, out of every regular enemy's reach, with enemies waiting below, gets
-- the same kind of telegraphed root strike, drawn at their height.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Contact = require(ReplicatedStorage.Shared.Core.Contact)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)

local BossService = Knit.CreateService({ Name = "BossService" })

local rng = Random.new()
local P_THORN = 5

function BossService:KnitInit()
	self._bosses = {} -- slot -> { type, name, timers }
	self._pending = {} -- telegraphed attacks waiting to land
	self._thorns = {}
	self._camp = {} -- rec -> Contact.CampState
	self._nextThorn = 61000
	self._barsAt = 0
	self._bossEvent = Net.server("Boss")
	self._telegraph = Net.server("Telegraph")
	self._proj = Net.server("Proj")
	self._banner = Net.server("Banner")
end

function BossService:KnitStart()
	self._enemies = Knit.GetService("EnemyService")
	self._players = Knit.GetService("PlayerStateService")
	self._director = Knit.GetService("RunDirectorService")
	self._enemies.Killed:Connect(function(info)
		if info.bossKind > 0 then
			self._bosses[info.slot] = nil
			self._barsAt = 0
			if info.bossKind == 2 then
				self._director:BossDied()
			else
				self._director:MinibossDied()
			end
		end
	end)
end

function BossService:Reset()
	table.clear(self._bosses)
	table.clear(self._pending)
	table.clear(self._thorns)
	table.clear(self._camp)
	self._bossEvent:FireAllClients({})
end

function BossService:AnyStageBoss(): boolean
	for _, b in self._bosses do
		if b.stage then
			return true
		end
	end
	return false
end

function BossService:AnyMiniboss(): boolean
	for _, b in self._bosses do
		if not b.stage then
			return true
		end
	end
	return false
end

local function scale(players: number, difficulty: number): number
	return (1 + GameConfig.BossHPPerExtraPlayer * math.max(players - 1, 0)) * (1 + difficulty)
end

function BossService:_register(slot: number, typeName: string, now: number)
	local def = Roster.Enemies[typeName]
	self._bosses[slot] =
		{ type = typeName, name = def.name, stage = def.boss == "stage", a = now + 3, b = now + 6, c = now + 9, d = now + 5 }
	self._barsAt = 0
end

--- Spawn the stage boss at the portal.
function BossService:SummonStage(x: number, z: number, now: number)
	local recs = self._players:All()
	local slot = self._enemies:Spawn(Roster.StageBoss, x, z, { hpMult = scale(#recs, self._director:GetDifficulty()) })
	if slot then
		self:_register(slot, Roster.StageBoss, now)
		self._banner:FireAllClients(Roster.Enemies[Roster.StageBoss].name, "boss")
	end
end

--- Spawn a miniboss on the ring around a random standing hero.
function BossService:SpawnMini(typeName: string, now: number)
	local standing = {}
	for _, rec in self._players:All() do
		if not rec.downed then
			table.insert(standing, rec)
		end
	end
	if #standing == 0 then
		return
	end
	local rec = standing[rng:NextInteger(1, #standing)]
	local hpMult = scale(#self._players:All(), self._director:GetDifficulty()) * (1 + self._director:GetClock() / 300)
	local slot = self._enemies:SpawnNear(rec, typeName, { hpMult = hpMult }, 55, 80)
	if slot then
		self:_register(slot, typeName, now)
		self._banner:FireAllClients(Roster.Enemies[typeName].name, "miniboss")
	end
end

-- Warn now, land later. `y` draws the warning at that height (a hero up a
-- tree) instead of on the ground; the hit itself is the same circle.
function BossService:_strike(x: number, z: number, radius: number, delay: number, damage: number, kind: string, now: number, y: number?)
	table.insert(self._pending, { x = x, z = z, y = y, r = radius, at = now + delay, dmg = damage, kind = kind })
	self._telegraph:FireAllClients(x, z, radius, delay, kind, y)
end

local CAMP: Contact.Camp = { seconds = GameConfig.CampSeconds, every = GameConfig.CampEvery }

-- Heroes out of every regular enemy's reach, with enemies waiting below: after
-- CampSeconds, a root strike at their feet, telegraphed and dodged by moving.
function BossService:_camping(dt: number, now: number)
	local enemies = self._enemies
	for _, rec in self._players:All() do
		local state = self._camp[rec]
		if not state then
			state = Contact.newCamp()
			self._camp[rec] = state
		end
		if rec.downed or not rec.active or rec.frozen or rec.inMenu then
			state.elevated = 0
			continue
		end
		local feet = rec.y - (rec.rootHeight or 3)
		local high = feet - rec.groundY > GameConfig.CampHeight
		local below = if high then enemies:Nearest(rec.x, rec.z, GameConfig.CampWatchRange) else nil
		if Contact.campStep(state, CAMP, high, below ~= nil, dt, now) and below then
			local damage = enemies:ContactDamage(below) * GameConfig.CampStrikeDamage
			self:_strike(rec.x, rec.z, GameConfig.CampStrikeRadius, GameConfig.CampStrikeDelay, damage, "root", now, feet)
		end
	end
end

--- Called when a pause ends. The warning for a strike that was already on its
--- way played out on screen during the pause, so draw it again with the
--- gameplay time the strike still has left.
function BossService:Resync(now: number)
	for _, s in self._pending do
		self._telegraph:FireAllClients(s.x, s.z, s.r, math.max(s.at - now, 0.05), s.kind, s.y)
	end
end

function BossService:_throwThorn(x: number, z: number, dx: number, dz: number, damage: number)
	local id = self._nextThorn
	self._nextThorn = if id >= 65000 then 61000 else id + 1
	local thorn = { id = id, x = x, z = z, dx = dx, dz = dz, speed = 42, life = 3, dmg = damage }
	table.insert(self._thorns, thorn)
	self._proj:FireAllClients("spawn", id, P_THORN, 0, x, z, dx, dz, thorn.speed, 0, 1.6)
end

local Script = {}

function Script.OldManTimber(self, slot, b, now, x, z, dmg)
	local recs = self._players:All()
	if now >= b.a then
		b.a = now + 4.5
		-- roots erupt where each hero is standing
		for _, rec in recs do
			if not rec.downed then
				self:_strike(rec.x, rec.z, 9, 1.1, dmg, "root", now)
			end
		end
	end
	if now >= b.b then
		b.b = now + 8
		local t = self._enemies:TargetOf(slot)
		if t then
			local dx, dz = t.x - x, t.z - z
			local m = math.max(math.sqrt(dx * dx + dz * dz), 0.05)
			dx, dz = dx / m, dz / m
			for k = -3, 3 do
				local a = k * 0.16
				local c, s = math.cos(a), math.sin(a)
				self:_throwThorn(x, z, dx * c - dz * s, dx * s + dz * c, dmg * 0.6)
			end
		end
	end
	if now >= b.c then
		b.c = now + 14
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			self._enemies:Spawn("Twiglet", x + math.cos(a) * 14, z + math.sin(a) * 14, { hpMult = 1 + self._director:GetClock() / 300 })
		end
	end
	local hp, maxHp = self._enemies:Health(slot)
	if hp < maxHp * 0.5 and now >= b.d then
		b.d = now + 8
		self:_strike(x, z, 30, 1.4, dmg * 1.2, "stomp", now)
	end
end

function Script.BoulderBro(self, slot, b, now, x, z, dmg)
	if now >= b.a then
		b.a = now + 5.5
		self:_strike(x, z, 16, 1.0, dmg, "slam", now)
	end
	if now >= b.b then
		b.b = now + 7
		local t = self._enemies:TargetOf(slot)
		if t then
			self:_strike(t.x, t.z, 8, 1.3, dmg * 0.8, "rock", now)
		end
	end
end

function Script.Hamlet(self, slot, b, now, x, z, dmg)
	if now >= b.a then
		b.a = now + 6.5
		local t = self._enemies:TargetOf(slot)
		if t then
			local dx, dz = t.x - x, t.z - z
			local m = math.max(math.sqrt(dx * dx + dz * dz), 0.05)
			self._enemies:Dash(slot, dx / m, dz / m, 1.2, now)
			self._telegraph:FireAllClients(x, z, 6, 0.5, "charge")
		end
	end
	if now >= b.b then
		b.b = now + 9
		self:_strike(x, z, 18, 1.2, dmg, "slam", now)
	end
end

function BossService:Step(dt: number, now: number)
	local enemies = self._enemies
	local players = self._players
	for slot, b in self._bosses do
		if not enemies:IsAlive(slot) then
			self._bosses[slot] = nil
			continue
		end
		local x, _, z = enemies:Pos(slot)
		local run = Script[b.type]
		if run then
			local dmg = Roster.Enemies[b.type].dmg * GameConfig.EnemyDamageScale
			local ok, err = pcall(run, self, slot, b, now, x, z, dmg)
			if not ok then
				warn(`[BossService] {b.type} failed: {err}`)
			end
		end
	end

	self:_camping(dt, now)

	local pending = self._pending
	for i = #pending, 1, -1 do
		local s = pending[i]
		if now >= s.at then
			table.remove(pending, i)
			for _, rec in players:All() do
				if not rec.downed and (rec.x - s.x) ^ 2 + (rec.z - s.z) ^ 2 <= s.r * s.r then
					-- a ground shock is jumped; a root or a rock is not
					local airborne = rec.y - rec.groundY > 6.5
					-- a strike aimed at a height (anti-camping) only reaches that height
					local level = not s.y
						or Contact.inStrikeBand(rec.y - (rec.rootHeight or 3), s.y, GameConfig.CampStrikeBelow, GameConfig.CampStrikeAbove)
					if level and not (airborne and (s.kind == "stomp" or s.kind == "slam")) then
						players:Hurt(rec, s.dmg, nil, now)
					end
				end
			end
		end
	end

	local thorns = self._thorns
	for i = #thorns, 1, -1 do
		local t = thorns[i]
		t.life -= dt
		t.x += t.dx * t.speed * dt
		t.z += t.dz * t.speed * dt
		local done = t.life <= 0
		if not done then
			for _, rec in players:All() do
				if not rec.downed and (rec.x - t.x) ^ 2 + (rec.z - t.z) ^ 2 <= 9 and rec.y - rec.groundY < 7 then
					players:Hurt(rec, t.dmg, nil, now)
					done = true
					break
				end
			end
		end
		if done then
			table.remove(thorns, i)
			self._proj:FireAllClients("end", t.id, t.x, t.z, 0)
		end
	end

	if now >= self._barsAt then
		self._barsAt = now + 0.25
		local bars = {}
		for slot, b in self._bosses do
			local hp, maxHp = enemies:Health(slot)
			table.insert(bars, { slot = slot, name = b.name, hp = math.max(hp, 0), maxHp = maxHp, stage = b.stage })
		end
		if #bars > 0 or self._hadBars then
			self._bossEvent:FireAllClients(bars)
		end
		self._hadBars = #bars > 0
	end
end

return BossService

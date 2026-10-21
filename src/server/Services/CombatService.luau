--!nonstrict
-- CombatService - owns weapon cooldown timers, projectiles, lingering zones and
-- hit resolution: all damage dealt to enemies.
--
-- Weapons fire on their own. Each weapon `kind` in the roster is one behaviour
-- here. Clients are told what fired and draw it; they never decide a hit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Damage = require(ReplicatedStorage.Shared.Core.Damage)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)
local Net = require(ReplicatedStorage.Shared.Net)
local PrimaryTrigger = require(ReplicatedStorage.Shared.Core.PrimaryTrigger)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local RunState = require(ReplicatedStorage.Shared.Core.RunState)

local RunAudience = require(script.Parent.Parent.RunAudience)

local CombatService = Knit.CreateService({ Name = "CombatService" })

local rng = Random.new()
local EMPTY = {}
local ITEMS = Roster.Items

-- projectile kinds on the wire
local P_FIREBALL, P_BONE, P_NANA, P_ROCKET = 1, 2, 3, 4

function CombatService:KnitInit()
	self._projs = {}
	self._zones = {}
	self._nextProj = 1
	self._out = {}
	self._fx = Net.server("Fx")
	self._proj = Net.server("Proj")
end

function CombatService:KnitStart()
	self._enemies = Knit.GetService("EnemyService")
	self._players = Knit.GetService("PlayerStateService")
	self._xp = Knit.GetService("XPService")
	self._director = Knit.GetService("RunDirectorService")
	self._map = Knit.GetService("MapService"):GetMap()

	-- The attack button. The client reports a state (held or not, and where it
	-- is aiming); this only records it. Whether and when the weapon fires is
	-- decided in Step, on the server's own cooldown.
	local pitchLow, pitchHigh = math.rad(GameConfig.CameraPitchMin), math.rad(GameConfig.CameraPitchMax)
	Net.server("PrimaryInput").OnServerEvent:Connect(function(player: Player, held: unknown, yaw: unknown, pitch: unknown)
		local rec = self._players:Get(player)
		if not rec or not rec.manual then
			return
		end
		local ok, isHeld, aim, aimPitch = PrimaryTrigger.parse(held, yaw, pitch, pitchLow, pitchHigh)
		if not ok then
			return
		end
		local input = rec.input
		local real = os.clock()
		if not PrimaryTrigger.allow(input, real, GameConfig.PrimaryInputRate, GameConfig.PrimaryInputBurst, not isHeld) then
			return
		end
		if not isHeld then
			PrimaryTrigger.release(input, real)
		elseif
			rec.downed
			or rec.frozen
			or not rec.active
			or self._director:IsPaused()
			or not RunState.isLive(self._director:GetPhase())
		then
			PrimaryTrigger.clear(input) -- not a moment anyone can attack in
		else
			PrimaryTrigger.press(input, aim, self._director:Now(), real, aimPitch)
		end
	end)
end

--- Drop every held attack button and remembered click (a pause began).
function CombatService:ReleaseInputs()
	for _, rec in self._players:All() do
		PrimaryTrigger.clear(rec.input)
	end
end

function CombatService:Reset()
	table.clear(self._projs)
	table.clear(self._zones)
end

-- ------------------------------------------------------------------ helpers

local function stackChance(chance: number, count: number): number
	return 1 - (1 - chance) ^ count
end

local function rotate(dx: number, dz: number, angle: number): (number, number)
	local c, s = math.cos(angle), math.sin(angle)
	return dx * c - dz * s, dx * s + dz * c
end

local function shots(rec, w): number
	local c = (w.s.ProjectileCount or 1) + rec.stats.ProjectileCount
	local whole = math.floor(c)
	if rng:NextNumber() < c - whole then
		whole += 1
	end
	return math.clamp(whole, 1, GameConfig.MaxShotsPerFire)
end

local function sizeOf(rec, w): number
	return (w.s.Size or 1) * rec.stats.Size
end

-- Unit direction from a hero towards the nearest enemy, or where they face.
function CombatService:_aim(rec, range: number): (number, number, number?)
	local slot = self._enemies:Nearest(rec.x, rec.z, range)
	if slot then
		local x, _, z = self._enemies:Pos(slot)
		local dx, dz = x - rec.x, z - rec.z
		local m = math.sqrt(dx * dx + dz * dz)
		if m > 0.05 then
			return dx / m, dz / m, slot
		end
	end
	return rec.fx, rec.fz, nil
end

--- One weapon hit on one enemy: crits, item procs, status, knockback.
--- `w` may be nil for a proc. Returns true if the enemy died.
function CombatService:_hit(rec, w, slot: number, base: number, now: number, isProc: boolean, dirx: number?, dirz: number?): boolean
	local enemies = self._enemies
	if not enemies:IsAlive(slot) then
		return false
	end
	local stats = rec.stats
	local s = if w then w.s else EMPTY
	local items = rec.itemIndex

	local mult = stats.Damage
	if enemies:IsTough(slot) then
		mult *= stats.DamageToElites
	end
	if items.CrackedGoggles then
		local missing = (1 - rec.hp / stats.MaxHP) * 100
		mult *= 1 + missing * ITEMS.CrackedGoggles.n.perPercent * items.CrackedGoggles
	end
	if now < rec.frenzyUntil then
		mult *= 1 + GameConfig.FrenzyBonus
	end
	local megaChance = if items.ColossalFork then stackChance(ITEMS.ColossalFork.n.chance, items.ColossalFork) else 0
	local amount, crit = Damage.roll(
		base,
		mult,
		stats.CritChance + (s.CritChance or 0),
		stats.CritDamage + (s.CritDamage or 0),
		megaChance,
		ITEMS.ColossalFork.n.mult,
		rng:NextNumber(),
		rng:NextNumber()
	)
	local flags = crit
	local freezeChance = stats.FreezeChance + (s.Freeze or 0)
	if items.BigIceCube and rng:NextNumber() < stackChance(ITEMS.BigIceCube.n.chance, items.BigIceCube) then
		amount *= 1 + ITEMS.BigIceCube.n.mult
		flags += 8
		freezeChance += ITEMS.BigIceCube.n.freeze
	end

	local x, _, z = enemies:Pos(slot)
	local killed = enemies:Damage(slot, amount, rec, flags)
	if not killed then
		if dirx and (s.Knockback or 0) > 0 then
			enemies:Knock(slot, dirx, dirz, s.Knockback * stats.Knockback * 0.5)
		end
		-- never a certainty, or a ring of frost becomes a cage nothing escapes
		if freezeChance > 0 and rng:NextNumber() < math.min(freezeChance, GameConfig.FreezeChanceMax) then
			enemies:Freeze(slot, s.FreezeSeconds or 1.5, now)
		end
		if items.StinkyCheese and rng:NextNumber() < ITEMS.StinkyCheese.n.chance then
			local n = ITEMS.StinkyCheese.n
			enemies:Poison(slot, amount * n.dps * items.StinkyCheese, n.seconds, rec, now)
		end
	end
	if stats.Lifesteal > 0 then
		self._players:Lifesteal(rec, math.min(amount * stats.Lifesteal, 4))
	end

	if not isProc then
		rec.hitCounter += 1
		if items.StaticMitts and rec.hitCounter % ITEMS.StaticMitts.n.every == 0 then
			local n = ITEMS.StaticMitts.n
			enemies:DamageCircle(x, z, n.radius, amount * n.mult * items.StaticMitts, rec, 0)
			RunAudience.fire(self._fx, "Bolt", x, z, n.radius)
		end
		if items.VolatileMeatball and rng:NextNumber() < stackChance(ITEMS.VolatileMeatball.n.chance, items.VolatileMeatball) then
			local n = ITEMS.VolatileMeatball.n
			enemies:DamageCircle(x, z, n.radius, amount * n.mult, rec, 0)
			RunAudience.fire(self._fx, "Burst", x, 0, z, n.radius, "meatball")
		end
	end
	return killed
end

-- Hit everything in a circle with a weapon. Returns how many were hit. With a
-- height `y` (a blast in the air), only bodies within `r` of that height count.
function CombatService:_blast(rec, w, x: number, z: number, r: number, base: number, now: number, y: number?): number
	local out = self._out
	local n = self._enemies:Query(x, z, r, out)
	local hitSlots = table.clone(out)
	for i = 1, n do
		local slot = hitSlots[i]
		local ex, ground, ez = self._enemies:Pos(slot)
		if y and not PrimaryTrigger.touchHeight(y, r, ground, self._enemies:HeightOf(slot)) then
			continue
		end
		local dx, dz = ex - x, ez - z
		local m = math.sqrt(dx * dx + dz * dz)
		if m > 0.05 then
			self:_hit(rec, w, slot, base, now, false, dx / m, dz / m)
		else
			self:_hit(rec, w, slot, base, now, false, nil, nil)
		end
	end
	return n
end

function CombatService:_spawnProj(p)
	if #self._projs >= GameConfig.MaxProjectiles then
		return -- the sky is full: this one is never fired (nor sent)
	end
	p.id = self._nextProj
	self._nextProj = self._nextProj % 60000 + 1
	table.insert(self._projs, p)
	-- y and dy only for a shot that flies at a height of its own (a hand-aimed fireball)
	RunAudience.fire(self._proj, "spawn", p.id, p.kind, p.rec.index, p.x, p.z, p.dx, p.dz, p.speed, p.a or 0, p.b or 0, p.y, p.dy)
end

function CombatService:_endProj(p, boom: number)
	p.dead = true
	RunAudience.fire(self._proj, "end", p.id, p.x, p.z, boom, p.y)
end

-- ------------------------------------------------------------------ weapon kinds

local Fire = {}

-- `aim` is only passed for a hand-fired primary: { dx, dz, pitch? }, the
-- direction the player chose (Auto-Trigger passes one without a pitch).
-- Without it the weapon aims itself, as every automatic one does.
function Fire.Arc(self, rec, w, now, aim)
	local s = w.s
	local range = s.Range * sizeOf(rec, w)
	local half = math.cos(math.rad(s.Arc / 2))
	local ax, az
	if aim then
		ax, az = aim.dx, aim.dz
	else
		ax, az = self:_aim(rec, range + 8)
	end
	local swings = shots(rec, w)
	local out = {}
	for k = 1, swings do
		-- first swing forward, second behind, then the sides
		local offset = if k == 1 then 0 elseif k == 2 then math.pi elseif k % 2 == 1 then math.pi / 2 else -math.pi / 2
		local dx, dz = rotate(ax, az, offset)
		local n = self._enemies:Query(rec.x, rec.z, range, out)
		local slots = table.clone(out)
		for i = 1, n do
			local slot = slots[i]
			local x, _, z = self._enemies:Pos(slot)
			local vx, vz = x - rec.x, z - rec.z
			local d = math.sqrt(vx * vx + vz * vz)
			if (d < 2.5 or (vx * dx + vz * dz) / d >= half) and (not aim or self:_canTouch(rec, slot)) then
				self:_hit(rec, w, slot, s.Damage, now, false, dx, dz)
			end
		end
		RunAudience.fire(self._fx, "Slash", rec.index, rec.x, rec.y, rec.z, dx, dz, range, s.Arc)
	end
end

function Fire.Fireball(self, rec, w, _now, aim)
	local s = w.s
	local out = {}
	local count = shots(rec, w)
	local found = if aim then 0 else self._enemies:NearestN(rec.x, rec.z, s.Range, count, out)
	local speed = s.Speed * (s.ProjectileSpeed or 1) * rec.stats.ProjectileSpeed
	local pitch = aim and aim.pitch
	for k = 1, count do
		local dx, dz = rec.fx, rec.fz
		local y, dy = nil, nil
		if aim then
			-- the first straight down the aim, extra ones fanned out either side of it
			local fan = math.ceil((k - 1) / 2) * 0.35 * (if k % 2 == 0 then 1 else -1)
			dx, dz = rotate(aim.dx, aim.dz, fan)
			if pitch then
				-- a real 3D shot: from the camera's focus above the hero, along the
				-- camera's look, so it flies exactly under the crosshair
				local level = math.cos(pitch)
				dx, dz = dx * level, dz * level
				y, dy = rec.y + GameConfig.CameraHeight, math.sin(pitch)
			end
		elseif found > 0 then
			local x, _, z = self._enemies:Pos(out[(k - 1) % found + 1])
			local vx, vz = x - rec.x, z - rec.z
			local m = math.sqrt(vx * vx + vz * vz)
			if m > 0.05 then
				dx, dz = vx / m, vz / m
			end
		end
		if not aim and k > found then
			dx, dz = rotate(dx, dz, (k - found) * 0.35 * (if k % 2 == 0 then 1 else -1))
		end
		self:_spawnProj({
			kind = P_FIREBALL,
			rec = rec,
			w = w,
			x = rec.x,
			y = y,
			z = rec.z,
			dx = dx,
			dy = dy,
			dz = dz,
			speed = speed,
			life = s.Range / speed,
			hitR = 1.8,
			boom = s.Radius * sizeOf(rec, w),
			b = s.Radius * sizeOf(rec, w),
		})
	end
end

function Fire.Aura(self, rec, w, now)
	local radius = w.s.Range * sizeOf(rec, w)
	self:_blast(rec, w, rec.x, rec.z, radius, w.s.Damage, now)
	RunAudience.fire(self._fx, "Frost", rec.index, radius, (w.s.Duration or 1) * rec.stats.Duration * 0.4)
end

function Fire.Lightning(self, rec, w, now)
	local s = w.s
	local enemies = self._enemies
	local out = {}
	local n = enemies:Query(rec.x, rec.z, s.Range, out)
	if n == 0 then
		return
	end
	local pool = table.clone(out)
	local radius = s.Radius * sizeOf(rec, w)
	local bounces = math.floor((s.ProjectileBounces or 0) + rec.stats.ProjectileBounces)
	for _ = 1, math.min(shots(rec, w), n) do
		local slot = table.remove(pool, rng:NextInteger(1, #pool))
		local struck = {}
		for _ = 0, bounces do
			if not slot or not enemies:IsAlive(slot) then
				break
			end
			struck[slot] = true
			local x, _, z = enemies:Pos(slot)
			self:_blast(rec, w, x, z, radius, s.Damage, now)
			RunAudience.fire(self._fx, "Bolt", x, z, radius)
			slot = enemies:Nearest(x, z, 24, struck)
		end
	end
end

function Fire.Bounce(self, rec, w, _now)
	local s = w.s
	local out = {}
	local count = shots(rec, w)
	local found = self._enemies:NearestN(rec.x, rec.z, s.Range, count, out)
	if found == 0 then
		return
	end
	local speed = s.Speed * (s.ProjectileSpeed or 1) * rec.stats.ProjectileSpeed
	for k = 1, count do
		local slot = out[(k - 1) % found + 1]
		local x, _, z = self._enemies:Pos(slot)
		local vx, vz = x - rec.x, z - rec.z
		local m = math.max(math.sqrt(vx * vx + vz * vz), 0.05)
		self:_spawnProj({
			kind = P_BONE,
			rec = rec,
			w = w,
			x = rec.x,
			z = rec.z,
			dx = vx / m,
			dz = vz / m,
			speed = speed,
			life = 3.5,
			hitR = s.Radius,
			target = slot,
			bounces = math.floor((s.ProjectileBounces or 0) + rec.stats.ProjectileBounces),
			seen = {},
			a = slot,
		})
	end
end

function Fire.Boomerang(self, rec, w, _now)
	local s = w.s
	local ax, az = self:_aim(rec, s.Range)
	local count = shots(rec, w)
	local speed = s.Speed * (s.ProjectileSpeed or 1) * rec.stats.ProjectileSpeed
	for k = 1, count do
		local spread = (k - (count + 1) / 2) * 0.4
		local dx, dz = rotate(ax, az, spread)
		self:_spawnProj({
			kind = P_NANA,
			rec = rec,
			w = w,
			x = rec.x,
			z = rec.z,
			dx = dx,
			dz = dz,
			speed = speed,
			life = 6,
			hitR = s.Radius * sizeOf(rec, w),
			range = s.Range,
			travelled = 0,
			back = false,
			seen = {},
			a = s.Range,
			b = s.Radius * sizeOf(rec, w),
		})
	end
end

function Fire.Linger(self, rec, w, now)
	local s = w.s
	local out = {}
	local count = shots(rec, w)
	local found = self._enemies:NearestN(rec.x, rec.z, s.Range, count, out)
	local radius = s.Radius * sizeOf(rec, w)
	local duration = s.Duration * rec.stats.Duration
	for k = 1, count do
		local tx, tz
		if found > 0 then
			local x, _, z = self._enemies:Pos(out[(k - 1) % found + 1])
			tx, tz = x + (k - 1) * 1.5, z
		else
			local dx, dz = rotate(rec.fx, rec.fz, (k - 1) * 0.6)
			tx, tz = rec.x + dx * 16, rec.z + dz * 16
		end
		table.insert(
			self._zones,
			{ rec = rec, w = w, x = tx, z = tz, r = radius, next = now + 0.35, tick = s.Tick, untilAt = now + 0.35 + duration }
		)
		RunAudience.fire(self._fx, "Axe", rec.index, rec.x, rec.z, tx, tz, radius, duration)
	end
end

function Fire.Homing(self, rec, w, _now)
	local s = w.s
	local out = {}
	local n = self._enemies:Query(rec.x, rec.z, s.Range, out)
	if n == 0 then
		return
	end
	local pool = table.clone(out)
	local speed = s.Speed * (s.ProjectileSpeed or 1) * rec.stats.ProjectileSpeed
	for _ = 1, shots(rec, w) do
		local slot = if #pool > 0 then table.remove(pool, rng:NextInteger(1, #pool)) else out[rng:NextInteger(1, n)]
		local dx, dz = rotate(rec.fx, rec.fz, (rng:NextNumber() - 0.5) * 2.4)
		self:_spawnProj({
			kind = P_ROCKET,
			rec = rec,
			w = w,
			x = rec.x,
			z = rec.z,
			dx = dx,
			dz = dz,
			speed = speed,
			life = 4.5,
			hitR = 2.2,
			target = slot,
			boom = s.Radius * sizeOf(rec, w),
			a = slot,
			b = s.Radius * sizeOf(rec, w),
		})
	end
end

-- ------------------------------------------------------------------ the primary weapon

-- Can a swing made at the hero's own height touch this enemy? Its body has to
-- be within vertical reach, and the ground must not stand between the two:
-- an enemy up on a ledge or down over a cliff edge is not hit through it.
-- Scenery props are not checked; a melee sweep passes a tree trunk.
function CombatService:_canTouch(rec, slot: number): boolean
	local x, ground, z = self._enemies:Pos(slot)
	local at = PrimaryTrigger.touchHeight(rec.y, GameConfig.PrimaryReachY, ground, self._enemies:HeightOf(slot))
	if not at then
		return false
	end
	-- aim a little above the ground the enemy stands on, so its own slope does not hide it
	return MapGen.sightClear(self._map, rec.x, rec.y, rec.z, x, math.max(at, ground + 1), z)
end

-- Auto-Trigger: would the primary reach anything right now? Returns whether it
-- should fire, and the aim to fire with. A nil aim lets the weapon aim itself,
-- exactly as it did when it was automatic.
function CombatService:_autoTarget(rec, w): (boolean, any)
	local enemies = self._enemies
	local s = w.s
	local kind = Roster.Weapons[w.id].kind
	if kind == "Aura" then
		return enemies:Nearest(rec.x, rec.z, s.Range * sizeOf(rec, w)) ~= nil, nil
	elseif kind ~= "Arc" then
		return enemies:Nearest(rec.x, rec.z, s.Range) ~= nil, nil
	end
	-- a melee swing: the nearest enemy it could actually touch, so the item
	-- never swings at something up a ledge that a hand-aimed swing would miss
	local out = self._out
	local n = enemies:Query(rec.x, rec.z, s.Range * sizeOf(rec, w), out)
	local bestD, ax, az = math.huge, nil, nil
	for i = 1, n do
		local slot = out[i]
		local x, _, z = enemies:Pos(slot)
		local dx, dz = x - rec.x, z - rec.z
		local d = dx * dx + dz * dz
		if d < bestD and self:_canTouch(rec, slot) then
			bestD = d
			local m = math.sqrt(d)
			if m > 0.05 then
				ax, az = dx / m, dz / m
			else
				ax, az = rec.fx, rec.fz
			end
		end
	end
	if not ax then
		return false, nil
	end
	return true, { dx = ax, dz = az }
end

-- The hero's own weapon, fired by the attack button (or, with Auto-Trigger,
-- by itself when the button is idle). Same cooldown, same attack-speed scaling
-- and the same Fire function as an automatic weapon; the only differences are
-- who decides when, and where it points.
function CombatService:_stepPrimary(rec, w, elapsed: number, now: number)
	local input = rec.input
	PrimaryTrigger.expire(input, os.clock(), GameConfig.PrimaryHeldTimeout)
	local autoAim = nil
	local auto = nil
	if rec.itemIndex.AutoTrigger then
		auto = function(): boolean
			local found, aim = self:_autoTarget(rec, w)
			autoAim = aim
			return found
		end
	end
	local left, fires, byHand = PrimaryTrigger.step(input, w.cd, elapsed, w.s.Cooldown, now, GameConfig.PrimaryClickBuffer, auto)
	w.cd = left
	if not fires then
		return
	end
	-- read by the dev status hook
	if byHand then
		rec.primarySwings = (rec.primarySwings or 0) + 1
	else
		rec.primaryAuto = (rec.primaryAuto or 0) + 1
	end
	local fire = Fire[Roster.Weapons[w.id].kind]
	if fire then
		local aim = autoAim
		if byHand then
			local dx, dz = PrimaryTrigger.direction(input.yaw)
			aim = { dx = dx, dz = dz, pitch = input.pitch }
		end
		local ok, err = pcall(fire, self, rec, w, now, aim)
		if not ok then
			warn(`[CombatService] primary {w.id} failed: {err}`)
		end
	end
end

-- ------------------------------------------------------------------ projectiles

function CombatService:_stepProj(p, dt: number, now: number)
	local enemies = self._enemies
	local rec, w = p.rec, p.w
	local s = w.s
	p.life -= dt
	local step = p.speed * dt

	if p.kind == P_FIREBALL then
		p.x += p.dx * step
		p.z += p.dz * step
		local out = self._out
		if p.y then
			-- flying at its own height: it bursts on the ground it meets, or on a
			-- body it actually passes through, not on one far above or below it
			p.y += p.dy * step
			local ground = MapGen.heightAt(self._map, p.x, p.z)
			local struck = p.y <= ground or p.life <= 0
			if not struck then
				local n = enemies:Query(p.x, p.z, p.hitR, out)
				for i = 1, n do
					local _, g, _ = enemies:Pos(out[i])
					if PrimaryTrigger.touchHeight(p.y, p.hitR, g, enemies:HeightOf(out[i])) then
						struck = true
						break
					end
				end
			end
			if struck then
				p.y = math.max(p.y, ground)
				self:_blast(rec, w, p.x, p.z, p.boom, s.Damage, now, p.y)
				self:_endProj(p, p.boom)
			end
		elseif enemies:Query(p.x, p.z, p.hitR, out) > 0 or p.life <= 0 then
			self:_blast(rec, w, p.x, p.z, p.boom, s.Damage, now)
			self:_endProj(p, p.boom)
		end
	elseif p.kind == P_BONE then
		local target = p.target
		if target and enemies:IsAlive(target) then
			local x, _, z = enemies:Pos(target)
			local vx, vz = x - p.x, z - p.z
			local m = math.sqrt(vx * vx + vz * vz)
			if m <= step + p.hitR then
				p.x, p.z = x, z
				p.seen[target] = true
				self:_hit(rec, w, target, s.Damage, now, false, p.dx, p.dz)
				local nextSlot = if p.bounces > 0 then enemies:Nearest(x, z, 40, p.seen) else nil
				if nextSlot then
					p.bounces -= 1
					p.target = nextSlot
					local nx, _, nz = enemies:Pos(nextSlot)
					local wx, wz = nx - p.x, nz - p.z
					local wm = math.max(math.sqrt(wx * wx + wz * wz), 0.05)
					p.dx, p.dz = wx / wm, wz / wm
					p.life = math.max(p.life, 1.5)
					RunAudience.fire(self._proj, "turn", p.id, p.x, p.z, p.dx, p.dz, nextSlot)
				else
					self:_endProj(p, 0)
				end
				return
			end
			p.dx, p.dz = vx / m, vz / m
		else
			-- the target died on the way: pick another without spending a bounce
			local nextSlot = enemies:Nearest(p.x, p.z, 40, p.seen)
			if nextSlot then
				p.target = nextSlot
				RunAudience.fire(self._proj, "turn", p.id, p.x, p.z, p.dx, p.dz, nextSlot)
			else
				p.target = nil
			end
		end
		p.x += p.dx * step
		p.z += p.dz * step
		if p.life <= 0 then
			self:_endProj(p, 0)
		end
	elseif p.kind == P_NANA then
		if p.back then
			local vx, vz = rec.x - p.x, rec.z - p.z
			local m = math.sqrt(vx * vx + vz * vz)
			if m < 3 + step or p.life <= 0 or not rec.active then
				self:_endProj(p, 0)
				return
			end
			p.dx, p.dz = vx / m, vz / m
		else
			p.travelled += step
			if p.travelled >= p.range then
				p.back = true
				table.clear(p.seen) -- it hits again on the way home
				RunAudience.fire(self._proj, "turn", p.id, p.x, p.z, p.dx, p.dz, -1)
			end
		end
		p.x += p.dx * step
		p.z += p.dz * step
		local out = {}
		local n = enemies:Query(p.x, p.z, p.hitR, out)
		for i = 1, n do
			local slot = out[i]
			if not p.seen[slot] then
				p.seen[slot] = true
				self:_hit(rec, w, slot, s.Damage, now, false, p.dx, p.dz)
			end
		end
	elseif p.kind == P_ROCKET then
		local target = p.target
		if not target or not enemies:IsAlive(target) then
			target = enemies:Nearest(p.x, p.z, 90)
			p.target = target
			if target then
				RunAudience.fire(self._proj, "turn", p.id, p.x, p.z, p.dx, p.dz, target)
			end
		end
		if target then
			local x, _, z = enemies:Pos(target)
			local vx, vz = x - p.x, z - p.z
			local m = math.sqrt(vx * vx + vz * vz)
			if m <= step + p.hitR then
				p.x, p.z = x, z
				self:_blast(rec, w, p.x, p.z, p.boom, s.Damage, now)
				self:_endProj(p, p.boom)
				return
			end
			-- turn towards the target at a limited rate so it arcs in
			local turn = math.min(1, 6 * dt)
			local nx, nz = p.dx + (vx / m - p.dx) * turn, p.dz + (vz / m - p.dz) * turn
			local nm = math.max(math.sqrt(nx * nx + nz * nz), 0.05)
			p.dx, p.dz = nx / nm, nz / nm
		end
		p.x += p.dx * step
		p.z += p.dz * step
		if p.life <= 0 then
			self:_blast(rec, w, p.x, p.z, p.boom, s.Damage, now)
			self:_endProj(p, p.boom)
		end
	end
end

-- ------------------------------------------------------------------ the tick

function CombatService:Step(dt: number, now: number)
	for _, rec in self._players:All() do
		if rec.downed or not rec.active then
			PrimaryTrigger.clear(rec.input) -- a fallen hero is not holding an attack
			continue
		end
		local haste = rec.stats.AttackSpeed * (if now < rec.frenzyUntil then 1 + GameConfig.FrenzyBonus else 1)
		for _, w in rec.weapons do
			if rec.manual and w == rec.primary then
				self:_stepPrimary(rec, w, dt * haste, now)
				continue
			end
			w.cd -= dt * haste
			if w.cd <= 0 then
				w.cd += w.s.Cooldown
				local fire = Fire[Roster.Weapons[w.id].kind]
				if fire then
					local ok, err = pcall(fire, self, rec, w, now)
					if not ok then
						warn(`[CombatService] {w.id} failed: {err}`)
					end
				end
			end
		end

		local lights = rec.itemIndex.Nightlight
		if lights and now >= rec.nightAt then
			local n = ITEMS.Nightlight.n
			rec.nightAt = now + n.every
			local base = (10 + self._xp:GetLevel() * 0.5) * rec.stats.Damage * n.mult * lights
			self._enemies:DamageCircle(rec.x, rec.z, n.radius, base, rec, 0)
			RunAudience.fire(self._fx, "Burst", rec.x, rec.y, rec.z, n.radius, "night")
		end
	end

	local projs = self._projs
	for i = #projs, 1, -1 do
		local p = projs[i]
		if not p.dead then
			self:_stepProj(p, dt, now)
		end
		if p.dead then
			table.remove(projs, i)
		end
	end

	local zones = self._zones
	for i = #zones, 1, -1 do
		local zone = zones[i]
		if now >= zone.untilAt then
			table.remove(zones, i)
		elseif now >= zone.next then
			zone.next = now + zone.tick
			self:_blast(zone.rec, zone.w, zone.x, zone.z, zone.r, zone.w.s.Damage, now)
		end
	end
end

return CombatService

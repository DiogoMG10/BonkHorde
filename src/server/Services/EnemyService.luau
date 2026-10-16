--!nonstrict
-- EnemyService - owns every enemy as plain data (position, HP, type, target,
-- status effects), the spawn director, and the snapshot stream to clients.
--
-- There are no enemy Instances on the server. The horde is parallel arrays
-- indexed by slot, stepped on a spatial grid over the map's heightfield, and
-- clients draw it from what this service sends. That is the only way a few
-- hundred enemies fit on Roblox.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Contact = require(ReplicatedStorage.Shared.Core.Contact)
local Grid = require(ReplicatedStorage.Shared.Core.Grid)
local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Snapshot = require(ReplicatedStorage.Shared.Core.Snapshot)
local Spawn = require(ReplicatedStorage.Shared.Core.Spawn)

local EnemyService = Knit.CreateService({ Name = "EnemyService" })

local MAX = GameConfig.EnemyHardCap + 60 -- regulars plus bosses, summons and challenge packs
local SEP = GameConfig.EnemySeparation
local rng = Random.new()

-- flags sent with a spawn
local FLAG_ELITE = 1
local FLAG_RUNNER = 2
-- reasons sent with a removal
local GONE_KILLED = 1
local GONE_CLEARED = 2

-- parallel arrays
local alive = table.create(MAX, false)
local typeId = table.create(MAX, 0)
local def = table.create(MAX, false)
local ex = table.create(MAX, 0)
local ez = table.create(MAX, 0)
local hp = table.create(MAX, 0)
local maxHp = table.create(MAX, 0)
local elite = table.create(MAX, false)
local target = table.create(MAX, false)
local retargetAt = table.create(MAX, 0)
local frozenUntil = table.create(MAX, 0)
local poisonUntil = table.create(MAX, 0)
local poisonDps = table.create(MAX, 0)
local poisonAcc = table.create(MAX, 0)
local poisonOwner = table.create(MAX, false)
local contactAt = table.create(MAX, 0)
local kbx = table.create(MAX, 0)
local kbz = table.create(MAX, 0)
local radius = table.create(MAX, 1) -- movement and spacing
local body = table.create(MAX, 1) -- visible body radius: contact reach
local sentX = table.create(MAX, 0) -- where the last snapshot put it (what clients draw)
local sentZ = table.create(MAX, 0)
local speed = table.create(MAX, 0)
local dmg = table.create(MAX, 0)
local bossKind = table.create(MAX, 0) -- 0 regular, 1 miniboss, 2 stage boss
local dashUntil = table.create(MAX, 0)
local dashX = table.create(MAX, 0)
local dashZ = table.create(MAX, 0)
local tag = table.create(MAX, false)
local runner = table.create(MAX, false) -- an overtime runner: frenzied and fast

local typeIndex = {}
for i, name in Roster.EnemyOrder do
	typeIndex[name] = i
end

function EnemyService:KnitInit()
	self._free = {}
	-- slots freed this tick: only reusable once the client has been told they are
	-- gone (FlushNet), so a new enemy never takes a slot whose removal, or whose
	-- killing blow, is still on its way
	self._recycle = {}
	for slot = MAX, 1, -1 do
		table.insert(self._free, slot)
	end
	self._count = 0
	self._regular = 0
	self._budget = 0
	self._tick = 0
	self._grid = Grid.new(12)
	self._scratch = {}
	self._spawned = {}
	self._gone = {}
	self._hits = {}
	self._frozen = {} -- slot, tenths of a second: flushed with the hits so clients can show the ice
	self.Killed = Signal.new()
	self._spawnEvent = Net.server("EnemySpawn")
	self._snapEvent = Net.server("EnemySnap")
	self._goneEvent = Net.server("EnemyGone")
	self._hitsEvent = Net.server("Hits")
	self._frozenEvent = Net.server("EnemyFrozen")
end

-- queue a freeze for the clients' ice shell (bounded, like hits)
function EnemyService:_tellFrozen(slot: number, seconds: number)
	local frozen = self._frozen
	if #frozen < 600 then
		table.insert(frozen, slot)
		table.insert(frozen, math.clamp(math.floor(seconds * 10 + 0.5), 1, 255))
	end
end

function EnemyService:KnitStart()
	self._players = Knit.GetService("PlayerStateService")
	self._mapService = Knit.GetService("MapService")
	self._map = self._mapService:GetMap()
end

-- ------------------------------------------------------------------ queries

function EnemyService:Count(): number
	return self._count
end

function EnemyService:IsAlive(slot: number): boolean
	return alive[slot] == true
end

--- x, y (ground), z of an enemy.
function EnemyService:Pos(slot: number): (number, number, number)
	local x, z = ex[slot], ez[slot]
	return x, MapGen.heightAt(self._map, x, z), z
end

function EnemyService:Info(slot: number)
	return { name = def[slot].name, hp = hp[slot], maxHp = maxHp[slot], kind = bossKind[slot], x = ex[slot], z = ez[slot] }
end

--- Elites and bosses: what "Damage to Elites" applies to.
function EnemyService:IsTough(slot: number): boolean
	return elite[slot] == true or bossKind[slot] > 0
end

--- Contact damage of an enemy (as its touch deals it).
function EnemyService:ContactDamage(slot: number): number
	return dmg[slot] * (if elite[slot] then 1.5 else 1)
end

--- How tall an enemy stands, in studs.
function EnemyService:HeightOf(slot: number): number
	return def[slot].height * (if elite[slot] then GameConfig.EliteScale else 1)
end

function EnemyService:Health(slot: number): (number, number)
	return hp[slot], maxHp[slot]
end

--- Fill `out` with every living slot within `r` of (x, z). Returns the count.
function EnemyService:Query(x: number, z: number, r: number, out: { number }): number
	local scratch = self._scratch
	table.clear(scratch)
	local n = Grid.query(self._grid, x, z, r, scratch)
	local count = 0
	for i = 1, n do
		local slot = scratch[i]
		if alive[slot] then
			local reach = r + radius[slot]
			local dx, dz = ex[slot] - x, ez[slot] - z
			if dx * dx + dz * dz <= reach * reach then
				count += 1
				out[count] = slot
			end
		end
	end
	for i = count + 1, #out do
		out[i] = nil
	end
	return count
end

--- The closest living enemy within `maxR`, skipping any slot in `skip`.
function EnemyService:Nearest(x: number, z: number, maxR: number, skip: { [number]: boolean }?): number?
	local scratch = self._scratch
	table.clear(scratch)
	local n = Grid.query(self._grid, x, z, maxR, scratch)
	local best, bestD = nil, maxR * maxR
	for i = 1, n do
		local slot = scratch[i]
		if alive[slot] and not (skip and skip[slot]) then
			local dx, dz = ex[slot] - x, ez[slot] - z
			local d = dx * dx + dz * dz
			if d < bestD then
				best, bestD = slot, d
			end
		end
	end
	return best
end

--- Up to `n` different living enemies within `maxR`, nearest first.
function EnemyService:NearestN(x: number, z: number, maxR: number, n: number, out: { number }): number
	local found = self:Query(x, z, maxR, out)
	if found > 1 then
		table.sort(out, function(a, b)
			local da = (ex[a] - x) ^ 2 + (ez[a] - z) ^ 2
			local db = (ex[b] - x) ^ 2 + (ez[b] - z) ^ 2
			return da < db
		end)
	end
	for i = n + 1, found do
		out[i] = nil
	end
	return math.min(found, n)
end

-- ------------------------------------------------------------------ spawning

--- Put one enemy in the world. opts: elite, hpMult, dmgMult, speedMult, runner, tag.
function EnemyService:Spawn(typeName: string, x: number, z: number, opts): number?
	local d = Roster.Enemies[typeName]
	local slot = table.remove(self._free)
	if not d or not slot then
		return nil
	end
	opts = opts or {}
	local isElite = opts.elite == true
	local health = d.hp * (d.hpScale or 1) * (opts.hpMult or 1)
	if isElite then
		health *= GameConfig.EliteHPMultiplier
	end
	alive[slot] = true
	typeId[slot] = typeIndex[typeName]
	def[slot] = d
	ex[slot], ez[slot] = x, z
	hp[slot], maxHp[slot] = health, health
	elite[slot] = isElite
	target[slot] = false
	retargetAt[slot] = 0
	frozenUntil[slot] = 0
	poisonUntil[slot] = 0
	poisonAcc[slot] = 0
	contactAt[slot] = 0
	kbx[slot], kbz[slot] = 0, 0
	radius[slot] = d.radius * (if isElite then GameConfig.EliteScale else 1)
	body[slot] = (d.body or d.radius) * (if isElite then GameConfig.EliteScale else 1)
	sentX[slot], sentZ[slot] = x, z
	speed[slot] = d.speed * GameConfig.EnemySpeedScale * (0.92 + rng:NextNumber() * 0.16) * (opts.speedMult or 1)
	runner[slot] = opts.runner == true
	dmg[slot] = d.dmg * GameConfig.EnemyDamageScale * (opts.dmgMult or 1)
	bossKind[slot] = if d.boss == "stage" then 2 elseif d.boss == "mini" then 1 else 0
	dashUntil[slot] = 0
	tag[slot] = opts.tag or false
	self._count += 1
	if bossKind[slot] == 0 and not opts.tag then
		self._regular += 1
	end
	table.insert(self._spawned, slot)
	return slot
end

-- A point on the ring around a hero that an enemy can actually walk from.
function EnemyService:_ringPoint(rec, minR: number, maxR: number): (number?, number?)
	local limit = GameConfig.PlaySizeStuds / 2
	for _ = 1, 8 do
		local angle = rng:NextNumber() * math.pi * 2
		local r = minR + rng:NextNumber() * (maxR - minR)
		local x = math.clamp(rec.x + math.cos(angle) * r, -limit, limit)
		local z = math.clamp(rec.z + math.sin(angle) * r, -limit, limit)
		local dx, dz = x - rec.x, z - rec.z
		if dx * dx + dz * dz >= (minR * 0.6) ^ 2 and self._mapService:IsReachable(x, z) then
			return x, z
		end
	end
	return nil, nil
end

--- Spawn one enemy on the ring around a hero.
function EnemyService:SpawnNear(rec, typeName: string, opts, minR: number?, maxR: number?): number?
	local x, z = self:_ringPoint(rec, minR or GameConfig.SpawnRingMin, maxR or GameConfig.SpawnRingMax)
	if not x then
		return nil
	end
	return self:Spawn(typeName, x, z, opts)
end

--- The spawn director: feed the horde for this tick.
function EnemyService:Direct(dt: number, clock: number, tier: number, difficulty: number, bossActive: boolean)
	local recs = self._players:All()
	local standing = {}
	for _, rec in recs do
		if not rec.downed then
			table.insert(standing, rec)
		end
	end
	if #standing == 0 then
		return
	end
	local c = GameConfig
	local rate = Spawn.rate(clock, #recs, difficulty, c.SpawnBasePerSecond, c.SpawnPerMinute, c.SpawnRatePerExtraPlayer)
	if tier > 0 then
		rate *= c.OvertimeSpawnMultiplier * (1 + 0.25 * (tier - 1))
	end
	self._budget = math.min(self._budget + rate * dt, 40)
	local cap = Spawn.cap(#recs, c.EnemyCapSolo, c.EnemyCapPerExtraPlayer, c.EnemyHardCap)
	local types = if tier > 0
		then Roster.OvertimeTypes
		elseif bossActive then Roster.BossSpawnTypes
		else Spawn.typesAt(Roster.SpawnTimeline, clock)
	local hpMult = Spawn.hpMult(clock, difficulty, tier, c.EnemyHPPerMinute, c.OvertimeHPGrowth, c.OvertimeHPMax)
	local dmgMult = (1 + c.EnemyDamagePerMinute * (clock / 60)) * Spawn.overtimeDamage(tier, c.OvertimeDamageGrowth, c.OvertimeDamageMax)
	local pace = Spawn.overtimeSpeed(tier, c.OvertimeSpeedPerTier, c.OvertimeSpeedMax)
	local runShare, runBoost = Spawn.runners(
		tier,
		c.OvertimeRunnerPerTier,
		c.OvertimeRunnerMax,
		c.OvertimeRunnerBoost,
		c.OvertimeRunnerBoostPerTier,
		c.OvertimeRunnerBoostMax
	)
	while self._budget >= 1 do
		self._budget -= 1
		if self._regular >= cap then
			continue
		end
		local rec = standing[rng:NextInteger(1, #standing)]
		local name = types[rng:NextInteger(1, #types)]
		local chance =
			Spawn.eliteChance(c.EliteBaseChance, rec.stats.EliteSpawnIncrease, clock, tier, c.OvertimeElitePerTier, c.OvertimeEliteMax)
		local run = runShare > 0 and rng:NextNumber() < runShare
		self:SpawnNear(rec, name, {
			elite = rng:NextNumber() < chance,
			hpMult = hpMult,
			dmgMult = dmgMult,
			speedMult = if run then pace * runBoost else pace,
			runner = run,
		})
	end
end

function EnemyService:Clear()
	for slot = 1, MAX do
		if alive[slot] then
			alive[slot] = false
			table.insert(self._recycle, slot)
			table.insert(self._gone, slot)
			table.insert(self._gone, GONE_CLEARED)
		end
	end
	self._count = 0
	self._regular = 0
	self._budget = 0
	Grid.clear(self._grid)
	self:FlushNet()
end

-- ------------------------------------------------------------------ damage and status

--- Damage one enemy. flags: bits 0-1 crit level, 4 poison, 8 ice. Returns true if it died.
function EnemyService:Damage(slot: number, amount: number, rec, flags: number?): boolean
	if not alive[slot] or amount <= 0 then
		return false
	end
	hp[slot] -= amount
	if rec then
		rec.damage += amount
	end
	local hits = self._hits
	if #hits < 450 then
		table.insert(hits, slot)
		table.insert(hits, math.clamp(math.floor(amount + 0.5), 1, 65535))
		table.insert(hits, flags or 0)
	end
	if hp[slot] > 0 then
		return false
	end
	alive[slot] = false
	table.insert(self._recycle, slot)
	self._count -= 1
	if bossKind[slot] == 0 and not tag[slot] then
		self._regular -= 1
	end
	table.insert(self._gone, slot)
	table.insert(self._gone, GONE_KILLED)
	if rec then
		rec.kills += 1
	end
	self.Killed:Fire({
		slot = slot,
		type = Roster.EnemyOrder[typeId[slot]],
		def = def[slot],
		x = ex[slot],
		z = ez[slot],
		elite = elite[slot],
		bossKind = bossKind[slot],
		killer = rec,
		tag = tag[slot],
	})
	return true
end

--- The same flat damage to everything in a circle. Returns how many were hit.
function EnemyService:DamageCircle(x: number, z: number, r: number, amount: number, rec, flags: number?): number
	local out = {}
	local n = self:Query(x, z, r, out)
	for i = 1, n do
		self:Damage(out[i], amount, rec, flags)
	end
	return n
end

function EnemyService:Knock(slot: number, dx: number, dz: number, studs: number)
	if not alive[slot] or studs <= 0 then
		return
	end
	local resist = def[slot].kbResist or 0
	if elite[slot] then
		resist = math.max(resist, 0.5)
	end
	local push = studs * (1 - math.clamp(resist, 0, 1)) * 6 -- an impulse that decays over about a quarter second
	kbx[slot] += dx * push
	kbz[slot] += dz * push
end

function EnemyService:Freeze(slot: number, seconds: number, now: number)
	if alive[slot] and bossKind[slot] == 0 then
		frozenUntil[slot] = math.max(frozenUntil[slot], now + seconds)
		self:_tellFrozen(slot, frozenUntil[slot] - now)
	end
end

function EnemyService:FreezeAll(seconds: number, now: number)
	for slot = 1, MAX do
		if alive[slot] then
			frozenUntil[slot] = math.max(frozenUntil[slot], now + seconds * (if bossKind[slot] > 0 then 0.4 else 1))
			self:_tellFrozen(slot, frozenUntil[slot] - now)
		end
	end
end

function EnemyService:IsFrozen(slot: number, now: number): boolean
	return frozenUntil[slot] > now
end

function EnemyService:Poison(slot: number, dps: number, seconds: number, rec, now: number)
	if alive[slot] then
		poisonUntil[slot] = now + seconds
		poisonDps[slot] = math.max(poisonDps[slot] or 0, dps)
		poisonOwner[slot] = rec
	end
end

function EnemyService:Dash(slot: number, dx: number, dz: number, seconds: number, now: number)
	if alive[slot] then
		dashUntil[slot] = now + seconds
		dashX[slot], dashZ[slot] = dx, dz
	end
end

function EnemyService:TargetOf(slot: number)
	return target[slot] or nil
end

-- ------------------------------------------------------------------ the tick

function EnemyService:Step(dt: number, now: number)
	local map = self._map
	local grid = self._grid
	local players = self._players
	local recs = players:All()
	local cliff = GameConfig.CliffSlope
	local heroBody = GameConfig.HeroBodyRadius
	local heroHeight = GameConfig.HeroHeight
	local margin = GameConfig.ContactMargin
	local tolY = GameConfig.ContactHeightTolerance
	local leash2 = GameConfig.LeashDistance ^ 2
	local kbDecay = math.exp(-9 * dt)
	local scratch = {}

	Grid.clear(grid)
	for slot = 1, MAX do
		if alive[slot] then
			Grid.insert(grid, slot, ex[slot], ez[slot])
		end
	end

	for slot = 1, MAX do
		if not alive[slot] then
			continue
		end
		-- poison ticks in whole points so damage numbers stay readable
		if poisonUntil[slot] > now then
			poisonAcc[slot] += poisonDps[slot] * dt
			if poisonAcc[slot] >= 1 then
				local whole = math.floor(poisonAcc[slot])
				poisonAcc[slot] -= whole
				if self:Damage(slot, whole, poisonOwner[slot] or nil, 4) then
					continue
				end
			end
		else
			poisonDps[slot] = 0
		end

		local x, z = ex[slot], ez[slot]
		local t = target[slot]
		if now >= retargetAt[slot] or not t or t.downed or not t.active then
			t = false
			local best = math.huge
			for _, rec in recs do
				if not rec.downed and rec.active then
					local d = (rec.x - x) ^ 2 + (rec.z - z) ^ 2
					if d < best then
						best, t = d, rec
					end
				end
			end
			target[slot] = t
			retargetAt[slot] = now + 0.5 + (slot % 5) * 0.1
		end
		if not t then
			continue
		end

		local dx, dz = t.x - x, t.z - z
		local dist = math.sqrt(dx * dx + dz * dz)
		local frozen = frozenUntil[slot] > now
		local mx, mz = 0, 0
		-- contact is body to body; the approach stops just inside it
		local reach = Contact.reach(body[slot], heroBody, margin)

		if not frozen then
			local sp = speed[slot]
			if dashUntil[slot] > now then
				mx, mz = dashX[slot] * sp * 4, dashZ[slot] * sp * 4
			else
				if dist > reach * 0.85 then
					-- never past the stop point in one tick (a runner covers 2-3 studs a tick)
					local go = math.min(sp, (dist - reach * 0.8) / math.max(dt, 1e-3))
					mx, mz = dx / dist * go, dz / dist * go
				elseif dist < reach * 0.55 and dist > 1e-3 then
					-- standing inside the hero: back out, so a pack rings him instead of burying him
					mx, mz = -dx / dist * sp * 0.7, -dz / dist * sp * 0.7
				end
				-- keep the horde from collapsing into one point
				table.clear(scratch)
				local n = Grid.query(grid, x, z, SEP, scratch)
				local px, pz, used = 0, 0, 0
				for i = 1, n do
					local other = scratch[i]
					if other ~= slot and alive[other] then
						local ox, oz = x - ex[other], z - ez[other]
						local d2 = ox * ox + oz * oz
						local want = radius[slot] + radius[other]
						if d2 < want * want and d2 > 1e-4 then
							local d = math.sqrt(d2)
							local w = (want - d) / want
							px += ox / d * w
							pz += oz / d * w
							used += 1
							if used >= 6 then
								break
							end
						end
					end
				end
				mx += px * sp * 0.9
				mz += pz * sp * 0.9
			end
		end

		mx += kbx[slot]
		mz += kbz[slot]
		kbx[slot] *= kbDecay
		kbz[slot] *= kbDecay

		if mx ~= 0 or mz ~= 0 then
			local nx, nz = x + mx * dt, z + mz * dt
			if def[slot].flying or MapGen.canStep(map, x, z, nx, nz, cliff) then
				x, z = nx, nz
			elseif MapGen.canStep(map, x, z, nx, z, cliff) then
				x = nx -- slide along the cliff in x
			elseif MapGen.canStep(map, x, z, x, nz, cliff) then
				z = nz -- or in z
			else
				-- boxed in: step sideways, alternating by slot so a pack fans out
				local side = if slot % 2 == 0 then 1 else -1
				local sx, sz = x - mz * dt * side, z + mx * dt * side
				if MapGen.canStep(map, x, z, sx, sz, cliff) then
					x, z = sx, sz
				end
			end
			ex[slot], ez[slot] = x, z
		end

		if not frozen and now >= contactAt[slot] then
			-- in reach where the server has it now AND where clients are drawing it,
			-- so a chasing enemy never hits from ground it has not been seen to cover
			local nowDist = math.sqrt((t.x - x) ^ 2 + (t.z - z) ^ 2)
			local drawnDist = math.sqrt((t.x - sentX[slot]) ^ 2 + (t.z - sentZ[slot]) ^ 2)
			if Contact.touches(nowDist, drawnDist, reach) then
				-- and the bodies overlap in height: a hero jumping over it is not touched
				local low = MapGen.heightAt(map, x, z) + (if def[slot].flying then 1.9 else 0)
				local feet = t.y - (t.rootHeight or 3)
				if
					Contact.overlapsY(
						feet,
						heroHeight,
						low,
						low + def[slot].height * (if elite[slot] then GameConfig.EliteScale else 1),
						tolY
					)
				then
					players:Hurt(t, self:ContactDamage(slot), slot, now)
					contactAt[slot] = now + GameConfig.ContactCooldown
				end
			end
		end

		if bossKind[slot] == 0 and dist * dist > leash2 then
			local rx, rz = self:_ringPoint(t, GameConfig.SpawnRingMin, GameConfig.SpawnRingMax)
			if rx then
				ex[slot], ez[slot] = rx, rz
			end
		end
	end

	self._tick += 1
	self:FlushNet()
	if self._tick % math.max(1, math.floor(GameConfig.SimHz / GameConfig.SnapshotHz)) == 0 then
		self:_sendSnapshot(now)
	end
end

function EnemyService:_sendSnapshot(now: number)
	local slots, xs, zs = {}, {}, {}
	local count = 0
	for slot = 1, MAX do
		if alive[slot] then
			count += 1
			slots[count], xs[count], zs[count] = slot, ex[slot], ez[slot]
			sentX[slot], sentZ[slot] = ex[slot], ez[slot]
		end
	end
	self._snapEvent:FireAllClients(Snapshot.encode(count, slots, xs, zs, self._map.half, now % 4096))
end

--- Send this tick's spawns, removals and hits.
function EnemyService:FlushNet()
	local spawned = self._spawned
	if #spawned > 0 then
		local b = buffer.create(#spawned * 4)
		for i, slot in spawned do
			local o = (i - 1) * 4
			buffer.writeu16(b, o, slot)
			buffer.writeu8(b, o + 2, typeId[slot])
			buffer.writeu8(b, o + 3, (if elite[slot] then FLAG_ELITE else 0) + (if runner[slot] then FLAG_RUNNER else 0))
		end
		table.clear(spawned)
		self._spawnEvent:FireAllClients(b)
	end
	-- hits before removals: a killing blow's number is drawn where the enemy
	-- still stands on the client, and only then does it go
	local hits = self._hits
	if #hits > 0 then
		local n = #hits / 3
		local b = buffer.create(n * 5)
		for i = 1, n do
			local o = (i - 1) * 5
			buffer.writeu16(b, o, hits[i * 3 - 2])
			buffer.writeu16(b, o + 2, hits[i * 3 - 1])
			buffer.writeu8(b, o + 4, hits[i * 3])
		end
		table.clear(hits)
		self._hitsEvent:FireAllClients(b)
	end
	local gone = self._gone
	if #gone > 0 then
		local n = #gone / 2
		local b = buffer.create(n * 3)
		for i = 1, n do
			local o = (i - 1) * 3
			buffer.writeu16(b, o, gone[i * 2 - 1])
			buffer.writeu8(b, o + 2, gone[i * 2])
		end
		table.clear(gone)
		self._goneEvent:FireAllClients(b)
	end
	-- the client now knows these slots are empty: they may be used again
	local recycle = self._recycle
	for i = #recycle, 1, -1 do
		table.insert(self._free, recycle[i])
	end
	table.clear(recycle)
	local frozen = self._frozen
	if #frozen > 0 then
		local n = #frozen / 2
		local b = buffer.create(n * 3)
		for i = 1, n do
			local o = (i - 1) * 3
			buffer.writeu16(b, o, frozen[i * 2 - 1])
			buffer.writeu8(b, o + 2, frozen[i * 2])
		end
		table.clear(frozen)
		self._frozenEvent:FireAllClients(b)
	end
end

--- For a client that joins mid-run: every living enemy as a spawn packet.
function EnemyService:SendAllTo(player: Player)
	local list = {}
	for slot = 1, MAX do
		if alive[slot] then
			table.insert(list, slot)
		end
	end
	if #list == 0 then
		return
	end
	local b = buffer.create(#list * 4)
	for i, slot in list do
		local o = (i - 1) * 4
		buffer.writeu16(b, o, slot)
		buffer.writeu8(b, o + 2, typeId[slot])
		buffer.writeu8(b, o + 3, (if elite[slot] then FLAG_ELITE else 0) + (if runner[slot] then FLAG_RUNNER else 0))
	end
	self._spawnEvent:FireClient(player, b)
end

return EnemyService

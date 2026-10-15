--!nonstrict
-- RunDirectorService - owns the run state machine (Lobby, Intro, Playing,
-- Overtime, Victory, Wipe, Results), the stage clock, the pause flag (one
-- reason each: "levelup", "panel", "player") and the
-- difficulty value. It also drives the one simulation tick every other service
-- steps on, so the order things happen in is written down in one place.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Progress = require(ReplicatedStorage.Shared.Core.Progress)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local RunState = require(ReplicatedStorage.Shared.Core.RunState)
local SimClock = require(ReplicatedStorage.Shared.Core.SimClock)
local Spawn = require(ReplicatedStorage.Shared.Core.Spawn)

local RunDirectorService = Knit.CreateService({ Name = "RunDirectorService" })

local STEP = 1 / GameConfig.SimHz

function RunDirectorService:KnitInit()
	self._phase = RunState.Lobby
	self._clock = 0
	self._tier = 0
	self._difficulty = 0
	self._pauses = {}
	self._paused = false
	self._kills = 0
	self._minibossKills = 0
	self._bossKills = 0
	self._portalFound = false
	self._bossSummoned = false
	self._bossDead = false
	self._bossDeadAt = nil
	self._nextMini = 1
	self._exitAt = nil
	self._phaseUntil = nil
	self._accum = 0
	-- gameplay time: every simulation timestamp is taken from this, never from
	-- os.clock(), so nothing comes due while the run is paused
	self._sim = SimClock.new()
	self._clockSentAt = 0
	self._phaseEvent = Net.server("Phase")
	self._clockEvent = Net.server("Clock")
	self._banner = Net.server("Banner")
	self._results = Net.server("Results")
	self._toast = Net.server("Toast")
end

function RunDirectorService:KnitStart()
	self._party = Knit.GetService("PartyService")
	self._players = Knit.GetService("PlayerStateService")
	self._enemies = Knit.GetService("EnemyService")
	self._combat = Knit.GetService("CombatService")
	self._pickups = Knit.GetService("PickupService")
	self._upgrades = Knit.GetService("UpgradeService")
	self._interactables = Knit.GetService("InteractableService")
	self._bosses = Knit.GetService("BossService")
	self._xp = Knit.GetService("XPService")
	self._data = Knit.GetService("DataService")
	self._mapService = Knit.GetService("MapService")
	self._pause = Knit.GetService("PauseService")

	self._enemies.Killed:Connect(function()
		self._kills += 1
	end)
	self._party.ReadyChanged:Connect(function(player, ready)
		if ready and RunState.isLive(self._phase) and not self._players:Get(player) then
			self:_lateJoin(player)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.delay(1.5, function()
			if player.Parent == Players then
				self:_sendPhase(player)
				if RunState.isLive(self._phase) then
					self._enemies:SendAllTo(player)
					self._interactables:SendAll(player)
					self._xp:Broadcast()
				end
			end
		end)
	end)

	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(function()
			self:_frame(dt)
		end)
		if not ok then
			warn(`[RunDirectorService] frame failed: {err}`)
		end
	end)
end

-- ------------------------------------------------------------------ queries

function RunDirectorService:GetPhase(): string
	return self._phase
end

function RunDirectorService:GetClock(): number
	return self._clock
end

function RunDirectorService:GetDifficulty(): number
	return self._difficulty
end

function RunDirectorService:IsPaused(): boolean
	return self._paused
end

--- Gameplay time in seconds. Anything that acts outside the simulation tick
--- (a remote, a signal, a dev hook) stamps with this, not with os.clock().
function RunDirectorService:Now(): number
	return SimClock.now(self._sim)
end

-- ------------------------------------------------------------------ events from other services

function RunDirectorService:SetPause(reason: string, on: boolean)
	self._pauses[reason] = if on then true else nil
	local paused = next(self._pauses) ~= nil
	if paused ~= self._paused then
		self._paused = paused
		if RunState.isLive(self._phase) then
			-- outside a live run the phase owns whether heroes are frozen
			self._players:SetFrozen(paused)
		end
		self:_sendClock()
		if paused then
			self._combat:ReleaseInputs() -- nobody is holding an attack through a pause
		else
			-- a warning drawn before the pause ran out on screen while the strike waited
			self._bosses:Resync(self:Now())
		end
	end
end

function RunDirectorService:AddDifficulty(amount: number)
	self._difficulty += amount
	for _, rec in self._players:All() do
		rec.bonus.Difficulty = self._difficulty
		self._players:Recompute(rec)
	end
end

function RunDirectorService:PortalFound()
	if not self._portalFound then
		self._portalFound = true
		self:_sendPhase(nil)
	end
end

--- A hero interacted with the boss portal.
function RunDirectorService:PortalUsed(it)
	if not RunState.isLive(self._phase) then
		return
	end
	if not self._bossSummoned then
		self._bossSummoned = true
		self._portalFound = true
		self._interactables:SetState(it, "summoned")
		self._bosses:SummonStage(it.x + 14, it.z, self:Now())
		self:_sendPhase(nil)
	elseif self._bossDead and not self._exitAt then
		self._exitAt = self:Now() + GameConfig.ExitCountdownSeconds
		self._banner:FireAllClients(`Leaving in {GameConfig.ExitCountdownSeconds}...`, "exit")
	end
end

function RunDirectorService:BossDied()
	self._bossKills += 1
	self._bossDead = true
	self._bossDeadAt = self._clock
	local portal = self._interactables:GetPortal()
	if portal then
		self._interactables:SetState(portal, "exit")
	end
	self._banner:FireAllClients("BOSS BONKED", "win")
	self:_sendPhase(nil)
end

function RunDirectorService:MinibossDied()
	self._minibossKills += 1
end

-- ------------------------------------------------------------------ phases

function RunDirectorService:_setPhase(phase: string)
	if not RunState.canMove(self._phase, phase) then
		warn(`[RunDirectorService] refused {self._phase} -> {phase}`)
		return false
	end
	self._phase = phase
	self:_sendPhase(nil)
	return true
end

function RunDirectorService:_payload()
	return {
		phase = self._phase,
		clock = self._clock,
		stage = GameConfig.StageSeconds,
		tier = self._tier,
		paused = self._paused,
		kills = self._kills,
		map = self._party:GetMap(),
		quests = RunState.quests(self._portalFound, self._bossSummoned, self._bossDead),
		portal = if self._portalFound then self:_portalPos() else nil,
	}
end

function RunDirectorService:_portalPos()
	local portal = self._interactables:GetPortal()
	return if portal then { x = portal.x, z = portal.z } else nil
end

function RunDirectorService:_sendPhase(player: Player?)
	if player then
		self._phaseEvent:FireClient(player, self:_payload())
	else
		self._phaseEvent:FireAllClients(self:_payload())
	end
end

function RunDirectorService:_sendClock()
	self._clockEvent:FireAllClients(self._clock, self._tier, self._paused, self._kills)
end

function RunDirectorService:_startRun()
	if not self._mapService:IsTerrainReady() then
		return
	end
	if not self:_setPhase(RunState.Intro) then
		return
	end
	self._clock = 0
	self._tier = 0
	self._difficulty = 0
	self._kills = 0
	self._minibossKills = 0
	self._bossKills = 0
	self._portalFound = false
	self._bossSummoned = false
	self._bossDead = false
	self._bossDeadAt = nil
	self._nextMini = 1
	self._exitAt = nil
	table.clear(self._pauses)
	self._paused = false

	self._enemies:Clear()
	self._combat:Reset()
	self._pickups:Clear()
	self._upgrades:Reset()
	self._bosses:Reset()
	self._xp:Reset()
	self._interactables:Place()
	self._players:BeginRun(self._party:GetPlayers())
	self._phaseUntil = os.clock() + GameConfig.IntroSeconds
	self:_sendPhase(nil)
	local map = Roster.Maps[self._party:GetMap()]
	self._banner:FireAllClients(map.name, "stage", map.joke)
	print(`[RunDirectorService] run started with {#self._party:GetPlayers()} player(s)`)
end

function RunDirectorService:_lateJoin(player: Player)
	self._players:JoinRun(player)
	self._enemies:SendAllTo(player)
	self._interactables:SendAll(player)
	local rec = self._players:Get(player)
	local catchUp = math.floor((self._xp:GetLevel() - 1) * GameConfig.LateJoinLevelFraction)
	if rec and catchUp > 0 then
		self._upgrades:QueueFor(rec, catchUp)
	end
	self:_sendPhase(player)
end

function RunDirectorService:_endRun(victory: boolean)
	if not self:_setPhase(if victory then RunState.Victory else RunState.Wipe) then
		return
	end
	self._players:SetFrozen(true)
	local rows = {}
	local c = GameConfig
	for _, rec in self._players:All() do
		local silver = Progress.silver(
			self._kills,
			self._minibossKills,
			self._bossKills,
			c.SilverPerHundredKills,
			c.SilverPerMinibossKill,
			c.SilverPerBossKill,
			rec.stats.SilverGain,
			self._tier,
			c.OvertimeSilverStep
		)
		self._data:AddSilver(rec.player, silver)
		self._data:RecordRun(rec.player, rec.hero, self._kills, self._bossDeadAt)
		table.insert(rows, {
			userId = rec.player.UserId,
			name = rec.player.DisplayName,
			hero = rec.hero,
			kills = rec.kills,
			damage = math.floor(rec.damage),
			gold = rec.gold,
			silver = silver,
		})
		task.spawn(function()
			self._data:Save(rec.player)
		end)
	end
	self._results:FireAllClients({
		victory = victory,
		kills = self._kills,
		level = self._xp:GetLevel(),
		clock = self._clock,
		bossTime = self._bossDeadAt,
		tier = self._tier,
		joke = Roster.DeathJokes[math.random(1, #Roster.DeathJokes)],
		players = rows,
	})
	self._phaseUntil = os.clock() + 2.5
end

function RunDirectorService:_toLobby()
	self._enemies:Clear()
	self._combat:Reset()
	self._pickups:Clear()
	self._upgrades:Reset()
	self._bosses:Reset()
	self._interactables:Clear()
	self._players:EndRun()
	self._party:ClearReady()
	table.clear(self._pauses)
	self._paused = false
	self._phase = RunState.Lobby
	self:_sendPhase(nil)
end

-- ------------------------------------------------------------------ the frame

function RunDirectorService:_frame(dt: number)
	local now = os.clock()
	local phase = self._phase

	-- choices time out and tidy up whether or not the simulation is paused
	self._upgrades:Step(now)
	self._interactables:StepPanels(now)
	self._pause:Step(now)

	if phase == RunState.Lobby then
		if self._party:AllReady() then
			self:_startRun()
		end
		return
	elseif phase == RunState.Intro then
		if now >= self._phaseUntil then
			self:_setPhase(RunState.Playing)
		end
		return
	elseif phase == RunState.Victory or phase == RunState.Wipe then
		if now >= self._phaseUntil then
			self:_setPhase(RunState.Results)
			self._phaseUntil = now + GameConfig.ResultsSeconds
		end
		return
	elseif phase == RunState.Results then
		if now >= self._phaseUntil then
			self:_toLobby()
		end
		return
	end

	-- Playing or Overtime
	local recs = self._players:All()
	if #recs == 0 then
		self:_toLobby()
		return
	end
	if self._paused then
		self._players:Flush(now)
		return
	end

	self._accum = math.min(self._accum + dt, STEP * 4)
	while self._accum >= STEP do
		self._accum -= STEP
		local t0 = os.clock()
		self:_tick(STEP, SimClock.advance(self._sim, STEP))
		-- a running average of what one simulation tick costs, for the perf check
		self._tickCost = (self._tickCost or 0) * 0.95 + (os.clock() - t0) * 0.05
		if not RunState.isLive(self._phase) or self._paused then
			break
		end
	end

	if now >= self._clockSentAt then
		self._clockSentAt = now + 0.5
		self:_sendClock()
	end
end

function RunDirectorService:_tick(dt: number, now: number)
	self._clock += dt
	local c = GameConfig

	if self._phase == RunState.Playing and self._clock >= c.StageSeconds then
		self:_setPhase(RunState.Overtime)
		self._banner:FireAllClients("FINAL HORDE INCOMING!", "alarm")
	end
	local tier = Spawn.overtimeTier(self._clock - c.StageSeconds, c.OvertimeTierSeconds)
	if tier ~= self._tier then
		self._tier = tier
		self:_sendClock()
	end

	local miniTime = Roster.MinibossTimes[self._nextMini]
	if miniTime and self._clock >= miniTime then
		self._bosses:SpawnMini(Roster.Minibosses[(self._nextMini - 1) % #Roster.Minibosses + 1], now)
		self._nextMini += 1
	end

	self._players:Step(dt, now)
	self._enemies:Direct(dt, self._clock, self._tier, self._difficulty, self._bosses:AnyStageBoss())
	self._enemies:Step(dt, now)
	self._combat:Step(dt, now)
	self._bosses:Step(dt, now)
	self._pickups:Step(dt, now)
	self._interactables:Step(dt, now)
	self._enemies:FlushNet()

	if self._players:AliveCount() == 0 then
		self:_endRun(false)
	elseif self._exitAt and now >= self._exitAt then
		self:_endRun(true)
	end
end

return RunDirectorService

--!nonstrict
-- RunDirectorService - owns the run state machine (Lobby, Intro, Playing,
-- Overtime, Victory, Wipe, Results), the stage clock, the pause flag (one
-- reason each: "levelup", "panel", "player") and the
-- difficulty value. It also drives the one simulation tick every other service
-- steps on, so the order things happen in is written down in one place.
--
-- A run's end: Silver is paid and saved the moment it ends, then Victory or
-- Wipe holds for a moment and Results follows. The squad goes back to the
-- island as soon as every player still here has pressed CONTINUE (T3,
-- Core/EndVote), or when the Results time runs out, whichever comes first.
--
-- T6: a server holds the island hub and at most one Wardwood run. A run starts
-- only for the party that entered the portal (PartyService.Launch), and only
-- that party hears it (server/RunAudience): its phase and clock, the horde, its
-- sky and its results. Nobody joins a run once it is going. When it ends the
-- party is handed back to the island together (RunEnded).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local EndVote = require(ReplicatedStorage.Shared.Core.EndVote)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Progress = require(ReplicatedStorage.Shared.Core.Progress)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local RunState = require(ReplicatedStorage.Shared.Core.RunState)
local SimClock = require(ReplicatedStorage.Shared.Core.SimClock)
local Spawn = require(ReplicatedStorage.Shared.Core.Spawn)

local RunAudience = require(script.Parent.Parent.RunAudience)

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
	self._runId = 0 -- numbers each run, so a CONTINUE meant for one cannot touch the next
	self._endVote = nil -- who has pressed CONTINUE on the results (Core/EndVote)
	self._endSig = nil
	self._members = {} -- the run's party, as it entered the portal
	self._circle = nil -- the rune circle that party came from
	self._sky = "golden" -- drawn at the start, worn by the run's players only
	self._startedAt = 0
	self.RunEnded = Signal.new() -- (players still here, circle): the party is back on the island
	self._accum = 0
	-- gameplay time: every simulation timestamp is taken from this, never from
	-- os.clock(), so nothing comes due while the run is paused
	self._sim = SimClock.new()
	self._clockSentAt = 0
	self._phaseEvent = Net.server("Phase")
	self._clockEvent = Net.server("Clock")
	self._banner = Net.server("Banner")
	self._results = Net.server("Results")
	self._resultsReady = Net.server("ResultsReady")
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
	-- a party's countdown on the island is over: into the Wardwood
	self._party.Launch:Connect(function(players, circle)
		if not self:StartRun(players, circle) then
			self._party:LaunchFailed(circle)
		end
	end)
	-- CONTINUE on the results: counted once, for the run it names, from a player
	-- who was in that run; the frame below sends the squad home when all have
	Net.server("ResultsContinue").OnServerEvent:Connect(function(player: Player, run: unknown)
		if typeof(run) ~= "number" or not self._endVote or not self:_ending() then
			return
		end
		if EndVote.press(self._endVote, run, player.UserId) then
			self:_sendReady()
		end
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

--- Is the server's one Wardwood run taken (starting, going or ending)?
function RunDirectorService:IsRunActive(): boolean
	return self._phase ~= RunState.Lobby
end

--- What the island shows about the run, or nil when there is none.
function RunDirectorService:RunInfo()
	if self._phase == RunState.Lobby then
		return nil
	end
	local members = {}
	for _, player in self._members do
		table.insert(members, player.UserId)
	end
	return { circle = self._circle, members = members, phase = self._phase, since = os.clock() - self._startedAt }
end

--- Take `players` (a party from rune circle `circle`) into the Wardwood. False
--- when the run is taken or the Wardwood is not ready yet.
function RunDirectorService:StartRun(players: { Player }, circle: number): boolean
	if self._phase ~= RunState.Lobby or #players == 0 or not self._mapService:IsTerrainReady() then
		return false
	end
	self._members = table.clone(players)
	self._circle = circle
	RunAudience.set(players)
	self:_startRun()
	if self._phase == RunState.Lobby then
		RunAudience.clear()
		self._members = {}
		self._circle = nil
		return false
	end
	return true
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
			self._enemies:Resync(self:Now())
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
		RunAudience.fire(self._banner, `Leaving in {GameConfig.ExitCountdownSeconds}...`, "exit")
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
	RunAudience.fire(self._banner, "BOSS BONKED", "win")
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
		sky = self._sky,
		quests = RunState.quests(self._portalFound, self._bossSummoned, self._bossDead),
		portal = if self._portalFound then self:_portalPos() else nil,
	}
end

function RunDirectorService:_portalPos()
	local portal = self._interactables:GetPortal()
	return if portal then { x = portal.x, z = portal.z } else nil
end

--- The run is over and its results are up (Victory, Wipe or Results).
function RunDirectorService:_ending(): boolean
	local phase = self._phase
	return phase == RunState.Victory or phase == RunState.Wipe or phase == RunState.Results
end

local function presentIds(): { number }
	local ids = {}
	for _, player in RunAudience.list() do
		table.insert(ids, player.UserId)
	end
	return ids
end

--- Has every player still here from the run that ended pressed CONTINUE?
function RunDirectorService:_allContinued(): boolean
	return self._endVote ~= nil and EndVote.everyone(self._endVote, presentIds())
end

--- Who is done with the results, whenever that changes (a press, or a player
--- leaving, which also lowers how many are needed).
function RunDirectorService:_sendReady()
	local vote = self._endVote
	if not vote then
		return
	end
	local present = presentIds()
	local ready, need = EndVote.count(vote, present)
	local sig = `{vote.run}:{ready}:{need}`
	if sig == self._endSig then
		return
	end
	self._endSig = sig
	RunAudience.fire(self._resultsReady, { run = vote.run, ready = EndVote.readyList(vote, present), need = need })
end

function RunDirectorService:_sendPhase(player: Player?)
	if player then
		self._phaseEvent:FireClient(player, self:_payload())
	else
		RunAudience.fire(self._phaseEvent, self:_payload())
	end
end

function RunDirectorService:_sendClock()
	RunAudience.fire(self._clockEvent, self._clock, self._tier, self._paused, self._kills)
end

function RunDirectorService:_startRun()
	if not self._mapService:IsTerrainReady() then
		return
	end
	if not self:_setPhase(RunState.Intro) then
		return
	end
	self._runId += 1
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
	self._sky = self._mapService:DrawRunSky()
	self._startedAt = os.clock()
	self._players:BeginRun(self._members)
	self._phaseUntil = os.clock() + GameConfig.IntroSeconds
	self:_sendPhase(nil)
	local map = Roster.Maps[self._party:GetMap()]
	RunAudience.fire(self._banner, map.name, "stage", map.joke)
	print(`[RunDirectorService] run started with {#self._members} player(s) from circle {self._circle}, sky {self._sky}`)
end

function RunDirectorService:_endRun(victory: boolean)
	if not self:_setPhase(if victory then RunState.Victory else RunState.Wipe) then
		return
	end
	self._players:SetFrozen(true)
	local rows = {}
	local members = {}
	local c = GameConfig
	local run = {
		stageSeconds = math.min(self._clock, c.StageSeconds),
		overtimeSeconds = math.max(0, self._clock - c.StageSeconds),
		kills = self._kills,
		minibossKills = self._minibossKills,
		bossKills = self._bossKills,
		escaped = victory,
	}
	-- what each part of the run paid before Silver Gain: the same for the whole squad
	local _, parts = Progress.silver(run, 1, c)
	-- every reward is paid and saved here, before anyone sees the results
	for _, rec in self._players:All() do
		local silver = Progress.silver(run, rec.stats.SilverGain, c)
		self._data:AddSilver(rec.player, silver)
		local bestKills, bestTime = self._data:RecordRun(rec.player, rec.hero, self._kills, self._bossDeadAt)
		table.insert(members, rec.player.UserId)
		table.insert(rows, {
			userId = rec.player.UserId,
			name = rec.player.DisplayName,
			hero = rec.hero,
			kills = rec.kills,
			damage = math.floor(rec.damage),
			gold = rec.gold,
			silver = silver,
			gain = math.clamp(rec.stats.SilverGain, 0, c.SilverGainCap), -- the Silver Gain that counted
			best = { kills = bestKills == true, time = bestTime == true },
		})
		task.spawn(function()
			self._data:Save(rec.player)
		end)
	end
	self._endVote = EndVote.new(self._runId, members)
	self._endSig = nil
	RunAudience.fire(self._results, {
		run = self._runId,
		victory = victory,
		kills = self._kills,
		level = self._xp:GetLevel(),
		clock = self._clock,
		bossTime = self._bossDeadAt,
		tier = self._tier,
		map = self._party:GetMap(),
		minibosses = self._minibossKills,
		bosses = self._bossKills,
		silverParts = parts,
		silverCap = c.SilverRunCap,
		joke = Roster.DeathJokes[math.random(1, #Roster.DeathJokes)],
		players = rows,
	})
	self._phaseUntil = os.clock() + c.EndHoldSeconds
end

--- The run is over: the party goes back to the island, together.
function RunDirectorService:_toLobby()
	self._enemies:Clear()
	self._combat:Reset()
	self._pickups:Clear()
	self._upgrades:Reset()
	self._bosses:Reset()
	self._interactables:Clear()
	self._players:EndRun()
	table.clear(self._pauses)
	self._paused = false
	self._endVote = nil
	self._endSig = nil
	self._phase = RunState.Lobby
	self:_sendPhase(nil) -- the last word the party hears from this run
	local back = RunAudience.list()
	local circle = self._circle
	RunAudience.clear()
	self._members = {}
	self._circle = nil
	if circle then
		self._party:RunEnded(circle)
	end
	self.RunEnded:Fire(back, circle)
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
		return -- a run starts only when a party enters the portal (StartRun)
	elseif phase == RunState.Intro then
		if now >= self._phaseUntil then
			self:_setPhase(RunState.Playing)
		end
		return
	elseif phase == RunState.Victory or phase == RunState.Wipe then
		self:_sendReady()
		local everyone = self:_allContinued()
		if now >= self._phaseUntil or everyone then
			self:_setPhase(RunState.Results)
			self._phaseUntil = now + GameConfig.ResultsSeconds
			if everyone then
				self:_toLobby() -- the whole squad skipped ahead: nobody is left waiting on the results
			end
		end
		return
	elseif phase == RunState.Results then
		self:_sendReady()
		if now >= self._phaseUntil or self:_allContinued() then
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
		RunAudience.fire(self._banner, "FINAL HORDE INCOMING!", "alarm")
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
	self._enemies:Direct(dt, self._clock, self._tier, self._difficulty, self._bosses:AnyStageBoss(), self._bosses:AnyMiniboss())
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

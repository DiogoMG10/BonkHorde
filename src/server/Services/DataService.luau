--!nonstrict
-- DataService - owns the persistent profile: silver, unlocked heroes, run counts,
-- best scores, the hero last chosen (T6/T7: the island hub dresses the player
-- in it) and the player's settings (volumes, enemy outlines: Core/Settings).
--
-- If the load fails the player still plays, on defaults, with saving DISABLED for
-- the session, so a blank profile can never overwrite a real one.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Settings = require(ReplicatedStorage.Shared.Core.Settings)
local Signal = require(ReplicatedStorage.Packages.Signal)

local DataService = Knit.CreateService({ Name = "DataService" })

local LOAD_TRIES = 3

local function blank()
	local unlocked = {}
	for _, id in Roster.HeroOrder do
		if Roster.Heroes[id].unlockSilver == 0 then
			unlocked[id] = true
		end
	end
	return {
		silver = 0,
		unlocked = unlocked,
		runs = {},
		best = { kills = 0, time = 0 },
		lastHero = nil, -- the hero last chosen at a plinth, when it is one still owned
		settings = {},
		devUnlocked = {}, -- Studio test unlocks: shown and playable, never saved
		canSave = true,
	}
end

function DataService:KnitInit()
	self._profiles = {}
	self._settingsAt = {}
	self.Loaded = Signal.new() -- (player): the profile is in (or the defaults, if it could not load)
	self._profileEvent = Net.server("Profile")
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		self._store = store
	else
		warn(`[DataService] no datastore, progress will not save: {store}`)
	end
end

function DataService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		self:_load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_load(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		self:Save(player)
		self._profiles[player] = nil
		self._settingsAt[player] = nil
	end)
	-- kept with the profile and written by the next autosave or on leaving
	Net.server("Settings").OnServerEvent:Connect(function(player: Player, raw: unknown)
		local p = self._profiles[player]
		local now = os.clock()
		if not p or now - (self._settingsAt[player] or 0) < 0.5 then
			return
		end
		self._settingsAt[player] = now
		-- only the keys sent change (Core/Settings): the volumes and the
		-- outline toggle can never reset each other
		p.settings = Settings.merge(p.settings, raw)
	end)
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveSeconds)
			for _, player in Players:GetPlayers() do
				self:Save(player)
			end
		end
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			self:Save(player)
		end
	end)
end

function DataService:_load(player: Player)
	local profile = blank()
	if not self._store then
		profile.canSave = false
	else
		local loaded = false
		for attempt = 1, LOAD_TRIES do
			local ok, data = pcall(function()
				return self._store:GetAsync("u" .. player.UserId)
			end)
			if ok then
				if typeof(data) == "table" then
					profile.silver = tonumber(data.silver) or 0
					if typeof(data.unlocked) == "table" then
						for id, value in data.unlocked do
							if Roster.Heroes[id] and value == true then
								profile.unlocked[id] = true
							end
						end
					end
					if typeof(data.runs) == "table" then
						profile.runs = data.runs
					end
					if typeof(data.best) == "table" then
						profile.best.kills = tonumber(data.best.kills) or 0
						profile.best.time = tonumber(data.best.time) or 0
					end
					if typeof(data.lastHero) == "string" and Roster.Heroes[data.lastHero] then
						profile.lastHero = data.lastHero
					end
					profile.settings = Settings.clean(data.settings)
				end
				loaded = true
				break
			end
			warn(`[DataService] load attempt {attempt} failed for {player.Name}: {data}`)
			if string.find(tostring(data), "Studio access to APIs", 1, true) then
				break -- an unpublished Studio session can never reach the datastore; do not make the tester wait
			end
			task.wait(1.5 * attempt)
		end
		if not loaded then
			profile.canSave = false
		end
	end
	if player.Parent ~= Players then
		return
	end
	self._profiles[player] = profile
	self:Push(player)
	self.Loaded:Fire(player)
end

--- The profile for a player. Never nil for a connected player once loaded;
--- callers that run before the load get defaults.
function DataService:Get(player: Player)
	local profile = self._profiles[player]
	if not profile then
		profile = blank()
		profile.canSave = false -- a stand-in must never be written back
	end
	return profile
end

function DataService:IsLoaded(player: Player): boolean
	return self._profiles[player] ~= nil
end

function DataService:Push(player: Player)
	local p = self._profiles[player]
	if p then
		self._profileEvent:FireClient(
			player,
			{ silver = p.silver, unlocked = p.unlocked, runs = p.runs, best = p.best, settings = p.settings, canSave = p.canSave }
		)
	end
end

function DataService:AddSilver(player: Player, amount: number)
	local p = self._profiles[player]
	if p and amount > 0 then
		p.silver += math.floor(amount)
		self:Push(player)
	end
end

--- Spend silver to unlock a hero. Returns whether it happened.
function DataService:Unlock(player: Player, heroId: string): boolean
	local p = self._profiles[player]
	local hero = Roster.Heroes[heroId]
	if not p or not hero or p.unlocked[heroId] then
		return false
	end
	if p.silver < hero.unlockSilver then
		return false
	end
	p.silver -= hero.unlockSilver
	p.unlocked[heroId] = true
	self:Push(player)
	self:Save(player)
	return true
end

--- Remember the hero this player chose last (written by the next save).
function DataService:SetLastHero(player: Player, heroId: string)
	local p = self._profiles[player]
	if p and Roster.Heroes[heroId] then
		p.lastHero = heroId
	end
end

--- The hero to dress this player in: the last one chosen, if still owned.
function DataService:LastHero(player: Player): string
	local p = self:Get(player)
	local id = p.lastHero
	return if id and p.unlocked[id] then id else Roster.HeroOrder[1]
end

--- Studio test hook (DevService): unlock a hero for this session only. It
--- costs nothing and is left out of every save.
function DataService:DevUnlock(player: Player, heroId: string): boolean
	local p = self._profiles[player]
	if not p or not Roster.Heroes[heroId] or p.unlocked[heroId] then
		return false
	end
	p.unlocked[heroId] = true
	p.devUnlocked[heroId] = true
	self:Push(player)
	return true
end

--- Count a finished run and keep its bests. Returns whether it set a new best
--- kill count and a new best boss time, for the results screen.
function DataService:RecordRun(player: Player, heroId: string, kills: number, bossSeconds: number?): (boolean, boolean)
	local p = self._profiles[player]
	if not p then
		return false, false
	end
	p.runs[heroId] = (tonumber(p.runs[heroId]) or 0) + 1
	local bestKills, bestTime = false, false
	if kills > p.best.kills then
		p.best.kills = kills
		bestKills = true
	end
	if bossSeconds and (p.best.time == 0 or bossSeconds < p.best.time) then
		p.best.time = math.floor(bossSeconds)
		bestTime = true
	end
	self:Push(player)
	return bestKills, bestTime
end

function DataService:Save(player: Player)
	local p = self._profiles[player]
	if not p or not p.canSave or not self._store then
		return
	end
	local unlocked = {}
	for id, value in p.unlocked do
		if not p.devUnlocked[id] then
			unlocked[id] = value
		end
	end
	-- a hero only unlocked for a Studio session is not remembered either
	local lastHero = if p.lastHero and not p.devUnlocked[p.lastHero] then p.lastHero else nil
	local ok, err = pcall(function()
		self._store:SetAsync(
			"u" .. player.UserId,
			{ silver = p.silver, unlocked = unlocked, runs = p.runs, best = p.best, lastHero = lastHero, settings = p.settings }
		)
	end)
	if not ok then
		warn(`[DataService] save failed for {player.Name}: {err}`)
	end
end

return DataService

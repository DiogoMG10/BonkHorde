--!nonstrict
-- MenuController - the Menu ScreenGui (main menu, character select, map select)
-- and the EndScreens ScreenGui (the death screen and the results table).
--
-- The menu is up in the Lobby phase, and for a player who has no hero while a
-- run is live (a late joiner picks a hero and readies up to drop in). Every
-- button only asks: PickHero, UnlockHero, PickMap and SetReady are decided by
-- the server, and the screens redraw from the Roster and Profile it sends back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local UiKit = require(script.Parent.Parent.UiKit)

local MenuController = Knit.CreateController({ Name = "MenuController" })

local player = Players.LocalPlayer

local GRID_TILES = 20
local DEATH_SECONDS = 4 -- the death screen gives way to the results by itself
local WIPE_SECONDS = 2.5 -- the server holds Victory / Wipe this long before Results

function MenuController:KnitInit()
	self._m = {} -- Menu elements
	self._r = {} -- EndScreens elements
	self._templates = {}
	self._clones = { squad = {}, ready = {}, players = {} }
	self._screen = nil -- "main" | "hero" | "map" | nil when the menu is down
	self._selected = nil -- the hero the detail card shows
	self._heroTiles = {}
	self._mapRows = {}
	self._results = nil
	self._resultsDeadline = nil
	self._resultsStamp = nil
end

function MenuController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._camera = Knit.GetController("CameraController")
	UiKit.safe("MenuController", function()
		self:_startMenu()
	end)
	UiKit.safe("MenuController", function()
		self:_startEndScreens()
	end)
end

--- The local player's row of the roster, if the server has sent one.
function MenuController:_mine()
	for _, entry in self._state.roster.players do
		if entry.userId == player.UserId then
			return entry
		end
	end
	return nil
end

-- ================================================================ Menu

function MenuController:_startMenu()
	local gui = UiKit.gui("Menu")
	if not gui then
		return
	end
	self._menu = gui
	local state = self._state

	local function f(path: string): Instance?
		return UiKit.find(gui, path)
	end
	local m = self._m
	m.main = f("MainMenu")
	m.play = f("MainMenu.PlayButton")
	m.squadList = f("MainMenu.SquadList")
	m.silver = f("MainMenu.SilverTotal")
	m.version = f("MainMenu.VersionLabel")

	m.hero = f("CharacterSelect")
	m.heroClose = f("CharacterSelect.CloseButton")
	m.heroGrid = f("CharacterSelect.CharacterGrid")
	m.heroPortrait = f("CharacterSelect.DetailCard.Portrait")
	m.heroName = f("CharacterSelect.DetailCard.CharacterName")
	m.heroRuns = f("CharacterSelect.DetailCard.RunCount")
	m.heroBlurb = f("CharacterSelect.DetailCard.Blurb")
	m.weaponIcon = f("CharacterSelect.DetailCard.StartWeaponRow.Icon")
	m.weaponName = f("CharacterSelect.DetailCard.StartWeaponRow.Name")
	m.weaponText = f("CharacterSelect.DetailCard.StartWeaponRow.Text")
	m.passiveName = f("CharacterSelect.DetailCard.PassiveRow.Name")
	m.passiveText = f("CharacterSelect.DetailCard.PassiveRow.Text")
	m.unlock = f("CharacterSelect.DetailCard.UnlockButton")
	m.unlockLabel = f("CharacterSelect.DetailCard.UnlockButton.Label")
	m.heroConfirm = f("CharacterSelect.DetailCard.ConfirmButton")
	m.heroConfirmLabel = f("CharacterSelect.DetailCard.ConfirmButton.Label")

	m.map = f("MapSelect")
	m.mapClose = f("MapSelect.CloseButton")
	m.mapList = f("MapSelect.MapList")
	m.mapName = f("MapSelect.DetailCard.MapName")
	m.mapTier = f("MapSelect.DetailCard.TierLabel")
	m.highscore = f("MapSelect.DetailCard.Highscore")
	m.bestTime = f("MapSelect.DetailCard.BestTime")
	m.stageCount = f("MapSelect.DetailCard.StageCount")
	m.readyList = f("MapSelect.DetailCard.ReadyList")
	m.mapConfirm = f("MapSelect.DetailCard.ConfirmButton")
	m.mapConfirmLabel = f("MapSelect.DetailCard.ConfirmButton.Label")

	local t = self._templates
	t.squadRow = UiKit.template(m.squadList, "SquadRow")
	t.readyRow = UiKit.template(m.readyList, "ReadyRow")
	local portraitTile = UiKit.template(m.heroGrid, "PortraitTile")
	local lockedTile = UiKit.template(m.heroGrid, "LockedTile")
	local mapRow = UiKit.template(m.mapList, "MapRow")

	UiKit.text(m.version, GameConfig.BuildStamp)

	local pickHero, setReady = Net.client("PickHero"), Net.client("SetReady")
	local unlockHero, pickMap = Net.client("UnlockHero"), Net.client("PickMap")

	-- ------------------------------------------------------------ the hero grid

	if m.heroGrid then
		local order = 0
		if portraitTile then
			for _, id in Roster.HeroOrder do
				local hero = Roster.Heroes[id]
				order += 1
				local tile = portraitTile:Clone()
				tile.LayoutOrder = order
				UiKit.setIcon(UiKit.find(tile, "Portrait"), "Portrait" .. id)
				UiKit.text(UiKit.find(tile, "Name"), hero.name)
				UiKit.button(tile, function()
					self._selected = id
					self:_renderHero()
				end, true)
				tile.Parent = m.heroGrid
				self._heroTiles[id] = tile
			end
		end
		-- the rest of the grid is heroes that do not exist yet
		if lockedTile then
			for _ = order + 1, GRID_TILES do
				order += 1
				local tile = lockedTile:Clone()
				tile.LayoutOrder = order
				UiKit.text(UiKit.find(tile, "Name"), "??")
				if tile:IsA("GuiButton") then
					tile.Selectable = false
				end
				tile.Parent = m.heroGrid
			end
		end
	end

	-- ------------------------------------------------------------ the map list

	if m.mapList and mapRow then
		for i, id in Roster.MapOrder do
			local def = Roster.Maps[id]
			local row = mapRow:Clone()
			row.LayoutOrder = i
			UiKit.setIcon(UiKit.find(row, "Thumb"), "Thumb" .. id)
			UiKit.text(UiKit.find(row, "Name"), def.name)
			UiKit.text(UiKit.find(row, "Blurb"), def.blurb)
			UiKit.show(UiKit.find(row, "LockTag"), def.locked == true)
			UiKit.button(row, function()
				local mine = self:_mine()
				if pickMap and not def.locked and mine and mine.host then
					pickMap:FireServer(id)
				end
			end)
			row.Parent = m.mapList
			self._mapRows[id] = row
		end
	end

	UiKit.fillIcons(gui)

	-- ------------------------------------------------------------ buttons

	UiKit.button(m.play, function()
		self:_show("hero")
	end)
	UiKit.button(m.heroClose, function()
		self:_show("main")
	end)
	UiKit.button(m.mapClose, function()
		self:_show("hero")
	end)
	UiKit.button(m.unlock, function()
		local id = self._selected
		local hero = id and Roster.Heroes[id]
		local profile = state.profile
		if unlockHero and hero and profile and not profile.unlocked[id] and profile.silver >= hero.unlockSilver then
			unlockHero:FireServer(id)
		end
	end)
	UiKit.button(m.heroConfirm, function()
		local id = self._selected
		local profile = state.profile
		if not id or not profile or not profile.unlocked[id] then
			return
		end
		local mine = self:_mine()
		if mine and mine.hero ~= id then
			-- a readied pick is locked in on the server: step back out first
			if mine.ready and setReady then
				setReady:FireServer(false)
			end
			if pickHero then
				pickHero:FireServer(id)
			end
		end
		self:_show("map")
	end)
	UiKit.button(m.mapConfirm, function()
		local mine = self:_mine()
		if setReady then
			setReady:FireServer(not (mine and mine.ready))
		end
	end)

	state.Changed:Connect(function(key)
		UiKit.safe("MenuController", function()
			if key == "phase" or key == "me" then
				self:_applyMenu()
			elseif key == "roster" or key == "profile" then
				self:_renderMenu()
			end
		end)
	end)
	self:_applyMenu()
end

--- Should the menu be up at all?
function MenuController:_menuWanted(): boolean
	local state = self._state
	return state.phase == "Lobby" or (state.me == nil and state:IsLive())
end

function MenuController:_applyMenu()
	local wanted = self:_menuWanted()
	if wanted and not self._screen then
		self:_show("main")
	elseif not wanted and self._screen then
		self:_show(nil)
	end
end

function MenuController:_show(screen: string?)
	local m = self._m
	self._screen = screen
	self._menu.Enabled = screen ~= nil
	UiKit.show(m.main, screen == "main")
	UiKit.show(m.hero, screen == "hero")
	UiKit.show(m.map, screen == "map")
	self._camera:SetUiOpen("menu", screen ~= nil)
	if not screen then
		UiKit.unfocus(self._menu)
		return
	end
	if screen == "hero" and not self._selected then
		local mine = self:_mine()
		self._selected = if mine and Roster.Heroes[mine.hero] then mine.hero else Roster.HeroOrder[1]
	end
	self:_renderMenu()
	UiKit.focus(if screen == "main" then m.play elseif screen == "hero" then m.heroConfirm else m.mapConfirm)
end

function MenuController:_renderMenu()
	if not self._menu or not self._screen then
		return
	end
	if self._screen == "main" then
		self:_renderMain()
	elseif self._screen == "hero" then
		self:_renderHero()
	else
		self:_renderMap()
	end
end

function MenuController:_renderMain()
	local m = self._m
	local state = self._state
	local profile = state.profile
	UiKit.text(m.silver, UiKit.commas(profile and profile.silver or 0))

	local clones = self._clones.squad
	UiKit.clear(clones)
	if not m.squadList or not self._templates.squadRow then
		return
	end
	for i, entry in state.roster.players do
		local hero = Roster.Heroes[entry.hero]
		local row = self._templates.squadRow:Clone()
		row.LayoutOrder = i
		UiKit.setIcon(UiKit.find(row, "Portrait"), "Portrait" .. tostring(entry.hero))
		UiKit.text(UiKit.find(row, "Name"), tostring(entry.name))
		UiKit.text(UiKit.find(row, "Hero"), if hero then hero.name else tostring(entry.hero))
		UiKit.show(UiKit.find(row, "ReadyTag"), entry.ready == true)
		UiKit.show(UiKit.find(row, "HostTag"), entry.host == true)
		row.Parent = m.squadList
		table.insert(clones, row)
	end
end

function MenuController:_renderHero()
	local m = self._m
	local state = self._state
	local profile = state.profile
	local id = self._selected or Roster.HeroOrder[1]
	local hero = Roster.Heroes[id]
	if not hero then
		return
	end
	local unlocked = profile ~= nil and profile.unlocked[id] == true
	local silver = profile and profile.silver or 0

	for tileId, tile in self._heroTiles do
		local tileUnlocked = profile ~= nil and profile.unlocked[tileId] == true
		UiKit.show(UiKit.find(tile, "Focus"), tileId == id)
		UiKit.textColour(UiKit.find(tile, "Name"), if tileUnlocked then UiKit.Colours.ink else UiKit.Colours.grey)
	end

	local weapon = Roster.Weapons[hero.weapon]
	local runs = profile and profile.runs and tonumber(profile.runs[id]) or 0
	UiKit.setIcon(m.heroPortrait, "Portrait" .. id)
	UiKit.text(m.heroName, hero.name)
	UiKit.text(m.heroRuns, if runs == 1 then "1 Run" else `{runs} Runs`)
	UiKit.text(m.heroBlurb, hero.blurb)
	UiKit.setIcon(m.weaponIcon, "Icon" .. hero.weapon)
	UiKit.text(m.weaponName, if weapon then weapon.name else hero.weapon)
	UiKit.text(m.weaponText, if weapon then weapon.text else "")
	UiKit.text(m.passiveName, hero.passiveName)
	UiKit.text(m.passiveText, hero.passiveText)

	-- locked: the unlock button shows the price, red when it cannot be paid
	local affordable = silver >= hero.unlockSilver
	UiKit.show(m.unlock, not unlocked)
	UiKit.text(m.unlockLabel, `UNLOCK {UiKit.commas(hero.unlockSilver)}`)
	UiKit.textColour(m.unlockLabel, if affordable then UiKit.Colours.ink else UiKit.Colours.red)
	UiKit.text(m.heroConfirmLabel, if unlocked then "CONFIRM" else "LOCKED")
	UiKit.textColour(m.heroConfirmLabel, if unlocked then UiKit.Colours.ink else UiKit.Colours.soft)
end

function MenuController:_renderMap()
	local m = self._m
	local state = self._state
	local profile = state.profile
	local mapId = state.roster.map
	local def = Roster.Maps[mapId] or Roster.Maps[Roster.MapOrder[1]]

	for id, row in self._mapRows do
		UiKit.textColour(UiKit.find(row, "Name"), if id == mapId then UiKit.Colours.gold else UiKit.Colours.ink)
	end
	local best = profile and profile.best
	UiKit.text(m.mapName, def.name)
	UiKit.text(m.mapTier, "Tier 1")
	UiKit.text(m.highscore, UiKit.commas(best and best.kills or 0))
	UiKit.text(m.bestTime, if best and (best.time or 0) > 0 then UiKit.clock(best.time) else "--:--")
	UiKit.text(m.stageCount, "Stages: 1")

	local clones = self._clones.ready
	UiKit.clear(clones)
	if m.readyList and self._templates.readyRow then
		for i, entry in state.roster.players do
			local row = self._templates.readyRow:Clone()
			row.LayoutOrder = i
			UiKit.text(UiKit.find(row, "Name"), tostring(entry.name))
			local label = UiKit.find(row, "State")
			UiKit.text(label, if entry.ready then "ready" else "choosing")
			UiKit.textColour(label, if entry.ready then UiKit.Colours.green else UiKit.Colours.soft)
			row.Parent = m.readyList
			table.insert(clones, row)
		end
	end

	local mine = self:_mine()
	UiKit.text(m.mapConfirmLabel, if mine and mine.ready then "CANCEL" else "READY")
end

-- ================================================================ EndScreens

function MenuController:_startEndScreens()
	local gui = UiKit.gui("EndScreens")
	if not gui then
		return
	end
	self._end = gui
	local state = self._state

	local function f(path: string): Instance?
		return UiKit.find(gui, path)
	end
	local r = self._r
	r.death = f("DeathScreen")
	r.deathTitle = f("DeathScreen.DeathTitle")
	r.deathJoke = f("DeathScreen.DeathJoke")
	r.deathConfirm = f("DeathScreen.ConfirmButton")
	r.results = f("Results")
	r.title = f("Results.ResultTitle")
	r.kills = f("Results.StatTable.Kills.Value")
	r.level = f("Results.StatTable.Level.Value")
	r.time = f("Results.StatTable.Time.Value")
	r.bossTime = f("Results.StatTable.BossTime.Value")
	r.rows = f("Results.PlayerRows")
	r.continue = f("Results.ContinueLabel")
	self._templates.playerRow = UiKit.template(r.rows, "PlayerRow")

	UiKit.fillIcons(gui)
	UiKit.show(r.death, false)
	UiKit.show(r.results, false)

	UiKit.button(r.deathConfirm, function()
		self:_showResults()
	end)

	local results = Net.client("Results")
	if results then
		results.OnClientEvent:Connect(function(data)
			UiKit.safe("MenuController.Results", function()
				if typeof(data) ~= "table" then
					return
				end
				self._results = data
				self._resultsDeadline = os.clock() + WIPE_SECONDS + GameConfig.ResultsSeconds
				self._camera:SetUiOpen("results", true)
				if data.victory then
					self:_showResults()
				else
					self:_showDeath()
				end
			end)
		end)
	end

	state.Changed:Connect(function(key)
		if key ~= "phase" then
			return
		end
		UiKit.safe("MenuController", function()
			if state.phase == "Results" then
				-- the server's own countdown to the lobby starts now
				self._resultsDeadline = os.clock() + GameConfig.ResultsSeconds
			elseif state.phase == "Lobby" or state.phase == "Intro" then
				self:_hideEnd()
			end
		end)
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local deadline = self._resultsDeadline
		if deadline and r.results and r.results.Visible then
			UiKit.text(r.continue, `Back to the lobby in {math.max(0, math.ceil(deadline - os.clock()))}`)
		end
	end)
end

function MenuController:_hideEnd()
	local r = self._r
	self._results = nil
	self._resultsDeadline = nil
	self._resultsStamp = nil
	UiKit.show(r.death, false)
	UiKit.show(r.results, false)
	UiKit.unfocus(self._end)
	self._camera:SetUiOpen("results", false)
end

function MenuController:_showDeath()
	local r = self._r
	local data = self._results
	UiKit.text(r.deathTitle, "you got bonked")
	UiKit.text(r.deathJoke, tostring(data.joke or ""))
	UiKit.show(r.results, false)
	UiKit.show(r.death, true)
	UiKit.focus(r.deathConfirm)
	local stamp = os.clock()
	self._resultsStamp = stamp
	task.delay(DEATH_SECONDS, function()
		if self._resultsStamp == stamp and self._results == data then
			UiKit.safe("MenuController", function()
				self:_showResults()
			end)
		end
	end)
end

function MenuController:_showResults()
	local r = self._r
	local data = self._results
	if not data then
		return
	end
	self._resultsStamp = nil
	UiKit.text(r.title, if data.victory then "VICTORY" else "BONKED")
	UiKit.textColour(r.title, if data.victory then UiKit.Colours.gold else UiKit.Colours.red)
	UiKit.text(r.kills, UiKit.commas(data.kills))
	UiKit.text(r.level, `LVL {data.level or 1}`)
	UiKit.text(r.time, UiKit.clock(data.clock or 0))
	UiKit.text(r.bossTime, if data.bossTime then UiKit.clock(data.bossTime) else "--:--")

	local clones = self._clones.players
	UiKit.clear(clones)
	if r.rows and self._templates.playerRow then
		for i, row in data.players or {} do
			local line = self._templates.playerRow:Clone()
			line.LayoutOrder = i
			UiKit.setIcon(UiKit.find(line, "Portrait"), "Portrait" .. tostring(row.hero))
			UiKit.text(UiKit.find(line, "Name"), tostring(row.name))
			UiKit.text(UiKit.find(line, "Kills"), UiKit.commas(row.kills))
			UiKit.text(UiKit.find(line, "Damage"), UiKit.commas(row.damage))
			UiKit.text(UiKit.find(line, "Silver"), "+" .. UiKit.commas(row.silver))
			line.Parent = r.rows
			table.insert(clones, line)
		end
	end
	local deadline = self._resultsDeadline
	UiKit.text(r.continue, `Back to the lobby in {math.max(0, math.ceil((deadline or os.clock()) - os.clock()))}`)
	UiKit.show(r.death, false)
	UiKit.show(r.results, true)
end

return MenuController

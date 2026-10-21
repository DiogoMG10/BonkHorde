--!nonstrict
-- MenuController - the Menu ScreenGui (main menu, character select, map select)
-- and the EndScreens ScreenGui (the death screen and the results).
--
-- The menu is up in the Lobby phase, and for a player who has no hero while a
-- run is live (a late joiner picks a hero and readies up to drop in). Every
-- button only asks: PickHero, UnlockHero, PickMap and SetReady are decided by
-- the server, and the screens redraw from the Roster and Profile it sends back.
--
-- A run's end (T3): a wipe shows the death screen for a few seconds (SKIP for
-- sooner), then the results; a victory goes straight to the results. Rewards
-- are already paid and saved by then. CONTINUE tells the server this player is
-- done: solo that is the squad, so it is back to the lobby at once; in co-op
-- the squad goes when everyone still here has pressed, or when the server's
-- fallback time runs out. SKIP and CONTINUE ignore input for a moment when
-- their screen lands, then answer only a fresh press (T1's Core/InputGuard).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local InputGuard = require(ReplicatedStorage.Shared.Core.InputGuard)
local Net = require(ReplicatedStorage.Shared.Net)
local PanelLayout = require(ReplicatedStorage.Shared.Core.PanelLayout)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local UiKit = require(script.Parent.Parent.UiKit)

local MenuController = Knit.CreateController({ Name = "MenuController" })

local player = Players.LocalPlayer

local GRID_TILES = 20
local VICTORY_INK = Color3.fromHex("#FFCB45")
local DEFEAT_INK = Color3.fromHex("#F2554D")
local RIM = Color3.fromHex("#D9B85C")
local GOLD = Color3.fromHex("#FFCB45")
local INK = Color3.fromHex("#FFF7E8")
local SOFT = Color3.fromHex("#D7CFBC")
local GOLD_FILL = Color3.fromHex("#B98A2C")
local QUIET_FILL = Color3.fromHex("#111A15")
local GOLD_RIM = Color3.fromHex("#FFE3A3")
-- the parts of a run that pay Silver (Core/Progress.silver), as the results name them
local SILVER_PARTS = {
	{ "stage", "Survival" },
	{ "kills", "Kills" },
	{ "minibosses", "Minibosses" },
	{ "boss", "Boss" },
	{ "escape", "Escape" },
	{ "overtime", "Overtime" },
}

-- one name per physical input; each finger on a touch screen is its own
local function inputKey(input: InputObject): any
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch then
		return input
	elseif kind == Enum.UserInputType.Keyboard or string.sub(kind.Name, 1, 7) == "Gamepad" then
		return input.KeyCode
	end
	return kind
end

local function trim(n: number): string
	local s = string.format("%.1f", n)
	s = string.gsub(s, "%.0$", "")
	return s
end

function MenuController:KnitInit()
	self._m = {} -- Menu elements
	self._r = {} -- EndScreens elements
	self._templates = {}
	self._clones = { squad = {}, ready = {}, players = {} }
	self._screen = nil -- "main" | "hero" | "map" | nil when the menu is down
	self._selected = nil -- the hero the detail card shows
	self._heroTiles = {}
	self._mapRows = {}
	self._results = nil -- the last run's results, as the server sent them
	self._resultsDeadline = nil -- when the server's fallback sends everyone to the lobby
	self._resultsStamp = nil -- the death screen on display (its auto-advance checks it)
	self._endGuard = InputGuard.new() -- SKIP and CONTINUE answer only a fresh press
	self._continued = false -- this player pressed CONTINUE on these results
	self._ready = {} -- userIds done with these results (ResultsReady)
	self._readyNeed = 0
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
	m.settings = f("MainMenu.SettingsButton")
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
	UiKit.button(m.settings, function()
		Knit.GetController("OverlayController"):OpenSettings(m.settings)
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
	r.deathSafe = f("DeathScreen.Safe")
	r.deathTitle = f("DeathScreen.Safe.Stage.DeathTitle")
	r.deathJoke = f("DeathScreen.Safe.Stage.DeathJoke")
	r.viewport = f("DeathScreen.Safe.Stage.HeroViewport")
	r.skip = f("DeathScreen.Safe.Stage.SkipButton")
	r.skipKey = f("DeathScreen.Safe.Stage.SkipButton.KeyCap")
	r.autoFill = f("DeathScreen.Safe.Stage.AutoBar.Fill")
	r.results = f("Results")
	r.resultsSafe = f("Results.Safe")
	r.panel = f("Results.Safe.Panel")
	r.title = f("Results.Safe.Panel.ResultTitle")
	r.subtitle = f("Results.Safe.Panel.Subtitle")
	r.kills = f("Results.Safe.Panel.StatTable.Kills.Value")
	r.killsBest = f("Results.Safe.Panel.StatTable.Kills.Best")
	r.level = f("Results.Safe.Panel.StatTable.Level.Value")
	r.time = f("Results.Safe.Panel.StatTable.Time.Value")
	r.bossLabel = f("Results.Safe.Panel.StatTable.BossTime.Label")
	r.bossTime = f("Results.Safe.Panel.StatTable.BossTime.Value")
	r.bossBest = f("Results.Safe.Panel.StatTable.BossTime.Best")
	r.silverCard = f("Results.Safe.Panel.SilverCard")
	r.silverAmount = f("Results.Safe.Panel.SilverCard.Amount")
	r.silverTotal = f("Results.Safe.Panel.SilverCard.Total")
	r.breakdown = f("Results.Safe.Panel.SilverCard.Breakdown")
	r.gain = f("Results.Safe.Panel.SilverCard.Gain")
	r.rows = f("Results.Safe.Panel.Squad.PlayerRows")
	r.continueButton = f("Results.Safe.Panel.ContinueButton")
	r.continueText = f("Results.Safe.Panel.ContinueButton.Label")
	r.continueKey = f("Results.Safe.Panel.ContinueButton.KeyCap")
	r.continue = f("Results.Safe.Panel.ContinueLabel")
	self._templates.playerRow = UiKit.template(r.rows, "PlayerRow")
	self._templates.part = UiKit.template(r.breakdown, "Part")
	self._clones.parts = {}

	UiKit.fillIcons(gui)
	UiKit.show(r.death, false)
	UiKit.show(r.results, false)

	-- a press that began before (or during) a screen's lock never answers it
	local guard = self._endGuard
	UserInputService.InputBegan:Connect(function(input)
		guard:press(inputKey(input), os.clock())
	end)
	UserInputService.InputEnded:Connect(function(input)
		guard:release(inputKey(input), os.clock())
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		guard:dropHeld()
	end)

	UiKit.button(r.skip, function(input)
		if self:_endAccepts(input) then
			self:_showResults()
		end
	end)
	UiKit.button(r.continueButton, function(input)
		if self:_endAccepts(input) then
			self:_continue()
		end
	end)
	-- Enter or Space presses whichever end screen is up
	UserInputService.InputBegan:Connect(function(input, processed)
		local key = input.KeyCode
		if processed or (key ~= Enum.KeyCode.Return and key ~= Enum.KeyCode.Space) then
			return
		end
		UiKit.safe("MenuController.endKey", function()
			if not self:_endAccepts(input) then
				return
			end
			if r.death and r.death.Visible then
				self:_showResults()
			elseif r.results and r.results.Visible then
				self:_continue()
			end
		end)
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		UiKit.safe("MenuController.keys", function()
			self:_renderEndKeys()
		end)
	end)

	local results = Net.client("Results")
	self._continueRemote = Net.client("ResultsContinue")
	if results then
		results.OnClientEvent:Connect(function(data)
			UiKit.safe("MenuController.Results", function()
				if typeof(data) ~= "table" then
					return
				end
				self._results = data
				self._continued = false
				self._ready = {}
				self._readyNeed = #(data.players or {})
				self._resultsDeadline = os.clock() + GameConfig.EndHoldSeconds + GameConfig.ResultsSeconds
				self._camera:SetUiOpen("results", true)
				if data.victory then
					self:_showResults()
				else
					self:_showDeath()
				end
			end)
		end)
	end
	local readyEvent = Net.client("ResultsReady")
	if readyEvent then
		readyEvent.OnClientEvent:Connect(function(p)
			UiKit.safe("MenuController.ResultsReady", function()
				local data = self._results
				if typeof(p) ~= "table" or not data or p.run ~= data.run then
					return -- another run's word
				end
				local before = self._ready
				self._ready = if typeof(p.ready) == "table" then p.ready else {}
				self._readyNeed = tonumber(p.need) or self._readyNeed
				self:_renderReady(before)
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

	UiKit.ownScale(gui, function()
		self:_layoutEnd()
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		if r.results and r.results.Visible then
			UiKit.safe("MenuController.status", function()
				self:_renderStatus()
			end)
		end
	end)
end

--- May this press (from a button's Activated or a key; nil when unknown)
--- answer the end screen on display?
function MenuController:_endAccepts(input: InputObject?): boolean
	local key = if input then inputKey(input) else nil
	return self._endGuard:accepts(key, os.clock())
end

--- Each end screen is drawn as large as fits the screen (Core/PanelLayout).
function MenuController:_layoutEnd()
	local gui, r = self._end, self._r
	if not gui then
		return
	end
	local screen = UiKit.insets()
	local need = if r.death and r.death.Visible then PanelLayout.Death else PanelLayout.Results
	local L = PanelLayout.fit(screen, need.width, need.height)
	local scale = UiKit.scaleOf(gui)
	if scale and math.abs(scale.Scale - L.scale) > 1e-4 then
		scale.Scale = L.scale
	end
	for _, pair in { { r.death, r.deathSafe }, { r.results, r.resultsSafe } } do
		local screenFrame, safe = pair[1], pair[2]
		if screenFrame and screenFrame:IsA("GuiObject") then
			screenFrame.Size = UDim2.fromOffset(math.ceil(screen.width / L.scale), math.ceil(screen.height / L.scale))
		end
		if safe and safe:IsA("GuiObject") then
			safe.Position = UDim2.fromOffset(math.floor(L.safe.x + 0.5), math.floor(L.safe.y + 0.5))
			safe.Size = UDim2.fromOffset(math.floor(L.safe.w + 0.5), math.floor(L.safe.h + 0.5))
		end
	end
end

function MenuController:_hideEnd()
	local r = self._r
	self._results = nil
	self._resultsDeadline = nil
	self._resultsStamp = nil
	self._countStamp = nil
	self._continued = false
	self._ready = {}
	self._endGuard:clear()
	UiKit.show(r.death, false)
	UiKit.show(r.results, false)
	UiKit.unfocus(self._end)
	self._camera:SetUiOpen("results", false)
end

-- The fallen hero, slumped in the middle of the death screen, lit from above.
function MenuController:_deathHero(viewport: Instance?)
	if not viewport or not viewport:IsA("ViewportFrame") then
		return
	end
	viewport:ClearAllChildren()
	local heroId = Roster.HeroOrder[1]
	for _, entry in self._state.roster.players do
		if entry.userId == Players.LocalPlayer.UserId then
			heroId = entry.hero
		end
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assets:FindFirstChild("Heroes") and assets.Heroes:FindFirstChild("Hero" .. heroId)
	if not source then
		return
	end
	local model = source:Clone()
	-- slumped forward and sunk a little, as if on one knee
	model:PivotTo(CFrame.new(0, -0.6, 0) * CFrame.Angles(math.rad(-24), math.rad(18), 0))
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, -13), Vector3.new(0, -0.2, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Ambient = Color3.fromRGB(70, 80, 95)
	viewport.LightColor = Color3.fromRGB(235, 240, 255)
	viewport.LightDirection = Vector3.new(0.2, -1, 0.5)
end

--- A short grow-and-settle on one element (scaled about its anchor point).
local function pop(inst: Instance?, from: number, seconds: number?)
	if not inst or not inst:IsA("GuiObject") then
		return
	end
	local scale = inst:FindFirstChild("Pop")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = inst
	end
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(seconds or 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function MenuController:_showDeath()
	local r = self._r
	local data = self._results
	UiKit.text(r.deathTitle, "you got bonked")
	UiKit.text(r.deathJoke, tostring(data.joke or ""))
	UiKit.show(r.results, false)
	UiKit.show(r.death, true)
	self:_layoutEnd()
	self._endGuard:lock(GameConfig.EndScreenLockSeconds, os.clock())
	UiKit.focus(r.skip)
	self:_renderEndKeys()
	pop(r.deathTitle, 0.85, 0.4)
	UiKit.safe("death hero", function()
		self:_deathHero(r.viewport)
	end)
	-- the bar under SKIP runs down to the moment the results come by themselves
	local fill = r.autoFill
	if fill and fill:IsA("GuiObject") then
		fill.Size = UDim2.fromScale(1, 1)
		TweenService:Create(fill, TweenInfo.new(GameConfig.DeathScreenSeconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
			:Play()
	end
	local stamp = os.clock()
	self._resultsStamp = stamp
	task.delay(GameConfig.DeathScreenSeconds, function()
		if self._resultsStamp == stamp and self._results == data then
			UiKit.safe("MenuController", function()
				self:_showResults()
			end)
		end
	end)
end

--- The local player's row of the results, if they were in the run.
function MenuController:_myRow()
	for _, row in (self._results and self._results.players) or {} do
		if row.userId == player.UserId then
			return row
		end
	end
	return nil
end

function MenuController:_showResults()
	local r = self._r
	local data = self._results
	if not data then
		return
	end
	local fromDeath = r.death and r.death.Visible
	self._resultsStamp = nil
	local mine = self:_myRow()
	local map = Roster.Maps[data.map] or Roster.Maps[Roster.MapOrder[1]]
	local hero = mine and Roster.Heroes[mine.hero]

	UiKit.text(r.title, if data.victory then "VICTORY" else "BONKED")
	UiKit.textColour(r.title, if data.victory then VICTORY_INK else DEFEAT_INK)
	local words = { map.name }
	if hero then
		table.insert(words, hero.name)
	end
	table.insert(words, UiKit.clock(data.clock or 0))
	UiKit.text(r.subtitle, table.concat(words, "  ·  "))
	UiKit.text(r.kills, UiKit.commas(data.kills))
	UiKit.text(r.level, `LVL {data.level or 1}`)
	UiKit.text(r.time, UiKit.clock(data.clock or 0))
	if data.bossTime then
		UiKit.text(r.bossLabel, "Boss down at")
		UiKit.text(r.bossTime, UiKit.clock(data.bossTime))
	else
		UiKit.text(r.bossLabel, "Minibosses")
		UiKit.text(r.bossTime, tostring(data.minibosses or 0))
	end
	local best = mine and mine.best or {}
	UiKit.show(r.killsBest, best.kills == true)
	UiKit.show(r.bossBest, best.time == true and data.bossTime ~= nil)

	self:_renderSilver(mine)
	self:_renderRows()
	self:_renderReady(nil)

	UiKit.show(r.death, false)
	UiKit.show(r.results, true)
	self:_layoutEnd()
	self._endGuard:lock(GameConfig.EndScreenLockSeconds, os.clock())
	UiKit.focus(r.continueButton)
	self:_renderEndKeys()
	pop(r.panel, if fromDeath then 0.94 else 0.9, 0.32)
	pop(r.title, 0.7, 0.45)
	if best.kills or best.time then
		task.delay(0.5, function()
			pop(r.killsBest, 1.6, 0.35)
			pop(r.bossBest, 1.6, 0.35)
		end)
	end
end

--- Silver: what this run paid, what each part of the run was worth, and the
--- new total. The numbers are the server's (Core/Progress.silver).
function MenuController:_renderSilver(mine)
	local r = self._r
	local data = self._results
	self._countStamp = nil
	UiKit.show(r.silverCard, mine ~= nil)
	if not mine then
		return
	end
	local clones = self._clones.parts
	UiKit.clear(clones)
	local raw = data.silverParts or {}
	if r.breakdown and self._templates.part then
		local order = 0
		for _, part in SILVER_PARTS do
			local value = tonumber(raw[part[1]]) or 0
			-- survival and kills always show; the rest only when they paid
			if value > 0 or part[1] == "stage" or part[1] == "kills" then
				order += 1
				local row = self._templates.part:Clone()
				row.LayoutOrder = order
				UiKit.text(row:FindFirstChild("Label"), part[2])
				UiKit.text(row:FindFirstChild("Value"), "+" .. trim(value))
				row.Parent = r.breakdown
				table.insert(clones, row)
			end
		end
	end
	local gain = tonumber(mine.gain) or 1
	local cap = tonumber(data.silverCap) or GameConfig.SilverRunCap
	local notes = {}
	if math.abs(gain - 1) > 1e-3 then
		table.insert(notes, `x{trim(gain)} Silver Gain`)
	end
	table.insert(notes, if (mine.silver or 0) >= cap then `capped at {cap} a run` else `a run pays at most {cap}`)
	UiKit.text(r.gain, table.concat(notes, "  ·  "))
	local profile = self._state.profile
	UiKit.text(r.silverTotal, if profile then `You have {UiKit.commas(profile.silver)}` else "")

	-- the reward counts up
	local target = tonumber(mine.silver) or 0
	local started = os.clock()
	self._countStamp = started
	UiKit.text(r.silverAmount, "+0")
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if self._countStamp ~= started then
			conn:Disconnect()
			return
		end
		local t = math.min((os.clock() - started) / 0.8, 1)
		local eased = 1 - (1 - t) ^ 3
		UiKit.text(r.silverAmount, "+" .. UiKit.commas(math.floor(target * eased + 0.5)))
		if t >= 1 then
			conn:Disconnect()
			pop(r.silverAmount, 1.25, 0.3)
		end
	end)
end

function MenuController:_renderRows()
	local r = self._r
	local data = self._results
	local clones = self._clones.players
	UiKit.clear(clones)
	self._rowByUser = {}
	if not r.rows or not self._templates.playerRow then
		return
	end
	for i, row in data.players or {} do
		local line = self._templates.playerRow:Clone()
		line.LayoutOrder = i
		local hero = Roster.Heroes[row.hero]
		UiKit.setIcon(line:FindFirstChild("Portrait"), "Portrait" .. tostring(row.hero))
		UiKit.text(line:FindFirstChild("Name"), tostring(row.name))
		UiKit.text(line:FindFirstChild("Hero"), if hero then hero.name else tostring(row.hero))
		UiKit.text(line:FindFirstChild("Kills"), UiKit.commas(row.kills))
		UiKit.text(line:FindFirstChild("Damage"), UiKit.commas(row.damage))
		UiKit.text(line:FindFirstChild("Gold"), UiKit.commas(row.gold))
		UiKit.text(line:FindFirstChild("Silver"), "+" .. UiKit.commas(row.silver))
		UiKit.show(line:FindFirstChild("ReadyTag"), false)
		local stroke = line:FindFirstChild("Stroke")
		if stroke and stroke:IsA("UIStroke") then
			local own = row.userId == player.UserId
			stroke.Color = if own then GOLD else RIM
			stroke.Transparency = if own then 0.3 else 0.8
		end
		line.Parent = r.rows
		table.insert(clones, line)
		self._rowByUser[row.userId] = line
	end
end

--- Who has pressed CONTINUE: a check on their row, popping in as it arrives.
function MenuController:_renderReady(before)
	for userId, line in self._rowByUser or {} do
		local ready = table.find(self._ready, userId) ~= nil
		local tag = line:FindFirstChild("ReadyTag")
		UiKit.show(tag, ready)
		if ready and before and not table.find(before, userId) then
			pop(tag, 1.8, 0.3)
		end
	end
	self:_renderStatus()
end

--- This player is done with the results. Sent once; the server checks that it
--- names this run and comes from someone who was in it.
function MenuController:_continue()
	local data = self._results
	if not data or self._continued then
		return
	end
	self._continued = true
	if self._continueRemote then
		self._continueRemote:FireServer(data.run)
	end
	pop(self._r.continueButton, 0.92, 0.25)
	self:_renderStatus()
end

--- The CONTINUE button and the line beside it: what pressing does, who the
--- squad is waiting for, and the fallback countdown.
function MenuController:_renderStatus()
	local r = self._r
	if not self._results then
		return
	end
	local left = math.max(0, math.ceil((self._resultsDeadline or os.clock()) - os.clock()))
	local need = math.max(self._readyNeed, 1)
	local ready = #self._ready
	if self._continued and not table.find(self._ready, player.UserId) then
		ready += 1 -- ours is on its way
	end
	local solo = need <= 1
	local caption, line
	if not self._continued then
		caption = "CONTINUE"
		line = if solo or ready == 0 then `Back to the lobby in {left}` else `{ready}/{need} ready  ·  back to the lobby in {left}`
	elseif solo then
		caption, line = "CONTINUE", "Back to the lobby..."
	else
		caption = `READY  {ready}/{need}`
		local waiting = need - ready
		line = if waiting > 0 then `Waiting for {waiting} more  ·  back in {left}` else "Back to the lobby..."
	end
	UiKit.text(r.continueText, caption)
	UiKit.text(r.continue, line)
	local button = r.continueButton
	if button and button:IsA("GuiObject") then
		button.BackgroundColor3 = if self._continued then QUIET_FILL else GOLD_FILL
		local stroke = button:FindFirstChild("Stroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Color = if self._continued then RIM else GOLD_RIM
		end
		UiKit.textColour(r.continueText, if self._continued then SOFT else INK)
	end
end

--- The key printed on SKIP and CONTINUE follows the last input (none on touch).
function MenuController:_renderEndKeys()
	local r = self._r
	local last = UserInputService:GetLastInputType()
	local pad = string.sub(last.Name, 1, 7) == "Gamepad"
	local touch = last == Enum.UserInputType.Touch
	for _, cap in { r.skipKey, r.continueKey } do
		UiKit.text(cap, if pad then "A" else "Enter")
		UiKit.show(cap, not touch)
	end
	-- a gamepad picked up mid-screen lands on the button
	if pad and GuiService.SelectedObject == nil then
		if r.death and r.death.Visible then
			UiKit.focus(r.skip)
		elseif r.results and r.results.Visible then
			UiKit.focus(r.continueButton)
		end
	end
end

return MenuController

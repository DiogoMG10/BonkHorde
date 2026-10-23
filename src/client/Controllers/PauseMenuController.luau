--!nonstrict
-- PauseMenuController - the Pause ScreenGui: the build with its inspector, the
-- actions, the stats sheet, the settings and the map, in one menu (T3).
--
-- OverlayController decides when it is open and in which mode: it owns the
-- pause vote, the notice and the 3-2-1. This controller draws the menu and
-- turns its buttons into OverlayController's requests; nothing here changes
-- the run.
--
--   pause     the run is paused: solo at once, co-op once everyone agreed
--   inspect   co-op without a pause: the world keeps running and the menu
--             says so; REQUEST PAUSE asks the squad (PauseService's vote), and
--             closing the menu never takes a request or a vote back
--   settings  outside a run: the settings alone (the main menu's SETTINGS)
--
-- Layout (Core/PanelLayout): three columns (build, actions, stats) wherever
-- they stay legible; otherwise a rail of actions beside BUILD / STATS /
-- SETTINGS tabs. The inspector reads Core/Inspect, so every number shown is
-- the server's. Pointing at, tapping or selecting a tile fills the details
-- card, and the card keeps showing it until another tile is chosen.
--
-- While the menu is open it takes the gamepad's B (back), LB / RB (columns or
-- tabs), X and the E key (nothing is used from behind a menu). Settings live
-- as PlayerGui attributes (OverlayController keeps them in the profile).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Inspect = require(ReplicatedStorage.Shared.Core.Inspect)
local Net = require(ReplicatedStorage.Shared.Net)
local PanelLayout = require(ReplicatedStorage.Shared.Core.PanelLayout)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local UiKit = require(script.Parent.Parent.UiKit)

local PauseMenuController = Knit.CreateController({ Name = "PauseMenuController" })

local INK = Color3.fromHex("#FFF7E8")
local SOFT = Color3.fromHex("#D7CFBC")
local RIM = Color3.fromHex("#D9B85C")
local TEAL = Color3.fromHex("#63D2C1")
local GOLD = Color3.fromHex("#FFCB45")
local DONE = Color3.fromHex("#7BD957")
local DOWN = Color3.fromHex("#FF9C8A")
local WARN = Color3.fromHex("#FFB347")
local CALM = Color3.fromHex("#7FD6C2")
local DANGER = Color3.fromHex("#FF6A4D")
local WARN_BG = Color3.fromHex("#3A2A0E")
local CALM_BG = Color3.fromHex("#14302B")
local TONE = { up = DONE, down = DOWN, harder = WARN }
-- fill, rim, rim transparency, label ink (as Screens_build.py builds them)
local STYLE = {
	gold = { Color3.fromHex("#B98A2C"), Color3.fromHex("#FFE3A3"), 0.2, INK },
	quiet = { Color3.fromHex("#111A15"), RIM, 0.72, SOFT },
	danger = { Color3.fromHex("#5E231D"), DANGER, 0.35, INK },
	tab = { Color3.fromHex("#22301F"), GOLD, 0, GOLD },
}

-- design sizes: design/ui_specs/Screens_build.py builds the menu with the same
local MARGIN = PanelLayout.Margin
local BUILD_W, CENTRE_W, STATS_W = 560, 520, 470
local COL_H_MAX, SPAN_MAX = 980, 1860
local WEAPON_TILE, TILE_GAP = 92, 12
local ITEM_TILE = 64
local DETAILS_H, GRID_Y = 310, 354
local RAIL_W, TABS_H = 300, 52
local TAB_TILE, TAB_ITEM, TAB_LEFT = 84, 60, 400
local MAP_W = 720
local SETTINGS_W = 460

local SCRIM_PAUSED, SCRIM_RUNNING = 0.38, 0.62
local FADE_IN, FADE_OUT = 0.18, 0.22
local RESUME_SECONDS = GameConfig.PauseResumeSeconds
local AUTO_WARNING = 10 -- seconds of warning before a co-op pause resumes on its own
local SENS_MIN, SENS_MAX = 0.2, 2
local PAD_STEP = 0.05
local SINK = "BonkPauseMenu"

local function signature(list, a: string, b: string): string
	local parts = table.create(#list)
	for i, entry in list do
		parts[i] = `{entry[a]}:{entry[b]}`
	end
	return table.concat(parts, ",")
end

local function setOffset(inst: Instance?, prop: string, x: number, y: number)
	if inst and inst:IsA("GuiObject") then
		local value = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
		if inst[prop] ~= value then
			inst[prop] = value
		end
	end
end

local function place(inst: Instance?, position: UDim2, anchor: Vector2?)
	if inst and inst:IsA("GuiObject") then
		inst.Position = position
		inst.AnchorPoint = anchor or Vector2.zero
	end
end

local function textSize(inst: Instance?, px: number)
	if not inst then
		return
	end
	local fit = inst:FindFirstChild("Fit")
	if fit and fit:IsA("UITextSizeConstraint") then
		fit.MaxTextSize = px
	elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
		inst.TextSize = px
	end
end

local function levelTag(level: number?): string
	return if (level or 1) >= GameConfig.UpgradeMaxLevel then "MAX" else `LVL {level or 1}`
end

local function plural(n: number, word: string): string
	return if n == 1 then `1 {word}` else `{n} {word}s`
end

--- Larger for a larger preferred text size, and on a TV (as the Hud).
local function textBoost(): number
	local boost = 1
	local ok, size = pcall(function()
		return (GuiService :: any).PreferredTextSize
	end)
	if ok and typeof(size) == "EnumItem" then
		boost = ({ Large = 1.08, Larger = 1.16, Largest = 1.25 })[size.Name] or 1
	end
	if GuiService:IsTenFootInterface() then
		boost *= 1.15
	end
	return boost
end

function PauseMenuController:KnitInit()
	self._e = {}
	self._mode = nil -- nil | "pause" | "inspect" | "settings"
	self._view = "main" -- "main" | "settings" | "map"
	self._tab = "build" -- the tabs arrangement's page: "build" | "stats" | "settings"
	self._arrangement = "wide"
	self._weaponSlots = {}
	self._tomeSlots = {}
	self._itemTiles = {}
	self._itemSig = nil
	self._statValues = {}
	self._statContainers = {}
	self._lines = {}
	self._inspected = nil -- { kind, id }: what the details card shows
	self._sliders = {}
	self._dragging = nil
	self._fadeStamp = 0
	self._edgeTweens = {}
end

function PauseMenuController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._overlay = Knit.GetController("OverlayController")
	self._minimap = Knit.GetController("MinimapController")
	UiKit.safe("PauseMenuController", function()
		self:_start()
	end)
end

--- Is the menu on screen?
function PauseMenuController:IsOpen(): boolean
	return self._mode ~= nil
end

--- Has the Pause ScreenGui arrived and been wired (it can take a moment at join)?
function PauseMenuController:Ready(): boolean
	return self._e.root ~= nil
end

function PauseMenuController:Mode(): string?
	return self._mode
end

-- ================================================================ setup

function PauseMenuController:_start()
	local gui = UiKit.gui("Pause")
	if not gui then
		return
	end
	self._gui = gui
	local function f(path: string): Instance?
		return UiKit.find(gui, "Root." .. path)
	end
	local e = self._e
	e.root = UiKit.find(gui, "Root")
	e.scrim = f("Scrim")
	e.edge = f("Edge")
	e.safe = f("Safe")

	e.build = f("Safe.Build")
	e.buildTitle = f("Safe.Build.Title")
	e.counts = f("Safe.Build.Counts")
	e.buildRule = f("Safe.Build.Rule")
	e.weaponsCaption = f("Safe.Build.WeaponsCaption")
	e.weaponRow = f("Safe.Build.WeaponRow")
	e.tomesCaption = f("Safe.Build.TomesCaption")
	e.tomeRow = f("Safe.Build.TomeRow")
	e.itemsCaption = f("Safe.Build.ItemsCaption")
	e.itemGrid = f("Safe.Build.ItemGrid")
	e.noItems = f("Safe.Build.NoItems")
	e.details = f("Safe.Build.Details")
	e.detailTile = f("Safe.Build.Details.IconTile")
	e.detailIcon = f("Safe.Build.Details.IconTile.Icon")
	e.detailName = f("Safe.Build.Details.Name")
	e.detailTags = f("Safe.Build.Details.Tags")
	e.kindTag = f("Safe.Build.Details.Tags.KindTag")
	e.levelTag = f("Safe.Build.Details.Tags.LevelTag")
	e.detailText = f("Safe.Build.Details.Text")
	e.detailLines = f("Safe.Build.Details.Lines")
	e.detailNote = f("Safe.Build.Details.Note")
	e.detailEmpty = f("Safe.Build.Details.Empty")

	e.centre = f("Safe.Centre")
	e.heading = f("Safe.Centre.Heading")
	e.status = f("Safe.Centre.Status")
	e.statusDot = f("Safe.Centre.Status.Dot")
	e.statusText = f("Safe.Centre.Status.Text")
	e.sub = f("Safe.Centre.Sub")
	e.runCard = f("Safe.Centre.RunCard")
	e.mapName = f("Safe.Centre.RunCard.MapName")
	e.phase = f("Safe.Centre.RunCard.Phase")
	e.facts = f("Safe.Centre.RunCard.Facts")
	e.factLevel = f("Safe.Centre.RunCard.Facts.Level.Value")
	e.factKills = f("Safe.Centre.RunCard.Facts.Kills.Value")
	e.factGold = f("Safe.Centre.RunCard.Facts.Gold.Value")
	e.actions = f("Safe.Centre.Actions")
	e.primary = f("Safe.Centre.Actions.PrimaryButton")
	e.primaryLabel = f("Safe.Centre.Actions.PrimaryButton.Label")
	e.primaryKey = f("Safe.Centre.Actions.PrimaryButton.KeyCap")
	e.voteInfo = f("Safe.Centre.Actions.VoteInfo")
	e.mapButton = f("Safe.Centre.Actions.MapButton")
	e.mapKey = f("Safe.Centre.Actions.MapButton.KeyCap")
	e.settingsButton = f("Safe.Centre.Actions.SettingsButton")
	e.cancel = f("Safe.Centre.Actions.CancelButton")
	e.close = f("Safe.Centre.Actions.CloseButton")
	e.settings = f("Safe.Centre.SettingsView")
	e.settingsTitle = f("Safe.Centre.SettingsView.Title")
	e.settingsList = f("Safe.Centre.SettingsView.List")
	e.settingsBack = f("Safe.Centre.SettingsView.List.BackButton")
	e.settingsBackLabel = f("Safe.Centre.SettingsView.List.BackButton.Label")
	e.hints = f("Safe.Centre.Hints")

	e.stats = f("Safe.Stats")
	e.heroName = f("Safe.Stats.Hero.HeroName")
	e.portrait = f("Safe.Stats.Hero.Portrait")
	e.statList = f("Safe.Stats.StatList")

	e.tabs = f("Safe.Tabs")
	e.tabButtons = { build = f("Safe.Tabs.BuildTab"), stats = f("Safe.Tabs.StatsTab"), settings = f("Safe.Tabs.SettingsTab") }

	e.mapView = f("Safe.MapView")
	e.mapTitle = f("Safe.MapView.Title")
	e.map = f("Safe.MapView.Map")
	e.mapLegend = f("Safe.MapView.Legend")
	e.mapBack = f("Safe.MapView.BackButton")
	e.mapBackKey = f("Safe.MapView.BackButton.KeyCap")

	local slot = UiKit.template(e.weaponRow, "Slot")
	local tomeSlot = UiKit.template(e.tomeRow, "Slot") or slot
	self._itemTemplate = UiKit.template(e.itemGrid, "ItemTile")
	self._lineTemplate = UiKit.template(e.detailLines, "Line")
	local section = UiKit.template(e.statList, "StatSection")
	local statRow = section and UiKit.template(section, "StatRow")

	-- Roblox's own selection box would sit on top of each button's gold ring
	local noBox = Instance.new("Frame")
	noBox.Name = "NoSelectionBox"
	noBox.BackgroundTransparency = 1
	noBox.Size = UDim2.fromScale(1, 1)
	self._noBox = noBox

	UiKit.fillIcons(gui)

	-- the four weapon and four tome sockets, filled in place
	local function sockets(container: Instance?, template: Instance?, count: number, into, kind: string)
		if not container or not template then
			return
		end
		for i = 1, count do
			local tile = template:Clone()
			tile.LayoutOrder = i
			tile.Parent = container
			into[i] = tile
			self:_wireTile(tile, kind, i)
		end
	end
	sockets(e.weaponRow, slot, GameConfig.WeaponSlots, self._weaponSlots, "weapon")
	sockets(e.tomeRow, tomeSlot, GameConfig.TomeSlots, self._tomeSlots, "tome")

	-- the stats sheet: its sections and rows never change, only the values
	if e.statList and section and statRow then
		for i, def in Inspect.sections(nil) do
			local sectionFrame = section:Clone()
			sectionFrame.LayoutOrder = i
			UiKit.text(sectionFrame:FindFirstChild("Title"), string.upper(def.title))
			for j, row in def.rows do
				local line = statRow:Clone()
				line.LayoutOrder = j
				UiKit.text(line:FindFirstChild("Name"), row.name)
				self._statValues[row.key] = line:FindFirstChild("Value")
				line.Parent = sectionFrame
			end
			sectionFrame.Parent = e.statList
			table.insert(self._statContainers, sectionFrame)
		end
	end

	self:_wireButtons()
	self:_wireSettings()
	self._minimap:AttachPauseMap(e.map)

	for _, inst in gui:GetDescendants() do
		if inst:IsA("GuiButton") then
			inst.SelectionImageObject = noBox
		end
	end
	UiKit.show(e.root, false)

	local hurt = Net.client("Hurt")
	if hurt then
		hurt.OnClientEvent:Connect(function(amount)
			if self._mode == "inspect" and (tonumber(amount) or 0) > 0 then
				UiKit.safe("PauseMenu.hurt", function()
					self:_flashEdge()
				end)
			end
		end)
	end

	local state = self._state
	state.Changed:Connect(function(key)
		if not self._mode then
			return
		end
		UiKit.safe("PauseMenuController", function()
			if key == "me" then
				self:_renderBuild()
				self:_renderDetails()
				self:_renderStats()
				self:_renderRunCard()
			elseif key == "xp" or key == "clock" or key == "roster" then
				self:_renderRunCard()
			end
		end)
	end)

	UserInputService.LastInputTypeChanged:Connect(function()
		if self._mode then
			UiKit.safe("PauseMenu.keys", function()
				self:_renderMode()
			end)
		end
	end)
	pcall(function()
		GuiService:GetPropertyChangedSignal("PreferredTextSize"):Connect(function()
			self:_queueLayout()
		end)
	end)
	UiKit.ownScale(gui, function()
		self:_layout()
	end)

	-- the clocks in the status and the run card, ten times a second while open
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 or not self._mode then
			return
		end
		acc = 0
		UiKit.safe("PauseMenu.tick", function()
			self:_renderStatus()
			self:_renderRunCard()
		end)
	end)
end

--- A tile the inspector reads: pointing, selecting or pressing shows it.
function PauseMenuController:_wireTile(tile: Instance, kind: string, index: number)
	if not tile:IsA("GuiButton") then
		return
	end
	local function look()
		self:_inspect(kind, index)
	end
	tile.MouseEnter:Connect(function()
		UiKit.safe("PauseMenu.tile", look)
	end)
	tile.SelectionGained:Connect(function()
		UiKit.safe("PauseMenu.tile", look)
	end)
	UiKit.button(tile, look, true) -- its ring marks what the details card shows
	tile.SelectionImageObject = self._noBox
	tile:SetAttribute("QuietHover", true) -- a whole grid of hover ticks would rattle
end

function PauseMenuController:_wireButtons()
	local e = self._e
	local overlay = self._overlay
	UiKit.button(e.primary, function()
		self:_primary()
	end)
	UiKit.button(e.cancel, function()
		overlay:Ask("withdraw")
	end)
	UiKit.button(e.close, function()
		overlay:CloseMenu()
	end)
	UiKit.button(e.mapButton, function()
		self:_setView("map")
	end)
	UiKit.button(e.settingsButton, function()
		self:_setView("settings")
	end)
	UiKit.button(e.settingsBack, function()
		if self._mode == "settings" then
			overlay:CloseMenu()
		else
			self:_setView("main", e.settingsButton)
		end
	end)
	UiKit.button(e.mapBack, function()
		self:_setView("main", e.mapButton)
	end)
	for tab, button in e.tabButtons do
		UiKit.button(button, function()
			self:_setTab(tab)
		end)
	end
	-- Enter presses the main action when nothing is selected with a gamepad
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self._mode or input.KeyCode ~= Enum.KeyCode.Return then
			return
		end
		if GuiService.SelectedObject == nil and self._view == "main" and e.primary and e.primary.Visible then
			UiKit.safe("PauseMenu.enter", function()
				self:_primary()
			end)
		end
	end)
end

-- ================================================================ open, close, views

--- Show the menu in `mode` ("pause" | "inspect" | "settings"); a menu already
--- open just changes mode, keeping its page.
function PauseMenuController:Open(mode: string)
	local e = self._e
	if not e.root then
		return
	end
	local was = self._mode
	self._mode = mode
	if mode == "settings" then
		self._view = "settings"
	elseif not was or was == "settings" then
		self._view = "main"
		self._tab = "build"
	end
	if not self._inspected then
		self._inspected = { kind = "weapon", id = "" }
	end
	self:_layout()
	self:_renderAll()
	self:_renderMode()
	if not was then
		self:_bindSinks(true)
		self:_fade(true)
	end
	if was ~= mode then
		self:_focusDefault()
	end
end

--- The pause vote moved on (a vote, a ready, a second ticking): redraw the state.
function PauseMenuController:Refresh()
	if self._mode then
		self:_renderStatus()
		self:_renderKeys()
	end
end

function PauseMenuController:Close()
	if not self._mode then
		return
	end
	self._mode = nil
	self._dragging = nil
	self:_bindSinks(false)
	self:_edgePulse(false)
	self._minimap:SetPauseMapOpen(false)
	UiKit.unfocus(self._e.root)
	self:_fade(false)
end

--- One step back: the map or the settings page first, then the menu itself
--- (solo: resume; co-op inspection: close; a co-op pause waits for READY).
function PauseMenuController:_back()
	local e = self._e
	if self._view == "map" then
		self:_setView("main", e.mapButton)
	elseif self._view == "settings" and self._mode ~= "settings" and self._arrangement == "wide" then
		self:_setView("main", e.settingsButton)
	elseif self._mode == "settings" or self._mode == "inspect" then
		self._overlay:CloseMenu()
	elseif self._mode == "pause" and self._overlay:IsSolo() then
		self._overlay:Ask("resume")
	end
end

function PauseMenuController:ToggleMap()
	if self._mode and self._mode ~= "settings" then
		self:_setView(if self._view == "map" then "main" else "map", self._e.mapButton)
	end
end

function PauseMenuController:_setView(view: string, focusAfter: Instance?)
	if not self._mode then
		return
	end
	if view == "settings" and self._arrangement == "tabs" and self._mode ~= "settings" then
		self:_setTab("settings")
		return
	end
	self._view = view
	self:_layout()
	self:_renderMode()
	if view == "settings" then
		UiKit.focus(self._sliders[1] and self._sliders[1].frame)
	elseif view == "map" then
		UiKit.focus(self._e.mapBack)
	else
		UiKit.focus(focusAfter or self:_firstAction())
	end
end

function PauseMenuController:_setTab(tab: string)
	self._tab = tab
	self._view = if tab == "settings" then "settings" else "main"
	self:_layout()
	self:_renderMode()
	UiKit.focus(self._e.tabButtons[tab])
end

--- LB / RB: the next tab, or the next column's first control.
function PauseMenuController:_cycle(step: number)
	if self._arrangement == "tabs" then
		local order = { "build", "stats", "settings" }
		local i = table.find(order, self._tab) or 1
		self:_setTab(order[(i - 1 + step) % #order + 1])
		return
	end
	if self._view ~= "main" then
		return
	end
	local e = self._e
	local targets = { self:_inspectedTile() or self._weaponSlots[1], self:_firstAction(), e.statList }
	local selected = GuiService.SelectedObject
	local at = 2
	for i, target in targets do
		if selected and target and (selected == target or selected:IsDescendantOf(target)) then
			at = i
		end
	end
	if selected and self._e.build and selected:IsDescendantOf(self._e.build) then
		at = 1
	end
	UiKit.focus(targets[(at - 1 + step) % #targets + 1])
end

function PauseMenuController:_bindSinks(on: boolean)
	if not on then
		ContextActionService:UnbindAction(SINK)
		return
	end
	ContextActionService:BindActionAtPriority(
		SINK,
		function(_, inputState, input)
			if inputState == Enum.UserInputState.Begin then
				local key = input.KeyCode
				UiKit.safe("PauseMenu.pad", function()
					if key == Enum.KeyCode.ButtonB then
						self:_back()
					elseif key == Enum.KeyCode.ButtonL1 then
						self:_cycle(-1)
					elseif key == Enum.KeyCode.ButtonR1 then
						self:_cycle(1)
					end
				end)
			end
			-- X and E are swallowed too: nothing is used from behind the menu
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.E
	)
end

function PauseMenuController:_firstAction(): Instance?
	local e = self._e
	for _, button in { e.primary, e.cancel, e.close, e.mapButton } do
		if button and button:IsA("GuiObject") and button.Visible then
			return button
		end
	end
	return nil
end

function PauseMenuController:_focusDefault()
	local e = self._e
	if self._view == "settings" then
		UiKit.focus(self._sliders[1] and self._sliders[1].frame)
	elseif self._view == "map" then
		UiKit.focus(e.mapBack)
	else
		UiKit.focus(self:_firstAction())
	end
end

-- ================================================================ fades

-- The transparencies a fade scales, per kind of instance.
local function fadedProps(inst: Instance): { string }?
	if inst:IsA("UIStroke") then
		return { "Transparency" }
	elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
		return { "BackgroundTransparency", "TextTransparency" }
	elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		return { "BackgroundTransparency", "ImageTransparency" }
	elseif inst:IsA("ScrollingFrame") then
		return { "ScrollBarImageTransparency" }
	elseif inst:IsA("GuiObject") then
		return { "BackgroundTransparency" }
	end
	return nil
end

--- Fade the whole menu in or out. Every transparency is remembered as drawn
--- and eased from (or to) clear, so the fade always hands back the originals.
--- The running edge pulses on its own and is left out.
function PauseMenuController:_fade(show: boolean)
	local e = self._e
	local root = e.root
	if not root then
		return
	end
	self._fadeStamp += 1
	local stamp = self._fadeStamp
	if self._fadeList then
		-- a fade still running: put its values back before starting again
		for _, entry in self._fadeList do
			entry.inst[entry.prop] = entry.base
		end
		self._fadeList = nil
	end
	if show then
		root.Visible = true
	elseif not root.Visible then
		return
	end
	local list = {}
	for _, inst in root:GetDescendants() do
		if e.edge and (inst == e.edge or inst:IsDescendantOf(e.edge)) then
			continue
		end
		for _, prop in fadedProps(inst) or {} do
			table.insert(list, { inst = inst, prop = prop, base = inst[prop] })
		end
	end
	self._fadeList = list
	local safe = e.safe
	local rise = safe and safe.Position
	local seconds = if show then FADE_IN else FADE_OUT
	local started = os.clock()
	local function apply(level: number)
		for _, entry in list do
			entry.inst[entry.prop] = entry.base + (1 - entry.base) * level
		end
	end
	apply(if show then 1 else 0)
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if self._fadeStamp ~= stamp then
			conn:Disconnect()
			return
		end
		local t = math.min((os.clock() - started) / seconds, 1)
		local eased = 1 - (1 - t) ^ 2
		apply(if show then 1 - eased else eased)
		if safe and rise then
			-- the columns rise a few pixels into place
			local lift = if show then (1 - eased) * 10 else eased * 6
			safe.Position = rise + UDim2.fromOffset(0, math.floor(lift + 0.5))
		end
		if t >= 1 then
			conn:Disconnect()
			if safe and rise then
				safe.Position = rise
			end
			for _, entry in list do
				entry.inst[entry.prop] = entry.base
			end
			self._fadeList = nil
			if not show then
				root.Visible = false
			else
				-- anything that changed while it faded in is drawn again as it is now
				self:_queueLayout()
				self:_renderBuild()
				self:_renderDetails()
			end
		end
	end)
end

--- The thin amber frame round the screen while the world runs: a slow breath.
function PauseMenuController:_edgePulse(on: boolean)
	if self._edgeOn == on then
		return
	end
	self._edgeOn = on
	for _, t in self._edgeTweens do
		t:Cancel()
	end
	table.clear(self._edgeTweens)
	local edge = self._e.edge
	if not edge then
		return
	end
	UiKit.show(edge, on)
	if not on then
		return
	end
	local info = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	for _, bar in edge:GetChildren() do
		if bar:IsA("GuiObject") then
			bar.BackgroundColor3 = WARN
			bar.BackgroundTransparency = 0.3
			local t = TweenService:Create(bar, info, { BackgroundTransparency = 0.68 })
			t:Play()
			table.insert(self._edgeTweens, t)
		end
	end
end

--- A hit while inspecting: the edge flashes red for a moment.
function PauseMenuController:_flashEdge()
	local edge = self._e.edge
	if not edge then
		return
	end
	for _, bar in edge:GetChildren() do
		if bar:IsA("GuiObject") then
			bar.BackgroundColor3 = DANGER
			TweenService:Create(bar, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = WARN })
				:Play()
		end
	end
end

-- ================================================================ layout

function PauseMenuController:_queueLayout()
	if self._layoutQueued then
		return
	end
	self._layoutQueued = true
	task.defer(function()
		self._layoutQueued = false
		UiKit.safe("PauseMenu.layout", function()
			self:_layout()
		end)
	end)
end

function PauseMenuController:_layout()
	local gui, e = self._gui, self._e
	if not gui or not e.root then
		return
	end
	local screen = UiKit.insets()
	screen.boost = textBoost()
	local L = PanelLayout.pause(screen)
	local scale = UiKit.scaleOf(gui)
	if scale and math.abs(scale.Scale - L.scale) > 1e-4 then
		scale.Scale = L.scale
	end
	setOffset(e.root, "Size", screen.width / L.scale, screen.height / L.scale)
	setOffset(e.safe, "Position", L.safe.x, L.safe.y)
	setOffset(e.safe, "Size", L.safe.w, L.safe.h)
	local changed = self._arrangement ~= L.mode
	self._arrangement = L.mode
	if L.mode == "tabs" and self._view == "settings" and self._mode ~= "settings" then
		self._tab = "settings"
	end
	if self._mode == "settings" then
		self:_layoutSettingsOnly(L)
	elseif L.mode == "wide" then
		self:_layoutWide(L)
	else
		self:_layoutTabs(L)
	end
	if changed then
		self:_renderBuild()
		self:_renderMode()
	end
end

--- Common to both arrangements: the centre column as the wide menu has it.
function PauseMenuController:_centreWide(colH: number)
	local e = self._e
	setOffset(e.centre, "Size", CENTRE_W, colH)
	setOffset(e.heading, "Size", 520, 86)
	textSize(e.heading, 76)
	place(e.status, UDim2.new(0.5, 0, 0, 92), Vector2.new(0.5, 0))
	place(e.sub, UDim2.new(0.5, 0, 0, 138), Vector2.new(0.5, 0))
	setOffset(e.sub, "Size", 500, 44)
	textSize(e.sub, 19)
	place(e.runCard, UDim2.new(0.5, 0, 0, 196), Vector2.new(0.5, 0))
	setOffset(e.runCard, "Size", 440, 128)
	setOffset(e.mapName, "Size", 400, 34)
	textSize(e.mapName, 28)
	place(e.phase, UDim2.new(0.5, 0, 0, 48), Vector2.new(0.5, 0))
	setOffset(e.phase, "Size", 400, 24)
	textSize(e.phase, 19)
	setOffset(e.facts, "Size", 400, 32)
	place(e.actions, UDim2.new(0.5, 0, 0, 352), Vector2.new(0.5, 0))
	setOffset(e.actions, "Size", 400, 0)
	setOffset(e.primary, "Size", 400, 84)
	for _, b in { e.mapButton, e.settingsButton } do
		setOffset(b, "Size", 400, 68)
	end
	for _, b in { e.cancel, e.close } do
		setOffset(b, "Size", 400, 60)
	end
	setOffset(e.voteInfo, "Size", 400, 22)
	textSize(e.voteInfo, 17)
end

function PauseMenuController:_layoutWide(L)
	local e = self._e
	local m = MARGIN
	local colH = math.min(L.safe.h - 2 * m, COL_H_MAX)
	local top = (L.safe.h - colH) / 2
	local span = math.min(L.safe.w - 2 * m, SPAN_MAX)
	local left = (L.safe.w - span) / 2
	place(e.build, UDim2.fromOffset(math.floor(left + 0.5), math.floor(top + 0.5)))
	setOffset(e.build, "Size", BUILD_W, colH)
	place(e.stats, UDim2.fromOffset(math.floor(left + span - STATS_W + 0.5), math.floor(top + 0.5)))
	setOffset(e.stats, "Size", STATS_W, colH)
	place(e.centre, UDim2.fromOffset(math.floor(left + span / 2 - CENTRE_W / 2 + 0.5), math.floor(top + 0.5)))
	self:_centreWide(colH)

	-- build: as built
	for _, inst in { e.buildTitle, e.counts, e.buildRule } do
		UiKit.show(inst, true)
	end
	place(e.weaponsCaption, UDim2.fromOffset(22, 68))
	place(e.tomesCaption, UDim2.fromOffset(22, 196))
	place(e.itemsCaption, UDim2.fromOffset(22, 324))
	self:_layoutRow(e.weaponRow, self._weaponSlots, 98, WEAPON_TILE, TILE_GAP)
	self:_layoutRow(e.tomeRow, self._tomeSlots, 226, WEAPON_TILE, TILE_GAP)
	place(e.itemGrid, UDim2.fromOffset(20, GRID_Y))
	setOffset(e.itemGrid, "Size", 528, colH - GRID_Y - DETAILS_H - 32)
	place(e.noItems, UDim2.fromOffset(22, GRID_Y + 4))
	self:_layoutItems(ITEM_TILE)
	place(e.details, UDim2.new(0, 20, 1, -20), Vector2.new(0, 1))
	setOffset(e.details, "Size", 520, DETAILS_H)
	self:_layoutDetails(520, DETAILS_H)

	-- stats
	setOffset(e.statList, "Size", STATS_W - 24, colH - 84)
	self:_layoutStatWidth(STATS_W - 46)

	-- settings, in the centre column
	place(e.settings, UDim2.new(0.5, 0, 0, 180), Vector2.new(0.5, 0))
	self:_layoutSettings(SETTINGS_W, math.min(640, colH - 220), true)

	-- the map, over the centre column
	UiKit.show(e.tabs, false)
	local mapH = math.min(colH, 900)
	place(e.mapView, UDim2.fromOffset(math.floor(left + span / 2 - MAP_W / 2 + 0.5), math.floor(top + 0.5)))
	setOffset(e.mapView, "Size", MAP_W, mapH)
	self:_layoutMap(MAP_W, mapH, false)
end

function PauseMenuController:_layoutTabs(L)
	local e = self._e
	local m = MARGIN
	local areaW, areaH = L.safe.w - 2 * m, L.safe.h - 2 * m
	-- the rail: title, state, actions, and the run card at its foot
	place(e.centre, UDim2.fromOffset(m, m))
	setOffset(e.centre, "Size", RAIL_W, areaH)
	setOffset(e.heading, "Size", RAIL_W, 52)
	textSize(e.heading, 44)
	place(e.status, UDim2.new(0.5, 0, 0, 56), Vector2.new(0.5, 0))
	place(e.sub, UDim2.new(0.5, 0, 0, 104), Vector2.new(0.5, 0))
	setOffset(e.sub, "Size", RAIL_W, 44)
	textSize(e.sub, 16)
	place(e.actions, UDim2.new(0.5, 0, 0, 156), Vector2.new(0.5, 0))
	setOffset(e.actions, "Size", RAIL_W, 0)
	setOffset(e.primary, "Size", RAIL_W, 66)
	for _, b in { e.mapButton, e.cancel, e.close } do
		setOffset(b, "Size", RAIL_W, 54)
	end
	setOffset(e.voteInfo, "Size", RAIL_W, 20)
	textSize(e.voteInfo, 15)
	place(e.runCard, UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1))
	setOffset(e.runCard, "Size", RAIL_W, 112)
	setOffset(e.mapName, "Size", RAIL_W - 24, 30)
	textSize(e.mapName, 24)
	place(e.phase, UDim2.new(0.5, 0, 0, 42), Vector2.new(0.5, 0))
	setOffset(e.phase, "Size", RAIL_W - 24, 22)
	textSize(e.phase, 16)
	setOffset(e.facts, "Size", RAIL_W - 24, 30)

	-- the tabs and their page
	local rx, rw = m + RAIL_W + 24, areaW - RAIL_W - 24
	place(e.tabs, UDim2.fromOffset(rx, m))
	setOffset(e.tabs, "Size", rw, TABS_H)
	local cy, ch = m + TABS_H + 12, areaH - TABS_H - 12

	place(e.build, UDim2.fromOffset(rx, cy))
	setOffset(e.build, "Size", rw, ch)
	for _, inst in { e.buildTitle, e.counts, e.buildRule } do
		UiKit.show(inst, false)
	end
	place(e.weaponsCaption, UDim2.fromOffset(22, 10))
	place(e.tomesCaption, UDim2.fromOffset(22, 132))
	place(e.itemsCaption, UDim2.fromOffset(22, 252))
	self:_layoutRow(e.weaponRow, self._weaponSlots, 38, TAB_TILE, 10)
	self:_layoutRow(e.tomeRow, self._tomeSlots, 158, TAB_TILE, 10)
	place(e.itemGrid, UDim2.fromOffset(20, 276))
	setOffset(e.itemGrid, "Size", TAB_LEFT + 8, ch - 276 - 14)
	place(e.noItems, UDim2.fromOffset(22, 280))
	self:_layoutItems(TAB_ITEM)
	local dx = 20 + TAB_LEFT + 28
	place(e.details, UDim2.fromOffset(dx, 14))
	setOffset(e.details, "Size", rw - dx - 16, ch - 28)
	self:_layoutDetails(rw - dx - 16, ch - 28)

	local statsW = math.min(rw, 560)
	place(e.stats, UDim2.fromOffset(math.floor(rx + (rw - statsW) / 2), cy))
	setOffset(e.stats, "Size", statsW, ch)
	setOffset(e.statList, "Size", statsW - 24, ch - 84)
	self:_layoutStatWidth(statsW - 46)

	-- settings sit on the page, though they belong to the rail's column
	local setW = math.min(rw, 520)
	place(e.settings, UDim2.fromOffset(math.floor(rx - m + (rw - setW) / 2), cy - m))
	self:_layoutSettings(setW, ch, false)

	place(e.mapView, UDim2.fromOffset(rx, cy))
	setOffset(e.mapView, "Size", rw, ch)
	self:_layoutMap(rw, ch, true)
end

--- Outside a run: the settings alone, in the middle of the screen.
function PauseMenuController:_layoutSettingsOnly(L)
	local e = self._e
	local colH = L.safe.h - 2 * MARGIN
	place(e.centre, UDim2.fromOffset(math.floor((L.safe.w - CENTRE_W) / 2 + 0.5), MARGIN))
	self:_centreWide(colH)
	place(e.settings, UDim2.new(0.5, 0, 0, 100), Vector2.new(0.5, 0))
	self:_layoutSettings(SETTINGS_W, math.min(640, colH - 110), true)
	UiKit.show(e.tabs, false)
end

function PauseMenuController:_layoutRow(row: Instance?, slots, y: number, side: number, gap: number)
	place(row, UDim2.fromOffset(20, y))
	setOffset(row, "Size", 4 * side + 3 * gap, side)
	local layout = row and row:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, gap)
	end
	for _, tile in slots do
		self:_sizeTile(tile, side)
	end
end

function PauseMenuController:_sizeTile(tile: Instance, side: number)
	setOffset(tile, "Size", side, side)
	local icon = tile:FindFirstChild("Icon")
	setOffset(icon, "Size", math.floor(side * 0.66), math.floor(side * 0.66))
end

function PauseMenuController:_itemSide(): number
	return if self._arrangement == "tabs" then TAB_ITEM else ITEM_TILE
end

function PauseMenuController:_layoutItems(side: number)
	local grid = self._e.itemGrid and self._e.itemGrid:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = UDim2.fromOffset(side, side)
	end
	for _, tile in self._itemTiles do
		self:_sizeTile(tile, side)
	end
end

--- The details card's inside for a card `w` x `h` (Screens_build.details_layout).
function PauseMenuController:_layoutDetails(w: number, h: number)
	local e = self._e
	local inner = w - 32
	setOffset(e.detailName, "Size", w - 122, 36)
	setOffset(e.detailTags, "Size", w - 122, 26)
	local textH = if h < 340 then 48 else 72
	setOffset(e.detailText, "Size", inner, textH)
	local linesY = 100 + textH + 6
	place(e.detailLines, UDim2.fromOffset(16, linesY))
	setOffset(e.detailLines, "Size", inner, h - linesY - 52)
	local cols = if inner >= 440 then 2 else 1
	local grid = e.detailLines and e.detailLines:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = UDim2.fromOffset(math.floor((inner - 24 * (cols - 1)) / cols), 22)
	end
	setOffset(e.detailNote, "Size", inner, 40)
	setOffset(e.detailEmpty, "Size", inner, 60)
end

function PauseMenuController:_layoutStatWidth(width: number)
	for _, section in self._statContainers do
		setOffset(section, "Size", width, 0)
		for _, child in section:GetChildren() do
			if child:IsA("GuiObject") then
				setOffset(child, "Size", width, child.Size.Y.Offset)
			end
		end
	end
end

function PauseMenuController:_layoutSettings(width: number, height: number, withTitle: boolean)
	local e = self._e
	setOffset(e.settings, "Size", width, height)
	UiKit.show(e.settingsTitle, withTitle)
	local top = if withTitle then 62 else 12
	place(e.settingsList, UDim2.new(0.5, 0, 0, top), Vector2.new(0.5, 0))
	setOffset(e.settingsList, "Size", width - 24, height - top - 10)
end

--- The map page: the square map, its legend and BACK. On the tabs page the
--- legend stands beside the map.
function PauseMenuController:_layoutMap(width: number, height: number, beside: boolean)
	local e = self._e
	UiKit.show(e.mapTitle, not beside)
	local legend = e.mapLegend and e.mapLegend:FindFirstChildOfClass("UIListLayout")
	if beside then
		local side = math.max(120, math.min(height - 28, width - 300))
		place(e.map, UDim2.fromOffset(14, 14))
		setOffset(e.map, "Size", side, side)
		place(e.mapLegend, UDim2.fromOffset(side + 36, 20))
		setOffset(e.mapLegend, "Size", width - side - 52, 200)
		if legend then
			legend.FillDirection = Enum.FillDirection.Vertical
			legend.HorizontalAlignment = Enum.HorizontalAlignment.Left
			legend.VerticalAlignment = Enum.VerticalAlignment.Top
		end
		place(e.mapBack, UDim2.new(1, -16, 1, -16), Vector2.new(1, 1))
		setOffset(e.mapBack, "Size", math.min(260, width - side - 52), 56)
	else
		local side = math.min(680, height - 202)
		place(e.map, UDim2.new(0.5, 0, 0, 62), Vector2.new(0.5, 0))
		setOffset(e.map, "Size", side, side)
		place(e.mapLegend, UDim2.new(0.5, 0, 0, 62 + side + 14), Vector2.new(0.5, 0))
		setOffset(e.mapLegend, "Size", 680, 32)
		if legend then
			legend.FillDirection = Enum.FillDirection.Horizontal
			legend.HorizontalAlignment = Enum.HorizontalAlignment.Center
			legend.VerticalAlignment = Enum.VerticalAlignment.Center
		end
		place(e.mapBack, UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1))
		setOffset(e.mapBack, "Size", 320, 60)
	end
end

-- ================================================================ what shows, per mode and page

function PauseMenuController:_renderMode()
	local e = self._e
	local mode, view = self._mode, self._view
	if not mode then
		return
	end
	local tabs = self._arrangement == "tabs" and mode ~= "settings"
	local map = view == "map"
	local settingsShown = view == "settings"
	local only = mode == "settings"

	UiKit.show(e.tabs, tabs)
	for tab, button in e.tabButtons do
		local style = if tabs and not map and self._tab == tab then STYLE.tab else STYLE.quiet
		UiKit.colour(button, style[1])
		local stroke = button and button:FindFirstChild("Stroke")
		if stroke then
			stroke.Color, stroke.Transparency = style[2], style[3]
		end
		UiKit.textColour(button and button:FindFirstChild("Label"), style[4])
	end

	if tabs then
		UiKit.show(e.build, not map and self._tab == "build")
		UiKit.show(e.stats, not map and self._tab == "stats")
		UiKit.show(e.centre, true)
		UiKit.show(e.runCard, true)
		UiKit.show(e.actions, true)
		UiKit.show(e.settingsButton, false)
	else
		UiKit.show(e.build, not only)
		UiKit.show(e.stats, not only)
		UiKit.show(e.centre, not map)
		UiKit.show(e.runCard, not only and not settingsShown)
		UiKit.show(e.actions, not only and not settingsShown)
		UiKit.show(e.settingsButton, true)
	end
	-- key hints are for keys: none on the tabs rail or on a touch screen
	UiKit.show(e.hints, not tabs and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch)
	UiKit.show(e.settings, settingsShown and not map)
	UiKit.show(e.mapView, map)
	self._minimap:SetPauseMapOpen(map)
	UiKit.show(e.settingsBack, not tabs)
	UiKit.text(e.settingsBackLabel, if only then "CLOSE" else "BACK")
	UiKit.show(e.status, not only)
	UiKit.show(e.sub, not only)

	-- the world running behind a co-op inspection is plain to see
	local scrim = e.scrim
	local goal = if mode == "inspect" then SCRIM_RUNNING else SCRIM_PAUSED
	if scrim and scrim:IsA("GuiObject") and not self._fadeList and scrim.BackgroundTransparency ~= goal then
		if e.root.Visible then
			TweenService:Create(scrim, TweenInfo.new(0.25), { BackgroundTransparency = goal }):Play()
		else
			scrim.BackgroundTransparency = goal
		end
	end
	self:_edgePulse(mode == "inspect")
	self:_renderStatus()
	self:_renderKeys()
end

function PauseMenuController:_renderAll()
	self:_renderBuild()
	self:_renderDetails()
	self:_renderStats()
	self:_renderRunCard()
	self:_renderSettings()
end

-- ================================================================ the status and the actions

local function styleButton(button: Instance?, style)
	if not button or not button:IsA("GuiObject") then
		return
	end
	button.BackgroundColor3 = style[1]
	local stroke = button:FindFirstChild("Stroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color, stroke.Transparency = style[2], style[3]
	end
	UiKit.textColour(button:FindFirstChild("Label"), style[4])
end

function PauseMenuController:_renderStatus()
	local e = self._e
	local mode = self._mode
	if not mode then
		return
	end
	local overlay = self._overlay
	local info = overlay:Info()
	local heading, headColour = "PAUSED", INK
	local pill, pillCalm = nil, true
	local sub = ""
	local primary, primaryStyle = nil, STYLE.gold
	local voteInfo = nil
	local cancel, close = false, false
	local hints = "P to resume  ·  Tab for the map"

	if mode == "settings" then
		heading, hints = "SETTINGS", "Changes apply at once and are kept"
	elseif mode == "pause" then
		local seconds = overlay:SecondsLeft()
		if seconds < 0 then
			pill, sub, primary = "WORLD PAUSED", "The world is paused.", "RESUME"
		else
			-- co-op: everyone presses READY; near the limit it resumes on its own
			local ready = info.ready or {}
			local n, need = #ready, info.need or 0
			local auto = seconds - RESUME_SECONDS
			if auto <= AUTO_WARNING then
				pill, pillCalm = `AUTO-RESUME IN {math.max(0, math.ceil(auto))}`, false
			else
				pill = `SQUAD PAUSED  ·  {UiKit.clock(math.ceil(seconds))}`
			end
			sub = "Everyone presses READY to play on."
			local mine = table.find(ready, overlay:UserId()) ~= nil
			primary = if mine then `WAITING  {n}/{need}` else `READY  {n}/{need}`
			primaryStyle = if mine then STYLE.quiet else STYLE.gold
			hints = if mine then "P to stop waiting  ·  Tab for the map" else "P to ready up  ·  Tab for the map"
		end
	else -- inspect: co-op, the world keeps running
		heading, headColour = "GAME STILL RUNNING", WARN
		pillCalm = false
		close = true
		local left = math.max(0, math.ceil(overlay:SecondsLeft()))
		if info.mode == "vote" then
			local agreed, need = #(info.votes or {}), info.need or 0
			if info.by == overlay:UserId() then
				pill = `PAUSE REQUESTED  ·  {agreed}/{need}  ·  {left}s`
				sub = "The game pauses once everyone agrees."
				cancel = true
				voteInfo = "Closing the menu keeps your request."
			elseif overlay:Voted() then
				pill = `PAUSE VOTE  ·  {agreed}/{need}  ·  {left}s`
				sub = "You agreed. Waiting for the rest of the squad."
				voteInfo = "Closing the menu keeps your vote."
			else
				pill = `{string.upper(info.byName or "A TEAMMATE")} WANTS TO PAUSE  ·  {left}s`
				sub = "You can still be hit. Agree to pause the game."
				primary = "ACCEPT PAUSE"
				voteInfo = `{agreed} of {need} agreed`
			end
			hints = "P to close  ·  closing keeps the vote"
		else
			pill = "YOU CAN STILL BE HIT"
			sub = "Ask the squad to pause, or close the menu to fight on."
			primary = "REQUEST PAUSE"
			local hint = overlay:Hint()
			if hint then
				voteInfo = hint
			end
			hints = "P to close  ·  Tab for the map"
		end
	end

	if self._view == "settings" then
		hints = "Changes apply at once and are kept"
	end
	UiKit.text(e.heading, heading)
	UiKit.textColour(e.heading, headColour)
	UiKit.show(e.status, pill ~= nil and mode ~= "settings")
	if pill then
		UiKit.text(e.statusText, pill)
		local ink = if pillCalm then CALM else WARN
		UiKit.textColour(e.statusText, ink)
		UiKit.colour(e.statusDot, ink)
		UiKit.colour(e.status, if pillCalm then CALM_BG else WARN_BG)
		local stroke = e.status and e.status:FindFirstChild("Stroke")
		if stroke then
			stroke.Color = ink
		end
	end
	UiKit.text(e.sub, sub)
	local selected = GuiService.SelectedObject
	local moved = selected ~= nil and ((selected == e.primary and primary == nil) or (selected == e.cancel and not cancel))
	UiKit.show(e.primary, primary ~= nil)
	if primary then
		UiKit.text(e.primaryLabel, primary)
		styleButton(e.primary, primaryStyle)
	end
	UiKit.show(e.voteInfo, voteInfo ~= nil)
	UiKit.text(e.voteInfo, voteInfo or "")
	UiKit.show(e.cancel, cancel)
	UiKit.show(e.close, close)
	UiKit.text(e.hints, hints)
	if moved then
		UiKit.focus(self:_firstAction())
	end
end

--- The keys printed on the buttons follow the last input: keyboard, gamepad,
--- or none on touch.
function PauseMenuController:_renderKeys()
	local e = self._e
	local last = UserInputService:GetLastInputType()
	local pad = string.sub(last.Name, 1, 7) == "Gamepad"
	local touch = last == Enum.UserInputType.Touch
	local inspecting = self._mode == "inspect"
	UiKit.text(e.primaryKey, if inspecting then "Enter" elseif pad then "Start" else "P")
	UiKit.text(e.mapKey, if pad then "Select" else "Tab")
	UiKit.text(e.mapBackKey, if pad then "B" else "Tab")
	for _, cap in { e.primaryKey, e.mapKey, e.mapBackKey } do
		UiKit.show(cap, not touch)
	end
	-- while inspecting, P and Start close the menu: a gamepad presses the button itself
	if inspecting and pad then
		UiKit.show(e.primaryKey, false)
	end
end

function PauseMenuController:_primary()
	local overlay = self._overlay
	local mode = self._mode
	if mode == "pause" then
		overlay:Ask("resume")
	elseif mode == "inspect" then
		local info = overlay:Info()
		if info.mode == "vote" then
			if info.by ~= overlay:UserId() and not overlay:Voted() then
				overlay:Ask("accept")
			end
		elseif info.mode == "none" then
			overlay:Ask("request")
		end
	end
end

-- ================================================================ the run card

function PauseMenuController:_renderRunCard()
	local e = self._e
	local state = self._state
	local map = Roster.Maps[state.roster.map] or Roster.Maps[Roster.MapOrder[1]]
	UiKit.text(e.mapName, string.upper(map.name))
	local clock = state:Clock()
	local stage = state.stage or GameConfig.StageSeconds
	if state.phase == "Overtime" then
		local names = GameConfig.OvertimeNames
		local tier = math.clamp(math.max(state.tier, 1), 1, #names)
		UiKit.text(e.phase, `Overtime  ·  {names[tier]}  ·  {UiKit.clock(clock - stage)}`)
	else
		UiKit.text(e.phase, `Stage  ·  {UiKit.clock(math.max(0, stage - clock))} to the final horde`)
	end
	UiKit.text(e.factLevel, `LVL {state.level}`)
	UiKit.text(e.factKills, UiKit.commas(state.kills))
	UiKit.text(e.factGold, UiKit.commas(state.me and state.me.gold or 0))
end

-- ================================================================ the build and its inspector

function PauseMenuController:_renderBuild()
	local e = self._e
	local me = self._state.me
	local weapons = me and me.weapons or {}
	local tomes = me and me.tomes or {}
	local items = me and me.items or {}

	local function fill(slots, list, prefix: string, rim: Color3)
		for i, tile in slots do
			local entry = list[i]
			local icon = tile:FindFirstChild("Icon")
			UiKit.show(icon, entry ~= nil)
			if entry then
				UiKit.setIcon(icon, prefix .. tostring(entry.id))
			end
			local tag = tile:FindFirstChild("Tag")
			UiKit.text(tag, if entry then levelTag(entry.level) else "")
			UiKit.show(tag, entry ~= nil)
			if tile:IsA("GuiButton") then
				tile.Selectable = entry ~= nil
				tile.BackgroundTransparency = if entry then 0.06 else 0.55
			end
			local stroke = tile:FindFirstChild("Stroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = rim
				stroke.Transparency = if entry then 0.15 else 0.8
			end
		end
	end
	fill(self._weaponSlots, weapons, "Icon", RIM)
	fill(self._tomeSlots, tomes, "IconTome", TEAL)

	local sig = signature(items, "id", "count")
	if sig ~= self._itemSig and e.itemGrid and self._itemTemplate then
		self._itemSig = sig
		UiKit.clear(self._itemTiles)
		local side = self:_itemSide()
		for i, item in items do
			local tile = self._itemTemplate:Clone()
			tile.LayoutOrder = i
			UiKit.setIcon(tile:FindFirstChild("Icon"), "IconItem" .. tostring(item.id))
			UiKit.text(tile:FindFirstChild("Tag"), `x{item.count}`)
			local def = Roster.Items[item.id]
			local stroke = tile:FindFirstChild("Stroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = UiKit.rarityColour(def and def.rarity)
			end
			self:_sizeTile(tile, side)
			tile.Parent = e.itemGrid
			table.insert(self._itemTiles, tile)
			self:_wireTile(tile, "item", i)
		end
	end
	UiKit.show(e.noItems, #items == 0)
	UiKit.text(e.counts, `{plural(#weapons, "weapon")}  ·  {plural(#tomes, "tome")}  ·  {plural(#items, "item")}`)
end

--- Show the `index`th weapon, tome or item in the details card.
function PauseMenuController:_inspect(kind: string, index: number)
	local me = self._state.me
	local list = me and (if kind == "weapon" then me.weapons elseif kind == "tome" then me.tomes else me.items)
	local entry = list and list[index]
	if not entry then
		return
	end
	self._inspected = { kind = kind, id = entry.id }
	self:_renderDetails()
end

--- The tile the details card shows, if it is still in the build.
function PauseMenuController:_inspectedTile(): Instance?
	local me = self._state.me
	local pick = self._inspected
	if not me or not pick then
		return nil
	end
	local list, tiles
	if pick.kind == "weapon" then
		list, tiles = me.weapons, self._weaponSlots
	elseif pick.kind == "tome" then
		list, tiles = me.tomes, self._tomeSlots
	else
		list, tiles = me.items, self._itemTiles
	end
	for i, entry in list or {} do
		if entry.id == pick.id then
			return tiles[i]
		end
	end
	return nil
end

function PauseMenuController:_renderDetails()
	local e = self._e
	local me = self._state.me
	local pick = self._inspected
	local entry, kind = nil, nil
	if me and pick then
		local list = if pick.kind == "weapon" then me.weapons elseif pick.kind == "tome" then me.tomes else me.items
		for _, candidate in list or {} do
			if candidate.id == pick.id then
				entry, kind = candidate, pick.kind
			end
		end
	end
	if not entry and me and me.weapons and me.weapons[1] then
		-- what was shown left the build (a Second Wind broke): back to the main weapon
		entry, kind = me.weapons[1], "weapon"
		self._inspected = { kind = kind, id = entry.id }
	end

	local shownTile = if entry then self:_inspectedTile() else nil
	for _, group in { self._weaponSlots, self._tomeSlots, self._itemTiles } do
		for _, tile in group do
			UiKit.show(tile:FindFirstChild("Focus"), tile == shownTile)
		end
	end

	for _, inst in { e.detailTile, e.detailName, e.detailTags, e.detailText, e.detailLines, e.detailNote } do
		UiKit.show(inst, entry ~= nil)
	end
	UiKit.show(e.detailEmpty, entry == nil)
	if not entry then
		return
	end

	local card
	if kind == "weapon" then
		card = Inspect.weapon(entry, self:_has("AutoTrigger"))
	elseif kind == "tome" then
		card = Inspect.tome(entry, me.stats)
	else
		card = Inspect.item(entry)
	end
	local rim = if kind == "tome" then TEAL elseif kind == "item" then UiKit.rarityColour(card.rarity) else RIM
	local prefix = if kind == "weapon" then "Icon" elseif kind == "tome" then "IconTome" else "IconItem"
	UiKit.setIcon(e.detailIcon, prefix .. tostring(entry.id))
	local tileStroke = e.detailTile and e.detailTile:FindFirstChild("Stroke")
	if tileStroke then
		tileStroke.Color = rim
	end
	UiKit.text(e.detailName, string.upper(card.name))
	UiKit.text(e.kindTag, if kind == "item" then string.upper(card.rarity or "Item") else string.upper(kind))
	UiKit.textColour(e.kindTag, rim)
	local kindStroke = e.kindTag and e.kindTag:FindFirstChild("Stroke")
	if kindStroke then
		kindStroke.Color = rim
	end
	UiKit.text(e.levelTag, card.tag)
	UiKit.text(e.detailText, card.text)
	UiKit.text(e.detailNote, card.note or "")

	local parts = { card.name, card.tag }
	for _, line in card.lines do
		table.insert(parts, line.label .. "=" .. line.value)
	end
	local sig = table.concat(parts, "|")
	if sig == self._linesSig then
		return
	end
	self._linesSig = sig
	UiKit.clear(self._lines)
	if e.detailLines and self._lineTemplate then
		for i, line in card.lines do
			local row = self._lineTemplate:Clone()
			row.LayoutOrder = i
			UiKit.text(row:FindFirstChild("Label"), line.label)
			UiKit.text(row:FindFirstChild("Value"), line.value)
			row.Parent = e.detailLines
			table.insert(self._lines, row)
		end
	end
end

function PauseMenuController:_has(itemId: string): boolean
	local me = self._state.me
	for _, item in me and me.items or {} do
		if item.id == itemId then
			return true
		end
	end
	return false
end

-- ================================================================ the stats sheet

function PauseMenuController:_renderStats()
	local e = self._e
	local me = self._state.me
	for _, section in Inspect.sections(me and me.stats) do
		for _, row in section.rows do
			local label = self._statValues[row.key]
			UiKit.text(label, row.value)
			UiKit.textColour(label, TONE[row.tone] or INK)
		end
	end
	local hero = me and Roster.Heroes[me.hero]
	UiKit.text(e.heroName, if hero then string.upper(hero.name) else "")
	UiKit.setIcon(e.portrait, if me then "Portrait" .. tostring(me.hero) else nil)
end

-- ================================================================ settings

function PauseMenuController:_wireSettings()
	local e = self._e
	local gui = UiKit.playerGui()
	local list = e.settingsList
	local function addSlider(key: string, attribute: string, low: number, high: number, fmt: (number) -> string)
		local slider = UiKit.find(list, `{key}Row.{key}Slider`)
		if not slider or not slider:IsA("GuiObject") then
			return
		end
		local entry = {
			frame = slider,
			fill = slider:FindFirstChild("Fill"),
			knob = slider:FindFirstChild("Knob"),
			value = UiKit.find(list, `{key}Row.{key}Value`),
			focus = slider:FindFirstChild("Focus"),
			attribute = attribute,
			low = low,
			high = high,
			fmt = fmt,
		}
		table.insert(self._sliders, entry)
		slider.Active = true
		slider.Selectable = true
		slider.SelectionImageObject = self._noBox
		local function begin(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				self._dragging = entry
				self:_dragTo(entry, input.Position.X)
			end
		end
		slider.InputBegan:Connect(begin)
		if entry.knob and entry.knob:IsA("GuiObject") then
			entry.knob.Active = true
			entry.knob.InputBegan:Connect(begin)
		end
		slider.SelectionGained:Connect(function()
			UiKit.show(entry.focus, true)
		end)
		slider.SelectionLost:Connect(function()
			UiKit.show(entry.focus, false)
		end)
	end
	local function percent(v: number): string
		return `{math.floor(v * 100 + 0.5)}%`
	end
	local function times(v: number): string
		return `{math.floor(v * 100 + 0.5) / 100}x`
	end
	addSlider("Master", "MasterVolume", 0, 1, percent)
	addSlider("Music", "MusicVolume", 0, 1, percent)
	addSlider("Sfx", "SfxVolume", 0, 1, percent)
	addSlider("Sensitivity", "Sensitivity", SENS_MIN, SENS_MAX, times)

	UiKit.button(UiKit.find(list, "DamageNumbersToggle"), function()
		-- takes effect at once; kept in the profile when the menu closes
		gui:SetAttribute("DamageNumbers", gui:GetAttribute("DamageNumbers") == false)
		self:_renderSettings()
	end)
	UiKit.button(UiKit.find(list, "EnemyOutlinesToggle"), function()
		-- takes effect at once; kept in the profile when the menu closes
		gui:SetAttribute("EnemyOutlines", gui:GetAttribute("EnemyOutlines") ~= true)
		self:_renderSettings()
	end)
	self._numbersCheck = UiKit.find(list, "DamageNumbersToggle.Check")
	self._outlinesCheck = UiKit.find(list, "EnemyOutlinesToggle.Check")

	UserInputService.InputChanged:Connect(function(input)
		local entry = self._dragging
		if entry and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			UiKit.safe("PauseMenu.slider", function()
				self:_dragTo(entry, input.Position.X)
			end)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = nil
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		local key = input.KeyCode
		if not self._mode or (key ~= Enum.KeyCode.DPadLeft and key ~= Enum.KeyCode.DPadRight) then
			return
		end
		-- a gamepad nudges the slider it has selected
		local selected = GuiService.SelectedObject
		for _, entry in self._sliders do
			if entry.frame == selected then
				local step = if key == Enum.KeyCode.DPadLeft then -PAD_STEP else PAD_STEP
				self:_setFraction(entry, self:_fraction(entry) + step)
			end
		end
	end)
	for _, attribute in { "MasterVolume", "MusicVolume", "SfxVolume", "Sensitivity", "DamageNumbers", "EnemyOutlines" } do
		gui:GetAttributeChangedSignal(attribute):Connect(function()
			if self._mode then
				self:_renderSettings()
			end
		end)
	end
end

function PauseMenuController:_fraction(entry): number
	local value = tonumber(UiKit.playerGui():GetAttribute(entry.attribute)) or entry.low
	return math.clamp((value - entry.low) / (entry.high - entry.low), 0, 1)
end

function PauseMenuController:_setFraction(entry, fraction: number)
	fraction = math.clamp(fraction, 0, 1)
	local value = entry.low + (entry.high - entry.low) * fraction
	UiKit.playerGui():SetAttribute(entry.attribute, math.floor(value * 100 + 0.5) / 100)
	self:_renderSlider(entry)
end

function PauseMenuController:_dragTo(entry, screenX: number)
	local frame = entry.frame
	local width = frame.AbsoluteSize.X
	if width > 0 then
		self:_setFraction(entry, (screenX - frame.AbsolutePosition.X) / width)
	end
end

function PauseMenuController:_renderSlider(entry)
	local fraction = self:_fraction(entry)
	UiKit.fill(entry.fill, fraction)
	local knob = entry.knob
	if knob and knob:IsA("GuiObject") then
		knob.Position = UDim2.new(fraction, 0, knob.Position.Y.Scale, knob.Position.Y.Offset)
	end
	local value = tonumber(UiKit.playerGui():GetAttribute(entry.attribute)) or entry.low
	UiKit.text(entry.value, entry.fmt(value))
end

function PauseMenuController:_renderSettings()
	for _, entry in self._sliders do
		self:_renderSlider(entry)
	end
	local gui = UiKit.playerGui()
	UiKit.show(self._numbersCheck, gui:GetAttribute("DamageNumbers") ~= false)
	UiKit.show(self._outlinesCheck, gui:GetAttribute("EnemyOutlines") == true)
end

return PauseMenuController

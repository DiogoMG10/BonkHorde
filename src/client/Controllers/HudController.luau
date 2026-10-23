--!nonstrict
-- HudController - everything in the Hud ScreenGui: the vitals card, purse,
-- objectives, team, timer, boss bars, banners, toasts, minimap frame and the
-- build tray.
--
-- It draws what StateController mirrors and what the server announces. Nothing
-- here decides anything; a missing element is skipped with one warning.
--
-- Layout: every cluster lives in Hud.Safe, which this controller lays over
-- Roblox's CoreUISafeInsets (the top bar and the device's cut-outs) and scales
-- with Core/HudLayout, so nothing sits under Roblox's own buttons and small
-- screens get a compact arrangement at a legible size. The full-screen layers
-- (HurtFlash, DownedOverlay, Letterbox) stay outside it, edge to edge.
--
--   top edge     the XP strip (its own ScreenGui, XpBar, over the level-up
--                panels): the whole width of the screen, just under Roblox's bar
--   top left     Vitals (level, shield, HP), Purse, objectives, team
--   top centre   one column: timer plate, LEVEL UP!, overtime pill, boss bars,
--                banner, toast, pickup popup; nothing there can cover anything
--   top right    minimap (MinimapController draws in it)
--   bottom       interact prompt over the build tray (items, weapons | tomes)
--
-- The XP strip wears a flowing rainbow for as long as a level-up waits for
-- this player's choice (Core/XpStrip): from the offer arriving until the last
-- waiting one is answered, through Refresh, Banish and a panel opened over it.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local HudLayout = require(ReplicatedStorage.Shared.Core.HudLayout)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Spawn = require(ReplicatedStorage.Shared.Core.Spawn)
local Stats = require(ReplicatedStorage.Shared.Core.Stats)
local XpStrip = require(ReplicatedStorage.Shared.Core.XpStrip)
local UiFonts = require(script.Parent.Parent.UiFonts)
local UiKit = require(script.Parent.Parent.UiKit)

local HudController = Knit.CreateController({ Name = "HudController" })

local player = Players.LocalPlayer

local BANNER_SECONDS = 3.2
local SURGE_BANNER_SECONDS = 2
local TOAST_SECONDS = 4
local PICKUP_SECONDS = 1.6
local LEVELUP_SECONDS = 1.6 -- the LEVEL UP! popup; the strip's rainbow follows the choice instead
local TITLE_LINGER = 1.5
local LOW_HP = 0.3 -- the HP bar's rim pulses below this share
local SLOT_GAP = 6
local ITEM_GAP = 4
local RAINBOW_TURN = 2.4 -- seconds for the rainbow's colours to flow one full turn
local RAINBOW_STEP = 1 / 30 -- how often the flow is redrawn
local RAINBOW_IN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RAINBOW_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local INK = Color3.fromHex("#FFF7E8")
local SOFT = Color3.fromHex("#D7CFBC")
local TAN = Color3.fromHex("#D9B45A")
local RIM = Color3.fromHex("#D9B85C")
local GOLD = Color3.fromHex("#FFCB45")
local XP = Color3.fromHex("#45A3FF")
local HP = Color3.fromHex("#F2554D")
local DONE = Color3.fromHex("#7BD957")
local TRACK = Color3.fromHex("#0A110D")
local DANGER = Color3.fromHex("#FF6A4D")
local DANGER_BG = Color3.fromHex("#3A1411")
local OVERTIME_INK = Color3.fromHex("#FF8C73")
local WARN_INK = Color3.fromHex("#FFB347")
local REVIVE_BG = Color3.fromHex("#2A2214")
local BOSS_INK = Color3.fromHex("#FF8A6B")
local GREY = Color3.fromHex("#8A8A8A")
local WHITE = Color3.new(1, 1, 1)

local QUICK = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLASH = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function signature(list, a: string, b: string): string
	local parts = table.create(#list)
	for i, entry in list do
		parts[i] = `{entry[a]}:{entry[b]}`
	end
	return table.concat(parts, ",")
end

local function tween(inst: Instance?, info: TweenInfo, goal)
	if inst then
		local t = TweenService:Create(inst, info, goal)
		t:Play()
		return t
	end
	return nil
end

--- A short grow-and-settle on one element (scaled about its anchor point).
local function pop(inst: Instance?, from: number?)
	if not inst or not inst:IsA("GuiObject") then
		return
	end
	local scale = inst:FindFirstChild("Pop")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = inst
	end
	scale.Scale = from or 1.25
	tween(scale, POP, { Scale = 1 })
end

--- The rim of a panel lights up, then settles back.
local function flashRim(inst: Instance?, colour: Color3?)
	local rim = inst and inst:FindFirstChild("Stroke")
	if rim and rim:IsA("UIStroke") then
		if rim:GetAttribute("BaseTransparency") == nil then
			rim:SetAttribute("BaseTransparency", rim.Transparency)
		end
		if rim:GetAttribute("BaseColor") == nil then
			rim:SetAttribute("BaseColor", rim.Color)
		end
		local base, baseColour = rim:GetAttribute("BaseTransparency"), rim:GetAttribute("BaseColor")
		rim.Transparency = 0
		rim.Color = colour or WHITE
		tween(rim, FLASH, { Transparency = base, Color = baseColour })
	end
end

local function setOffset(inst: Instance?, prop: string, x: number, y: number)
	if inst and inst:IsA("GuiObject") then
		local value = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
		if inst[prop] ~= value then
			inst[prop] = value
		end
	end
end

function HudController:KnitInit()
	-- the top centre column moved or grew (OverlayController keeps its notice under it)
	self.TopChanged = Signal.new()
	self._latch = XpStrip.latch()
	self._rainbowOn = false
	self._e = {}
	self._templates = {}
	self._clones = { weapons = {}, tomes = {}, quests = {}, mates = {}, items = {}, minis = {} }
	self._sigs = {}
	self._bars = {}
	self._barState = {}
	self._fades = {}
	self._seen = { weapons = nil, tomes = nil, items = nil, quests = nil }
	self._tombs = {} -- tombstone id -> owner userId
	self._revives = {} -- userId -> { value, at }
	self._layoutQueued = false
end

function HudController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._world = Knit.GetController("WorldController")
	self._choices = Knit.GetController("ChoiceController")
	UiKit.safe("HudController", function()
		self:_start()
	end)
end

--- Where the top centre column ends, in pixels from the top of the screen, or
--- nil while the HUD is off. Anything drawn under it from another screen (the
--- pause notice) starts there.
function HudController:TopBottom(): number?
	local column = self._e.topCenter
	if not (self._hud and self._hud.Enabled and column) then
		return nil
	end
	local origin = UiKit.insets().origin
	return column.AbsolutePosition.Y + column.AbsoluteSize.Y - origin.Y
end

function HudController:_start()
	local hud = UiKit.gui("Hud")
	if not hud then
		return
	end
	self._hud = hud
	local state = self._state

	local function f(path: string): Instance?
		return UiKit.find(hud, path)
	end
	local e = self._e
	e.safe = f("Safe")
	e.topLeft = f("Safe.TopLeft")
	e.vitals = f("Safe.TopLeft.Vitals")
	e.badge = f("Safe.TopLeft.Vitals.LevelBadge")
	e.level = f("Safe.TopLeft.Vitals.LevelBadge.LevelLabel")
	e.levelCaption = f("Safe.TopLeft.Vitals.LevelBadge.LevelCaption")
	e.shieldBar = f("Safe.TopLeft.Vitals.Bars.ShieldBar")
	e.shieldFill = f("Safe.TopLeft.Vitals.Bars.ShieldBar.Fill")
	e.shieldText = f("Safe.TopLeft.Vitals.Bars.ShieldBar.Text")
	e.hpBar = f("Safe.TopLeft.Vitals.Bars.HPBar")
	e.hpFill = f("Safe.TopLeft.Vitals.Bars.HPBar.Fill")
	e.hpTrail = f("Safe.TopLeft.Vitals.Bars.HPBar.Trail")
	e.hpText = f("Safe.TopLeft.Vitals.Bars.HPBar.Text")
	e.goldIcon = f("Safe.TopLeft.Purse.Gold.Icon")
	e.gold = f("Safe.TopLeft.Purse.Gold.GoldCount")
	e.nextChest = f("Safe.TopLeft.Purse.NextChest")
	e.chestPrice = f("Safe.TopLeft.Purse.NextChest.Price")
	e.silver = f("Safe.TopLeft.Purse.Silver.SilverCount")
	e.kills = f("Safe.TopLeft.Purse.Kills.KillCount")
	e.questTracker = f("Safe.TopLeft.QuestTracker")
	e.teammates = f("Safe.TopLeft.TeammateBars")
	e.topCenter = f("Safe.TopCenter")
	e.plate = f("Safe.TopCenter.TimerPlate")
	e.timerCaption = f("Safe.TopCenter.TimerPlate.TimerCaption")
	e.stageTimer = f("Safe.TopCenter.TimerPlate.StageTimer")
	e.runClock = f("Safe.TopCenter.TimerPlate.RunClock")
	e.pill = f("Safe.TopCenter.DifficultyPill")
	e.tierName = f("Safe.TopCenter.DifficultyPill.TierName")
	e.tierMult = f("Safe.TopCenter.DifficultyPill.TierMult")
	e.bossBars = f("Safe.TopCenter.BossBars")
	e.bossMain = f("Safe.TopCenter.BossBars.Main")
	e.bossMainName = f("Safe.TopCenter.BossBars.Main.Name")
	e.bossMainFill = f("Safe.TopCenter.BossBars.Main.Back.Fill")
	e.bossMainTrail = f("Safe.TopCenter.BossBars.Main.Back.Trail")
	e.bossMainText = f("Safe.TopCenter.BossBars.Main.Text")
	e.bossMinis = f("Safe.TopCenter.BossBars.Minis")
	e.banner = f("Safe.TopCenter.Banner")
	e.bannerText = f("Safe.TopCenter.Banner.BannerText")
	e.bannerSub = f("Safe.TopCenter.Banner.BannerSub")
	e.bannerRules = { f("Safe.TopCenter.Banner.RuleTop"), f("Safe.TopCenter.Banner.RuleBottom") }
	e.toast = f("Safe.TopCenter.Toast")
	e.toastPortrait = f("Safe.TopCenter.Toast.ToastPortrait")
	e.toastTitle = f("Safe.TopCenter.Toast.ToastTitle")
	e.toastText = f("Safe.TopCenter.Toast.ToastText")
	e.topRight = f("Safe.TopRight")
	e.prompt = f("Safe.BottomCenter.InteractPrompt")
	e.promptKeyCap = f("Safe.BottomCenter.InteractPrompt.KeyCap")
	e.promptKey = f("Safe.BottomCenter.InteractPrompt.KeyCap.Key")
	e.promptText = f("Safe.BottomCenter.InteractPrompt.Text")
	e.tray = f("Safe.BottomCenter.BuildTray")
	e.itemStrip = f("Safe.BottomCenter.BuildTray.ItemStrip")
	e.loadout = f("Safe.BottomCenter.BuildTray.Loadout")
	e.weaponRow = f("Safe.BottomCenter.BuildTray.Loadout.WeaponRow")
	e.tomeRow = f("Safe.BottomCenter.BuildTray.Loadout.TomeRow")
	e.pickupToast = f("Safe.TopCenter.PickupToast")
	e.levelUp = f("Safe.TopCenter.LevelUpText")
	e.stageTitle = f("Safe.StageTitle")
	e.stageTier = f("Safe.StageTitle.TierLabel")
	e.stageName = f("Safe.StageTitle.StageName")
	e.stageJoke = f("Safe.StageTitle.StageJoke")
	e.letterbox = f("Letterbox")
	e.downed = f("DownedOverlay")
	e.reviveFill = f("DownedOverlay.ReviveBack.ReviveFill")
	e.spectate = f("DownedOverlay.SpectateName")
	e.hurt = f("HurtFlash")

	-- the XP strip: its own screen, drawn over the level-up panels
	local xpGui = UiKit.gui("XpBar")
	self._xpGui = xpGui
	e.strip = UiKit.find(xpGui, "Strip")
	e.xpBack = UiKit.find(xpGui, "Strip.Back")
	e.xpFill = UiKit.find(xpGui, "Strip.Fill")
	e.rainbow = UiKit.find(xpGui, "Strip.Rainbow")
	e.rainbowGradient = UiKit.find(xpGui, "Strip.Rainbow.Gradient")

	local t = self._templates
	t.weapon = UiKit.template(e.weaponRow, "LoadoutSlot")
	t.tome = UiKit.template(e.tomeRow, "LoadoutSlot") or t.weapon
	t.quest = UiKit.template(e.questTracker, "QuestLine")
	t.mate = UiKit.template(e.teammates, "Teammate")
	t.item = UiKit.template(e.itemStrip, "ItemSlot")
	t.mini = UiKit.template(e.bossMinis, "MiniBar")

	UiKit.fillIcons(hud)
	UiKit.setIcon(e.toastPortrait, "IconExclaim")

	-- the big popups wear the popups role's face (Config/Fonts; `font` in Studio)
	for _, key in { "levelUp", "bannerText", "stageName", "pickupToast" } do
		UiFonts.role(e[key], "popups")
	end

	-- everything that ships visible only as a mockup state starts hidden
	for _, key in
		{
			"pill",
			"bossBars",
			"prompt",
			"banner",
			"stageTitle",
			"letterbox",
			"toast",
			"pickupToast",
			"downed",
			"levelUp",
			"rainbow",
			"teammates",
			"questTracker",
		}
	do
		UiKit.show(e[key], false)
	end
	if e.hurt and e.hurt:IsA("GuiObject") then
		e.hurt.BackgroundTransparency = 1
	end

	self:_watchLayout()
	self:_wireEvents()

	state.Changed:Connect(function(key)
		UiKit.safe("HudController", function()
			if key == "phase" then
				self:_renderPhase()
				self:_renderQuests()
				self:_updateRainbow()
			elseif key == "me" then
				self:_renderMe()
				self:_updateRainbow()
			elseif key == "squad" or key == "roster" then
				self:_renderSquad()
			elseif key == "xp" then
				self:_renderXp()
			elseif key == "profile" then
				self:_renderProfile()
			end
		end)
	end)
	self._choices.OfferChanged:Connect(function()
		UiKit.safe("HudController.offer", function()
			self:_updateRainbow()
		end)
	end)

	-- the top centre column grows and shrinks as its parts come and go
	local topQueued = false
	local function topMoved()
		if topQueued then
			return
		end
		topQueued = true
		task.defer(function()
			topQueued = false
			self.TopChanged:Fire()
		end)
	end
	if e.topCenter then
		e.topCenter:GetPropertyChangedSignal("AbsoluteSize"):Connect(topMoved)
		e.topCenter:GetPropertyChangedSignal("AbsolutePosition"):Connect(topMoved)
	end
	hud:GetPropertyChangedSignal("Enabled"):Connect(topMoved)

	self._world.PromptChanged:Connect(function(text)
		UiKit.safe("HudController", function()
			self:_renderPrompt(text)
		end)
	end)

	self:_renderPhase()
	self:_renderQuests()
	self:_renderMe()
	self:_renderSquad()
	self:_renderXp()
	self:_renderProfile()

	local acc = 0
	local broken = false
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 0.1 or broken then
			return
		end
		local step = acc
		acc = 0
		local ok, err = pcall(function()
			self:_tick(step)
		end)
		if not ok then
			broken = true -- one warning, not one per frame
			warn(`[HudController] tick stopped: {err}`)
		end
	end)
end

-- ---------------------------------------------------------------- layout

--- Take over the Hud's scale from UiKit and follow everything that moves it:
--- the window, Roblox's insets and top bar, the touch buttons, text size.
function HudController:_watchLayout()
	local overlay = UiKit.gui("Overlay")
	local touch = UiKit.find(overlay, "TouchControls", true)
	self._touchButtons = {}
	if touch then
		for _, name in { "TabButton", "PauseButton" } do
			local button = touch:FindFirstChild(name)
			if button and button:IsA("GuiObject") then
				table.insert(self._touchButtons, button)
				button:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
					self:_queueLayout()
				end)
			end
		end
		touch:GetPropertyChangedSignal("Visible"):Connect(function()
			self:_queueLayout()
		end)
	end
	self._touch = touch
	pcall(function()
		GuiService:GetPropertyChangedSignal("PreferredTextSize"):Connect(function()
			self:_queueLayout()
		end)
	end)
	UiKit.ownScale(self._hud, function()
		self:_layout()
	end)
	if self._xpGui then
		-- the strip is laid out with the rest of the HUD
		UiKit.ownScale(self._xpGui, function()
			self:_queueLayout()
		end)
	end
end

function HudController:_queueLayout()
	if self._layoutQueued then
		return
	end
	self._layoutQueued = true
	task.defer(function()
		self._layoutQueued = false
		UiKit.safe("HudController.layout", function()
			self:_layout()
		end)
	end)
end

--- Rects (screen pixels) of the touch buttons the minimap must not cover.
function HudController:_touchRects(origin: Vector2)
	local rects = {}
	local touch = self._touch
	if not touch or not touch.Visible then
		return rects
	end
	local screenGui = touch:FindFirstAncestorOfClass("ScreenGui")
	if screenGui and not screenGui.Enabled then
		return rects
	end
	for _, button in self._touchButtons do
		if button.Visible and button.AbsoluteSize.X > 0 then
			local p, s = button.AbsolutePosition - origin, button.AbsoluteSize
			table.insert(rects, { x0 = p.X, y0 = p.Y, x1 = p.X + s.X, y1 = p.Y + s.Y })
		end
	end
	return rects
end

--- Larger for a larger preferred text size, and on a TV.
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

function HudController:_layout()
	local hud, e = self._hud, self._e
	if not hud then
		return
	end
	local screen = UiKit.insets()
	screen.avoid = self:_touchRects(screen.origin)
	screen.boost = textBoost()
	local layout = HudLayout.compute(screen)
	local old = self._layoutNow
	self._layoutNow = layout

	local scale = UiKit.scaleOf(hud)
	if scale and math.abs(scale.Scale - layout.scale) > 1e-4 then
		scale.Scale = layout.scale
	end
	local m, sizes = HudLayout.Margin, layout.sizes
	setOffset(e.safe, "Position", layout.safe.x, layout.safe.y)
	setOffset(e.safe, "Size", layout.safe.w, layout.safe.h)

	-- the XP strip, on its own screen (the whole viewport, no insets) at the
	-- same scale: the full width of that screen, from its left edge
	local xpScale = self._xpGui and UiKit.scaleOf(self._xpGui)
	if xpScale and math.abs(xpScale.Scale - layout.scale) > 1e-4 then
		xpScale.Scale = layout.scale
	end
	local strip = e.strip
	if strip and strip:IsA("GuiObject") then
		strip.Position = UDim2.fromOffset(0, math.floor(layout.xp.y + 0.5))
		strip.Size = UDim2.new(1, 0, 0, layout.xp.h)
	end

	setOffset(e.topLeft, "Position", m, layout.topLeft)
	setOffset(e.topLeft, "Size", sizes.column, 0)
	setOffset(e.vitals, "Size", sizes.column, sizes.vitals)
	for _, panel in { e.questTracker, e.teammates } do
		setOffset(panel, "Size", math.min(380, sizes.column - 20), 0)
	end

	local centre = layout.centreWidth
	if e.topCenter then
		e.topCenter.Position = UDim2.new(0.5, 0, 0, math.floor(layout.topCentre + 0.5))
	end
	setOffset(e.topCenter, "Size", centre, 0)
	setOffset(e.plate, "Size", sizes.plate, sizes.plateHeight)
	setOffset(e.bossBars, "Size", math.min(760, centre), 0)
	self._miniWidth = math.min(240, (centre - 14) / 2)
	for _, mini in self._clones.minis do
		setOffset(mini, "Size", self._miniWidth, 40)
	end
	setOffset(e.banner, "Size", centre, 96)
	setOffset(e.toast, "Size", math.min(400, centre), 70)

	if e.topRight then
		e.topRight.Position = UDim2.new(1, -math.floor(m + layout.shiftRight + 0.5), 0, math.floor(layout.topRight + 0.5))
	end
	setOffset(e.topRight, "Size", sizes.minimap, sizes.minimap)

	if not old or old.sizes ~= sizes then
		-- slot and item sizes, the item rows and the objective count follow the arrangement
		self._sigs.weapons, self._sigs.tomes, self._sigs.items, self._sigs.quests = nil, nil, nil, nil
		self:_renderMe()
		self:_renderQuests()
	end
end

--- The build tray's size, from the tile sizes and how many item rows show.
function HudController:_layoutTray(itemRows: number)
	local e = self._e
	local sizes = (self._layoutNow or { sizes = HudLayout.Regular }).sizes
	local slot = sizes.slot
	local rowWidth = math.max(GameConfig.WeaponSlots, GameConfig.TomeSlots) * (slot + SLOT_GAP) - SLOT_GAP
	setOffset(e.weaponRow, "Size", rowWidth, slot + 4)
	setOffset(e.tomeRow, "Size", rowWidth, slot + 4)
	local width = 2 * rowWidth + 22
	setOffset(e.loadout, "Size", width, slot + 4)
	local strip = if itemRows > 0 then itemRows * (sizes.item + ITEM_GAP) - ITEM_GAP else 0
	setOffset(e.itemStrip, "Size", width, strip)
	UiKit.show(e.itemStrip, itemRows > 0)
	setOffset(e.tray, "Size", width + 20, 10 + (if strip > 0 then strip + 8 else 0) + slot + 4 + 10)
	return width
end

-- ---------------------------------------------------------------- fades

--- Show or hide a group with a short fade: every transparency under it is
--- remembered once and eased between that and fully clear.
function HudController:_fade(root: GuiObject?, visible: boolean, info: TweenInfo?)
	if not root then
		return
	end
	local list = self._fades[root]
	if not list then
		list = {}
		local function add(inst: Instance)
			if inst:IsA("UIStroke") then
				table.insert(list, { inst, "Transparency", inst.Transparency })
			elseif inst:IsA("TextLabel") then
				table.insert(list, { inst, "TextTransparency", inst.TextTransparency })
				table.insert(list, { inst, "BackgroundTransparency", inst.BackgroundTransparency })
			elseif inst:IsA("ImageLabel") then
				table.insert(list, { inst, "ImageTransparency", inst.ImageTransparency })
				table.insert(list, { inst, "BackgroundTransparency", inst.BackgroundTransparency })
			elseif inst:IsA("Frame") then
				table.insert(list, { inst, "BackgroundTransparency", inst.BackgroundTransparency })
			end
		end
		add(root)
		for _, d in root:GetDescendants() do
			add(d)
		end
		self._fades[root] = list
	end
	local stamp = os.clock()
	root:SetAttribute("FadeStamp", stamp)
	if visible then
		for _, entry in list do
			entry[1][entry[2]] = 1
		end
		root.Visible = true
		for _, entry in list do
			tween(entry[1], info or QUICK, { [entry[2]] = entry[3] })
		end
	elseif root.Visible then
		for _, entry in list do
			tween(entry[1], info or FADE_OUT, { [entry[2]] = 1 })
		end
		task.delay((info or FADE_OUT).Time, function()
			if root:GetAttribute("FadeStamp") == stamp then
				root.Visible = false
				for _, entry in list do
					entry[1][entry[2]] = entry[3]
				end
			end
		end)
	end
end

--- A bar's fill eases to its new share; a pale trail behind it waits a
--- moment on a loss, then follows, so a hit reads as a chunk.
function HudController:_bar(key: string, fill: Instance?, trail: Instance?, fraction: number, instant: boolean?)
	if not fill or not fill:IsA("GuiObject") then
		return
	end
	if fraction ~= fraction then
		fraction = 0
	end
	fraction = math.clamp(fraction, 0, 1)
	local st = self._barState[key]
	if not st then
		st = { value = fraction }
		self._barState[key] = st
		instant = true
	end
	if not instant and math.abs(fraction - st.value) < 1e-4 then
		return
	end
	local down = fraction < st.value
	st.value = fraction
	local goal = UDim2.fromScale(fraction, 1)
	if instant then
		fill.Size = goal
		if trail and trail:IsA("GuiObject") then
			trail.Size = goal
		end
		return
	end
	tween(fill, QUICK, { Size = goal })
	if trail and trail:IsA("GuiObject") then
		if down then
			local stamp = os.clock()
			st.stamp = stamp
			task.delay(0.35, function()
				if st.stamp == stamp then
					tween(trail, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = goal })
				end
			end)
		else
			st.stamp = nil
			trail.Size = goal
		end
	end
	return down
end

-- ---------------------------------------------------------------- server announcements

local BANNER_STYLE = {
	alarm = { ink = DANGER, rule = DANGER },
	win = { ink = GOLD, rule = RIM },
	surge = { ink = GOLD, rule = RIM },
	boss = { ink = BOSS_INK, rule = DANGER, sub = "BOSS" },
	miniboss = { ink = BOSS_INK, rule = DANGER, sub = "MINIBOSS" },
}

function HudController:_wireEvents()
	local e = self._e
	local state = self._state

	local function on(name: string, fn)
		local remote = Net.client(name)
		if remote then
			remote.OnClientEvent:Connect(function(...)
				UiKit.safe(`HudController.{name}`, fn, ...)
			end)
		end
	end

	on("Boss", function(bars)
		self._bars = if typeof(bars) == "table" then bars else {}
		self:_renderBosses()
	end)

	on("Banner", function(text, style, extra)
		text = tostring(text or "")
		if style == "stage" then
			-- the stage card is drawn by the Intro phase; the banner only carries its words
			UiKit.text(e.stageName, string.upper(text))
			UiKit.text(e.stageJoke, if typeof(extra) == "string" then extra else "")
			return
		end
		local look = BANNER_STYLE[style] or { ink = INK, rule = RIM }
		UiKit.text(e.bannerText, text)
		UiKit.textColour(e.bannerText, look.ink)
		local sub = if typeof(extra) == "string" and extra ~= "" then extra else look.sub or ""
		UiKit.text(e.bannerSub, sub)
		UiKit.textColour(e.bannerSub, if look.sub and sub == look.sub then TAN else INK)
		for _, rule in e.bannerRules do
			UiKit.colour(rule, look.rule)
		end
		self:_fade(e.banner, true)
		pop(e.bannerText, 0.85)
		local stamp = os.clock()
		self._bannerStamp = stamp
		-- a surge's banner is brief: they come every minute or so
		task.delay(if style == "surge" then SURGE_BANNER_SECONDS else BANNER_SECONDS, function()
			if self._bannerStamp == stamp then
				self:_fade(e.banner, false)
			end
		end)
	end)

	on("Toast", function(head, text)
		UiKit.text(e.toastTitle, tostring(head or ""))
		UiKit.text(e.toastText, tostring(text or ""))
		self:_fade(e.toast, true)
		pop(e.toastPortrait, 1.3)
		local stamp = os.clock()
		self._toastStamp = stamp
		task.delay(TOAST_SECONDS, function()
			if self._toastStamp == stamp then
				self:_fade(e.toast, false)
			end
		end)
	end)

	-- the hurt flash, low-HP vignette and the bar at the hero's feet: VitalsController

	on("Fx", function(name, a, b)
		if name == "LevelUp" then
			self:_levelUpFx()
		elseif name == "Pickup" and a == state:MyIndex() and e.pickupToast then
			UiKit.text(e.pickupToast, string.upper(tostring(b or "")))
			self:_fade(e.pickupToast, true)
			pop(e.pickupToast, 0.6)
			local stamp = os.clock()
			self._pickupStamp = stamp
			task.delay(PICKUP_SECONDS, function()
				if self._pickupStamp == stamp then
					self:_fade(e.pickupToast, false)
				end
			end)
		end
	end)

	-- every tombstone carries its owner's revive progress: this hero's for the
	-- downed screen, a teammate's for the team panel
	on("InteractableState", function(id, what, value)
		if what == "spawn" and typeof(value) == "table" and value.kind == "Tombstone" and value.owner then
			self._tombs[id] = value.owner
			self._revives[value.owner] = nil
		elseif self._tombs[id] then
			local owner = self._tombs[id]
			if what == "charging" and typeof(value) == "number" then
				self._revives[owner] = { value = value, at = os.clock() }
			elseif what == "gone" then
				self._tombs[id] = nil
				self._revives[owner] = nil
			end
		end
	end)
end

function HudController:_levelUpFx()
	local e = self._e
	local me = self._state.me
	if me and me.complete then
		return -- the server does not send it to a finished build; a late packet is ignored too
	end
	-- the popup is brief; the strip's rainbow lasts until the choice is made
	local stamp = os.clock()
	self._levelStamp = stamp
	self:_fade(e.levelUp, true)
	pop(e.levelUp, 0.5)
	pop(e.level, 1.6)
	flashRim(e.badge, GOLD)
	flashRim(e.vitals, GOLD)
	flashRim(e.xpBack, WHITE)
	self:_updateRainbow()
	task.delay(LEVELUP_SECONDS, function()
		if self._levelStamp == stamp then
			self:_fade(e.levelUp, false)
		end
	end)
end

-- ---------------------------------------------------------------- the strip's rainbow

--- Is a level-up waiting for this player's choice? The server's count in
--- PlayerState, or an offer open here (it arrives a moment before the count).
function HudController:_waitingFacts(): XpStrip.Facts
	local state = self._state
	local me = state.me
	local phase = state.phase
	return {
		live = me ~= nil and (phase == "Playing" or phase == "Overtime"),
		complete = me ~= nil and me.complete == true,
		pending = if me then tonumber(me.levelUps) or 0 else 0,
		offer = self._choices ~= nil and self._choices:HasOffer(),
	}
end

--- Put the rainbow on or off the strip as the choice waits or is made.
function HudController:_updateRainbow()
	local facts = self:_waitingFacts()
	local waiting = XpStrip.waiting(facts)
	local hard = not facts.live or facts.complete
	local on = XpStrip.step(self._latch, waiting, os.clock(), nil, hard)
	if on ~= self._rainbowOn then
		self._rainbowOn = on
		self:_showRainbow(on, hard)
	end
end

function HudController:_showRainbow(on: boolean, instant: boolean?)
	local e = self._e
	local band, gradient = e.rainbow, e.rainbowGradient
	if not (band and band:IsA("GuiObject")) then
		return
	end
	local stamp = os.clock()
	self._rainbowStamp = stamp
	if self._rainbowFade then
		self._rainbowFade:Cancel()
		self._rainbowFade = nil
	end
	local rim = e.xpBack and e.xpBack:FindFirstChild("Stroke")
	if on then
		if not band.Visible then
			band.BackgroundTransparency = 1
			band.Visible = true
		end
		self._rainbowFade = tween(band, RAINBOW_IN, { BackgroundTransparency = 0 })
		self:_flowRainbow(true, gradient, rim)
	elseif instant then
		band.Visible = false
		band.BackgroundTransparency = 1
		self:_flowRainbow(false, gradient, rim)
	else
		-- back to the plain bar: the rainbow fades off what the fill now shows
		self._rainbowFade = tween(band, RAINBOW_OUT, { BackgroundTransparency = 1 })
		task.delay(RAINBOW_OUT.Time, function()
			if self._rainbowStamp == stamp then
				band.Visible = false
				self:_flowRainbow(false, gradient, rim)
			end
		end)
	end
end

--- The rainbow's colours flow along the strip and its rim breathes, redrawn a
--- few dozen times a second while it shows; nothing runs while it does not.
function HudController:_flowRainbow(on: boolean, gradient: Instance?, rim: Instance?)
	if self._flowConn then
		self._flowConn:Disconnect()
		self._flowConn = nil
	end
	local stroke = if rim and rim:IsA("UIStroke") then rim else nil
	if stroke then
		if stroke:GetAttribute("BaseColor") == nil then
			stroke:SetAttribute("BaseColor", stroke.Color)
			stroke:SetAttribute("BaseTransparency", stroke.Transparency)
		end
		stroke.Color = stroke:GetAttribute("BaseColor")
		stroke.Transparency = stroke:GetAttribute("BaseTransparency")
		stroke.Thickness = 1.5
	end
	if not on or not (gradient and gradient:IsA("UIGradient")) then
		return
	end
	local acc = RAINBOW_STEP
	local started = os.clock()
	self._flowConn = RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < RAINBOW_STEP then
			return
		end
		acc = 0
		local t = os.clock() - started
		local keys = XpStrip.rainbow(t / RAINBOW_TURN) -- flowing the way the bar fills
		local points = table.create(#keys)
		for i, k in keys do
			points[i] = ColorSequenceKeypoint.new(k[1], Color3.new(k[2], k[3], k[4]))
		end
		gradient.Color = ColorSequence.new(points)
		if stroke then
			local glow = 0.5 + 0.5 * math.sin(t * math.pi * 2 / 1.2)
			stroke.Color = GOLD:Lerp(WHITE, glow)
			stroke.Transparency = 0.25 - 0.2 * glow
			stroke.Thickness = 1.5 + glow
		end
	end)
end

-- ---------------------------------------------------------------- renders

function HudController:_renderPhase()
	local e = self._e
	local state = self._state
	local phase = state.phase
	local intro = phase == "Intro"

	UiKit.show(e.letterbox, intro)
	if intro then
		local map = Roster.Maps[state.roster.map] or Roster.Maps[Roster.MapOrder[1]]
		UiKit.text(e.stageTier, "Tier 1")
		UiKit.text(e.stageName, string.upper(map.name))
		UiKit.text(e.stageJoke, map.joke or "")
		self:_fade(e.stageTitle, true, TweenInfo.new(0.5))
		self._titleStamp = os.clock()
	elseif e.stageTitle and e.stageTitle.Visible then
		local stamp = os.clock()
		self._titleStamp = stamp
		task.delay(if phase == "Lobby" then 0 else TITLE_LINGER, function()
			if self._titleStamp == stamp then
				self:_fade(e.stageTitle, false)
			end
		end)
	end

	if phase == "Lobby" then
		-- a run is over: nothing from it may linger into the next one
		self._bars = {}
		table.clear(self._tombs)
		table.clear(self._revives)
		table.clear(self._barState)
		self._seen = {}
		self._bannerStamp, self._toastStamp, self._pickupStamp, self._levelStamp = nil, nil, nil, nil
		for _, key in { "banner", "toast", "pickupToast", "levelUp", "prompt", "downed", "pill" } do
			UiKit.show(e[key], false)
		end
		-- no level-up waits on the island: the strip is plain for the next run
		self._latch = XpStrip.latch()
		self._xpLevel = nil
		if self._rainbowOn then
			self._rainbowOn = false
			self:_showRainbow(false, true)
		end
		self:_renderBosses()
		self:_renderMe()
		self:_renderSquad()
	end
	self:_applyEnabled()
end

function HudController:_applyEnabled()
	local state = self._state
	local phase = state.phase
	-- hidden in the lobby; behind the end screens once the run is over (the
	-- death screen and the results take the whole screen, MenuController); and
	-- for a player who has no hero in a run that is live
	local over = phase == "Victory" or phase == "Wipe" or phase == "Results"
	local enabled = phase ~= "Lobby" and not over and (state.me ~= nil or phase == "Intro")
	if self._hud.Enabled ~= enabled then
		self._hud.Enabled = enabled
	end
	-- the strip waits for the intro's letterbox to lift
	local strip = self._xpGui
	local stripOn = enabled and state.phase ~= "Intro"
	if strip and strip.Enabled ~= stripOn then
		strip.Enabled = stripOn
	end
end

function HudController:_renderProfile()
	local profile = self._state.profile
	UiKit.text(self._e.silver, UiKit.commas(profile and profile.silver or 0))
end

function HudController:_renderXp()
	local e = self._e
	local state = self._state
	local complete = state.me ~= nil and state.me.complete == true
	if complete ~= self._xpGold then
		-- a finished build wears a full gold strip
		self._xpGold = complete
		UiKit.colour(e.xpFill, if complete then GOLD else XP)
	end
	if complete then
		-- a finished build: the squad's XP still runs for teammates, not for this bar
		self:_bar("xp", e.xpFill, nil, 1, true)
		UiKit.text(e.level, "MAX")
		if e.level and e.level:IsA("TextLabel") then
			e.level.TextSize = 26
		end
		return
	end
	local fraction = state.xp / math.max(state.need, 1)
	-- a new level starts the bar from empty rather than draining it backwards
	local wrapped = self._xpLevel ~= nil and state.level ~= self._xpLevel
	self._xpLevel = state.level
	if wrapped then
		self:_bar("xp", e.xpFill, nil, 0, true)
	end
	self:_bar("xp", e.xpFill, nil, fraction)
	UiKit.text(e.level, tostring(state.level))
	if e.level and e.level:IsA("TextLabel") then
		e.level.TextSize = if state.level >= 100 then 26 else 34
	end
end

--- Weapons or tomes: every slot the build can hold, the empty ones dimmed.
function HudController:_loadout(key: string, row: Instance?, template: Instance?, list, prefix: string, slots: number)
	local sizes = (self._layoutNow or { sizes = HudLayout.Regular }).sizes
	local sig = signature(list, "id", "level") .. `|{sizes.slot}`
	if self._sigs[key] == sig then
		return
	end
	self._sigs[key] = sig
	local before = self._seen[key]
	local now = {}
	local clones = self._clones[key]
	UiKit.clear(clones)
	if not row or not template then
		return
	end
	local slot = sizes.slot
	for i = 1, math.max(slots, #list) do
		local entry = list[i]
		local clone = template:Clone()
		clone.LayoutOrder = i
		setOffset(clone, "Size", slot, slot + 4)
		setOffset(UiKit.find(clone, "Tile"), "Size", slot, slot)
		local iconImage = UiKit.find(clone, "Icon")
		setOffset(iconImage, "Size", slot - 12, slot - 12)
		if iconImage then
			iconImage.Position = UDim2.new(0.5, 0, 0, math.floor(slot / 2))
		end
		local levelLabel = UiKit.find(clone, "Level")
		if entry then
			local maxed = entry.level >= GameConfig.UpgradeMaxLevel
			UiKit.setIcon(iconImage, prefix .. tostring(entry.id))
			UiKit.text(levelLabel, if maxed then "MAX" else tostring(entry.level))
			setOffset(levelLabel, "Size", if maxed then 36 else 28, 18)
			now[entry.id] = entry.level
			if before and (before[entry.id] == nil or before[entry.id] < entry.level) then
				task.defer(pop, iconImage, 1.35)
				task.defer(flashRim, UiKit.find(clone, "Tile"), WHITE)
			end
		else
			UiKit.show(iconImage, false)
			UiKit.show(levelLabel, false)
			local tile = UiKit.find(clone, "Tile")
			if tile and tile:IsA("GuiObject") then
				tile.BackgroundTransparency = 0.55
				local rim = tile:FindFirstChild("Stroke")
				if rim and rim:IsA("UIStroke") then
					rim.Transparency = 0.78
				end
			end
		end
		clone.Parent = row
		table.insert(clones, clone)
	end
	self._seen[key] = now
end

--- Items as small tiles over the loadout, rimmed by rarity, rows centred; a
--- "+N" tile when more are carried than fit.
function HudController:_renderItems(items)
	local e = self._e
	local layout = self._layoutNow or { sizes = HudLayout.Regular }
	local sizes = layout.sizes
	local sig = signature(items, "id", "count") .. `|{sizes.item}|{sizes.itemRows}|{sizes.slot}`
	if self._sigs.items == sig then
		return
	end
	self._sigs.items = sig
	local before = self._seen.items
	local now = {}
	local clones = self._clones.items
	UiKit.clear(clones)

	local tile = sizes.item
	local width = self:_layoutTray(0)
	local strip = HudLayout.strip(#items, width, tile, ITEM_GAP, sizes.itemRows)
	self:_layoutTray(strip.rows)
	local template = self._templates.item
	if not e.itemStrip or not template then
		return
	end
	local total = strip.shown + (if strip.overflow > 0 then 1 else 0)
	for i = 1, total do
		local clone = template:Clone()
		local x, y = HudLayout.cell(i, total, strip.perRow, width, tile, ITEM_GAP)
		setOffset(clone, "Position", x, y)
		setOffset(clone, "Size", tile, tile)
		local iconImage = UiKit.find(clone, "Icon")
		setOffset(iconImage, "Size", tile - 6, tile - 6)
		local count = UiKit.find(clone, "Count")
		local item = items[i]
		if i <= strip.shown and item then
			UiKit.setIcon(iconImage, "IconItem" .. tostring(item.id))
			UiKit.text(count, `x{item.count}`)
			UiKit.show(count, item.count > 1)
			local info = Roster.Items[item.id]
			local rim = clone:FindFirstChild("Stroke")
			if rim and rim:IsA("UIStroke") then
				rim.Color = UiKit.rarityColour(info and info.rarity)
			end
			now[item.id] = item.count
			if before and (before[item.id] or 0) < item.count then
				task.defer(pop, iconImage, 1.45)
			end
		else
			-- the overflow tile
			UiKit.show(iconImage, false)
			if count and count:IsA("TextLabel") then
				count.AnchorPoint = Vector2.new(0.5, 0.5)
				count.Position = UDim2.fromScale(0.5, 0.5)
				count.Size = UDim2.fromScale(1, 1)
				count.TextXAlignment = Enum.TextXAlignment.Center
				count.TextSize = 16
				count.Text = `+{strip.overflow}`
				count.Visible = true
			end
		end
		clone.Parent = e.itemStrip
		table.insert(clones, clone)
	end
	self._seen.items = now
end

function HudController:_renderMe()
	local e = self._e
	local me = self._state.me
	self:_applyEnabled()
	self:_renderXp() -- the level badge turns to MAX with the build

	-- gold, and whether the next chest is within reach
	local gold, price = me and me.gold or 0, me and me.chestPrice or 0
	if self._goldShown and gold > self._goldShown and e.gold then
		e.gold.TextColor3 = WHITE
		tween(e.gold, FLASH, { TextColor3 = GOLD })
		pop(e.goldIcon, 1.3)
	end
	self._goldShown = gold
	UiKit.text(e.gold, UiKit.commas(gold))
	UiKit.text(e.chestPrice, UiKit.commas(price))
	UiKit.show(e.nextChest, me ~= nil)
	local affordable = me ~= nil and price > 0 and gold >= price
	if affordable ~= self._affordable then
		self._affordable = affordable
		UiKit.textColour(e.chestPrice, if affordable then GOLD else TAN)
		local rim = e.nextChest and e.nextChest:FindFirstChild("Stroke")
		if rim and rim:IsA("UIStroke") then
			rim.Transparency = if affordable then 0.05 else 0.6
			rim:SetAttribute("BaseTransparency", rim.Transparency)
		end
		if affordable then
			flashRim(e.nextChest, WHITE)
		end
	end

	-- vitals
	local hp, maxHp = me and me.hp or 0, me and me.maxHp or 0
	local shield, maxShield = me and me.shield or 0, me and me.maxShield or 0
	local hpShare = if maxHp > 0 then hp / maxHp else 0
	local before = self._barState.hp and self._barState.hp.value
	self:_bar("hp", e.hpFill, e.hpTrail, hpShare)
	if before and hpShare > before + 0.001 and e.hpFill then
		-- a heal: the fill glows for a moment
		e.hpFill.BackgroundColor3 = Color3.fromHex("#FFC2B0")
		tween(e.hpFill, FLASH, { BackgroundColor3 = HP })
	end
	UiKit.text(e.hpText, `{math.max(0, math.ceil(hp))} / {math.floor(maxHp)}`)
	self:_lowHp(me ~= nil and not me.downed and maxHp > 0 and hpShare < LOW_HP)

	UiKit.show(e.shieldBar, maxShield >= 1)
	local shieldShare = if maxShield > 0 then shield / maxShield else 0
	local hadShield = self._barState.shield and self._barState.shield.value > 0.001
	self:_bar("shield", e.shieldFill, nil, shieldShare)
	if hadShield and shieldShare <= 0.001 and e.shieldBar then
		-- the shield breaks: its track flashes
		e.shieldBar.BackgroundColor3 = WHITE
		tween(e.shieldBar, FLASH, { BackgroundColor3 = TRACK })
	end
	UiKit.text(e.shieldText, `{math.max(0, math.floor(shield))} / {math.floor(maxShield)}`)

	self:_loadout("weapons", e.weaponRow, self._templates.weapon, me and me.weapons or {}, "Icon", GameConfig.WeaponSlots)
	self:_loadout("tomes", e.tomeRow, self._templates.tome, me and me.tomes or {}, "IconTome", GameConfig.TomeSlots)
	self:_renderItems(me and me.items or {})

	local downed = me ~= nil and me.downed == true
	if downed and not (e.downed and e.downed.Visible) then
		self._revives[player.UserId] = nil
	end
	UiKit.show(e.downed, downed)
end

--- Below LOW_HP the HP bar's rim pulses red until HP comes back.
function HudController:_lowHp(low: boolean)
	if low == (self._lowTween ~= nil) then
		return
	end
	local rim = self._e.hpBar and self._e.hpBar:FindFirstChild("Stroke")
	if not rim or not rim:IsA("UIStroke") then
		return
	end
	if self._lowTween then
		self._lowTween:Cancel()
		self._lowTween = nil
		rim.Color = Color3.fromHex("#0D1410")
		rim.Transparency = 0.35
		rim.Thickness = 1.5
	end
	if low then
		rim.Color = DANGER
		rim.Thickness = 2.5
		rim.Transparency = 0.6
		self._lowTween = tween(rim, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0 })
	end
end

function HudController:_renderQuests()
	local e = self._e
	local layout = self._layoutNow or { sizes = HudLayout.Regular }
	local all = self._state.quests or {}
	local quests = HudLayout.quests(all, layout.sizes.quests)
	local sig = signature(quests, "text", "done")
	if self._sigs.quests == sig then
		return
	end
	self._sigs.quests = sig
	local before = self._seen.quests
	local now = {}
	UiKit.clear(self._clones.quests)
	local template = self._templates.quest
	UiKit.show(e.questTracker, #quests > 0)
	if not e.questTracker or not template then
		return
	end
	local fresh = false
	for i, quest in quests do
		local line = template:Clone()
		line.LayoutOrder = i
		local done = quest.done == true
		local text = UiKit.find(line, "Text")
		local box = UiKit.find(line, "Box")
		local check = UiKit.find(line, "Check")
		UiKit.text(text, tostring(quest.text))
		UiKit.textColour(text, if done then SOFT else INK)
		UiKit.show(check, done)
		UiKit.colour(box, if done then DONE else TRACK)
		if box and box:IsA("GuiObject") then
			box.BackgroundTransparency = if done then 0 else 0.2
			local rim = box:FindFirstChild("Stroke")
			if rim and rim:IsA("UIStroke") then
				rim.Color = if done then DONE else TAN
			end
		end
		line.Parent = e.questTracker
		table.insert(self._clones.quests, line)
		now[quest.text] = done
		if before then
			if before[quest.text] == nil then
				fresh = true
				task.defer(pop, box, 1.6)
			elseif done and not before[quest.text] then
				task.defer(pop, check, 1.8)
				task.defer(flashRim, e.questTracker, DONE)
			end
		end
	end
	if fresh then
		flashRim(e.questTracker, GOLD)
	end
	self._seen.quests = now
end

function HudController:_mates()
	local mates = {}
	for _, mate in self._state.squad do
		if mate.userId ~= player.UserId then
			table.insert(mates, mate)
		end
	end
	return mates
end

function HudController:_renderSquad()
	local e = self._e
	local mates = self:_mates()
	local sig = signature(mates, "userId", "hero")
	local clones = self._clones.mates
	if self._sigs.mates ~= sig then
		self._sigs.mates = sig
		UiKit.clear(clones)
		local template = self._templates.mate
		if e.teammates and template then
			for i, mate in mates do
				local row = template:Clone()
				row.LayoutOrder = i
				UiKit.setIcon(UiKit.find(row, "Portrait"), "Portrait" .. tostring(mate.hero))
				row.Parent = e.teammates
				table.insert(clones, row)
			end
		end
	end
	-- solo runs carry no team panel at all
	UiKit.show(e.teammates, #mates > 0)
	self:_renderMates(mates)

	local alive = 0
	for _, mate in mates do
		if not mate.downed then
			alive += 1
		end
	end
	UiKit.text(e.spectate, if alive > 0 then "A teammate can revive you: hold on" else "")
end

--- Names, health, shields, and who is down or being revived.
function HudController:_renderMates(mates)
	local names = {}
	for _, entry in self._state.roster.players do
		names[entry.userId] = entry.name
	end
	for i, mate in mates do
		local row = self._clones.mates[i]
		if row then
			UiKit.text(UiKit.find(row, "Name"), names[mate.userId] or "Teammate")
			local fill = UiKit.find(row, "HPBack.HPFill")
			local shieldFill = UiKit.find(row, "HPBack.ShieldFill", true)
			local tag = UiKit.find(row, "DownedTag")
			local portrait = UiKit.find(row, "Portrait")
			local revive = self._revives[mate.userId]
			if mate.downed then
				local progress = revive and revive.value or 0
				UiKit.fill(fill, progress)
				UiKit.colour(fill, GOLD)
				UiKit.fill(shieldFill, 0)
				UiKit.text(tag, if progress > 0 then "REVIVING" else "DOWN")
				UiKit.textColour(tag, if progress > 0 then GOLD else DANGER)
				UiKit.colour(tag, if progress > 0 then REVIVE_BG else DANGER_BG)
				if portrait and portrait:IsA("ImageLabel") then
					portrait.ImageColor3 = GREY
				end
			else
				UiKit.fill(fill, if mate.maxHp > 0 then mate.hp / mate.maxHp else 0)
				UiKit.colour(fill, HP)
				local maxShield = mate.maxShield or 0
				UiKit.fill(shieldFill, if maxShield > 0 then (mate.shield or 0) / maxShield else 0)
				if portrait and portrait:IsA("ImageLabel") then
					portrait.ImageColor3 = WHITE
				end
			end
			UiKit.show(tag, mate.downed == true)
		end
	end
end

local function hpText(hp: number, maxHp: number): string
	return `{UiKit.commas(math.max(0, math.ceil(hp)))} / {UiKit.commas(maxHp)}`
end

function HudController:_renderBosses()
	local e = self._e
	local main = nil
	local minis = {}
	for _, bar in self._bars do
		if bar.stage and not main then
			main = bar
		else
			table.insert(minis, bar)
		end
	end
	local any = main ~= nil or #minis > 0
	if any and e.bossBars and not e.bossBars.Visible then
		self:_fade(e.bossBars, true, TweenInfo.new(0.3))
	elseif not any then
		UiKit.show(e.bossBars, false)
		self._barState.boss = nil
	end
	UiKit.show(e.bossMain, main ~= nil)
	if main then
		UiKit.text(e.bossMainName, string.upper(tostring(main.name)))
		self:_bar("boss", e.bossMainFill, e.bossMainTrail, if main.maxHp > 0 then main.hp / main.maxHp else 0)
		UiKit.text(e.bossMainText, hpText(main.hp, main.maxHp))
	end

	local sig = signature(minis, "slot", "name")
	local clones = self._clones.minis
	if self._sigs.minis ~= sig then
		self._sigs.minis = sig
		UiKit.clear(clones)
		local template = self._templates.mini
		if e.bossMinis and template then
			for i, bar in minis do
				local row = template:Clone()
				row.LayoutOrder = i
				setOffset(row, "Size", self._miniWidth or 240, 40)
				UiKit.text(UiKit.find(row, "Name"), string.upper(tostring(bar.name)))
				row.Parent = e.bossMinis
				table.insert(clones, row)
			end
		end
	end
	UiKit.show(e.bossMinis, #minis > 0)
	for i, bar in minis do
		local row = clones[i]
		if row then
			UiKit.fill(UiKit.find(row, "Back.Fill"), if bar.maxHp > 0 then bar.hp / bar.maxHp else 0)
			UiKit.text(UiKit.find(row, "Text"), hpText(bar.hp, bar.maxHp))
		end
	end
end

function HudController:_renderPrompt(text: string?)
	local e = self._e
	if not text then
		UiKit.show(e.prompt, false)
		self._promptShown = nil
		return
	end
	local inputType = UserInputService:GetLastInputType()
	local gamepad = string.sub(inputType.Name, 1, 7) == "Gamepad"
	local touch = inputType == Enum.UserInputType.Touch
	-- on touch the Interact button is the key; the prompt only says what it does
	UiKit.show(e.promptKeyCap, not touch)
	UiKit.text(e.promptKey, if gamepad then "X" else "E")
	UiKit.text(e.promptText, text)
	if self._promptShown ~= text then
		self._promptShown = text
		if not (e.prompt and e.prompt.Visible) then
			self:_fade(e.prompt, true)
			pop(e.promptKeyCap, 1.3)
		end
	end
	UiKit.show(e.prompt, true)
end

-- ---------------------------------------------------------------- ten times a second

function HudController:_tick(dt: number)
	local e = self._e
	local state = self._state
	self:_applyEnabled()
	if self._rainbowOn then
		self:_updateRainbow() -- the hold after the last choice runs out here
	end
	if not self._hud.Enabled then
		return
	end

	local clock = state:Clock()
	UiKit.text(e.runClock, UiKit.clock(clock))
	UiKit.text(e.kills, UiKit.commas(state.kills))

	local overtime = state.phase == "Overtime"
	if overtime ~= self._overtimeShown then
		self._overtimeShown = overtime
		local rim = e.plate and e.plate:FindFirstChild("Stroke")
		if rim and rim:IsA("UIStroke") then
			rim.Color = if overtime then DANGER else RIM
			rim.Transparency = if overtime then 0.15 else 0.4
			rim:SetAttribute("BaseColor", rim.Color)
			rim:SetAttribute("BaseTransparency", rim.Transparency)
		end
		UiKit.text(e.timerCaption, if overtime then "OVERTIME" else "FINAL HORDE IN")
		UiKit.textColour(e.timerCaption, if overtime then DANGER else TAN)
		if overtime then
			self:_fade(e.pill, true)
			flashRim(e.plate, DANGER)
		else
			UiKit.show(e.pill, false)
		end
	end
	if overtime then
		UiKit.text(e.stageTimer, UiKit.clock(clock - state.stage))
		UiKit.textColour(e.stageTimer, OVERTIME_INK)
		local names = GameConfig.OvertimeNames
		local tier = math.max(state.tier, 1)
		UiKit.text(e.tierName, string.upper(names[math.clamp(tier, 1, #names)]))
		-- how much tougher the horde now is than when overtime began
		local power = Spawn.overtimeHP(tier, GameConfig.OvertimeHPGrowth, GameConfig.OvertimeHPMax) / 1.5
		UiKit.text(e.tierMult, "x" .. Stats.format("int", math.floor(power * 10 + 0.5) / 10))
		if self._tierShown and tier > self._tierShown then
			flashRim(e.pill, WHITE)
			pop(e.tierName, 1.3)
		end
		self._tierShown = tier
	else
		self._tierShown = nil
		local live = state.phase == "Playing" or state.phase == "Intro"
		local left = math.max(0, state.stage - clock)
		UiKit.text(e.stageTimer, if live then UiKit.clock(left) else "")
		-- the last half minute warms up; the last ten seconds beat
		UiKit.textColour(e.stageTimer, if live and left <= 30 then WARN_INK else INK)
		local second = math.ceil(left)
		if live and state.phase == "Playing" and second <= 10 and second > 0 and second ~= self._beat then
			pop(e.stageTimer, 1.18)
		end
		self._beat = second
	end

	-- revive progress drains when nobody is standing on the tombstone
	local now = os.clock()
	local reviving = false
	for userId, revive in self._revives do
		if now - revive.at > 0.6 and revive.value > 0 then
			revive.value = math.max(0, revive.value - dt * 2 / GameConfig.ReviveSeconds)
		end
		if revive.value <= 0 then
			self._revives[userId] = nil
		else
			reviving = true
		end
	end
	if e.downed and e.downed.Visible then
		local mine = self._revives[player.UserId]
		UiKit.fill(e.reviveFill, mine and mine.value or 0)
	end
	if reviving or self._wasReviving then
		self:_renderMates(self:_mates())
	end
	self._wasReviving = reviving
end

return HudController

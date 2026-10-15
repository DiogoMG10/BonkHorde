--!nonstrict
-- HudController - everything in the Hud ScreenGui: the bars, counters, timers,
-- loadout rows, quest tracker, teammates, boss bars, banners and toasts.
--
-- It draws what StateController mirrors and what the server announces. Nothing
-- here decides anything; a missing element is skipped with one warning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Stats = require(ReplicatedStorage.Shared.Core.Stats)
local UiKit = require(script.Parent.Parent.UiKit)

local HudController = Knit.CreateController({ Name = "HudController" })

local player = Players.LocalPlayer

local BANNER_SECONDS = 3.2
local TOAST_SECONDS = 4
local PICKUP_SECONDS = 1.6
local LEVELUP_SECONDS = 1.6
local TITLE_LINGER = 1.5

local function signature(list, a: string, b: string): string
	local parts = table.create(#list)
	for i, entry in list do
		parts[i] = `{entry[a]}:{entry[b]}`
	end
	return table.concat(parts, ",")
end

function HudController:KnitInit()
	self._e = {}
	self._templates = {}
	self._clones = { weapons = {}, tomes = {}, quests = {}, mates = {}, items = {}, minis = {} }
	self._sigs = {}
	self._bars = {}
	self._revive = 0
	self._reviveAt = 0
	self._tombId = nil
end

function HudController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._world = Knit.GetController("WorldController")
	UiKit.safe("HudController", function()
		self:_start()
	end)
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
	e.xpFill = f("XPBar.Fill")
	e.rainbow = f("XPBar.Rainbow")
	e.runClock = f("RunClock")
	e.silver = f("SilverCount")
	e.gold = f("GoldCount")
	e.kills = f("KillCount")
	e.stageTimer = f("StageTimer")
	e.pill = f("DifficultyPill")
	e.tierName = f("DifficultyPill.TierName")
	e.tierMult = f("DifficultyPill.TierMult")
	e.level = f("LevelLabel")
	e.nextChest = f("NextChest")
	e.chestPrice = f("NextChest.Price")
	e.shieldBar = f("ShieldBar")
	e.shieldFill = f("ShieldBar.Fill")
	e.shieldText = f("ShieldBar.Text")
	e.hpFill = f("HPBar.Fill")
	e.hpText = f("HPBar.Text")
	e.weaponRow = f("WeaponRow")
	e.tomeRow = f("TomeRow")
	e.questTracker = f("QuestTracker")
	e.teammates = f("TeammateBars")
	e.itemStrip = f("ItemStrip")
	e.bossBars = f("BossBars")
	e.bossMain = f("BossBars.Main")
	e.bossMainName = f("BossBars.Main.Name")
	e.bossMainFill = f("BossBars.Main.Back.Fill")
	e.bossMainText = f("BossBars.Main.Text")
	e.bossMinis = f("BossBars.Minis")
	e.prompt = f("InteractPrompt")
	e.promptKey = f("InteractPrompt.Key")
	e.promptText = f("InteractPrompt.Text")
	e.banner = f("Banner")
	e.bannerText = f("Banner.BannerText")
	e.bannerSub = f("Banner.BannerSub")
	e.stageTitle = f("StageTitle")
	e.stageTier = f("StageTitle.TierLabel")
	e.stageName = f("StageTitle.StageName")
	e.stageJoke = f("StageTitle.StageJoke")
	e.letterbox = f("Letterbox")
	e.toast = f("Toast")
	e.toastPortrait = f("Toast.ToastPortrait")
	e.toastTitle = f("Toast.ToastTitle")
	e.toastText = f("Toast.ToastText")
	e.pickupToast = f("PickupToast")
	e.downed = f("DownedOverlay")
	e.reviveFill = f("DownedOverlay.ReviveBack.ReviveFill")
	e.spectate = f("DownedOverlay.SpectateName")
	e.hurt = f("HurtFlash")
	e.levelUp = f("LevelUpText")

	local t = self._templates
	t.weapon = UiKit.template(e.weaponRow, "LoadoutSlot")
	t.tome = UiKit.template(e.tomeRow, "LoadoutSlot") or t.weapon
	t.quest = UiKit.template(e.questTracker, "QuestLine")
	t.mate = UiKit.template(e.teammates, "Teammate")
	t.item = UiKit.template(e.itemStrip, "ItemSlot")
	t.mini = UiKit.template(e.bossMinis, "MiniBar")

	UiKit.fillIcons(hud)
	UiKit.setIcon(e.toastPortrait, "IconExclaim")

	-- everything that ships visible only as a mockup state starts hidden
	for _, key in
		{ "pill", "bossBars", "prompt", "banner", "stageTitle", "letterbox", "toast", "pickupToast", "downed", "levelUp", "rainbow" }
	do
		UiKit.show(e[key], false)
	end
	if e.hurt and e.hurt:IsA("GuiObject") then
		e.hurt.BackgroundTransparency = 1
	end

	self:_wireEvents()

	state.Changed:Connect(function(key)
		UiKit.safe("HudController", function()
			if key == "phase" then
				self:_renderPhase()
				self:_renderQuests()
			elseif key == "me" then
				self:_renderMe()
			elseif key == "squad" or key == "roster" then
				self:_renderSquad()
			elseif key == "xp" then
				self:_renderXp()
			elseif key == "profile" then
				self:_renderProfile()
			end
		end)
	end)

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

-- ---------------------------------------------------------------- server announcements

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
		UiKit.text(e.bannerText, text)
		UiKit.textColour(
			e.bannerText,
			if style == "alarm" then UiKit.Colours.red elseif style == "win" then UiKit.Colours.gold else UiKit.Colours.ink
		)
		UiKit.text(e.bannerSub, if typeof(extra) == "string" then extra else "")
		UiKit.show(e.banner, true)
		local stamp = os.clock()
		self._bannerStamp = stamp
		task.delay(BANNER_SECONDS, function()
			if self._bannerStamp == stamp then
				UiKit.show(e.banner, false)
			end
		end)
	end)

	on("Toast", function(head, text)
		UiKit.text(e.toastTitle, tostring(head or ""))
		UiKit.text(e.toastText, tostring(text or ""))
		UiKit.show(e.toast, true)
		local stamp = os.clock()
		self._toastStamp = stamp
		task.delay(TOAST_SECONDS, function()
			if self._toastStamp == stamp then
				UiKit.show(e.toast, false)
			end
		end)
	end)

	-- the hurt flash, low-HP vignette and the bar at the hero's feet: VitalsController

	on("Fx", function(name, a, b)
		if name == "LevelUp" then
			self:_levelUpFx()
		elseif name == "Pickup" and a == state:MyIndex() and e.pickupToast then
			UiKit.text(e.pickupToast, string.upper(tostring(b or "")))
			UiKit.show(e.pickupToast, true)
			local stamp = os.clock()
			self._pickupStamp = stamp
			task.delay(PICKUP_SECONDS, function()
				if self._pickupStamp == stamp then
					UiKit.show(e.pickupToast, false)
				end
			end)
		end
	end)

	-- the local hero's tombstone carries the revive progress
	on("InteractableState", function(id, what, value)
		if what == "spawn" and typeof(value) == "table" and value.kind == "Tombstone" then
			if value.owner == player.UserId then
				self._tombId = id
				self._revive = 0
			end
		elseif id == self._tombId then
			if what == "charging" and typeof(value) == "number" then
				self._revive = value
				self._reviveAt = os.clock()
			elseif what == "gone" then
				self._tombId = nil
				self._revive = 0
			end
		end
	end)
end

function HudController:_levelUpFx()
	local e = self._e
	local stamp = os.clock()
	self._levelStamp = stamp
	UiKit.show(e.rainbow, true)
	local label = e.levelUp
	if label and label:IsA("GuiObject") then
		label.Visible = true
		local pop = label:FindFirstChild("Pop")
		if not pop then
			pop = Instance.new("UIScale")
			pop.Name = "Pop"
			pop.Parent = label
		end
		pop.Scale = 0.5
		TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(LEVELUP_SECONDS, function()
		if self._levelStamp == stamp then
			UiKit.show(e.levelUp, false)
			UiKit.show(e.rainbow, false)
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
		UiKit.show(e.stageTitle, true)
		self._titleStamp = os.clock()
	elseif e.stageTitle and e.stageTitle.Visible then
		local stamp = os.clock()
		self._titleStamp = stamp
		task.delay(if phase == "Lobby" then 0 else TITLE_LINGER, function()
			if self._titleStamp == stamp then
				UiKit.show(e.stageTitle, false)
			end
		end)
	end

	if phase == "Lobby" then
		-- a run is over: nothing from it may linger into the next one
		self._bars = {}
		self._tombId = nil
		self._revive = 0
		self._bannerStamp, self._toastStamp, self._pickupStamp, self._levelStamp = nil, nil, nil, nil
		for _, key in { "banner", "toast", "pickupToast", "levelUp", "rainbow", "prompt", "downed", "pill" } do
			UiKit.show(e[key], false)
		end
		self:_renderBosses()
		self:_renderMe()
		self:_renderSquad()
	end
	self:_applyEnabled()
end

function HudController:_applyEnabled()
	local state = self._state
	-- hidden in the lobby, and for a player who has no hero in a run that is live
	local enabled = state.phase ~= "Lobby" and (state.me ~= nil or state.phase == "Intro")
	if self._hud.Enabled ~= enabled then
		self._hud.Enabled = enabled
	end
end

function HudController:_renderProfile()
	local profile = self._state.profile
	UiKit.text(self._e.silver, UiKit.commas(profile and profile.silver or 0))
end

function HudController:_renderXp()
	local state = self._state
	UiKit.fill(self._e.xpFill, state.xp / math.max(state.need, 1))
	UiKit.text(self._e.level, `LVL {state.level}`)
end

function HudController:_loadout(key: string, row: Instance?, template: Instance?, list, prefix: string)
	local sig = signature(list, "id", "level")
	if self._sigs[key] == sig then
		return
	end
	self._sigs[key] = sig
	local clones = self._clones[key]
	UiKit.clear(clones)
	if not row or not template then
		return
	end
	for i, entry in list do
		local slot = template:Clone()
		slot.LayoutOrder = i
		UiKit.setIcon(UiKit.find(slot, "Icon"), prefix .. tostring(entry.id))
		UiKit.text(UiKit.find(slot, "Level"), `LVL {entry.level}`)
		slot.Parent = row
		table.insert(clones, slot)
	end
end

function HudController:_renderMe()
	local e = self._e
	local me = self._state.me
	self:_applyEnabled()

	UiKit.text(e.gold, UiKit.commas(me and me.gold or 0))
	UiKit.text(e.chestPrice, UiKit.commas(me and me.chestPrice or 0))
	UiKit.show(e.nextChest, me ~= nil)

	local hp, maxHp = me and me.hp or 0, me and me.maxHp or 0
	local shield, maxShield = me and me.shield or 0, me and me.maxShield or 0
	UiKit.fill(e.hpFill, if maxHp > 0 then hp / maxHp else 0)
	UiKit.text(e.hpText, `{math.max(0, math.ceil(hp))}/{math.floor(maxHp)}`)
	UiKit.show(e.shieldBar, maxShield >= 1)
	UiKit.fill(e.shieldFill, if maxShield > 0 then shield / maxShield else 0)
	UiKit.text(e.shieldText, `{math.max(0, math.floor(shield))}/{math.floor(maxShield)}`)

	self:_loadout("weapons", e.weaponRow, self._templates.weapon, me and me.weapons or {}, "Icon")
	self:_loadout("tomes", e.tomeRow, self._templates.tome, me and me.tomes or {}, "IconTome")

	local items = me and me.items or {}
	local sig = signature(items, "id", "count")
	if self._sigs.items ~= sig then
		self._sigs.items = sig
		UiKit.clear(self._clones.items)
		if e.itemStrip and self._templates.item then
			for i, item in items do
				local slot = self._templates.item:Clone()
				slot.LayoutOrder = i
				UiKit.setIcon(UiKit.find(slot, "Icon"), "IconItem" .. tostring(item.id))
				UiKit.text(UiKit.find(slot, "Count"), `x{item.count}`)
				slot.Parent = e.itemStrip
				table.insert(self._clones.items, slot)
			end
		end
	end

	local downed = me ~= nil and me.downed == true
	if downed and not (e.downed and e.downed.Visible) then
		self._revive = 0
	end
	UiKit.show(e.downed, downed)
end

function HudController:_renderQuests()
	local e = self._e
	local quests = self._state.quests or {}
	local sig = signature(quests, "text", "done")
	if self._sigs.quests == sig then
		return
	end
	self._sigs.quests = sig
	UiKit.clear(self._clones.quests)
	local template = self._templates.quest
	if not e.questTracker or not template then
		return
	end
	for i, quest in quests do
		local line = template:Clone()
		line.LayoutOrder = i
		UiKit.text(UiKit.find(line, "Text"), tostring(quest.text))
		UiKit.show(UiKit.find(line, "Check"), quest.done == true)
		UiKit.colour(UiKit.find(line, "Box"), if quest.done then UiKit.Colours.green else UiKit.Colours.ink)
		line.Parent = e.questTracker
		table.insert(self._clones.quests, line)
	end
end

function HudController:_renderSquad()
	local e = self._e
	local state = self._state
	local mates = {}
	for _, mate in state.squad do
		if mate.userId ~= player.UserId then
			table.insert(mates, mate)
		end
	end
	local names = {}
	for _, entry in state.roster.players do
		names[entry.userId] = entry.name
	end

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
	for i, mate in mates do
		local row = clones[i]
		if row then
			UiKit.text(UiKit.find(row, "Name"), names[mate.userId] or "Teammate")
			UiKit.fill(UiKit.find(row, "HPBack.HPFill"), if mate.maxHp > 0 then mate.hp / mate.maxHp else 0)
			UiKit.show(UiKit.find(row, "DownedTag"), mate.downed == true)
		end
	end

	local alive = 0
	for _, mate in mates do
		if not mate.downed then
			alive += 1
		end
	end
	UiKit.text(e.spectate, if alive > 0 then "A teammate can revive you: hold on" else "")
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
	UiKit.show(e.bossBars, main ~= nil or #minis > 0)
	UiKit.show(e.bossMain, main ~= nil)
	if main then
		UiKit.text(e.bossMainName, tostring(main.name))
		UiKit.fill(e.bossMainFill, if main.maxHp > 0 then main.hp / main.maxHp else 0)
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
				UiKit.text(UiKit.find(row, "Name"), tostring(bar.name))
				row.Parent = e.bossMinis
				table.insert(clones, row)
			end
		end
	end
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
		return
	end
	local gamepad = string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
	UiKit.text(e.promptKey, if gamepad then "X" else "E")
	UiKit.text(e.promptText, text)
	UiKit.show(e.prompt, true)
end

-- ---------------------------------------------------------------- ten times a second

function HudController:_tick(dt: number)
	local e = self._e
	local state = self._state
	self:_applyEnabled()
	if not self._hud.Enabled then
		return
	end

	local clock = state:Clock()
	UiKit.text(e.runClock, UiKit.clock(clock))
	UiKit.text(e.kills, UiKit.commas(state.kills))

	local overtime = state.phase == "Overtime"
	if overtime then
		UiKit.text(e.stageTimer, UiKit.clock(clock - state.stage))
		UiKit.textColour(e.stageTimer, UiKit.Colours.red)
		local names = GameConfig.OvertimeNames
		local tier = math.max(state.tier, 1)
		UiKit.text(e.tierName, names[math.clamp(tier, 1, #names)])
		UiKit.text(e.tierMult, "x" .. Stats.format("int", 1 + tier * GameConfig.OvertimeSilverStep))
	else
		local live = state.phase == "Playing" or state.phase == "Intro"
		UiKit.text(e.stageTimer, if live then UiKit.clock(math.max(0, state.stage - clock)) else "")
		UiKit.textColour(e.stageTimer, UiKit.Colours.ink)
	end
	UiKit.show(e.pill, overtime)

	-- revive progress drains when nobody is standing on the tombstone
	if e.downed and e.downed.Visible then
		if os.clock() - self._reviveAt > 0.6 and self._revive > 0 then
			self._revive = math.max(0, self._revive - dt * 2 / GameConfig.ReviveSeconds)
		end
		UiKit.fill(e.reviveFill, self._revive)
	end
end

return HudController

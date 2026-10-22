--!nonstrict
-- ChoiceController - the Choices ScreenGui: upgrade offers on a level-up, and
-- the chest, shrine, shop and statue panels, flanked by the inventory and the
-- stats sheet.
--
-- The server sends an offer or a panel and waits for one answer; this
-- controller draws it and sends back "id, action, index". It never applies a
-- choice itself.
--
-- Every panel locks for a moment when it lands (T1, Core/InputGuard): its
-- buttons are dimmed, nothing that commits a choice answers, and after the lock
-- only a press that began after it does, so a click meant for the fight cannot.
-- Level-up cards also pop in. Dodgy Dan's Leave costs nothing and is never locked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local InputGuard = require(ReplicatedStorage.Shared.Core.InputGuard)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Stats = require(ReplicatedStorage.Shared.Core.Stats)
local UiKit = require(script.Parent.Parent.UiKit)

local ChoiceController = Knit.CreateController({ Name = "ChoiceController" })

local UI_KEY = "choices"
-- a weapon's own numbers do not all read like the hero stat of the same name
local WEAPON_FMT = { Size = "pct", CritChance = "pct", CritDamage = "pct" }
local CONFETTI = {
	Color3.fromHex("#FFD23A"),
	Color3.fromHex("#35D04A"),
	Color3.fromHex("#11B4F4"),
	Color3.fromHex("#FF4D9A"),
	Color3.fromHex("#B04DFF"),
	Color3.fromHex("#FFFFFF"),
}
local SOLD_FILL = Color3.fromHex("#2B2B2B")
-- a locked offer's veil: nearly opaque while a card pops in, then a dim haze
local VEIL = Color3.fromHex("#08130D")
local VEIL_IN, VEIL_DIM = 0.1, 0.45
local POP_SECONDS, POP_STAGGER = 0.13, 0.06 -- three cards in about 0.25 s
-- after an answer is sent, nothing more is sent until the server replies (or this
-- long, for an answer it refused without a word): no double purchase on a double click
local AWAIT_SECONDS = 0.5

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

-- a locked button neither answers nor takes the gamepad selection
local function setLive(button: Instance?, live: boolean)
	if button and button:IsA("GuiButton") then
		button.Selectable = live
		pcall(function()
			button.Interactable = live
		end)
	end
end

local function signature(list, a: string, b: string): string
	local parts = table.create(#list)
	for i, entry in list do
		parts[i] = `{entry[a]}:{entry[b]}`
	end
	return table.concat(parts, ",")
end

function ChoiceController:KnitInit()
	-- an upgrade offer opened, was re-dealt or closed (the HUD's XP strip follows it)
	self.OfferChanged = Signal.new()
	self._e = {}
	self._templates = {}
	self._clones = { offers = {}, shrine = {}, shop = {}, statue = {}, items = {} }
	self._offers = nil -- the open upgrade offer, as the server sent it
	self._panel = nil -- the open chest / shrine / shop / statue panel
	self._showing = nil
	self._banishMode = false
	self._deadline = nil
	self._guard = InputGuard.new()
	self._unlocked = true -- the open offer's lock has ended (or there is none)
	self._freshHand = false -- the next render draws a new hand: veil it in
	self._popIn = false -- ... and pop the cards in (a new offer, not a reroll)
	self._veils = {}
	self._lockables = {} -- the shown view's buttons that commit something
	self._awaitUntil = 0
	self._timerFrom = nil
	self._hot = {}
	self._statValues = {}
	self._weaponSlots = {}
	self._tomeSlots = {}
end

function ChoiceController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._camera = Knit.GetController("CameraController")
	self._audio = Knit.GetController("AudioController")
	UiKit.safe("ChoiceController", function()
		self:_start()
	end)
end

--- Is an offer or a panel on screen?
function ChoiceController:IsOpen(): boolean
	return self._showing ~= nil
end

--- Is an upgrade offer waiting for this player's choice (on screen, or under a
--- chest or shrine panel)? Refresh and Banish re-deal it without closing it.
function ChoiceController:HasOffer(): boolean
	return self._offers ~= nil
end

-- ---------------------------------------------------------------- text

--- The label and the before / after values of one stat line of an offer.
function ChoiceController:LineParts(kind: string, line): (string, string, string)
	local def = Roster.Stats[line.stat]
	local fmt = if kind == "weapon" then (WEAPON_FMT[line.stat] or "int") else (def and def.fmt or "int")
	local name = if def then def.name else tostring(line.stat)
	local from = line.from or 0
	local to = line.to or (from + (line.amount or 0))
	return name .. ":", Stats.format(fmt, from), Stats.format(fmt, to)
end

-- ---------------------------------------------------------------- setup

function ChoiceController:_start()
	local gui = UiKit.gui("Choices")
	if not gui then
		return
	end
	self._gui = gui
	local state = self._state

	local function f(path: string): Instance?
		return UiKit.find(gui, path)
	end
	local e = self._e
	e.fx = f("LevelUpFx")
	e.rays = f("LevelUpFx.RayBurst")
	e.confetti = f("LevelUpFx.Confetti")
	e.inventory = f("InventoryPanel")
	e.weaponSlots = f("InventoryPanel.WeaponSlots")
	e.tomeSlots = f("InventoryPanel.TomeSlots")
	e.itemGrid = f("InventoryPanel.ItemGrid")
	e.stats = f("StatsPanel")
	e.statRows = f("StatsPanel.Rows")

	e.upgrade = f("UpgradeOffers")
	e.upgradeTitle = f("UpgradeOffers.Header.Title")
	e.upgradeCards = f("UpgradeOffers.Cards")
	e.banish = f("UpgradeOffers.Footer.BanishButton")
	e.banishLabel = f("UpgradeOffers.Footer.BanishButton.Label")
	e.banishCount = f("UpgradeOffers.Footer.BanishButton.Count")
	e.skip = f("UpgradeOffers.Footer.SkipButton")
	e.skipCount = f("UpgradeOffers.Footer.SkipButton.Count")
	e.refresh = f("UpgradeOffers.Footer.RefreshButton")
	e.refreshCount = f("UpgradeOffers.Footer.RefreshButton.Count")
	e.timer = f("UpgradeOffers.Footer.ChoiceTimer")

	e.chest = f("ChestPanel")
	e.chestRarity = f("ChestPanel.RarityWord")
	e.chestName = f("ChestPanel.ItemName")
	e.chestText = f("ChestPanel.ItemText")
	e.chestRays = f("ChestPanel.Stage.LightRays")
	e.chestSprite = f("ChestPanel.Stage.ItemSprite")
	e.chestBanish = f("ChestPanel.Footer.BanishButton")
	e.chestBanishCount = f("ChestPanel.Footer.BanishButton.Count")
	e.chestTake = f("ChestPanel.Footer.TakeButton")

	e.shrine = f("ShrineOffers")
	e.shrineRows = f("ShrineOffers.Rows")
	e.shrineIgnore = f("ShrineOffers.IgnoreRow")

	e.shop = f("ShopPanel")
	e.shopCards = f("ShopPanel.Cards")
	e.shopGold = f("ShopPanel.Footer.GoldLabel")
	e.shopLeave = f("ShopPanel.Footer.LeaveButton")

	e.statue = f("StatueOffers")
	e.statueCards = f("StatueOffers.Cards")
	e.statueSkip = f("StatueOffers.Footer.SkipButton")

	local t = self._templates
	t.offer = UiKit.template(e.upgradeCards, "OfferCard")
	t.line = UiKit.template(UiKit.find(t.offer, "Lines"), "StatLine")
	t.reward = UiKit.template(e.shrineRows, "RewardRow")
	t.shopCard = UiKit.template(e.shopCards, "ShopCard")
	t.itemCard = UiKit.template(e.statueCards, "ItemCard")
	t.invItem = UiKit.template(e.itemGrid, "InvItem")
	local invSlot = UiKit.template(e.weaponSlots, "InvSlot")
	local tomeSlot = UiKit.template(e.tomeSlots, "InvSlot") or invSlot
	local statRow = UiKit.template(e.statRows, "StatRow")
	local statGap = UiKit.template(e.statRows, "StatGap")

	UiKit.fillIcons(gui)

	-- the fixed loadout slots: an empty one keeps its frame and hides its icon
	local function buildSlots(container: Instance?, template: Instance?, count: number, into)
		if not container or not template then
			return
		end
		for i = 1, count do
			local slot = template:Clone()
			slot.LayoutOrder = i
			slot.Parent = container
			into[i] = slot
		end
	end
	buildSlots(e.weaponSlots, invSlot, GameConfig.WeaponSlots, self._weaponSlots)
	buildSlots(e.tomeSlots, tomeSlot, GameConfig.TomeSlots, self._tomeSlots)

	-- the 30 stat rows, in roster order, with a gap between groups
	if e.statRows and statRow then
		local order = 0
		for groupIndex, group in Roster.StatGroups do
			for _, key in group do
				local def = Roster.Stats[key]
				order += 1
				local row = statRow:Clone()
				row.LayoutOrder = order
				UiKit.text(UiKit.find(row, "Name"), if def then def.name else key)
				self._statValues[key] = UiKit.find(row, "Value")
				row.Parent = e.statRows
			end
			if statGap and groupIndex < #Roster.StatGroups then
				order += 1
				local gap = statGap:Clone()
				gap.LayoutOrder = order
				gap.Parent = e.statRows
			end
		end
	end

	for _, key in { "fx", "inventory", "stats", "upgrade", "chest", "shrine", "shop", "statue" } do
		UiKit.show(e[key], false)
	end

	-- ------------------------------------------------------------ answers

	local chooseRemote = Net.client("ChooseOffer")
	local panelChoice = Net.client("PanelChoice")

	local function answered(): boolean
		local now = os.clock()
		if now < self._awaitUntil then
			return false
		end
		self._awaitUntil = now + AWAIT_SECONDS
		return true
	end
	local function choose(action: string, index: number?)
		local data = self._offers
		if data and chooseRemote and answered() then
			chooseRemote:FireServer(data.id, action, index or 0)
		end
	end
	local function send(action: string, index: number?)
		local p = self._panel
		if p and panelChoice and answered() then
			panelChoice:FireServer(p.id, action, index or 0)
		end
	end
	self._choose = choose
	self._send = send

	-- a button that commits a choice answers only a fresh press after the lock
	local function guarded(fn: () -> ()): (InputObject?) -> ()
		return function(input: InputObject?)
			if self:_accepts(input) then
				fn()
			end
		end
	end
	self._guarded = guarded

	UiKit.button(
		e.banish,
		guarded(function()
			local data = self._offers
			if not data then
				return
			end
			if not self._banishMode and (data.charges and data.charges.banish or 0) <= 0 then
				return
			end
			self._banishMode = not self._banishMode
			self:_renderOffers()
		end)
	)
	UiKit.button(
		e.skip,
		guarded(function()
			choose("skip", 0)
		end)
	)
	UiKit.button(
		e.refresh,
		guarded(function()
			choose("refresh", 0)
		end)
	)
	UiKit.button(
		e.chestTake,
		guarded(function()
			send("take")
		end)
	)
	UiKit.button(
		e.chestBanish,
		guarded(function()
			send("banish")
		end)
	)
	UiKit.button(
		e.shrineIgnore,
		guarded(function()
			send("ignore")
		end)
	)
	UiKit.button(e.shopLeave, function()
		send("leave") -- free, and the shop opens again: never locked
	end)
	UiKit.button(
		e.statueSkip,
		guarded(function()
			send("skip")
		end)
	)

	-- ------------------------------------------------------------ what the server opens

	local offers = Net.client("Offers")
	if offers then
		offers.OnClientEvent:Connect(function(data)
			UiKit.safe("ChoiceController.Offers", function()
				local hand = if typeof(data) == "table" then data else nil
				local reroll = hand ~= nil and self._offers ~= nil and self._offers.id == hand.id
				self._offers = hand
				self._banishMode = false
				self._awaitUntil = 0
				local lock = if hand
					then tonumber(hand.lock) or (if reroll then GameConfig.OfferLockFollowSeconds else GameConfig.OfferLockSeconds)
					else 0
				-- co-op's clock counts down from the end of the server's lock
				self._timerFrom = if hand then os.clock() + lock else nil
				-- under an open panel the offer is hidden: it locks when it shows again
				if not self._panel then
					self:_lockView(if hand then lock else nil, not reroll)
				end
				self._deadline = if self._offers and (tonumber(data.seconds) or 0) > 0 then os.clock() + data.seconds else nil
				self:_refresh()
			end)
			self.OfferChanged:Fire(self._offers ~= nil)
		end)
	end
	local panelEvent = Net.client("Panel")
	if panelEvent then
		panelEvent.OnClientEvent:Connect(function(p)
			UiKit.safe("ChoiceController.Panel", function()
				local panel = if typeof(p) == "table" then p else nil
				local again = panel ~= nil and self._panel ~= nil and self._panel.id == panel.id
				self._panel = panel
				self._awaitUntil = 0
				if panel then
					local fallback = if again
						then GameConfig.PanelLockAgainSeconds
						else GameConfig.PanelLockSeconds[panel.kind] or GameConfig.PanelLockAgainSeconds
					self:_lockView(tonumber(panel.lock) or fallback)
				elseif self._offers then
					-- the level-up that waited underneath shows again
					self:_lockView(GameConfig.OfferLockFollowSeconds)
				else
					self:_lockView(nil)
				end
				self:_refresh()
			end)
		end)
	end

	state.Changed:Connect(function(key)
		UiKit.safe("ChoiceController", function()
			if key == "me" then
				if self._showing then
					self:_renderSide()
				end
			elseif key == "phase" and not state:IsLive() and (self._offers or self._panel) then
				-- the run ended under an open panel: the server has already dropped it
				local hadOffer = self._offers ~= nil
				self._offers, self._panel = nil, nil
				self:_lockView(nil)
				self:_refresh()
				if hadOffer then
					self.OfferChanged:Fire(false)
				end
			end
		end)
	end)

	-- every press and release, even the ones the interface takes, so a press
	-- held across a panel opening is known to be stale
	UserInputService.InputBegan:Connect(function(input)
		self._guard:press(inputKey(input), os.clock())
	end)
	UserInputService.InputEnded:Connect(function(input)
		self._guard:release(inputKey(input), os.clock())
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		self._guard:dropHeld()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self._showing or self:_locked() then
			return
		end
		local index = input.KeyCode.Value - Enum.KeyCode.One.Value + 1
		local fn = self._hot[index]
		if index >= 1 and index <= 9 and fn then
			UiKit.safe("ChoiceController.key", fn)
		end
	end)

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		self:_locked() -- unlocks the panel on the frame its lock ends
		if self._showing ~= "offers" then
			return
		end
		if e.rays and e.rays:IsA("GuiObject") then
			e.rays.Rotation = (e.rays.Rotation + dt * 10) % 360
		end
		acc += dt
		if acc >= 0.1 then
			acc = 0
			self:_renderTimer()
		end
	end)
end

-- ---------------------------------------------------------------- which panel is up

function ChoiceController:_refresh()
	local e = self._e
	local showing: string? = nil
	if self._panel then
		showing = self._panel.kind
	elseif self._offers then
		showing = "offers"
	end
	local was = self._showing
	self._showing = showing
	self._hot = {}

	UiKit.show(e.upgrade, showing == "offers")
	UiKit.show(e.fx, showing == "offers")
	UiKit.show(e.chest, showing == "chest")
	UiKit.show(e.shrine, showing == "shrine")
	UiKit.show(e.shop, showing == "shop")
	UiKit.show(e.statue, showing == "statue")
	UiKit.show(e.inventory, showing ~= nil)
	UiKit.show(e.stats, showing ~= nil)
	self._camera:SetUiOpen(UI_KEY, showing ~= nil)

	if not showing then
		UiKit.unfocus(self._gui)
		return
	end
	self:_renderSide()
	if showing == "offers" then
		self:_renderOffers()
		if was ~= "offers" then
			UiKit.safe("ChoiceController.confetti", function()
				self:_confetti()
			end)
		end
	elseif showing == "chest" then
		self:_renderChest()
	elseif showing == "shrine" then
		self:_renderShrine()
	elseif showing == "shop" then
		self:_renderShop()
	elseif showing == "statue" then
		self:_renderStatue()
	end
end

-- ---------------------------------------------------------------- upgrade offers

function ChoiceController:_renderTimer()
	local e = self._e
	local deadline = self._deadline
	if not deadline then
		UiKit.show(e.timer, false) -- solo: the game is paused, there is no clock
		return
	end
	-- the server added the lock to co-op's clock: it counts down once the cards answer
	local from = math.max(os.clock(), self._timerFrom or 0)
	UiKit.text(e.timer, tostring(math.max(0, math.ceil(deadline - from))))
	UiKit.show(e.timer, true)
end

function ChoiceController:_renderOffers()
	local e = self._e
	local t = self._templates
	local data = self._offers
	local clones = self._clones.offers
	UiKit.clear(clones)
	self._hot = {}
	if not data then
		return
	end
	local banishing = self._banishMode
	local fresh = self:_beginView()
	local pending = tonumber(data.pending) or 0
	UiKit.text(e.upgradeTitle, if pending > 1 then `UPGRADE OFFERS  ({pending} waiting)` else "UPGRADE OFFERS")

	local first: Instance? = nil
	if e.upgradeCards and t.offer then
		for i, offer in data.offers do
			local def = if offer.kind == "weapon" then Roster.Weapons[offer.id] else Roster.Tomes[offer.id]
			local rarity = offer.rarity or "New"
			local card = t.offer:Clone()
			card.LayoutOrder = i
			UiKit.colour(card, if banishing then UiKit.Colours.banishFill else UiKit.cardColour(rarity))
			local tag = UiKit.find(card, "RarityTag")
			UiKit.text(tag, if banishing then "Banish?" else rarity)
			UiKit.textColour(tag, UiKit.rarityColour(rarity))
			UiKit.colour(UiKit.find(card, "IconTile"), UiKit.rarityColour(rarity))
			UiKit.setIcon(UiKit.find(card, "IconTile.Icon"), (if offer.kind == "weapon" then "Icon" else "IconTome") .. tostring(offer.id))
			UiKit.text(UiKit.find(card, "OfferName"), if def then def.name else tostring(offer.id))
			local levelTag = if offer.isNew then "NEW" elseif offer.level >= GameConfig.UpgradeMaxLevel then "MAX" else `LVL {offer.level}`
			UiKit.text(UiKit.find(card, "LevelTag"), levelTag)

			-- a new weapon explains itself; everything else shows what changes
			local describe = offer.isNew == true and offer.kind == "weapon"
			local description = UiKit.find(card, "Description")
			UiKit.text(description, if describe and def then def.text else "")
			UiKit.show(description, describe)
			local lines = UiKit.find(card, "Lines")
			UiKit.show(lines, not describe)
			if lines and t.line and not describe then
				for j, line in offer.lines or {} do
					local label, from, to = self:LineParts(offer.kind, line)
					local row = t.line:Clone()
					row.LayoutOrder = j
					UiKit.text(UiKit.find(row, "Label"), label)
					UiKit.text(UiKit.find(row, "From"), from)
					UiKit.text(UiKit.find(row, "To"), to)
					row.Parent = lines
				end
			end

			local function pick()
				self._choose(if self._banishMode then "banish" else "pick", i)
			end
			UiKit.button(card, self._guarded(pick))
			self._hot[i] = pick
			card.Parent = e.upgradeCards
			table.insert(clones, card)
			first = first or card
			local veil = self:_protect(card)
			if veil and fresh and self._popIn then
				veil.BackgroundTransparency = VEIL_IN
				local info = TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, (i - 1) * POP_STAGGER)
				TweenService:Create(veil, info, { BackgroundTransparency = VEIL_DIM }):Play()
			end
		end
	end

	local charges = data.charges or {}
	UiKit.text(e.banishCount, tostring(charges.banish or 0))
	UiKit.text(e.skipCount, tostring(charges.skip or 0))
	UiKit.text(e.refreshCount, tostring(charges.refresh or 0))
	UiKit.text(e.banishLabel, if banishing then "CANCEL" else "BANISH")
	self:_renderTimer()
	for _, button in { e.banish, e.skip, e.refresh } do
		self:_protect(button)
	end
	if fresh and self._popIn and not self._unlocked then
		self:_pop(0.92, 0.25, Enum.EasingStyle.Back)
	end
	self:_focusFirst(first or e.skip)
end

-- ---------------------------------------------------------------- the lock (T1)

--- Lock the view about to show for `seconds` (nil: nothing is shown, no lock).
--- Whatever is held now turns stale either way.
function ChoiceController:_lockView(seconds: number?, popIn: boolean?)
	if seconds == nil then
		self._guard:clear()
		self._unlocked = true
		return
	end
	self._guard:lock(seconds, os.clock())
	self._unlocked = seconds <= 0 -- a refused purchase re-sends the shop with no lock
	self._freshHand = true
	self._popIn = popIn == true
end

--- Start drawing a view's buttons; true when it is a fresh hand.
function ChoiceController:_beginView(): boolean
	local fresh = self._freshHand
	self._freshHand = false
	table.clear(self._veils)
	table.clear(self._lockables)
	return fresh
end

--- A button that commits a choice: dimmed and dead while the view is locked.
--- Returns its veil when it is locked.
function ChoiceController:_protect(button: Instance?): Frame?
	if not button or not button:IsA("GuiButton") then
		return nil
	end
	table.insert(self._lockables, button)
	if self._unlocked then
		setLive(button, true)
		local old = button:FindFirstChild("LockVeil")
		if old and old:IsA("GuiObject") then
			old.BackgroundTransparency = 1
		end
		return nil
	end
	setLive(button, false)
	local veil = self:_veil(button)
	if veil then
		veil.BackgroundTransparency = VEIL_DIM
	end
	return veil
end

--- The button a gamepad lands on: at once, or when the lock ends (A is also jump).
function ChoiceController:_focusFirst(button: Instance?)
	self._first = button
	if self._unlocked then
		UiKit.focus(button)
	else
		UiKit.unfocus(self._gui)
	end
end

--- Is the shown view still locked? Ends the lock on its first call after it ran out.
function ChoiceController:_locked(): boolean
	if not self._showing or self._unlocked then
		return false
	end
	if self._guard:locked(os.clock()) then
		return true
	end
	self:_unlock()
	return false
end

--- May this press (from a button's Activated, nil when unknown) answer the view?
function ChoiceController:_accepts(input: InputObject?): boolean
	if self:_locked() then
		return false
	end
	local key = if input then inputKey(input) else nil
	return self._guard:accepts(key, os.clock())
end

--- The lock ran out: the veils lift, a soft tick, the gamepad lands on the first option.
function ChoiceController:_unlock()
	self._unlocked = true
	for _, button in self._lockables do
		setLive(button, true)
	end
	local lift = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, veil in self._veils do
		TweenService:Create(veil, lift, { BackgroundTransparency = 1 }):Play()
	end
	if self._showing == "offers" then
		self:_pop(1.025, 0.15, Enum.EasingStyle.Quad)
	end
	local tick = self._audio and self._audio:Play("ui_hover", nil, 1.25)
	if tick then
		tick.Volume *= 0.7
	end
	UiKit.focus(self._first)
end

--- Scale the offer cards from `from` back to full size.
function ChoiceController:_pop(from: number, seconds: number, style: Enum.EasingStyle)
	local cards = self._e.upgradeCards
	if not cards then
		return
	end
	local scale = cards:FindFirstChild("LockPop")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "LockPop"
		scale.Parent = cards
	end
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(seconds, style, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

--- A veil over a button that dims it while its view is locked.
function ChoiceController:_veil(button: Instance?): Frame?
	if not button or not button:IsA("GuiObject") then
		return nil
	end
	local veil = button:FindFirstChild("LockVeil")
	if not veil then
		veil = Instance.new("Frame")
		veil.Name = "LockVeil"
		veil.BorderSizePixel = 0
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = 10
		veil.BackgroundColor3 = VEIL
		local face = button:FindFirstChild("Face")
		local corner = button:FindFirstChildOfClass("UICorner") or (face and face:FindFirstChildOfClass("UICorner"))
		if corner then
			corner:Clone().Parent = veil
		end
		veil.Parent = button
	end
	table.insert(self._veils, veil)
	return veil
end

function ChoiceController:_confetti()
	local holder = self._e.confetti
	if not holder then
		return
	end
	holder:ClearAllChildren()
	for _ = 1, 40 do
		local piece = Instance.new("Frame")
		piece.Name = "Piece"
		piece.BorderSizePixel = 0
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Size = UDim2.fromOffset(math.random(10, 18), math.random(16, 28))
		piece.BackgroundColor3 = CONFETTI[math.random(1, #CONFETTI)]
		piece.Rotation = math.random(0, 359)
		local x = math.random()
		piece.Position = UDim2.fromScale(x, -0.06)
		piece.Parent = holder
		local seconds = 1.4 + math.random() * 1.6
		local tween = TweenService:Create(
			piece,
			TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, math.random() * 0.5),
			{ Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.12, 1.08), Rotation = piece.Rotation + math.random(-360, 360) }
		)
		tween.Completed:Connect(function()
			piece:Destroy()
		end)
		tween:Play()
	end
end

-- ---------------------------------------------------------------- chest, shrine, shop, statue

function ChoiceController:_renderChest()
	local e = self._e
	local p = self._panel
	self:_beginView()
	local data = p.data or {}
	local item = Roster.Items[data.item]
	local rarity = data.rarity or (item and item.rarity) or "Common"
	local colour = UiKit.rarityColour(rarity)
	UiKit.text(e.chestRarity, string.upper(rarity))
	UiKit.textColour(e.chestRarity, colour)
	UiKit.text(e.chestName, if item then item.name else tostring(data.item))
	UiKit.text(e.chestText, if item then item.text else "")
	UiKit.setIcon(e.chestSprite, "IconItem" .. tostring(data.item))
	if e.chestRays then
		for _, ray in e.chestRays:GetChildren() do
			UiKit.colour(ray, colour)
		end
	end
	UiKit.text(e.chestBanishCount, tostring(p.charges and p.charges.banish or 0))
	self._hot = {
		function()
			self._send("take")
		end,
	}
	self:_protect(e.chestTake)
	self:_protect(e.chestBanish)
	self:_focusFirst(e.chestTake)
end

function ChoiceController:_renderShrine()
	local e = self._e
	local t = self._templates
	local p = self._panel
	local clones = self._clones.shrine
	UiKit.clear(clones)
	self:_beginView()
	local first: Instance? = nil
	if e.shrineRows and t.reward then
		for i, offer in (p.data and p.data.offers) or {} do
			local def = Roster.Stats[offer.stat]
			local fmt = if def and def.fmt == "int" then "int" else "pct"
			local amount = Stats.format(fmt, offer.amount or 0)
			local rarity = offer.rarity or "Common"
			local row = t.reward:Clone()
			row.LayoutOrder = i
			UiKit.colour(row, UiKit.cardColour(rarity))
			local tag = UiKit.find(row, "RarityTag")
			UiKit.text(tag, rarity)
			UiKit.textColour(tag, UiKit.rarityColour(rarity))
			UiKit.text(
				UiKit.find(row, "Text"),
				`Gain <font color="{UiKit.GreenHex}">{amount}</font> {if def then def.name else tostring(offer.stat)}`
			)
			local function pick()
				self._send("pick", i)
			end
			UiKit.button(row, self._guarded(pick))
			self._hot[i] = pick
			row.Parent = e.shrineRows
			table.insert(clones, row)
			first = first or row
			self:_protect(row)
		end
	end
	self:_protect(e.shrineIgnore) -- ignoring gives the reward up for good
	self:_focusFirst(first or e.shrineIgnore)
end

--- Fill the parts an item card shares between the shop and the statue.
function ChoiceController:_fillItemCard(card: Instance, id: string)
	local item = Roster.Items[id]
	local rarity = if item then item.rarity else "Common"
	UiKit.colour(card, UiKit.cardColour(rarity))
	local tag = UiKit.find(card, "RarityTag")
	UiKit.text(tag, rarity)
	UiKit.textColour(tag, UiKit.rarityColour(rarity))
	UiKit.colour(UiKit.find(card, "IconTile"), UiKit.rarityColour(rarity))
	UiKit.setIcon(UiKit.find(card, "IconTile.Icon"), "IconItem" .. tostring(id))
	UiKit.text(UiKit.find(card, "ItemName"), if item then item.name else tostring(id))
	UiKit.text(UiKit.find(card, "ItemText"), if item then item.text else "")
end

function ChoiceController:_renderShop()
	local e = self._e
	local t = self._templates
	local p = self._panel
	local clones = self._clones.shop
	UiKit.clear(clones)
	self:_beginView()
	local gold = tonumber(p.gold) or 0
	local first: Instance? = nil
	if e.shopCards and t.shopCard then
		for i, entry in (p.data and p.data.stock) or {} do
			local card = t.shopCard:Clone()
			card.LayoutOrder = i
			self:_fillItemCard(card, entry.item)
			local price = UiKit.find(card, "PriceTag.Price")
			UiKit.text(price, UiKit.commas(entry.price))
			UiKit.textColour(price, if gold >= (entry.price or 0) then UiKit.Colours.gold else UiKit.Colours.red)
			UiKit.show(UiKit.find(card, "SoldTag"), entry.sold == true)
			if entry.sold then
				UiKit.colour(card, SOLD_FILL)
				UiKit.show(UiKit.find(card, "PriceTag"), false)
				if card:IsA("GuiButton") then
					card.Selectable = false
				end
			else
				local function buy()
					self._send("buy", i)
				end
				UiKit.button(card, self._guarded(buy))
				self._hot[i] = buy
				first = first or card
				self:_protect(card)
			end
			card.Parent = e.shopCards
			table.insert(clones, card)
		end
	end
	UiKit.text(e.shopGold, `Your gold: {UiKit.commas(gold)}`)
	self:_focusFirst(first or e.shopLeave)
end

function ChoiceController:_renderStatue()
	local e = self._e
	local t = self._templates
	local p = self._panel
	local clones = self._clones.statue
	UiKit.clear(clones)
	self:_beginView()
	local first: Instance? = nil
	if e.statueCards and t.itemCard then
		for i, id in (p.data and p.data.items) or {} do
			local card = t.itemCard:Clone()
			card.LayoutOrder = i
			self:_fillItemCard(card, id)
			local function pick()
				self._send("pick", i)
			end
			UiKit.button(card, self._guarded(pick))
			self._hot[i] = pick
			card.Parent = e.statueCards
			table.insert(clones, card)
			first = first or card
			self:_protect(card)
		end
	end
	self:_protect(e.statueSkip) -- skipping gives the statue up for good
	self:_focusFirst(first or e.statueSkip)
end

-- ---------------------------------------------------------------- inventory and stats

function ChoiceController:_renderSide()
	local e = self._e
	local me = self._state.me

	local function fillSlots(slots, list, prefix: string)
		for i, slot in slots do
			local entry = list[i]
			local icon = UiKit.find(slot, "Icon")
			UiKit.show(icon, entry ~= nil)
			if entry then
				UiKit.setIcon(icon, prefix .. tostring(entry.id))
			end
			local label = if not entry then "" elseif entry.level >= GameConfig.UpgradeMaxLevel then "MAX" else `LVL {entry.level}`
			UiKit.text(UiKit.find(slot, "Level"), label)
		end
	end
	fillSlots(self._weaponSlots, me and me.weapons or {}, "Icon")
	fillSlots(self._tomeSlots, me and me.tomes or {}, "IconTome")

	local items = me and me.items or {}
	local sig = signature(items, "id", "count")
	if self._itemSig ~= sig then
		self._itemSig = sig
		local clones = self._clones.items
		UiKit.clear(clones)
		if e.itemGrid and self._templates.invItem then
			for i, item in items do
				local cell = self._templates.invItem:Clone()
				cell.LayoutOrder = i
				UiKit.setIcon(UiKit.find(cell, "Icon"), "IconItem" .. tostring(item.id))
				UiKit.text(UiKit.find(cell, "Count"), `x{item.count}`)
				cell.Parent = e.itemGrid
				table.insert(clones, cell)
			end
		end
	end

	local stats = me and me.stats or {}
	for key, label in self._statValues do
		local def = Roster.Stats[key]
		UiKit.text(label, Stats.format(def.fmt, stats[key] or def.default))
	end
end

return ChoiceController

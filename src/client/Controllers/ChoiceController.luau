--!nonstrict
-- ChoiceController - the Choices ScreenGui: upgrade offers on a level-up, and
-- the chest, shrine, shop and statue panels, flanked by the inventory and the
-- stats sheet.
--
-- The server sends an offer or a panel and waits for one answer; this
-- controller draws it and sends back "id, action, index". It never applies a
-- choice itself.

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

local function signature(list, a: string, b: string): string
	local parts = table.create(#list)
	for i, entry in list do
		parts[i] = `{entry[a]}:{entry[b]}`
	end
	return table.concat(parts, ",")
end

function ChoiceController:KnitInit()
	self._e = {}
	self._templates = {}
	self._clones = { offers = {}, shrine = {}, shop = {}, statue = {}, items = {} }
	self._offers = nil -- the open upgrade offer, as the server sent it
	self._panel = nil -- the open chest / shrine / shop / statue panel
	self._showing = nil
	self._banishMode = false
	self._deadline = nil
	self._hot = {}
	self._statValues = {}
	self._weaponSlots = {}
	self._tomeSlots = {}
end

function ChoiceController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._camera = Knit.GetController("CameraController")
	UiKit.safe("ChoiceController", function()
		self:_start()
	end)
end

--- Is an offer or a panel on screen?
function ChoiceController:IsOpen(): boolean
	return self._showing ~= nil
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

	-- the 31 stat rows, in roster order, with a gap between groups
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

	local function choose(action: string, index: number?)
		local data = self._offers
		if data and chooseRemote then
			chooseRemote:FireServer(data.id, action, index or 0)
		end
	end
	local function send(action: string, index: number?)
		local p = self._panel
		if p and panelChoice then
			panelChoice:FireServer(p.id, action, index or 0)
		end
	end
	self._choose = choose
	self._send = send

	UiKit.button(e.banish, function()
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
	UiKit.button(e.skip, function()
		choose("skip", 0)
	end)
	UiKit.button(e.refresh, function()
		choose("refresh", 0)
	end)
	UiKit.button(e.chestTake, function()
		send("take")
	end)
	UiKit.button(e.chestBanish, function()
		send("banish")
	end)
	UiKit.button(e.shrineIgnore, function()
		send("ignore")
	end)
	UiKit.button(e.shopLeave, function()
		send("leave")
	end)
	UiKit.button(e.statueSkip, function()
		send("skip")
	end)

	-- ------------------------------------------------------------ what the server opens

	local offers = Net.client("Offers")
	if offers then
		offers.OnClientEvent:Connect(function(data)
			UiKit.safe("ChoiceController.Offers", function()
				self._offers = if typeof(data) == "table" then data else nil
				self._banishMode = false
				self._deadline = if self._offers and (tonumber(data.seconds) or 0) > 0 then os.clock() + data.seconds else nil
				self:_refresh()
			end)
		end)
	end
	local panelEvent = Net.client("Panel")
	if panelEvent then
		panelEvent.OnClientEvent:Connect(function(p)
			UiKit.safe("ChoiceController.Panel", function()
				self._panel = if typeof(p) == "table" then p else nil
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
				self._offers, self._panel = nil, nil
				self:_refresh()
			end
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self._showing then
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
	UiKit.text(e.timer, tostring(math.max(0, math.ceil(deadline - os.clock()))))
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
			UiKit.button(card, pick)
			self._hot[i] = pick
			card.Parent = e.upgradeCards
			table.insert(clones, card)
			first = first or card
		end
	end

	local charges = data.charges or {}
	UiKit.text(e.banishCount, tostring(charges.banish or 0))
	UiKit.text(e.skipCount, tostring(charges.skip or 0))
	UiKit.text(e.refreshCount, tostring(charges.refresh or 0))
	UiKit.text(e.banishLabel, if banishing then "CANCEL" else "BANISH")
	self:_renderTimer()
	UiKit.focus(first or e.skip)
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
	UiKit.focus(e.chestTake)
end

function ChoiceController:_renderShrine()
	local e = self._e
	local t = self._templates
	local p = self._panel
	local clones = self._clones.shrine
	UiKit.clear(clones)
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
			UiKit.button(row, pick)
			self._hot[i] = pick
			row.Parent = e.shrineRows
			table.insert(clones, row)
			first = first or row
		end
	end
	UiKit.focus(first or e.shrineIgnore)
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
				UiKit.button(card, buy)
				self._hot[i] = buy
				first = first or card
			end
			card.Parent = e.shopCards
			table.insert(clones, card)
		end
	end
	UiKit.text(e.shopGold, `Your gold: {UiKit.commas(gold)}`)
	UiKit.focus(first or e.shopLeave)
end

function ChoiceController:_renderStatue()
	local e = self._e
	local t = self._templates
	local p = self._panel
	local clones = self._clones.statue
	UiKit.clear(clones)
	local first: Instance? = nil
	if e.statueCards and t.itemCard then
		for i, id in (p.data and p.data.items) or {} do
			local card = t.itemCard:Clone()
			card.LayoutOrder = i
			self:_fillItemCard(card, id)
			local function pick()
				self._send("pick", i)
			end
			UiKit.button(card, pick)
			self._hot[i] = pick
			card.Parent = e.statueCards
			table.insert(clones, card)
			first = first or card
		end
	end
	UiKit.focus(first or e.statueSkip)
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

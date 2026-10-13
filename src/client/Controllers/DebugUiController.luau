--!nonstrict
-- DebugUiController - a plain, complete interface for playing the loop before
-- the real screens exist: a text HUD and one list panel that serves the lobby,
-- upgrade offers, chest, shrine, vendor, statue and results.
--
-- It is deliberately unstyled. It stays in the project as the fallback that is
-- always wired to live data; set the attribute BonkDebugUi = false on the
-- player's PlayerGui to hide it once the real HUD is in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Stats = require(ReplicatedStorage.Shared.Core.Stats)

local DebugUiController = Knit.CreateController({ Name = "DebugUiController" })

local player = Players.LocalPlayer
local WEAPON_FMT = { Size = "pct", CritChance = "pct", CritDamage = "pct" }

local function clockText(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function label(parent: Instance, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.BuilderSansBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.3
	l.TextSize = 20
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function DebugUiController:KnitInit()
	self._panelKey = nil
	self._buttons = {}
	self._banishMode = false
end

--- "Damage: 11 -> 13" for one stat line of an offer.
function DebugUiController:LineText(kind: string, line): string
	local def = Roster.Stats[line.stat]
	local fmt = if kind == "weapon" then (WEAPON_FMT[line.stat] or "int") else (def and def.fmt or "int")
	local name = if def then def.name else line.stat
	return `{name}: {Stats.format(fmt, line.from or 0)} -> {Stats.format(fmt, line.to or line.amount)}`
end

function DebugUiController:OfferText(offer): string
	local def = if offer.kind == "weapon" then Roster.Weapons[offer.id] else Roster.Tomes[offer.id]
	if offer.isNew and offer.kind == "weapon" then
		return `NEW  {def.name}: {def.text}`
	end
	local parts = {}
	for _, line in offer.lines do
		table.insert(parts, self:LineText(offer.kind, line))
	end
	local tag = if offer.isNew then "NEW" else `{offer.rarity} LVL {offer.level}`
	return `{tag}  {def.name}: {table.concat(parts, ", ")}`
end

function DebugUiController:KnitStart()
	local state = Knit.GetController("StateController")
	local camera = Knit.GetController("CameraController")
	local world = Knit.GetController("WorldController")
	self._state = state

	local gui = Instance.new("ScreenGui")
	gui.Name = "BonkDebugUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Until the real screens are wired, keep them out of the way of this one.
	if not player.PlayerGui:GetAttribute("BonkRealUi") then
		for _, name in { "Hud", "Choices", "Menu", "EndScreens", "Overlay" } do
			task.spawn(function()
				local screen = player.PlayerGui:WaitForChild(name, 10)
				if screen and screen:IsA("ScreenGui") then
					screen.Enabled = false
				end
			end)
		end
	end

	local hud = label(gui, { Name = "Hud", Position = UDim2.fromOffset(16, 46), Size = UDim2.fromOffset(520, 520), RichText = true })
	local timer = label(gui, {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(300, 44),
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local level = label(gui, {
		Name = "Level",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 40),
		Size = UDim2.fromOffset(240, 44),
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local bosses = label(gui, {
		Name = "Bosses",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(700, 100),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local prompt = label(gui, {
		Name = "Prompt",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(600, 34),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	})
	local banner = label(gui, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(1100, 120),
		TextSize = 56,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = "",
	})
	local toast = label(gui, {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 200),
		Size = UDim2.fromOffset(800, 60),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	})

	local xpBack = Instance.new("Frame")
	xpBack.Name = "XPBar"
	xpBack.Size = UDim2.new(1, 0, 0, 22)
	xpBack.BackgroundColor3 = Color3.fromRGB(12, 14, 16)
	xpBack.BorderSizePixel = 0
	xpBack.Parent = gui
	local xpFill = Instance.new("Frame")
	xpFill.Name = "Fill"
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Color3.fromRGB(17, 180, 244)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBack

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromOffset(760, 520)
	panel.BackgroundColor3 = Color3.fromRGB(34, 42, 37)
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local title = label(panel, { Name = "Title", Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 34), TextSize = 28 })
	local sub = label(
		panel,
		{ Name = "Sub", Position = UDim2.fromOffset(20, 50), Size = UDim2.new(1, -40, 0, 70), TextSize = 18, TextWrapped = true }
	)
	local listFrame = Instance.new("Frame")
	listFrame.Name = "List"
	listFrame.Position = UDim2.fromOffset(20, 126)
	listFrame.Size = UDim2.new(1, -40, 1, -146)
	listFrame.BackgroundTransparency = 1
	listFrame.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = listFrame

	local function showList(key: string?, titleText: string?, subText: string?, entries)
		for _, b in self._buttons do
			b:Destroy()
		end
		table.clear(self._buttons)
		if self._panelKey and self._panelKey ~= key then
			camera:SetUiOpen(self._panelKey, false)
		end
		self._panelKey = key
		if not key then
			panel.Visible = false
			return
		end
		camera:SetUiOpen(key, true)
		panel.Visible = true
		title.Text = titleText or ""
		sub.Text = subText or ""
		for i, entry in entries do
			local b = Instance.new("TextButton")
			b.Name = `Entry{i}`
			b.Size = UDim2.new(1, 0, 0, 44)
			b.BackgroundColor3 = entry.colour or Color3.fromRGB(46, 70, 55)
			b.Font = Enum.Font.BuilderSansBold
			b.TextSize = 18
			b.TextColor3 = Color3.new(1, 1, 1)
			b.TextWrapped = true
			b.Text = (if i <= 9 and entry.hotkey ~= false then `[{i}] ` else "") .. entry.text
			b.AutoButtonColor = entry.fn ~= nil
			b.LayoutOrder = i
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 8)
			c.Parent = b
			if entry.fn then
				b.Activated:Connect(entry.fn)
			end
			b.Parent = listFrame
			table.insert(self._buttons, b)
			b:SetAttribute("Hot", entry.fn ~= nil and entry.hotkey ~= false)
		end
		self._entries = entries
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self._panelKey or not self._entries then
			return
		end
		local index = input.KeyCode.Value - Enum.KeyCode.One.Value + 1
		local entry = self._entries[index]
		if index >= 1 and index <= 9 and entry and entry.fn and entry.hotkey ~= false then
			entry.fn()
		end
	end)

	-- ---------------------------------------------------------------- lobby

	local pickHero, setReady, unlockHero = Net.client("PickHero"), Net.client("SetReady"), Net.client("UnlockHero")
	local function showLobby()
		if state.phase ~= "Lobby" and state.me then
			return
		end
		local profile = state.profile
		local mine
		local squad = {}
		for _, entry in state.roster.players do
			if entry.userId == player.UserId then
				mine = entry
			end
			table.insert(squad, `{entry.name}: {Roster.Heroes[entry.hero].name}{if entry.ready then " (ready)" else ""}`)
		end
		local entries = {}
		for _, id in Roster.HeroOrder do
			local hero = Roster.Heroes[id]
			local unlocked = profile and profile.unlocked[id]
			local picked = mine and mine.hero == id
			if unlocked then
				table.insert(entries, {
					text = `{if picked then "> " else ""}{hero.name}: {Roster.Weapons[hero.weapon].name}. {hero.passiveText}`,
					colour = if picked then Color3.fromRGB(46, 127, 209) else nil,
					fn = function()
						if pickHero then
							pickHero:FireServer(id)
						end
					end,
				})
			else
				table.insert(entries, {
					text = `LOCKED {hero.name}: unlock for {hero.unlockSilver} silver`,
					colour = Color3.fromRGB(60, 60, 60),
					fn = function()
						if unlockHero then
							unlockHero:FireServer(id)
						end
					end,
				})
			end
		end
		local ready = mine and mine.ready
		table.insert(entries, {
			text = if ready then "READY (waiting for the squad) - click to cancel" else "READY UP",
			colour = if ready then Color3.fromRGB(46, 158, 76) else Color3.fromRGB(46, 127, 209),
			fn = function()
				if setReady then
					setReady:FireServer(not ready)
				end
			end,
		})
		local midRun = state.phase ~= "Lobby"
		local silver = if profile then profile.silver else 0
		local note = if profile and not profile.canSave then "  (progress will not save this session)" else ""
		showList(
			"lobby",
			if midRun then "BONK HORDE: a run is in progress, pick a hero to drop in" else "BONK HORDE",
			`Silver: {silver}{note}\nSquad: {table.concat(squad, "  |  ")}`,
			entries
		)
	end

	-- ---------------------------------------------------------------- offers and panels

	local choose = Net.client("ChooseOffer")
	local offers = Net.client("Offers")
	if offers then
		offers.OnClientEvent:Connect(function(data)
			if not data then
				if self._panelKey == "offers" then
					showList(nil)
				end
				return
			end
			self._banishMode = false
			local function render()
				local entries = {}
				for i, offer in data.offers do
					table.insert(entries, {
						text = self:OfferText(offer),
						colour = if self._banishMode then Color3.fromRGB(150, 40, 55) else nil,
						fn = function()
							if choose then
								choose:FireServer(data.id, if self._banishMode then "banish" else "pick", i)
							end
						end,
					})
				end
				table.insert(entries, {
					text = `SKIP ({data.charges.skip} left)`,
					colour = Color3.fromRGB(46, 158, 76),
					hotkey = false,
					fn = function()
						if choose then
							choose:FireServer(data.id, "skip", 0)
						end
					end,
				})
				table.insert(entries, {
					text = `BANISH ({data.charges.banish} left){if self._banishMode then ": now click an offer" else ""}`,
					colour = Color3.fromRGB(179, 38, 58),
					hotkey = false,
					fn = function()
						self._banishMode = not self._banishMode
						render()
					end,
				})
				table.insert(entries, {
					text = `REFRESH ({data.charges.refresh} left)`,
					colour = Color3.fromRGB(46, 127, 209),
					hotkey = false,
					fn = function()
						if choose then
							choose:FireServer(data.id, "refresh", 0)
						end
					end,
				})
				local waiting = if data.seconds > 0 then `Pick within {math.ceil(data.seconds)}s.` else ""
				showList("offers", "UPGRADE OFFERS", `Level {state.level}. {data.pending} choice(s) waiting. {waiting}`, entries)
			end
			render()
		end)
	end

	local panelChoice = Net.client("PanelChoice")
	local panelEvent = Net.client("Panel")
	if panelEvent then
		panelEvent.OnClientEvent:Connect(function(p)
			if not p then
				if self._panelKey == "panel" then
					showList(nil)
				end
				return
			end
			local function send(action: string, index: number?)
				if panelChoice then
					panelChoice:FireServer(p.id, action, index or 0)
				end
			end
			local entries = {}
			local titleText, subText = "", ""
			if p.kind == "chest" then
				local item = Roster.Items[p.data.item]
				titleText = string.upper(p.data.rarity)
				subText = `{item.name}\n{item.text}`
				table.insert(entries, {
					text = "TAKE",
					colour = Color3.fromRGB(46, 127, 209),
					fn = function()
						send("take")
					end,
				})
				table.insert(entries, {
					text = `BANISH ({p.charges.banish} left)`,
					colour = Color3.fromRGB(179, 38, 58),
					fn = function()
						send("banish")
					end,
				})
			elseif p.kind == "shrine" then
				titleText, subText = "CHARGE SHRINE", "The shrine offers you a reward:"
				for i, offer in p.data.offers do
					local def = Roster.Stats[offer.stat]
					local amount = if def.fmt == "int" then Stats.format("int", offer.amount) else Stats.format("pct", offer.amount)
					table.insert(entries, {
						text = `{offer.rarity}: Gain {amount} {def.name}`,
						fn = function()
							send("pick", i)
						end,
					})
				end
				table.insert(entries, {
					text = "Ignore Offers",
					colour = Color3.fromRGB(90, 30, 30),
					fn = function()
						send("ignore")
					end,
				})
			elseif p.kind == "statue" then
				titleText, subText = "ITEM OFFERS", "The statue winks. You feel judged."
				for i, id in p.data.items do
					local item = Roster.Items[id]
					table.insert(entries, {
						text = `{item.rarity}  {item.name}: {item.text}`,
						fn = function()
							send("pick", i)
						end,
					})
				end
				table.insert(entries, {
					text = "SKIP",
					colour = Color3.fromRGB(46, 158, 76),
					fn = function()
						send("skip")
					end,
				})
			elseif p.kind == "shop" then
				titleText, subText = "DODGY DAN'S DEALS", `Everything fell off the back of a cart. Probably.   Your gold: {p.gold}`
				for i, entry in p.data.stock do
					local item = Roster.Items[entry.item]
					table.insert(entries, {
						text = if entry.sold then `SOLD  {item.name}` else `{item.rarity}  {item.name} - {entry.price} gold: {item.text}`,
						colour = if entry.sold then Color3.fromRGB(60, 60, 60) else Color3.fromRGB(74, 67, 9),
						fn = if entry.sold
							then nil
							else function()
								send("buy", i)
							end,
					})
				end
				table.insert(entries, {
					text = "LEAVE",
					colour = Color3.fromRGB(107, 111, 107),
					fn = function()
						send("leave")
					end,
				})
			end
			showList("panel", titleText, subText, entries)
		end)
	end

	local results = Net.client("Results")
	if results then
		results.OnClientEvent:Connect(function(r)
			local rows = {}
			for _, row in r.players do
				table.insert(rows, {
					text = `{row.name} ({Roster.Heroes[row.hero].name}): {row.kills} kills, {row.damage} damage, +{row.silver} silver`,
					hotkey = false,
				})
			end
			local head = if r.victory then "VICTORY" else "you got bonked"
			local detail =
				`{if r.victory then "The boss is bonked." else r.joke}\nKills {r.kills}   Level {r.level}   Time {clockText(r.clock)}`
			showList("results", head, detail, rows)
		end)
	end

	-- ---------------------------------------------------------------- banners, toasts, prompt

	local bannerEvent = Net.client("Banner")
	if bannerEvent then
		bannerEvent.OnClientEvent:Connect(function(text, style, extra)
			banner.Text = if extra and extra ~= "" then `{text}\n{extra}` else text
			banner.TextColor3 = if style == "alarm" then Color3.fromRGB(255, 60, 60) else Color3.new(1, 1, 1)
			local stamp = os.clock()
			self._bannerStamp = stamp
			task.delay(3.2, function()
				if self._bannerStamp == stamp then
					banner.Text = ""
				end
			end)
		end)
	end
	local toastEvent = Net.client("Toast")
	if toastEvent then
		toastEvent.OnClientEvent:Connect(function(head, text)
			toast.Text = `{head}: {text}`
			local stamp = os.clock()
			self._toastStamp = stamp
			task.delay(4, function()
				if self._toastStamp == stamp then
					toast.Text = ""
				end
			end)
		end)
	end
	world.PromptChanged:Connect(function(text)
		prompt.Text = if text then `[E] {text}` else ""
	end)

	local bossBars = {}
	local bossEvent = Net.client("Boss")
	if bossEvent then
		bossEvent.OnClientEvent:Connect(function(bars)
			bossBars = bars
		end)
	end

	state.Changed:Connect(function(key)
		if key == "phase" then
			if state.phase == "Lobby" then
				showLobby()
			elseif self._panelKey == "lobby" or (self._panelKey == "results" and state.phase == "Intro") then
				showList(nil)
			end
		elseif (key == "roster" or key == "profile") and (self._panelKey == "lobby" or (self._panelKey == nil and not state.me)) then
			showLobby()
		elseif key == "me" and self._panelKey == "lobby" and state.me then
			showList(nil)
		end
	end)
	task.defer(showLobby)

	-- ---------------------------------------------------------------- the HUD text

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local visible = gui:GetAttribute("Enabled") ~= false
		hud.Visible, timer.Visible, level.Visible, bosses.Visible = visible, visible, visible, visible
		xpBack.Visible = visible
		xpFill.Size = UDim2.fromScale(math.clamp(state.xp / math.max(state.need, 1), 0, 1), 1)
		level.Text = `LVL {state.level}`
		local clock = state:Clock()
		if state.phase == "Overtime" then
			timer.Text = `{clockText(clock - state.stage)}  tier {state.tier}`
			timer.TextColor3 = Color3.fromRGB(255, 60, 60)
		else
			timer.Text = if state:IsLive() or state.phase == "Intro" then clockText(state.stage - clock) else ""
			timer.TextColor3 = Color3.new(1, 1, 1)
		end

		local me = state.me
		if not me or state.phase == "Lobby" then
			hud.Text = ""
			bosses.Text = ""
			return
		end
		local lines = {
			`time {clockText(clock)}   gold {me.gold}   kills {state.kills}{if state.paused then "   PAUSED" else ""}`,
			`<font color="#12a8e8">shield {math.floor(me.shield)}/{math.floor(me.maxShield)}</font>   <font color="#ff4444">HP {math.ceil(
				me.hp
			)}/{math.floor(me.maxHp)}</font>{if me.downed then "   DOWNED" else ""}`,
		}
		local w = {}
		for _, weapon in me.weapons do
			table.insert(w, `{Roster.Weapons[weapon.id].name} {weapon.level}`)
		end
		table.insert(lines, "weapons: " .. table.concat(w, ", "))
		local t = {}
		for _, tome in me.tomes do
			table.insert(t, `{Roster.Tomes[tome.id].name} {tome.level}`)
		end
		table.insert(lines, "tomes: " .. table.concat(t, ", "))
		local it = {}
		for _, item in me.items do
			table.insert(it, `{Roster.Items[item.id].name}{if item.count > 1 then " x" .. item.count else ""}`)
		end
		table.insert(lines, "items: " .. table.concat(it, ", "))
		for _, quest in state.quests do
			table.insert(lines, `{if quest.done then "[x]" else "[ ]"} {quest.text}`)
		end
		for _, mate in state.squad do
			if mate.userId ~= player.UserId then
				table.insert(lines, `mate {mate.hero}: {mate.hp}/{mate.maxHp}{if mate.downed then " DOWNED" else ""}`)
			end
		end
		hud.Text = table.concat(lines, "\n")

		local b = {}
		for _, bar in bossBars do
			table.insert(b, `{bar.name}  {math.floor(bar.hp)} / {math.floor(bar.maxHp)}`)
		end
		bosses.Text = table.concat(b, "\n")
	end)
end

return DebugUiController

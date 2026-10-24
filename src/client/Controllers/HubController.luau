--!nonstrict
-- HubController - life on Skyhold, the island hub (T6/T7), as this player sees it.
--
--   rune circles  each circle's glow, its three slot crystals (lit in each
--                 member's hero colour, bright when READY) and the stone board
--                 beside it saying who is in, who leads and how it stands
--   prompts       the only way into or out of a party: E / gamepad X / a tap
--                 on PLAY SOLO, OPEN A SQUAD, JOIN, BEGIN, READY...; LEAVE is
--                 the second prompt (F / Y) and must be held a moment. Walking
--                 across a circle changes nothing.
--   party card    top left while in a party: members, leader, READY, what
--                 happens next, and the same choices as buttons
--   nameplates    over everyone else on the island: name, hero, party (hidden
--                 while their hero is under the ground, T8)
--   countdown     this player's own, big, top centre: 5, 4, 3, 2, 1, each with a
--                 soft tick, and a nudge back into the portal for whoever is off it
--
-- The portal itself and the crossing through it (its surge, the departure,
-- the arrival in the Wardwood and the way home) are PortalController's (T8).
--
-- Everything here only asks (PartyAction): the server decides (PartyService,
-- Core/HubParty) and every client redraws from what it sends back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)
local SkyholdGen = require(ReplicatedStorage.Shared.Core.SkyholdGen)
local HubUi = require(script.Parent.Parent.HubUi)
local Sink = require(script.Parent.Parent.Sink)
local UiKit = require(script.Parent.Parent.UiKit)

local HubController = Knit.CreateController({ Name = "HubController" })

local player = Players.LocalPlayer
local C = HubUi.Colours

local NUMERALS = { "I", "II", "III", "IV", "V", "VI" }
local IDLE_GLOW = Color3.fromRGB(90, 220, 205)
local SOLO_GLOW = Color3.fromRGB(255, 205, 96)
local PREP_GLOW = Color3.fromRGB(255, 214, 120)
local WAIT_GLOW = Color3.fromRGB(255, 160, 70)
local AWAY_GLOW = Color3.fromRGB(110, 140, 220)
local GONE_GLOW = Color3.fromRGB(150, 255, 236) -- a party sinking into its portal
local EMPTY_SLOT = Color3.fromRGB(70, 96, 92)
local PROMPT_RANGE = Skyhold.JoinRange - 2.5

local function heroColour(heroId: string?): Color3
	local def = heroId and Roster.Heroes[heroId]
	local c = def and def.colour
	return if c then Color3.fromRGB(c[1], c[2], c[3]) else IDLE_GLOW
end

function HubController:KnitInit()
	self._plan = SkyholdGen.build(Skyhold)
	self._circles = {} -- circle -> { anchor, primary, secondary, model? }
	self._plates = {} -- userId -> BillboardGui
end

function HubController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._audio = Knit.GetController("AudioController")
	self._party = Net.client("PartyAction")
	self._folder = Instance.new("Folder")
	self._folder.Name = "HubClient"
	self._folder.Parent = Workspace

	self:_makeCircles()
	self:_makeUi()

	local state = self._state
	state.Changed:Connect(function(key)
		UiKit.safe("HubController", function()
			if key == "hub" or key == "roster" or key == "phase" or key == "profile" then
				self:_refresh()
			end
		end)
	end)
	self:_refresh()

	-- nameplates follow characters as they (re)spawn
	task.spawn(function()
		while true do
			task.wait(1)
			UiKit.safe("HubController.plates", function()
				self:_refreshPlates()
			end)
		end
	end)

	-- the circles' and the portal's light, the countdowns: every frame
	local broken = false
	RunService.RenderStepped:Connect(function()
		if broken then
			return
		end
		local ok, err = pcall(function()
			self:_animate()
		end)
		if not ok then
			broken = true
			warn(`[HubController] animation stopped: {err}`)
		end
	end)
end

-- ------------------------------------------------------------------ places

function HubController:_ground(x: number, z: number): Vector3
	local h = SkyholdGen.heightAt(self._plan, x, z) or 0
	return Vector3.new(SkyholdGen.world(Skyhold, x, h, z))
end

function HubController:_art(name: string): Instance?
	local island = Workspace:FindFirstChild("Skyhold")
	local art = island and island:FindFirstChild("Art")
	return art and art:FindFirstChild(name)
end

-- ------------------------------------------------------------------ circles

function HubController:_makeCircles()
	for i, c in Skyhold.Circles do
		local at = self:_ground(c.x, c.z)
		local anchor = Instance.new("Part")
		anchor.Name = `CirclePrompt{i}`
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.CFrame = CFrame.new(at + Vector3.new(0, 2.5, 0))
		anchor.Parent = self._folder

		local function prompt(key: Enum.KeyCode, pad: Enum.KeyCode, order: number): ProximityPrompt
			local p = Instance.new("ProximityPrompt")
			p.KeyboardKeyCode = key
			p.GamepadKeyCode = pad
			p.RequiresLineOfSight = false
			p.MaxActivationDistance = PROMPT_RANGE
			p.ObjectText = `Rune circle {NUMERALS[i] or i}`
			p.UIOffset = Vector2.new(0, order * 72)
			p.Enabled = false
			p.Parent = anchor
			p.Triggered:Connect(function()
				local action = p:GetAttribute("Action")
				if self._party and typeof(action) == "string" then
					self._party:FireServer(action, i)
				end
			end)
			return p
		end
		self._circles[i] = {
			anchor = anchor,
			primary = prompt(Enum.KeyCode.E, Enum.KeyCode.ButtonX, 0),
			secondary = prompt(Enum.KeyCode.F, Enum.KeyCode.ButtonY, 1),
		}
	end
end

-- what the two prompts at a circle offer this player now: { action, text, hold? }
function HubController:_choices(circle: number)
	local state = self._state
	local mine = state:Mine()
	local myCircle = mine and mine.circle
	local party = state:PartyAt(circle)
	if myCircle and myCircle ~= circle then
		return nil, nil
	end
	local leave = { "leave", "Leave party", 0.6 }
	if not myCircle then
		if not party then
			return { "solo", "Play solo" }, { "squad", "Open a squad" }
		end
		if party.mode == "squad" and (party.phase == "forming" or party.phase == "preparing") and #party.members < Skyhold.SquadSize then
			return { "join", "Join squad" }, nil
		end
		return nil, nil
	end
	if not party then
		return nil, nil
	end
	local me = player.UserId
	local leader = party.leader == me
	local ready = table.find(party.ready, me) ~= nil
	local phase = party.phase
	if phase == "forming" then
		if leader then
			local text = if party.mode == "solo" then "Go again" elseif #party.members > 1 then "Begin preparation" else "Begin alone"
			return { "prepare", text }, leave
		end
		return nil, leave
	elseif phase == "preparing" then
		if leader then
			return { "cancel", "Call it off" }, leave
		end
		return if ready then { "unready", "Not ready" } else { "ready", "Ready" }, leave
	elseif phase == "countdown" or phase == "waiting" then
		if leader then
			return { "cancel", "Call it off" }, leave
		end
		return { "unready", "Not ready" }, leave
	end
	return nil, nil
end

local function setPrompt(p: ProximityPrompt, choice)
	if not choice then
		p.Enabled = false
		return
	end
	p:SetAttribute("Action", choice[1])
	p.ActionText = choice[2]
	p.HoldDuration = choice[3] or 0
	p.Enabled = true
end

function HubController:_refreshCircles()
	local onIsland = self._state:OnIsland()
	for i, c in self._circles do
		local primary, secondary = self:_choices(i)
		setPrompt(c.primary, if onIsland then primary else nil)
		setPrompt(c.secondary, if onIsland then secondary else nil)
		self:_drawBoard(i)
	end
end

-- the stone board beside a circle: who is in it and how it stands
function HubController:_drawBoard(circle: number)
	local c = self._circles[circle]
	local model = self:_art(`Circle{circle}`)
	local board = model and model:FindFirstChild("Board", true)
	if not board or not board:IsA("BasePart") then
		return
	end
	local gui = c.board
	if not gui or gui.Parent ~= board then
		gui = Instance.new("SurfaceGui")
		gui.Name = "HubBoard"
		gui.Face = Enum.NormalId.Back -- the board faces south (+z) when its circle is unturned
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 100
		gui.LightInfluence = 0.3
		gui.Brightness = 1.4
		gui.ZOffset = 0.05
		gui.Parent = board
		local list = Instance.new("UIListLayout")
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, 6)
		list.Parent = gui
		c.title = HubUi.label(
			gui,
			"",
			44,
			"display",
			{ Size = UDim2.new(1, -24, 0, 54), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 }
		)
		c.lines = HubUi.label(gui, "", 30, "body", {
			Size = UDim2.new(1, -24, 0, 132),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 2,
		})
		c.status = HubUi.label(
			gui,
			"",
			30,
			"body",
			{ Size = UDim2.new(1, -24, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.gold, LayoutOrder = 3 }
		)
		c.board = gui
	end
	local state = self._state
	local party = state:PartyAt(circle)
	local names = {}
	for _, entry in state.roster.players do
		names[entry.userId] = entry
	end
	if not party then
		c.title.Text = `CIRCLE {NUMERALS[circle] or circle}`
		c.title.TextColor3 = C.teal
		c.lines.Text = "Step in to play solo\nor open a squad of three"
		c.status.Text = if state.hub.run then "Portal in use" else "Open"
		return
	end
	c.title.Text = if party.mode == "solo" then "SOLO" else `SQUAD {#party.members}/{Skyhold.SquadSize}`
	c.title.TextColor3 = if party.mode == "solo" then C.gold else C.teal
	local lines = {}
	for _, uid in party.members do
		local entry = names[uid]
		local tag = if table.find(party.ready, uid) then "  READY" else ""
		local lead = if uid == party.leader then "* " else ""
		table.insert(lines, `{lead}{if entry then entry.name else "?"}{tag}`)
	end
	c.lines.Text = table.concat(lines, "\n")
	c.status.Text = self:_statusText(party, false)
end

-- what a party is waiting for, from the board's view or the member's own
function HubController:_statusText(party, mine: boolean): string
	local phase = party.phase
	if phase == "forming" then
		if mine and party.leader == player.UserId then
			if party.mode == "solo" then
				return "Back from the Wardwood. Go again when you like"
			end
			return if #party.members > 1 then "Begin the preparation when your squad is in" else "Others can join. Begin when you like"
		end
		return "Waiting for the leader to begin"
	elseif phase == "preparing" then
		return `{#party.ready}/{#party.members} ready`
	elseif phase == "countdown" then
		local left = self._state:CountdownLeft(party)
		return `Into the Wardwood in {math.max(1, math.ceil(left or 0))}`
	elseif phase == "waiting" then
		return "The portal is in use: you go next"
	elseif phase == "departing" then
		return "Into the Wardwood..."
	elseif phase == "run" then
		return "In the Wardwood"
	end
	return ""
end

-- ------------------------------------------------------------------ the interface

function HubController:_makeUi()
	local gui = HubUi.screen("HubHud", 4)
	self._gui = gui

	-- top left: the party card
	local card = HubUi.panel(gui, {
		Name = "PartyCard",
		Position = UDim2.fromOffset(24, 16),
		Size = UDim2.fromOffset(420, 300),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	})
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 14), UDim.new(0, 16)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 18), UDim.new(0, 18)
	pad.Parent = card
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = card
	self._card = {
		frame = card,
		title = HubUi.label(card, "", 34, "display", { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, TextColor3 = C.gold }),
		status = HubUi.label(card, "", 24, "body", { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2, TextColor3 = C.soft }),
		rows = {},
	}
	local rows = Instance.new("Frame")
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.new(1, 0, 0, 0)
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.LayoutOrder = 3
	rows.Parent = card
	local rowList = Instance.new("UIListLayout")
	rowList.Padding = UDim.new(0, 6)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = rows
	for k = 1, Skyhold.SquadSize do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = C.mossDeep
		row.BackgroundTransparency = 0.35
		row.Size = UDim2.new(1, 0, 0, 52)
		row.LayoutOrder = k
		row.Visible = false
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 8)
		rc.Parent = row
		local portrait = Instance.new("ImageLabel")
		portrait.Name = "Portrait"
		portrait.BackgroundTransparency = 1
		portrait.Size = UDim2.fromOffset(44, 44)
		portrait.Position = UDim2.fromOffset(4, 4)
		portrait.Parent = row
		local crown = Instance.new("ImageLabel")
		crown.Name = "Crown"
		crown.BackgroundTransparency = 1
		crown.Size = UDim2.fromOffset(22, 22)
		crown.Position = UDim2.fromOffset(32, -6)
		crown.Parent = row
		UiKit.setIcon(crown, "IconCrown")
		local name =
			HubUi.label(row, "", 24, "body", { Name = "PlayerName", Position = UDim2.fromOffset(58, 2), Size = UDim2.new(1, -170, 0, 26) })
		local hero = HubUi.label(
			row,
			"",
			20,
			"body",
			{ Name = "Hero", Position = UDim2.fromOffset(58, 26), Size = UDim2.new(1, -170, 0, 22), TextColor3 = C.tan }
		)
		local tag = HubUi.label(row, "", 22, "display", {
			Name = "Tag",
			Position = UDim2.new(1, -110, 0, 0),
			Size = UDim2.fromOffset(104, 52),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		row.Parent = rows
		self._card.rows[k] = { frame = row, portrait = portrait, crown = crown, name = name, hero = hero, tag = tag }
	end
	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 52)
	buttons.LayoutOrder = 4
	buttons.Parent = card
	self._card.main = HubUi.button(buttons, "READY", "gold", { Size = UDim2.new(0.58, -6, 1, 0) }, function()
		local action = self._card.main:GetAttribute("Action")
		if self._party and typeof(action) == "string" then
			self._party:FireServer(action)
		end
	end)
	self._card.leave = HubUi.button(
		buttons,
		"LEAVE",
		"quiet",
		{ Size = UDim2.new(0.42, 0, 1, 0), Position = UDim2.new(0.58, 0, 0, 0) },
		function()
			if self._party then
				self._party:FireServer("leave")
			end
		end
	)

	-- top right: Silver, and the menu (settings)
	local purse = HubUi.panel(gui, {
		Name = "Purse",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 16),
		Size = UDim2.fromOffset(200, 56),
	})
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(40, 40)
	icon.Position = UDim2.fromOffset(10, 8)
	icon.Parent = purse
	UiKit.setIcon(icon, "IconSilver")
	self._silver = HubUi.label(purse, "0", 32, "display", { Position = UDim2.fromOffset(58, 0), Size = UDim2.new(1, -66, 1, 0) })
	HubUi.button(gui, "MENU", "quiet", {
		Name = "MenuButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -236, 0, 16),
		Size = UDim2.fromOffset(120, 56),
		TextSize = 24,
	}, function()
		Knit.GetController("OverlayController"):OpenSettings(nil)
	end)

	-- bottom centre: what to do next, while not in a party
	self._hint = HubUi.label(gui, "", 26, "body", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(1400, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.ink,
	})
	-- top centre: the countdown into the Wardwood, one big number at a time
	local countdown = Instance.new("Frame")
	countdown.Name = "Countdown"
	countdown.BackgroundTransparency = 1
	countdown.AnchorPoint = Vector2.new(0.5, 0)
	countdown.Position = UDim2.new(0.5, 0, 0, 40)
	countdown.Size = UDim2.fromOffset(600, 200)
	countdown.Visible = false
	countdown.Parent = gui
	HubUi.label(countdown, "INTO THE WARDWOOD", 26, "display", {
		Name = "Caption",
		Size = UDim2.new(1, 0, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.teal,
	})
	local number = HubUi.label(countdown, "", 120, "display", {
		Name = "Number",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(240, 136),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.gold,
	})
	local pulse = Instance.new("UIScale")
	pulse.Parent = number
	local nudge = HubUi.label(countdown, "Step into the portal", 24, "body", {
		Name = "Nudge",
		Position = UDim2.fromOffset(0, 172),
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.ink,
		Visible = false,
	})
	self._countdown = { frame = countdown, number = number, pulse = pulse, nudge = nudge, shown = nil, at = 0 }
	-- bottom right: the build, quietly
	HubUi.label(gui, GameConfig.BuildStamp, 18, "body", {
		Name = "Build",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -8),
		Size = UDim2.fromOffset(300, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.soft,
		TextTransparency = 0.3,
	})
end

--- Hush the hub's hint while another screen (the hero card) has the player's attention.
function HubController:SetQuiet(quiet: boolean)
	self._quiet = quiet
	self:_refreshCard()
end

function HubController:_refreshCard()
	local state = self._state
	local card = self._card
	local mine = state:Mine()
	local party = mine and mine.circle and state:PartyAt(mine.circle)
	-- sinking into the portal: nothing of the island's interface is left to use
	self._gui.Enabled = state:OnIsland() and not (party and party.phase == "departing")
	card.frame.Visible = party ~= nil
	local profile = state.profile
	self._silver.Text = UiKit.commas(profile and profile.silver or 0)
	if not party then
		self._hint.Text = "Choose your hero in the Hall of Heroes   ·   Start a run at a rune circle before the portal"
		self._hint.Visible = not self._quiet
		return
	end
	self._hint.Visible = false
	local circle = NUMERALS[party.circle] or tostring(party.circle)
	card.title.Text = if party.mode == "solo" then `SOLO · CIRCLE {circle}` else `SQUAD · CIRCLE {circle}`
	card.status.Text = self:_statusText(party, true)
	local entries = {}
	for _, entry in state.roster.players do
		entries[entry.userId] = entry
	end
	for k, row in card.rows do
		local uid = party.members[k]
		local entry = uid and entries[uid]
		row.frame.Visible = entry ~= nil
		if entry then
			UiKit.setIcon(row.portrait, "Portrait" .. tostring(entry.hero))
			row.crown.Visible = uid == party.leader
			row.name.Text = entry.name
			local def = Roster.Heroes[entry.hero]
			row.hero.Text = if def then def.name else ""
			local ready = table.find(party.ready, uid) ~= nil
			row.tag.Text = if ready then "READY" elseif party.phase == "preparing" then "..." else ""
			row.tag.TextColor3 = if ready then C.ready else C.soft
		end
	end
	-- the card's own button mirrors the circle's first choice
	local me = player.UserId
	local action, text, kind = nil, nil, "gold"
	if party.phase == "forming" and party.leader == me then
		action, text = "prepare", if party.mode == "solo" then "GO AGAIN" else "BEGIN"
	elseif party.phase == "preparing" or party.phase == "countdown" or party.phase == "waiting" then
		if party.leader == me then
			action, text, kind = "cancel", "CALL IT OFF", "quiet"
		elseif table.find(party.ready, me) then
			action, text, kind = "unready", "NOT READY", "quiet"
		else
			action, text, kind = "ready", "READY", "ready"
		end
	end
	card.main.Visible = action ~= nil
	card.leave.Size = if action then UDim2.new(0.42, 0, 1, 0) else UDim2.new(1, 0, 1, 0)
	card.leave.Position = if action then UDim2.new(0.58, 0, 0, 0) else UDim2.new(0, 0, 0, 0)
	if action then
		card.main:SetAttribute("Action", action)
		card.main.Text = text
		HubUi.kind(card.main, kind)
	end
end

-- ------------------------------------------------------------------ nameplates

function HubController:_refreshPlates()
	local state = self._state
	local seen = {}
	for _, entry in state.roster.players do
		local other = Players:GetPlayerByUserId(entry.userId)
		local character = other and other.Character
		local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
		if other and other ~= player and head and state:OnIsland() then
			seen[entry.userId] = true
			local plate = self._plates[entry.userId]
			if not plate or plate.Adornee ~= head or not plate.Parent then
				if plate then
					plate:Destroy()
				end
				-- wide enough for "Sir Clonk · leads circle III · READY"
				plate = HubUi.billboard(head, UDim2.fromOffset(340, 74), Vector3.new(0, 3.4, 0), 80)
				plate.Name = `Plate{entry.userId}`
				HubUi.label(
					plate,
					"",
					26,
					"body",
					{ Name = "PlayerName", Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center }
				)
				HubUi.label(plate, "", 20, "body", {
					Name = "Line",
					Position = UDim2.fromOffset(0, 30),
					Size = UDim2.new(1, 0, 0, 24),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextColor3 = C.tan,
				})
				plate.Parent = self._folder
				self._plates[entry.userId] = plate
			end
			plate.PlayerName.Text = entry.name
			-- a party stands together: its members' plates stack instead of overlapping
			local party = entry.circle and state:PartyAt(entry.circle)
			local slot = party and table.find(party.members, entry.userId) or 1
			local lift = Vector3.new(0, 3.4 + (slot - 1) * 2.1, 0)
			if plate.StudsOffsetWorldSpace ~= lift then
				plate.StudsOffsetWorldSpace = lift
			end
			local def = Roster.Heroes[entry.hero]
			local bits = { if def then def.name else "" }
			if entry.circle then
				table.insert(bits, `{if entry.leader then "leads" else "in"} circle {NUMERALS[entry.circle] or entry.circle}`)
			end
			if entry.ready then
				table.insert(bits, "READY")
			end
			plate.Line.Text = table.concat(bits, " · ")
			plate.Line.TextColor3 = if entry.ready then C.ready else C.tan
		end
	end
	for uid, plate in self._plates do
		if not seen[uid] then
			plate:Destroy()
			self._plates[uid] = nil
		end
	end
end

-- ------------------------------------------------------------------ every frame

function HubController:_refresh()
	self:_refreshCircles()
	self:_refreshCard()
	self:_refreshPlates()
end

function HubController:_animate()
	local state = self._state
	local t = os.clock()
	local onIsland = state:OnIsland()
	local mine = state:Mine()
	local entries = {}
	for _, entry in state.roster.players do
		entries[entry.userId] = entry
	end
	local anyCounting = nil
	for i in self._circles do
		local model = self:_art(`Circle{i}`)
		if model then
			local party = state:PartyAt(i)
			local glow = model:FindFirstChild("Glow", true)
			local colour, strength = IDLE_GLOW, 0.35 + math.sin(t * 1.6 + i) * 0.08
			if party then
				if party.phase == "run" then
					colour, strength = AWAY_GLOW, 0.3
				elseif party.phase == "departing" then
					colour, strength = GONE_GLOW, 0.95
				elseif party.phase == "waiting" then
					colour, strength = WAIT_GLOW, 0.5 + math.sin(t * 2.2) * 0.15
				elseif party.phase == "countdown" then
					colour, strength = PREP_GLOW, 0.75 + math.sin(t * 9) * 0.2
					anyCounting = anyCounting or party
				elseif party.phase == "preparing" then
					colour, strength = PREP_GLOW, 0.55 + math.sin(t * 4) * 0.12
				else
					colour, strength = if party.mode == "solo" then SOLO_GLOW else IDLE_GLOW, 0.6
				end
			end
			if glow and glow:IsA("BasePart") then
				glow.Color = colour
				glow.Transparency = math.clamp(1 - strength, 0, 0.95)
			end
			for k = 1, Skyhold.SquadSize do
				local slot = model:FindFirstChild(`Slot{k}`, true)
				if slot and slot:IsA("BasePart") then
					local uid = party and party.members[k]
					if uid then
						local ready = table.find(party.ready, uid) ~= nil
						slot.Color = heroColour(entries[uid] and entries[uid].hero)
						slot.Transparency = if ready then 0 else 0.35 + math.sin(t * 3 + k) * 0.1
					else
						slot.Color = EMPTY_SLOT
						slot.Transparency = 0.5
					end
				end
			end
		end
	end

	-- this player's own countdown, big (the portals and the crossing: PortalController)
	local myParty = mine and mine.circle and state:PartyAt(mine.circle)
	self:_drawCountdown(onIsland and myParty or nil, t)
	if onIsland and myParty and myParty.phase == "countdown" then
		self._card.status.Text = self:_statusText(myParty, true)
	end
	-- nobody's nameplate hangs over a hero who is under the ground
	for uid, plate in self._plates do
		local other = Players:GetPlayerByUserId(uid)
		local hidden = other ~= nil and Sink.studs(other.Character) > 0.5
		if plate.Enabled == hidden then
			plate.Enabled = not hidden
		end
	end
	-- the boards count down too
	if anyCounting then
		for i in self._circles do
			local party = state:PartyAt(i)
			if party and party.phase == "countdown" then
				self:_drawBoard(i)
			end
		end
	end
end

-- the big number: 5, 4, 3, 2, 1, each landing with a pulse and a soft tick;
-- gone as the departure starts
function HubController:_drawCountdown(party, t: number)
	local cd = self._countdown
	local counting = party ~= nil and party.phase == "countdown"
	cd.frame.Visible = counting
	if not counting then
		cd.shown = nil
		return
	end
	local left = self._state:CountdownLeft(party) or 0
	local n = math.max(1, math.ceil(left))
	if cd.shown ~= n then
		cd.shown, cd.at = n, t
		cd.number.Text = tostring(n)
		pcall(function()
			local tick = self._audio:Play("timer_tick")
			if tick then
				tick.Volume *= 0.6
				tick.PlaybackSpeed = 1 + (5 - n) * 0.04
			end
		end)
	end
	-- each number lands big and settles; the last ones in the portal's own colour
	local k = math.clamp((t - cd.at) / 0.35, 0, 1)
	cd.pulse.Scale = 1 + 0.45 * (1 - k) * (1 - k)
	cd.number.TextTransparency = 0.6 * (1 - math.min(1, k * 3))
	cd.number.TextColor3 = if n <= 2 then C.teal:Lerp(C.gold, 0.25) else C.gold
	-- whoever has wandered off the portal is asked back onto it
	local c = Skyhold.Circles[party.circle]
	local root = self._state:Root()
	local off = false
	if c and root then
		local at = self:_ground(c.x, c.z)
		local flat = Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z)
		off = flat.Magnitude > Skyhold.CircleRadius - 0.6
	end
	cd.nudge.Visible = off
end

return HubController

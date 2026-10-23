--!nonstrict
-- HeroHallController - the Hall of Heroes on Skyhold (T6/T7).
--
-- Each plinth carries one hero (Roster.HeroOrder), drawn here so every player
-- sees their own locks: a hero they own stands in full colour, turning slowly;
-- a locked one is cool slate behind a rune veil, its price on the plate. Each
-- statue is drawn with a soft dark edge and stands before its banner in a deep
-- shade of its hero's colour, so it reads in the island's bright sun.
-- Walking up and pressing VIEW (E / gamepad X / a tap) borrows the camera for a
-- close look and opens the hero's card: starting weapon, passive, runs played,
-- and CHOOSE, or UNLOCK for Silver. CHOOSE asks the server (PickHero), which
-- re-dresses this player's own character on the spot; BACK, walking away or
-- the gamepad's B gives the camera back. A READY player cannot change hero.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)
local SkyholdGen = require(ReplicatedStorage.Shared.Core.SkyholdGen)
local HubUi = require(script.Parent.Parent.HubUi)
local UiKit = require(script.Parent.Parent.UiKit)
local Vfx = require(script.Parent.Parent.Vfx)

local HeroHallController = Knit.CreateController({ Name = "HeroHallController" })

local player = Players.LocalPlayer
local C = HubUi.Colours

local STATUE_LIFT = 3.2 -- the plinth's top above the ground
local STATUE_SCALE = 1.5 -- larger than life, on a pedestal, so it reads across the hall
local VIEW_RANGE = 10
local CLOSE_RANGE = 16 -- walking further than this from the plinth closes the card
local LOCKED_TINT = Color3.fromRGB(134, 148, 150) -- slate: the paving and the sky are pale already
local EDGE = Color3.fromRGB(28, 40, 34) -- the statues' soft outline
local BANNER_SHADE = Color3.fromRGB(26, 38, 32) -- banners deepen towards this behind the statues

function HeroHallController:KnitInit()
	self._plan = SkyholdGen.build(Skyhold)
	self._statues = {} -- plinth index -> { hero, model, base, locked, veil }
	self._open = nil -- the plinth whose card is up
end

function HeroHallController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._camera = Knit.GetController("CameraController")
	self._pick = Net.client("PickHero")
	self._unlock = Net.client("UnlockHero")
	self._folder = Instance.new("Folder")
	self._folder.Name = "HeroHall"
	self._folder.Parent = Workspace

	self:_makeCard()
	for i, spot in Skyhold.Plinths do
		local heroId = Roster.HeroOrder[i]
		if heroId then
			self:_makePlinth(i, spot, heroId)
		end
	end

	self._state.Changed:Connect(function(key)
		UiKit.safe("HeroHall", function()
			if key == "profile" or key == "roster" then
				self:_refreshStatues()
				if self._open then
					self:_renderCard()
				end
			elseif key == "phase" and not self._state:OnIsland() then
				self:_close()
			end
		end)
	end)
	self:_refreshStatues()

	UserInputService.InputBegan:Connect(function(input, processed)
		if not self._open then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Backspace or (key == Enum.KeyCode.Escape and not processed) then
			self:_close()
		end
	end)

	RunService.RenderStepped:Connect(function()
		UiKit.safe("HeroHall.frame", function()
			self:_animate()
		end)
	end)
end

-- ------------------------------------------------------------------ plinths

function HeroHallController:_top(spot): CFrame
	local h = SkyholdGen.heightAt(self._plan, spot.x, spot.z) or 0
	local x, y, z = SkyholdGen.world(Skyhold, spot.x, h + STATUE_LIFT, spot.z)
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(spot.yaw), 0)
end

function HeroHallController:_makePlinth(i: number, spot, heroId: string)
	local base = self:_top(spot)
	local entry = { hero = heroId, base = base, spot = spot }
	self._statues[i] = entry

	local anchor = Instance.new("Part")
	anchor.Name = `PlinthPrompt{i}`
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	-- in front of the plinth (its front faces where its yaw points: +z turned)
	anchor.CFrame = base * CFrame.new(0, -1, 4)
	anchor.Parent = self._folder
	local prompt = Instance.new("ProximityPrompt")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = VIEW_RANGE
	prompt.ObjectText = Roster.Heroes[heroId].name
	prompt.ActionText = "View hero"
	prompt.Parent = anchor
	prompt.Triggered:Connect(function()
		self:_openCard(i)
	end)
	entry.prompt = prompt

	-- the name, carved in light over the hero's head
	local over = anchor:Clone()
	over:ClearAllChildren() -- not a second prompt
	over.Name = `PlinthSign{i}`
	over.CFrame = base * CFrame.new(0, 10.4, 0)
	over.Parent = self._folder
	local sign = HubUi.billboard(over, UDim2.fromOffset(260, 70), Vector3.zero, 70)
	sign.Name = "Sign"
	entry.title = HubUi.label(sign, string.upper(Roster.Heroes[heroId].name), 34, "display", {
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.gold,
	})
	entry.sub = HubUi.label(sign, "", 22, "body", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.ink,
	})
	sign.Parent = over
	entry.sign = sign
end

function HeroHallController:_statueModel(heroId: string, locked: boolean): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local heroes = assets and assets:FindFirstChild("Heroes")
	local template = heroes and heroes:FindFirstChild("Hero" .. heroId)
	if not template or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	local _, size = model:GetBoundingBox()
	model:ScaleTo(GameConfig.HeroHeight * STATUE_SCALE / math.max(size.Y, 0.1))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			if locked then
				-- carved in slate until it is theirs
				part.Color = LOCKED_TINT
				part.Material = Enum.Material.Slate
				if part:IsA("MeshPart") then
					part.TextureID = ""
				end
				local sa = part:FindFirstChildOfClass("SurfaceAppearance")
				if sa then
					sa:Destroy()
				end
			end
		elseif locked and (part:IsA("Decal") or part:IsA("Texture")) then
			part.Transparency = 0.7
		end
	end
	-- a soft dark edge: the statue's shape against the sunlit paving and sky
	local edge = Instance.new("Highlight")
	edge.Name = "Edge"
	edge.FillTransparency = 1
	edge.OutlineColor = EDGE
	edge.OutlineTransparency = 0.5
	edge.DepthMode = Enum.HighlightDepthMode.Occluded
	edge.Parent = model
	return model
end

function HeroHallController:_refreshStatues()
	local profile = self._state.profile
	local mine = self._state:Mine()
	for _, entry in self._statues do
		local unlocked = profile ~= nil and profile.unlocked[entry.hero] == true
		local locked = not unlocked
		if entry.model == nil or entry.locked ~= locked then
			if entry.model then
				entry.model:Destroy()
			end
			if entry.veil then
				entry.veil:Destroy()
				entry.veil = nil
			end
			entry.locked = locked
			entry.model = self:_statueModel(entry.hero, locked)
			if entry.model then
				local _, size = entry.model:GetBoundingBox()
				entry.half = size.Y / 2
				entry.model.Parent = self._folder
			end
			if locked then
				-- a column of slow teal light round a locked hero
				local veil = Instance.new("Part")
				veil.Name = "Veil"
				veil.Shape = Enum.PartType.Cylinder
				veil.Anchored = true
				veil.CanCollide = false
				veil.CanQuery = false
				veil.CanTouch = false
				veil.CastShadow = false
				veil.Material = Enum.Material.ForceField
				veil.Color = Color3.fromRGB(90, 230, 210)
				veil.Size = Vector3.new(9, 5.4, 5.4)
				veil.CFrame = entry.base * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.rad(90))
				veil.Parent = self._folder
				entry.veil = veil
			end
		end
		local def = Roster.Heroes[entry.hero]
		local chosen = mine and mine.hero == entry.hero
		entry.sub.Text = if locked
			then `LOCKED · {UiKit.commas(def.unlockSilver)} SILVER`
			elseif chosen then "YOUR HERO"
			else Roster.Weapons[def.weapon].name
		entry.sub.TextColor3 = if locked then C.soft elseif chosen then C.ready else C.ink
		entry.prompt.ActionText = if locked then "View (locked)" elseif chosen then "View" else "View hero"
	end
end

-- ------------------------------------------------------------------ the card

function HeroHallController:_makeCard()
	local gui = HubUi.screen("HeroCard", 6)
	gui.Enabled = false
	self._gui = gui
	local card = HubUi.panel(gui, {
		Name = "Card",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -48, 0.5, 0),
		Size = UDim2.fromOffset(560, 640),
	})
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 22), UDim.new(0, 22)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 26), UDim.new(0, 26)
	pad.Parent = card
	local e = {}
	e.portrait = Instance.new("ImageLabel")
	e.portrait.BackgroundTransparency = 1
	e.portrait.Size = UDim2.fromOffset(96, 96)
	e.portrait.Parent = card
	e.name =
		HubUi.label(card, "", 52, "display", { Position = UDim2.fromOffset(110, 4), Size = UDim2.new(1, -110, 0, 58), TextColor3 = C.gold })
	e.runs =
		HubUi.label(card, "", 24, "body", { Position = UDim2.fromOffset(112, 62), Size = UDim2.new(1, -112, 0, 28), TextColor3 = C.soft })
	e.blurb = HubUi.label(
		card,
		"",
		26,
		"body",
		{ Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 0, 70), TextYAlignment = Enum.TextYAlignment.Top }
	)

	local function row(y: number, heading: string)
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = C.mossDeep
		frame.BackgroundTransparency = 0.3
		frame.Position = UDim2.fromOffset(0, y)
		frame.Size = UDim2.new(1, 0, 0, 132)
		frame.Parent = card
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = frame
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(64, 64)
		icon.Position = UDim2.fromOffset(12, 14)
		icon.Parent = frame
		HubUi.label(frame, heading, 20, "body", { Position = UDim2.fromOffset(88, 8), Size = UDim2.new(1, -96, 0, 22), TextColor3 = C.tan })
		local title = HubUi.label(frame, "", 30, "display", { Position = UDim2.fromOffset(88, 30), Size = UDim2.new(1, -96, 0, 34) })
		local text = HubUi.label(frame, "", 22, "body", {
			Position = UDim2.fromOffset(88, 66),
			Size = UDim2.new(1, -96, 0, 60),
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = C.soft,
		})
		return icon, title, text
	end
	e.weaponIcon, e.weaponName, e.weaponText = row(196, "STARTING WEAPON")
	e.passiveIcon, e.passiveName, e.passiveText = row(340, "PASSIVE")
	e.note = HubUi.label(card, "", 22, "body", {
		Position = UDim2.fromOffset(0, 482),
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.soft,
	})
	e.main = HubUi.button(
		card,
		"CHOOSE",
		"gold",
		{ Position = UDim2.fromOffset(0, 516), Size = UDim2.new(0.62, -8, 0, 62), TextSize = 32 },
		function()
			self:_mainPressed()
		end
	)
	e.back = HubUi.button(
		card,
		"BACK",
		"quiet",
		{ Position = UDim2.new(0.62, 0, 0, 516), Size = UDim2.new(0.38, 0, 0, 62), TextSize = 28 },
		function()
			self:_close()
		end
	)
	self._e = e
end

function HeroHallController:_openCard(i: number)
	local entry = self._statues[i]
	if not entry or not self._state:OnIsland() then
		return
	end
	self._open = i
	self._gui.Enabled = true
	-- the hero framed from in front of the plinth, a touch below eye level
	-- (aimed a little to the hero's left, so they stand left of the card)
	local look = (entry.base * CFrame.new(2.6, 4.2, 0)).Position
	local eye = (entry.base * CFrame.new(1.4, 5.4, 14)).Position
	self._camera:SetShot(CFrame.lookAt(eye, look))
	self:_hideSelf(true)
	self:_quiet(true)
	self:_renderCard()
	UiKit.focus(self._e.main)
end

function HeroHallController:_close()
	if not self._open then
		return
	end
	self._open = nil
	self._gui.Enabled = false
	self._camera:SetShot(nil)
	self:_hideSelf(false)
	self:_quiet(false)
	UiKit.unfocus(self._gui)
end

-- while the card is up, nothing else speaks over it: the hall's signs, the hub's hint
function HeroHallController:_quiet(quiet: boolean)
	for _, entry in self._statues do
		if entry.sign then
			entry.sign.Enabled = not quiet
		end
	end
	Knit.GetController("HubController"):SetQuiet(quiet)
end

-- our own hero stands in front of the plinth: out of the shot while it is borrowed
function HeroHallController:_hideSelf(hidden: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

function HeroHallController:_renderCard()
	local entry = self._open and self._statues[self._open]
	if not entry then
		return
	end
	local e = self._e
	local state = self._state
	local def = Roster.Heroes[entry.hero]
	local weapon = Roster.Weapons[def.weapon]
	local profile = state.profile
	local mine = state:Mine()
	local unlocked = profile ~= nil and profile.unlocked[entry.hero] == true
	local silver = profile and profile.silver or 0
	local runs = profile and profile.runs and tonumber(profile.runs[entry.hero]) or 0
	UiKit.setIcon(e.portrait, "Portrait" .. entry.hero)
	e.name.Text = string.upper(def.name)
	e.runs.Text = if runs == 1 then "1 run" else `{runs} runs`
	e.blurb.Text = def.blurb
	UiKit.setIcon(e.weaponIcon, "Icon" .. def.weapon)
	e.weaponName.Text = if weapon then weapon.name else def.weapon
	e.weaponText.Text = if weapon then weapon.text or "" else ""
	UiKit.setIcon(e.passiveIcon, "IconCrown")
	e.passiveName.Text = def.passiveName
	e.passiveText.Text = def.passiveText

	local chosen = mine and mine.hero == entry.hero
	local ready = mine and mine.ready
	if not unlocked then
		local afford = silver >= def.unlockSilver
		e.main.Text = `UNLOCK  {UiKit.commas(def.unlockSilver)}`
		HubUi.kind(e.main, if afford then "teal" else "quiet")
		e.main.AutoButtonColor = afford
		e.note.Text = if afford
			then `You have {UiKit.commas(silver)} Silver`
			else `You have {UiKit.commas(silver)} of {UiKit.commas(def.unlockSilver)} Silver`
		e.note.TextColor3 = if afford then C.soft else C.red
	elseif chosen then
		e.main.Text = "YOUR HERO"
		HubUi.kind(e.main, "quiet")
		e.main.AutoButtonColor = false
		e.note.Text = "You are playing this hero"
		e.note.TextColor3 = C.ready
	elseif ready then
		e.main.Text = "CHOOSE"
		HubUi.kind(e.main, "quiet")
		e.main.AutoButtonColor = false
		e.note.Text = "You are READY: unready first to change hero"
		e.note.TextColor3 = C.gold
	else
		e.main.Text = "CHOOSE"
		HubUi.kind(e.main, "gold")
		e.main.AutoButtonColor = true
		e.note.Text = ""
	end
end

function HeroHallController:_mainPressed()
	local entry = self._open and self._statues[self._open]
	if not entry then
		return
	end
	local state = self._state
	local def = Roster.Heroes[entry.hero]
	local profile = state.profile
	local mine = state:Mine()
	local unlocked = profile ~= nil and profile.unlocked[entry.hero] == true
	if not unlocked then
		if profile and profile.silver >= def.unlockSilver and self._unlock then
			self._unlock:FireServer(entry.hero)
		end
		return
	end
	if (mine and (mine.hero == entry.hero or mine.ready)) or not self._pick then
		return
	end
	self._pick:FireServer(entry.hero)
	-- the moment of becoming them: a burst where we stand, and the camera back
	local root = state:Root()
	if root then
		pcall(Vfx.burst, "LevelUpBurst", root.Position, { tint = Color3.fromRGB(def.colour[1], def.colour[2], def.colour[3]) })
	end
	self:_close()
end

-- ------------------------------------------------------------------ every frame

function HeroHallController:_animate()
	local t = os.clock()
	for i, entry in self._statues do
		local model = entry.model
		if model then
			local turn = if entry.locked then 0 else math.sin(t * 0.5 + i) * 0.35
			local bob = if entry.locked then 0 else math.sin(t * 1.6 + i) * 0.12
			model:PivotTo(entry.base * CFrame.new(0, (entry.half or 3) + bob, 0) * CFrame.Angles(0, math.pi + turn, 0))
		end
		if entry.veil then
			entry.veil.Transparency = 0.55 + math.sin(t * 1.4 + i) * 0.15
		end
	end
	-- each plinth's banner wears its hero's colour (the island streams in, so
	-- look again now and then)
	if t >= (self._bannerAt or 0) then
		self._bannerAt = t + 1
		local island = Workspace:FindFirstChild("Skyhold")
		local art = island and island:FindFirstChild("Art")
		for i, entry in self._statues do
			local plinth = art and art:FindFirstChild(`Plinth{i}`)
			local banner = plinth and plinth:FindFirstChild("Banner", true)
			local c = Roster.Heroes[entry.hero].colour
			if banner and banner:IsA("BasePart") and c then
				banner.Color = Color3.fromRGB(c[1], c[2], c[3]):Lerp(BANNER_SHADE, 0.38)
			end
		end
	end
	-- walking away from the plinth (or being moved) closes its card
	if self._open then
		local entry = self._statues[self._open]
		local root = self._state:Root()
		if not root or (root.Position - entry.base.Position).Magnitude > CLOSE_RANGE then
			self:_close()
		elseif GuiService.SelectedObject == nil and UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
			UiKit.focus(self._e.main)
		end
	end
end

return HeroHallController

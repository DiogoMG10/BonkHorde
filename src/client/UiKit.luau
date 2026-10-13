--!nonstrict
-- UiKit - what the interface controllers share: the five ScreenGuis, the one
-- UIScale each of them gets, sample-child templates, icons, rarity colours and
-- number formatting.
--
-- Every helper here tolerates a missing instance: a lookup that fails warns
-- once with the path and returns nil, and every setter ignores nil. A screen
-- with a hole in it must never stop the client.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Icons = require(ReplicatedStorage.Shared.Config.Icons)

local UiKit = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- The real screens are wired: DebugUiController reads this and builds nothing.
playerGui:SetAttribute("BonkRealUi", true)

UiKit.DesignSize = Vector2.new(1920, 1080)
UiKit.ScreenNames = { "Hud", "Choices", "Menu", "EndScreens", "Overlay" }

local function hex(code: string): Color3
	return Color3.fromHex(code)
end

UiKit.Colours = {
	ink = hex("#FFFFFF"),
	soft = hex("#C9D2CB"),
	tan = hex("#D9B45A"),
	gold = hex("#FFD23A"),
	green = hex("#35D04A"),
	red = hex("#E5121B"),
	xp = hex("#11B4F4"),
	shield = hex("#12A8E8"),
	dark = hex("#101512"),
	grey = hex("#6B6F6B"),
	confirm = hex("#2E7FD1"),
	skip = hex("#2E9E4C"),
	banish = hex("#B3263A"),
	banishFill = hex("#4A1218"),
}
UiKit.GreenHex = "#35D04A"

local RARITY = {
	Common = hex("#35D07A"),
	Uncommon = hex("#3D8BFF"),
	Rare = hex("#B04DFF"),
	Epic = hex("#FF4D9A"),
	Legendary = hex("#FFD23A"),
	New = hex("#FFFFFF"),
}
local CARD_FILL = {
	Common = hex("#0F3B24"),
	Uncommon = hex("#12294A"),
	Rare = hex("#2A1040"),
	Epic = hex("#401028"),
	Legendary = hex("#4A4309"),
	New = hex("#2B2B2B"),
}

--- The text and tile colour of a rarity ("New" for a first pick).
function UiKit.rarityColour(rarity: string?): Color3
	return RARITY[rarity or "Common"] or RARITY.Common
end

--- The card background of a rarity.
function UiKit.cardColour(rarity: string?): Color3
	return CARD_FILL[rarity or "Common"] or CARD_FILL.Common
end

-- ---------------------------------------------------------------- safety

local warned = {}

function UiKit.warnOnce(message: string)
	if not warned[message] then
		warned[message] = true
		warn(message)
	end
end

--- Run cosmetic code; an error becomes a warning, never a broken client.
function UiKit.safe(label: string, fn, ...): boolean
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(`[{label}] {err}`)
	end
	return ok
end

--- `root.A.B.C` by name. Warns once with the path when a link is missing.
function UiKit.find(root: Instance?, path: string, quiet: boolean?): Instance?
	if not root then
		return nil
	end
	local node = root
	for _, name in string.split(path, ".") do
		local nextNode = node:FindFirstChild(name)
		if not nextNode then
			if not quiet then
				UiKit.warnOnce(`[UiKit] missing UI element {root:GetFullName()}.{path}`)
			end
			return nil
		end
		node = nextNode
	end
	return node
end

-- ---------------------------------------------------------------- setters

function UiKit.text(inst: Instance?, text: string)
	if inst and (inst:IsA("TextLabel") or inst:IsA("TextButton")) and inst.Text ~= text then
		inst.Text = text
	end
end

function UiKit.textColour(inst: Instance?, colour: Color3)
	if inst and (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
		inst.TextColor3 = colour
	end
end

function UiKit.show(inst: Instance?, visible: boolean)
	if inst and inst:IsA("GuiObject") and inst.Visible ~= visible then
		inst.Visible = visible
	end
end

function UiKit.colour(inst: Instance?, colour: Color3)
	if inst and inst:IsA("GuiObject") then
		inst.BackgroundColor3 = colour
	end
end

--- Set a bar fill's width as a 0..1 share of its track.
function UiKit.fill(inst: Instance?, fraction: number)
	if inst and inst:IsA("GuiObject") then
		if fraction ~= fraction then
			fraction = 0
		end
		local size = inst.Size
		inst.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, size.Y.Scale, size.Y.Offset)
	end
end

-- ---------------------------------------------------------------- templates

--- Take a sample-child container: clone its first child called `name` as the
--- template (returned detached) and delete every sample of that name.
function UiKit.template(container: Instance?, name: string): Instance?
	if not container then
		return nil
	end
	local first: Instance? = nil
	for _, child in container:GetChildren() do
		if child.Name == name then
			if not first then
				first = child:Clone()
			end
			child:Destroy()
		end
	end
	if not first then
		UiKit.warnOnce(`[UiKit] no sample child {name} in {container:GetFullName()}`)
	end
	return first
end

--- Destroy every instance in a list of clones and empty the list.
function UiKit.clear(list: { Instance })
	for _, inst in list do
		inst:Destroy()
	end
	table.clear(list)
end

-- ---------------------------------------------------------------- icons

--- Put the icon `key` on one ImageLabel. An id that is not uploaded yet hides
--- the image (fully transparent) and leaves `Visible` to the caller's logic.
function UiKit.setIcon(image: Instance?, key: string?)
	if not image or not (image:IsA("ImageLabel") or image:IsA("ImageButton")) then
		return
	end
	local id = Icons.get(key)
	if key then
		image:SetAttribute("IconName", key)
	end
	image.Image = id
	image.ImageTransparency = if id == "" then 1 else 0
end

--- Fill every ImageLabel under `root` that carries the IconName attribute.
function UiKit.fillIcons(root: Instance?)
	if not root then
		return
	end
	for _, d in root:GetDescendants() do
		if d:IsA("ImageLabel") then
			local key = d:GetAttribute("IconName")
			if typeof(key) == "string" then
				UiKit.setIcon(d, key)
			end
		end
	end
end

-- ---------------------------------------------------------------- formatting

--- "12:34" for a number of seconds.
function UiKit.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

--- "12,345" for a number (rounded to a whole number).
function UiKit.commas(value: number?): string
	local n = math.floor((value or 0) + 0.5)
	local sign = if n < 0 then "-" else ""
	local digits = string.format("%d", math.abs(n))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return sign .. grouped
end

-- ---------------------------------------------------------------- the ScreenGuis and their UIScale

local screens = {} -- name -> ScreenGui, or false when it never arrived
local loading = {}
local scaled = {} -- ScreenGui -> { scale = UIScale, tops = { [GuiObject] = { size, position } } }
local viewportConn: RBXScriptConnection? = nil

local function currentScale(): number
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else UiKit.DesignSize
	if size.X < 1 or size.Y < 1 then
		return 1
	end
	return math.clamp(math.min(size.X / UiKit.DesignSize.X, size.Y / UiKit.DesignSize.Y), 0.2, 4)
end

-- A UIScale under a ScreenGui multiplies the whole layout of its children, scale
-- components included, so a 1,0,1,0 frame would cover only `s` of the screen and
-- a 0.5 anchor would sit at `0.5 * s`. Dividing the top-level scale components
-- by `s` puts every screen-relative size and anchor back where the design has
-- it, while offsets (the 1920x1080 design pixels) are what gets scaled.
-- Set the attribute BonkUiScaleCompensate = false on PlayerGui to turn this off.
local function applyScale()
	local s = currentScale()
	local compensate = playerGui:GetAttribute("BonkUiScaleCompensate") ~= false
	local k = if compensate then 1 / s else 1
	for _, entry in scaled do
		entry.scale.Scale = s
		for object, original in entry.tops do
			if object.Parent then
				local size, position = original.size, original.position
				object.Size = UDim2.new(size.X.Scale * k, size.X.Offset, size.Y.Scale * k, size.Y.Offset)
				object.Position = UDim2.new(position.X.Scale * k, position.X.Offset, position.Y.Scale * k, position.Y.Offset)
			end
		end
	end
end

local function watchViewport()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end
	applyScale()
end

local function installScale(screen: ScreenGui)
	if scaled[screen] then
		return
	end
	local scale = screen:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "BonkScale"
		scale.Parent = screen
	end
	local tops = {}
	for _, child in screen:GetChildren() do
		if child:IsA("GuiObject") then
			tops[child] = { size = child.Size, position = child.Position }
		end
	end
	scaled[screen] = { scale = scale, tops = tops }
	applyScale()
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)
playerGui:GetAttributeChangedSignal("BonkUiScaleCompensate"):Connect(applyScale)
watchViewport()

-- Characters do not load automatically in this game, so Roblox may not have
-- copied StarterGui into PlayerGui when the lobby needs its menu. The kit copies
-- a missing screen itself and removes the engine's later duplicate.
playerGui.ChildAdded:Connect(function(child)
	local mine = screens[child.Name]
	if mine and mine ~= child and child:IsA("ScreenGui") then
		task.defer(function()
			if screens[child.Name] ~= child then
				child:Destroy()
			end
		end)
	end
end)

--- One of the five ScreenGuis, with its UIScale installed. Nil (after a
--- warning) when it never arrives. Yields the first time.
function UiKit.gui(name: string): ScreenGui?
	while loading[name] do
		task.wait()
	end
	local known = screens[name]
	if known ~= nil then
		return known or nil
	end
	loading[name] = true
	local screen = playerGui:FindFirstChild(name)
	if not (screen and screen:IsA("ScreenGui")) then
		screen = nil
		local source = StarterGui:WaitForChild(name, 10)
		local arrived = playerGui:FindFirstChild(name)
		if arrived and arrived:IsA("ScreenGui") then
			screen = arrived
		elseif source and source:IsA("ScreenGui") then
			screen = source:Clone()
			screen.Parent = playerGui
		else
			local late = playerGui:WaitForChild(name, 5)
			if late and late:IsA("ScreenGui") then
				screen = late
			end
		end
	end
	if screen then
		screens[name] = screen
		UiKit.safe("UiKit", installScale, screen)
	else
		screens[name] = false
		warn(`[UiKit] ScreenGui {name} never arrived`)
	end
	loading[name] = nil
	return screen
end

function UiKit.playerGui(): PlayerGui
	return playerGui
end

-- ---------------------------------------------------------------- buttons and gamepad focus

local function isGamepad(inputType: Enum.UserInputType): boolean
	return string.sub(inputType.Name, 1, 7) == "Gamepad"
end

--- Wire a button for mouse, touch and gamepad: `Activated` covers all three.
--- A child called Focus (corner brackets) follows hover and gamepad selection,
--- unless `ownFocus` says the caller drives it (a "this one is selected" mark).
function UiKit.button(button: Instance?, fn: () -> (), ownFocus: boolean?): GuiButton?
	if not button or not button:IsA("GuiButton") then
		return nil
	end
	button.Activated:Connect(function()
		UiKit.safe(button.Name, fn)
	end)
	local focus = button:FindFirstChild("Focus")
	if focus and focus:IsA("GuiObject") and not focus.Visible and not ownFocus then
		local hover, selected = false, false
		local function refresh()
			focus.Visible = hover or selected
		end
		button.MouseEnter:Connect(function()
			hover = true
			refresh()
		end)
		button.MouseLeave:Connect(function()
			hover = false
			refresh()
		end)
		button.SelectionGained:Connect(function()
			selected = true
			refresh()
		end)
		button.SelectionLost:Connect(function()
			selected = false
			refresh()
		end)
	end
	return button
end

local wanted: GuiObject? = nil

local function usable(object: GuiObject?): boolean
	if not object or not object:IsDescendantOf(playerGui) then
		return false
	end
	local node: Instance? = object
	while node and node ~= playerGui do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("ScreenGui") and not node.Enabled then
			return false
		end
		node = node.Parent
	end
	return true
end

--- Name the button a gamepad should land on. It is selected at once when a
--- gamepad is in use, and as soon as one is picked up otherwise.
function UiKit.focus(button: Instance?)
	if button and button:IsA("GuiObject") then
		wanted = button
		if isGamepad(UserInputService:GetLastInputType()) and usable(button) then
			GuiService.SelectedObject = button
		end
	end
end

--- Drop the gamepad selection if it sits inside `root` (a panel being closed).
function UiKit.unfocus(root: Instance?)
	if not root then
		return
	end
	if wanted and (wanted == root or wanted:IsDescendantOf(root)) then
		wanted = nil
	end
	local selected = GuiService.SelectedObject
	if selected and (selected == root or selected:IsDescendantOf(root)) then
		GuiService.SelectedObject = nil
	end
end

UserInputService.LastInputTypeChanged:Connect(function(inputType)
	if not isGamepad(inputType) then
		return
	end
	local selected = GuiService.SelectedObject
	if (not selected or not usable(selected)) and usable(wanted) then
		GuiService.SelectedObject = wanted
	end
end)

return UiKit

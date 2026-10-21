--!nonstrict
-- HubUi - the island hub's own interface pieces (T6/T7), built in code in the
-- T2 storybook look: moss panels with a thin gold rim and a soft shade, Luckiest
-- Guy headings over Fredoka body text. One ScreenGui per job, laid inside
-- Roblox's safe area and scaled from the 1920x1080 design like the other screens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Fonts = require(ReplicatedStorage.Shared.Config.Fonts)
local UiKit = require(script.Parent.UiKit)

local HubUi = {}

HubUi.Colours = {
	moss = Color3.fromHex("#16231B"),
	mossDeep = Color3.fromHex("#0E1712"),
	rim = Color3.fromHex("#D9B85C"),
	gold = Color3.fromHex("#FFCB45"),
	goldFill = Color3.fromHex("#B98A2C"),
	ink = Color3.fromHex("#FFF7E8"),
	soft = Color3.fromHex("#D7CFBC"),
	tan = Color3.fromHex("#D9B45A"),
	teal = Color3.fromHex("#5FE3D0"),
	tealFill = Color3.fromHex("#1F6F68"),
	ready = Color3.fromHex("#7BD957"),
	readyFill = Color3.fromHex("#2F6B2A"),
	red = Color3.fromHex("#F2554D"),
	redFill = Color3.fromHex("#5A1B18"),
	quiet = Color3.fromHex("#111A15"),
}

HubUi.Display = Font.new(Fonts.Faces.luckiest.family, Enum.FontWeight.Regular)
HubUi.Body = Font.new(Fonts.Faces.fredoka.family, Enum.FontWeight.Regular)

local DESIGN = Vector2.new(1920, 1080)

--- A ScreenGui inside the core UI's safe area, scaled from the design size.
function HubUi.screen(name: string, order: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = order
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		(gui :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function fit()
		local camera = Workspace.CurrentCamera
		local size = if camera then camera.ViewportSize else DESIGN
		local s = math.min(size.X / DESIGN.X, size.Y / DESIGN.Y)
		-- small screens get a little more than their share, so text stays legible
		scale.Scale = math.clamp(s * (if s < 0.6 then 1.25 else 1), 0.42, 1.6)
	end
	local function watch()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		end
		fit()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)
	watch()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

--- How big the design area is inside a screen (its size over its UIScale).
function HubUi.area(gui: ScreenGui): Vector2
	local scale = gui:FindFirstChildOfClass("UIScale")
	local s = if scale then scale.Scale else 1
	return gui.AbsoluteSize / math.max(s, 0.01)
end

--- A moss panel with the gold rim.
function HubUi.panel(parent: Instance, props): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = HubUi.Colours.moss
	f.BackgroundTransparency = 0.18
	f.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = HubUi.Colours.rim
	stroke.Thickness = 1.5
	stroke.Transparency = 0.15
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 204, 198))
	shade.Parent = f
	for k, v in props or {} do
		f[k] = v
	end
	f.Parent = parent
	return f
end

--- A text label; `face` "display" (Luckiest) or "body" (Fredoka).
function HubUi.label(parent: Instance, text: string, size: number, face: string?, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.FontFace = if face == "display" then HubUi.Display else HubUi.Body
	l.TextColor3 = HubUi.Colours.ink
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextWrapped = true
	l.RichText = false
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(6, 10, 8)
	stroke.Thickness = if face == "display" then 2 else 1.2
	stroke.Transparency = 0.25
	stroke.Parent = l
	for k, v in props or {} do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local KINDS = {
	gold = { fill = HubUi.Colours.goldFill, rim = HubUi.Colours.gold, ink = HubUi.Colours.ink },
	teal = { fill = HubUi.Colours.tealFill, rim = HubUi.Colours.teal, ink = HubUi.Colours.ink },
	ready = { fill = HubUi.Colours.readyFill, rim = HubUi.Colours.ready, ink = HubUi.Colours.ink },
	red = { fill = HubUi.Colours.redFill, rim = HubUi.Colours.red, ink = HubUi.Colours.ink },
	quiet = { fill = HubUi.Colours.quiet, rim = HubUi.Colours.rim, ink = HubUi.Colours.soft },
}

--- A button in one of the panel kinds; `fn` runs on mouse, touch or gamepad.
function HubUi.button(parent: Instance, text: string, kind: string, props, fn): TextButton
	local k = KINDS[kind] or KINDS.quiet
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = k.fill
	b.BorderSizePixel = 0
	b.Text = text
	b.TextSize = 26
	b.FontFace = HubUi.Display
	b.TextColor3 = k.ink
	b.Selectable = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = k.rim
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local text3 = Instance.new("UIStroke")
	text3.Color = Color3.fromRGB(6, 10, 8)
	text3.Thickness = 1.6
	text3.Transparency = 0.3
	text3.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	text3.Parent = b
	for key, v in props or {} do
		b[key] = v
	end
	b.Parent = parent
	if fn then
		UiKit.button(b, fn)
	end
	return b
end

--- Restyle a button made by HubUi.button to another kind.
function HubUi.kind(button: TextButton?, kind: string)
	local k = KINDS[kind]
	if not button or not k then
		return
	end
	button.BackgroundColor3 = k.fill
	button.TextColor3 = k.ink
	local stroke = button:FindFirstChild("Stroke")
	if stroke then
		stroke.Color = k.rim
	end
end

--- A BillboardGui label floating in the world (nameplates, signs).
function HubUi.billboard(adornee: Instance, size: UDim2, offset: Vector3, maxDistance: number?): BillboardGui
	local b = Instance.new("BillboardGui")
	b.Size = size
	b.StudsOffsetWorldSpace = offset
	b.AlwaysOnTop = false
	b.LightInfluence = 0
	b.MaxDistance = maxDistance or 90
	b.ResetOnSpawn = false
	b.Adornee = adornee
	return b
end

return HubUi

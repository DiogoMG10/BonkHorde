--!strict
-- Loading - what a player sees from the moment they join until Skyhold is
-- ready to be seen. ReplicatedFirst runs this before the rest of the game has
-- arrived, so the island is never watched being built, streamed in or framed.
--
-- BONK HORDE in gold over a dark moss field, a slowly turning ring of the
-- portal's light, drifting motes, a line on what is happening and a tip. The
-- game decides when it is done: PortalController sets the LocalPlayer's
-- attribute BonkReady once the hero stands on the island, the ground round
-- them has streamed in and the portal is lit (Core/Crossing gate `join`), and
-- BonkLoading to what it still waits for. This shows it for a short minimum,
-- then opens like the portal does and fades into the island. Whatever goes
-- wrong, it gives up after GIVE_UP seconds: nobody is ever kept here.
--
-- Self-contained on purpose (no requires): it must draw before ReplicatedStorage
-- is there. The textures are the game's own (client Vfx.Tex), nothing new.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MIN_SECONDS = 1.2 -- shown at least this long, so it never flashes
local SLOW_SECONDS = 15 -- then it admits it is taking a while
local GIVE_UP = 45 -- whatever happened, the game is shown after this
local FADE = 0.75

local TEX = {
	glow = "rbxassetid://101511447930755",
	ring = "rbxassetid://136208787434277",
	swirl = "rbxassetid://110730811881184",
	dot = "rbxassetid://93327830389071",
	star = "rbxassetid://138729166738433",
}

local MOSS_TOP = Color3.fromRGB(20, 38, 29)
local MOSS_BOTTOM = Color3.fromRGB(7, 14, 10)
local POOL = Color3.fromRGB(34, 84, 70) -- the soft light behind the ring
local GOLD_HI = Color3.fromRGB(255, 226, 132)
local GOLD_LO = Color3.fromRGB(240, 168, 58)
local INK = Color3.fromRGB(38, 22, 8)
local TEAL = Color3.fromRGB(63, 210, 194)
local MINT = Color3.fromRGB(150, 255, 236)
local LIGHT = Color3.fromRGB(226, 255, 246)
local CREAM = Color3.fromRGB(239, 227, 198)
local SAGE = Color3.fromRGB(143, 168, 151)

local WORDS = {
	hero = "Waking your hero",
	world = "Raising the island",
	detail = "Lighting the portal",
}
local TIPS = {
	"Choose your hero in the Hall of Heroes.",
	"Gather a party at a rune circle and go through the portal together.",
	"Chain your hops to build speed; a slide keeps it.",
	"A level-up waits for your choice: the bar shimmers until you pick.",
}

-- ---------------------------------------------------------------- the screen

local gui = Instance.new("ScreenGui")
gui.Name = "BonkLoading"
gui.DisplayOrder = 100 -- over everything the game draws
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- every piece fades out from its own resting transparency
local fades: { { inst: Instance, prop: string, base: number } } = {}
local function fadeable(inst: Instance, prop: string)
	table.insert(fades, { inst = inst, prop = prop, base = (inst :: any)[prop] })
end

local back = Instance.new("Frame")
back.Name = "Back"
back.Size = UDim2.fromScale(1, 1)
back.BackgroundColor3 = Color3.new(1, 1, 1)
back.BorderSizePixel = 0
back.Active = true -- nothing under it can be clicked while it is up
back.Parent = gui
local shade = Instance.new("UIGradient")
shade.Rotation = 90
shade.Color = ColorSequence.new(MOSS_TOP, MOSS_BOTTOM)
shade.Parent = back

local function image(name: string, tex: string, colour: Color3, size: number, alpha: number, z: number, parent: Instance): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.BackgroundTransparency = 1
	i.Image = tex
	i.ImageColor3 = colour
	i.ImageTransparency = alpha
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.Size = UDim2.fromOffset(size, size)
	i.ZIndex = z
	i.Parent = parent
	return i
end

-- the design is 1920 x 1080, centred and scaled to the screen
local stage = Instance.new("Frame")
stage.Name = "Stage"
stage.BackgroundTransparency = 1
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromOffset(1920, 1080)
stage.Parent = back
local scale = Instance.new("UIScale")
scale.Parent = stage

local pool = image("Pool", TEX.glow, POOL, 1500, 0.45, 1, stage)
pool.Position = UDim2.fromOffset(960, 470)
pool.Size = UDim2.fromOffset(1900, 1500)

-- the ring of portal light
local emblem = Instance.new("Frame")
emblem.Name = "Emblem"
emblem.BackgroundTransparency = 1
emblem.AnchorPoint = Vector2.new(0.5, 0.5)
emblem.Position = UDim2.fromOffset(960, 500)
emblem.Size = UDim2.fromOffset(400, 400)
emblem.Parent = stage
local emblemScale = Instance.new("UIScale")
emblemScale.Parent = emblem
local function centred(i: ImageLabel)
	i.Position = UDim2.fromScale(0.5, 0.5)
end
local halo = image("Halo", TEX.glow, TEAL, 420, 0.7, 2, emblem)
local outer = image("Ring", TEX.ring, GOLD_HI, 250, 0.3, 4, emblem)
local inner = image("Inner", TEX.ring, TEAL, 196, 0.35, 4, emblem)
local swirl = image("Swirl", TEX.swirl, MINT, 168, 0.45, 3, emblem)
local core = image("Core", TEX.glow, LIGHT, 92, 0.35, 5, emblem)
for _, i in { halo, outer, inner, swirl, core } do
	centred(i)
end
local sparks = {}
for k = 1, 4 do
	local s = image(`Spark{k}`, TEX.star, GOLD_HI, 18, 0.2, 6, emblem)
	table.insert(sparks, s)
end

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromOffset(960, 222)
title.Size = UDim2.fromOffset(1400, 150)
title.FontFace = Font.fromEnum(Enum.Font.LuckiestGuy)
title.Text = "BONK HORDE"
title.TextSize = 132
title.TextColor3 = Color3.new(1, 1, 1)
title.ZIndex = 7
title.Parent = stage
local titleShade = Instance.new("UIGradient")
titleShade.Rotation = 90
titleShade.Color = ColorSequence.new(GOLD_HI, GOLD_LO)
titleShade.Parent = title
local titleRim = Instance.new("UIStroke")
titleRim.Color = INK
titleRim.Thickness = 6
titleRim.Parent = title

-- a thin gold rule under the title, a small diamond in the middle
local rule = Instance.new("Frame")
rule.Name = "Rule"
rule.BackgroundTransparency = 1
rule.AnchorPoint = Vector2.new(0.5, 0.5)
rule.Position = UDim2.fromOffset(960, 312)
rule.Size = UDim2.fromOffset(520, 14)
rule.Parent = stage
for side = -1, 1, 2 do
	local line = Instance.new("Frame")
	line.Name = if side < 0 then "Left" else "Right"
	line.BorderSizePixel = 0
	line.BackgroundColor3 = GOLD_LO
	line.BackgroundTransparency = 0.35
	line.AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5)
	line.Position = UDim2.new(0.5, side * 18, 0.5, 0)
	line.Size = UDim2.new(0.5, -18, 0, 3)
	line.ZIndex = 7
	line.Parent = rule
	local taper = Instance.new("UIGradient")
	taper.Transparency = NumberSequence.new(if side < 0 then 1 else 0, if side < 0 then 0 else 1)
	taper.Parent = line
	fadeable(line, "BackgroundTransparency")
end
local diamond = Instance.new("Frame")
diamond.Name = "Diamond"
diamond.BorderSizePixel = 0
diamond.BackgroundColor3 = GOLD_HI
diamond.AnchorPoint = Vector2.new(0.5, 0.5)
diamond.Position = UDim2.fromScale(0.5, 0.5)
diamond.Size = UDim2.fromOffset(10, 10)
diamond.Rotation = 45
diamond.ZIndex = 8
diamond.Parent = rule

local function text(name: string, y: number, size: number, colour: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromOffset(960, y)
	t.Size = UDim2.fromOffset(1500, size + 12)
	t.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	t.TextSize = size
	t.TextColor3 = colour
	t.ZIndex = 7
	t.Parent = stage
	return t
end
local status = text("Status", 758, 36, CREAM)
status.Text = "Entering Skyhold"
-- the dots sit just after the words, so the words never move as they count
local dots = text("Dots", 758, 36, CREAM)
dots.TextXAlignment = Enum.TextXAlignment.Left
dots.Size = UDim2.fromOffset(60, 48)
dots.AnchorPoint = Vector2.new(0, 0.5)
local slow = text("Slow", 806, 24, SAGE)
slow.Text = "Taking a little longer than usual"
slow.TextTransparency = 1
local tip = text("Tip", 990, 24, SAGE)
tip.Text = TIPS[math.random(#TIPS)]
tip.TextTransparency = 0.15

-- motes of light drifting up the screen
local motes = {}
local rng = Random.new()
for k = 1, 16 do
	local warm = k % 3 == 0
	local m = image(`Mote{k}`, TEX.dot, if warm then GOLD_HI else TEAL, rng:NextNumber(5, 12), rng:NextNumber(0.45, 0.8), 2, stage)
	table.insert(motes, {
		image = m,
		x = rng:NextNumber(0, 1920),
		y = rng:NextNumber(0, 1080),
		speed = rng:NextNumber(14, 34),
		sway = rng:NextNumber(0, 6.28),
	})
end

for _, i in { pool, halo, outer, inner, swirl, core } do
	fadeable(i, "ImageTransparency")
end
for _, s in sparks do
	fadeable(s, "ImageTransparency")
end
for _, m in motes do
	fadeable(m.image, "ImageTransparency")
end
for _, t in { title, status, dots, tip } do
	fadeable(t, "TextTransparency")
end
fadeable(titleRim, "Transparency")
fadeable(diamond, "BackgroundTransparency")

gui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- ---------------------------------------------------------------- every frame

local started = os.clock()
local function layout()
	local size = back.AbsoluteSize -- the whole screen, cut-outs included
	if size.X < 1 or size.Y < 1 then
		local camera = Workspace.CurrentCamera
		size = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	end
	-- a short screen (a phone on its side) shows the middle of the design larger
	-- and leaves the tip out, so the words stay readable
	local short = size.Y < 520
	local k = if short then math.min(size.Y / 860, size.X / 1600) else math.min(size.X / 1920, size.Y / 1080)
	scale.Scale = math.clamp(k, 0.3, 3)
	tip.Visible = not short
	titleRim.Thickness = math.max(2, 6 * scale.Scale)
end

local function words(): string
	local awaited = player:GetAttribute("BonkLoading")
	return if typeof(awaited) == "string" and WORDS[awaited] then WORDS[awaited] else "Entering Skyhold"
end

local leaving: number? = nil
local function frame()
	local now = os.clock()
	local t = now - started
	layout()
	-- the ring turns, the vortex inside it the other way, the core breathes
	outer.Rotation = (t * 14) % 360
	inner.Rotation = (-t * 22) % 360
	swirl.Rotation = (-t * 55) % 360
	local breathe = math.sin(t * 2.1)
	core.Size = UDim2.fromOffset(92 + breathe * 10, 92 + breathe * 10)
	for k, s in sparks do
		local a = t * 0.6 + k * math.pi / 2
		s.Position = UDim2.new(0.5, math.cos(a) * 125, 0.5, math.sin(a) * 125)
		s.Rotation = (t * 90 + k * 40) % 360
		if not leaving then
			s.ImageTransparency = 0.25 + 0.5 * (0.5 + 0.5 * math.sin(t * 3 + k * 1.7))
		end
	end
	for _, m in motes do
		m.y -= m.speed * (1 / 60)
		if m.y < -20 then
			m.y = 1100
			m.x = rng:NextNumber(0, 1920)
		end
		m.image.Position = UDim2.fromOffset(m.x + math.sin(t * 0.7 + m.sway) * 14, m.y)
	end
	-- what it is waiting for, with its dots counting, and an admission if slow
	if not leaving then
		local said = words()
		if status.Text ~= said then
			status.Text = said
		end
		dots.Text = string.rep(".", 1 + math.floor(t / 0.45) % 3)
		local bounds = status.TextBounds.X / math.max(scale.Scale, 0.01) -- TextBounds is in screen pixels
		dots.Position = UDim2.fromOffset(960 + bounds / 2 + 2, 758)
		slow.TextTransparency = if t > SLOW_SECONDS then math.max(0.15, 1 - (t - SLOW_SECONDS) / 0.8) else 1
	end
end

local stepped = RunService.RenderStepped:Connect(function()
	local ok, err = pcall(frame)
	if not ok then
		warn(`[Loading] {err}`)
	end
end)

-- ---------------------------------------------------------------- until ready

local function ready(): boolean
	return player:GetAttribute("BonkReady") == true
end

while os.clock() - started < GIVE_UP and not (ready() and os.clock() - started >= MIN_SECONDS) do
	task.wait()
end
if not ready() then
	warn(`[Loading] the game did not say it was ready in {GIVE_UP}s; showing it anyway`)
end

-- open like the portal does: the ring swells as everything fades, the moss last
leaving = os.clock()
slow.TextTransparency = 1
local fadeStart = os.clock()
while true do
	local k = math.clamp((os.clock() - fadeStart) / FADE, 0, 1)
	local eased = k * k * (3 - 2 * k)
	emblemScale.Scale = 1 + 0.35 * eased
	local front = math.clamp(eased * 1.6, 0, 1) -- the words and the ring go first
	for _, f in fades do
		(f.inst :: any)[f.prop] = f.base + (1 - f.base) * front
	end
	back.BackgroundTransparency = math.clamp((eased - 0.25) / 0.75, 0, 1)
	if k >= 1 then
		break
	end
	task.wait()
end
stepped:Disconnect()
gui:Destroy()

--!nonstrict
-- GroundPortal - a magical opening on the ground (T8): the party sinks into one
-- on Skyhold and rises out of another in the Wardwood (and on the plaza, coming
-- home). Purely cosmetic and local to this client: PortalController makes one
-- per opening and tells it every frame how open it is and how strong its magic.
--
-- It is drawn flat on the ground with Skyhold's portal's own language: a soft
-- teal pool of light round it, a dark well inside, three swirls turning against
-- each other over a bright core, a gold rim, a teal outer ring with a dozen
-- runes orbiting between the two; motes rising off it, rays of light shooting
-- up from its rim while heroes pass through, a teal light on whoever stands in
-- it. A hero below its surface is under the ground itself, so the ground hides
-- them.

local Workspace = game:GetService("Workspace")

local Vfx = require(script.Parent.Vfx)

local GroundPortal = {}
GroundPortal.__index = GroundPortal

local TEAL = Color3.fromRGB(64, 214, 200)
local MINT = Color3.fromRGB(150, 255, 236)
local LIGHT = Color3.fromRGB(226, 255, 246)
local WELL = Color3.fromRGB(6, 38, 50)
local LIP = Color3.fromRGB(4, 22, 30)
local GOLD = Color3.fromRGB(255, 222, 150)
local RUNE = Color3.fromRGB(255, 236, 190)

local OPENING = 1 / 1.3 -- the opening's diameter, as a share of the drawn card (room for its pool of light)
local RUNES = { "star4", "plus", "crescent", "shard" }
local RUNE_COUNT = 12

local function image(parent: Instance, name: string, tex: string, colour: Color3, size: number, z: number): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.BackgroundTransparency = 1
	i.Image = Vfx.Tex[tex] or tex
	i.ImageColor3 = colour
	i.ImageTransparency = 1
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.Position = UDim2.fromScale(0.5, 0.5)
	i.Size = UDim2.fromScale(size, size)
	i.ZIndex = z
	i.Parent = parent
	return i
end

local function quiet(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
end

--- A closed portal on the ground at `centre` (the ground's height there),
--- `radius` studs when fully open. `lite` drops a swirl, the runes' flicker
--- and the motes (the lowest graphics settings).
function GroundPortal.new(centre: Vector3, radius: number, lite: boolean?)
	local self = setmetatable({}, GroundPortal)
	self.centre = centre
	self.radius = radius
	self.lite = lite == true
	self.spin = 0
	self.runeTurn = math.random() * 360
	self.clock = 0

	local folder = Instance.new("Folder")
	folder.Name = "GroundPortal"
	self.folder = folder

	-- the card lies a hair above the ground, wide enough for the pool of light
	local span = radius * 2 / OPENING
	local card = Instance.new("Part")
	card.Name = "Card"
	quiet(card)
	card.Size = Vector3.new(span, 0.05, span)
	card.CFrame = CFrame.new(centre + Vector3.new(0, 0.1, 0))
	card.Parent = folder
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Portal"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = math.clamp(520 / span, 12, 40)
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.Parent = card
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(0, 0)
	root.Parent = gui
	self.root = root

	local d = OPENING
	self.layers = {
		halo = image(root, "Halo", "glow", TEAL, 1, 1),
		lip = image(root, "Lip", "ring", LIP, d * 1.06, 2),
		well = image(root, "Well", "glow", WELL, d * 1.2, 3),
		swirlA = image(root, "SwirlA", "swirl", MINT, d * 0.98, 4),
		swirlB = if self.lite then nil else image(root, "SwirlB", "swirl", TEAL, d * 0.74, 5),
		swirlC = image(root, "SwirlC", "swirl", Color3.new(1, 1, 1), d * 0.5, 6),
		core = image(root, "Core", "glow", LIGHT, d * 0.35, 7),
		outer = image(root, "Outer", "ring_thin", TEAL, d * 1.16, 8),
		rim = image(root, "Rim", "ring_thin", GOLD, d * 1.01, 9),
	}
	self.runes = {}
	for k = 1, RUNE_COUNT do
		local rune = image(root, `Rune{k}`, RUNES[(k - 1) % #RUNES + 1], RUNE, d * 0.065, 10)
		table.insert(self.runes, { image = rune, phase = k * 1.7 })
	end

	-- a teal light on whoever stands in it
	local light = Instance.new("PointLight")
	light.Color = TEAL
	light.Shadows = false
	light.Brightness = 0
	light.Range = radius * 1.6 + 6
	local lamp = Instance.new("Attachment")
	lamp.Position = Vector3.new(0, 2.5, 0)
	lamp.Parent = card
	light.Parent = lamp
	self.light = light

	-- motes rising off it, and the column of light while heroes pass through
	local host = Instance.new("Part")
	host.Name = "Motes"
	quiet(host)
	host.Size = Vector3.new(radius * 1.7, 0.2, radius * 1.7)
	host.CFrame = CFrame.new(centre + Vector3.new(0, 0.2, 0))
	host.Parent = folder
	self.motes = if self.lite then {} else Vfx.attach("GroundPortalMotes", host)
	-- the rays rise from the rim, never across the heroes in the middle
	local rim = Instance.new("Part")
	rim.Name = "Rim"
	quiet(rim)
	rim.Size = Vector3.new(radius * 2, 0.2, radius * 2)
	rim.CFrame = CFrame.new(centre + Vector3.new(0, 0.2, 0))
	rim.Parent = folder
	self.rays = Vfx.attach("GroundPortalRays", rim)

	folder.Parent = Workspace
	return self
end

--- Draw it: `open` 0..1 of its full size, `charge` 0..1 of its magic, `column`
--- 0..1 of the column of light, `dt` the frame's seconds.
function GroundPortal:draw(open: number, charge: number, column: number, dt: number)
	open = math.clamp(open, 0, 1)
	charge = math.clamp(charge, 0, 1)
	column = math.clamp(column, 0, 1)
	self.clock += dt
	local c = charge
	self.root.Size = UDim2.fromScale(open, open)
	self.root.Visible = open > 0.01

	-- the swirls turn faster with the magic, against each other
	self.spin = (self.spin + (40 + 260 * c * c) * dt) % 360
	local s = self.spin
	local L = self.layers
	local shown = math.clamp(open * 1.6, 0, 1) -- faint while it is still tiny
	local function alpha(base: number): number
		return 1 - (1 - base) * shown
	end
	L.halo.ImageTransparency = alpha(0.62 - 0.32 * c)
	L.lip.ImageTransparency = alpha(0.35)
	L.well.ImageTransparency = alpha(0.08)
	L.swirlA.Rotation = s
	L.swirlA.ImageTransparency = alpha(0.55 - 0.35 * c)
	if L.swirlB then
		L.swirlB.Rotation = -s * 1.6
		L.swirlB.ImageTransparency = alpha(0.45 - 0.3 * c)
	end
	L.swirlC.Rotation = s * 2.4
	L.swirlC.ImageTransparency = alpha(0.62 - 0.42 * c)
	local breathe = math.sin(self.clock * 2.4) * 0.03
	local core = OPENING * (0.28 + breathe + 0.32 * c * c)
	L.core.Size = UDim2.fromScale(core, core)
	L.core.ImageTransparency = alpha(0.55 - 0.45 * c)
	L.rim.Rotation = -s * 0.2
	L.rim.ImageTransparency = alpha(0.3 - 0.25 * c)
	L.outer.Rotation = s * 0.12
	L.outer.ImageTransparency = alpha(0.55 - 0.3 * c)

	-- the runes orbit between the rim and the outer ring, each flickering
	self.runeTurn = (self.runeTurn + (6 + 30 * c) * dt) % 360
	local ring = OPENING * 0.545
	for k, rune in self.runes do
		local angle = math.rad(self.runeTurn + (k - 1) * 360 / RUNE_COUNT)
		rune.image.Position = UDim2.fromScale(0.5 + math.cos(angle) * ring, 0.5 + math.sin(angle) * ring)
		rune.image.Rotation = math.deg(angle) + 90
		local flicker = if self.lite then 0 else 0.12 * math.sin(self.clock * 3 + rune.phase)
		rune.image.ImageTransparency = alpha(math.clamp(0.35 - 0.3 * c + flicker, 0, 1))
	end

	self.light.Brightness = (0.25 + 1.1 * c * c) * open
	for _, e in self.motes do
		e.Rate = (3 + 22 * c * c) * open
	end
	for _, e in self.rays do
		e.Rate = 30 * column * open
	end
end

--- A ring of light rushing out over the ground as it opens (or in, as it
--- closes), and a burst of stars from its middle.
function GroundPortal:flash(closing: boolean?)
	local at = self.centre + Vector3.new(0, 0.15, 0)
	if closing then
		pcall(Vfx.ground, at, "ring_thin", MINT, self.radius * 1.1, 0.4, 0.45, { alpha = 0.15, hold = 0.2 })
		pcall(Vfx.burst, "PortalArrive", self.centre + Vector3.new(0, 1, 0))
	else
		pcall(Vfx.ground, at, "ring_thin", LIGHT, 0.5, self.radius * 1.25, 0.6, { alpha = 0.1, hold = 0.25 })
	end
end

function GroundPortal:destroy()
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
end

return GroundPortal

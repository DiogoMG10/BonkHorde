--!nonstrict
-- EnemyRenderController - owns the pooled enemy models driven by server
-- snapshots: interpolation, limb animation, hit flash and damage numbers.
--
-- The server sends data, not Instances. This controller keeps one visual per
-- living slot, slides it between snapshots, puts it on the ground using the same
-- heightfield the server uses, and moves every part in one BulkMoveTo per frame.
--
-- A visual comes from the Blender kit (ReplicatedStorage.WardwoodArt.Kit<Model>,
-- baked by the server's ArtKit: the Goblin Runt, Goblin Bruiser and Slime so
-- far) when it has baked, else from ReplicatedStorage.Assets.Enemies.<Model>
-- (parts named Body, Head, ArmL, ArmR, LegL, LegR are animated), and is a
-- plain coloured block otherwise, so the game always has something to draw.
--
-- Enemy outlines, a setting each player chooses (Settings: "Enemy outlines",
-- off by default, the PlayerGui attribute EnemyOutlines): the enemies near the
-- hero get a thin ink outline so the grass cannot hide them. Two Highlights in
-- all (Roblox draws at most 31), each on a container Model the near enemies
-- are moved into a few times a second: one for the small ones, a shade firmer,
-- one for the rest. Occluded, so a hill or a wall still hides them; dark by
-- day, moonlit pale at night. In Studio, `enemy clarity on|off|through|player`
-- in Workspace.BonkDev overrides every player's choice for the session only
-- (through: drawn over the grass where the terrain leaves the enemy in sight;
-- player: back to each player's own setting); nothing it does is saved.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vfx = require(script.Parent.Parent.Vfx)
local Fonts = require(ReplicatedStorage.Shared.Config.Fonts)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Snapshot = require(ReplicatedStorage.Shared.Core.Snapshot)

local GONE_KILLED = 1 -- matches EnemyService

local EnemyRenderController = Knit.CreateController({ Name = "EnemyRenderController" })

local SNAP_INTERVAL = 1 / GameConfig.SnapshotHz
local LIMB_SWING = { ArmL = 1, ArmR = -1, LegL = -1, LegR = 1 }
local MAX_NUMBERS = 60
-- enemy types whose model is not simply "Enemy" .. type
local MODEL_NAME = { BoulderBro = "EnemyRockGolem", Hamlet = "EnemyHogBrute", OldManTimber = "BossOldManTimber" }

-- special attacks (EnemyService, Core/Attacks): what each act looks like
local ACT_CHARGE, ACT_LEAP, ACT_OFF = 1, 2, 3
local CHARGE_LANE = Color3.fromRGB(255, 120, 40) -- a heavy hit coming down a line
local LEAP_RING = Color3.fromRGB(255, 196, 60) -- a light one coming down in a ring
local LEAP_HEIGHT = 4.5 -- the top of a slime's arc, studs

-- enemy clarity
local CLARITY_EVERY = 0.2 -- seconds between choosing who is outlined
local CLARITY_NEAR = 70 -- studs from the hero
local CLARITY_SLACK = 8 -- an outlined enemy keeps it until this much further
local CLARITY_MAX = 90 -- the nearest this many at most
local CLARITY_SMALL = 3.5 -- studs tall or less: the grass can hide most of one
local INK_DAY = Color3.fromRGB(30, 24, 18)

local kitModel: (typeName: string) -> Model?
local INK_NIGHT = Color3.fromRGB(214, 224, 255)

function EnemyRenderController:KnitInit()
	self._sparkBudget = 6
	self._active = {} -- slot -> visual state
	self._pool = {} -- key -> { visual }
	self._parts = {}
	self._cframes = {}
	self._numbers = {}
	self._numberPool = {}
	-- the numbers' face: the default, or one being tried in Studio (`font`)
	local fontAttr = Fonts.Attributes.numbers
	self._numberFont = Fonts.face(Workspace:GetAttribute(fontAttr))
	Workspace:GetAttributeChangedSignal(fontAttr):Connect(function()
		self._numberFont = Fonts.face(Workspace:GetAttribute(fontAttr))
	end)
	self._slots, self._xs, self._zs = {}, {}, {}
	self._icePool = {} -- spare ice shells for frozen enemies
	local folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	self._folder = folder
	local numbers = Instance.new("Folder")
	numbers.Name = "DamageNumbers"
	numbers.Parent = Workspace
	self._numberFolder = numbers
	self:_initClarity()
end

-- ------------------------------------------------------------------ clarity

function EnemyRenderController:_initClarity()
	local c = { t = 0, zones = {} }
	for _, spec in { { name = "Near", day = 0.45, night = 0.55 }, { name = "NearSmall", day = 0.25, night = 0.4 } } do
		-- a Model, not a Folder: a Highlight outlines a Model and all inside it
		local zone = Instance.new("Model")
		zone.Name = spec.name
		local h = Instance.new("Highlight")
		h.FillTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = zone
		zone.Parent = self._folder
		c.zones[spec.name] = { model = zone, highlight = h, day = spec.day, night = spec.night }
	end
	self._clarity = c
	c.mode = "off"
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function readMode()
		-- a Studio override for the session, else the player's own setting
		local dev = Workspace:GetAttribute("BonkEnemyClarity")
		if dev == "on" or dev == "off" or dev == "through" then
			c.mode = dev
		else
			c.mode = if playerGui:GetAttribute("EnemyOutlines") == true then "on" else "off"
		end
		for _, z in c.zones do
			z.highlight.Enabled = c.mode ~= "off"
			z.highlight.DepthMode = if c.mode == "through" then Enum.HighlightDepthMode.AlwaysOnTop else Enum.HighlightDepthMode.Occluded
		end
	end
	local function readSky()
		-- a dark line reads on a sunlit meadow, a pale one under the moon
		local clock = Lighting.ClockTime
		local night = clock < 5.5 or clock > 19.5
		for _, z in c.zones do
			z.highlight.OutlineColor = if night then INK_NIGHT else INK_DAY
			z.highlight.OutlineTransparency = if night then z.night else z.day
		end
	end
	readMode()
	readSky()
	Workspace:GetAttributeChangedSignal("BonkEnemyClarity"):Connect(readMode)
	playerGui:GetAttributeChangedSignal("EnemyOutlines"):Connect(readMode)
	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(readSky)
end

-- whether the terrain leaves the line from the camera to an enemy open (the
-- heightfield the enemies stand on, a few samples: no raycasts)
function EnemyRenderController:_inSight(eye: Vector3, e): boolean
	local tx, ty, tz = e.x, e.y + e.height * 0.6, e.z
	for i = 1, 5 do
		local t = i / 6
		local x, y, z = eye.X + (tx - eye.X) * t, eye.Y + (ty - eye.Y) * t, eye.Z + (tz - eye.Z) * t
		if self._state:HeightAt(x, z) > y then
			return false
		end
	end
	return true
end

function EnemyRenderController:_stepClarity(dt: number)
	local c = self._clarity
	c.t += dt
	if c.t < CLARITY_EVERY then
		return
	end
	c.t = 0
	local chosen = {}
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if c.mode ~= "off" and camera and root then
		local fx, fz = root.Position.X, root.Position.Z
		local eye = camera.CFrame.Position
		local list = {}
		for _, e in self._active do
			if e.x then
				local r = if e.visual.zone then CLARITY_NEAR + CLARITY_SLACK else CLARITY_NEAR
				local d2 = (e.x - fx) ^ 2 + (e.z - fz) ^ 2
				if d2 < r * r and (c.mode ~= "through" or self:_inSight(eye, e)) then
					table.insert(list, { e = e, d2 = d2 })
				end
			end
		end
		if #list > CLARITY_MAX then
			table.sort(list, function(a, b)
				return a.d2 < b.d2
			end)
		end
		for i = 1, math.min(#list, CLARITY_MAX) do
			chosen[list[i].e] = true
		end
	end
	for _, e in self._active do
		local zone = nil
		if chosen[e] then
			zone = if e.height <= CLARITY_SMALL then c.zones.NearSmall.model else c.zones.Near.model
		end
		local visual = e.visual
		if visual.zone ~= zone then
			visual.zone = zone
			visual.model.Parent = zone or self._folder
		end
	end
end

--- Where an enemy is being drawn, for effects that chase it. nil if not visible.
function EnemyRenderController:PosOf(slot: number): Vector3?
	local e = self._active[slot]
	if e and e.x then
		return Vector3.new(e.x, e.y + e.height * 0.5, e.z)
	end
	return nil
end

-- ------------------------------------------------------------------ visuals

local function placeholder(def, scale: number): Model
	local model = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(def.radius * 2, def.height, def.radius * 2) * scale
	body.Color = Color3.fromRGB(def.colour[1], def.colour[2], def.colour[3])
	body.Material = Enum.Material.SmoothPlastic
	body.Parent = model
	local eyes = Instance.new("Part")
	eyes.Name = "Eyes"
	eyes.Size = Vector3.new(def.radius * 1.4, def.height * 0.12, 0.3) * scale
	eyes.Color = Color3.fromRGB(20, 20, 24)
	eyes.Material = Enum.Material.SmoothPlastic
	eyes.CFrame = CFrame.new(0, def.height * 0.25 * scale, -def.radius * scale)
	eyes.Parent = model
	model.PrimaryPart = body
	return model
end

-- the Blender kit's model for an enemy type, once the server has baked it
kitModel = function(typeName: string): Model?
	local art = ReplicatedStorage:FindFirstChild("WardwoodArt")
	local found = art and art:FindFirstChild("Kit" .. (MODEL_NAME[typeName] or ("Enemy" .. typeName)))
	return if found and found:IsA("Model") then found else nil
end

function EnemyRenderController:_build(typeName: string, elite: boolean, runner: boolean)
	local def = Roster.Enemies[typeName]
	local scale = if elite then GameConfig.EliteScale else 1
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local modelName = MODEL_NAME[typeName] or ("Enemy" .. typeName)
	local kit = kitModel(typeName)
	local source = kit or (assets and assets:FindFirstChild("Enemies") and assets.Enemies:FindFirstChild(modelName))
	local model: Model
	if source and source:IsA("Model") then
		model = source:Clone()
		-- fit the model to the height the roster gives this enemy, so one mesh can serve two sizes
		local _, size = model:GetBoundingBox()
		local fit = if size.Y > 0.1 then def.height / size.Y else 1
		model:ScaleTo(fit * scale)
	else
		model = placeholder(def, scale)
	end
	if elite then
		local pivot = model:GetPivot()
		local above = pivot * CFrame.new(0, def.height * scale * 0.5 + 1.4, 0)
		local crownSource = assets and assets:FindFirstChild("Pickups") and assets.Pickups:FindFirstChild("EliteCrown")
		local body = crownSource and crownSource:FindFirstChild("Body")
		local crown: BasePart
		if body and body:IsA("BasePart") then
			crown = body:Clone()
			crown.Size *= 1.6
			crown.CFrame = above
		else
			local fallback = Instance.new("Part")
			fallback.Shape = Enum.PartType.Cylinder
			fallback.Size = Vector3.new(0.5, 1.4, 1.4)
			fallback.Color = Color3.fromRGB(255, 206, 50)
			fallback.Material = Enum.Material.Neon
			fallback.CFrame = above * CFrame.Angles(0, 0, math.rad(90))
			crown = fallback
		end
		crown.Name = "Crown"
		crown.Anchored = true
		crown.CanCollide = false
		crown.CanQuery = false
		crown.CanTouch = false
		crown.CastShadow = false
		crown.Parent = model
		pcall(Vfx.attach, "EliteGlint", crown)
	end
	if typeName == "Ghost" then
		local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if body then
			pcall(Vfx.attach, "GhostWisp", body)
		end
	end
	if runner then
		-- an overtime runner trails embers: the fast ones read before they arrive
		local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if body then
			pcall(Vfx.attach, "RunnerEmbers", body)
		end
	end

	local pivot = model:GetPivot()
	local parts, offsets, limbs, colours = {}, {}, {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = d.Name == "Body"
			table.insert(parts, d)
			table.insert(offsets, pivot:ToObjectSpace(d.CFrame))
			table.insert(limbs, LIMB_SWING[d.Name] or 0)
			table.insert(colours, d.Color)
		end
	end
	model.Parent = self._folder
	return {
		model = model,
		parts = parts,
		offsets = offsets,
		limbs = limbs,
		colours = colours,
		isPlaceholder = source == nil,
		isKit = kit ~= nil,
	}
end

function EnemyRenderController:_acquire(typeName: string, elite: boolean, runner: boolean)
	local key = typeName .. (if elite then "#E" else "") .. (if runner then "#R" else "")
	local list = self._pool[key]
	local visual = list and table.remove(list)
	if visual and not visual.isKit and kitModel(typeName) then
		-- built before the kit's model had baked: retire it for the new one
		visual.model:Destroy()
		visual = nil
	end
	if not visual then
		visual = self:_build(typeName, elite, runner)
	elseif visual.isPlaceholder then
		visual.parts[1].Color = visual.colours[1] -- it may have been released mid-flash
	end
	visual.key = key
	return visual
end

function EnemyRenderController:_release(visual)
	if visual.zone then
		visual.zone = nil
		visual.model.Parent = self._folder
	end
	local far = CFrame.new(0, -500, 0)
	local parts, cframes = visual.parts, {}
	for i = 1, #parts do
		cframes[i] = far
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	local list = self._pool[visual.key]
	if not list then
		list = {}
		self._pool[visual.key] = list
	end
	table.insert(list, visual)
end

function EnemyRenderController:_clear()
	for slot, e in self._active do
		self:_thaw(e)
		self:_release(e.visual)
		self._active[slot] = nil
	end
end

-- ------------------------------------------------------------------ frozen look

-- A frozen enemy is encased in one translucent block of ice, sized to its
-- height. One pooled part per frozen enemy, placed in the same BulkMoveTo as
-- the body, so a crowd of frozen enemies costs a few parts and no extra loop.
local ICE_COLOUR = Color3.fromRGB(175, 225, 255)

function EnemyRenderController:_freeze(e, seconds: number)
	e.frozenUntil = math.max(e.frozenUntil or 0, os.clock() + seconds)
	if e.ice then
		return
	end
	local ice = table.remove(self._icePool)
	if not ice then
		ice = Instance.new("Part")
		ice.Name = "Ice"
		ice.Anchored, ice.CanCollide, ice.CanQuery, ice.CanTouch = true, false, false, false
		ice.CastShadow = false
		ice.Material = Enum.Material.Ice
		ice.Color = ICE_COLOUR
		ice.Transparency = 0.4
		ice.Parent = self._folder
	end
	local h = e.height
	ice.Size = Vector3.new(h * 0.75, h * 1.05, h * 0.75)
	e.ice = ice
end

function EnemyRenderController:_thaw(e)
	local ice = e.ice
	if ice then
		e.ice = nil
		ice.CFrame = CFrame.new(0, -500, 0)
		table.insert(self._icePool, ice)
	end
end

-- ------------------------------------------------------------------ damage numbers

-- numbers only, no words: strength reads from colour, size and a pop.
-- normal white, crit gold, megacrit orange-red; poison green, ice blue
local NUMBER_COLOURS = {
	[0] = Color3.fromRGB(255, 255, 255),
	[1] = Color3.fromRGB(255, 212, 40),
	[2] = Color3.fromRGB(255, 92, 36),
}
local NUMBER_STROKES = {
	[0] = Color3.fromRGB(10, 10, 14),
	[1] = Color3.fromRGB(70, 40, 0),
	[2] = Color3.fromRGB(80, 8, 0),
}
local NUMBER_SCALE = { [0] = 1, [1] = 1.3, [2] = 1.6 }
local NUMBER_POP = { [0] = 1.15, [1] = 1.6, [2] = 2.1 } -- how big it starts before it settles

function EnemyRenderController:_number(position: Vector3, amount: number, flags: number)
	if #self._numbers >= MAX_NUMBERS then
		return
	end
	local gui = table.remove(self._numberPool)
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(160, 56)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 220
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
		label.Parent = gui
		Instance.new("UIScale").Parent = label
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = self._numberFolder
		gui.Adornee = part
		gui.Parent = part
	end
	local crit = math.min(bit32.band(flags, 3), 2)
	local label = gui.Label
	label.FontFace = self._numberFont
	label.Text = tostring(amount)
	label.TextColor3 = if bit32.band(flags, 4) ~= 0
		then Color3.fromRGB(140, 235, 90)
		elseif bit32.band(flags, 8) ~= 0 then Color3.fromRGB(120, 220, 255)
		else NUMBER_COLOURS[crit]
	label.TextStrokeColor3 = NUMBER_STROKES[crit]
	label.TextSize = math.clamp(20 + math.sqrt(amount) * 2.2, 22, 54) * NUMBER_SCALE[crit]
	label.Rotation = math.random(-12, 12) * (if crit > 0 then 0.5 else 1)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0
	label.UIScale.Scale = NUMBER_POP[crit]
	gui.Enabled = true
	local jitter = Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10)
	table.insert(self._numbers, { gui = gui, part = gui.Adornee, origin = position + jitter, born = os.clock(), pop = NUMBER_POP[crit] })
end

function EnemyRenderController:_stepNumbers(now: number)
	local numbers = self._numbers
	for i = #numbers, 1, -1 do
		local n = numbers[i]
		local age = (now - n.born) / 0.7
		if age >= 1 then
			n.gui.Enabled = false
			table.insert(self._numberPool, n.gui)
			table.remove(numbers, i)
		else
			n.part.Position = n.origin + Vector3.new(0, 1 + age * 3.5, 0)
			local fade = math.clamp((age - 0.6) / 0.4, 0, 1)
			local label = n.gui.Label
			label.TextTransparency = fade
			label.TextStrokeTransparency = fade
			-- a hard hit lands big and settles in the first moment
			local settle = math.clamp(age / 0.18, 0, 1)
			label.UIScale.Scale = n.pop + (1 - n.pop) * (1 - (1 - settle) ^ 3)
		end
	end
end

-- ------------------------------------------------------------------ network

function EnemyRenderController:KnitStart()
	self._state = Knit.GetController("StateController")
	self:_watchBench()
	local half = GameConfig.MapSizeStuds / 2

	local function on(name, fn)
		local remote = Net.client(name)
		if remote then
			remote.OnClientEvent:Connect(fn)
		end
	end

	on("EnemySpawn", function(b: buffer)
		for i = 0, buffer.len(b) / 4 - 1 do
			local o = i * 4
			local slot = buffer.readu16(b, o)
			local typeName = Roster.EnemyOrder[buffer.readu8(b, o + 2)]
			local flags = buffer.readu8(b, o + 3)
			local elite = bit32.band(flags, 1) ~= 0
			local runner = bit32.band(flags, 2) ~= 0
			local old = self._active[slot]
			if old then
				self:_thaw(old)
				self:_release(old.visual)
			end
			if typeName then
				local def = Roster.Enemies[typeName]
				self._active[slot] = {
					visual = self:_acquire(typeName, elite, runner),
					def = def,
					height = def.height * (if elite then GameConfig.EliteScale else 1),
					yaw = 0,
					phase = math.random() * 6,
					flashUntil = 0,
				}
			end
		end
	end)

	on("EnemySnap", function(b: buffer)
		local slots, xs, zs = self._slots, self._xs, self._zs
		local count = Snapshot.decode(b, half, slots, xs, zs)
		local now = os.clock()
		for i = 1, count do
			local e = self._active[slots[i]]
			if e then
				if e.x then
					e.px, e.pz = e.x, e.z
				else
					e.px, e.pz = xs[i], zs[i]
					e.x, e.z = xs[i], zs[i]
					e.y = self._state:HeightAt(xs[i], zs[i])
				end
				e.tx, e.tz = xs[i], zs[i]
				e.t0 = now
			end
		end
	end)

	on("EnemyGone", function(b: buffer)
		for i = 0, buffer.len(b) / 3 - 1 do
			local slot = buffer.readu16(b, i * 3)
			local e = self._active[slot]
			if e then
				if buffer.readu8(b, i * 3 + 2) == GONE_KILLED and e.x then
					pcall(Vfx.burst, "DeathPoof", Vector3.new(e.x, e.y + e.height * 0.5, e.z))
				end
				self:_thaw(e)
				self:_release(e.visual)
				self._active[slot] = nil
			end
		end
	end)

	-- a special attack starting: its telegraph for everyone, its moves for the model
	on("EnemyAct", function(slot: number, code: number, bx: number, bz: number, windup: number, dur: number)
		local e = self._active[slot]
		if not e or not e.x then
			return
		end
		if code == ACT_OFF then
			e.act = nil
			return
		end
		local atk = e.def.attack
		if not atk then
			return
		end
		local state = self._state
		e.act = { code = code, t0 = os.clock(), windup = windup, dur = dur, recover = atk.recover }
		e.act.yaw = math.atan2(-(bx - e.x), -(bz - e.z))
		pcall(function()
			if code == ACT_CHARGE then
				-- the lane it will run, filling as the windup runs out
				local from = Vector3.new(e.x, state:HeightAt(e.x, e.z) + 0.35, e.z)
				local to = Vector3.new(bx, state:HeightAt(bx, bz) + 0.35, bz)
				Vfx.lane(from, to, atk.width * 2 + 0.6, CHARGE_LANE, windup, windup + dur + 0.1)
				task.delay(windup, function()
					Vfx.burst("DustPuff", from)
				end)
			elseif code == ACT_LEAP then
				-- the ring it will land in, filling as it comes down
				local at = Vector3.new(bx, state:HeightAt(bx, bz) + 0.4, bz)
				local life = windup + dur
				Vfx.ground(at, "ring", LEAP_RING, atk.radius, atk.radius, life + 0.05, { alpha = 0.15, hold = 0.95 })
				Vfx.ground(at, "dot", LEAP_RING, 0.4, atk.radius * 0.94, life + 0.05, { alpha = 0.6, hold = 0.95 })
				task.delay(life, function()
					Vfx.ground(at, "ring_thin", Color3.fromRGB(255, 240, 200), atk.radius * 0.5, atk.radius * 1.6, 0.3)
					Vfx.burst("DustPuff", at)
				end)
			end
		end)
	end)

	on("EnemyFrozen", function(b: buffer)
		for i = 0, buffer.len(b) / 3 - 1 do
			local e = self._active[buffer.readu16(b, i * 3)]
			if e then
				self:_freeze(e, buffer.readu8(b, i * 3 + 2) / 10)
			end
		end
	end)

	on("Hits", function(b: buffer)
		local now = os.clock()
		for i = 0, buffer.len(b) / 5 - 1 do
			local o = i * 5
			local slot = buffer.readu16(b, o)
			local e = self._active[slot]
			if e and e.x then
				e.flashUntil = now + 0.09
				local flags = buffer.readu8(b, o + 4)
				self:_number(Vector3.new(e.x, e.y + e.height, e.z), buffer.readu16(b, o + 2), flags)
				-- every hit sparks; the budget keeps a 300-enemy frost tick from flooding the screen
				if self._sparkBudget > 0 then
					self._sparkBudget -= 1
					local at = Vector3.new(e.x, e.y + e.height * 0.6, e.z)
					pcall(Vfx.burst, if bit32.band(flags, 3) > 0 then "CritBurst" else "HitSpark", at)
				end
			end
		end
	end)

	self._state.Changed:Connect(function(key)
		if key == "phase" and self._state.phase == "Lobby" then
			self:_clear()
		end
	end)

	RunService:BindToRenderStep("BonkEnemies", Enum.RenderPriority.Character.Value + 1, function(dt)
		self:_frame(dt)
	end)
end

-- Studio only (DevService `bench`): while Workspace.BonkBench is set, time
-- every frame and this controller's own share of it, then print them.
function EnemyRenderController:_watchBench()
	Workspace:GetAttributeChangedSignal("BonkBench"):Connect(function()
		local seconds = Workspace:GetAttribute("BonkBench")
		if typeof(seconds) ~= "number" or self._bench then
			return
		end
		local b = { frames = 0, sum = 0, worst = 0, own = 0, enemies = 0, parts = 0 }
		self._bench = b
		local conn = RunService.Heartbeat:Connect(function(dt)
			b.frames += 1
			b.sum += dt
			b.worst = math.max(b.worst, dt)
			local n = 0
			for _ in self._active do
				n += 1
			end
			b.enemies = math.max(b.enemies, n)
			b.parts = math.max(b.parts, #self._parts)
		end)
		task.delay(seconds, function()
			conn:Disconnect()
			self._bench = nil
			print(
				string.format(
					"[Bench] client: %.0f fps mean, worst frame %.1f ms; enemy drawing %.2f ms a frame; up to %d enemies, %d parts moved a frame",
					b.frames / math.max(b.sum, 1e-3),
					b.worst * 1000,
					b.own / math.max(b.frames, 1) * 1000,
					b.enemies,
					b.parts
				)
			)
		end)
	end)
end

function EnemyRenderController:_frame(dt: number)
	local benchStart = if self._bench then os.clock() else 0
	self._sparkBudget = 6
	local now = os.clock()
	local state = self._state
	local parts, cframes = self._parts, self._cframes
	local n = 0
	local white = Color3.new(1, 1, 1)
	local paused = state.paused

	for _, e in self._active do
		if not e.tx then
			continue
		end
		local alpha = math.min((now - e.t0) / SNAP_INTERVAL, 1)
		local x = e.px + (e.tx - e.px) * alpha
		local z = e.pz + (e.tz - e.pz) * alpha
		local mx, mz = e.tx - e.px, e.tz - e.pz
		local moving = mx * mx + mz * mz > 0.0025
		if moving then
			local want = math.atan2(-mx, -mz)
			local delta = (want - e.yaw + math.pi) % (2 * math.pi) - math.pi
			e.yaw += delta * math.min(1, dt * 10)
			e.phase += dt * 9
		end
		local ground = state:HeightAt(x, z)
		e.x, e.z, e.y = x, z, ground

		local def = e.def
		local lift = 0
		if def.flying then
			lift = 2.5 + math.sin(e.phase * 0.5) * 0.6
		elseif def.hop then
			lift = math.abs(math.sin(e.phase * 0.8)) * 1.6
		elseif moving then
			lift = math.abs(math.sin(e.phase)) * 0.25
		end
		-- a special attack's moves: a charger braces back, runs leaning in, then
		-- sways winded; a leaper squats, arcs through the air, lands splattered
		local tilt = 0
		local act = e.act
		if act then
			local ta = now - act.t0
			local w, d = act.windup, act.dur
			if ta > w + d + act.recover then
				e.act = nil
			elseif act.code == ACT_CHARGE then
				e.yaw = act.yaw
				if ta < w then
					tilt = 0.16 + math.sin(ta * 40) * 0.03
					lift = 0
				elseif ta < w + d then
					tilt = -0.28
					e.phase += dt * 18
				else
					tilt = math.sin(ta * 9) * 0.08
					lift = 0
				end
			else
				e.yaw = act.yaw
				if ta < w then
					lift = -0.3 * (ta / w)
				elseif ta < w + d then
					local s = (ta - w) / d
					lift = 4 * LEAP_HEIGHT * s * (1 - s)
				else
					lift = -0.25 * (1 - (ta - w - d) / act.recover)
				end
			end
		end
		local root = CFrame.new(x, ground + e.height * 0.5 + lift, z) * CFrame.Angles(0, e.yaw, 0) * CFrame.Angles(tilt, 0, 0)

		local visual = e.visual
		local vParts, offsets, limbs = visual.parts, visual.offsets, visual.limbs
		local swing = if moving then math.sin(e.phase) * 0.7 else 0
		for i = 1, #vParts do
			n += 1
			parts[n] = vParts[i]
			local limb = limbs[i]
			if limb ~= 0 then
				-- swing a limb about its own top edge
				local off = offsets[i]
				local topY = vParts[i].Size.Y * 0.5
				cframes[n] = root * off * CFrame.new(0, topY, 0) * CFrame.Angles(swing * limb, 0, 0) * CFrame.new(0, -topY, 0)
			else
				cframes[n] = root * offsets[i]
			end
		end

		if e.ice then
			if paused then
				e.frozenUntil += dt -- the server's freeze clock stops while paused too
			end
			if now >= e.frozenUntil then
				self:_thaw(e)
			else
				n += 1
				parts[n] = e.ice
				cframes[n] = root
			end
		end

		if visual.isPlaceholder then
			local flashing = now < e.flashUntil
			if flashing ~= e.flashing then
				e.flashing = flashing
				vParts[1].Color = if flashing then white else visual.colours[1]
			end
		end
	end

	for i = n + 1, #parts do
		parts[i] = nil
		cframes[i] = nil
	end
	if n > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	self:_stepNumbers(now)
	self:_stepClarity(dt)
	if self._bench then
		self._bench.own += os.clock() - benchStart
	end
end

return EnemyRenderController

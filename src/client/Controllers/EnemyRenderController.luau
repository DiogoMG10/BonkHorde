--!nonstrict
-- EnemyRenderController - owns the pooled enemy models driven by server
-- snapshots: interpolation, limb animation, hit flash and damage numbers.
--
-- The server sends data, not Instances. This controller keeps one visual per
-- living slot, slides it between snapshots, puts it on the ground using the same
-- heightfield the server uses, and moves every part in one BulkMoveTo per frame.
--
-- A visual comes from ReplicatedStorage.Assets.Enemies.<Type> when that model
-- exists (parts named Body, Head, ArmL, ArmR, LegL, LegR are animated), and is a
-- plain coloured block otherwise, so the game always has something to draw.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vfx = require(script.Parent.Parent.Vfx)
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

function EnemyRenderController:KnitInit()
	self._sparkBudget = 6
	self._active = {} -- slot -> visual state
	self._pool = {} -- key -> { visual }
	self._parts = {}
	self._cframes = {}
	self._numbers = {}
	self._numberPool = {}
	self._slots, self._xs, self._zs = {}, {}, {}
	local folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	self._folder = folder
	local numbers = Instance.new("Folder")
	numbers.Name = "DamageNumbers"
	numbers.Parent = Workspace
	self._numberFolder = numbers
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

function EnemyRenderController:_build(typeName: string, elite: boolean)
	local def = Roster.Enemies[typeName]
	local scale = if elite then GameConfig.EliteScale else 1
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local modelName = MODEL_NAME[typeName] or ("Enemy" .. typeName)
	local source = assets and assets:FindFirstChild("Enemies") and assets.Enemies:FindFirstChild(modelName)
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
	return { model = model, parts = parts, offsets = offsets, limbs = limbs, colours = colours, isPlaceholder = source == nil }
end

function EnemyRenderController:_acquire(typeName: string, elite: boolean)
	local key = typeName .. (if elite then "#E" else "")
	local list = self._pool[key]
	local visual = list and table.remove(list)
	if not visual then
		visual = self:_build(typeName, elite)
	elseif visual.isPlaceholder then
		visual.parts[1].Color = visual.colours[1] -- it may have been released mid-flash
	end
	visual.key = key
	return visual
end

function EnemyRenderController:_release(visual)
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
		self:_release(e.visual)
		self._active[slot] = nil
	end
end

-- ------------------------------------------------------------------ damage numbers

local NUMBER_COLOURS = {
	[0] = Color3.fromRGB(255, 255, 255),
	[1] = Color3.fromRGB(255, 221, 60),
	[2] = Color3.fromRGB(255, 120, 40),
}

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
		label.Font = Enum.Font.LuckiestGuy
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
		label.Parent = gui
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
	local crit = bit32.band(flags, 3)
	local label = gui.Label
	label.Text = (if crit > 0 then "CRIT! " else "") .. tostring(amount)
	label.TextColor3 = if bit32.band(flags, 4) ~= 0
		then Color3.fromRGB(140, 235, 90)
		elseif bit32.band(flags, 8) ~= 0 then Color3.fromRGB(120, 220, 255)
		else NUMBER_COLOURS[crit] or NUMBER_COLOURS[0]
	local size = math.clamp(20 + math.sqrt(amount) * 2.2, 22, 54) * (if crit > 0 then 1.25 else 1)
	label.TextSize = size
	label.Rotation = math.random(-12, 12)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0
	gui.Enabled = true
	local jitter = Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10)
	table.insert(self._numbers, { gui = gui, part = gui.Adornee, origin = position + jitter, born = os.clock() })
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
			n.gui.Label.TextTransparency = fade
			n.gui.Label.TextStrokeTransparency = fade
		end
	end
end

-- ------------------------------------------------------------------ network

function EnemyRenderController:KnitStart()
	self._state = Knit.GetController("StateController")
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
			local elite = buffer.readu8(b, o + 3) == 1
			local old = self._active[slot]
			if old then
				self:_release(old.visual)
			end
			if typeName then
				local def = Roster.Enemies[typeName]
				self._active[slot] = {
					visual = self:_acquire(typeName, elite),
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
				self:_release(e.visual)
				self._active[slot] = nil
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

function EnemyRenderController:_frame(dt: number)
	self._sparkBudget = 6
	local now = os.clock()
	local state = self._state
	local parts, cframes = self._parts, self._cframes
	local n = 0
	local white = Color3.new(1, 1, 1)

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
		local root = CFrame.new(x, ground + e.height * 0.5 + lift, z) * CFrame.Angles(0, e.yaw, 0)

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
end

return EnemyRenderController

--!nonstrict
-- WeaponFxController - owns weapon, projectile and telegraph visuals, replayed
-- from server events.
--
-- Standing rule: cosmetics can never break gameplay. Every effect here is
-- pcall-isolated and built from plain parts, so a failed effect is one missing
-- flash and never a dead client. The VFX stage swaps these shapes for real
-- effects by replacing entries in the `Effects` table.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Vfx = require(script.Parent.Parent.Vfx)
local Net = require(ReplicatedStorage.Shared.Net)

local WeaponFxController = Knit.CreateController({ Name = "WeaponFxController" })

local P_FIREBALL, P_BONE, P_NANA, P_ROCKET, P_THORN = 1, 2, 3, 4, 5
local PROJ_LOOK = {
	[P_FIREBALL] = {
		colour = Color3.fromRGB(255, 160, 40),
		size = Vector3.new(2, 2, 2),
		shape = Enum.PartType.Ball,
		neon = true,
		trail = "FireTrail",
	},
	[P_BONE] = {
		colour = Color3.fromRGB(240, 235, 215),
		size = Vector3.new(0.7, 2.6, 0.7),
		spin = 14,
		model = "WeaponBone",
		trail = "PaleTrail",
	},
	[P_NANA] = {
		colour = Color3.fromRGB(255, 220, 50),
		size = Vector3.new(0.9, 3.4, 0.9),
		spin = 18,
		model = "WeaponBoomernana",
		trail = "PaleTrail",
	},
	[P_ROCKET] = {
		colour = Color3.fromRGB(255, 90, 170),
		size = Vector3.new(0.9, 0.9, 2.6),
		neon = true,
		model = "WeaponRocket",
		trail = "RocketTrail",
	},
	[P_THORN] = { colour = Color3.fromRGB(40, 110, 40), size = Vector3.new(0.6, 0.6, 3), neon = false, trail = "ThornTrail" },
}

local folder: Folder

local function part(size: Vector3, colour: Color3, cframe: CFrame, transparency: number?, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = colour
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.CFrame = cframe
	p.Parent = folder
	return p
end

-- the mesh of a weapon from the asset pack, as one loose anchored part
local function model(name: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assets:FindFirstChild("Weapons") and assets.Weapons:FindFirstChild(name)
	local body = source and source:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return nil
	end
	local p = body:Clone()
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder
	return p
end

-- ---------------------------------------------------------------- the sword slash

local SLASH_CORE = Color3.fromRGB(255, 255, 255)
local SLASH_GLOW = Color3.fromRGB(150, 210, 255)
local SLASH_INK = Color3.fromRGB(22, 34, 62) -- the dark edge that makes the white read
local TRAIL_ON = 0.28 -- seconds the blade leaves a trail: the swing animation's length
local CUT_LIFE = 0.32 -- the crescent's whole life...
local CUT_DRAW = 0.45 -- ...the share of it the head takes to cross the arc
local CUT_SEGMENTS = 20
local CUT_RADIUS = 0.85 -- the centre line, as a share of the hit range
local CUT_WIDTH = 2.2 -- studs at the thickest point, for a 13-stud reach
local CUT_TILT = 0 -- a level, horizontal cut: no side runs higher than the other...
local CUT_BANK = math.rad(10) -- ...but its middle rises a little, so from behind it reads as a curve
-- A ribbon behind the hero's own blade, from just above the grip to the tip.
-- It follows whatever the swing animation does, so it can never point the
-- wrong way. The held weapon is welded with its length along its Y axis
-- (PlayerStateService:_dress). Made once per character, switched on per swing.
local function bladeTrail(character: Model): Trail?
	local blade = character:FindFirstChild("HeldWeapon")
	if not blade or not blade:IsA("BasePart") then
		return nil
	end
	local trail = blade:FindFirstChild("SlashTrail")
	if trail and trail:IsA("Trail") then
		return trail
	end
	local length = blade.Size.Y
	local base = Instance.new("Attachment")
	base.Name = "SlashBase"
	base.Position = Vector3.new(0, -0.1 * length, 0)
	base.Parent = blade
	local tip = Instance.new("Attachment")
	tip.Name = "SlashTip"
	tip.Position = Vector3.new(0, 0.55 * length, 0)
	tip.Parent = blade
	local t = Instance.new("Trail")
	t.Name = "SlashTrail"
	t.Attachment0 = base
	t.Attachment1 = tip
	t.FaceCamera = false -- the ribbon is the surface the blade sweeps
	t.Lifetime = 0.16
	t.MinLength = 0.05
	t.LightEmission = 1
	t.LightInfluence = 0
	t.Color = ColorSequence.new(SLASH_CORE, SLASH_GLOW)
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.4, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	t.Enabled = false
	t.Parent = blade
	return t
end

-- Pooled ribbon pieces for the crescent: a slash every second must not churn
-- a hundred new parts each time.
local piecePool: { Part } = {}

local function piece(colour: Color3, neon: boolean): Part
	local p = table.remove(piecePool)
	if not p then
		p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.CastShadow = false
		p.Parent = folder
	end
	p.Color = colour
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Transparency = 1
	return p
end

local function release(p: Part)
	p.Transparency = 1
	p.CFrame = CFrame.new(0, -500, 0)
	table.insert(piecePool, p)
end

-- Width along the visible stroke, s = 0 at the tail to 1 at the head: a hair at
-- the tail, swelling to full at 80 %, a blunt point at the head.
local function strokeWidth(s: number): number
	if s < 0.8 then
		return 0.06 + 0.94 * (s / 0.8) ^ 1.5
	end
	return 1 - 0.55 * (s - 0.8) / 0.2
end

-- The cut itself, after the reference slash: an anime crescent drawn in the
-- air on the edge of the hit area (range x arc around the swing direction, the
-- same area CombatService Fire.Arc tests). Its head races from the hero's right
-- to their left with the blade; the stroke behind it is thick and white near
-- the head and thins to a hair at the tail, with a dark ink edge and two thin
-- brush streaks; then the tail eats the stroke up to the head and it is gone.
-- Every piece is a ribbon turned to face the camera, so it reads as a drawn
-- stroke from any angle and never as a mark on the floor.
local function crescent(at: Vector3, forward: Vector3, range: number, arcDeg: number)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local half = math.rad(arcDeg) / 2
	local radius0 = range * CUT_RADIUS
	local width0 = CUT_WIDTH * math.clamp(range / 13, 0.7, 1.6)
	local centre = at + Vector3.new(0, 0.4, 0)

	-- a point on the arc at radius r: v = 0 at the right end, 1 at the left
	local function point(v: number, r: number): Vector3
		local a = half - v * 2 * half
		local rise = r * (math.sin(a) * math.sin(CUT_TILT) + (math.cos(a) - math.cos(half)) * math.sin(CUT_BANK))
		return centre + (forward * math.cos(a) + right * math.sin(a)) * r + Vector3.new(0, rise, 0)
	end

	-- strokes: the main one with its ink edge, and two thin streaks beside it
	local strokes = {
		{ offset = 0, scale = 1, lead = 0, lag = 0, ink = true, colour = SLASH_CORE },
		{ offset = 0.75, scale = 0.12, lead = 0.04, lag = 0.25, colour = SLASH_GLOW },
		{ offset = -0.6, scale = 0.09, lead = -0.06, lag = 0.4, colour = SLASH_GLOW },
	}
	local parts = {}
	for _, stroke in strokes do
		stroke.core = {}
		stroke.edge = {}
		for i = 1, CUT_SEGMENTS do
			stroke.core[i] = piece(stroke.colour, true)
			table.insert(parts, stroke.core[i])
			if stroke.ink then
				stroke.edge[i] = piece(SLASH_INK, false)
				table.insert(parts, stroke.edge[i])
			end
		end
	end

	local born = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local u = (os.clock() - born) / CUT_LIFE
		local camera = Workspace.CurrentCamera
		if u >= 1 or not camera then
			conn:Disconnect()
			for _, p in parts do
				release(p)
			end
			return
		end
		local eye = camera.CFrame.Position
		-- the head is already a little way in when it appears, and slows as it lands
		local drawn = math.min(u / CUT_DRAW, 1)
		local head = 0.12 + 0.88 * (1 - (1 - drawn) ^ 3)
		local tail = math.max(0, (u - 0.12) / 0.88) ^ 2 * head
		local fade = if u < 0.6 then 0 else (u - 0.6) / 0.4
		local thin = 1 - 0.55 * u * u -- the remaining head thins as it goes
		local radius = radius0 * (0.96 + 0.08 * u)

		for _, stroke in strokes do
			local h = math.clamp(head + stroke.lead, 0, 1)
			local t = math.clamp(tail + stroke.lag * (head - tail), 0, h)
			local r = radius + stroke.offset * width0
			for i = 1, CUT_SEGMENTS do
				local v0 = math.max((i - 1) / CUT_SEGMENTS, t)
				local v1 = math.min(i / CUT_SEGMENTS, h)
				local core = stroke.core[i]
				local edge = stroke.edge[i]
				if v1 - v0 <= 1e-3 or h - t <= 1e-3 then
					core.Transparency = 1
					if edge then
						edge.Transparency = 1
					end
					continue
				end
				local p0, p1 = point(v0, r), point(v1, r)
				local mid = (p0 + p1) / 2
				local length = (p1 - p0).Magnitude + 0.06
				local s = ((v0 + v1) / 2 - t) / (h - t)
				local width = width0 * stroke.scale * strokeWidth(s) * thin
				local toEye = eye - mid
				local cf = CFrame.lookAt(mid, p1, toEye) -- width across the arc, face to the camera
				core.Size = Vector3.new(width, 0.05, length)
				core.CFrame = cf
				core.Color = SLASH_CORE:Lerp(stroke.colour, 1 - s) -- white at the head, blue to the tail
				core.Transparency = 0.05 + 0.95 * fade
				if edge then
					edge.Size = Vector3.new(width * 1.55 + 0.12, 0.05, length + 0.1)
					edge.CFrame = cf - toEye.Unit * 0.15 -- just behind the white, as seen
					edge.Transparency = 0.2 + 0.8 * fade
				end
			end
		end
	end)
end

function WeaponFxController:KnitInit()
	folder = Instance.new("Folder")
	folder.Name = "Fx"
	folder.Parent = Workspace
	self._projs = {}
	self.Effects = {}
end

function WeaponFxController:KnitStart()
	local state = Knit.GetController("StateController")
	local enemies = Knit.GetController("EnemyRenderController")
	self._state = state
	local Effects = self.Effects

	function Effects.Slash(index, x, y, z, dx, dz, range, arcDeg)
		-- The blade's own trail follows the arm; the crescent at the edge of the
		-- hit area is the cut and shows its reach. Both on the hero as this
		-- client sees them.
		if dx * dx + dz * dz < 1e-6 then
			return
		end
		local root = state:RootOfIndex(index)
		local at = if root then root.Position else Vector3.new(x, y, z)
		crescent(at, Vector3.new(dx, 0, dz).Unit, range, math.clamp(arcDeg, 20, 360))
		local trail = root and root.Parent and bladeTrail(root.Parent)
		if trail then
			trail:Clear()
			trail.Enabled = true
			local stamp = (trail:GetAttribute("Swing") or 0) + 1
			trail:SetAttribute("Swing", stamp)
			task.delay(TRAIL_ON, function()
				if trail.Parent and trail:GetAttribute("Swing") == stamp then
					trail.Enabled = false
				end
			end)
		end
	end

	function Effects.Frost(index, radius, seconds)
		local root = state:RootOfIndex(index)
		if not root then
			return
		end
		local pos = root.Position
		local at = Vector3.new(pos.X, state:HeightAt(pos.X, pos.Z) + 0.35, pos.Z)
		local life = math.max(seconds, 0.35)
		Vfx.ground(at, "ring", Color3.fromRGB(120, 230, 255), radius * 0.5, radius, life, { alpha = 0.1 })
		Vfx.ground(at, "ring_thin", Color3.fromRGB(220, 250, 255), radius * 0.2, radius * 0.8, life, { alpha = 0.2, spin = 40 })
		Vfx.ground(at, "glow", Color3.fromRGB(90, 200, 255), radius * 0.8, radius, life, { alpha = 0.7 })
		Vfx.burst("FrostSparkle", at + Vector3.new(0, 1, 0))
	end

	function Effects.Bolt(x, z, radius)
		local ground = state:HeightAt(x, z)
		local at = Vector3.new(x, ground + 0.4, z)
		Vfx.bolt(at + Vector3.new(math.random(-8, 8), 80, math.random(-8, 8)), at, Color3.fromRGB(255, 255, 255), 9, 0.13)
		Vfx.bolt(at + Vector3.new(math.random(-8, 8), 80, math.random(-8, 8)), at, Color3.fromRGB(150, 225, 255), 14, 0.1)
		Vfx.ground(at, "ring", Color3.fromRGB(200, 240, 255), radius * 0.3, radius, 0.28)
		Vfx.burst("LightningImpact", at + Vector3.new(0, 1.2, 0))
	end

	function Effects.Burst(x, _y, z, radius, style)
		local ground = state:HeightAt(x, z)
		local at = Vector3.new(x, ground + 2, z)
		local name, colour = "FireExplosion", Color3.fromRGB(255, 170, 60)
		if style == "night" then
			name, colour = "NightBurst", Color3.fromRGB(255, 245, 180)
		elseif style == "mirror" then
			name, colour = "MirrorBurst", Color3.fromRGB(190, 230, 255)
		elseif style == "rocket" then
			name, colour = "RocketExplosion", Color3.fromRGB(255, 140, 200)
		end
		Vfx.burst(name, at)
		Vfx.ground(Vector3.new(x, ground + 0.35, z), "ring", colour, radius * 0.25, radius, 0.32)
	end

	function Effects.Axe(_index, fromX, fromZ, toX, toZ, radius, duration)
		local fromY = state:HeightAt(fromX, fromZ) + 3
		local toY = state:HeightAt(toX, toZ) + 2.5
		local axe = model("WeaponAxe") or part(Vector3.new(0.5, 3.4, 2), Color3.fromRGB(190, 195, 205), CFrame.new(fromX, fromY, fromZ))
		axe.Size *= 1.5
		Vfx.attach("PaleTrail", axe)
		Vfx.ground(
			Vector3.new(toX, toY - 2.1, toZ),
			"ring_thin",
			Color3.fromRGB(215, 220, 230),
			radius,
			radius,
			duration + 0.35,
			{ alpha = 0.35, spin = 360 * duration, hold = 0.9 }
		)
		local born = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local age = os.clock() - born
			if age >= duration + 0.35 or not axe.Parent then
				conn:Disconnect()
				axe:Destroy()
				return
			end
			local travel = math.clamp(age / 0.35, 0, 1)
			local pos = Vector3.new(fromX, fromY, fromZ):Lerp(Vector3.new(toX, toY, toZ), travel)
				+ Vector3.new(0, math.sin(travel * math.pi) * 6, 0)
			if travel >= 1 then
				-- orbit the landing spot so the zone reads as occupied
				local a = age * 7
				pos = Vector3.new(toX + math.cos(a) * radius * 0.6, toY, toZ + math.sin(a) * radius * 0.6)
			end
			axe.CFrame = CFrame.new(pos) * CFrame.Angles(0, age * 18, math.rad(90))
		end)
	end

	function Effects.LevelUp(_level)
		for _, entry in state.roster.players do
			local root = state:RootOfIndex(entry.index)
			if root then
				local ground = state:HeightAt(root.Position.X, root.Position.Z)
				local at = Vector3.new(root.Position.X, ground + 0.35, root.Position.Z)
				Vfx.ground(at, "ring", Color3.fromRGB(255, 220, 70), 2, 12, 0.6)
				Vfx.ground(at, "ring_thin", Color3.fromRGB(255, 245, 170), 1, 16, 0.75, { alpha = 0.2 })
				Vfx.burst("LevelUpBurst", at + Vector3.new(0, 1.5, 0))
			end
		end
	end

	function Effects.Pickup(index, name)
		local root = state:RootOfIndex(index)
		if not root then
			return
		end
		if name == "Magnet" then
			Vfx.burst("MagnetPull", root.Position)
		elseif name == "Snack" then
			Vfx.burst("HealPlus", root.Position)
		elseif name == "Frenzy" then
			Vfx.burst("FrenzyFlare", root.Position)
			local aura = Vfx.attach("FrenzyAura", root)
			task.delay(GameConfig.FrenzySeconds, function()
				for _, e in aura do
					e:Destroy()
				end
			end)
		end
	end

	local fx = Net.client("Fx")
	if fx then
		fx.OnClientEvent:Connect(function(name, ...)
			local effect = Effects[name]
			if not effect then
				return
			end
			local ok, err = pcall(effect, ...)
			if not ok then
				warn(`[WeaponFx] {name} failed inert: {err}`)
			end
		end)
	end

	local telegraph = Net.client("Telegraph")
	if telegraph then
		telegraph.OnClientEvent:Connect(function(x, z, radius, delay, _kind, y)
			local ok, err = pcall(function()
				-- on the ground, or at the height it was aimed at (a hero up a tree)
				local floor = if typeof(y) == "number" then y else state:HeightAt(x, z)
				local at = Vector3.new(x, floor + 0.4, z)
				-- the rim shows where it lands, the fill grows to meet it as the hit arrives
				Vfx.ground(at, "ring", Color3.fromRGB(255, 50, 50), radius, radius, delay + 0.05, { alpha = 0.1, hold = 0.95 })
				Vfx.ground(at, "dot", Color3.fromRGB(255, 60, 60), 0.5, radius * 0.94, delay + 0.05, { alpha = 0.55, hold = 0.95 })
				task.delay(delay, function()
					Vfx.ground(at, "ring_thin", Color3.fromRGB(255, 200, 190), radius * 0.6, radius * 1.5, 0.3)
					Vfx.burst("RootBurst", at + Vector3.new(0, 1, 0))
				end)
			end)
			if not ok then
				warn(`[WeaponFx] telegraph failed inert: {err}`)
			end
		end)
	end

	local projs = self._projs
	local proj = Net.client("Proj")
	if proj then
		proj.OnClientEvent:Connect(function(op, id, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11)
			if op == "spawn" then
				local kind, owner, x, z, dx, dz, speed, extraA, _extraB, y, dy = a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11
				local look = PROJ_LOOK[kind]
				if not look then
					return
				end
				local p = (look.model and model(look.model))
					or part(look.size, look.colour, CFrame.new(x, y or state:HeightAt(x, z) + 3, z), 0, look.neon)
				if look.shape and p:IsA("Part") then
					p.Shape = look.shape
				end
				if look.trail then
					Vfx.attach(look.trail, p)
				end
				projs[id] = {
					part = p,
					kind = kind,
					owner = owner,
					x = x,
					y = typeof(y) == "number" and y or nil, -- a shot at its own height, not following the ground
					z = z,
					dx = dx,
					dy = typeof(dy) == "number" and dy or 0,
					dz = dz,
					speed = speed,
					target = extraA,
					spin = look.spin,
					age = 0,
				}
			elseif op == "turn" then
				local p = projs[id]
				if p then
					p.x, p.z, p.dx, p.dz = a1, a2, a3, a4
					if a5 == -1 then
						p.back = true
					else
						p.target = a5
					end
				end
			elseif op == "end" then
				local p = projs[id]
				if p then
					projs[id] = nil
					p.part:Destroy()
				end
				local x, z, boom, y = a1, a2, a3, a4
				if boom and boom > 0 and typeof(y) == "number" then
					-- burst where it really went off, ring on the ground only if that is near
					pcall(function()
						local ground = state:HeightAt(x, z)
						Vfx.burst("FireExplosion", Vector3.new(x, math.max(y, ground + 2), z))
						if y - ground < boom then
							Vfx.ground(Vector3.new(x, ground + 0.35, z), "ring", Color3.fromRGB(255, 170, 60), boom * 0.25, boom, 0.32)
						end
					end)
				elseif boom and boom > 0 then
					pcall(Effects.Burst, x, 0, z, boom, if p and p.kind == P_ROCKET then "rocket" else "fire")
				end
			end
		end)
	end

	RunService.RenderStepped:Connect(function(dt)
		if state.paused then
			return -- the server is not moving them either
		end
		for id, p in projs do
			p.age += dt
			if p.age > 8 or not p.part.Parent then
				p.part:Destroy()
				projs[id] = nil
				continue
			end
			-- chase what the server said it is chasing, so the visual lands where the hit does
			local goal: Vector3? = nil
			if p.back then
				local root = state:RootOfIndex(p.owner)
				goal = root and root.Position
			elseif (p.kind == P_ROCKET or p.kind == P_BONE) and p.target and p.target > 0 then
				goal = enemies:PosOf(p.target)
			end
			if goal then
				local vx, vz = goal.X - p.x, goal.Z - p.z
				local m = math.sqrt(vx * vx + vz * vz)
				if m > 0.05 then
					local turn = if p.kind == P_ROCKET then math.min(1, 6 * dt) else 1
					local nx, nz = p.dx + (vx / m - p.dx) * turn, p.dz + (vz / m - p.dz) * turn
					local nm = math.max(math.sqrt(nx * nx + nz * nz), 0.05)
					p.dx, p.dz = nx / nm, nz / nm
				end
			end
			p.x += p.dx * p.speed * dt
			p.z += p.dz * p.speed * dt
			local pos, dir
			if p.y then
				p.y += p.dy * p.speed * dt
				pos, dir = Vector3.new(p.x, p.y, p.z), Vector3.new(p.dx, p.dy, p.dz)
			else
				pos, dir = Vector3.new(p.x, state:HeightAt(p.x, p.z) + 3, p.z), Vector3.new(p.dx, 0, p.dz)
			end
			local cf = CFrame.lookAt(pos, pos + dir)
			if p.spin then
				cf *= CFrame.Angles(0, 0, p.age * p.spin)
			end
			p.part.CFrame = cf
		end
	end)

	-- slow red embers drifting through the forest, carried along with the camera
	local embers = Vfx.place("Embers", CFrame.new(0, 20, 0), 110, folder)
	task.spawn(function()
		while embers.Parent do
			local camera = Workspace.CurrentCamera
			if camera then
				embers.CFrame = CFrame.new(camera.CFrame.Position)
			end
			task.wait(0.5)
		end
	end)

	state.Changed:Connect(function(key)
		if key == "phase" and state.phase == "Lobby" then
			for id, p in projs do
				p.part:Destroy()
				projs[id] = nil
			end
		end
	end)
end

return WeaponFxController

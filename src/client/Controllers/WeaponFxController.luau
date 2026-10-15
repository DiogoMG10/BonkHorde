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

local SLASH_FILL = Color3.fromRGB(150, 210, 255)
local SLASH_EDGE = Color3.fromRGB(235, 250, 255)
local SLASH_SWEEP = 0.1 -- seconds for the cut to cross the arc
local SLASH_LIFE = 0.32 -- seconds until the last of it is gone
local SLASH_LIFT = 0.3 -- studs above the ground, so it never sinks into a slope

local function wedge(colour: Color3): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = false
	w.Material = Enum.Material.Neon
	w.Color = colour
	w.Transparency = 1
	w.Parent = folder
	return w
end

-- A flat triangle a, b, c out of two wedges (each wedge is a right triangle).
local function triangle(a: Vector3, b: Vector3, c: Vector3, colour: Color3): { WedgePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- a must sit opposite the longest side
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local w1, w2 = wedge(colour), wedge(colour)
	w1.Size = Vector3.new(0.05, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(0.05, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	return { w1, w2 }
end

-- The swing's whole area as slices of a fan, plus a bright rim along the
-- outer edge. Slice 1 is the hero's right; each lights up as the cut passes
-- it and then fades, so the fan reads as one sweep from right to left.
local function slash(at: Vector3, forward: Vector3, range: number, arcDeg: number)
	local state = Knit.GetController("StateController")
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local half = math.rad(arcDeg) / 2
	local count = math.max(3, math.ceil(arcDeg / 12))
	local function point(angle: number, radius: number): Vector3
		local flat = at + (forward * math.cos(angle) + right * math.sin(angle)) * radius
		return Vector3.new(flat.X, state:HeightAt(flat.X, flat.Z) + SLASH_LIFT, flat.Z)
	end
	local centre = point(0, 0)
	local slices = {}
	for i = 1, count do
		local a0 = half - (i - 1) / count * 2 * half
		local a1 = half - i / count * 2 * half
		local p0, p1 = point(a0, range), point(a1, range)
		local rim = Instance.new("Part")
		rim.Anchored, rim.CanCollide, rim.CanQuery, rim.CanTouch = true, false, false, false
		rim.CastShadow = false
		rim.Material = Enum.Material.Neon
		rim.Color = SLASH_EDGE
		rim.Transparency = 1
		rim.Size = Vector3.new(0.45, 0.12, (p1 - p0).Magnitude + 0.2)
		rim.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
		rim.Parent = folder
		table.insert(slices, { fill = triangle(centre, p0, p1, SLASH_FILL), rim = rim, at = (i - 1) / count * SLASH_SWEEP })
	end
	local born = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local age = os.clock() - born
		local done = age >= SLASH_LIFE
		for _, slice in slices do
			local t = (age - slice.at) / (SLASH_LIFE - slice.at)
			local shown = if done or t < 0 then 0 else (1 - t) ^ 1.5
			for _, w in slice.fill do
				w.Transparency = 1 - 0.38 * shown
			end
			slice.rim.Transparency = 1 - 0.9 * shown
		end
		if done then
			conn:Disconnect()
			for _, slice in slices do
				slice.rim:Destroy()
				for _, w in slice.fill do
					w:Destroy()
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

	function Effects.Slash(index, x, _y, z, dx, dz, range, arcDeg)
		-- Drawn from the hit test itself (CombatService Fire.Arc): a sector of
		-- radius `range` and width `arcDeg` around the swing direction, so what
		-- is seen is where the swing hits. Centred on the hero as this client
		-- sees them, and swept right to left like the animation's cut.
		local root = state:RootOfIndex(index)
		if root then
			x, z = root.Position.X, root.Position.Z
		end
		if dx * dx + dz * dz < 1e-6 then
			return
		end
		slash(Vector3.new(x, 0, z), Vector3.new(dx, 0, dz).Unit, range, math.clamp(arcDeg, 20, 360))
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
		telegraph.OnClientEvent:Connect(function(x, z, radius, delay, _kind)
			local ok, err = pcall(function()
				local ground = state:HeightAt(x, z)
				local at = Vector3.new(x, ground + 0.4, z)
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

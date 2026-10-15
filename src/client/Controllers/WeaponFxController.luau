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

	function Effects.Slash(_index, x, y, z, dx, dz, range, arcDeg)
		-- a crescent swoosh swept across the arc in front of the hero
		local yaw = math.atan2(-dx, -dz)
		local sweep = math.clamp(arcDeg, 60, 200)
		local at = Vector3.new(x, y + 0.6, z)
		-- The crescent texture's body sits clockwise of its top edge, and the
		-- swoosh is seen mostly near the end of its spin; this start angle puts
		-- what is on screen across the swing direction. (+45 drew it well left.)
		local turn = yaw + math.rad(sweep / 2 - 45)
		Vfx.ground(
			at,
			"crescent",
			Color3.fromRGB(215, 240, 255),
			range * 0.75,
			range * 1.08,
			0.2,
			{ yaw = turn, spin = sweep, hold = 0.5, alpha = 0.15 }
		)
		Vfx.ground(
			at - Vector3.new(0, 0.15, 0),
			"crescent",
			Color3.fromRGB(120, 190, 255),
			range * 0.7,
			range * 1.15,
			0.26,
			{ yaw = turn, spin = sweep * 0.8, alpha = 0.45, hold = 0.3 }
		)
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
		proj.OnClientEvent:Connect(function(op, id, a1, a2, a3, a4, a5, a6, a7, a8, a9)
			if op == "spawn" then
				local kind, owner, x, z, dx, dz, speed, extraA, _extraB = a1, a2, a3, a4, a5, a6, a7, a8, a9
				local look = PROJ_LOOK[kind]
				if not look then
					return
				end
				local p = (look.model and model(look.model))
					or part(look.size, look.colour, CFrame.new(x, state:HeightAt(x, z) + 3, z), 0, look.neon)
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
					z = z,
					dx = dx,
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
				local x, z, boom = a1, a2, a3
				if boom and boom > 0 then
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
			local pos = Vector3.new(p.x, state:HeightAt(p.x, p.z) + 3, p.z)
			local cf = CFrame.lookAt(pos, pos + Vector3.new(p.dx, 0, p.dz))
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

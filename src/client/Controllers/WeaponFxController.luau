--!nonstrict
-- WeaponFxController - owns weapon, projectile and telegraph visuals, replayed
-- from server events.
--
-- Standing rule: cosmetics can never break gameplay. Every effect here is
-- pcall-isolated and built from plain parts, so a failed effect is one missing
-- flash and never a dead client. The VFX stage swaps these shapes for real
-- effects by replacing entries in the `Effects` table.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)

local WeaponFxController = Knit.CreateController({ Name = "WeaponFxController" })

local P_FIREBALL, P_BONE, P_NANA, P_ROCKET, P_THORN = 1, 2, 3, 4, 5
local PROJ_LOOK = {
	[P_FIREBALL] = { colour = Color3.fromRGB(255, 130, 30), size = Vector3.new(2.2, 2.2, 2.2), shape = Enum.PartType.Ball, neon = true },
	[P_BONE] = { colour = Color3.fromRGB(240, 235, 215), size = Vector3.new(0.7, 2.6, 0.7), spin = 14 },
	[P_NANA] = { colour = Color3.fromRGB(255, 220, 50), size = Vector3.new(0.9, 3.4, 0.9), spin = 18 },
	[P_ROCKET] = { colour = Color3.fromRGB(255, 90, 170), size = Vector3.new(0.9, 0.9, 2.6), neon = true },
	[P_THORN] = { colour = Color3.fromRGB(40, 110, 40), size = Vector3.new(0.6, 0.6, 3), neon = false },
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

local function fade(p: BasePart, seconds: number, goal: { [string]: any }?)
	local props = goal or {}
	props.Transparency = 1
	TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
	Debris:AddItem(p, seconds + 0.05)
end

-- a flat disc on the ground
local function disc(x: number, y: number, z: number, radius: number, colour: Color3, transparency: number): Part
	local p = part(
		Vector3.new(0.3, radius * 2, radius * 2),
		colour,
		CFrame.new(x, y + 0.4, z) * CFrame.Angles(0, 0, math.rad(90)),
		transparency,
		true
	)
	p.Shape = Enum.PartType.Cylinder
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
		-- a thin wedge-ish slab swept in front of the hero
		local width = 2 * range * math.sin(math.rad(arcDeg / 2))
		local centre = Vector3.new(x + dx * range * 0.55, y, z + dz * range * 0.55)
		local cf = CFrame.lookAt(centre, centre + Vector3.new(dx, 0, dz))
		local p = part(Vector3.new(width, 0.35, range * 0.9), Color3.fromRGB(210, 235, 255), cf, 0.25, true)
		fade(p, 0.18, { Size = Vector3.new(width * 1.15, 0.2, range) })
	end

	function Effects.Frost(index, radius, seconds)
		local root = state:RootOfIndex(index)
		if not root then
			return
		end
		local pos = root.Position
		local ground = state:HeightAt(pos.X, pos.Z)
		local p = disc(pos.X, ground, pos.Z, radius * 0.6, Color3.fromRGB(120, 225, 255), 0.45)
		fade(p, math.max(seconds, 0.3), { Size = Vector3.new(0.3, radius * 2, radius * 2) })
	end

	function Effects.Bolt(x, z, radius)
		local ground = state:HeightAt(x, z)
		local bolt = part(
			Vector3.new(0.9, 70, 0.9),
			Color3.fromRGB(255, 255, 255),
			CFrame.new(x, ground + 35, z) * CFrame.Angles(0, 0, math.rad(math.random(-6, 6))),
			0,
			true
		)
		fade(bolt, 0.14)
		local ring = disc(x, ground, z, radius, Color3.fromRGB(200, 230, 255), 0.4)
		fade(ring, 0.25)
	end

	function Effects.Burst(x, _y, z, radius, style)
		local ground = state:HeightAt(x, z)
		local colour = if style == "night"
			then Color3.fromRGB(255, 245, 180)
			elseif style == "mirror" then Color3.fromRGB(190, 230, 255)
			else Color3.fromRGB(255, 150, 40)
		local p = part(Vector3.new(2, 2, 2), colour, CFrame.new(x, ground + 2, z), 0.35, true)
		p.Shape = Enum.PartType.Ball
		fade(p, 0.3, { Size = Vector3.new(radius * 2, radius * 2, radius * 2) })
	end

	function Effects.Axe(_index, fromX, fromZ, toX, toZ, radius, duration)
		local fromY = state:HeightAt(fromX, fromZ) + 3
		local toY = state:HeightAt(toX, toZ) + 2.5
		local axe = part(Vector3.new(0.5, 3.4, 2), Color3.fromRGB(190, 195, 205), CFrame.new(fromX, fromY, fromZ))
		local ring = disc(toX, toY - 2.5, toZ, radius, Color3.fromRGB(200, 205, 215), 0.78)
		local born = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local age = os.clock() - born
			if age >= duration + 0.35 or not axe.Parent then
				conn:Disconnect()
				axe:Destroy()
				ring:Destroy()
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
			axe.CFrame = CFrame.new(pos) * CFrame.Angles(age * 16, 0, 0)
		end)
	end

	function Effects.LevelUp(_level)
		for _, entry in state.roster.players do
			local root = state:RootOfIndex(entry.index)
			if root then
				local ground = state:HeightAt(root.Position.X, root.Position.Z)
				local ring = disc(root.Position.X, ground, root.Position.Z, 3, Color3.fromRGB(255, 220, 70), 0.3)
				fade(ring, 0.6, { Size = Vector3.new(0.3, 22, 22) })
			end
		end
	end

	function Effects.Pickup(_index, _name) end -- the HUD announces powerups; nothing in the world yet

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
				local outer = disc(x, ground, z, radius, Color3.fromRGB(255, 40, 40), 0.75)
				local inner = disc(x, ground + 0.1, z, 0.5, Color3.fromRGB(255, 60, 60), 0.45)
				TweenService
					:Create(inner, TweenInfo.new(delay, Enum.EasingStyle.Linear), { Size = Vector3.new(0.3, radius * 2, radius * 2) })
					:Play()
				task.delay(delay, function()
					outer:Destroy()
					inner.Transparency = 0.1
					fade(inner, 0.25)
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
				local p = part(look.size, look.colour, CFrame.new(x, state:HeightAt(x, z) + 3, z), 0, look.neon)
				if look.shape then
					p.Shape = look.shape
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
					pcall(Effects.Burst, x, 0, z, boom, "fire")
				end
			end
		end)
	end

	RunService.RenderStepped:Connect(function(dt)
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

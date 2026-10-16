--!nonstrict
-- PickupRenderController - owns gem, coin and powerup visuals and their
-- flight to the hero.
--
-- The server says what dropped where and who took it; it has already counted
-- the XP and the gold. Here a taken pickup is seen to go to its hero: it hops
-- up and away for an instant, then homes in with ever-growing speed (it
-- outruns a hero at full bunny-hop speed within half a second), and twinkles
-- and chimes as it arrives. A magnet or vacuum shrine sweeps nearest first,
-- so the whole map's gems and coins stream in as a converging wave. No number
-- is drawn for it: the XP bar says what it was worth. Gems and coins near the
-- camera bob and turn while they wait. Parts are pooled and every frame's moves go out in one
-- BulkMoveTo. A visual comes from ReplicatedStorage.Assets.Pickups.<Kind> when
-- it exists and is a simple shape otherwise.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Vfx = require(script.Parent.Parent.Vfx)

local PickupRenderController = Knit.CreateController({ Name = "PickupRenderController" })

local LOOK = {
	XPGem = { colour = Color3.fromRGB(60, 150, 255), size = Vector3.new(0.9, 1.7, 0.9), material = Enum.Material.Neon },
	GoldCoin = { colour = Color3.fromRGB(255, 205, 50), size = Vector3.new(0.35, 1.5, 1.5), shape = Enum.PartType.Cylinder },
	PowerupMagnet = {
		colour = Color3.fromRGB(230, 50, 50),
		size = Vector3.new(2.2, 2.2, 2.2),
		shape = Enum.PartType.Ball,
		label = "MAGNET",
	},
	PowerupSnack = { colour = Color3.fromRGB(220, 160, 90), size = Vector3.new(2.2, 2.2, 2.2), shape = Enum.PartType.Ball, label = "SNACK" },
	PowerupFrenzy = {
		colour = Color3.fromRGB(255, 110, 30),
		size = Vector3.new(2.2, 2.2, 2.2),
		shape = Enum.PartType.Ball,
		label = "FRENZY",
	},
}

local GOLD = Color3.fromRGB(255, 214, 90)
local IDLE_RANGE = 140 -- gems and coins this close to the camera bob and turn
local ARRIVE = 2.2 -- studs from the hero's chest that count as arrived

function PickupRenderController:KnitInit()
	self._items = {} -- id -> { part, kind, value, at (resting CFrame), phase }
	self._pool = {} -- kind -> { part }
	self._flying = {}
	self._moveParts = {}
	self._moveFrames = {}
	local folder = Instance.new("Folder")
	folder.Name = "Pickups"
	folder.Parent = Workspace
	self._folder = folder
	self._streak = 0
	self._streakAt = 0
	self._sparkAt = 0
end

function PickupRenderController:_make(kind: string): BasePart
	local list = self._pool[kind]
	local part = list and table.remove(list)
	if part then
		return part
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assets:FindFirstChild("Pickups") and assets.Pickups:FindFirstChild(kind)
	local mesh = source and (if source:IsA("BasePart") then source else source:FindFirstChild("Body"))
	if mesh and mesh:IsA("BasePart") then
		part = mesh:Clone()
	else
		local look = LOOK[kind]
		part = Instance.new("Part")
		part.Size = look.size
		part.Color = look.colour
		part.Material = look.material or Enum.Material.SmoothPlastic
		if look.shape then
			part.Shape = look.shape
		end
		if look.label then
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(120, 30)
			gui.StudsOffset = Vector3.new(0, 2.4, 0)
			gui.AlwaysOnTop = true
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Font = Enum.Font.LuckiestGuy
			text.TextSize = 20
			text.TextColor3 = Color3.new(1, 1, 1)
			text.TextStrokeTransparency = 0
			text.Text = look.label
			text.Parent = gui
			gui.Parent = part
		end
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part:SetAttribute("BaseSize", part.Size)
	part.Parent = self._folder
	return part
end

function PickupRenderController:_free(kind: string, part: BasePart)
	part.CFrame = CFrame.new(0, -500, 0)
	local list = self._pool[kind]
	if not list then
		list = {}
		self._pool[kind] = list
	end
	table.insert(list, part)
end

function PickupRenderController:_clear()
	for id, item in self._items do
		self:_free(item.kind, item.part)
		self._items[id] = nil
	end
	for i = #self._flying, 1, -1 do
		local f = self._flying[i]
		self:_free(f.kind, f.part)
		self._flying[i] = nil
	end
end

-- a pickup reached its hero: for the local hero, a twinkle, a chime that
-- climbs in pitch through a run of them
function PickupRenderController:_arrived(f, at: Vector3)
	if f.index ~= self._state:MyIndex() then
		return
	end
	local now = os.clock()
	if now - self._sparkAt > 0.06 then
		self._sparkAt = now
		pcall(Vfx.burst, "GemCollect", at, if f.kind == "GoldCoin" then { tint = GOLD } else nil)
	end
	if f.kind == "XPGem" then
		self._streak = if now - self._streakAt < 0.5 then math.min(self._streak + 1, 14) else 0
		self._streakAt = now
		self._audio:Play("xp_pickup", nil, 1 + self._streak * 0.045)
	elseif f.kind == "GoldCoin" then
		self._audio:Play("coin_pickup", 0.08)
	end
end

function PickupRenderController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._audio = Knit.GetController("AudioController")
	local half = GameConfig.MapSizeStuds / 2
	local function restore(q: number): number
		return q / 65535 * (2 * half) - half
	end

	local spawn = Net.client("PickupSpawn")
	if spawn then
		spawn.OnClientEvent:Connect(function(b: buffer)
			for i = 0, buffer.len(b) / 8 - 1 do
				local o = i * 8
				local id = buffer.readu16(b, o)
				local kind = Roster.PickupOrder[buffer.readu8(b, o + 2)]
				local value = buffer.readu8(b, o + 3)
				local x, z = restore(buffer.readu16(b, o + 4)), restore(buffer.readu16(b, o + 6))
				local old = self._items[id]
				if old then
					self:_free(old.kind, old.part)
				end
				if kind then
					local part = self:_make(kind)
					local base = part:GetAttribute("BaseSize")
					if kind == "XPGem" then
						part.Size = base * (if value >= 20 then 2.2 elseif value >= 5 then 1.5 else 1)
					else
						part.Size = base
					end
					local y = self._state:HeightAt(x, z) + 1.6
					local at = CFrame.new(x, y, z) * CFrame.Angles(0, (id % 12) * 0.5, if kind == "GoldCoin" then 0 else math.rad(8))
					part.CFrame = at
					self._items[id] = { part = part, kind = kind, value = value, at = at, phase = (id % 17) * 0.37 }
				end
			end
		end)
	end

	local taken = Net.client("PickupTaken")
	if taken then
		taken.OnClientEvent:Connect(function(b: buffer)
			for i = 0, buffer.len(b) / 3 - 1 do
				local id = buffer.readu16(b, i * 3)
				local index = buffer.readu8(b, i * 3 + 2)
				local item = self._items[id]
				if item then
					self._items[id] = nil
					local pos = item.part.Position
					local root = self._state:RootOfIndex(index)
					-- a little hop up and away from the hero before the pull takes it
					local away = if root then (pos - root.Position) * Vector3.new(1, 0, 1) else Vector3.zero
					away = if away.Magnitude > 0.1 then away.Unit else Vector3.zero
					table.insert(self._flying, {
						part = item.part,
						kind = item.kind,
						value = item.value,
						index = index,
						pos = pos,
						vel = away * 9 + Vector3.new(0, 11, 0),
						t = 0,
						spin = (id % 7) * 0.9,
					})
				end
			end
		end)
	end

	self._state.Changed:Connect(function(key)
		if key == "phase" and self._state.phase == "Lobby" then
			self:_clear()
		end
	end)

	local roots = {}
	RunService.RenderStepped:Connect(function(dt)
		dt = math.min(dt, 0.05)
		local parts, frames = self._moveParts, self._moveFrames
		table.clear(parts)
		table.clear(frames)
		table.clear(roots)
		for _, entry in self._state.roster.players do
			roots[entry.index] = self._state:RootOfIndex(entry.index)
		end

		-- flights home
		local flying = self._flying
		for i = #flying, 1, -1 do
			local f = flying[i]
			f.t += dt
			local root = roots[f.index]
			if not root or f.t > 4 then
				self:_free(f.kind, f.part)
				table.remove(flying, i)
				continue
			end
			local target = root.Position + Vector3.new(0, 0.6, 0)
			local to = target - f.pos
			local dist = to.Magnitude
			if dist < ARRIVE then
				self:_arrived(f, target)
				self:_free(f.kind, f.part)
				table.remove(flying, i)
				continue
			end
			-- homing with a speed that keeps growing: a gentle start, a fast finish
			local speed = 18 + 240 * f.t ^ 1.4
			local want = to / dist * speed
			f.vel = f.vel:Lerp(want, math.min(1, dt * (3 + 14 * f.t)))
			local step = f.vel * dt
			if step.Magnitude >= dist then
				f.pos = target
			else
				f.pos += step
			end
			f.spin += dt * 9
			table.insert(parts, f.part)
			table.insert(frames, CFrame.new(f.pos) * CFrame.Angles(0, f.spin, if f.kind == "GoldCoin" then 0 else 0.3))
		end

		-- the ones still waiting near the camera bob and turn
		local camera = Workspace.CurrentCamera
		if camera then
			local c = camera.CFrame.Position
			local clock = os.clock()
			for _, item in self._items do
				local p = item.at.Position
				local dx, dz = p.X - c.X, p.Z - c.Z
				if dx * dx + dz * dz < IDLE_RANGE * IDLE_RANGE then
					local ph = item.phase + clock
					table.insert(parts, item.part)
					table.insert(frames, item.at * CFrame.new(0, math.sin(ph * 2.2) * 0.25, 0) * CFrame.Angles(0, ph * 1.6, 0))
				end
			end
		end

		if #parts > 0 then
			Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return PickupRenderController

--!nonstrict
-- PickupRenderController - owns gem, coin and powerup visuals and their
-- fly-to-hero animation.
--
-- The server says what dropped where and who took it. A visual comes from
-- ReplicatedStorage.Assets.Pickups.<Kind> when it exists and is a simple shape
-- otherwise.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)

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

function PickupRenderController:KnitInit()
	self._items = {} -- id -> { part, kind }
	self._pool = {} -- kind -> { part }
	self._flying = {}
	local folder = Instance.new("Folder")
	folder.Name = "Pickups"
	folder.Parent = Workspace
	self._folder = folder
end

function PickupRenderController:_make(kind: string): BasePart
	local list = self._pool[kind]
	local part = list and table.remove(list)
	if part then
		return part
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assets:FindFirstChild("Pickups") and assets.Pickups:FindFirstChild(kind)
	if source and source:IsA("BasePart") then
		part = source:Clone()
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

function PickupRenderController:KnitStart()
	self._state = Knit.GetController("StateController")
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
					part.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, (id % 12) * 0.5, if kind == "GoldCoin" then 0 else math.rad(8))
					self._items[id] = { part = part, kind = kind }
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
					table.insert(self._flying, { part = item.part, kind = item.kind, index = index, from = item.part.Position, t = 0 })
				end
			end
		end)
	end

	self._state.Changed:Connect(function(key)
		if key == "phase" and self._state.phase == "Lobby" then
			self:_clear()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local flying = self._flying
		for i = #flying, 1, -1 do
			local f = flying[i]
			f.t += dt / 0.22
			local root = self._state:RootOfIndex(f.index)
			if f.t >= 1 or not root then
				self:_free(f.kind, f.part)
				table.remove(flying, i)
			else
				-- ease in so it lingers a moment, then snaps to the hero
				local a = f.t * f.t
				f.part.Position = f.from:Lerp(root.Position, a) + Vector3.new(0, math.sin(f.t * math.pi) * 2, 0)
			end
		end
	end)
end

return PickupRenderController

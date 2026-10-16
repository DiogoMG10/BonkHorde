--!nonstrict
-- CanopyController - keeps the forest's foliage out of the way of the fight.
--
-- Crowns and boughs never collide and are never hit by the camera's ray, so
-- in a wood a crown can sit between the camera and the hero. Here any foliage
-- part whose bounds cross the line from the camera to the hero fades to a
-- ghost while it is in the way, and comes back once it is not. Foliage is
-- recognised by its material and shape (Core/Blueprints: LeafyGrass, and
-- Grass on rounded or wedge parts; moss bands are Grass cylinders and blocks),
-- and kept in a coarse grid as it streams in. Purely local and cosmetic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local CanopyController = Knit.CreateController({ Name = "CanopyController" })

local CELL = 32
local GHOST = 0.72 -- how far a crown in the way fades
local FADE_RATE = 6 -- per second, in and out
local CHECK_EVERY = 1 / 20

local function isFoliage(d: Instance): boolean
	if not d:IsA("BasePart") then
		return false
	end
	local m = d.Material
	if m == Enum.Material.LeafyGrass then
		return true
	end
	if m ~= Enum.Material.Grass then
		return false
	end
	if d:IsA("WedgePart") then
		return true
	end
	return d:IsA("Part") and (d.Shape == Enum.PartType.Ball or d:FindFirstChildOfClass("SpecialMesh") ~= nil)
end

function CanopyController:KnitInit()
	self._cells = {} -- cell key -> { [part] = radius }
	self._where = {} -- part -> cell key
	self._fading = {} -- part -> current fade (0 clear .. GHOST)
	self._maxRadius = 8
end

local function key(x: number, z: number): number
	return math.floor(x / CELL) * 4096 + math.floor(z / CELL)
end

function CanopyController:_add(part: BasePart)
	if self._where[part] or not isFoliage(part) then
		return
	end
	local radius = part.Size.Magnitude / 2
	self._maxRadius = math.max(self._maxRadius, radius)
	local k = key(part.Position.X, part.Position.Z)
	local cell = self._cells[k]
	if not cell then
		cell = {}
		self._cells[k] = cell
	end
	cell[part] = radius
	self._where[part] = k
end

function CanopyController:_remove(part: Instance)
	local k = self._where[part]
	if k then
		self._where[part] = nil
		local cell = self._cells[k]
		if cell then
			cell[part] = nil
		end
		self._fading[part] = nil
	end
end

function CanopyController:_watch(map: Instance)
	for _, d in map:GetDescendants() do
		self:_add(d)
	end
	map.DescendantAdded:Connect(function(d)
		-- a mesh child arrives after its part: look at the part again then
		self:_add(if d:IsA("SpecialMesh") and d.Parent then d.Parent else d)
	end)
	map.DescendantRemoving:Connect(function(d)
		self:_remove(d)
	end)
end

function CanopyController:KnitStart()
	local state = Knit.GetController("StateController")
	local map = Workspace:FindFirstChild("Map")
	if map then
		self:_watch(map)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Map" then
			self:_watch(child)
		end
	end)

	local inWay = {} -- parts in the way at the last check
	local since = 0
	RunService.RenderStepped:Connect(function(dt)
		since += dt
		local camera = Workspace.CurrentCamera
		local root = state:Root()
		if since >= CHECK_EVERY then
			since = 0
			table.clear(inWay)
			if camera and root and state.phase ~= "Lobby" then
				local a = camera.CFrame.Position
				local b = root.Position + Vector3.new(0, 2, 0)
				local ab = b - a
				local len2 = ab:Dot(ab)
				local reach = self._maxRadius
				local x0, x1 = math.min(a.X, b.X) - reach, math.max(a.X, b.X) + reach
				local z0, z1 = math.min(a.Z, b.Z) - reach, math.max(a.Z, b.Z) + reach
				for cx = math.floor(x0 / CELL), math.floor(x1 / CELL) do
					for cz = math.floor(z0 / CELL), math.floor(z1 / CELL) do
						local cell = self._cells[cx * 4096 + cz]
						if cell then
							for part, radius in cell do
								local p = part.Position
								local t = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
								-- a crown's bounds are generous: fade when the line passes
								-- through the inner part of them
								if (a + ab * t - p).Magnitude < radius * 0.75 then
									inWay[part] = true
									if not self._fading[part] then
										self._fading[part] = 0
									end
								end
							end
						end
					end
				end
			end
		end
		for part, fade in self._fading do
			local target = if inWay[part] then GHOST else 0
			local nextFade = if fade < target then math.min(target, fade + FADE_RATE * dt) else math.max(target, fade - FADE_RATE * dt)
			part.LocalTransparencyModifier = nextFade
			if nextFade <= 0 and target == 0 then
				self._fading[part] = nil
			else
				self._fading[part] = nextFade
			end
		end
	end)
end

return CanopyController

--!nonstrict
-- ArtController - draws the Wardwood's Blender art kit (M3.B) on this client.
--
-- The server bakes each kit model once into ReplicatedStorage.WardwoodArt and
-- keeps only the colliders of what the kit dresses (server Wardwood/Builder).
-- This client rebuilds the same world (Core/World is deterministic), so it
-- knows every prop whether or not the map has streamed in, and draws each one
-- from the shared templates (Core/ArtPlan picks the model):
--
--   trees and bushes  full detail near the camera, a far version ("_LOD") in
--                     the middle distance, a horizon version ("_FAR") beyond
--                     (Config/Wardwood.ArtLod, with slack so nothing flickers);
--                     copies are pooled and reused, never rebuilt
--   every plant       a small fixed shift of its foliage colour (ArtPlan.tint)
--   short 3D grass    grown only around the hero, a patch per grid
--                     cell of grassy ground (Config/Wardwood.ArtGrass); the
--                     terrain's own grass carpet carries the distance
--
-- Purely visual and local: the server never sees any of it. `BonkArt` off (the
-- `art off` dev command) or a family listed in `BonkArtClassic` leaves the old
-- props showing instead.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ArtPlan = require(ReplicatedStorage.Shared.Core.ArtPlan)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Wardwood = require(ReplicatedStorage.Shared.Config.Wardwood)
local World = require(ReplicatedStorage.Shared.Core.World)

local ArtController = Knit.CreateController({ Name = "ArtController" })

local LOD = Wardwood.ArtLod
local GRASS = Wardwood.ArtGrass
local TREE_EVERY = 0.2 -- seconds between detail checks
local GRASS_EVERY = 0.1
local SWAPS_PER_TICK = 60
local GRASS_PER_TICK = 90
local SUFFIX = { [0] = "", [1] = "_LOD", [2] = "_FAR" }
local GRASS_TONE = { bladesDark = 0.76, bladesMid = 1, bladesLight = 1.13 }
-- the outer ring of the grass grows shorter, so its edge melts into the
-- terrain's carpet instead of drawing a circle round the hero
local GRASS_EDGE = 12
local EDGE_SCALE = 0.5

function ArtController:KnitInit()
	self._items = {}
	self._pools = {} -- template name -> { free models }
	self._grassActive = {} -- cell key -> model | false
	self._grassEdge = {} -- cell key -> in the shorter outer ring
	self._classic = {}
	self._on = false
end

function ArtController:KnitStart()
	task.defer(function()
		local templates = ReplicatedStorage:WaitForChild("WardwoodArt", 120)
		if not templates then
			warn("[ArtController] no art templates arrived; the old props stay")
			return
		end
		self._templates = templates
		self._world = World.build(GameConfig)
		self._field = ArtPlan.grassField(self._world)
		for _, prop in self._world.props do
			local asset = ArtPlan.asset(prop)
			if asset then
				local r, g, b = ArtPlan.tint(prop)
				table.insert(self._items, {
					prop = prop,
					asset = asset,
					lod = ArtPlan.hasLod(prop),
					x = prop.x,
					z = prop.z,
					cf = CFrame.new(prop.x, ArtPlan.footY(self._world, prop), prop.z) * CFrame.Angles(0, prop.yaw, 0),
					scale = prop.scale,
					tint = { r, g, b },
					level = nil,
					name = nil,
					model = nil,
				})
			end
		end
		self:_readClassic()
		Workspace:GetAttributeChangedSignal("BonkArtClassic"):Connect(function()
			self:_readClassic()
		end)
		Workspace:GetAttributeChangedSignal("BonkArt"):Connect(function()
			self:_setOn(Workspace:GetAttribute("BonkArt") == true)
		end)
		Workspace:GetAttributeChangedSignal("BonkGrassColor"):Connect(function()
			for _, model in self._grassActive do
				if model then
					self:_tintGrass(model)
				end
			end
		end)
		-- a template arriving later may be the better version for some plants
		templates.ChildAdded:Connect(function()
			self._dirty = true
		end)
		self:_setOn(Workspace:GetAttribute("BonkArt") == true)

		local treeT, grassT = 0, 0
		RunService.Heartbeat:Connect(function(dt)
			if not self._on then
				return
			end
			treeT += dt
			grassT += dt
			local camera = Workspace.CurrentCamera
			if not camera then
				return
			end
			if treeT >= TREE_EVERY then
				treeT = 0
				self:_updateTrees(camera.CFrame.Position)
			end
			if grassT >= GRASS_EVERY then
				grassT = 0
				-- grass grows round the hero (the camera's own focus is not kept up to date)
				local character = Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				self:_updateGrass(if root then root.Position else camera.CFrame.Position)
			end
		end)
	end)
end

function ArtController:_readClassic()
	table.clear(self._classic)
	for _, kind in string.split(Workspace:GetAttribute("BonkArtClassic") or "", ",") do
		if kind ~= "" then
			self._classic[kind] = true
		end
	end
	self._dirty = true
end

function ArtController:_setOn(on: boolean)
	if on == self._on then
		return
	end
	self._on = on
	if on then
		local folder = Instance.new("Folder")
		folder.Name = "WardwoodArt" -- the canopy fade watches this name (CanopyController)
		folder.Parent = Workspace
		self._folder = folder
		local grass = Instance.new("Folder")
		grass.Name = "WardwoodGrass"
		grass.Parent = Workspace
		self._grassFolder = grass
		self._dirty = true
	else
		for _, item in self._items do
			item.model, item.level, item.name = nil, nil, nil
		end
		table.clear(self._pools)
		table.clear(self._grassActive)
		table.clear(self._grassEdge)
		if self._folder then
			self._folder:Destroy()
		end
		if self._grassFolder then
			self._grassFolder:Destroy()
		end
	end
end

-- ------------------------------------------------------------------ copies

function ArtController:_take(name: string): Model?
	local pool = self._pools[name]
	if pool and #pool > 0 then
		return table.remove(pool)
	end
	local template = self._templates:FindFirstChild(name)
	return if template then template:Clone() else nil
end

function ArtController:_give(name: string, model: Model)
	model.Parent = nil
	local pool = self._pools[name]
	if not pool then
		pool = {}
		self._pools[name] = pool
	end
	table.insert(pool, model)
end

local function tint(model: Model, k: { number })
	for _, part in model:GetChildren() do
		if part:IsA("MeshPart") and CollectionService:HasTag(part, "WWFoliage") then
			local base = part:GetAttribute("BaseColor")
			if base then
				part.Color = Color3.new(math.min(base.R * k[1], 1), math.min(base.G * k[2], 1), math.min(base.B * k[3], 1))
			end
		end
	end
end

-- ------------------------------------------------------------------ trees and props

-- the detail level for a plant `d` studs from the camera, kept where it is
-- until it is `slack` past the boundary
local function levelFor(current: number?, d: number): number
	local near, far, slack = LOD.near, LOD.far, LOD.slack
	local level = if d < near then 0 elseif d < far then 1 else 2
	if current == 0 and level == 1 and d < near + slack then
		return 0
	elseif current == 1 and level == 0 and d > near - slack then
		return 1
	elseif current == 1 and level == 2 and d < far + slack then
		return 1
	elseif current == 2 and level == 1 and d > far - slack then
		return 2
	end
	return level
end

-- the template for a level, or the nearest level that has baked
function ArtController:_nameFor(item, level: number): string?
	if not item.lod then
		level = 0
	end
	local order = if level == 2 then { 2, 1, 0 } elseif level == 1 then { 1, 2, 0 } else { 0, 1, 2 }
	for _, l in order do
		local name = item.asset .. SUFFIX[l]
		if self._templates:FindFirstChild(name) then
			return name
		end
	end
	return nil
end

function ArtController:_updateTrees(eye: Vector3)
	local changes = {}
	local dirty = self._dirty
	self._dirty = false
	for _, item in self._items do
		local d = math.sqrt((item.x - eye.X) ^ 2 + (item.z - eye.Z) ^ 2)
		local level = if item.lod then levelFor(item.level, d) else 0
		local classic = self._classic[item.prop.kind]
		if classic then
			if item.model then
				table.insert(changes, { item = item, d = d, name = nil })
			end
		elseif level ~= item.level or (dirty and item.name ~= self:_nameFor(item, level)) then
			table.insert(changes, { item = item, d = d, name = self:_nameFor(item, level), level = level })
		end
	end
	if #changes > SWAPS_PER_TICK then
		table.sort(changes, function(a, b)
			return a.d < b.d
		end)
		self._dirty = self._dirty or dirty
	end
	for i = 1, math.min(#changes, SWAPS_PER_TICK) do
		local c = changes[i]
		local item = c.item
		if item.name ~= c.name then
			if item.model then
				self:_give(item.name, item.model)
				item.model = nil
			end
			if c.name then
				local model = self:_take(c.name)
				if model then
					if math.abs(model:GetScale() - item.scale) > 1e-3 then
						model:ScaleTo(item.scale)
					end
					model:PivotTo(item.cf)
					tint(model, item.tint)
					model.Parent = self._folder
					item.model = model
				end
			end
			item.name = if item.model then c.name else nil
		end
		item.level = c.level
	end
end

-- ------------------------------------------------------------------ grass

function ArtController:_tintGrass(model: Model)
	local colour = Workspace:GetAttribute("BonkGrassColor")
	for _, part in model:GetChildren() do
		if part:IsA("MeshPart") then
			local base = if typeof(colour) == "Color3" then colour else part:GetAttribute("BaseColor")
			local k = if typeof(colour) == "Color3" then GRASS_TONE[part.Name] or 1 else 1
			if base then
				part.Color = Color3.new(math.min(base.R * k, 1), math.min(base.G * k, 1), math.min(base.B * k, 1))
			end
		end
	end
end

local function grassFrame(patch): CFrame
	local up = Vector3.new(patch.up[1], patch.up[2], patch.up[3]).Unit
	local at = CFrame.new(patch.x, patch.y, patch.z)
	local axis = Vector3.new(0, 1, 0):Cross(up)
	if axis.Magnitude > 1e-4 then
		at *= CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(up.Y, -1, 1)))
	end
	return at * CFrame.Angles(0, patch.yaw, 0)
end

function ArtController:_updateGrass(focus: Vector3)
	local cell, radius = GRASS.cell, GRASS.radius
	local keep = radius + cell
	local edge = radius - GRASS_EDGE
	-- what has fallen behind goes back to its pool; what crosses into or out
	-- of the outer ring is resized
	for key, model in self._grassActive do
		local cx, cz = key // 65536, key % 65536 - 32768
		local x, z = (cx + 0.5) * cell, (cz + 0.5) * cell
		local d2 = (x - focus.X) ^ 2 + (z - focus.Z) ^ 2
		if d2 > keep * keep then
			if model then
				self:_give(model.Name, model)
			end
			self._grassActive[key] = nil
			self._grassEdge[key] = nil
		elseif model then
			local outer = d2 > edge * edge
			if outer ~= self._grassEdge[key] then
				self._grassEdge[key] = outer
				model:ScaleTo(self._field(cx, cz).scale * (if outer then EDGE_SCALE else 1))
			end
		end
	end
	-- and the ground ahead is grown, nearest first
	local r = math.ceil(radius / cell)
	local fx, fz = math.floor(focus.X / cell), math.floor(focus.Z / cell)
	local grown = 0
	for ring = 0, r do
		for cx = fx - ring, fx + ring do
			for cz = fz - ring, fz + ring do
				if math.max(math.abs(cx - fx), math.abs(cz - fz)) == ring then
					local key = cx * 65536 + (cz + 32768)
					if self._grassActive[key] == nil then
						local x, z = (cx + 0.5) * cell, (cz + 0.5) * cell
						if (x - focus.X) ^ 2 + (z - focus.Z) ^ 2 <= radius * radius then
							local patch = self._field(cx, cz)
							local model = patch and self:_take(patch.asset)
							if model then
								model.Name = patch.asset
								local outer = (x - focus.X) ^ 2 + (z - focus.Z) ^ 2 > edge * edge
								self._grassEdge[key] = outer
								local scale = patch.scale * (if outer then EDGE_SCALE else 1)
								if math.abs(model:GetScale() - scale) > 1e-3 then
									model:ScaleTo(scale)
								end
								model:PivotTo(grassFrame(patch))
								self:_tintGrass(model)
								model.Parent = self._grassFolder
							end
							self._grassActive[key] = model or false
							grown += 1
							if grown >= GRASS_PER_TICK then
								return
							end
						end
					end
				end
			end
		end
	end
end

return ArtController

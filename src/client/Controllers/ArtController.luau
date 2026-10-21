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
--
-- Purely visual and local: the server never sees any of it. `BonkArt` off (the
-- `art off` dev command) or a family listed in `BonkArtClassic` leaves the old
-- props showing instead.

local CollectionService = game:GetService("CollectionService")
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
local TREE_EVERY = 0.2 -- seconds between detail checks
local HIDE_BEYOND = 1500 -- studs from the Wardwood's centre: past this its art is put away
local SWAPS_PER_TICK = 60
local SUFFIX = { [0] = "", [1] = "_LOD", [2] = "_FAR" }

function ArtController:KnitInit()
	self._items = {}
	self._pools = {} -- template name -> { free models }
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
					cf = (function()
						local x, y, z, yaw, roll = ArtPlan.place(self._world, prop)
						return CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, roll)
					end)(),
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
		-- a template arriving later may be the better version for some plants
		templates.ChildAdded:Connect(function()
			self._dirty = true
		end)
		self:_setOn(Workspace:GetAttribute("BonkArt") == true)

		local treeT = 0
		RunService.Heartbeat:Connect(function(dt)
			if not self._on then
				return
			end
			treeT += dt
			local camera = Workspace.CurrentCamera
			if not camera then
				return
			end
			-- far from the Wardwood (on the island hub, T6/T7) none of it is drawn
			local at = camera.CFrame.Position
			local away = at.X * at.X + at.Z * at.Z > HIDE_BEYOND * HIDE_BEYOND
			if away ~= self._away then
				self._away = away
				if self._folder then
					self._folder.Parent = if away then nil else Workspace
				end
			end
			if away then
				return
			end
			if treeT >= TREE_EVERY then
				treeT = 0
				self:_updateTrees(camera.CFrame.Position)
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
		self._dirty = true
	else
		for _, item in self._items do
			item.model, item.level, item.name = nil, nil, nil
		end
		table.clear(self._pools)
		if self._folder then
			self._folder:Destroy()
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

return ArtController

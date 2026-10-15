--!nonstrict
-- Wardwood Builder - turns Core/World's scenery into instances under
-- Workspace.Map.
--
-- Part-built props (Core/Blueprints) become anchored Parts exactly as the
-- offline preview draws them. Mesh props are cloned from
-- ReplicatedStorage.Assets.Props; a mesh tree keeps only an invisible trunk
-- as its solid part, so a hero at full bunny-hop speed is never snagged by a
-- canopy and nobody can stand in a crown. Effect parts carry a tag
-- (WWFlame, WWRune, WWGlow) and the client's AmbienceController dresses them.
--
-- Workspace.Map is not part of the Rojo tree: this runtime build must never
-- sit inside a Rojo-managed subtree, which Rojo would reconcile away.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)
local World = require(ReplicatedStorage.Shared.Core.World)

local Builder = {}

local SHAPES = { block = Enum.PartType.Block, ball = Enum.PartType.Ball, cylinder = Enum.PartType.Cylinder }

-- mesh props a hero passes through rather than trips over
local WALK_THROUGH = { Bush = true, RockSmall = true, LanternPost = true }

local function material(name: string): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and value then value else Enum.Material.SmoothPlastic
end

local function makePart(p, parent: Instance): BasePart
	local part: BasePart
	if p.shape == "wedge" then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		block.Shape = SHAPES[p.shape] or Enum.PartType.Block
		part = block
	end
	part.Anchored = true
	part.CanCollide = p.collide
	part.CanQuery = p.collide
	part.CanTouch = false
	part.CastShadow = p.shadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
	local cf = p.cf
	part.CFrame = CFrame.new(cf[1], cf[2], cf[3], cf[4], cf[5], cf[6], cf[7], cf[8], cf[9], cf[10], cf[11], cf[12])
	part.Color = Color3.fromRGB(p.color[1], p.color[2], p.color[3])
	part.Material = if p.neon then Enum.Material.Neon else material(p.mat)
	if p.light then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(p.light.color[1], p.light.color[2], p.light.color[3])
		l.Brightness = p.light.brightness
		l.Range = p.light.range
		l.Shadows = false
		l.Parent = part
	end
	if p.tag then
		CollectionService:AddTag(part, "WW" .. p.tag)
	end
	part.Parent = parent
	return part
end

-- an invisible upright trunk: the only thing about a mesh tree that collides
local function trunk(model: Model, x: number, y: number, z: number, radius: number, height: number)
	local p = Instance.new("Part")
	p.Name = "Trunk"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, radius * 2, radius * 2)
	p.CFrame = CFrame.new(x, y + height / 2, z) * CFrame.Angles(0, 0, math.rad(90))
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = model
end

local function meshProp(world, prop, templates: Instance): Model?
	local template = templates:FindFirstChild(prop.kind)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	model:ScaleTo(prop.scale)
	local ground = MapGen.heightAt(world.map, prop.x, prop.z)
	local y = ground - 0.4 * prop.scale + (prop.lift or 0)
	model:PivotTo(CFrame.new(prop.x, y, prop.z) * CFrame.Angles(0, prop.yaw, 0))
	local solidTree = prop.collider ~= nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CanQuery = false
			if solidTree or WALK_THROUGH[prop.kind] then
				d.CanCollide = false
			end
		end
	end
	if solidTree then
		trunk(model, prop.x, ground - 1, prop.z, prop.collider, math.max(10, 4 * prop.scale))
	end
	if prop.kind == "LanternPost" then
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 190, 110)
		glow.Brightness = 1.4
		glow.Range = 24
		glow.Shadows = false
		glow.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	end
	return model
end

-- the Moonwell's surface: a still glassy disc over its shallow floor, and a
-- faint teal glow beneath it
local function water(w, parent: Instance)
	local surface = Instance.new("Part")
	surface.Name = "MoonwellSurface"
	surface.Shape = Enum.PartType.Cylinder
	surface.Size = Vector3.new(0.3, w.r * 2, w.r * 2)
	surface.CFrame = CFrame.new(w.x, w.level, w.z) * CFrame.Angles(0, 0, math.rad(90))
	surface.Material = Enum.Material.Glass
	surface.Color = Color3.fromRGB(62, 136, 146)
	surface.Transparency = 0.45
	surface.Reflectance = 0.2
	surface.Anchored = true
	surface.CanCollide = false
	surface.CanQuery = false
	surface.CanTouch = false
	surface.CastShadow = false
	surface.Parent = parent
	local glow = surface:Clone()
	glow.Name = "MoonwellGlow"
	glow.Size = Vector3.new(0.2, w.r * 1.6, w.r * 1.6)
	glow.CFrame = CFrame.new(w.x, w.level - 1.1, w.z) * CFrame.Angles(0, 0, math.rad(90))
	glow.Material = Enum.Material.Neon
	glow.Color = Color3.fromRGB(80, 210, 196)
	glow.Transparency = 0.82
	glow.Reflectance = 0
	glow.Parent = parent
	CollectionService:AddTag(glow, "WWGlow")
end

--- Build every prop of the world into a fresh Workspace.Map. Yields now and
--- then so the server never stalls; returns how many props were built.
function Builder.build(world): number
	local old = Workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Map"
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local templates = assets and assets:FindFirstChild("Props")
	local built, parts = 0, 0
	for i, prop in world.props do
		local prims = World.parts(world, prop)
		local model: Model? = nil
		if prims then
			model = Instance.new("Model")
			for _, p in prims do
				makePart(p, model)
			end
			parts += #prims
		elseif templates then
			model = meshProp(world, prop, templates)
			parts += 1
		end
		if model then
			model.Name = prop.kind
			model.Parent = folder
			built += 1
		end
		if i % 120 == 0 then
			task.wait()
		end
	end
	for _, w in world.water do
		water(w, folder)
	end
	folder.Parent = Workspace
	print(`[Wardwood] {built} props, about {parts} parts`)
	return built
end

--- The terrain material and colour key for one column (see Look.Surfaces).
function Builder.surface(world, x: number, z: number): string
	return World.surface(world, x, z)
end

return Builder

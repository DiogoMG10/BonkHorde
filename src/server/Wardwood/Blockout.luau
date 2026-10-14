--!nonstrict
-- Wardwood Blockout - greybox stand-ins for the Wardwood prototype's props.
--
-- Plain Parts in the blockout palette, built where WardwoodDressing put them.
-- They stand in for meshes that do not exist yet, so the composition, lighting,
-- occlusion and movement can be judged before any asset is made. They follow
-- the convention of the real props: visual parts never collide or answer
-- queries, and only the parts a hero should bump into collide.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)
local Wardwood = require(ReplicatedStorage.Shared.Config.Wardwood)
local WardwoodLook = require(ReplicatedStorage.Shared.Config.WardwoodLook)

local Blockout = {}

local C = WardwoodLook.Colors

local function part(model: Model, size: Vector3, cframe: CFrame, color: Color3, solid: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanTouch = false
	p.CanQuery = false
	p.CanCollide = solid == true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Parent = model
	return p
end

-- a vertical cylinder (Roblox cylinders run along X)
local function column(model: Model, height: number, diameter: number, base: Vector3, yaw: number, color: Color3, solid: boolean?): Part
	local cf = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, yaw, math.rad(90))
	return part(model, Vector3.new(height, diameter, diameter), cf, color, solid, Enum.PartType.Cylinder)
end

local function light(parent: Instance, spec, color: Color3)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = spec.Brightness
	l.Range = spec.Range
	l.Shadows = spec.Shadows
	l.Parent = parent
end

-- a stable per-position jitter in [0, 1)
local function jitter(x: number, z: number, salt: number): number
	local v = math.sin(x * 12.9898 + z * 78.233 + salt * 37.719) * 43758.5453
	return v - math.floor(v)
end

local builders = {}

function builders.WW_Trunk(model, prop, ground)
	local s = prop.scale
	local h = Wardwood.TrunkHeight * s
	local d = prop.radius * 1.7
	column(model, h + 1, d, Vector3.new(prop.x, ground - 1, prop.z), prop.yaw, C.Bark, true)
	-- three tiers of crossed blocks: a jagged, solid canopy that starts high
	local bottom = math.max(Wardwood.CanopyMinHeight, h * 0.4)
	local tierH = (h - bottom) / 3
	for k = 1, 3 do
		local w = (11 - 3 * (k - 1)) * s
		local y = ground + bottom + tierH * (k - 0.5)
		local color = if k % 2 == 0 then C.CanopyLight else C.Canopy
		for j = 0, 1 do
			local cf = CFrame.new(prop.x, y, prop.z) * CFrame.Angles(0, prop.yaw + k * 0.7 + j * math.pi / 2, 0)
			part(model, Vector3.new(w, tierH * 0.9, w * 0.5), cf, color)
		end
	end
end

function builders.WW_Slab(model, prop, ground)
	local s = prop.scale
	local main = Vector3.new(10, 5, 7) * s
	local cf = CFrame.new(prop.x, ground + main.Y * 0.2, prop.z) * CFrame.Angles(math.rad(8), prop.yaw, math.rad(-6))
	part(model, main, cf, C.Stone, true)
	part(model, Vector3.new(main.X * 0.92, 0.6 * s, main.Z * 0.9), cf * CFrame.new(0, main.Y / 2 + 0.2 * s, 0), C.Moss)
	local side = cf * CFrame.new(main.X * 0.45, -main.Y * 0.15, main.Z * 0.35) * CFrame.Angles(math.rad(-12), 0.6, math.rad(10))
	part(model, Vector3.new(6, 4, 5) * s, side, C.Stone, true)
end

function builders.WW_Fern(model, prop, ground)
	local s = prop.scale
	for k = 0, 4 do
		local cf = CFrame.new(prop.x, ground + 0.8 * s, prop.z)
			* CFrame.Angles(0, prop.yaw + k * math.pi * 2 / 5, 0)
			* CFrame.Angles(math.rad(35), 0, 0)
		part(model, Vector3.new(0.3, 2.2 * s, 2.6 * s), cf * CFrame.new(0, 0, -1 * s), C.Fern)
	end
end

-- a ruin tile laid on the ground's own slope, so no edge stands proud of it
function builders.WW_Tile(model, prop, _ground, map)
	local size = Wardwood.WardTileSize
	local right = Vector3.new(math.cos(prop.yaw), 0, -math.sin(prop.yaw))
	local back = Vector3.new(math.sin(prop.yaw), 0, math.cos(prop.yaw))
	local function h(v: Vector3): number
		return MapGen.heightAt(map, prop.x + v.X, prop.z + v.Z)
	end
	local half = size / 2
	local sx = (h(right * half) - h(-right * half)) / size
	local sz = (h(back * half) - h(-back * half)) / size
	local up = Vector3.new(back.X, sz, back.Z).Unit:Cross(Vector3.new(right.X, sx, right.Z).Unit).Unit
	local vx = up:Cross(Vector3.new(back.X, sz, back.Z).Unit).Unit
	local thickness = 1.2
	local centre = Vector3.new(prop.x, MapGen.heightAt(map, prop.x, prop.z) + 0.25, prop.z) - up * (thickness / 2)
	local mossy = jitter(prop.x, prop.z, 1) > 0.65
	local color = if mossy then C.RuinStone:Lerp(C.Moss, 0.45) else C.RuinStone
	part(model, Vector3.new(size - 0.3, thickness, size - 0.3), CFrame.fromMatrix(centre, vx, up), color, true)
end

local function drums(model, prop, ground, count: number)
	local top = ground - 0.5
	for k = 1, count do
		local offset = Vector3.new((jitter(prop.x, prop.z, k) - 0.5) * 0.3, 0, (jitter(prop.z, prop.x, k) - 0.5) * 0.3)
		column(model, 4.5, 3.4, Vector3.new(prop.x, top, prop.z) + offset, prop.yaw + k, C.RuinStone, true)
		top += 4.5
	end
	return top
end

function builders.WW_Pillar(model, prop, ground)
	local top = drums(model, prop, ground, 4)
	column(model, 0.6, 3.6, Vector3.new(prop.x, top, prop.z), prop.yaw, C.Moss)
	-- the finial: a stand-in for a carved head
	local cf = CFrame.new(prop.x, top + 1.8, prop.z) * CFrame.Angles(0, prop.yaw + math.pi / 4, 0)
	part(model, Vector3.new(2.2, 2.2, 2.2), cf, C.RuinStone)
end

function builders.WW_PillarBroken(model, prop, ground)
	local top = drums(model, prop, ground, 2)
	column(model, 0.5, 3.6, Vector3.new(prop.x, top, prop.z), prop.yaw, C.Moss)
	-- a fallen drum beside it: decoration only, so it never trips a hop
	local right = Vector3.new(math.cos(prop.yaw), 0, -math.sin(prop.yaw))
	local at = Vector3.new(prop.x, ground + 1.2, prop.z) + right * 4
	part(
		model,
		Vector3.new(4.5, 3.4, 3.4),
		CFrame.new(at) * CFrame.Angles(0, prop.yaw + 0.4, 0),
		C.RuinStone,
		false,
		Enum.PartType.Cylinder
	)
end

function builders.WW_Brazier(model, prop, ground)
	part(model, Vector3.new(3, 2.6, 3), CFrame.new(prop.x, ground + 0.8, prop.z) * CFrame.Angles(0, prop.yaw, 0), C.RuinStone, true)
	column(model, 1.2, 4.6, Vector3.new(prop.x, ground + 2.1, prop.z), prop.yaw, C.Stone)
	local embers =
		part(model, Vector3.new(3.2, 0.5, 3.2), CFrame.new(prop.x, ground + 3.2, prop.z) * CFrame.Angles(0, prop.yaw, 0), C.Ember)
	embers.Material = Enum.Material.Neon
	light(embers, WardwoodLook.BrazierLight, C.Ember)
end

function builders.WW_WardStone(model, prop, ground)
	local cf = CFrame.new(prop.x, ground + 4.5, prop.z) * CFrame.Angles(0, prop.yaw, 0) * CFrame.Angles(math.rad(4), 0, 0)
	part(model, Vector3.new(5, 11, 1.6), cf, C.Stone, true)
	-- the rune strip faces spawn (local -z)
	local rune = part(model, Vector3.new(0.6, 7, 0.12), cf * CFrame.new(0, 0.5, -0.86), C.Rune)
	rune.Material = Enum.Material.Neon
	light(rune, WardwoodLook.WardLight, C.Rune)
end

--- Is there a blockout builder for this prop kind?
function Blockout.has(kind: string): boolean
	return builders[kind] ~= nil
end

--- Build one prop as a Model of Parts. The caller parents it.
function Blockout.build(prop, map): Model
	local model = Instance.new("Model")
	model.Name = prop.kind
	local ground = MapGen.heightAt(map, prop.x, prop.z)
	builders[prop.kind](model, prop, ground, map)
	model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
	return model
end

return Blockout

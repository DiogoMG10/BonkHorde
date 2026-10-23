--!nonstrict
-- Skyhold Builder - puts the island hub (T6/T7) into the world, once, at server
-- start: its walkable ground as Roblox Terrain (Core/SkyholdGen), then the
-- Blender kit (tools/art/skyhold.py) baked and placed where the kit's own
-- layout says, with the colliders the kit authored, and an invisible wall
-- round the rim so nobody walks off by accident.
--
-- The kit's meshes are rebuilt at start as EditableMeshes (Wardwood/ArtKit, with
-- their vertex colours) and kept as templates in ReplicatedStorage.SkyholdArt,
-- so clients can draw far scenery from the same shapes. Nothing is uploaded.
-- Before the kit exists (or if an asset will not bake) the gameplay pieces get
-- plain stand-ins, so the hub always works.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Look = require(ReplicatedStorage.Shared.Look)
local SkyholdGen = require(ReplicatedStorage.Shared.Core.SkyholdGen)

local ArtKit = require(script.Parent.Parent.Wardwood.ArtKit)

local Builder = {}

local VOXEL = 4
local CHUNK = 32 -- terrain columns per side per write

local function origin(cfg): Vector3
	return Vector3.new(cfg.Origin[1], cfg.Origin[2], cfg.Origin[3])
end

-- ------------------------------------------------------------------ terrain

local function bounds(plan)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, poly in { plan.outline, plan.islet } do
		for _, p in poly do
			minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
			minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
		end
	end
	local function down(v)
		return math.floor(v / VOXEL) * VOXEL - VOXEL
	end
	local function up(v)
		return math.ceil(v / VOXEL) * VOXEL + VOXEL
	end
	return down(minX), up(maxX), down(minZ), up(maxZ)
end

--- Write the island's ground into Terrain: a crust under every column of
--- land, its surface material from SkyholdGen.surfaceAt.
function Builder.writeTerrain(plan)
	local cfg = plan.cfg
	local o = origin(cfg)
	local terrain = Workspace.Terrain
	local minX, maxX, minZ, maxZ = bounds(plan)
	local columnsX = (maxX - minX) // VOXEL
	local columnsZ = (maxZ - minZ) // VOXEL

	-- every column's height once (nil: open sky)
	local heights = table.create(columnsX)
	local lowest, highest = math.huge, -math.huge
	for ix = 1, columnsX do
		local row = {}
		heights[ix] = row
		local x = minX + (ix - 0.5) * VOXEL
		for iz = 1, columnsZ do
			local z = minZ + (iz - 0.5) * VOXEL
			local h = SkyholdGen.heightAt(plan, x, z)
			row[iz] = h or false
			if h then
				lowest, highest = math.min(lowest, h), math.max(highest, h)
			end
		end
	end
	local floor = math.floor((lowest - cfg.CrustDepth) / VOXEL) * VOXEL
	local layers = math.ceil((highest + VOXEL - floor) / VOXEL)
	local air = Enum.Material.Air

	for cx = 0, columnsX - 1, CHUNK do
		for cz = 0, columnsZ - 1, CHUNK do
			local nx = math.min(CHUNK, columnsX - cx)
			local nz = math.min(CHUNK, columnsZ - cz)
			local materials = table.create(nx)
			local occupancy = table.create(nx)
			for ix = 1, nx do
				local matX, occX = table.create(layers), table.create(layers)
				for iy = 1, layers do
					matX[iy] = table.create(nz, air)
					occX[iy] = table.create(nz, 0)
				end
				materials[ix], occupancy[ix] = matX, occX
				local column = heights[cx + ix]
				local x = minX + (cx + ix - 0.5) * VOXEL
				for iz = 1, nz do
					local h = column[cz + iz]
					if h then
						local z = minZ + (cz + iz - 0.5) * VOXEL
						local surface = Look.Surfaces[SkyholdGen.surfaceAt(plan, x, z)]
						local material = if surface then surface[1] else Enum.Material.Grass
						for iy = 1, layers do
							local bottom = floor + (iy - 1) * VOXEL
							if bottom >= h - cfg.CrustDepth then
								-- the drawn surface sits half a voxel above the fill (as in the Wardwood)
								local fill = math.clamp((h - VOXEL / 2 - bottom) / VOXEL, 0, 1)
								if fill > 0 then
									occX[iy][iz] = fill
									matX[iy][iz] = if h - bottom <= VOXEL * 2 then material else Enum.Material.Ground
								end
							end
						end
					end
				end
			end
			local minV = o + Vector3.new(minX + cx * VOXEL, floor, minZ + cz * VOXEL)
			local maxV = minV + Vector3.new(nx * VOXEL, layers * VOXEL, nz * VOXEL)
			terrain:WriteVoxels(Region3.new(minV, maxV), VOXEL, materials, occupancy)
		end
		task.wait()
	end
end

-- ------------------------------------------------------------------ the kit

local function folderIn(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Folder
end

local LIGHTS = {
	Glass = { Color3.fromRGB(255, 190, 110), 14, 1.1 },
	Embers = { Color3.fromRGB(255, 140, 60), 18, 1.6 },
}

-- bake one kit asset into a template Model (its pivot the asset's origin)
local function bakeAsset(name: string, data): Model?
	local model = Instance.new("Model")
	model.Name = name
	for _, part in data.parts do
		local mp = ArtKit.bakeMesh(ArtKit.decode(part), `{name}.{part.name}`)
		if not mp then
			model:Destroy()
			return nil
		end
		mp.Name = part.name
		mp.Color = Color3.fromRGB(part.color[1], part.color[2], part.color[3])
		mp.Material = (Enum.Material :: any)[part.material] or Enum.Material.SmoothPlastic
		mp.Transparency = part.transparency or 0
		mp.CastShadow = part.shadow ~= false
		if part.tag then
			CollectionService:AddTag(mp, part.tag)
		end
		-- the lanterns' glass and the braziers' embers give off a little light
		local light = LIGHTS[part.name]
		if light then
			local l = Instance.new("PointLight")
			l.Color = light[1]
			l.Range = light[2]
			l.Brightness = light[3]
			l.Shadows = false
			l.Parent = mp
		end
		mp.Parent = model
	end
	model.WorldPivot = CFrame.new()
	return model
end

--- Bake every kit asset into ReplicatedStorage.SkyholdArt. Returns the names
--- that would not bake.
function Builder.bakeKit(): { string }
	local templates = folderIn(ReplicatedStorage, "SkyholdArt")
	local meshes = script.Parent:FindFirstChild("Meshes")
	local failed = {}
	if not meshes then
		return failed
	end
	local sources = meshes:GetChildren()
	table.sort(sources, function(a, b)
		return a.Name < b.Name
	end)
	for i, source in sources do
		if source:IsA("ModuleScript") and not templates:FindFirstChild(source.Name) then
			local ok, data = pcall(require, source)
			local model = ok and bakeAsset(source.Name, data)
			if model then
				model.Parent = templates
			else
				table.insert(failed, source.Name)
			end
		end
		if i % 4 == 0 then
			task.wait()
		end
	end
	return failed
end

local function collider(parent: Instance, cf: CFrame, size: Vector3, shape: string?)
	local p = Instance.new("Part")
	p.Name = "Collider"
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	if shape == "cyl" then
		p.Shape = Enum.PartType.Cylinder
		-- a Roblox cylinder lies along its x axis: stand it up
		p.Size = Vector3.new(size.Y, size.X, size.Z)
		p.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	else
		p.Size = size
		p.CFrame = cf
	end
	p.Parent = parent
	return p
end

-- place one layout entry: a kit template, or one of the Wardwood's own trees
local function place(entry, root: CFrame, art: Folder, colliders: Folder, kitData)
	local templates = if entry.kit == "wardwood"
		then ReplicatedStorage:FindFirstChild("WardwoodArt")
		else ReplicatedStorage:FindFirstChild("SkyholdArt")
	local template = templates and templates:FindFirstChild(entry.asset)
	if not template then
		return nil
	end
	local model = template:Clone()
	model.Name = entry.name or entry.asset
	local p = entry.cf
	local cf = root * CFrame.new(p[1], p[2], p[3]) * CFrame.fromOrientation(math.rad(p[4] or 0), math.rad(p[5] or 0), math.rad(p[6] or 0))
	local scale = entry.scale or 1
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:PivotTo(cf)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	model.Parent = art
	local data = kitData[entry.asset]
	if data and data.colliders and entry.collide ~= false then
		for _, c in data.colliders do
			-- the kit's colliders: a position and a full rotation (r: R00..R22), in the asset's space
			local r = c.r
			local at = cf * CFrame.new(c.p[1] * scale, c.p[2] * scale, c.p[3] * scale, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
			collider(colliders, at, Vector3.new(c.size[1], c.size[2], c.size[3]) * scale, c.shape)
		end
	elseif entry.kit == "wardwood" and entry.trunk and entry.collide ~= false then
		collider(colliders, cf * CFrame.new(0, entry.trunk[2] / 2, 0), Vector3.new(entry.trunk[1], entry.trunk[2], entry.trunk[1]), "cyl")
	end
	if entry.seat then
		-- somewhere to sit and watch the clouds
		local seat = Instance.new("Seat")
		seat.Name = "Seat"
		seat.Anchored = true
		seat.Transparency = 1
		seat.Size = Vector3.new(3.6, 0.4, 1.2) * scale
		seat.CFrame = cf * CFrame.new(0, 1.2 * scale, 0)
		seat.Parent = model
	end
	return model
end

-- ------------------------------------------------------------------ stand-ins

local STONE = Color3.fromRGB(178, 168, 150)
local TEAL = Color3.fromRGB(70, 214, 200)

local function block(parent: Instance, name: string, cf: CFrame, size: Vector3, colour: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.Slate
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- the gameplay pieces as plain parts, for whatever the kit could not give
local function standIns(plan, root: CFrame, art: Folder, have: { [string]: boolean })
	local cfg = plan.cfg
	local function at(x: number, z: number, lift: number?): CFrame
		local h = SkyholdGen.heightAt(plan, x, z) or 0
		return root * CFrame.new(x, h + (lift or 0), z)
	end
	for i, c in cfg.Circles do
		local name = `Circle{i}`
		if not have[name] then
			local m = Instance.new("Model")
			m.Name = name
			local base = at(c.x, c.z, 0.15)
			local ring = block(
				m,
				"Ring",
				base * CFrame.Angles(0, 0, math.rad(90)),
				Vector3.new(0.3, cfg.CircleRadius * 2, cfg.CircleRadius * 2),
				STONE
			)
			ring.Shape = Enum.PartType.Cylinder
			ring.CanCollide = false
			local glow = block(
				m,
				"Glow",
				base * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Vector3.new(0.3, cfg.CircleRadius * 1.6, cfg.CircleRadius * 1.6),
				TEAL,
				Enum.Material.Neon
			)
			glow.Shape = Enum.PartType.Cylinder
			glow.Transparency = 0.6
			glow.CanCollide = false
			for k = 1, cfg.SquadSize do
				local a = (k - 1) / cfg.SquadSize * math.pi * 2
				local slot = block(
					m,
					`Slot{k}`,
					base * CFrame.new(math.sin(a) * (cfg.CircleRadius - 1.2), 0.3, -math.cos(a) * (cfg.CircleRadius - 1.2)),
					Vector3.new(1.4, 0.5, 1.4),
					TEAL,
					Enum.Material.Neon
				)
				slot.CanCollide = false
			end
			block(m, "Board", base * CFrame.new(0, 2, cfg.CircleRadius + 1.5), Vector3.new(4, 4, 0.8), STONE)
			m.Parent = art
		end
	end
	for i, p in cfg.Plinths do
		local name = `Plinth{i}`
		if not have[name] then
			local m = Instance.new("Model")
			m.Name = name
			local base = at(p.x, p.z) * CFrame.Angles(0, math.rad(p.yaw), 0)
			block(m, "Base", base * CFrame.new(0, 0.75, 0), Vector3.new(6, 1.5, 6), STONE)
			block(m, "Top", base * CFrame.new(0, 2, 0), Vector3.new(4.6, 1, 4.6), STONE)
			local plate =
				block(m, "Plate", base * CFrame.new(0, 1, -3.2), Vector3.new(4, 1.2, 0.4), Color3.fromRGB(90, 70, 50), Enum.Material.Wood)
			plate.CanCollide = false
			m.Parent = art
		end
	end
	if not have.Portal then
		local m = Instance.new("Model")
		m.Name = "Portal"
		local p = cfg.Portal
		local base = at(p.x, p.z) * CFrame.Angles(0, math.rad(p.yaw), 0)
		block(m, "PillarL", base * CFrame.new(-12, 10, 0), Vector3.new(3, 20, 3), STONE)
		block(m, "PillarR", base * CFrame.new(12, 10, 0), Vector3.new(3, 20, 3), STONE)
		block(m, "Lintel", base * CFrame.new(0, 21, 0), Vector3.new(28, 3, 3.5), STONE)
		m.Parent = art
	end
end

-- the portal's face: the part the clients light and swirl (PortalController)
local function portalFace(plan, root: CFrame, art: Folder)
	local cfg = plan.cfg
	local p = cfg.Portal
	local h = SkyholdGen.heightAt(plan, p.x, p.z) or 0
	local face = Instance.new("Part")
	face.Name = "PortalFace"
	face.Shape = Enum.PartType.Cylinder
	face.Anchored = true
	face.CanCollide = false
	face.CanQuery = false
	face.CanTouch = false
	face.CastShadow = false
	face.Material = Enum.Material.Neon
	face.Color = Color3.fromRGB(60, 200, 196)
	face.Transparency = 0.35
	local radius = cfg.PortalRadius or 9.5
	face.Size = Vector3.new(0.4, radius * 2, radius * 2)
	-- a cylinder's round faces look along its x axis: turn them to face south
	face.CFrame = root
		* CFrame.new(p.x, h + (cfg.PortalCentreHeight or 15), p.z)
		* CFrame.Angles(0, math.rad(p.yaw), 0)
		* CFrame.Angles(0, math.rad(90), 0)
	face.Parent = art
end

-- ------------------------------------------------------------------ rim

--- An invisible wall round both pieces of land, open where the bridge lands.
local function rimWall(plan, root: CFrame, parent: Folder)
	local cfg = plan.cfg
	local gaps = { cfg.Bridge.from, cfg.Bridge.to }
	for _, poly in { plan.outline, plan.islet } do
		local n = #poly
		for i = 1, n do
			local a, b = poly[i], poly[i % n + 1]
			local mx, mz = (a.x + b.x) / 2, (a.z + b.z) / 2
			local open = false
			for _, g in gaps do
				if (mx - g[1]) ^ 2 + (mz - g[2]) ^ 2 < 7 * 7 then
					open = true
				end
			end
			if not open then
				local length = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2) + 0.6
				-- a little inside the rim, where the ground still is
				local cx, cz = mx, mz
				local h = SkyholdGen.heightAt(plan, cx, cz) or SkyholdGen.heightAt(plan, a.x * 0.98, a.z * 0.98) or 0
				local yaw = math.atan2(b.x - a.x, b.z - a.z)
				local wall = Instance.new("Part")
				wall.Name = "Rim"
				wall.Anchored = true
				wall.CanTouch = false
				wall.CanQuery = false
				wall.Transparency = 1
				wall.CastShadow = false
				wall.Size = Vector3.new(1, cfg.RimWallHeight + 6, length)
				wall.CFrame = root * CFrame.new(cx, h + cfg.RimWallHeight / 2 - 2, cz) * CFrame.Angles(0, yaw, 0)
				wall.Parent = parent
			end
		end
	end
end

-- ------------------------------------------------------------------ the island

--- Build Skyhold's scenery under Workspace.Skyhold: the kit's layout, colliders,
--- the stand-ins it may need, the portal face and the rim wall.
--- The Wardwood kit's assets the island is dressed with (its trees, bushes,
--- ferns and rocks), so they can be baked before the rest of the kit.
function Builder.wardwoodAssets(): { string }
	local layout = script.Parent:FindFirstChild("Layout")
	local ok, entries = pcall(require, layout)
	local seen, out = {}, {}
	for _, entry in if ok and typeof(entries) == "table" then entries else {} do
		if entry.kit == "wardwood" and entry.asset and not seen[entry.asset] then
			seen[entry.asset] = true
			table.insert(out, entry.asset)
		end
	end
	return out
end

function Builder.build(plan)
	local cfg = plan.cfg
	local root = CFrame.new(origin(cfg))
	local old = Workspace:FindFirstChild("Skyhold")
	if old then
		old:Destroy()
	end
	local island = Instance.new("Folder")
	island.Name = "Skyhold"
	local art = folderIn(island, "Art")
	local colliders = folderIn(island, "Colliders")
	local rim = folderIn(island, "Rim")

	local layout = script.Parent:FindFirstChild("Layout")
	local entries = if layout then require(layout) else {}
	local kitData = {}
	local meshes = script.Parent:FindFirstChild("Meshes")
	if meshes then
		for _, source in meshes:GetChildren() do
			if source:IsA("ModuleScript") then
				local ok, data = pcall(require, source)
				if ok then
					kitData[source.Name] = data
				end
			end
		end
	end
	island.Parent = Workspace

	local have = {}
	local placed = 0
	for i, entry in entries do
		if place(entry, root, art, colliders, kitData) then
			have[entry.name or entry.asset] = true
			placed += 1
		end
		if i % 40 == 0 then
			task.wait()
		end
	end
	standIns(plan, root, art, have)
	portalFace(plan, root, art)
	rimWall(plan, root, rim)
	print(`[Skyhold] {placed} pieces placed from the kit, {#entries - placed} missing`)
	return island
end

return Builder

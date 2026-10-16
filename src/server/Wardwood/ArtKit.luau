--!nonstrict
-- ArtKit - the Wardwood's Blender-made art (M3.B) brought into the game with
-- no upload. tools/art/kit.py packs each asset's geometry into
-- Wardwood/ArtMeshes/<Asset> (positions, authored normals, triangles); at
-- start the server rebuilds each part once as an EditableMesh, bakes it into
-- static content (AssetService:CreateDataModelContentAsync) and keeps the
-- result as a template Model in ReplicatedStorage.WardwoodArt. The templates,
-- and the content with them, replicate to every client, which places its own
-- copies (client ArtController); nothing is rebuilt per tree.
--
-- The baked content lasts for the server's session: nothing is saved into the
-- place or uploaded. Making the meshes permanent (real MeshIds) is the upload
-- route in docs/M3B-art-pipeline.md, and needs a person's go-ahead.
--
-- Every art part is visual only: no collision, query or touch. Whatever it
-- stands in for keeps its own collider (Wardwood/Builder).

local ArtKit = {}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local LOOKUP = {}
for i = 1, 64 do
	LOOKUP[string.byte(B64, i)] = i - 1
end

local function unbase64(s: string): buffer
	local n = #s
	local pad = if string.sub(s, -2) == "==" then 2 elseif string.sub(s, -1) == "=" then 1 else 0
	local size = n // 4 * 3 - pad
	local out = buffer.create(size)
	local o = 0
	for i = 1, n, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local v = LOOKUP[a] * 262144 + LOOKUP[b] * 4096 + (LOOKUP[c] or 0) * 64 + (LOOKUP[d] or 0)
		buffer.writeu8(out, o, v // 65536)
		if o + 1 < size then
			buffer.writeu8(out, o + 1, (v // 256) % 256)
		end
		if o + 2 < size then
			buffer.writeu8(out, o + 2, v % 256)
		end
		o += 3
	end
	return out
end

export type Mesh = {
	verts: number,
	tris: number,
	pos: { number }, -- x, y, z per vertex, centred on the part's box
	nrm: { number }, -- x, y, z per vertex
	idx: { number }, -- 0-based vertex ids, three per triangle
	centre: { number }, -- the box centre, in the asset's own space
	size: { number },
}

--- One packed part back into plain arrays (no Roblox types, so the specs can
--- check every asset headless).
function ArtKit.decode(part): Mesh
	local buf = unbase64(part.data)
	local lo, hi = part.min, part.max
	local centre = { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }
	local span = { hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3] }
	local pos = table.create(part.verts * 3)
	local nrm = table.create(part.verts * 3)
	for i = 0, part.verts - 1 do
		local o = i * 9
		for k = 0, 2 do
			pos[i * 3 + k + 1] = lo[k + 1] + buffer.readu16(buf, o + k * 2) / 65535 * span[k + 1] - centre[k + 1]
			nrm[i * 3 + k + 1] = buffer.readi8(buf, o + 6 + k) / 127
		end
	end
	local base = part.verts * 9
	local idx = table.create(part.tris * 3)
	for t = 0, part.tris * 3 - 1 do
		idx[t + 1] = buffer.readu16(buf, base + t * 2)
	end
	return { verts = part.verts, tris = part.tris, pos = pos, nrm = nrm, idx = idx, centre = centre, size = span }
end

-- ------------------------------------------------------------------ in the engine

local FOLIAGE =
	{ leafDark = true, leafMid = true, leafLight = true, leafGold = true, needleDark = true, needleMid = true, needleLight = true }

local function meshPart(part, asset: string): MeshPart?
	local AssetService = game:GetService("AssetService")
	local mesh = ArtKit.decode(part)
	local em = AssetService:CreateEditableMesh()
	local vids, nids = table.create(mesh.verts), table.create(mesh.verts)
	local pos, nrm = mesh.pos, mesh.nrm
	for i = 0, mesh.verts - 1 do
		vids[i + 1] = em:AddVertex(Vector3.new(pos[i * 3 + 1], pos[i * 3 + 2], pos[i * 3 + 3]))
		local n = Vector3.new(nrm[i * 3 + 1], nrm[i * 3 + 2], nrm[i * 3 + 3])
		nids[i + 1] = em:AddNormal(if n.Magnitude > 0 then n.Unit else Vector3.new(0, 1, 0))
	end
	local idx = mesh.idx
	for t = 0, mesh.tris - 1 do
		local a, b, c = idx[t * 3 + 1] + 1, idx[t * 3 + 2] + 1, idx[t * 3 + 3] + 1
		local face = em:AddTriangle(vids[a], vids[b], vids[c])
		em:SetFaceNormals(face, { nids[a], nids[b], nids[c] })
	end
	-- bake it, so it reaches the clients and the editable copy can go
	local okBake, result, baked = pcall(function()
		return AssetService:CreateDataModelContentAsync(Content.fromObject(em))
	end)
	if not (okBake and result == Enum.CreateContentResult.Success) then
		em:Destroy()
		warn(`[ArtKit] {asset}.{part.name}: not baked ({if okBake then result else baked})`)
		return nil
	end
	local ok, mp = pcall(function()
		return AssetService:CreateMeshPartAsync(baked, {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			-- the engine's own simplification would thin blades away; grass is
			-- only ever drawn near the hero anyway
			RenderFidelity = if string.find(asset, "^Grass") then Enum.RenderFidelity.Precise else Enum.RenderFidelity.Automatic,
		})
	end)
	em:Destroy()
	if not ok then
		warn(`[ArtKit] {asset}.{part.name}: {mp}`)
		return nil
	end
	local colour = Color3.fromRGB(part.color[1], part.color[2], part.color[3])
	mp.Name = part.name
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	-- grass and the horizon trees cast no shadow: nobody would see it
	mp.CastShadow = not (string.find(asset, "^Grass") or string.find(asset, "_FAR$"))
	mp.Color = colour
	mp:SetAttribute("BaseColor", colour) -- clients tint each plant from it
	mp.Material = (Enum.Material :: any)[part.material] or Enum.Material.SmoothPlastic
	mp.Size = Vector3.new(math.max(mesh.size[1], 0.01), math.max(mesh.size[2], 0.01), math.max(mesh.size[3], 0.01))
	mp.CFrame = CFrame.new(mesh.centre[1], mesh.centre[2], mesh.centre[3])
	if FOLIAGE[part.name] then
		game:GetService("CollectionService"):AddTag(mp, "WWFoliage")
	end
	return mp
end

--- One asset's template Model (its pivot the asset's foot, at the origin), or
--- nil if any of its parts would not bake: half a tree is worse than the old one.
function ArtKit.build(name: string): Model?
	local source = script.Parent.ArtMeshes:FindFirstChild(name)
	if not source then
		return nil
	end
	local data = require(source) :: any
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored, root.CanCollide, root.CanQuery, root.CanTouch = true, false, false, false
	root.Transparency = 1
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	for _, part in data.parts do
		local mp = meshPart(part, name)
		if not mp then
			model:Destroy()
			return nil
		end
		mp.Parent = model
	end
	return model
end

-- the horizon and far versions first, so the whole wood stands at once; then
-- the grass and the close-up trees; then the rest of the kit
local function priority(name: string): number
	if string.find(name, "_FAR$") then
		return 0
	elseif string.find(name, "_LOD$") then
		return 1
	elseif string.find(name, "^Grass") then
		return 2
	end
	return 3
end

--- Bake every asset into ReplicatedStorage.WardwoodArt, a few at a time.
--- Returns the names that failed. The folder's `Ready` attribute turns true
--- at the end, with `Failed` listing any that did not bake.
function ArtKit.bakeAll(): { string }
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local folder = ReplicatedStorage:FindFirstChild("WardwoodArt")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "WardwoodArt"
		folder.Parent = ReplicatedStorage
	end
	folder:SetAttribute("Ready", false)
	local names = {}
	for _, m in script.Parent.ArtMeshes:GetChildren() do
		if not folder:FindFirstChild(m.Name) then
			table.insert(names, m.Name)
		end
	end
	table.sort(names, function(a, b)
		local pa, pb = priority(a), priority(b)
		return if pa == pb then a < b else pa < pb
	end)
	local failed = {}
	local started = os.clock()
	for _, name in names do
		local model = ArtKit.build(name)
		if model then
			model.Parent = folder
		else
			table.insert(failed, name)
		end
	end
	folder:SetAttribute("Failed", table.concat(failed, ","))
	folder:SetAttribute("Ready", true)
	print(
		`[ArtKit] {#names - #failed} art models baked in {string.format("%.1f", os.clock() - started)}s{if #failed > 0
			then `, {#failed} failed`
			else ""}`
	)
	return failed
end

return ArtKit

-- Dev helper: collect generate_mesh results into Workspace.Staging on a grid,
-- named from design/mesh_jobs.json, and post a measured manifest back to disk.
local Http = game:GetService("HttpService")
local BRIDGE = "http://127.0.0.1:34881/"
local M = {}

function M.collect()
	local jobs = Http:JSONDecode(Http:GetAsync(BRIDGE .. "design/mesh_jobs.json?t=" .. os.clock(), true)).jobs
	local staging = workspace:FindFirstChild("Staging") or Instance.new("Folder")
	staging.Name = "Staging"
	staging.Parent = workspace
	local byPrompt = {}
	for i, job in jobs do byPrompt[job.prompt] = { job = job, index = i } end
	local moved = {}
	for _, c in workspace:GetChildren() do
		local hit = nil
		if c:IsA("Model") and #c.Name >= 20 then
			for prompt, entry in byPrompt do
				if string.sub(prompt, 1, #c.Name) == c.Name then hit = entry break end
			end
		end
		if hit then
			local old = staging:FindFirstChild(hit.job.name)
			if old then old:Destroy() end
			c.Name = hit.job.name
			c:SetAttribute("Class", hit.job.class)
			for _, d in c:GetDescendants() do
				if d:IsA("BasePart") then d.Anchored = true end
			end
			c.Parent = staging
			table.insert(moved, hit.job.name)
		end
	end
	-- lay everything out by job order, 40 studs apart, resting on y = 0
	local missing = {}
	for i, job in jobs do
		local m = staging:FindFirstChild(job.name)
		if m then
			local cf, size = m:GetBoundingBox()
			local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
			local want = Vector3.new(1000 + col * 40, size.Y / 2, 1000 + row * 40)
			m:PivotTo(m:GetPivot() + (want - cf.Position))
		else
			table.insert(missing, job.name)
		end
	end
	return "moved: " .. table.concat(moved, ",") .. "\nmissing (" .. #missing .. "): " .. table.concat(missing, ",")
end

function M.manifest()
	local staging = workspace.Staging
	local assets = {}
	local AS = game:GetService("AssetService")
	for _, m in staging:GetChildren() do
		local cf, size = m:GetBoundingBox()
		local parts, tris = {}, 0
		for _, d in m:GetDescendants() do
			if d:IsA("MeshPart") then
				local n = -1
				local ok, em = pcall(function() return AS:CreateEditableMeshAsync(Content.fromUri(d.MeshId)) end)
				if ok and em then n = #em:GetFaces() em:Destroy() end
				if n > 0 then tris += n end
				local rel = cf:ToObjectSpace(d.CFrame)
				table.insert(parts, {
					name = d.Parent.Name, mesh = d.MeshId, texture = d.TextureID, tris = n,
					size = { d.Size.X, d.Size.Y, d.Size.Z }, meshSize = { d.MeshSize.X, d.MeshSize.Y, d.MeshSize.Z },
					cframe = { rel:GetComponents() },
				})
			end
		end
		assets[m.Name] = { class = m:GetAttribute("Class"), bounds_studs = { size.X, size.Y, size.Z }, tris = tris, parts = parts, route = "studio generate_mesh" }
	end
	local body = Http:JSONEncode({ assets = assets })
	local res = Http:PostAsync(BRIDGE .. "save?path=assets/meshes/manifest.json", body, Enum.HttpContentType.ApplicationJson)
	local n = 0 for _ in assets do n += 1 end
	return n .. " assets, " .. res
end
return M

--!nocheck
-- Drift check: does a place file match what this Rojo project would sync?
--
--     lune run tools/rojo/drift.luau <place.rbxl> [project.json]
--
-- Needs Lune 0.10 or newer: the repo's pinned 0.8.9 cannot read the compressed
-- place files Studio saves. With rokit installed:
--     %USERPROFILE%\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe run tools/rojo/drift.luau <place>
--
-- Builds the project with `rojo build` into the temp folder, reads both places
-- (read-only) and reports:
--   1. MANAGED trees (everything the project syncs: code, UI, Assets, Packages):
--      instance names and classes, script source, mesh, texture and image ids.
--   2. DECLARED settings (every $properties entry in the project).
--   3. UNMANAGED objects: what lives only in the place and Rojo leaves alone.
-- Exit code 1 when 1 or 2 differ. Nothing is written except the temp build.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local placePath = process.args[1]
local projectPath = process.args[2] or "default.project.json"
if not placePath then
	print("usage: lune run tools/rojo/drift.luau <place.rbxl> [project.json]")
	process.exit(2)
end

local temp = process.env.TEMP or process.env.TMPDIR or "/tmp"
local expectedPath = `{temp}/bonk-drift-expected.rbxlx` -- XML: Lune cannot read rojo 7.7 compressed binary
local exec = process.exec or process.spawn -- renamed in Lune 0.9
local built = exec("rojo", { "build", projectPath, "-o", expectedPath })
if not built.ok then
	print("rojo build failed:\n" .. built.stderr)
	process.exit(2)
end

local place = roblox.deserializePlace(fs.readFile(placePath))
local expected = roblox.deserializePlace(fs.readFile(expectedPath))
local project = serde.decode("json", fs.readFile(projectPath))

local function service(root, className)
	for _, s in root:GetChildren() do
		if s.ClassName == className then
			return s
		end
	end
	return nil
end

-- the first readable property among names, as text
local function read(inst, names)
	for _, name in names do
		local ok, value = pcall(function()
			return inst[name]
		end)
		if ok and value ~= nil then
			return tostring(value)
		end
	end
	return ""
end

local function assetId(inst, names)
	return string.match(read(inst, names), "%d%d%d%d%d+") or ""
end

-- one entry per instance: path, class and the content that matters
local function signature(root)
	local set = {}
	local function walk(inst, path)
		local key = path .. "/" .. inst.Name .. ":" .. inst.ClassName
		local extra = ""
		if inst:IsA("LuaSourceContainer") then
			local source = string.gsub(read(inst, { "Source" }), "\r\n", "\n")
			extra = "#" .. #source .. ":" .. source
		elseif inst:IsA("MeshPart") then
			extra = assetId(inst, { "MeshContent", "MeshId" }) .. "|" .. assetId(inst, { "TextureContent", "TextureID" })
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			extra = assetId(inst, { "ImageContent", "Image" })
		elseif inst:IsA("Sound") then
			extra = assetId(inst, { "AudioContent", "SoundId" })
		end
		local full = key .. "=" .. extra
		set[full] = (set[full] or 0) + 1
		for _, child in inst:GetChildren() do
			walk(child, key)
		end
	end
	walk(root, "")
	return set
end

local function compare(label, a, b)
	if a == nil or b == nil then
		print(`  DRIFT  {label}: missing in {if a == nil then "place" else "project build"}`)
		return 1
	end
	local sa, sb = signature(a), signature(b)
	local onlyPlace, onlyDisk, examples = 0, 0, {}
	for key, n in sa do
		if (sb[key] or 0) < n then
			onlyPlace += 1
			if #examples < 4 then
				table.insert(examples, "place only: " .. string.sub(key, 1, 160))
			end
		end
	end
	for key, n in sb do
		if (sa[key] or 0) < n then
			onlyDisk += 1
			if #examples < 8 then
				table.insert(examples, "disk only:  " .. string.sub(key, 1, 160))
			end
		end
	end
	if onlyPlace + onlyDisk == 0 then
		print(`  same   {label} ({#a:GetDescendants() + 1} instances)`)
		return 0
	end
	print(`  DRIFT  {label}: {onlyPlace} entries only in the place, {onlyDisk} only on disk`)
	for _, e in examples do
		print("           " .. e)
	end
	return 1
end

local drift = 0
print(`place:   {placePath}`)
print(`project: {projectPath} (built to {expectedPath})`)

print("\nMANAGED (Rojo owns these and replaces them on sync)")
local managed = {} -- service class -> { child names } that are managed
for serviceName, node in project.tree do
	if string.sub(serviceName, 1, 1) == "$" then
		continue
	end
	local p, e = service(place, serviceName), service(expected, serviceName)
	managed[serviceName] = {}
	if node["$path"] then
		-- the whole service is owned: compare every child
		managed[serviceName]["*"] = true
		local names = {}
		for _, c in e:GetChildren() do
			names[c.Name] = true
		end
		for _, c in p:GetChildren() do
			names[c.Name] = true
		end
		for name in names do
			drift += compare(`{serviceName}.{name}`, p and p:FindFirstChild(name), e:FindFirstChild(name))
		end
	end
	local function walkNode(n, pInst, eInst, path)
		for childName, childNode in n do
			if string.sub(childName, 1, 1) == "$" then
				continue
			end
			local pc = pInst and pInst:FindFirstChild(childName)
			local ec = eInst and eInst:FindFirstChild(childName)
			if childNode["$path"] then
				managed[serviceName][path .. childName] = true
				drift += compare(`{serviceName}.{path}{childName}`, pc, ec)
			else
				-- a plain container: only some of its children are managed
				managed[serviceName][path .. childName] = "partial"
				walkNode(childNode, pc, ec, path .. childName .. ".")
			end
		end
	end
	walkNode(node, p, e, "")
end

print("\nDECLARED SETTINGS ($properties in the project)")
local function declared(node, pInst, eInst, path)
	for key, value in node do
		if key == "$properties" then
			for prop in value do
				local pv, ev = read(pInst, { prop }), read(eInst, { prop })
				if pv == "" then
					-- deprecated or unserialised properties (FilteringEnabled) cannot be read back
					print(`  n/a    {path}.{prop}: not readable from the place file, project {ev}`)
					continue
				end
				local same = pv == ev
				if not same then
					drift += 1
				end
				print(`  {if same then "same " else "DRIFT"}  {path}.{prop}: place {pv}, project {ev}`)
			end
		elseif string.sub(key, 1, 1) ~= "$" and type(value) == "table" then
			declared(value, pInst and pInst:FindFirstChild(key), eInst and eInst:FindFirstChild(key), path .. "." .. key)
		end
	end
end
for serviceName, node in project.tree do
	if string.sub(serviceName, 1, 1) ~= "$" then
		declared(node, service(place, serviceName), service(expected, serviceName), serviceName)
	end
end

print("\nUNMANAGED (only in the place; Rojo leaves these alone, they are NOT on disk)")
for _, s in place:GetChildren() do
	local owned = managed[s.ClassName]
	if owned and owned["*"] then
		continue
	end
	for _, c in s:GetChildren() do
		local state = owned and owned[c.Name]
		if state == "partial" then
			for _, gc in c:GetChildren() do
				if not owned[c.Name .. "." .. gc.Name] then
					print(`  {s.ClassName}.{c.Name}.{gc.Name} ({gc.ClassName}, {#gc:GetDescendants()} descendants)`)
				end
			end
		elseif not state then
			print(`  {s.ClassName}.{c.Name} ({c.ClassName}, {#c:GetDescendants()} descendants)`)
		end
	end
end

print(if drift == 0 then "\nverdict: NO DRIFT in managed trees or declared settings" else `\nverdict: DRIFT ({drift} items)`)
process.exit(if drift == 0 then 0 else 1)

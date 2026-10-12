-- Run in Studio's EDIT DataModel (Studio MCP execute_luau) after tools/push/build.ps1.
-- Pulls the four built trees from the local file server and replaces them in the place.
-- One-way, disk to Studio: disk stays the only source of truth.
local Http = game:GetService("HttpService")
local SS = game:GetService("SerializationService")
Http.HttpEnabled = true
local base = "http://127.0.0.1:34880/"
local targets = {
	{ file = "Packages.rbxmx", parent = game:GetService("ReplicatedStorage") },
	{ file = "Shared.rbxmx", parent = game:GetService("ReplicatedStorage") },
	{ file = "Server.rbxmx", parent = game:GetService("ServerScriptService") },
	{ file = "Client.rbxmx", parent = game:GetService("StarterPlayer").StarterPlayerScripts },
}
local report = {}
for _, t in targets do
	local ok, body = pcall(function()
		return Http:GetAsync(base .. t.file .. "?t=" .. tostring(os.clock()), true)
	end)
	if not ok then
		table.insert(report, t.file .. " FETCH FAIL " .. tostring(body))
		continue
	end
	local ok2, list = pcall(function()
		return SS:DeserializeInstancesAsync(buffer.fromstring(body))
	end)
	if not ok2 or #list == 0 then
		table.insert(report, t.file .. " DESERIALIZE FAIL " .. tostring(list))
		continue
	end
	local inst = list[1]
	local old = t.parent:FindFirstChild(inst.Name)
	if old then
		old:Destroy()
	end
	inst.Parent = t.parent
	table.insert(report, t.file .. " ok " .. #inst:GetDescendants())
end
return table.concat(report, " | ")

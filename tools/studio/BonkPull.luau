return function()
	local Http = game:GetService("HttpService")
	local SS = game:GetService("SerializationService")
	Http.HttpEnabled = true
	local base = "http://127.0.0.1:34880/"
	local RS, SG = game:GetService("ReplicatedStorage"), game:GetService("StarterGui")
	local targets = {
		{ file = "Packages.rbxmx", parent = RS },
		{ file = "Shared.rbxmx", parent = RS },
		{ file = "Assets.rbxmx", parent = RS },
		{ file = "Server.rbxmx", parent = game:GetService("ServerScriptService") },
		{ file = "Client.rbxmx", parent = game:GetService("StarterPlayer").StarterPlayerScripts },
		{ file = "Ui.rbxmx", parent = SG, spill = true },
	}
	local report = {}
	for _, t in targets do
		local ok, body = pcall(function() return Http:GetAsync(base .. t.file .. "?t=" .. tostring(os.clock()), true) end)
		if not ok then table.insert(report, t.file .. " FETCH FAIL " .. tostring(body)) continue end
		local ok2, list = pcall(function() return SS:DeserializeInstancesAsync(buffer.fromstring(body)) end)
		if not ok2 or #list == 0 then table.insert(report, t.file .. " DESERIALIZE FAIL " .. tostring(list)) continue end
		local inst = list[1]
		local n = #inst:GetDescendants()
		if t.spill then
			-- the root is only a carrier: its children are the real top-level instances
			for _, child in inst:GetChildren() do
				local old = t.parent:FindFirstChild(child.Name)
				if old then old:Destroy() end
				child.Parent = t.parent
			end
		else
			local old = t.parent:FindFirstChild(inst.Name)
			if old then old:Destroy() end
			inst.Parent = t.parent
		end
		table.insert(report, t.file .. " ok " .. n)
	end
	return table.concat(report, " | ")
end

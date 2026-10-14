-- Fingerprint of an open place: paste the whole file into Studio's command bar
-- (edit mode). Changes nothing; prints one block to Output.
--
-- Run it before and after a Rojo connect. UNMANAGED lines must be identical
-- (Rojo must not touch them). MANAGED lines may change only where disk differs.
-- The first line answers "is this a local file?" (PlaceId and GameId).

local function tally(root)
	local count, names = 0, 0
	for _, d in root:GetDescendants() do
		count += 1
		-- a cheap order-independent checksum of names and classes
		for i = 1, #d.Name do
			names = (names + string.byte(d.Name, i) * i) % 2147483647
		end
		names = (names + #d.ClassName * 131) % 2147483647
	end
	return `{count} descendants, sum {names}`
end

local managedNames = {
	ReplicatedStorage = { Packages = true, Shared = true, Assets = true },
	ServerScriptService = { Server = true },
}

local out = {}
local function add(line)
	table.insert(out, line)
end

add(`[fingerprint] PlaceId={game.PlaceId} GameId={game.GameId} Studio={game:GetService("RunService"):IsStudio()}`)

local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local gameConfig = shared and shared:FindFirstChild("Config") and shared.Config:FindFirstChild("GameConfig")
add(`[fingerprint] BuildStamp={gameConfig and string.match(gameConfig.Source, 'BuildStamp = "([^"]+)"') or "?"}`)

add("[fingerprint] MANAGED")
for serviceName, names in managedNames do
	local s = game:GetService(serviceName)
	for name in names do
		local inst = s:FindFirstChild(name)
		add(`  {serviceName}.{name}: {if inst then tally(inst) else "MISSING"}`)
	end
end
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local client = sps and sps:FindFirstChild("Client")
add(`  StarterPlayerScripts.Client: {if client then tally(client) else "MISSING"}`)
add(`  StarterGui: {tally(game:GetService("StarterGui"))}`)

add("[fingerprint] UNMANAGED")
local unmanaged = {
	"Workspace",
	"Lighting",
	"ServerStorage",
	"TextChatService",
	"SoundService",
	"Teams",
	"Chat",
}
for _, serviceName in unmanaged do
	local ok, s = pcall(function()
		return game:GetService(serviceName)
	end)
	if ok and s then
		for _, c in s:GetChildren() do
			if not c:IsA("Terrain") and not c:IsA("Camera") then
				add(`  {serviceName}.{c.Name} ({c.ClassName}): {tally(c)}`)
			end
		end
	end
end
for _, c in game:GetService("ReplicatedStorage"):GetChildren() do
	if not managedNames.ReplicatedStorage[c.Name] then
		add(`  ReplicatedStorage.{c.Name} ({c.ClassName}): {tally(c)}`)
	end
end

-- one property as text; some (Workspace.SignalBehavior) are not scriptable and
-- throw when read from the command bar, so they print UNREADABLE instead
local function setting(inst, name)
	local ok, value = pcall(function()
		return inst[name]
	end)
	if not ok then
		return "UNREADABLE"
	end
	return if typeof(value) == "EnumItem" then value.Name else tostring(value)
end

add("[fingerprint] SETTINGS")
local ws, sp, lt = workspace, game:GetService("StarterPlayer"), game:GetService("Lighting")
local sg, http = game:GetService("StarterGui"), game:GetService("HttpService")
local settingLines = {
	{ "Workspace", ws, "StreamingEnabled", "SignalBehavior", "StreamingIntegrityMode" },
	{ "StarterPlayer", sp, "CharacterUseJumpPower", "CameraMaxZoomDistance", "CharacterBreakJointsOnDeath" },
	{ "Lighting", lt, "Technology" },
	{ "StarterGui", sg, "ScreenOrientation" },
	{ "HttpService", http, "HttpEnabled" },
}
for _, line in settingLines do
	local parts = { `  {line[1]}` }
	for i = 3, #line do
		table.insert(parts, `{line[i]}={setting(line[2], line[i])}`)
	end
	add(table.concat(parts, " "))
end

print(table.concat(out, "\n"))

--!nonstrict
-- ProtoController - Studio-only measuring hooks for the Wardwood prototype.
-- Does nothing at all outside Studio.
--
-- `perf <seconds>` (DevService) sets the Workspace attribute BonkPerf; this
-- samples the client's frame times for that long and prints one [Perf] line:
-- average and 1%-low frame rate, the worst frame, memory by tag, and what is
-- on screen (map parts, lights, enemy visuals). It works in either map
-- profile, so the MossyWoods baseline is measured with the same code.
--
-- `look cam <n>` sets BonkFace; this turns the camera to the viewpoint's yaw.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ProtoController = Knit.CreateController({ Name = "ProtoController" })

local MEMORY_TAGS = { "GraphicsTexture", "GraphicsMeshParts", "GraphicsParts", "GraphicsTerrain", "GraphicsParticles" }

-- "<number>:<nonce>" -> number
local function leading(value): number?
	if typeof(value) ~= "string" then
		return nil
	end
	return tonumber(string.match(value, "^([%d%.%-]+)"))
end

local function memory(): string
	local out = {}
	local ok, total = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	table.insert(out, `memMb={if ok then math.floor(total) else "?"}`)
	for _, tag in MEMORY_TAGS do
		local okTag, mb = pcall(function()
			return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag[tag])
		end)
		table.insert(out, `{tag}={if okTag then string.format("%.0f", mb) else "?"}`)
	end
	return table.concat(out, " ")
end

local function scene(): string
	local parts, lights, shadowed = 0, 0, 0
	local map = Workspace:FindFirstChild("Map")
	if map then
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			elseif d:IsA("Light") and d.Enabled then
				lights += 1
				if d.Shadows then
					shadowed += 1
				end
			end
		end
	end
	local enemies = 0
	local folder = Workspace:FindFirstChild("Enemies")
	if folder then
		for _, model in folder:GetChildren() do
			-- pooled visuals wait at y -500 (EnemyRenderController:_release)
			local body = if model:IsA("BasePart") then model else model:FindFirstChildWhichIsA("BasePart", true)
			if body and body.Position.Y > -400 then
				enemies += 1
			end
		end
	end
	return `enemyVisuals={enemies} mapParts={parts} lights={lights} shadowed={shadowed}`
end

local function quality(): string
	local ok, level = pcall(function()
		return UserSettings().GameSettings.SavedQualityLevel.Name
	end)
	return if ok then level else "?"
end

function ProtoController:_sample(seconds: number)
	if self._sampling then
		print("[Perf] already sampling")
		return
	end
	self._sampling = true
	local frames = {}
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		table.insert(frames, dt)
		if os.clock() - started >= seconds then
			connection:Disconnect()
			local elapsed = os.clock() - started
			table.sort(frames, function(a, b)
				return a > b
			end)
			local count = #frames
			local low = frames[math.max(1, math.floor(count * 0.01))] or 0
			print(
				`[Perf] profile={Workspace:GetAttribute("BonkMapProfile")} look={Workspace:GetAttribute("BonkLook") or "-"} `
					.. `seconds={string.format("%.1f", elapsed)} frames={count} `
					.. `avgFps={string.format("%.1f", count / elapsed)} low1Fps={string.format("%.1f", if low > 0 then 1 / low else 0)} `
					.. `worstMs={string.format("%.1f", (frames[1] or 0) * 1000)} {scene()} {memory()} quality={quality()}`
			)
			self._sampling = false
		end
	end)
end

function ProtoController:KnitStart()
	if not RunService:IsStudio() then
		return
	end
	Workspace:GetAttributeChangedSignal("BonkPerf"):Connect(function()
		local seconds = leading(Workspace:GetAttribute("BonkPerf"))
		if seconds and seconds > 0 then
			self:_sample(seconds)
		end
	end)
	Workspace:GetAttributeChangedSignal("BonkFace"):Connect(function()
		local yaw = leading(Workspace:GetAttribute("BonkFace"))
		if yaw then
			Knit.GetController("CameraController"):Face(yaw)
		end
	end)
end

return ProtoController

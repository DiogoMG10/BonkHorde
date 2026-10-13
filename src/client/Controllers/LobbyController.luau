--!nonstrict
-- LobbyController - owns the scene behind the main menu: each squad member's
-- hero standing in the spawn clearing, softly out of focus behind them.
--
-- Nobody has a character in the lobby, so these are local copies of the hero
-- models. They follow the roster: pick another hero and the figure changes.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local LobbyController = Knit.CreateController({ Name = "LobbyController" })

-- where each squad slot stands: the first in the middle, the others a step back
local SPOTS = { Vector3.new(0, 0, 0), Vector3.new(-5.5, 0, 2.5), Vector3.new(5.5, 0, 2.5) }

function LobbyController:KnitInit()
	self._figures = {} -- index -> { hero, model, base }
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = Workspace
	self._folder = folder

	local blur = Instance.new("DepthOfFieldEffect")
	blur.Name = "LobbyFocus"
	blur.FocusDistance = 15
	blur.InFocusRadius = 9
	blur.FarIntensity = 0.45
	blur.NearIntensity = 0
	blur.Enabled = false
	blur.Parent = Lighting
	self._blur = blur
end

function LobbyController:_refresh()
	local inLobby = self._state.phase == "Lobby"
	self._blur.Enabled = inLobby
	local wanted = {}
	if inLobby then
		for _, member in self._state.roster.players do
			wanted[member.index] = member.hero
		end
	end
	for index, figure in self._figures do
		if wanted[index] ~= figure.hero then
			figure.model:Destroy()
			self._figures[index] = nil
		end
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local heroes = assets and assets:FindFirstChild("Heroes")
	if not heroes then
		return
	end
	for index, hero in wanted do
		local spot = SPOTS[index]
		if spot and not self._figures[index] then
			local template = heroes:FindFirstChild("Hero" .. hero)
			if template and template:IsA("Model") then
				local model = template:Clone()
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
						part.CanQuery = false
					end
				end
				local _, size = model:GetBoundingBox()
				local ground = self._state:HeightAt(spot.X, spot.Z)
				-- hero models face -Z, which is towards the lobby camera
				local base = CFrame.new(spot.X, ground + size.Y / 2, spot.Z)
				model:PivotTo(base)
				model.Parent = self._folder
				self._figures[index] = { hero = hero, model = model, base = base, half = size.Y / 2, spot = spot, grounded = false }
			end
		end
	end
end

function LobbyController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._state.Changed:Connect(function(key)
		if key == "phase" or key == "roster" then
			self:_refresh()
		end
	end)
	self:_refresh()
	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType = Enum.RaycastFilterType.Include
	self._rayParams.FilterDescendantsInstances = { Workspace.Terrain }

	-- a gentle idle bob so the figures are not statues
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for index, figure in self._figures do
			if not figure.grounded then
				-- the terrain streams in after the menu opens; stand on it once it is there
				local hit = Workspace:Raycast(Vector3.new(figure.spot.X, 300, figure.spot.Z), Vector3.new(0, -400, 0), self._rayParams)
				if hit then
					figure.base = CFrame.new(figure.spot.X, hit.Position.Y + figure.half, figure.spot.Z)
					figure.grounded = true
				end
			end
			local bob = (math.sin(t * 2.2 + index) + 1) * 0.08
			figure.model:PivotTo(figure.base * CFrame.new(0, bob, 0) * CFrame.Angles(0, math.sin(t * 0.8 + index) * 0.08, 0))
		end
	end)
end

return LobbyController

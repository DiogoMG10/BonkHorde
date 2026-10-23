--!nonstrict
-- HubDecorController - Skyhold's far scenery and slow motion (T6/T7), local to
-- this client and only while it is on the island.
--
--   the sky     the sea of clouds under the island, banks drifting at mid
--               height, the far peak and isles on the horizon (Config/SkyholdDecor,
--               drawn from the kit's templates in ReplicatedStorage.SkyholdArt)
--   the portal  its rune monoliths (Orbit1..8) circling the ring, slowly, each
--               with its own bob; faster and drawn in while the portal surges
--               (PortalController's charge, T8)
--
-- Purely cosmetic: nothing here collides, is queried or touches gameplay, and
-- it is all put away while this player is in the Wardwood.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)
local SkyholdDecor = require(ReplicatedStorage.Shared.Config.SkyholdDecor)
local SkyholdGen = require(ReplicatedStorage.Shared.Core.SkyholdGen)

local HubDecorController = Knit.CreateController({ Name = "HubDecorController" })

local DRIFT = 0.004 -- radians a second the cloud sea turns round the island
local ORBIT_SPEED = 0.12 -- radians a second the portal's monoliths travel
local ORBIT_SURGE = 1.6 -- added at the portal's full surge
local ORBIT_RADIUS = 23
local ORBIT_PULL = 2.5 -- studs they draw in at full surge

function HubDecorController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._portal = Knit.GetController("PortalController")
	self._orbit = 0
	local origin = Vector3.new(Skyhold.Origin[1], Skyhold.Origin[2], Skyhold.Origin[3])
	self._origin = origin
	local folder = Instance.new("Folder")
	folder.Name = "SkyholdDecor"
	self._folder = folder
	self._pieces = {} -- { model, base CFrame (island-local), radius, angle }

	task.spawn(function()
		local templates = ReplicatedStorage:WaitForChild("SkyholdArt", 120)
		if not templates then
			return
		end
		for i, entry in SkyholdDecor do
			local template = templates:WaitForChild(entry.asset, 30)
			if template then
				local model = template:Clone()
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						d.CastShadow = false
					end
				end
				if (entry.scale or 1) ~= 1 then
					model:ScaleTo(entry.scale)
				end
				local p = entry.cf
				local radius = math.sqrt(p[1] * p[1] + p[3] * p[3])
				table.insert(self._pieces, {
					model = model,
					y = p[2],
					yaw = math.rad(p[5] or 0),
					radius = radius,
					angle = math.atan2(p[3], p[1]),
					drifts = string.sub(entry.asset, 1, 5) == "Cloud",
				})
				model.Parent = folder
			end
			if i % 8 == 0 then
				task.wait()
			end
		end
	end)

	-- where the portal ring's centre is, for its monoliths
	local plan = SkyholdGen.build(Skyhold)
	local p = Skyhold.Portal
	local h = SkyholdGen.heightAt(plan, p.x, p.z) or 0
	self._ringCentre = origin + Vector3.new(p.x, h + Skyhold.PortalCentreHeight, p.z - 1)

	local function place()
		folder.Parent = if self._state:OnIsland() then Workspace else nil
	end
	self._state.Changed:Connect(function(key)
		if key == "phase" then
			place()
		end
	end)
	place()

	local broken = false
	RunService.RenderStepped:Connect(function(dt)
		if broken or not self._state:OnIsland() then
			return
		end
		local ok, err = pcall(function()
			self:_step(os.clock(), dt)
		end)
		if not ok then
			broken = true
			warn(`[HubDecorController] stopped: {err}`)
		end
	end)
end

function HubDecorController:_step(t: number, dt: number)
	local origin = self._origin
	local charge = self._portal:Charge()
	self._orbit = (self._orbit + dt * (ORBIT_SPEED + ORBIT_SURGE * charge * charge)) % (math.pi * 2)
	local radius = ORBIT_RADIUS - ORBIT_PULL * charge * charge
	for _, piece in self._pieces do
		local a = piece.angle + (if piece.drifts then t * DRIFT else 0)
		local at = origin + Vector3.new(math.cos(a) * piece.radius, piece.y, math.sin(a) * piece.radius)
		piece.model:PivotTo(CFrame.new(at) * CFrame.Angles(0, piece.yaw - (if piece.drifts then t * DRIFT else 0), 0))
	end
	-- the portal's monoliths circle the ring, facing out of it
	local island = Workspace:FindFirstChild("Skyhold")
	local art = island and island:FindFirstChild("Art")
	if art then
		for k = 1, 8 do
			local stone = art:FindFirstChild(`Orbit{k}`)
			if stone and stone:IsA("Model") then
				local a = (k - 1) / 8 * math.pi * 2 + self._orbit
				local bob = math.sin(t * 1.3 + k) * 0.6
				local at = self._ringCentre + Vector3.new(math.cos(a) * radius, math.sin(a) * radius + bob, 0)
				stone:PivotTo(CFrame.new(at) * CFrame.Angles(0, 0, a - math.pi / 2) * CFrame.new(0, -1.6, 0))
			end
		end
	end
end

return HubDecorController

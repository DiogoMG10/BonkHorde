--!nonstrict
-- PrimaryController - owns the attack button for the hero's own weapon.
--
-- It tells the server one thing: whether the button is held, and the yaw the
-- camera is aiming along. It never asks for an attack and never decides a hit;
-- the server fires the weapon on its own cooldown while the button is held.
-- The state is repeated while held, so a server that stops hearing it lets go.
--
-- Mouse and keyboard only for now. The aim is a direction on the ground (the
-- simulation is flat), so it is shown as a marker at the hero's feet rather
-- than a crosshair that would promise aiming up and down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)

local PrimaryController = Knit.CreateController({ Name = "PrimaryController" })

local YAW_STEP = math.rad(2) -- send a new aim once it has moved this far...
local YAW_INTERVAL = 1 / 15 -- ...but no more often than this
local REPEAT_INTERVAL = 0.4 -- and confirm a held button at least this often
local MARKER_DISTANCE = 4.5

function PrimaryController:KnitInit()
	self._down = false -- the physical button
	self._sent = false -- the held state the server was last told
	self._sentYaw = 0
	self._sentAt = 0
end

-- Is this a moment the local hero can attack by hand in?
function PrimaryController:_enabled(): boolean
	local state = self._state
	local me = state.me
	if not me or me.downed or state.paused or not state:IsLive() or not state:Root() then
		return false
	end
	-- a free mouse means a menu or panel is open: clicks belong to it
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		return false
	end
	for _, w in me.weapons do
		if w.primary then
			return true
		end
	end
	return false
end

function PrimaryController:_send(held: boolean, yaw: number, now: number)
	self._sent, self._sentYaw, self._sentAt = held, yaw, now
	self._remote:FireServer(held, yaw)
end

function PrimaryController:_marker(): BasePart
	local marker = self._markerPart
	if not marker or not marker.Parent then
		marker = Instance.new("Part")
		marker.Name = "PrimaryAim"
		marker.Size = Vector3.new(0.7, 0.12, 2.6)
		marker.Material = Enum.Material.Neon
		marker.Color = Color3.fromRGB(255, 244, 214)
		marker.Transparency = 0.45
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.CastShadow = false
		marker.Parent = Workspace
		self._markerPart = marker
	end
	return marker
end

function PrimaryController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._camera = Knit.GetController("CameraController")
	self._remote = Net.client("PrimaryInput")
	if not self._remote then
		return -- no remote: the weapon simply never fires by hand
	end

	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		self._down = true
		-- sent at once, not on the next frame: a click released within the same
		-- frame must still reach the server as a press and then a release
		if self:_enabled() and not self._sent then
			self:_send(true, self._camera:Yaw(), os.clock())
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self._down = false
		end
	end)
	-- the button-up never arrives if the window lost focus while it was down
	UserInputService.WindowFocusReleased:Connect(function()
		self._down = false
	end)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		self._down = false
	end)

	-- after the camera has turned for this frame
	RunService:BindToRenderStep("BonkPrimary", Enum.RenderPriority.Camera.Value + 2, function()
		local now = os.clock()
		local enabled = self:_enabled()
		local yaw = self._camera:Yaw()
		local want = self._down and enabled

		if want ~= self._sent then
			self:_send(want, yaw, now)
		elseif want then
			local turned = math.abs((yaw - self._sentYaw + math.pi) % (2 * math.pi) - math.pi)
			local since = now - self._sentAt
			if (turned >= YAW_STEP and since >= YAW_INTERVAL) or since >= REPEAT_INTERVAL then
				self:_send(true, yaw, now)
			end
		end

		local root = enabled and self._state:Root()
		if root then
			local dx, dz = -math.sin(yaw), -math.cos(yaw)
			local x, z = root.Position.X + dx * MARKER_DISTANCE, root.Position.Z + dz * MARKER_DISTANCE
			local at = Vector3.new(x, self._state:HeightAt(x, z) + 0.25, z)
			self:_marker().CFrame = CFrame.lookAt(at, at + Vector3.new(dx, 0, dz))
		elseif self._markerPart then
			self._markerPart:Destroy()
			self._markerPart = nil
		end
	end)
end

return PrimaryController

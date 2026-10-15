--!nonstrict
-- CameraController - owns the orbit camera and the mouse lock.
--
-- Third person, mouse-look: the camera orbits the hero, movement is relative to
-- it, and the hero faces where they run. In menus and panels the mouse is free.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CameraController = Knit.CreateController({ Name = "CameraController" })

local player = Players.LocalPlayer

function CameraController:KnitInit()
	self._yaw = 0
	self._pitch = math.rad(-18)
	self._uiOpen = 0
	self._lookTouch = nil
	self._stick = Vector2.zero
	self._distance = GameConfig.CameraDistance
end

--- Panels call this so the mouse is released while they are open.
function CameraController:SetUiOpen(key: string, open: boolean)
	self._uiKeys = self._uiKeys or {}
	self._uiKeys[key] = if open then true else nil
	self._uiOpen = 0
	for _ in self._uiKeys do
		self._uiOpen += 1
	end
end

function CameraController:Yaw(): number
	return self._yaw
end

--- Up (+) or down (-) from level, radians. With the yaw this is the camera's
--- look, which passes through the focus point above the hero.
function CameraController:Pitch(): number
	return self._pitch
end

function CameraController:KnitStart()
	self._state = Knit.GetController("StateController")
	local movement = Knit.GetController("MovementController")
	local sens = GameConfig.CameraSensitivity
	local pitchLow, pitchHigh = math.rad(GameConfig.CameraPitchMin), math.rad(GameConfig.CameraPitchMax)

	local function turn(dx: number, dy: number)
		self._yaw -= math.rad(dx * sens)
		self._pitch = math.clamp(self._pitch - math.rad(dy * sens), pitchLow, pitchHigh)
	end

	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
				turn(input.Delta.X, input.Delta.Y)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			self._distance = math.clamp(self._distance - input.Position.Z * 2, 8, 34)
		elseif input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local v = Vector2.new(input.Position.X, -input.Position.Y)
			self._stick = if v.Magnitude > 0.15 then v else Vector2.zero
		elseif input.UserInputType == Enum.UserInputType.Touch and input == self._lookTouch and not processed then
			turn(input.Delta.X * 1.6, input.Delta.Y * 1.6)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.Touch and not processed and not self._lookTouch then
			-- the right half of the screen looks; the left half is the move stick
			local camera = Workspace.CurrentCamera
			if camera and input.Position.X > camera.ViewportSize.X * 0.45 then
				self._lookTouch = input
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == self._lookTouch then
			self._lookTouch = nil
		end
	end)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { Workspace.Terrain }

	RunService:BindToRenderStep("BonkCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		-- a touch wider at bunny-hop speed, so momentum can be felt
		camera.FieldOfView = GameConfig.CameraFOV + movement:SpeedFeel() * GameConfig.SpeedFovKick
		local root = self._state:Root()
		local inRun = root ~= nil and self._state.phase ~= "Lobby"
		local wantLock = inRun and self._uiOpen == 0 and not UserInputService.TouchEnabled
		UserInputService.MouseBehavior = if wantLock then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = not wantLock
		camera.CameraType = Enum.CameraType.Scriptable

		if not inRun then
			-- lobby: look at the squad standing in the clearing, with a slow sway
			local ground = self._state:HeightAt(0, 0)
			local sway = math.sin(os.clock() * 0.25) * 1.2
			local eye = Vector3.new(sway - 1.5, ground + 5.5, -12)
			camera.FieldOfView = 50
			camera.CFrame = CFrame.lookAt(eye, Vector3.new(0, ground + 4.2, 0))
			camera.Focus = CFrame.new(0, ground + 3, 0)
			return
		end

		if self._stick ~= Vector2.zero then
			turn(self._stick.X * 420 * dt, self._stick.Y * 300 * dt)
		end
		local focus = root.Position + Vector3.new(0, GameConfig.CameraHeight, 0)
		local rotation = CFrame.Angles(0, self._yaw, 0) * CFrame.Angles(self._pitch, 0, 0)
		local back = -rotation.LookVector
		local distance = self._distance
		local hit = Workspace:Raycast(focus, back * distance, rayParams)
		if hit then
			distance = math.max((hit.Position - focus).Magnitude - 1, 3)
		end
		camera.CFrame = CFrame.lookAt(focus + back * distance, focus)
		camera.Focus = CFrame.new(focus)
	end)

	player.CharacterAdded:Connect(function()
		self._yaw = 0
		self._pitch = math.rad(-18)
	end)
end

return CameraController

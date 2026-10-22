--!nonstrict
-- CameraController - owns the orbit camera and the mouse lock.
--
-- Third person, mouse-look: the camera orbits the hero, movement is relative to
-- it, and the hero faces where they run. In menus and panels the mouse is free.
--
-- On the island hub (T6/T7) it is the same camera on the same hero, but the
-- mouse stays free for the hub's buttons (the party card, the menu) and the
-- right button held turns the camera, as in most Roblox worlds. A plinth in
-- the Hall of Heroes can borrow it (SetShot): it eases to that framing and
-- back. With no hero yet (the first moments, or between a run and the island)
-- it takes a slow wide look at Skyhold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)

local CameraController = Knit.CreateController({ Name = "CameraController" })

local player = Players.LocalPlayer

function CameraController:KnitInit()
	self._yaw = math.rad(GameConfig.SpawnCameraYaw)
	self._pitch = math.rad(-18)
	self._uiOpen = 0
	self._lookTouch = nil
	self._stick = Vector2.zero
	self._dragging = false -- the right mouse button held, on the island
	self._distance = GameConfig.CameraDistance
	self._shot = nil -- a borrowed framing (CFrame), eased to and from
	self._blend = 0 -- 0 the hero's camera, 1 the borrowed shot
	self._occluders = {} -- what the camera may not pass through, besides the terrain
end

--- Borrow the camera for a framed shot (a hero on a plinth), or give it back
--- with nil. The mouse is free while it is borrowed.
function CameraController:SetShot(cframe: CFrame?)
	self._shot = cframe or self._shot
	self._wantShot = cframe ~= nil
	self:SetUiOpen("shot", cframe ~= nil)
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
			local behaviour = UserInputService.MouseBehavior
			if behaviour == Enum.MouseBehavior.LockCenter or behaviour == Enum.MouseBehavior.LockCurrentPosition then
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
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
			self._dragging = true
		end
		if input.UserInputType == Enum.UserInputType.Touch and not processed and not self._lookTouch then
			-- the right half of the screen looks; the left half is the move stick
			local camera = Workspace.CurrentCamera
			if camera and input.Position.X > camera.ViewportSize.X * 0.45 then
				self._lookTouch = input
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._dragging = false
		end
		if input == self._lookTouch then
			self._lookTouch = nil
		end
	end)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { Workspace.Terrain }
	-- the island's solid scenery (its colliders) stops the camera as the terrain does
	task.spawn(function()
		local island = Workspace:WaitForChild("Skyhold", 60)
		local colliders = island and island:WaitForChild("Colliders", 30)
		if colliders then
			rayParams.FilterDescendantsInstances = { Workspace.Terrain, colliders }
		end
	end)
	local origin = Vector3.new(Skyhold.Origin[1], Skyhold.Origin[2], Skyhold.Origin[3])

	RunService:BindToRenderStep("BonkCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		-- a touch wider at bunny-hop speed, so momentum can be felt
		camera.FieldOfView = GameConfig.CameraFOV + movement:SpeedFeel() * GameConfig.SpeedFovKick
		local root = self._state:Root()
		local hasHero = root ~= nil
		local looking = hasHero and self._uiOpen == 0 and not UserInputService.TouchEnabled
		-- in the Wardwood the mouse aims (locked to the centre); on the island it
		-- is free, and the right button held turns the camera
		local hub = self._state:OnIsland()
		local wantLock = looking and not hub
		UserInputService.MouseBehavior = if wantLock
			then Enum.MouseBehavior.LockCenter
			elseif looking and self._dragging then Enum.MouseBehavior.LockCurrentPosition
			else Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = not wantLock
		camera.CameraType = Enum.CameraType.Scriptable

		if not hasHero then
			-- no hero yet: a slow turn round Skyhold, its portal in the middle
			local t = os.clock() * 0.03
			local focus = origin + Vector3.new(0, 12, -40)
			local eye = focus + Vector3.new(math.sin(t) * 230, 70, math.cos(t) * 230)
			camera.FieldOfView = 55
			camera.CFrame = CFrame.lookAt(eye, focus)
			camera.Focus = CFrame.new(focus)
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
		local follow = CFrame.lookAt(focus + back * distance, focus)
		-- a borrowed shot eases in and out over about half a second
		local goal = if self._wantShot then 1 else 0
		self._blend += math.clamp(goal - self._blend, -dt * 2.4, dt * 2.4)
		local k = self._blend * self._blend * (3 - 2 * self._blend)
		if k > 0 and self._shot then
			camera.CFrame = follow:Lerp(self._shot, k)
			camera.FieldOfView = camera.FieldOfView + (50 - camera.FieldOfView) * k
		else
			camera.CFrame = follow
		end
		camera.Focus = CFrame.new(focus)
	end)

	player.CharacterAdded:Connect(function(character)
		self._pitch = math.rad(-18)
		self._yaw = math.rad(GameConfig.SpawnCameraYaw)
		if self._state:OnIsland() then
			-- on the island: look the way the hero was set down facing
			local root = character:WaitForChild("HumanoidRootPart", 5)
			-- the server sets the hero down on the island a moment after it exists
			local deadline = os.clock() + 2
			while root and root.Parent and os.clock() < deadline and root.Position.Y < origin.Y - 60 do
				task.wait()
			end
			if root then
				local look = root.CFrame.LookVector
				self._yaw = math.atan2(-look.X, -look.Z)
			end
		end
	end)
end

return CameraController

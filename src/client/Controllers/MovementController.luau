--!nonstrict
-- MovementController - owns local movement feel: slide, bunny hop and extra jumps.
--
-- Movement is client-owned, as on any Roblox character. The server sets the base
-- speed and jump height from the hero's stats (the BaseSpeed and ExtraJumps
-- attributes on the character); this controller layers the slide and the extra
-- jumps on top. Holding jump re-jumps on landing, which is the bunny hop.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)

local MovementController = Knit.CreateController({ Name = "MovementController" })

local player = Players.LocalPlayer

function MovementController:KnitInit()
	self._slideHeld = false
	self._sliding = false
	self._slideMult = 1
	self._slideFor = 0
	self._slideDir = Vector3.zAxis
	self._jumpsUsed = 0
end

function MovementController:IsSliding(): boolean
	return self._sliding
end

function MovementController:KnitStart()
	self._state = Knit.GetController("StateController")

	ContextActionService:BindAction("BonkSlide", function(_, inputState)
		self._slideHeld = inputState == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("BonkSlide", "Slide")
	ContextActionService:SetPosition("BonkSlide", UDim2.new(1, -150, 1, -90))

	UserInputService.JumpRequest:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or character:GetAttribute("Downed") then
			return
		end
		local state = humanoid:GetState()
		local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
		local extra = character:GetAttribute("ExtraJumps") or 0
		if airborne and self._jumpsUsed < extra and root.AssemblyLinearVelocity.Y < 22 then
			self._jumpsUsed += 1
			local v = root.AssemblyLinearVelocity
			local up = math.sqrt(2 * Workspace.Gravity * humanoid.JumpHeight)
			root.AssemblyLinearVelocity = Vector3.new(v.X, up, v.Z)
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)

	local function hook(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid then
			return
		end
		self._jumpsUsed = 0
		self._sliding = false
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
				self._jumpsUsed = 0
			end
		end)
	end
	player.CharacterAdded:Connect(hook)
	if player.Character then
		task.spawn(hook, player.Character)
	end

	-- after the default control module has set the move direction for this frame
	RunService:BindToRenderStep("BonkMovement", Enum.RenderPriority.Input.Value + 5, function(dt)
		self:_frame(dt)
	end)
end

function MovementController:_frame(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	local base = character:GetAttribute("BaseSpeed") or GameConfig.PlayerWalkSpeed
	if base <= 0 then
		self._sliding = false
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

	if not self._sliding then
		if self._slideHeld and grounded and flat.Magnitude > base * 0.5 then
			self._sliding = true
			self._slideMult = GameConfig.SlideBoost
			self._slideFor = 0
			self._slideDir = flat.Unit
		else
			if humanoid.WalkSpeed ~= base then
				humanoid.WalkSpeed = base
			end
			return
		end
	end

	-- sliding: speed bleeds off on the flat and builds going downhill
	self._slideFor += dt
	local dx, dz, steep = MapGen.downhill(self._state.map, root.Position.X, root.Position.Z)
	local along = (dx * self._slideDir.X + dz * self._slideDir.Z) * steep -- >0 when heading downhill
	if grounded then
		self._slideMult += (along * GameConfig.SlideDownhillAccel / base - GameConfig.SlideDecayPerSecond * (1 - math.clamp(along * 2, 0, 1))) * dt
		-- let the slope pull the slide round towards the fall line
		if steep > 0.12 then
			local pull = Vector3.new(dx, 0, dz) * steep * 1.5 * dt
			local dir = self._slideDir + pull
			if dir.Magnitude > 0.01 then
				self._slideDir = dir.Unit
			end
		end
	end
	self._slideMult = math.clamp(self._slideMult, 0.5, GameConfig.SlideMaxMultiplier)

	local done = (not self._slideHeld and self._slideFor >= GameConfig.SlideMinSeconds) or self._slideMult <= 0.8
	if done then
		self._sliding = false
		humanoid.WalkSpeed = base
		return
	end
	humanoid.WalkSpeed = base * self._slideMult
	humanoid:Move(self._slideDir, false)
end

return MovementController

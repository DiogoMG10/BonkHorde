--!nonstrict
-- MovementController - owns local movement feel: slide, bunny hop and extra jumps.
--
-- Movement is client-owned, as on any Roblox character. The server sets the base
-- speed and jump height from the hero's stats (the BaseSpeed and ExtraJumps
-- attributes on the character); this controller layers the slide, the extra
-- jumps and bunny-hop momentum on top. Holding jump re-jumps on landing.
--
-- Bunny hop (rules in Core/Hop): each jump made within a moment of landing,
-- while running, raises a speed multiplier a step towards a cap; staying down
-- or stopping bleeds it away. In the air the hero steers a remembered velocity
-- by turning its heading at a limited rate with the speed kept, so momentum
-- carries between hops, strafing curves the run, and a reversal takes a moment. A slide starts at least as fast as the
-- hop it came from, a jump out of a slide carries the slide's speed, and a
-- slide that ends hands its speed back to bleed off.
--
-- The speed is put on the body, not only asked of the Humanoid: in the air the
-- steered velocity is written to the root, and just after landing a hero who
-- is slower than the hop's speed is brought up to it. Asking (WalkSpeed) alone
-- left the body behind, and the gain never showed.
--
-- Studio only: `hop` in Workspace.BonkDev shows real and intended speed on
-- screen and prints every jump to the Output (temporary, for the M2.B playtest).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Hop = require(ReplicatedStorage.Shared.Core.Hop)
local MapGen = require(ReplicatedStorage.Shared.Core.MapGen)

local MovementController = Knit.CreateController({ Name = "MovementController" })

local player = Players.LocalPlayer

local HOP: Hop.Config = {
	gain = GameConfig.HopGain,
	cap = GameConfig.HopMaxMultiplier,
	window = GameConfig.HopWindow,
	minSpeed = GameConfig.HopMinSpeed,
	groundDecay = GameConfig.HopGroundDecay,
	stopDecay = GameConfig.HopStopDecay,
	overCapDecay = GameConfig.HopOverCapDecay,
	carryMax = GameConfig.SlideMaxMultiplier,
	keep = GameConfig.HopKeep,
}
local AIR: Hop.Air = {
	accel = GameConfig.AirAccel,
	brake = GameConfig.AirBrake,
	turn = math.rad(GameConfig.AirTurnRate),
	reverse = GameConfig.AirReverseBrake,
	reverseDot = math.cos(math.rad(GameConfig.AirReverseAngle)),
}

-- Studio-only diagnostics for the M2.B playtest (DevService `hop`)
local function debugOn(): boolean
	return RunService:IsStudio() and Workspace:GetAttribute("BonkHopDebug") == true
end

function MovementController:KnitInit()
	self._slideHeld = false
	self._sliding = false
	self._slideMult = 1
	self._slideFor = 0
	self._slideDir = Vector3.zAxis
	self._jumpsUsed = 0
	self._hop = Hop.new()
	self._groundFor = 0 -- seconds on the ground since the last landing
	self._airVel = nil -- the horizontal velocity being steered while airborne
	self._speedFeel = 0 -- 0 at base speed, 1 at the hop cap, smoothed (camera FOV)
	self._jumpedAt = -math.huge -- os.clock() of the last jump from the ground
end

--- 0 at the hero's base speed, rising to 1 at the hop cap: for the camera.
function MovementController:SpeedFeel(): number
	return self._speedFeel
end

-- Forget all momentum: respawn, a freeze (pause, level-up), downed.
function MovementController:_still()
	Hop.reset(self._hop)
	self._sliding = false
	self._airVel = nil
	self._groundFor = 0
end

-- A jump left the ground (not an extra jump in the air).
function MovementController:_takeoff(character: Model, humanoid: Humanoid, root: BasePart)
	local base = character:GetAttribute("BaseSpeed") or GameConfig.PlayerWalkSpeed
	if base <= 0 then
		return
	end
	local v = root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local carry = nil
	if self._sliding then
		-- the slide becomes the hop: its speed goes with it, and it ends here
		carry = self._slideMult
		self._sliding = false
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local chained = Hop.takeoff(self._hop, HOP, self._groundFor, flat.Magnitude, base, moving, carry)
	self._airVel = flat
	if debugOn() then
		print(
			string.format(
				"[Hop] jump %s  real %.1f  intended %.1f  x%.2f  hops %d%s  (ground %.2fs)",
				if chained then "CHAIN" else "start",
				flat.Magnitude,
				base * self._hop.mult,
				self._hop.mult,
				self._hop.hops,
				if carry then string.format("  from slide x%.2f", carry) else "",
				self._groundFor
			)
		)
	end
	self._groundFor = 0 -- the floor check can lag the jump by a frame
	self._jumpedAt = os.clock()
end

-- Studio-only: one line of real vs intended speed in the corner of the screen.
function MovementController:_debugLabel(text: string?)
	local label = self._debugText
	if not text then
		if label then
			label.Parent:Destroy()
			self._debugText = nil
		end
		return
	end
	if not label then
		local gui = Instance.new("ScreenGui")
		gui.Name = "BonkHopDebug"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 100
		label = Instance.new("TextLabel")
		label.BackgroundTransparency = 0.4
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.Code
		label.TextSize = 16
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.AnchorPoint = Vector2.new(0, 1)
		label.Position = UDim2.new(0, 12, 1, -120)
		label.Size = UDim2.fromOffset(520, 24)
		label.Parent = gui
		gui.Parent = player:WaitForChild("PlayerGui")
		self._debugText = label
	end
	label.Text = text
end

-- the slide key, or the touch slide button (which the overlay reports on PlayerGui)
function MovementController:_slideWanted(): boolean
	if self._slideHeld then
		return true
	end
	local gui = player:FindFirstChildOfClass("PlayerGui")
	return gui ~= nil and gui:GetAttribute("BonkSlideHeld") == true
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
		self:_still()
		local root = character:WaitForChild("HumanoidRootPart", 5)
		humanoid.StateChanged:Connect(function(old, new)
			if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
				self._jumpsUsed = 0
			elseif
				new == Enum.HumanoidStateType.Jumping
				and old ~= Enum.HumanoidStateType.Freefall
				and old ~= Enum.HumanoidStateType.Jumping
				and root
				and player.Character == character
			then
				self:_takeoff(character, humanoid, root) -- from the ground: a hop, maybe
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
	if base <= 0 or root.Anchored then
		self:_still() -- frozen or downed: nothing carries over to the moment it ends
		self._speedFeel = 0
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	self._groundFor = if grounded then self._groundFor + dt else 0
	local feel = math.clamp((flat.Magnitude / base - 1) / math.max(HOP.cap - 1, 0.01), 0, 1)
	self._speedFeel += (feel - self._speedFeel) * math.min(1, dt * 6)
	if debugOn() then
		local intended = base * (if self._sliding then self._slideMult else self._hop.mult)
		self:_debugLabel(
			string.format(
				" %s  real %5.1f  intended %5.1f  (base %.0f, x%.2f, hops %d)",
				if self._sliding then "SLIDE " elseif grounded then "GROUND" else "AIR   ",
				flat.Magnitude,
				intended,
				base,
				intended / base,
				self._hop.hops
			)
		)
	elseif self._debugText then
		self:_debugLabel(nil)
	end

	if not self._sliding then
		-- Not on the frame or two after a jump, while the floor check still says
		-- grounded: a held slide key would otherwise grab the hop and reset it.
		local settled = grounded and os.clock() - self._jumpedAt > GameConfig.HopSlideAfterJump
		if self:_slideWanted() and settled and flat.Magnitude > base * 0.5 then
			self._sliding = true
			-- at least as fast as the hop it came from (never the two multiplied)
			self._slideMult = Hop.slideStart(self._hop, GameConfig.SlideBoost)
			self._slideFor = 0
			self._slideDir = flat.Unit
			self._airVel = nil
			-- start at that speed on the body too, so entering a slide never dips
			local at = self._slideDir * base * self._slideMult
			if flat.Magnitude < at.Magnitude then
				root.AssemblyLinearVelocity = Vector3.new(at.X, velocity.Y, at.Z)
			end
		else
			self:_hopFrame(dt, humanoid, root, base, flat, grounded)
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

	local done = (not self:_slideWanted() and self._slideFor >= GameConfig.SlideMinSeconds) or self._slideMult <= 0.8
	if done then
		-- hand the slide's speed back to bleed off, rather than snapping to a walk
		self._sliding = false
		Hop.slideEnd(self._hop, HOP, self._slideMult)
		humanoid.WalkSpeed = base * self._hop.mult
		return
	end
	humanoid.WalkSpeed = base * self._slideMult
	humanoid:Move(self._slideDir, false)
end

-- Not sliding: run at the hop's speed on the ground, steer momentum in the air.
function MovementController:_hopFrame(dt: number, humanoid: Humanoid, root: BasePart, base: number, flat: Vector3, grounded: boolean)
	local hop = self._hop
	local input = humanoid.MoveDirection -- this frame's stick or keys, set by the control module
	input = Vector3.new(input.X, 0, input.Z)
	local moving = input.Magnitude > 0.1
	local v = root.AssemblyLinearVelocity

	-- On the ground inside the hop window (just landed, chain alive) the hop is
	-- steered exactly as in the air: a landing with only A held must not snap
	-- the run sideways. Past the window, ordinary ground control takes over.
	local carrying = moving and hop.mult > 1 and self._groundFor <= HOP.window
	if grounded then
		Hop.ground(hop, HOP, dt, self._groundFor, moving)
		if not carrying then
			self._airVel = nil
			local speed = base * hop.mult
			if humanoid.WalkSpeed ~= speed then
				humanoid.WalkSpeed = speed
			end
			return
		end
	else
		Hop.air(hop, HOP, dt)
	end

	local air = self._airVel or flat
	-- something stopped the hero (a wall, a crowd): steer from what is real
	if flat.Magnitude < air.Magnitude * 0.8 then
		air = flat
	end
	local dir = if moving then input.Unit else Vector3.zero
	local ax, az = Hop.airStep(air.X, air.Z, dir.X, dir.Z, base * hop.mult, AIR, dt)
	air = Vector3.new(ax, 0, az)
	self._airVel = air
	-- the body really moves at the steered velocity; the Humanoid is asked for
	-- the same, so it does not pull against it
	root.AssemblyLinearVelocity = Vector3.new(air.X, v.Y, air.Z)
	if air.Magnitude > 0.5 then
		humanoid.WalkSpeed = air.Magnitude
		humanoid:Move(air.Unit, false)
	elseif humanoid.WalkSpeed ~= base then
		humanoid.WalkSpeed = base
	end
end

return MovementController

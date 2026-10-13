--!nonstrict
-- HeroAnimController - owns the hero poses the stock walk cycle does not cover:
-- attack swings, casts and throws, the slide, the downed kneel and the cheer.
--
-- Roblox's own Animate script still runs Idle, Run, Jump, Fall and Land. These
-- are layered on top by writing Motor6D.Transform after the animator has run,
-- so they need no uploaded animation and work on every hero the same way.
-- Every client plays them for every hero, driven by the events the server
-- already sends, so nothing new crosses the network.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local Vfx = require(script.Parent.Parent.Vfx)

local HeroAnimController = Knit.CreateController({ Name = "HeroAnimController" })

local player = Players.LocalPlayer
local rad = math.rad

-- how long each one-shot lasts, in seconds
local ACTIONS = { AttackSwing = 0.3, AttackCast = 0.34, AttackThrow = 0.36, Land = 0.18, PortalStep = 0.6 }
local P_FIREBALL, P_BONE, P_NANA, P_ROCKET = 1, 2, 3, 4
local MAX_TWIST = rad(100) -- how far the upper body turns to follow a swing

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 0 -> 1 -> 0 over the life of an action, fast in and slow out
local function arc(t: number): number
	if t < 0.3 then
		return ease(t / 0.3)
	end
	return 1 - ease((t - 0.3) / 0.7)
end

function HeroAnimController:KnitInit()
	self._rigs = {} -- character -> { joints, action, startedAt }
end

function HeroAnimController:_rig(character: Model)
	local rig = self._rigs[character]
	if rig then
		return rig
	end
	local joints = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then -- newer avatars use AnimationConstraints
			joints[d.Name] = d
		end
	end
	if not joints.Waist then
		return nil -- not an R15 body yet
	end
	rig = { joints = joints, action = nil, startedAt = 0, root = character:FindFirstChild("HumanoidRootPart") }
	self._rigs[character] = rig
	character.Destroying:Connect(function()
		self._rigs[character] = nil
	end)
	return rig
end

--- Start a one-shot on the hero in squad slot `index`. `aimX`, `aimZ` is the
--- direction an attack was made in, when it has one: the body turns to it.
function HeroAnimController:Play(index: number, action: string, aimX: number?, aimZ: number?)
	local root = self._state:RootOfIndex(index)
	local character = root and root.Parent
	local rig = character and self:_rig(character)
	if rig and ACTIONS[action] then
		rig.action = action
		rig.startedAt = os.clock()
		rig.aimX, rig.aimZ = aimX, aimZ
	end
end

local function set(joints, name: string, cf: CFrame)
	local j = joints[name]
	if j then
		j.Transform = j.Transform * cf
	end
end

function HeroAnimController:_pose(rig, slot: number?, now: number)
	local joints = rig.joints
	local action = rig.action
	if action then
		local t = (now - rig.startedAt) / ACTIONS[action]
		if t >= 1 then
			rig.action = nil
		elseif action == "AttackSwing" then
			-- wind up to the right, cut across to the left, torso following the blade
			local sweep = ease(t) * 2 - 1
			local lift = arc(t)
			-- The swing goes where the attack went, not where the legs are running:
			-- the upper body turns towards it and back, and the hero is not rotated.
			-- A waist only turns so far, so a swing aimed behind is cut at the limit.
			local turn = 0
			local root = rig.root
			if rig.aimX and rig.aimZ and root and root.Parent then
				local v = root.CFrame:VectorToObjectSpace(Vector3.new(rig.aimX, 0, rig.aimZ))
				turn = math.clamp(math.atan2(-v.X, -v.Z), -MAX_TWIST, MAX_TWIST) * lift
			end
			set(joints, "Waist", CFrame.Angles(0, turn + rad(-38) * sweep, 0))
			set(joints, "RightShoulder", CFrame.Angles(rad(80) * lift, rad(-50) * sweep, rad(-20) * lift))
			set(joints, "RightElbow", CFrame.Angles(rad(25) * lift, 0, 0))
			set(joints, "LeftShoulder", CFrame.Angles(rad(-20) * lift, 0, rad(-18) * lift))
		elseif action == "AttackCast" then
			local a = arc(t)
			set(joints, "Waist", CFrame.Angles(rad(-8) * a, rad(-14) * a, 0))
			set(joints, "RightShoulder", CFrame.Angles(rad(95) * a, 0, 0))
			set(joints, "LeftShoulder", CFrame.Angles(rad(60) * a, 0, rad(-25) * a))
			set(joints, "LeftElbow", CFrame.Angles(rad(30) * a, 0, 0))
		elseif action == "AttackThrow" then
			-- arm back over the shoulder, then whip forward
			local back = if t < 0.35 then ease(t / 0.35) else 1 - ease((t - 0.35) / 0.25)
			local forward = if t < 0.35 then 0 elseif t < 0.6 then ease((t - 0.35) / 0.25) else 1 - ease((t - 0.6) / 0.4)
			set(joints, "Waist", CFrame.Angles(rad(12) * forward, rad(22) * back - rad(26) * forward, 0))
			set(joints, "RightShoulder", CFrame.Angles(rad(170) * back + rad(70) * forward, 0, 0))
			set(joints, "RightElbow", CFrame.Angles(rad(60) * back, 0, 0))
		elseif action == "Land" then
			local a = arc(t)
			set(joints, "Root", CFrame.new(0, -0.35 * a, 0))
			set(joints, "RightHip", CFrame.Angles(rad(28) * a, 0, 0))
			set(joints, "LeftHip", CFrame.Angles(rad(28) * a, 0, 0))
			set(joints, "RightKnee", CFrame.Angles(rad(-40) * a, 0, 0))
			set(joints, "LeftKnee", CFrame.Angles(rad(-40) * a, 0, 0))
		elseif action == "PortalStep" then
			local a = 1 - ease(t)
			set(joints, "Root", CFrame.new(0, 0, -1.2 * a) * CFrame.Angles(rad(-14) * a, 0, 0))
			set(joints, "RightShoulder", CFrame.Angles(rad(30) * a, 0, 0))
			set(joints, "LeftShoulder", CFrame.Angles(rad(-30) * a, 0, 0))
		end
	end

	local squad = slot and self._downed[slot]
	if squad then
		-- collapsed on one knee, head down
		set(joints, "Root", CFrame.new(0, -1.1, 0))
		set(joints, "Waist", CFrame.Angles(rad(-32), 0, 0))
		set(joints, "Neck", CFrame.Angles(rad(-28), 0, 0))
		set(joints, "RightHip", CFrame.Angles(rad(80), 0, 0))
		set(joints, "RightKnee", CFrame.Angles(rad(-95), 0, 0))
		set(joints, "LeftHip", CFrame.Angles(rad(-10), 0, 0))
		set(joints, "LeftKnee", CFrame.Angles(rad(-85), 0, 0))
		set(joints, "RightShoulder", CFrame.Angles(rad(35), 0, 0))
		set(joints, "LeftShoulder", CFrame.Angles(rad(20), 0, rad(-10)))
	elseif self._cheer then
		-- weapon overhead and a small hop
		local hop = math.abs(math.sin(now * 6)) * 0.5
		set(joints, "Root", CFrame.new(0, hop, 0))
		set(joints, "RightShoulder", CFrame.Angles(rad(170), 0, rad(-12)))
		set(joints, "LeftShoulder", CFrame.Angles(rad(150) + math.sin(now * 12) * rad(10), 0, rad(18)))
	elseif slot == self._mySlot and self._movement and self._movement:IsSliding() then
		-- feet first, leaning back, one hand down
		set(joints, "Root", CFrame.new(0, -0.9, 0) * CFrame.Angles(rad(32), 0, 0))
		set(joints, "RightHip", CFrame.Angles(rad(62), 0, 0))
		set(joints, "LeftHip", CFrame.Angles(rad(48), 0, 0))
		set(joints, "LeftKnee", CFrame.Angles(rad(-30), 0, 0))
		set(joints, "RightShoulder", CFrame.Angles(rad(-40), 0, rad(-25)))
		set(joints, "LeftShoulder", CFrame.Angles(rad(-55), 0, rad(20)))
	end
end

function HeroAnimController:KnitStart()
	local state = Knit.GetController("StateController")
	self._state = state
	self._downed = {}
	self._cheer = false
	pcall(function()
		self._movement = Knit.GetController("MovementController")
	end)

	local function on(name: string, handler: (...any) -> ())
		local remote = Net.client(name)
		if remote then
			remote.OnClientEvent:Connect(function(...)
				pcall(handler, ...)
			end)
		end
	end

	on("Fx", function(name, index, _x, _y, _z, dx, dz)
		if name == "Slash" then
			self:Play(index, "AttackSwing", dx, dz)
		elseif name == "Axe" then
			self:Play(index, "AttackThrow")
		elseif name == "Frost" then
			self:Play(index, "AttackCast")
		end
	end)

	on("Proj", function(op, _id, kind, owner)
		if op ~= "spawn" then
			return
		end
		if kind == P_FIREBALL or kind == P_ROCKET then
			self:Play(owner, "AttackCast")
		elseif kind == P_BONE or kind == P_NANA then
			self:Play(owner, "AttackThrow")
		end
	end)

	state.Changed:Connect(function(key)
		if key == "squad" then
			table.clear(self._downed)
			for _, entry in state.squad do
				for _, member in state.roster.players do
					if member.userId == entry.userId then
						self._downed[member.index] = entry.downed == true
					end
				end
			end
		elseif key == "phase" then
			self._cheer = state.phase == "Victory"
			if state.phase == "Intro" then
				for _, member in state.roster.players do
					self:Play(member.index, "PortalStep")
				end
			end
		end
	end)

	local function character(model: Model)
		local humanoid = model:WaitForChild("Humanoid", 5)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.StateChanged:Connect(function(_old, new)
				if new == Enum.HumanoidStateType.Landed then
					self:Play(state:MyIndex(), "Land")
					local root = model:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") then
						pcall(Vfx.burst, "DustPuff", root.Position - Vector3.new(0, 2.6, 0))
					end
				end
			end)
		end
	end
	player.CharacterAdded:Connect(character)
	if player.Character then
		task.spawn(character, player.Character)
	end

	-- Stepped runs after the animator has written this frame's pose, so what is
	-- multiplied in here lands on top of the walk cycle instead of under it
	RunService.Stepped:Connect(function()
		local now = os.clock()
		self._mySlot = state:MyIndex()
		if self._movement and self._movement:IsSliding() and now - (self._dustAt or 0) > 0.1 then
			self._dustAt = now
			local root = state:Root()
			if root then
				pcall(Vfx.burst, "DustPuff", root.Position - Vector3.new(0, 2.6, 0), { count = 1 })
			end
		end
		for _, member in state.roster.players do
			local root = state:RootOfIndex(member.index)
			local model = root and root.Parent
			local rig = model and self:_rig(model)
			if rig then
				self:_pose(rig, member.index, now)
			end
		end
	end)
end

return HeroAnimController

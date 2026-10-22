--!nonstrict
-- HeroDress - turns a player's avatar into their BonkHorde hero: hides the
-- avatar, welds each piece of ReplicatedStorage.Assets.Heroes.Hero<Id> to the
-- matching limb and the hero's starting weapon to the right hand, so the
-- avatar's own animations move the hero. Used for the run (PlayerStateService)
-- and on the island hub (HubService), where choosing another hero at a plinth
-- re-dresses the same character in place, mid-stride.
--
-- The welds are measured from the rig's rest pose (its Motor6D offsets), not
-- from wherever an animation has the limbs this frame, so a hero put on while
-- walking sits exactly as one put on standing still.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)

local HeroDress = {}

-- which avatar limb each piece of a hero model rides on
local HERO_LIMB = {
	Body = "UpperTorso",
	Head = "Head",
	ArmL = "LeftUpperArm",
	ArmR = "RightUpperArm",
	LegL = "LeftUpperLeg",
	LegR = "RightUpperLeg",
}

local DRESS_TAG = "BonkHeroPart" -- attribute on everything a dressing adds

--- The humanoid as the game wants it: HP lives in PlayerStateService, never in
--- the Humanoid, and nobody shows Roblox's name and health bar.
function HeroDress.prepare(character: Model, humanoid: Humanoid)
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.UseJumpPower = false
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local health = character:FindFirstChild("Health")
	if health then
		health:Destroy() -- Roblox's regen script
	end
end

-- a part's CFrame in the rig's rest pose: the root's, then each joint's offsets
-- down the chain, without the animation's Transform
local function restOf(character: Model, part: BasePart, root: BasePart, depth: number?): CFrame
	if part == root or (depth or 0) > 8 then
		return root.CFrame
	end
	for _, motor in character:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part1 == part and motor.Part0 then
			return restOf(character, motor.Part0, root, (depth or 0) + 1) * motor.C0 * motor.C1:Inverse()
		end
	end
	return part.CFrame
end

--- Take off whatever hero the character wears.
function HeroDress.undress(character: Model)
	for _, child in character:GetChildren() do
		if child:GetAttribute(DRESS_TAG) then
			child:Destroy()
		end
	end
end

--- Dress `character` as `heroId` (replacing any hero it wore). Returns the
--- root's height above the feet, or nil when the hero has no model (the avatar
--- then stays as it is).
function HeroDress.dress(character: Model, heroId: string): number?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Heroes") and assets.Heroes:FindFirstChild("Hero" .. heroId)
	if not humanoid or not root or not template then
		return nil
	end
	HeroDress.undress(character)
	humanoid:RemoveAccessories()
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			if not d:GetAttribute(DRESS_TAG) then
				d.Transparency = 1
			end
		elseif d:IsA("Decal") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("CharacterMesh") then
			d:Destroy()
		end
	end

	local rootRest = root.CFrame
	local hero = template:Clone()
	local _, size = hero:GetBoundingBox()
	hero:ScaleTo(GameConfig.HeroHeight / math.max(size.Y, 0.1))
	local _, scaled = hero:GetBoundingBox()
	-- stand the model where the avatar stands: feet on the floor under the root
	local rootHeight = humanoid.HipHeight + root.Size.Y / 2
	local feet = rootRest.Position.Y - rootHeight
	hero:PivotTo(CFrame.new(rootRest.Position.X, feet + scaled.Y / 2, rootRest.Position.Z) * rootRest.Rotation)
	for _, part in hero:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "Root" then
			local limb = character:FindFirstChild(HERO_LIMB[part.Name] or "UpperTorso") or root
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part:SetAttribute(DRESS_TAG, true)
			local weld = Instance.new("Weld")
			weld.Part0 = limb
			weld.Part1 = part
			weld.C0 = restOf(character, limb, root):ToObjectSpace(part.CFrame)
			weld.Parent = part
			-- never under a limb's own name: a second "Head" in the character
			-- becomes the humanoid's head, and undressing it (a re-dress at a
			-- plinth) would kill the character
			part.Name = "Hero" .. part.Name
			part.Parent = character
		end
	end
	hero:Destroy()

	local def = Roster.Heroes[heroId]
	local weaponTemplate = def and assets:FindFirstChild("Weapons") and assets.Weapons:FindFirstChild("Weapon" .. def.weapon)
	local hand = character:FindFirstChild("RightHand")
	local mesh = weaponTemplate and weaponTemplate:FindFirstChild("Body")
	if hand and mesh then
		local weapon = mesh:Clone()
		weapon.Name = "HeldWeapon"
		weapon.Anchored = false
		weapon.CanCollide = false
		weapon.CanQuery = false
		weapon.CanTouch = false
		weapon.Massless = true
		weapon:SetAttribute(DRESS_TAG, true)
		local weld = Instance.new("Weld")
		weld.Part0 = hand
		weld.Part1 = weapon
		-- gripped a third of the way up, pointing forward and up out of the fist
		weld.C0 = CFrame.new(0, -0.2, -weapon.Size.Y * 0.3) * CFrame.Angles(math.rad(-90), 0, 0)
		weld.Parent = weapon
		weapon.Parent = character
	end
	character:SetAttribute("Hero", heroId)
	return rootHeight
end

return HeroDress

--!nonstrict
-- Showcase - the M3.B art kit standing in the real Wardwood, for a person to
-- judge from the game's own camera before anything wider is replaced.
--
-- In the Old Grove's clearing every tree, rock and column the kit has an
-- answer for is shown as its new model instead (Core/ArtShowcase plans it):
-- the same spot, turn and size, and the old prop's collider kept (only its
-- look is hidden), so the layout, the paths and how enemies walk round it are
-- exactly what was approved. Low 3D grass covers the grassy ground there.
-- `art off` in BonkDev puts the old props back to compare, `art on` the new,
-- `art goto` stands you at its edge.
--
-- Studio only for now (Config/Wardwood.ArtShowcase); nothing is uploaded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ArtShowcase = require(ReplicatedStorage.Shared.Core.ArtShowcase)

local ArtKit = require(script.Parent.ArtKit)

local Showcase = {}
Showcase.Centre = ArtShowcase.Centre
Showcase.Radius = ArtShowcase.Radius

-- ------------------------------------------------------------------ in the engine

local HIDDEN = "ArtShowcaseHidden"

local function hideOld(map: Instance, props: { [number]: boolean }, hide: boolean)
	for _, model in map:GetChildren() do
		local i = model:GetAttribute("Prop")
		if i and props[i] then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					if hide then
						if d:GetAttribute(HIDDEN) == nil then
							d:SetAttribute(HIDDEN, d.Transparency)
						end
						d.Transparency = 1
					else
						local was = d:GetAttribute(HIDDEN)
						if was ~= nil then
							d.Transparency = was
							d:SetAttribute(HIDDEN, nil)
						end
					end
				end
			end
		end
	end
end

local function frame(p): CFrame
	local at = CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, p.yaw, 0)
	if p.up then
		local up = Vector3.new(p.up[1], p.up[2], p.up[3]).Unit
		local axis = Vector3.new(0, 1, 0):Cross(up)
		if axis.Magnitude > 1e-4 then
			local tilt = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(up.Y, -1, 1)))
			at = CFrame.new(p.x, p.y, p.z) * tilt * CFrame.Angles(0, p.yaw, 0)
		end
	end
	return at
end

local active = false

--- Show the new art (true) or the old props (false). Yields while the kit's
--- meshes are built the first time.
function Showcase.set(world, on: boolean)
	active = on
	local map = Workspace:FindFirstChild("Map")
	local old = Workspace:FindFirstChild("WardwoodArt")
	if old then
		old:Destroy()
	end
	local plan = ArtShowcase.plan(world)
	local props = {}
	for _, p in plan do
		if p.prop then
			props[p.prop] = true
		end
	end
	if not on then
		if map then
			hideOld(map, props, false)
		end
		return 0
	end
	local folder = Instance.new("Folder")
	folder.Name = "WardwoodArt"
	local placed, started = 0, os.clock()
	for _, p in plan do
		if not active then
			folder:Destroy()
			return 0
		end
		if ArtKit.place(p.asset, frame(p), p.scale, folder) then
			placed += 1
		end
	end
	folder.Parent = Workspace
	if map then
		hideOld(map, props, true)
	end
	print(`[Showcase] {placed} pieces of M3.B art in the Old Grove ({string.format("%.1f", os.clock() - started)}s)`)
	return placed
end

function Showcase.active(): boolean
	return active
end

return Showcase

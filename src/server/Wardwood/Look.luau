--!nonstrict
-- Wardwood Look - applies one of the prototype's lighting conditions.
--
-- Runs on the server after MapService has built the normal lighting, and
-- overwrites it from Config/WardwoodLook, so the place file carries no
-- hand-set lighting and every client sees the same condition. Switching is
-- what `look light <name>` does.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WardwoodLook = require(ReplicatedStorage.Shared.Config.WardwoodLook)

local Look = {}

local function ensure(parent: Instance, className: string): Instance
	local found = parent:FindFirstChildOfClass(className)
	if not found then
		found = Instance.new(className)
		found.Parent = parent
	end
	return found
end

local function assign(target: Instance, values)
	for key, value in values do
		target[key] = value
	end
end

--- Names of the available conditions, sorted.
function Look.names(): { string }
	local out = {}
	for name in WardwoodLook.Looks do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

--- Apply a condition by name. Returns false and a reason for an unknown name.
function Look.apply(name: string): (boolean, string)
	local look = WardwoodLook.Looks[name]
	if not look then
		return false, `unknown look "{name}" (have {table.concat(Look.names(), ", ")})`
	end
	for key, value in look do
		if typeof(value) ~= "table" then
			Lighting[key] = value
		end
	end
	assign(ensure(Lighting, "Atmosphere"), look.Atmosphere)
	assign(ensure(Lighting, "ColorCorrectionEffect"), look.Grade)
	assign(ensure(Lighting, "BloomEffect"), look.Bloom)
	assign(ensure(Lighting, "SunRaysEffect"), look.SunRays)
	local terrain = Workspace.Terrain
	assign(ensure(terrain, "Clouds"), look.Clouds)
	local colors = WardwoodLook.Colors
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, colors.Grass)
	terrain:SetMaterialColor(Enum.Material.Ground, colors.Ground)
	terrain:SetMaterialColor(Enum.Material.Rock, colors.Rock)
	Workspace:SetAttribute("BonkLook", name)
	return true, name
end

return Look

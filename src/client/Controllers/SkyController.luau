--!nonstrict
-- SkyController - the sky over this player, wherever they are (T6/T7).
--
-- The server built the sky's instances once and never touches them again
-- (shared/Look); every client puts on its own sky: Skyhold's on the island
-- hub, the one its run drew (the Phase message) in the Wardwood. So a party
-- starting a run never changes the light for the players left on the island.
-- `sky <name>` in Workspace.BonkDev (attribute BonkSky) overrides both in a
-- Studio playtest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Look = require(ReplicatedStorage.Shared.Look)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)

local SkyController = Knit.CreateController({ Name = "SkyController" })

function SkyController:KnitStart()
	local state = Knit.GetController("StateController")
	local worn = nil
	local function apply()
		local name = Workspace:GetAttribute("BonkSky")
		if typeof(name) ~= "string" or not Look.Skies[name] then
			name = if state:OnIsland() then Skyhold.Sky else (state.sky or "golden")
		end
		if name ~= worn then
			worn = name
			pcall(Look.sky, name)
		end
	end
	state.Changed:Connect(function(key)
		if key == "phase" then
			apply()
		end
	end)
	Workspace:GetAttributeChangedSignal("BonkSky"):Connect(apply)
	-- the Lighting instances may still be arriving from the server
	local Lighting = game:GetService("Lighting")
	Lighting.ChildAdded:Connect(function()
		worn = nil
		apply()
	end)
	apply()
end

return SkyController

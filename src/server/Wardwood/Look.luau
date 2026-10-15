--!nonstrict
-- Wardwood Look - the light over the Wardwood: a late golden afternoon. Warm
-- low sun, cool teal shade and distance, a soft haze that gives depth without
-- fogging the fight. Built in code so the place file carries no hand-set
-- lighting to drift out of step.
--
-- Rules learned the hard way (roblox-map skill): Atmosphere needs a Sky;
-- ColorShift_Top is additive, so it stays small; ambient stays near neutral so
-- blue shade on blue stone does not compound; the place's own effects are
-- cleared by class, not by name.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Wardwood = require(ReplicatedStorage.Shared.Config.Wardwood)

local Look = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Terrain materials, by World.surface key: which Roblox material and its tint
-- (Config/Wardwood, shared with the offline previews).
Look.Surfaces = {}
for key, s in Wardwood.Surfaces do
	Look.Surfaces[key] = { (Enum.Material :: any)[s.material], rgb(s.color[1], s.color[2], s.color[3]) }
end

function Look.apply()
	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("PostEffect") or child:IsA("Clouds") then
			child:Destroy()
		end
	end
	Lighting.ClockTime = 16.6
	Lighting.GeographicLatitude = 41
	Lighting.Brightness = 2.6
	Lighting.Ambient = rgb(80, 92, 98)
	Lighting.OutdoorAmbient = rgb(122, 136, 136)
	Lighting.ColorShift_Top = rgb(16, 10, 2)
	Lighting.ColorShift_Bottom = rgb(0, 8, 12)
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.25
	Lighting.ExposureCompensation = 0.15
	Lighting.ShadowSoftness = 0.3
	Lighting.GlobalShadows = true

	local sky = Instance.new("Sky")
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 9
	sky.StarCount = 0
	sky.Parent = Lighting

	local haze = Instance.new("Atmosphere")
	haze.Density = 0.24
	haze.Offset = 0.22
	haze.Color = rgb(206, 200, 178) -- warm air in the sun
	haze.Decay = rgb(98, 140, 150) -- teal in the distance and the shade
	haze.Glare = 0.35
	haze.Haze = 1.15
	haze.Parent = Lighting

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Saturation = 0.1
	grade.Contrast = 0.08
	grade.TintColor = rgb(255, 246, 232)
	grade.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 24
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.55
	rays.Parent = Lighting

	local terrain = Workspace.Terrain
	local oldClouds = terrain:FindFirstChildOfClass("Clouds")
	if oldClouds then
		oldClouds:Destroy()
	end
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.48
	clouds.Density = 0.5
	clouds.Color = rgb(255, 238, 218)
	clouds.Parent = terrain

	for _, entry in Look.Surfaces do
		terrain:SetMaterialColor(entry[1], entry[2])
	end
	pcall(function()
		-- short enough that enemies, gems and coins are never lost in it (0.35 hid
		-- enemies in the first Studio playtest), long enough to stir in the meadows
		terrain.GrassLength = 0.15
	end)
	pcall(function()
		terrain.WaterColor = rgb(52, 120, 128)
	end)
end

return Look

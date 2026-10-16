--!nonstrict
-- Wardwood Look - the light over the Wardwood. Built in code so the place file
-- carries no hand-set lighting to drift out of step.
--
-- Skies to compare (Config/Wardwood.Sky picks the one a run starts with, and
-- stays golden until a person picks otherwise; `sky <name>` in
-- Workspace.BonkDev switches live in a Studio playtest):
--   golden   the default: a late golden afternoon, warm low sun, cool teal
--            shade and distance, a soft haze that gives depth without fogging
--            the fight
--   clear    a bright fair-weather day: the sun higher, clean blue air, big
--            soft white clouds, the greens at their freshest
--   dusk     the magical hour: the sun low and amber, a warm glowing horizon
--            under a cool violet upper sky, peach clouds, longer shadows
--   sunset   the sun on the horizon and the whole sky burning orange: hot
--            haze, copper clouds, long shadows, shade kept warm and readable
--   night    moonlight: a high moon and stars, blue-grey ambient lifted well
--            above true dark so the horde, gems and coins still read, and the
--            lanterns and neon glow
--   enchanted  a fantasy twilight just after sundown: violet-teal air, lilac
--            clouds, the first stars, a soft magical bloom
-- Each moves the sun (or moon) with the clock, so shadows agree with the sky.
-- None uses a texture: Roblox's own sky, atmosphere and clouds, nothing uploaded.
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

Look.Skies = {
	golden = {
		clock = 16.6,
		brightness = 2.6,
		ambient = rgb(80, 92, 98),
		outdoor = rgb(122, 136, 136),
		shiftTop = rgb(16, 10, 2),
		shiftBottom = rgb(0, 8, 12),
		exposure = 0.15,
		sunSize = 16,
		haze = { density = 0.24, offset = 0.22, color = rgb(206, 200, 178), decay = rgb(98, 140, 150), glare = 0.35, haze = 1.15 },
		grade = { saturation = 0.1, contrast = 0.08, tint = rgb(255, 246, 232) },
		bloom = 0.4,
		rays = 0.06,
		clouds = { cover = 0.48, density = 0.5, color = rgb(255, 238, 218) },
	},
	clear = {
		clock = 14.3,
		brightness = 3,
		ambient = rgb(90, 98, 106),
		outdoor = rgb(132, 142, 150),
		shiftTop = rgb(8, 7, 4),
		shiftBottom = rgb(0, 6, 12),
		exposure = 0.05,
		sunSize = 12,
		haze = { density = 0.2, offset = 0.12, color = rgb(198, 214, 228), decay = rgb(104, 142, 172), glare = 0.12, haze = 0.6 },
		grade = { saturation = 0.14, contrast = 0.06, tint = rgb(250, 252, 255) },
		bloom = 0.3,
		rays = 0.03,
		clouds = { cover = 0.62, density = 0.55, color = rgb(255, 255, 255) },
	},
	dusk = {
		clock = 17.65,
		brightness = 2.4,
		ambient = rgb(88, 88, 110),
		outdoor = rgb(126, 124, 150),
		shiftTop = rgb(30, 14, 2),
		shiftBottom = rgb(6, 8, 22),
		exposure = 0.2,
		sunSize = 21,
		haze = { density = 0.3, offset = 0.3, color = rgb(238, 178, 130), decay = rgb(92, 98, 152), glare = 0.8, haze = 1.6 },
		grade = { saturation = 0.16, contrast = 0.12, tint = rgb(255, 238, 226) },
		bloom = 0.6,
		rays = 0.12,
		clouds = { cover = 0.55, density = 0.6, color = rgb(255, 206, 178) },
	},
	sunset = {
		clock = 17.95,
		brightness = 2.3,
		ambient = rgb(104, 82, 74),
		outdoor = rgb(150, 112, 92),
		shiftTop = rgb(46, 18, 0),
		shiftBottom = rgb(14, 6, 4),
		exposure = 0.25,
		sunSize = 24,
		haze = { density = 0.32, offset = 0.34, color = rgb(255, 156, 92), decay = rgb(178, 84, 62), glare = 1.2, haze = 2.2 },
		grade = { saturation = 0.2, contrast = 0.1, tint = rgb(255, 228, 204) },
		bloom = 0.7,
		rays = 0.18,
		clouds = { cover = 0.52, density = 0.62, color = rgb(255, 160, 112) },
	},
	night = {
		clock = 0.6, -- the moon high in the south-east, its light from the same side
		brightness = 2.2,
		ambient = rgb(70, 80, 112),
		outdoor = rgb(84, 96, 136),
		shiftTop = rgb(0, 4, 14),
		shiftBottom = rgb(0, 2, 10),
		exposure = 0.45,
		sunSize = 12,
		moonSize = 13,
		stars = 3000,
		haze = { density = 0.28, offset = 0.1, color = rgb(64, 76, 108), decay = rgb(28, 34, 62), glare = 0, haze = 0.5 },
		grade = { saturation = -0.08, contrast = 0.12, tint = rgb(214, 226, 255) },
		bloom = 0.9, -- lanterns, gems and neon carry the night
		rays = 0,
		clouds = { cover = 0.42, density = 0.5, color = rgb(92, 104, 136) },
	},
	enchanted = {
		clock = 18.35,
		brightness = 2.2,
		ambient = rgb(96, 88, 124),
		outdoor = rgb(112, 120, 164),
		shiftTop = rgb(22, 0, 30),
		shiftBottom = rgb(0, 10, 18),
		exposure = 0.35,
		sunSize = 18,
		moonSize = 10,
		stars = 1200,
		haze = { density = 0.3, offset = 0.24, color = rgb(176, 146, 222), decay = rgb(60, 124, 146), glare = 0.6, haze = 1.4 },
		grade = { saturation = 0.24, contrast = 0.1, tint = rgb(242, 234, 255) },
		bloom = 0.8,
		rays = 0.08,
		clouds = { cover = 0.5, density = 0.55, color = rgb(232, 184, 255) },
	},
}

local current: string? = nil

--- The sky in use.
function Look.current(): string?
	return current
end

--- Switch to one of Look.Skies; returns false for an unknown name. Needs
--- Look.apply to have built the sky's instances first.
function Look.sky(name: string): boolean
	local preset = Look.Skies[name]
	if not preset then
		return false
	end
	current = name
	Lighting.ClockTime = preset.clock
	Lighting.Brightness = preset.brightness
	Lighting.Ambient = preset.ambient
	Lighting.OutdoorAmbient = preset.outdoor
	Lighting.ColorShift_Top = preset.shiftTop
	Lighting.ColorShift_Bottom = preset.shiftBottom
	Lighting.ExposureCompensation = preset.exposure
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.SunAngularSize = preset.sunSize
		sky.MoonAngularSize = preset.moonSize or 9
		sky.StarCount = preset.stars or 0
	end
	local haze = Lighting:FindFirstChildOfClass("Atmosphere")
	if haze then
		haze.Density = preset.haze.density
		haze.Offset = preset.haze.offset
		haze.Color = preset.haze.color
		haze.Decay = preset.haze.decay
		haze.Glare = preset.haze.glare
		haze.Haze = preset.haze.haze
	end
	local grade = Lighting:FindFirstChild("WardwoodGrade")
	if grade then
		grade.Saturation = preset.grade.saturation
		grade.Contrast = preset.grade.contrast
		grade.TintColor = preset.grade.tint
	end
	local bloom = Lighting:FindFirstChild("WardwoodBloom")
	if bloom then
		bloom.Intensity = preset.bloom
	end
	local rays = Lighting:FindFirstChild("WardwoodRays")
	if rays then
		rays.Intensity = preset.rays
	end
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Cover = preset.clouds.cover
		clouds.Density = preset.clouds.density
		clouds.Color = preset.clouds.color
	end
	return true
end

function Look.apply()
	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("PostEffect") or child:IsA("Clouds") then
			child:Destroy()
		end
	end
	Lighting.GeographicLatitude = 41
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.25
	Lighting.ShadowSoftness = 0.3
	Lighting.GlobalShadows = true

	local sky = Instance.new("Sky")
	sky.CelestialBodiesShown = true
	sky.MoonAngularSize = 9
	sky.StarCount = 0
	sky.Parent = Lighting

	Instance.new("Atmosphere").Parent = Lighting

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "WardwoodGrade"
	grade.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "WardwoodBloom"
	bloom.Size = 24
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "WardwoodRays"
	rays.Spread = 0.55
	rays.Parent = Lighting

	local terrain = Workspace.Terrain
	local oldClouds = terrain:FindFirstChildOfClass("Clouds")
	if oldClouds then
		oldClouds:Destroy()
	end
	Instance.new("Clouds").Parent = terrain

	if not Look.sky(Wardwood.Sky) then
		Look.sky("golden")
	end

	for _, entry in Look.Surfaces do
		terrain:SetMaterialColor(entry[1], entry[2])
	end
	pcall(function()
		-- Roblox's shortest: a meadow's texture without hiding enemies, gems or
		-- coins (0.35 hid enemies in the first Studio playtest, and 0.15 still
		-- now and then hid the small ones)
		terrain.GrassLength = 0.1
	end)
	pcall(function()
		terrain.WaterColor = rgb(52, 120, 128)
	end)
end

return Look

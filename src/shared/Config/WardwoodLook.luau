--!strict
-- WardwoodLook - colours, lights and lighting conditions for the Wardwood
-- prototype. Kept apart from Config/Wardwood because Color3 exists only in the
-- engine; the layout config stays loadable by the headless specs.
--
-- EVERY value below is a starting point for tuning in Studio, not a validated
-- specification.

local WardwoodLook = {
	-- blockout colours (greybox stand-ins for the material library)
	Colors = {
		Bark = Color3.fromRGB(62, 46, 40),
		Canopy = Color3.fromRGB(47, 76, 54),
		CanopyLight = Color3.fromRGB(64, 98, 62),
		Stone = Color3.fromRGB(111, 120, 118),
		RuinStone = Color3.fromRGB(122, 126, 120),
		Moss = Color3.fromRGB(78, 118, 56),
		Fern = Color3.fromRGB(70, 112, 60),
		Ember = Color3.fromRGB(255, 154, 60),
		Rune = Color3.fromRGB(255, 170, 90),
		Grass = Color3.fromRGB(86, 128, 52),
		Ground = Color3.fromRGB(96, 78, 56),
		Rock = Color3.fromRGB(104, 112, 112),
	},

	-- warm lights on the landmark; counts and shadows are what the test measures
	BrazierLight = { Brightness = 3, Range = 40, Shadows = true },
	WardLight = { Brightness = 1.5, Range = 16, Shadows = false },

	-- lighting conditions compared in the A/B. Applied on the server so every
	-- client sees the same one. Starting points for tuning only.
	DefaultLook = "golden",
	Looks = {
		golden = {
			ClockTime = 16.9,
			GeographicLatitude = 41,
			Brightness = 3,
			Ambient = Color3.fromRGB(64, 84, 92),
			OutdoorAmbient = Color3.fromRGB(112, 124, 118),
			ColorShift_Top = Color3.fromRGB(255, 214, 160),
			ColorShift_Bottom = Color3.fromRGB(40, 70, 80),
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.2,
			ExposureCompensation = 0.2,
			ShadowSoftness = 0.35,
			Atmosphere = {
				Density = 0.3,
				Offset = 0.12,
				Color = Color3.fromRGB(196, 176, 150),
				Decay = Color3.fromRGB(70, 118, 124),
				Glare = 0.6,
				Haze = 1.8,
			},
			Grade = { Saturation = 0.08, Contrast = 0.12, TintColor = Color3.fromRGB(255, 244, 228) },
			Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.4 },
			SunRays = { Intensity = 0.1, Spread = 0.6 },
			Clouds = { Cover = 0.45, Density = 0.6, Color = Color3.fromRGB(255, 226, 196) },
		},
		teal = {
			ClockTime = 18.4,
			GeographicLatitude = 41,
			Brightness = 1.6,
			Ambient = Color3.fromRGB(70, 104, 114),
			OutdoorAmbient = Color3.fromRGB(82, 124, 138),
			ColorShift_Top = Color3.fromRGB(150, 196, 210),
			ColorShift_Bottom = Color3.fromRGB(30, 60, 72),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.25,
			ExposureCompensation = 0.4,
			ShadowSoftness = 0.5,
			Atmosphere = {
				Density = 0.38,
				Offset = 0.15,
				Color = Color3.fromRGB(84, 150, 164),
				Decay = Color3.fromRGB(38, 88, 108),
				Glare = 0.2,
				Haze = 2.2,
			},
			Grade = { Saturation = 0.04, Contrast = 0.15, TintColor = Color3.fromRGB(218, 240, 246) },
			Bloom = { Intensity = 0.6, Size = 26, Threshold = 1.2 },
			SunRays = { Intensity = 0.04, Spread = 0.5 },
			Clouds = { Cover = 0.55, Density = 0.7, Color = Color3.fromRGB(120, 170, 190) },
		},
	},
}

return WardwoodLook

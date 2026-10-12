--!strict
-- Bonk Horde - client entry point.
-- Boots Knit (Controllers). Keep this file to the boot only; logic lives in Controllers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

Knit.AddControllers(script.Controllers)

Knit.Start()
	:andThen(function()
		-- BUILD STAMP - see the note in the server boot.
		print(`[Bonk Horde] Client started - BUILD {GameConfig.BuildStamp}`)
	end)
	:catch(warn)

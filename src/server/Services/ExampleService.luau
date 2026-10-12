--!strict
-- ExampleService - the shape every server Service takes.
--
-- The server owns game state. Anything a client sends is a REQUEST, validated
-- here before it changes anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)

local ExampleService = Knit.CreateService({
	Name = "ExampleService",
})

function ExampleService:KnitInit()
	-- Create remotes in Init so they exist before any client asks for them.
	self._ping = Net.server("Ping")
end

function ExampleService:KnitStart()
	self._ping.OnServerEvent:Connect(function(player: Player, payload: unknown)
		-- Validate every client input. Type first, then range, then ownership.
		if type(payload) ~= "string" or #payload > 64 then
			return
		end
		print(`[ExampleService] {player.Name} says {payload}`)
	end)
end

return ExampleService

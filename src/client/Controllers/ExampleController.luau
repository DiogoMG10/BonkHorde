--!strict
-- ExampleController - the shape every client Controller takes.
--
-- Clients own input and display. They ask; they never decide.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)

local ExampleController = Knit.CreateController({
	Name = "ExampleController",
})

function ExampleController:KnitStart()
	local ping = Net.client("Ping")
	if not ping then
		-- Fail inert: one dead feature, not a dead client.
		return
	end
	ping:FireServer("hello")
end

return ExampleController

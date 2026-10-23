--!nonstrict
-- ControlLock - holds the hero still for a moment of presentation (the portal
-- crossing, T8) and always gives the controls back.
--
-- Each reason is held with a deadline, so a lock that is never released by its
-- owner still lets go on its own; the controls come back the frame the last
-- reason goes. While held, Roblox's own controls are disabled (no walking or
-- jumping input) and MovementController keeps the hero standing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ControlLock = {}

local held: { [string]: number } = {} -- reason -> when it lets go on its own (os.clock)
local locked = false
local controls = nil

local function getControls()
	if controls then
		return controls
	end
	local ok, result = pcall(function()
		local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 2)
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		return module and require(module):GetControls()
	end)
	controls = if ok then result else nil
	return controls
end

local function apply()
	local now = os.clock()
	local any = false
	for reason, untilAt in held do
		if now >= untilAt then
			held[reason] = nil
		else
			any = true
		end
	end
	if any == locked then
		return
	end
	locked = any
	local c = getControls()
	if c then
		pcall(function()
			if any then
				c:Disable()
			else
				c:Enable()
			end
		end)
	end
end

--- Hold the hero still for `reason` (at most `seconds`), or let go of it.
function ControlLock.set(reason: string, on: boolean, seconds: number?)
	held[reason] = if on then os.clock() + (seconds or 4) else nil
	apply()
end

--- Is the hero being held still?
function ControlLock.held(): boolean
	return locked
end

-- deadlines run out here even when nobody calls again
RunService.Heartbeat:Connect(function()
	if locked then
		apply()
	end
end)

return ControlLock

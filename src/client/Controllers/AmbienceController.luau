--!nonstrict
-- AmbienceController - the small living touches on the Wardwood's scenery.
--
-- The server builds the scenery and tags the parts that should live
-- (Wardwood/Builder): WWFlame (braziers, lamps), WWRune (ward runes), WWGlow
-- (the Moonwell, glowcaps), WWMist (the foot of the falls). Here they get their
-- fire, their motes, their spray and a slow
-- breathing pulse. Purely cosmetic and local: nothing here can touch gameplay,
-- and with streaming on, parts that stream in later are dressed as they arrive.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Vfx = require(script.Parent.Parent.Vfx)

local AmbienceController = Knit.CreateController({ Name = "AmbienceController" })

local PULSE_HZ = 15 -- how often the rune pulse is updated

function AmbienceController:KnitInit()
	self._runes = {} -- part -> { base transparency, phase }
end

-- Emitters go on an upright host at the part, not on the part itself: an
-- ember bed is a cylinder rolled on its side, and an emitter on it would fire
-- its flames sideways. The host is parented to the part, so it streams out with it.
local function upright(name: string, part: BasePart, width: number, height: number?): BasePart?
	local ok, host = pcall(Vfx.place, name, CFrame.new(part.Position), width, part)
	if not ok then
		return nil
	end
	host.Size = Vector3.new(width, height or width, width)
	return host
end

function AmbienceController:_flame(part: BasePart)
	-- a brazier's ember bed is wide and flat; a lamp is small
	local wide = math.max(part.Size.Y, part.Size.Z) > 2.5
	if wide then
		upright("BrazierFlame", part, math.max(part.Size.Y, part.Size.Z) * 0.6, 0.4)
	else
		upright("LampFlame", part, 0.6)
	end
end

function AmbienceController:_rune(part: BasePart)
	self._runes[part] = { part.Transparency, (part.Position.X + part.Position.Z) * 0.37 }
	if part.Size.Magnitude > 1 then
		upright("RuneMotes", part, 1, math.max(part.Size.Y, 1))
	end
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(game) then
			self._runes[part] = nil
		end
	end)
end

function AmbienceController:_glow(part: BasePart)
	if part.Name == "MoonwellGlow" then
		-- a flat sheet of motes over the whole pond
		upright("MoonMotes", part, part.Size.Y * 0.9, 0.5)
	end
end

function AmbienceController:_mist(part: BasePart)
	upright("FallsMist", part, 7, 1)
end

function AmbienceController:_forestMist(part: BasePart)
	pcall(Vfx.attach, "ForestMist", part)
end

function AmbienceController:KnitStart()
	local function watch(tag: string, fn)
		for _, inst in CollectionService:GetTagged(tag) do
			if inst:IsA("BasePart") then
				fn(self, inst)
			end
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			if inst:IsA("BasePart") then
				fn(self, inst)
			end
		end)
	end
	watch("WWFlame", self._flame)
	watch("WWRune", self._rune)
	watch("WWGlow", self._glow)
	watch("WWMist", self._mist)
	watch("WWForestMist", self._forestMist)

	-- the runes breathe: a slow brightening and dimming, each on its own beat
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / PULSE_HZ then
			return
		end
		acc = 0
		local t = os.clock()
		for part, state in self._runes do
			local wave = 0.5 + 0.5 * math.sin(t * 1.4 + state[2])
			part.Transparency = math.clamp(state[1] + 0.35 * wave, 0, 0.9)
		end
	end)
end

return AmbienceController

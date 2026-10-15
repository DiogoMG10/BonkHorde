--!nonstrict
-- AmbienceController - the small living touches on the Wardwood's scenery.
--
-- The server builds the scenery and tags the parts that should live
-- (Wardwood/Builder): WWFlame (braziers, lamps), WWRune (ward runes), WWGlow
-- (the Moonwell, glowcaps). Here they get their fire, their motes and a slow
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

function AmbienceController:_flame(part: BasePart)
	-- a brazier's ember bed is wide and flat; a lamp is small
	local wide = math.max(part.Size.Y, part.Size.Z) > 2.5
	pcall(Vfx.attach, if wide then "BrazierFlame" else "LampFlame", part)
end

function AmbienceController:_rune(part: BasePart)
	self._runes[part] = { part.Transparency, (part.Position.X + part.Position.Z) * 0.37 }
	if part.Size.Magnitude > 1 then
		pcall(Vfx.attach, "RuneMotes", part)
	end
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(game) then
			self._runes[part] = nil
		end
	end)
end

function AmbienceController:_glow(part: BasePart)
	if part.Name == "MoonwellGlow" then
		pcall(Vfx.attach, "MoonMotes", part)
	end
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

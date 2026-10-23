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
	local size = part.Size
	if size.Y >= size.X and size.Y >= 12 then
		-- a tall falling sheet (Skyhold's): the spray where it breaks up at the
		-- bottom, wide enough to swallow its frayed end, and foam down its face
		local cf = part.CFrame
		local foot = (cf * CFrame.new(0, -size.Y / 2 + size.Y * 0.08, size.Z / 2 - 0.5)).Position
		local ok, host = pcall(Vfx.place, "FallsMist", CFrame.new(foot), 1, part)
		if ok and host then
			host.Size = Vector3.new(size.X * 1.2, size.Y * 0.12, size.X * 1.2)
			-- puffs as big as the water is wide
			local k = math.max(size.X / 6, 1)
			for _, e in host:GetChildren() do
				if e:IsA("ParticleEmitter") then
					e.Size = NumberSequence.new(2.6 * k, 7 * k)
					e.Rate = 10 + 4 * k
				end
			end
		end
		self:_flow(part)
		return
	end
	upright("FallsMist", part, 7, 1)
end

-- foam streaking down a fall from its lip: the part is the falling sheet, its
-- height the drop, its lip at the top of its back face
function AmbienceController:_flow(part: BasePart)
	local size = part.Size
	if size.Y < size.X or size.Y < 12 then
		return -- not a tall fall
	end
	local cf = part.CFrame
	local outward = -cf.LookVector -- the sheet curves out along its +z
	local lip = (cf * CFrame.new(0, size.Y / 2 - 0.5, -size.Z / 2 + 0.6)).Position
	local ok, host = pcall(Vfx.place, "FallsFlow", CFrame.new(lip), 1, part)
	if not ok or not host then
		return
	end
	host.Size = Vector3.new(math.max(size.X * 0.55, 1), 0.5, math.max(size.X * 0.55, 1))
	-- lifetime: long enough to fall the whole drop, from the emitter's speed and pull
	local v0, a = 17, 26
	local t = (-v0 + math.sqrt(v0 * v0 + 2 * a * size.Y)) / a
	for _, e in host:GetChildren() do
		if e:IsA("ParticleEmitter") then
			e.EmissionDirection = Enum.NormalId.Bottom
			e.SpreadAngle = Vector2.new(4, 4)
			e.Lifetime = NumberRange.new(t * 0.92, t)
			-- out with the sheet as it falls
			e.Acceleration = Vector3.new(0, -a, 0) + outward * (2 * size.Z / math.max(t * t, 0.1))
			e.Rate = math.clamp(size.X * 1.6, 6, 22)
		end
	end
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

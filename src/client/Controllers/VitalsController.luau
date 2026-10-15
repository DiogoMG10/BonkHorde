--!nonstrict
-- VitalsController - how the local hero's health feels: a flash at the screen
-- edges when a hit lands, a red vignette that grows as HP runs low, and a small
-- health bar at the hero's feet so nobody has to look at the corner of the
-- screen mid-fight.
--
-- Everything here reads HP the server already sends (PlayerState, Hurt). The
-- edges live in the Hud's HurtFlash frame; the bar is a BillboardGui in
-- PlayerGui adorned to the hero. Cosmetic only: it decides nothing.
--
-- Low HP is a share of max HP, never an absolute number:
--   above 30%   nothing stays on screen
--   30% to 15%  a faint red edge that deepens as HP falls
--   below 15%   critical: deeper again, with a slow pulse

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local UiKit = require(script.Parent.Parent.UiKit)

local VitalsController = Knit.CreateController({ Name = "VitalsController" })

local player = Players.LocalPlayer

local LOW = 0.30 -- the share of max HP where the vignette starts
local CRITICAL = 0.15 -- ...and where it starts to pulse
local HIT_RED = Color3.fromHex("#E5121B")
local LOW_RED = Color3.fromHex("#B00010")
local TRAIL = Color3.fromHex("#FFE2A8")
local BAR_BACK = Color3.fromHex("#101512")
local BAR_FILL = Color3.fromHex("#E8323A")
local BAR_SHIELD = Color3.fromHex("#4FC6FF")

-- The four edges of the screen, each a gradient from opaque at the edge to
-- clear towards the middle. Corners overlap a little, which reads as a vignette.
local function edges(parent: Instance, name: string)
	local root = Instance.new("Frame")
	root.Name = name
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ZIndex = 1
	root.Parent = parent
	local list = {}
	-- side, gradient rotation (where transparency 0 sits), anchor, position
	for _, side in
		{
			{ "Top", 90, Vector2.new(0, 0), UDim2.fromScale(0, 0) },
			{ "Bottom", -90, Vector2.new(0, 1), UDim2.fromScale(0, 1) },
			{ "Left", 0, Vector2.new(0, 0), UDim2.fromScale(0, 0) },
			{ "Right", 180, Vector2.new(1, 0), UDim2.fromScale(1, 0) },
		}
	do
		local frame = Instance.new("Frame")
		frame.Name = side[1]
		frame.AnchorPoint = side[3]
		frame.Position = side[4]
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = HIT_RED
		frame.BackgroundTransparency = 1
		frame.ZIndex = 1
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = side[2]
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = frame
		frame.Parent = root
		table.insert(list, frame)
	end
	return { root = root, frames = list, depth = -1, alpha = -1 }
end

-- How far in from the edge the gradient reaches, as a share of screen height.
local function setDepth(set, depth: number)
	if math.abs(set.depth - depth) < 0.002 then
		return
	end
	set.depth = depth
	local side = depth * 9 / 16 -- the same thickness on the long sides of a 16:9 screen
	for _, frame in set.frames do
		if frame.Name == "Top" or frame.Name == "Bottom" then
			frame.Size = UDim2.fromScale(1, depth)
		else
			frame.Size = UDim2.fromScale(side, 1)
		end
	end
end

local function setLook(set, colour: Color3, alpha: number)
	alpha = math.clamp(alpha, 0, 1)
	if math.abs(set.alpha - alpha) < 0.004 and set.colour == colour then
		return
	end
	set.alpha, set.colour = alpha, colour
	set.root.Visible = alpha > 0.004
	for _, frame in set.frames do
		frame.BackgroundColor3 = colour
		frame.BackgroundTransparency = 1 - alpha
	end
end

function VitalsController:KnitInit()
	self._hit = nil -- { colour, strength, at, duration }
	self._low = 0 -- the vignette's smoothed strength
	self._crit = 0 -- the pulse's smoothed share
	self._predHp = nil -- HP after a hit, until PlayerState catches up
	self._predAt = 0
	self._shown = 0 -- the bar's drawn fraction
	self._trail = 0 -- the lagging chunk behind it
	self._trailHold = 0
end

function VitalsController:KnitStart()
	self._state = Knit.GetController("StateController")
	UiKit.safe("VitalsController", function()
		self:_start()
	end)
end

function VitalsController:_start()
	local hud = UiKit.gui("Hud")
	local flash = hud and UiKit.find(hud, "HurtFlash")
	if flash and flash:IsA("GuiObject") then
		flash.BackgroundTransparency = 1
		self._lowSet = edges(flash, "LowHp")
		self._hitSet = edges(flash, "Hit")
		setLook(self._lowSet, LOW_RED, 0)
		setLook(self._hitSet, HIT_RED, 0)
	end
	self:_buildBar()

	local hurt = Net.client("Hurt")
	if hurt then
		hurt.OnClientEvent:Connect(function(amount, dodged, shieldBroke, hpLost)
			UiKit.safe("VitalsController.Hurt", function()
				self:_onHurt(tonumber(amount) or 0, dodged == true, shieldBroke == true, tonumber(hpLost))
			end)
		end)
	end

	local broken = false
	RunService.RenderStepped:Connect(function(dt)
		if broken then
			return
		end
		local ok, err = pcall(function()
			self:_frame(dt)
		end)
		if not ok then
			broken = true -- one warning, not one per frame
			warn(`[VitalsController] stopped: {err}`)
		end
	end)
end

function VitalsController:_onHurt(amount: number, dodged: boolean, shieldBroke: boolean, hpLost: number?)
	if dodged or amount <= 0 then
		return
	end
	local me = self._state.me
	local maxHp = if me and me.maxHp and me.maxHp > 0 then me.maxHp else 100
	local lost = hpLost or amount -- an older server sends no split: treat it all as HP
	if lost > 0 then
		-- HP: red, a little stronger for a bigger bite
		local bite = math.clamp(lost / maxHp * 4, 0, 1)
		self._hit = { colour = HIT_RED, strength = 0.42 + 0.33 * bite, at = os.clock(), duration = 0.45, depth = 0.15 }
		if me then
			self._predHp = math.max(0, (self._predHp or me.hp) - lost)
			self._predAt = os.clock()
		end
	else
		-- shield only: a thinner, quicker blue edge
		self._hit = {
			colour = UiKit.Colours.shield,
			strength = if shieldBroke then 0.45 else 0.28,
			at = os.clock(),
			duration = 0.3,
			depth = 0.1,
		}
	end
end

--- Current HP share, using the hit we just took if PlayerState has not caught up.
function VitalsController:_fraction(): (number, boolean)
	local state = self._state
	local me = state.me
	if not me or not state:IsLive() or me.downed or not me.maxHp or me.maxHp <= 0 then
		return 1, false
	end
	local hp = me.hp
	if self._predHp and os.clock() - self._predAt < 0.35 then
		hp = math.min(hp, self._predHp)
	else
		self._predHp = nil
	end
	return math.clamp(hp / me.maxHp, 0, 1), true
end

function VitalsController:_frame(dt: number)
	local fraction, alive = self:_fraction()
	local now = os.clock()

	-- low HP: nothing above 30%, then a curve rather than a straight line
	local danger = if alive and fraction < LOW then (LOW - fraction) / LOW else 0
	local target = if danger > 0 then 0.1 + 0.42 * danger ^ 0.85 else 0
	local critTarget = if alive and fraction < CRITICAL then 1 else 0
	local k = math.min(1, dt * 5)
	self._low += (target - self._low) * k
	self._crit += (critTarget - self._crit) * k
	if self._lowSet then
		local alpha = self._low
		if self._crit > 0.01 then
			-- a slow pulse that quickens a little as HP runs out
			local speed = 1.1 + 0.7 * math.clamp((CRITICAL - fraction) / CRITICAL, 0, 1)
			local pulse = 0.5 + 0.5 * math.sin(now * math.pi * 2 * speed)
			alpha += self._crit * (0.06 + 0.14 * pulse)
		end
		setDepth(self._lowSet, 0.13 + 0.1 * danger + 0.03 * self._crit)
		setLook(self._lowSet, LOW_RED, math.min(alpha, 0.72))
	end

	-- the hit flash, fading out fast
	local hit = self._hit
	if self._hitSet then
		local alpha = 0
		if hit then
			local t = (now - hit.at) / hit.duration
			if t >= 1 then
				self._hit = nil
			else
				alpha = hit.strength * (1 - t) ^ 2
				setDepth(self._hitSet, hit.depth)
			end
		end
		setLook(self._hitSet, if hit then hit.colour else HIT_RED, alpha)
	end

	self:_renderBar(dt, fraction, alive)
end

-- ---------------------------------------------------------------- the bar at the hero's feet

function VitalsController:_buildBar()
	local bill = Instance.new("BillboardGui")
	bill.Name = "BonkHeroBar"
	bill.Size = UDim2.fromScale(3.4, 0.42) -- studs: it shrinks and grows with the world
	bill.AlwaysOnTop = true
	bill.LightInfluence = 0
	bill.MaxDistance = 120
	bill.ResetOnSpawn = false
	bill.Enabled = false

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = BAR_BACK
	back.BackgroundTransparency = 0.3
	back.BorderSizePixel = 0
	back.ClipsDescendants = true
	back.Parent = bill
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = BAR_BACK
	stroke.Transparency = 0.2
	stroke.Parent = back

	local function bar(name: string, colour: Color3, z: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = colour
		frame.BorderSizePixel = 0
		frame.ZIndex = z
		frame.Parent = back
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = frame
		return frame
	end
	self._barTrail = bar("Trail", TRAIL, 1)
	self._barFill = bar("Fill", BAR_FILL, 2)
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	shine.Parent = self._barFill
	self._barShield = bar("Shield", BAR_SHIELD, 3)
	self._barShield.AnchorPoint = Vector2.new(0, 0)
	self._bar = bill
	bill.Parent = UiKit.playerGui()
end

function VitalsController:_renderBar(dt: number, fraction: number, alive: boolean)
	local bill = self._bar
	if not bill then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local show = alive and root ~= nil and humanoid ~= nil
	if bill.Enabled ~= show then
		bill.Enabled = show
		if show then
			self._shown, self._trail = fraction, fraction -- no slide-in on appearing
		end
	end
	if not show then
		return
	end
	if bill.Adornee ~= root then
		bill.Adornee = root
	end
	-- just under the feet, whatever the hero's size
	local below = root.Size.Y / 2 + humanoid.HipHeight + 0.35
	local offset = Vector3.new(0, -below, 0)
	if bill.StudsOffsetWorldSpace ~= offset then
		bill.StudsOffsetWorldSpace = offset
	end

	-- the fill moves quickly; the pale chunk behind it waits, then follows
	self._shown += (fraction - self._shown) * math.min(1, dt * 14)
	if fraction >= self._trail then
		self._trail = fraction
		self._trailHold = 0
	else
		self._trailHold += dt
		if self._trailHold > 0.35 then
			self._trail += (fraction - self._trail) * math.min(1, dt * 6)
		end
	end
	self._barFill.Size = UDim2.fromScale(self._shown, 1)
	self._barTrail.Size = UDim2.fromScale(self._trail, 1)

	local me = self._state.me
	local maxShield = me and me.maxShield or 0
	local shield = if maxShield >= 1 then math.clamp((me.shield or 0) / maxShield, 0, 1) else 0
	self._barShield.Visible = shield > 0.001
	self._barShield.Size = UDim2.fromScale(shield, 0.32)
end

return VitalsController

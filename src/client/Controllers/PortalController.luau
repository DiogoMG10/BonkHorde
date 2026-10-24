--!nonstrict
-- PortalController - the party's way from Skyhold into the Wardwood and back
-- (T8), and Skyhold's standing portal.
--
--   the portal   Skyhold's standing portal: its face is a vortex of teal light
--                over a deep core, with a rim of light, motes drawn in from the
--                ring and a light on the plaza. Everyone on the island sees it
--                surge through any party's countdown, flare as a party sinks
--                away or comes back, and sleep while the run is in use.
--   countdown    a portal opens on the ground of the party's rune circle and
--                grows stronger to the end (everyone on the island sees it); the
--                party can still move, and hears it hum
--   departure    the countdown over, the party is held still (the server anchors
--                them, PartyService); everyone on the island sees them rise a
--                little and sink into the portal, which closes after them. For
--                the party the camera frames them and the screen goes black.
--   arrival      in the Wardwood the black holds until the hero is set down and
--                the wood round them is there (streamed in, its art drawn, the
--                rest of the party arrived), then until the server says the whole
--                party is ready (RunDirectorService): then all at once the black
--                clears, a portal on the ground is open where they start, they
--                rise out of it, it closes, the camera hands back and the
--                controls come back as the run begins.
--   home         back from a run: black until the hero stands on the plaza and
--                the island round them is there, then the same rise out of a
--                portal on the plaza; anyone on the island sees the party rise.
--   joining      the loading screen (ReplicatedFirst/Loading) stays up until the
--                hero stands on the island and the island round them is there:
--                this tells it so (the LocalPlayer's BonkReady and BonkLoading).
--
-- Each cover waits on what the client can actually see (Core/Crossing.step:
-- the hero where the server put them, streaming no longer pausing them, the
-- ground round them present by WorldProbe, then the finishing touches), for a
-- short minimum and never past a maximum. Roblox's own "paused" notice is kept
-- off while a cover is up, since the cover says it better.
--
-- Heroes sink and rise through client/Sink (a stand-in of their visible pieces
-- drawn lower, following their animation; the character itself, its root, the
-- Humanoid and the physics stay put). The server decides
-- everything (PartyService, RunDirectorService): this only watches the hub's
-- parties and the run's phase (StateController). Timings are
-- Config/Skyhold.Crossing, the curves Core/Crossing, the portal on the ground
-- client/GroundPortal. Every effect is cosmetic and pcall-isolated; every hold
-- on the controls has a deadline (ControlLock).

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Crossing = require(ReplicatedStorage.Shared.Core.Crossing)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)
local SkyholdGen = require(ReplicatedStorage.Shared.Core.SkyholdGen)
local ControlLock = require(script.Parent.Parent.ControlLock)
local GroundPortal = require(script.Parent.Parent.GroundPortal)
local HubUi = require(script.Parent.Parent.HubUi)
local Sink = require(script.Parent.Parent.Sink)
local Vfx = require(script.Parent.Parent.Vfx)
local WorldProbe = require(script.Parent.Parent.WorldProbe)

local PortalController = Knit.CreateController({ Name = "PortalController" })

local player = Players.LocalPlayer
local CFG = Skyhold.Crossing
local LOCK = "crossing"

local BLACK = Color3.fromRGB(3, 6, 8) -- the cover
local LIGHT = Color3.fromRGB(226, 255, 246)
local MINT = Color3.fromRGB(150, 255, 236)
local TEAL = Color3.fromRGB(64, 214, 200)
local DEEP = Color3.fromRGB(16, 92, 112)
local SLEEP = Color3.fromRGB(90, 120, 200) -- the run is in use
local CREAM = Color3.fromRGB(255, 238, 196)
local GLOW_TO = Color3.fromRGB(205, 255, 244) -- what the portal's neon pieces brighten towards
local PLACED_NEAR = 14 -- studs: a hero this near where the server set it down stands there
local BELOW_ISLAND = 60 -- studs under the island's origin: the Wardwood
local DEPTH = GameConfig.HeroHeight + 2 -- studs: this far under, a hero is out of sight, weapon and all
local SHOT_TURN = math.rad(35) -- the arrival's shots look at the party from a little to the side
local SHOT_SWING = math.rad(50) -- the departure's shot turns at most this far from where the camera looks
local HOME_NEAR = 14 -- studs from the plaza's return spot: a hero there has just come home
local WATCH_DELAY = 0.35 -- seconds: someone else coming home rises this long after their portal opens

-- Studio only: `Workspace:SetAttribute("BonkCrossingSlow", 4)` plays the
-- departure, the arrival and the homecoming four times slower, to look at them
local function slow(): number
	local k = RunService:IsStudio() and Workspace:GetAttribute("BonkCrossingSlow")
	return if typeof(k) == "number" and k > 0 then k else 1
end

local function lite(): boolean
	-- a lighter portal on the lowest graphics settings
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	return ok and level > 0 and level <= 3
end

function PortalController:KnitInit()
	self._charge = Crossing.Idle -- the standing portal's, shown (eased)
	self._flareAt = -math.huge
	self._totals = {} -- circle -> the countdown's length when it was first seen
	self._phases = {} -- circle -> the party phase last seen
	self._departs = {} -- circle -> the portal opening on its ground, and who sinks into it
	self._rises = {} -- "wardwood" | "home" -> a portal heroes rise out of
	self._raising = {} -- character -> a hero rising back after a departure called off
	self._under = {} -- character -> until when a hero who went stays under
	self._returning = {} -- userId -> when their party came home (hub.run went away)
	self._departing = nil
	self._arriving = nil
	self._home = nil
	-- the loading screen is up from the first frame: the hero is held with it
	self._joining = { gate = Crossing.wait(os.clock()) }
	self._knitStarted = false
	self._preloaded = false
	self._covered = false
	self._darkNow = 0
	self._lastRun = nil
end

function PortalController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._camera = Knit.GetController("CameraController")
	self._audio = Knit.GetController("AudioController")
	self._artKit = Knit.GetController("ArtController")
	self._lite = lite()
	self._ready = Net.client("CrossingReady")
	self:_makeCover()
	ControlLock.set(LOCK, true, CFG.join.max + 1)
	Knit.OnStart():andThen(function()
		self._knitStarted = true
	end)
	task.spawn(function()
		-- what the island shows first: the portals' vortices and their motes
		pcall(function()
			ContentProvider:PreloadAsync({
				Vfx.Tex.glow,
				Vfx.Tex.swirl,
				Vfx.Tex.ring,
				Vfx.Tex.ring_thin,
				Vfx.Tex.dot,
				Vfx.Tex.star4,
				Vfx.Tex.streak,
				Vfx.Tex.beam,
			})
		end)
		self._preloaded = true
	end)

	local plan = SkyholdGen.build(Skyhold)
	self._plan = plan
	local p = Skyhold.Portal
	local h = SkyholdGen.heightAt(plan, p.x, p.z) or 0
	self._centre = Vector3.new(SkyholdGen.world(Skyhold, p.x, h + Skyhold.PortalCentreHeight, p.z))
	local r = Skyhold.Return
	local rh = SkyholdGen.heightAt(plan, r.x, r.z) or 0
	self._returnAt = Vector3.new(SkyholdGen.world(Skyhold, r.x, rh, r.z))

	local state = self._state
	self._lastPhase = state.phase
	state.Changed:Connect(function(key)
		if key == "phase" then
			pcall(function()
				self:_onPhase()
			end)
		elseif key == "hub" then
			pcall(function()
				self:_onHub()
			end)
		end
	end)

	local broken = false
	RunService.RenderStepped:Connect(function(dt)
		if broken then
			return
		end
		local ok, err = pcall(function()
			self:_frame(dt)
		end)
		if not ok then
			broken = true
			warn(`[PortalController] stopped: {err}`)
			-- whatever was held is let go, whatever was covered is shown, whoever
			-- was under the ground stands up
			ControlLock.set(LOCK, false)
			self._camera:SetCrossing(nil)
			self:_setDark(0)
			for _, character in Sink.all() do
				Sink.clear(character)
			end
		end
	end)
end

--- The standing portal's charge as drawn now, 0..1 (HubDecorController's stones read it).
function PortalController:Charge(): number
	return self._charge
end

-- ------------------------------------------------------------------ the cover

function PortalController:_makeCover()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crossing"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	pcall(function()
		(gui :: any).ScreenInsets = Enum.ScreenInsets.None
	end)
	gui.DisplayOrder = 60 -- over everything the game draws, under Roblox's own menu
	gui.Enabled = false
	local fill = Instance.new("Frame")
	fill.Name = "Black"
	fill.BackgroundColor3 = BLACK
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = gui
	-- a quiet word, only when the wait runs long: a turning rune and a line
	local hint = Instance.new("Frame")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -48)
	hint.Size = UDim2.fromOffset(420, 40)
	hint.Visible = false
	hint.Parent = gui
	local rune = Instance.new("ImageLabel")
	rune.Name = "Rune"
	rune.BackgroundTransparency = 1
	rune.Image = Vfx.Tex.swirl
	rune.ImageColor3 = TEAL
	rune.AnchorPoint = Vector2.new(0.5, 0.5)
	rune.Position = UDim2.new(0, 20, 0.5, 0)
	rune.Size = UDim2.fromOffset(34, 34)
	rune.Parent = hint
	local text = HubUi.label(hint, "", 22, "body", {
		Name = "Text",
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.new(1, -46, 1, 0),
		TextColor3 = Color3.fromRGB(190, 225, 215),
	})
	gui.Parent = player:WaitForChild("PlayerGui")
	self._coverGui, self._coverFill = gui, fill
	self._hintFrame, self._hintRune, self._hintText = hint, rune, text
end

--- How much of the screen is black, 0..1.
function PortalController:_setDark(amount: number)
	local gui = self._coverGui
	if not gui then
		return
	end
	amount = math.clamp(amount, 0, 1)
	gui.Enabled = amount > 0.001
	self._darkNow = amount
	self._coverFill.BackgroundTransparency = 1 - amount
	if amount < 0.99 then
		self:_hint(nil)
	end
end

--- The quiet line under the black while a wait runs long (nil: none).
function PortalController:_hint(text: string?)
	local frame = self._hintFrame
	if not frame then
		return
	end
	if not text then
		frame.Visible = false
		self._hintSince = nil
		return
	end
	local now = os.clock()
	self._hintSince = self._hintSince or now
	local k = math.clamp((now - self._hintSince) / 0.5, 0, 1)
	frame.Visible = true
	self._hintText.Text = text
	self._hintText.TextTransparency = 1 - 0.85 * k
	self._hintRune.ImageTransparency = 1 - 0.8 * k
	self._hintRune.Rotation = (now * 90) % 360
end

-- ------------------------------------------------------------------ Skyhold's standing portal

-- the island's art, once it is built
function PortalController:_art(name: string): Instance?
	local island = Workspace:FindFirstChild("Skyhold")
	local art = island and island:FindFirstChild("Art")
	return art and art:FindFirstChild(name)
end

--- The vortex over the portal's face, built once the island is (and again
--- after streaming let the island go while this player was in the Wardwood:
--- the face and its neon pieces come back as new parts).
function PortalController:_vortex()
	local built = self._vortexData
	if built then
		if built.face:IsDescendantOf(Workspace) then
			return built
		end
		built.folder:Destroy()
		self._vortexData = nil
	end
	local face = self:_art("PortalFace")
	if not face or not face:IsA("BasePart") then
		return nil
	end
	local radius = Skyhold.PortalRadius
	-- the face is a disc looking south: its round sides point along its x axis
	local front = -face.CFrame.RightVector
	local centre = face.Position
	local card = Instance.new("Part")
	card.Name = "PortalVortex"
	card.Anchored = true
	card.CanCollide = false
	card.CanQuery = false
	card.CanTouch = false
	card.CastShadow = false
	card.Transparency = 1
	card.Size = Vector3.new(radius * 2, radius * 2, 0.05)
	card.CFrame = CFrame.lookAt(centre + front * 0.3, centre + front * 10)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Vortex"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.ClipsDescendants = true
	gui.Parent = card
	local layers = {}
	local function layer(name: string, tex: string, colour: Color3, size: number, alpha: number, z: number)
		local image = Instance.new("ImageLabel")
		image.Name = name
		image.BackgroundTransparency = 1
		image.Image = Vfx.Tex[tex]
		image.ImageColor3 = colour
		image.ImageTransparency = alpha
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(size, size)
		image.ZIndex = z
		image.Parent = gui
		layers[name] = image
		return image
	end
	-- deepest first: a dark well, three swirls turning against each other, the
	-- bright core, the rim of light where the stone meets the light
	layer("Well", "glow", DEEP, 1.25, 0.15, 1)
	layer("SwirlA", "swirl", MINT, 1.05, 0.4, 2)
	if not self._lite then
		layer("SwirlB", "swirl", TEAL, 0.82, 0.3, 3)
	end
	layer("SwirlC", "swirl", Color3.new(1, 1, 1), 0.55, 0.5, 4)
	layer("Core", "glow", LIGHT, 0.4, 0.4, 5)
	layer("Rim", "ring_thin", CREAM, 0.97, 0.5, 6)
	local folder = Instance.new("Folder")
	folder.Name = "PortalClient"
	card.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = TEAL
	light.Range = 34
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = card
	local motes = nil
	if not self._lite then
		motes = Vfx.place("PortalMotes", CFrame.new(centre + front * 0.6), radius * 1.7, folder)
	end
	folder.Parent = Workspace
	-- the portal's own neon pieces, and what colour each was built
	local neon = {}
	local function collect(model: Instance?, names: { string })
		if not model then
			return
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon and table.find(names, d.Name) then
				table.insert(neon, { part = d, base = d.Color })
			end
		end
	end
	collect(self:_art("Portal"), { "Runes", "Crystal" })
	collect(self:_art("Plaza"), { "Inlay" })
	for k = 1, 8 do
		collect(self:_art(`Orbit{k}`), { "Glyph" })
	end
	self._vortexData = {
		face = face,
		card = card,
		folder = folder,
		layers = layers,
		light = light,
		motes = motes and motes:FindFirstChildOfClass("ParticleEmitter"),
		neon = neon,
		spin = { a = 0, b = 0, c = 0, rim = 0 },
	}
	return self._vortexData
end

function PortalController:_drawPortal(dt: number, onIsland: boolean)
	local v = self:_vortex()
	if not v then
		return
	end
	v.folder.Parent = if onIsland then Workspace else nil
	if not onIsland then
		return
	end
	local state = self._state
	local now = os.clock()
	-- the countdown nearest its end (any party's): the whole island sees it
	local left, total = nil, nil
	for _, party in state.hub.circles or {} do
		if party.phase == "countdown" then
			local l = state:CountdownLeft(party)
			if l and (not left or l < left) then
				left, total = l, self._totals[party.circle] or l
			end
		elseif party.phase == "departing" then
			left, total = 0, 1 -- a party sinking away: full
		end
	end
	local busy = state.hub.run ~= nil
	local flare = math.clamp(1 - (now - self._flareAt) / 1.4, 0, 1)
	local target = Crossing.charge(left, total, busy and left == nil, flare)
	self._charge += (target - self._charge) * math.min(1, dt * 5)
	local c = self._charge
	local sleepy = busy and left == nil

	-- the swirls turn faster as it surges, against each other
	local spinIdle, spinFull = Skyhold.PortalSpin[1], Skyhold.PortalSpin[2]
	local turns = (spinIdle + (spinFull - spinIdle) * c * c) * 360 * dt
	local s = v.spin
	s.a = (s.a + turns) % 360
	s.b = (s.b - turns * 1.6) % 360
	s.c = (s.c + turns * 2.4) % 360
	s.rim = (s.rim + turns * 0.25) % 360
	local L = v.layers
	local tint = if sleepy then SLEEP else MINT
	L.SwirlA.Rotation = s.a
	L.SwirlA.ImageColor3 = tint
	L.SwirlA.ImageTransparency = 0.5 - 0.35 * c
	if L.SwirlB then
		L.SwirlB.Rotation = s.b
		L.SwirlB.ImageTransparency = 0.35 - 0.25 * c
	end
	L.SwirlC.Rotation = s.c
	L.SwirlC.ImageTransparency = 0.55 - 0.4 * c
	local breathe = math.sin(now * 2.2) * 0.04
	local core = 0.36 + breathe + 0.5 * c * c
	L.Core.Size = UDim2.fromScale(core, core)
	L.Core.ImageTransparency = math.clamp(0.45 - 0.45 * c, 0, 1)
	L.Well.ImageTransparency = 0.15 + 0.55 * c -- the well fills with light as it surges
	L.Rim.Rotation = s.rim
	L.Rim.ImageTransparency = 0.45 - 0.35 * c
	v.light.Brightness = 0.6 + 4.5 * c * c
	v.light.Range = 30 + 22 * c
	v.light.Color = if sleepy then SLEEP else TEAL
	if v.motes then
		v.motes.Rate = 6 + 70 * c * c
	end
	v.face.Color = (if sleepy then SLEEP else DEEP):Lerp(MINT, c * c)
	v.face.Transparency = 0.12
	for _, entry in v.neon do
		entry.part.Color = entry.base:Lerp(GLOW_TO, math.clamp((c - Crossing.Idle) * 1.2, 0, 0.85))
	end
end

-- ------------------------------------------------------------------ parties on the island

-- countdown lengths; the moment a party sinks away; a party coming home
function PortalController:_onHub()
	local state = self._state
	local seen = {}
	for _, party in state.hub.circles or {} do
		seen[party.circle] = true
		local before = self._phases[party.circle]
		if party.phase == "countdown" and before ~= "countdown" then
			self._totals[party.circle] = state:CountdownLeft(party) or Skyhold.CountdownSeconds
		end
		self._phases[party.circle] = party.phase
	end
	for circle in self._phases do
		if not seen[circle] then
			self._phases[circle] = nil
		end
	end
	-- the run is over: its party is on its way back to the plaza
	local run = state.hub.run
	local last = self._lastRun
	if last and not run then
		local now = os.clock()
		for _, uid in last.members or {} do
			self._returning[uid] = now
		end
	end
	self._lastRun = run
end

-- the ground at a place on the island, with whatever stands on it there (a
-- rune circle's stone), or nil
local function islandGround(at: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain, Workspace:FindFirstChild("Skyhold") }
	local hit = Workspace:Raycast(at + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position
end

-- the Wardwood's ground under (x, z), or nil while it has not streamed in
local function woodGround(x: number, z: number, near: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(x, near + 20, z), Vector3.new(0, -60, 0), params)
	return hit and hit.Position
end

local function onIslandRoot(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root.Position.Y > Skyhold.Origin[2] - BELOW_ISLAND then
		return root
	end
	return nil
end

-- a portal opening on a circle's ground, for its party's countdown and departure
function PortalController:_newDepart(circle: number)
	local c = Skyhold.Circles[circle]
	local h = SkyholdGen.heightAt(self._plan, c.x, c.z) or 0
	local guess = Vector3.new(SkyholdGen.world(Skyhold, c.x, h, c.z))
	local centre = islandGround(guess) or guess
	local portal = GroundPortal.new(centre, Skyhold.CircleRadius + 0.5, self._lite)
	portal:flash(false)
	local g = { portal = portal, centre = centre, circle = circle, members = {}, charge = 0.25, open = 0 }
	self._departs[circle] = g
	return g
end

-- every party counting down, waiting or departing: its portal, and its heroes
-- sinking into it, as everyone on the island sees them
function PortalController:_islandDepartures(dt: number)
	local state = self._state
	local onIsland = state:OnIsland()
	local seen = {}
	if onIsland then
		for _, party in state.hub.circles or {} do
			local phase = party.phase
			if phase == "countdown" or phase == "waiting" or phase == "departing" then
				seen[party.circle] = true
				local g = self._departs[party.circle]
				if g and g.closing then
					g.portal:destroy()
					g = nil
				end
				g = g or self:_newDepart(party.circle)
				self:_drawDepart(g, party, dt)
			end
		end
	end
	local now = os.clock()
	for circle, g in self._departs do
		if not seen[circle] and not g.closing then
			-- into the run, or called off: the portal closes either way
			local party = state:PartyAt(circle)
			local went = g.departed and party ~= nil and party.phase == "run"
			g.closing = { since = now, from = g.open, went = went }
			if not went then
				g.portal:flash(true)
			end
			for character in g.members do
				if went then
					self._under[character] = now + 6 -- until the run takes the character away
				else
					self._raising[character] = { from = Sink.studs(character), since = now }
				end
			end
		end
		if g.closing then
			local k = math.clamp((now - g.closing.since) / 0.45, 0, 1)
			g.portal:draw(g.closing.from * (1 - Crossing.smooth(k)), g.charge * (1 - k), 0, dt)
			if k >= 1 then
				g.portal:destroy()
				self._departs[circle] = nil
			end
		end
	end
end

function PortalController:_drawDepart(g, party, dt: number)
	local state = self._state
	local left = state:CountdownLeft(party) or 0
	if party.phase == "countdown" then
		local total = self._totals[party.circle] or left
		local k = Crossing.gather(left, total, CFG.portal.open)
		g.open = k.open
		g.charge += (k.charge - g.charge) * math.min(1, dt * 6)
		g.portal:draw(g.open, g.charge, 0, dt)
		return
	elseif party.phase == "waiting" then
		-- the portal is busy: this one idles, open, until the party's turn
		g.open += (1 - g.open) * math.min(1, dt * 4)
		g.charge += (0.3 - g.charge) * math.min(1, dt * 3)
		g.portal:draw(g.open, g.charge, 0, dt)
		return
	end
	-- departing: seconds since the countdown ended, by the server's clock
	local t = (CFG.descent * slow() - left) / slow()
	local d = Crossing.descent(t, CFG.depart)
	if not g.departed then
		g.departed = true
		self._flareAt = os.clock()
		pcall(Vfx.burst, "PortalSurge", self._centre)
		g.portal:flash(false)
		if not table.find(party.members, player.UserId) then
			-- heard from the circle by everyone else on the island
			pcall(function()
				local sound = self._audio:PlayAt("portal_open", g.portal.folder:FindFirstChild("Card"), 0.05)
				if sound then
					sound.RollOffMaxDistance = 220
				end
			end)
		end
	end
	if d.gone and not g.swallowed then
		g.swallowed = true
		pcall(Vfx.burst, "PortalDepart", g.centre + Vector3.new(0, 1, 0))
	end
	g.open = d.open
	g.charge = d.charge
	g.portal:draw(d.open, d.charge, if d.gone then d.open else 1, dt)
	for _, uid in party.members do
		local other = Players:GetPlayerByUserId(uid)
		local character = other and other.Character
		if character and onIslandRoot(character) then
			g.members[character] = true
			self._raising[character] = nil
			Sink.set(character, DEPTH * d.sink, DEPTH)
		end
	end
end

-- heroes rising back after a departure was called off, and heroes who went
-- staying under until the run takes their island character away
function PortalController:_islandSinking()
	local now = os.clock()
	for character, r in self._raising do
		local k = math.clamp((now - r.since) / 0.45, 0, 1)
		if not character.Parent or k >= 1 then
			self._raising[character] = nil
			Sink.clear(character)
		else
			Sink.set(character, r.from * (1 - Crossing.smooth(k)), DEPTH)
		end
	end
	for character, untilAt in self._under do
		if not character.Parent then
			self._under[character] = nil
			Sink.clear(character)
		elseif now > untilAt then
			-- the run never took them (it could not start): they stand up again
			self._under[character] = nil
			self._raising[character] = { from = Sink.studs(character), since = now }
		end
	end
end

-- ------------------------------------------------------------------ this player's departure

--- My party, if it is on a circle.
function PortalController:_myParty()
	local state = self._state
	local mine = state:Mine()
	return mine and mine.circle and state:PartyAt(mine.circle)
end

--- The departure's shot: the party and its portal, close and from a little
--- above, from where the camera already looks, turned towards the plaza's side
--- (Skyhold's portal behind them) by at most SHOT_SWING, so it never swings
--- across.
function PortalController:_departShot(g): CFrame
	local centre = g.centre
	local function angle(v: Vector3): number
		return math.atan2(v.X, v.Z)
	end
	local away = centre - self._centre
	local camera = Workspace.CurrentCamera
	local from = if camera then camera.CFrame.Position - centre else away
	local a, goal = angle(from), angle(away)
	local turn = (goal - a + math.pi) % (2 * math.pi) - math.pi
	a += math.clamp(turn, -SHOT_SWING, SHOT_SWING)
	local dir = Vector3.new(math.sin(a), 0, math.cos(a))
	local r = g.portal.radius
	local eye = centre + dir * (8 + r * 0.9) + Vector3.new(0, 4.5 + r * 0.35, 0)
	return CFrame.lookAt(eye, centre + Vector3.new(0, 2.2, 0))
end

-- the countdown's hum, rising with it, for the party only
function PortalController:_countdownHum(party)
	local state = self._state
	local counting = state:OnIsland() and party ~= nil and party.phase == "countdown"
	local hum = self._hum
	if counting then
		if not hum or not hum.Parent then
			hum = self._audio:Play("shrine_charge_loop")
			if hum then
				hum.Volume = 0
			end
			self._hum = hum
		end
		if hum then
			local left = state:CountdownLeft(party) or 0
			local total = self._totals[party.circle] or Skyhold.CountdownSeconds
			local k = 1 - math.clamp(left / math.max(total, 0.1), 0, 1)
			hum.Volume = 0.08 + 0.22 * k
			hum.PlaybackSpeed = 0.85 + 0.55 * k
		end
	elseif hum then
		self._hum = nil
		TweenService:Create(hum, TweenInfo.new(0.35), { Volume = 0 }):Play()
		task.delay(0.4, function()
			hum:Destroy()
		end)
	end
end

-- my party sinking into its portal: held, the camera framing us, the black
function PortalController:_myDeparture()
	local state = self._state
	local party = self:_myParty()
	self:_countdownHum(party)
	local going = self._departing
	if state:OnIsland() and party and party.phase == "departing" then
		local left = state:CountdownLeft(party) or 0
		local d = Crossing.descent((CFG.descent * slow() - left) / slow(), CFG.depart)
		if not going then
			going = { since = os.clock() }
			self._departing = going
			self._unwinding = nil
			self._audio:Play("portal_open")
		end
		ControlLock.set(LOCK, true, CFG.descent * slow() + 2)
		local g = self._departs[party.circle]
		if g then
			-- chosen once, from where the camera was when it began
			going.shot = going.shot or self:_departShot(g)
			self._camera:SetCrossing(going.shot, 60, d.camera)
		end
		self:_setDark(d.dark)
		going.dark = d.dark
		return
	end
	if not going then
		return
	end
	self._departing = nil
	if state.phase == "Intro" or (party and party.phase == "run") then
		self:_setDark(1) -- into the run: the arrival takes it from here
	else
		-- called off after all (the run could not start): back as we were
		ControlLock.set(LOCK, false)
		self._camera:SetCrossing(nil)
		self._unwinding = { from = going.dark or 0, started = os.clock() }
	end
end

-- ------------------------------------------------------------------ portals heroes rise out of

--- A portal on the ground at `centre` that heroes rise out of (`key`:
--- "wardwood" or "home"), with the curve they rise on.
function PortalController:_rise(key: string, centre: Vector3, radius: number, cfg: Crossing.Rise)
	local g = self._rises[key]
	if g and g.closeFrom then
		-- a closing portal opens again for whoever comes next
		g.closeFrom = nil
	end
	if not g then
		g = {
			portal = GroundPortal.new(centre, radius, self._lite),
			centre = centre,
			cfg = cfg,
			risers = {}, -- character -> { startAt = os.clock()?, done }
			created = os.clock(),
		}
		self._rises[key] = g
	end
	return g
end

--- `character` will rise out of `g`: from `startAt` (os.clock), or held under
--- until it is given one.
function PortalController:_riser(g, character: Model, startAt: number?)
	local r = g.risers[character]
	if not r then
		r = { startAt = startAt }
		g.risers[character] = r
		Sink.set(character, DEPTH, DEPTH)
	elseif startAt and not r.startAt then
		r.startAt = startAt
	end
	return r
end

--- Every portal heroes rise out of: each hero on their own curve, the portal
--- open while any is still under or rising, then closing after them.
function PortalController:_stepRises(dt: number)
	local now = os.clock()
	for key, g in self._rises do
		local cfg = g.cfg
		local busy = false
		local column = 0
		for character, r in g.risers do
			if not character.Parent then
				g.risers[character] = nil
			elseif not r.startAt then
				busy = true
				Sink.set(character, DEPTH, DEPTH)
			elseif not r.done then
				local t = (now - r.startAt) / slow()
				local e = Crossing.emerge(t, cfg)
				local u = (t - cfg.riseFrom) / cfg.rise
				if u >= 1 then
					r.done = true
					Sink.clear(character)
				else
					busy = true
					Sink.set(character, DEPTH * e.sink, DEPTH)
					if u > 0 then
						column = math.max(column, math.sin(math.clamp(u, 0, 1) * math.pi))
						if not r.burst then
							r.burst = true
							local root = character:FindFirstChild("HumanoidRootPart")
							if root then
								pcall(Vfx.burst, "PortalDepart", root.Position - Vector3.new(0, 1.5, 0))
							end
						end
					end
				end
			end
		end
		local open, charge
		if busy then
			open = Crossing.out((now - g.created) / (CFG.portal.open * 0.5))
			charge = 0.85
		else
			if not g.closeFrom then
				g.closeFrom = now
				g.portal:flash(true)
			end
			local k = math.clamp((now - g.closeFrom) / (cfg.close * slow()), 0, 1)
			open, charge = 1 - Crossing.smooth(k), 0.85 * (1 - k)
			if k >= 1 then
				g.portal:destroy()
				self._rises[key] = nil
			end
		end
		g.portal:draw(open, charge, column, dt)
	end
end

--- The rise's shot: the portal and the heroes in it from behind and above the
--- way the hero's own camera looks, a little to the side; `weight` of the way
--- there from the hero's own camera.
function PortalController:_riseShot(centre: Vector3, radius: number, weight: number)
	local yaw = self._camera:Yaw() + SHOT_TURN
	local back = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local eye = centre + back * (10 + radius * 1.2) + Vector3.new(0, 6 + radius * 0.5, 0)
	self._camera:SetCrossing(CFrame.lookAt(eye, centre + Vector3.new(0, 2, 0)), 70, weight)
end

-- ------------------------------------------------------------------ the run's phase

-- the run's phase: into the Wardwood, or home
function PortalController:_onPhase()
	local state = self._state
	local phase, last = state.phase, self._lastPhase
	self._lastPhase = phase
	if phase == last then
		return
	end
	if phase == "Intro" then
		self._unwinding = nil
		self._departing = nil -- through: the departure is over, the black stays
		self:_finishHome()
		ControlLock.set(LOCK, true, CFG.arriveGate.max + CFG.revealMax + 3)
		local now = os.clock()
		-- black from wherever the departure had got to (straight into a run, with
		-- no departure: from nothing, quickly)
		self._arriving = { since = now, gate = Crossing.wait(now), fromDark = self._darkNow or 0 }
	elseif phase == "Lobby" and last ~= "Lobby" then
		self:_finishArrival()
		self:_dropRise("wardwood")
		self._flareAt = os.clock()
		self:_setDark(1)
		ControlLock.set(LOCK, true, CFG.homeGate.max + 3)
		self._home = { since = os.clock(), gate = Crossing.wait(os.clock()) }
	elseif (phase == "Results" or phase == "Victory" or phase == "Wipe") and self._arriving then
		-- the run ended before the hero was seen: nothing more to wait for
		self:_finishArrival()
		self:_dropRise("wardwood")
	end
end

function PortalController:_dropRise(key: string)
	local g = self._rises[key]
	if g then
		for character in g.risers do
			Sink.clear(character)
		end
		g.portal:destroy()
		self._rises[key] = nil
	end
end

-- the squad's heroes in the Wardwood, by player
function PortalController:_squad(): { Player }
	local state = self._state
	local out = {}
	for _, mate in state.squad do
		local other = Players:GetPlayerByUserId(mate.userId)
		if other then
			table.insert(out, other)
		end
	end
	if #out == 0 then
		table.insert(out, player)
	end
	return out
end

local function inWardwood(root: BasePart?): boolean
	return root ~= nil and root.Parent ~= nil and root.Position.Y < Skyhold.Origin[2] - BELOW_ISLAND
end

-- does this character stand where the server set it down (on the island, or in
-- the Wardwood)?
local function placed(character: Model?, island: boolean): boolean
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local at = character and character:GetAttribute("PlacedAt")
	if not (root and root:IsA("BasePart") and typeof(at) == "Vector3") then
		return false
	end
	local onIsland = root.Position.Y > Skyhold.Origin[2] - BELOW_ISLAND
	return onIsland == island and (root.Position - at).Magnitude < PLACED_NEAR
end

local function streamingPaused(): boolean
	local ok, paused = pcall(function()
		return player.GameplayPaused
	end)
	return ok and paused == true
end

-- ------------------------------------------------------------------ what the client can see

--- Is the hero where the server set them down, and the ground round them there?
--- `island`: on Skyhold, else in the Wardwood.
function PortalController:_facts(island: boolean): Crossing.Facts
	local character = player.Character
	local facts = { placed = placed(character, island), streamed = false, detail = false }
	if facts.placed and not streamingPaused() then
		local root = character.HumanoidRootPart
		local o = Skyhold.Origin
		local heights, include
		if island then
			local plan = self._plan
			heights = function(x: number, z: number): number?
				local h = SkyholdGen.heightAt(plan, x - o[1], z - o[3])
				return h and o[2] + h
			end
			include = { Workspace.Terrain, Workspace:FindFirstChild("Skyhold") }
		else
			local state = self._state
			local half = state.map.half - 8
			heights = function(x: number, z: number): number?
				if math.abs(x) > half or math.abs(z) > half then
					return nil
				end
				return state:HeightAt(x, z)
			end
			include = { Workspace.Terrain }
		end
		facts.streamed = WorldProbe.streamed(root.Position, heights, include)
	end
	return facts
end

--- Every other member of the squad stands in the Wardwood where they were set down.
function PortalController:_squadPlaced(): boolean
	for _, mate in self:_squad() do
		if mate ~= player and not placed(mate.Character, false) then
			return false
		end
	end
	return true
end

--- Roblox's own notice that streaming paused the player, off while a cover
--- says it better.
function PortalController:_cover(on: boolean)
	if on == self._covered then
		return
	end
	self._covered = on
	pcall(function()
		GuiService:SetGameplayPausedNotificationEnabled(not on)
	end)
end

--- A cover lifts: one line in the log on how long it waited and for what
--- (`late`: the finishing touches it waited longest for, if any).
function PortalController:_shown(what: string, gate: Crossing.Wait, why: string, late: string?)
	local waited = if late and (gate.spent.detail or 0) > 0.3 then `; last detail: {late}` else ""
	local line =
		`[PortalController] {what} shown after {string.format("%.2f", os.clock() - gate.since)}s ({Crossing.summary(gate)}{waited})`
	if why == "timeout" then
		warn(`{line}: not ready in time, shown anyway`)
	else
		print(line)
	end
end

-- joining: the loading screen is told what is still awaited, and when to go
function PortalController:_join()
	local j = self._joining
	local facts = self:_facts(true)
	if facts.placed and facts.streamed then
		local missing = {}
		for name, done in
			{
				controllers = self._knitStarted,
				textures = self._preloaded,
				profile = self._state.profile ~= nil,
				portal = self:_vortex() ~= nil,
			}
		do
			if not done then
				table.insert(missing, name)
			end
		end
		facts.detail = #missing == 0
		if #missing > 0 then
			table.sort(missing)
			j.late = table.concat(missing, ", ")
		end
	end
	local ready, why = Crossing.step(j.gate, facts, os.clock(), CFG.join)
	if player:GetAttribute("BonkLoading") ~= why then
		player:SetAttribute("BonkLoading", why)
	end
	if ready then
		self._joining = nil
		ControlLock.set(LOCK, false)
		player:SetAttribute("BonkReady", true)
		self:_shown("Skyhold (joining)", j.gate, why, j.late)
	end
end

-- ------------------------------------------------------------------ the arrival in the Wardwood

-- where the party rises in the Wardwood: the spawn's centre (MapService.SpawnPoint)
function PortalController:_woodPortal()
	local state = self._state
	local n = #self:_squad()
	local spread = if n > 1 then GameConfig.SpawnSpacing else 0
	local near = state:HeightAt(0, 0)
	local ground = woodGround(0, 0, near)
	local centre = if ground then ground else Vector3.new(0, near, 0)
	return centre, Crossing.radius(spread, CFG.portal)
end

function PortalController:_arrival(dt: number)
	local a = self._arriving
	if not a then
		return
	end
	local state = self._state
	local now = os.clock()
	local root = state:Root()
	if not a.revealAt then
		-- black until this player's Wardwood hero is set down and the wood round
		-- them is there: streamed in, its art drawn (all at once, unseen), the rest
		-- of the party arrived; a while at most (CFG.arriveGate)
		self:_setDark(math.min(1, a.fromDark + (now - a.since) / 0.2))
		local facts = self:_facts(false)
		if facts.placed and root then
			-- under the black: the portal open where the party starts, every hero
			-- already set down held under it, the camera where it will look from
			if facts.streamed and not a.portal then
				local centre, radius = self:_woodPortal()
				a.centre, a.radius = centre, radius
				a.portal = self:_rise("wardwood", centre, radius, CFG.arrive)
			end
			if a.portal then
				for _, mate in self:_squad() do
					if placed(mate.Character, false) then
						self:_riser(a.portal, mate.Character, nil)
					end
				end
				self:_riseShot(a.centre, a.radius, 1)
			end
			local drawn = self._artKit:Prepare(root.Position)
			facts.detail = facts.streamed and drawn and self:_squadPlaced() and a.portal ~= nil
		end
		local ready, why = Crossing.step(a.gate, facts, now, CFG.arriveGate)
		if ready and not a.readyAt then
			a.readyAt, a.why = now, why
			a.run = state.run
			if self._ready then
				self._ready:FireServer(a.run)
			end
		end
		-- then the server's word that the whole party is ready (a while at most)
		local revealed = state.reveal and a.run ~= nil and state.run == a.run
		if not (ready and (revealed or now - a.readyAt >= CFG.revealMax)) then
			if a.readyAt then
				Crossing.waitedFor(a.gate, "party", dt)
			end
			if now - a.since > CFG.hint then
				self:_hint(if a.readyAt then "Waiting for your party..." else "Opening the way...")
			end
			return
		end
		self:_shown("the Wardwood", a.gate, a.why)
		a.revealAt = now
		if not a.portal and root then
			local centre, radius = self:_woodPortal()
			a.centre, a.radius = centre, radius
			a.portal = self:_rise("wardwood", centre, radius, CFG.arrive)
		end
		if a.portal then
			for character, r in a.portal.risers do
				r.startAt = r.startAt or now
				if not character.Parent then
					a.portal.risers[character] = nil
				end
			end
		end
		pcall(function()
			self._audio:Play("portal_enter", 0.04)
		end)
	end
	local t = (now - a.revealAt) / slow()
	local e = Crossing.emerge(t, CFG.arrive)
	self:_setDark(e.dark)
	if a.portal then
		-- anyone set down after the reveal rises on their own
		for _, mate in self:_squad() do
			local character = mate.Character
			if character and placed(character, false) and not a.portal.risers[character] then
				self:_riser(a.portal, character, now)
			end
		end
	end
	if a.centre and inWardwood(root) then
		self:_riseShot(a.centre, a.radius, e.camera)
	else
		self._camera:SetCrossing(nil)
	end
	if not e.held then
		ControlLock.set(LOCK, false)
	end
	if e.done then
		self:_finishArrival()
	end
end

function PortalController:_finishArrival()
	local a = self._arriving
	self._arriving = nil
	if not a then
		return
	end
	self._camera:SetCrossing(nil)
	ControlLock.set(LOCK, false)
	self:_setDark(0)
end

-- ------------------------------------------------------------------ home

-- where a party coming home rises: the plaza's return spot
function PortalController:_homePortal(count: number)
	local centre = islandGround(self._returnAt) or self._returnAt
	return centre, Crossing.radius(if count > 1 then 4 else 0, CFG.portal)
end

-- home from a run: black until the island hero is on the plaza, then up out of
-- a portal there
function PortalController:_homecoming()
	local h = self._home
	if not h then
		return
	end
	local now = os.clock()
	if not h.revealAt then
		-- black until the island hero stands on the plaza and the island round them
		-- is there, the portal lit again; a while at most (CFG.homeGate)
		self:_setDark(1)
		local facts = self:_facts(true)
		if facts.placed and facts.streamed then
			facts.detail = self:_vortex() ~= nil
			if not h.portal then
				local party = self:_myParty()
				local count = if party then #party.members else 1
				h.centre, h.radius = self:_homePortal(count)
				h.portal = self:_rise("home", h.centre, h.radius, CFG.home)
			end
			self:_riser(h.portal, player.Character, nil)
			self:_riseShot(h.centre, h.radius, 1)
		end
		local ready, why = Crossing.step(h.gate, facts, now, CFG.homeGate)
		if not ready then
			if now - h.since > CFG.hint then
				self:_hint("Back to Skyhold...")
			end
			return
		end
		self:_shown("Skyhold (home)", h.gate, why)
		h.revealAt = now
		self._flareAt = now
		if h.portal then
			for _, r in h.portal.risers do
				r.startAt = r.startAt or now
			end
		end
		pcall(function()
			local sound = self._audio:Play("portal_enter", 0.04)
			if sound then
				sound.Volume *= 0.7
			end
		end)
	end
	local e = Crossing.emerge((now - h.revealAt) / slow(), CFG.home)
	self:_setDark(e.dark)
	if h.centre and onIslandRoot(player.Character) then
		self:_riseShot(h.centre, h.radius, e.camera)
	else
		self._camera:SetCrossing(nil)
	end
	if not e.held then
		ControlLock.set(LOCK, false)
	end
	if e.done then
		self:_finishHome()
	end
end

function PortalController:_finishHome()
	local h = self._home
	self._home = nil
	if not h then
		return
	end
	self._camera:SetCrossing(nil)
	ControlLock.set(LOCK, false)
	self:_setDark(0)
end

-- a party coming home, as everyone on the island sees it: each of them rises
-- out of the portal on the plaza as they appear there (this player's own mates
-- with this player, once their own black has cleared)
function PortalController:_watchHomecomings()
	local state = self._state
	if not state:OnIsland() then
		return
	end
	local now = os.clock()
	local count = 0
	for _ in self._returning do
		count += 1
	end
	for uid, since in self._returning do
		if now - since > 12 then
			self._returning[uid] = nil
			continue
		end
		local other = Players:GetPlayerByUserId(uid)
		local character = other and other.Character
		local root = onIslandRoot(character)
		if other ~= player and root and placed(character, true) then
			local flat = root.Position - self._returnAt
			if Vector3.new(flat.X, 0, flat.Z).Magnitude < HOME_NEAR then
				self._returning[uid] = nil
				local centre, radius = self:_homePortal(count)
				local g = self:_rise("home", centre, radius, CFG.home)
				local mine = self._home
				local startAt = if mine and not mine.revealAt then nil elseif mine then now else now + WATCH_DELAY
				self:_riser(g, character, startAt)
				if not mine then
					pcall(function()
						local sound = self._audio:PlayAt("portal_enter", g.portal.folder:FindFirstChild("Card"), 0.05)
						if sound then
							sound.RollOffMaxDistance = 200
						end
					end)
				end
			end
		end
	end
end

-- ------------------------------------------------------------------ every frame

function PortalController:_frame(dt: number)
	local state = self._state
	local onIsland = state:OnIsland()
	self:_drawPortal(dt, onIsland)
	Sink.tidy()
	self:_islandDepartures(dt)
	self:_islandSinking()
	self:_watchHomecomings()
	if self._joining then
		self:_join()
	end
	local arriving, home = self._arriving, self._home
	self:_cover(self._joining ~= nil or (arriving ~= nil and arriving.revealAt == nil) or (home ~= nil and home.revealAt == nil))
	local phase = state.phase
	if phase == "Results" or phase == "Victory" or phase == "Wipe" then
		local root = state:Root()
		if root then
			self._endRoot = root
		elseif self._endRoot then
			-- the run let go of the hero a moment before it says so: the black covers
			-- that moment (the way home starts from it)
			self:_setDark(1)
			self:_stepRises(dt)
			return
		end
	else
		self._endRoot = nil
	end
	if self._arriving then
		self:_arrival(dt)
	elseif self._home then
		self:_homecoming()
	else
		self:_myDeparture()
		local unwind = self._unwinding
		if unwind and not self._departing then
			local k = math.clamp((os.clock() - unwind.started) / 0.5, 0, 1)
			self:_setDark(unwind.from * (1 - Crossing.smooth(k)))
			if k >= 1 then
				self._unwinding = nil
			end
		end
	end
	self:_stepRises(dt)
end

return PortalController

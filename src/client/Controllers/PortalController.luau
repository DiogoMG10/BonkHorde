--!nonstrict
-- PortalController - Skyhold's portal and the party's crossing through it (T8).
--
--   the portal   its face is a vortex: turning layers of teal light over a deep
--                core, a rim of light, motes drawn in from the ring and a light
--                on the plaza. Everyone on the island sees it surge through a
--                party's countdown, flare as a party goes through or comes back,
--                and sleep while the run is in use. The ring's runes, the
--                obelisks' crystals, the plaza's inlay and the orbiting stones
--                light with it (HubDecorController speeds the stones up).
--   departure    for the party, the last moments of its countdown: held still,
--                the camera swings up to frame the portal, the heroes glow and
--                turn to light, and the light closes in from the portal. Others
--                on the island see the heroes glow and vanish in a burst.
--   arrival      in the Wardwood the light holds until the hero is set down and
--                the wood round them is there (streamed in, its art drawn, the
--                rest of the party arrived), then clears round the hero, the
--                camera drops in behind them, every member takes shape over a
--                swirl of light on the ground, and the controls come back.
--   home         back from a run: in the light until the island hero stands at
--                the portal and the island round them is there, then out of it.
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
-- The server decides everything (PartyService, RunDirectorService): this only
-- watches the hub's parties and the run's phase (StateController). Timings are
-- Config/Skyhold.Crossing, the curves Core/Crossing. Every effect is cosmetic
-- and pcall-isolated; every hold on the controls has a deadline (ControlLock).

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Crossing = require(ReplicatedStorage.Shared.Core.Crossing)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)
local SkyholdGen = require(ReplicatedStorage.Shared.Core.SkyholdGen)
local ControlLock = require(script.Parent.Parent.ControlLock)
local Vfx = require(script.Parent.Parent.Vfx)
local WorldProbe = require(script.Parent.Parent.WorldProbe)

local PortalController = Knit.CreateController({ Name = "PortalController" })

local player = Players.LocalPlayer
local CFG = Skyhold.Crossing
local LOCK = "crossing"

local LIGHT = Color3.fromRGB(226, 255, 246) -- the light the party goes into
local MINT = Color3.fromRGB(150, 255, 236)
local TEAL = Color3.fromRGB(64, 214, 200)
local DEEP = Color3.fromRGB(16, 92, 112)
local SLEEP = Color3.fromRGB(90, 120, 200) -- the run is in use
local CREAM = Color3.fromRGB(255, 238, 196)
local GLOW_TO = Color3.fromRGB(205, 255, 244) -- what the portal's neon pieces brighten towards
local PLACED_NEAR = 14 -- studs: a hero this near where the server set it down stands there
local BELOW_ISLAND = 60 -- studs under the island's origin: the Wardwood

-- Studio only: `Workspace:SetAttribute("BonkCrossingSlow", 4)` plays the
-- arrival and the homecoming four times slower, to look at them
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
	self._charge = Crossing.Idle -- shown (eased)
	self._flareAt = -math.huge
	self._totals = {} -- circle -> the countdown's length when it was first seen
	self._watched = {} -- userId -> { highlight, motes, at } for heroes about to go
	self._phases = {} -- circle -> the party phase last seen
	self._departing = nil
	self._arriving = nil
	self._home = nil
	self._neon = nil
	-- the loading screen is up from the first frame: the hero is held with it
	self._joining = { gate = Crossing.wait(os.clock()) }
	self._knitStarted = false
	self._preloaded = false
	self._covered = false
end

function PortalController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._camera = Knit.GetController("CameraController")
	self._audio = Knit.GetController("AudioController")
	self._artKit = Knit.GetController("ArtController")
	self._lite = lite()
	self:_makeLight()
	ControlLock.set(LOCK, true, CFG.join.max + 1)
	Knit.OnStart():andThen(function()
		self._knitStarted = true
	end)
	task.spawn(function()
		-- what the island shows first: the portal's vortex and its motes (the
		-- island's own UI is drawn from text and frames)
		pcall(function()
			ContentProvider:PreloadAsync({ Vfx.Tex.glow, Vfx.Tex.swirl, Vfx.Tex.ring_thin, Vfx.Tex.dot, Vfx.Tex.star4 })
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
	self._returnAt = Vector3.new(SkyholdGen.world(Skyhold, r.x, rh + 3, r.z))

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
			-- whatever was held is let go, whatever was covered is shown
			ControlLock.set(LOCK, false)
			self._camera:SetCrossing(nil)
			self:_setLight(0)
		end
	end)
end

--- The portal's charge as drawn now, 0..1 (HubDecorController's stones read it).
function PortalController:Charge(): number
	return self._charge
end

-- ------------------------------------------------------------------ the light overlay

function PortalController:_makeLight()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crossing"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60 -- over everything the game draws, under Roblox's own menu
	gui.Enabled = false
	local fill = Instance.new("Frame")
	fill.Name = "Light"
	fill.BackgroundColor3 = LIGHT
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = gui
	-- the light blooming out of the portal before it fills the screen
	local bloom = Instance.new("ImageLabel")
	bloom.Name = "Bloom"
	bloom.BackgroundTransparency = 1
	bloom.Image = Vfx.Tex.glow
	bloom.ImageColor3 = LIGHT
	bloom.ImageTransparency = 1
	bloom.AnchorPoint = Vector2.new(0.5, 0.5)
	bloom.Size = UDim2.fromScale(0, 0)
	bloom.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	self._lightGui, self._lightFill, self._bloom = gui, fill, bloom
end

--- How much of the screen is light, 0..1; `bloom` (0..1) grows the glow out of
--- the portal's place on screen first.
function PortalController:_setLight(amount: number, bloom: number?)
	local gui = self._lightGui
	if not gui then
		return
	end
	amount = math.clamp(amount, 0, 1)
	bloom = math.clamp(bloom or 0, 0, 1)
	gui.Enabled = amount > 0.001 or bloom > 0.001
	self._lightNow = amount
	self._lightFill.BackgroundTransparency = 1 - amount
	local image = self._bloom
	image.ImageTransparency = 1 - bloom * 0.9
	if bloom > 0 then
		local camera = Workspace.CurrentCamera
		local at, onScreen = camera:WorldToViewportPoint(self._centre)
		if onScreen then
			image.Position = UDim2.fromOffset(at.X, at.Y)
		else
			image.Position = UDim2.fromScale(0.5, 0.45)
		end
		local size = 0.2 + 3.2 * bloom * bloom
		image.Size = UDim2.new(size * 1.2, 0, size * 1.2 * camera.ViewportSize.X / math.max(camera.ViewportSize.Y, 1), 0)
	end
end

-- ------------------------------------------------------------------ the portal

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
		faceBase = { colour = face.Color, transparency = face.Transparency },
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

-- countdown lengths, and the moment each party goes through
function PortalController:_onHub()
	local state = self._state
	local seen = {}
	for _, party in state.hub.circles or {} do
		seen[party.circle] = true
		local before = self._phases[party.circle]
		if party.phase == "countdown" and before ~= "countdown" then
			self._totals[party.circle] = state:CountdownLeft(party) or Skyhold.CountdownSeconds
		end
		if party.phase == "run" and (before == "countdown" or before == "waiting") then
			self:_partyWent(party)
		end
		self._phases[party.circle] = party.phase
	end
	for circle in self._phases do
		if not seen[circle] then
			self._phases[circle] = nil
		end
	end
end

-- a party went through: the portal surges, its heroes vanish in light
function PortalController:_partyWent(party)
	self._flareAt = os.clock()
	if not self._state:OnIsland() then
		return
	end
	pcall(Vfx.burst, "PortalSurge", self._centre)
	for _, uid in party.members do
		local watched = self._watched[uid]
		local at = watched and watched.at
		if at then
			pcall(Vfx.burst, "PortalDepart", at)
		end
	end
	local v = self._vortexData
	if v and not table.find(party.members, player.UserId) then
		-- heard from the portal by everyone else on the island
		pcall(function()
			local sound = self._audio:PlayAt("portal_open", v.card, 0.05)
			if sound then
				sound.RollOffMaxDistance = 260
			end
		end)
	end
end

local function setFade(character: Model?, amount: number)
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = amount
		end
	end
end

-- the heroes of a party in its last moments glow and turn to light, everyone
-- on the island seeing it, and are watched so the burst that takes them
-- happens where they stood
function PortalController:_watchParties()
	local state = self._state
	local want = {} -- userId -> how far that party's departure has gone
	if state:OnIsland() then
		for _, party in state.hub.circles or {} do
			local left = party.phase == "countdown" and state:CountdownLeft(party)
			if left and left <= CFG.lead then
				local d = Crossing.departure(left, CFG)
				for _, uid in party.members do
					want[uid] = d
				end
			end
		end
	end
	for uid, d in want do
		local other = Players:GetPlayerByUserId(uid)
		local character = other and other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local w = self._watched[uid]
		if root then
			if not w or w.character ~= character then
				if w then
					self:_unwatch(uid)
				end
				local highlight = Instance.new("Highlight")
				highlight.FillColor = MINT
				highlight.OutlineColor = LIGHT
				highlight.FillTransparency = 1
				highlight.OutlineTransparency = 1
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Parent = character
				local motes = if self._lite then {} else Vfx.attach("DepartMotes", root)
				w = { character = character, highlight = highlight, motes = motes }
				self._watched[uid] = w
			end
			w.at = root.Position
			w.highlight.FillTransparency = 1 - 0.6 * d.k
			w.highlight.OutlineTransparency = 1 - 0.85 * d.k
			setFade(character, d.dissolve * 0.85)
		end
	end
	for uid in self._watched do
		if not want[uid] then
			self:_unwatch(uid)
		end
	end
end

function PortalController:_unwatch(uid: number)
	local w = self._watched[uid]
	if not w then
		return
	end
	self._watched[uid] = nil
	pcall(function()
		w.highlight:Destroy()
		for _, e in w.motes do
			e:Destroy()
		end
		-- called off: the hero is whole again (a hero who went is gone anyway)
		if w.character.Parent then
			setFade(w.character, 0)
		end
	end)
end

-- ------------------------------------------------------------------ this player's crossing

--- My party, if it is on a circle.
function PortalController:_myParty()
	local state = self._state
	local mine = state:Mine()
	return mine and mine.circle and state:PartyAt(mine.circle)
end

-- the last moments of my party's countdown, on the island
function PortalController:_departure()
	local state = self._state
	local party = self:_myParty()
	local left = party and party.phase == "countdown" and state:CountdownLeft(party)
	local d = if left and state:OnIsland() then Crossing.departure(left, CFG) else nil
	local going = self._departing
	if d and d.active then
		if not going then
			going = { since = os.clock(), opened = false }
			self._departing = going
			local hum = self._audio:Play("shrine_charge_loop")
			if hum then
				hum.Volume = 0
				TweenService:Create(hum, TweenInfo.new(0.5), { Volume = 0.32 }):Play()
			end
			going.hum = hum
		end
		ControlLock.set(LOCK, true, CFG.lead + CFG.arrive.max + 1.5)
		local root = state:Root()
		if root then
			-- behind the hero, a little above, framing the portal over them
			local away = root.Position - self._centre
			away = Vector3.new(away.X, 0, away.Z)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.zAxis
			local eye = root.Position + away * 11 + Vector3.new(0, 6.5, 0)
			self._camera:SetCrossing(CFrame.lookAt(eye, self._centre), 74 + 10 * d.camera, d.camera)
		end
		if going.hum then
			going.hum.PlaybackSpeed = 0.9 + 0.7 * d.k
		end
		if d.light > 0 and not going.opened then
			going.opened = true
			self._audio:Play("portal_open")
		end
		self:_setLight(d.light * d.light, d.light)
		going.light = d.light
		return
	end
	if not going then
		return
	end
	-- the countdown is over: through the portal (the run's intro takes over), or
	-- called off (back on the island as we were)
	local through = (party and party.phase == "run") or state.phase == "Intro"
	if through then
		self:_setLight(1)
		self:_endDeparture(false)
	else
		self:_endDeparture(true)
	end
end

function PortalController:_endDeparture(restore: boolean)
	local going = self._departing
	self._departing = nil
	if not going then
		return
	end
	if going.hum then
		local hum = going.hum
		TweenService:Create(hum, TweenInfo.new(0.35), { Volume = 0 }):Play()
		task.delay(0.4, function()
			hum:Destroy()
		end)
	end
	if restore then
		ControlLock.set(LOCK, false)
		self._camera:SetCrossing(nil)
		-- the light goes back the way it came
		local from = going.light or 0
		if from > 0 then
			local started = os.clock()
			self._unwinding = { from = from, started = started }
		else
			self:_setLight(0)
		end
	end
end

-- the run's phase: into the Wardwood, or home
function PortalController:_onPhase()
	local state = self._state
	local phase, last = state.phase, self._lastPhase
	self._lastPhase = phase
	if phase == last then
		return
	end
	if phase == "Intro" then
		self:_endDeparture(false)
		self._unwinding = nil
		self._home = nil
		ControlLock.set(LOCK, true, CFG.arrive.max + CFG.release + 1.5)
		-- the light finishes closing in from wherever the departure had got to
		-- (straight into a run, with no countdown: from nothing, quickly)
		local now = os.clock()
		self._arriving = { since = now, gate = Crossing.wait(now), revealAt = nil, formed = {}, fromLight = self._lightNow or 0 }
	elseif phase == "Lobby" and last ~= "Lobby" then
		self:_finishArrival()
		self._flareAt = os.clock()
		self:_setLight(1)
		ControlLock.set(LOCK, true, CFG.home.max + 1)
		self._home = { since = os.clock(), gate = Crossing.wait(os.clock()), revealAt = nil }
	elseif (phase == "Results" or phase == "Victory" or phase == "Wipe") and self._arriving then
		-- the run ended before the hero was seen: nothing more to wait for
		self:_finishArrival()
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

function PortalController:_reveal()
	local a = self._arriving
	if not a or a.revealAt then
		return
	end
	a.revealAt = os.clock()
end

-- a hero stepping out of the light: a swirl on the ground, a ring, a burst
local function arriveAt(position: Vector3)
	local ground = position - Vector3.new(0, 2.8, 0)
	local k = slow()
	pcall(Vfx.ground, ground, "swirl", MINT, 1.5, 7.5, 1.0 * k, { spin = 220, alpha = 0.15, hold = 0.35 })
	pcall(Vfx.ground, ground + Vector3.new(0, 0.05, 0), "ring_thin", LIGHT, 2, 16, 0.85 * k, { alpha = 0.1, hold = 0.2 })
	pcall(Vfx.burst, "PortalArrive", position)
end

function PortalController:_arrival()
	local a = self._arriving
	if not a then
		return
	end
	local state = self._state
	local now = os.clock()
	local root = state:Root()
	if not a.revealAt then
		-- in the light until this player's Wardwood hero is set down and the wood
		-- round them is there: streamed in, its art drawn (all at once, unseen),
		-- the rest of the party arrived; a while at most (CFG.arrive)
		local into = math.min(1, a.fromLight + (now - a.since) / 0.2)
		self:_setLight(into)
		local facts = self:_facts(false)
		if facts.placed and root then
			-- the camera already waits where it will drop in from, so what it will
			-- see is what is drawn and streamed under the light
			self:_dropIn(root, 1)
			local drawn = self._artKit:Prepare(root.Position)
			facts.detail = facts.streamed and drawn and self:_squadPlaced()
		end
		local ready, why = Crossing.step(a.gate, facts, now, CFG.arrive)
		if not (ready and into >= 1) then
			return
		end
		self:_shown("the Wardwood", a.gate, why)
		self:_reveal()
	end
	local t = (now - a.revealAt) / slow()
	local arc = Crossing.arrival(t, CFG)
	self:_setLight(arc.light)
	if inWardwood(root) then
		self:_dropIn(root, arc.camera)
	else
		self._camera:SetCrossing(nil) -- no hero to drop in on (yet): the camera is its own
	end
	-- every member takes shape as they appear (the server sets them down together)
	for _, mate in self:_squad() do
		local character = mate.Character
		local mateRoot = character and character:FindFirstChild("HumanoidRootPart")
		if inWardwood(mateRoot) then
			local formed = a.formed[mate]
			if not formed or formed.character ~= character then
				formed = { character = character, at = now }
				a.formed[mate] = formed
				arriveAt(mateRoot.Position)
			end
			local k = Crossing.smooth(((now - formed.at) / slow() - 0.05) / CFG.materialise)
			setFade(character, 1 - k)
		end
	end
	if not arc.held then
		ControlLock.set(LOCK, false)
	end
	if arc.done and t > CFG.materialise + 0.3 then
		self:_finishArrival()
	end
end

-- the arrival's camera: from above and behind the hero, `weight` of the way
-- there from its own place behind them
function PortalController:_dropIn(root: BasePart, weight: number)
	local yaw = self._camera:Yaw()
	local back = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local eye = root.Position + back * 19 + Vector3.new(0, 15, 0)
	self._camera:SetCrossing(CFrame.lookAt(eye, root.Position + Vector3.new(0, 2, 0)), 82, weight)
end

function PortalController:_finishArrival()
	local a = self._arriving
	self._arriving = nil
	if not a then
		return
	end
	for _, formed in a.formed do
		setFade(formed.character, 0)
	end
	self._camera:SetCrossing(nil)
	ControlLock.set(LOCK, false)
	self:_setLight(0)
end

-- home from a run: in the light until the island hero is at the portal
function PortalController:_homecoming()
	local h = self._home
	if not h then
		return
	end
	local now = os.clock()
	local root = self._state:Root()
	if not h.revealAt then
		-- in the light until the island hero stands at the portal and the island
		-- round them is there, the portal lit again; a while at most (CFG.home)
		local facts = self:_facts(true)
		if facts.placed and facts.streamed then
			facts.detail = self:_vortex() ~= nil
		end
		local ready, why = Crossing.step(h.gate, facts, now, CFG.home)
		if ready then
			self:_shown("Skyhold (home)", h.gate, why)
			h.revealAt = now
			self._flareAt = now
			ControlLock.set(LOCK, false)
			if root then
				arriveAt(root.Position) -- out of the portal, onto the plaza
			end
			pcall(function()
				local sound = self._audio:Play("portal_enter", 0.04)
				if sound then
					sound.Volume *= 0.7
				end
			end)
		else
			self:_setLight(1)
			return
		end
	end
	local light = Crossing.home((now - h.revealAt) / slow(), CFG)
	self:_setLight(light)
	if light <= 0 then
		self._home = nil
		self:_setLight(0)
	end
end

-- ------------------------------------------------------------------ every frame

function PortalController:_frame(dt: number)
	local state = self._state
	local onIsland = state:OnIsland()
	self:_drawPortal(dt, onIsland)
	self:_watchParties()
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
			-- the run let go of the hero a moment before it says so: the light covers
			-- that moment (the way home starts from it)
			self:_setLight(1)
			return
		end
	else
		self._endRoot = nil
	end
	if self._arriving then
		self:_arrival()
	elseif self._home then
		self:_homecoming()
	else
		self:_departure()
		local unwind = self._unwinding
		if unwind and not self._departing then
			local k = math.clamp((os.clock() - unwind.started) / 0.5, 0, 1)
			self:_setLight(unwind.from * (1 - Crossing.smooth(k)))
			if k >= 1 then
				self._unwinding = nil
			end
		end
	end
end

return PortalController

--!nonstrict
-- OverlayController - the pause: the vote with the squad, the notice at the
-- top of the screen, the 3-2-1 back into play and the paused world's look; the
-- touch controls; and the settings kept in the profile. The menu itself
-- (build, actions, stats, settings, map) is PauseMenuController's (T3). The
-- big map in the Overlay ScreenGui belongs to MinimapController.
--
-- Roblox owns Esc, so the menu is P or the gamepad Start button (a PAUSE
-- button on touch). Solo, that asks the server (PauseService) for a pause,
-- which comes at once, and the menu opens on its word. In co-op it opens the
-- same menu straight away while the world keeps running, and the menu says so;
-- its REQUEST PAUSE asks the squad, and the run only pauses once everyone has
-- agreed. Closing the menu never takes a request or a vote back (CANCEL does).
-- Once the run is really paused the menu opens for everyone; co-op plays on
-- once every player has pressed READY. Outside a run, and from the main
-- menu's SETTINGS button, the same menu shows the settings alone.
--
-- While the run is really paused (any reason) the world is softly desaturated
-- and darkened. Going back in after a co-op pause, a 3-2-1 countdown plays
-- over the frozen world and the colour returns with it.
--
-- The settings live as attributes on PlayerGui so any controller can read
-- them and listen for changes:
--   MasterVolume  0..1   MusicVolume 0..1   SfxVolume 0..1
--   Sensitivity   0.2..2 (x the configured camera sensitivity; 1 = default)
--   DamageNumbers boolean
--   EnemyOutlines boolean, off by default (EnemyRenderController draws them)
-- The volumes and EnemyOutlines are kept in the profile (DataService) between
-- sessions; without a datastore (a local Studio test) they last the session.
-- The touch buttons do what the keys do. Slide and jump are published as the
-- attributes BonkSlideHeld and BonkJumpHeld on PlayerGui for MovementController.

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local UiKit = require(script.Parent.Parent.UiKit)

local OverlayController = Knit.CreateController({ Name = "OverlayController" })

local player = Players.LocalPlayer

local DEFAULTS = {
	MasterVolume = 0.7,
	MusicVolume = 0.45,
	SfxVolume = 0.55,
	Sensitivity = 1,
	DamageNumbers = true,
	EnemyOutlines = false,
}
local VOLUMES = { master = "MasterVolume", music = "MusicVolume", sfx = "SfxVolume" }
local AMBER = Color3.fromHex("#FFB23A")
-- the notice's own place (design pixels from the top), and its gap under the
-- HUD's top centre column when that reaches further down
local NOTICE_TOP = 140
local NOTICE_GAP = 10
-- the paused world: how far colour and light drop at full strength
local GRADE_SATURATION, GRADE_BRIGHTNESS, GRADE_CONTRAST = -0.6, -0.07, -0.05

local function noPause()
	return { mode = "none", votes = {}, need = 0, seconds = 0 }
end

function OverlayController:KnitInit()
	self._menuMode = nil -- nil, "pause" (the run is paused), "inspect" (co-op, running) or "settings"
	self._returnFocus = nil
	self._info = noPause() -- the last word from PauseService
	self._infoAt = 0
	self._hint = nil -- { text, untilAt }: a short refusal shown in the notice and the menu
	self._volumesLoaded = false
	self._volumesSent = nil
	self._grade = 0 -- the paused-world look, 0..1
	self._cdShown = nil -- the countdown text on screen
	self._cdTotal = nil -- how long this countdown was when first seen
	self._cdStamp = 0
	self._choicesWere = false
	local gui = UiKit.playerGui()
	for name, value in DEFAULTS do
		if gui:GetAttribute(name) == nil then
			gui:SetAttribute(name, value)
		end
	end
	gui:SetAttribute("BonkSlideHeld", false)
	gui:SetAttribute("BonkJumpHeld", false)
end

function OverlayController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._camera = Knit.GetController("CameraController")
	self._world = Knit.GetController("WorldController")
	self._menu = Knit.GetController("PauseMenuController")
	self._choices = Knit.GetController("ChoiceController")
	self._hud = Knit.GetController("HudController")
	UiKit.safe("OverlayController", function()
		self:_start()
	end)
end

--- Is the menu open (paused, inspecting or settings)?
function OverlayController:IsPaused(): boolean
	return self._menuMode ~= nil
end

--- The main menu's SETTINGS button. `back` gets the gamepad focus on close.
function OverlayController:OpenSettings(back: Instance?)
	self._returnFocus = back
	self:_openMenu("settings")
end

-- ---------------------------------------------------------------- what the menu reads

--- The last word from PauseService.
function OverlayController:Info()
	return self._info
end

function OverlayController:UserId(): number
	return player.UserId
end

--- Alone in the run: a pause comes at once and has no limit.
function OverlayController:IsSolo(): boolean
	return #self._state.squad <= 1
end

--- A refusal to show for a moment ("You can ask again in 12s"), or nil.
function OverlayController:Hint(): string?
	local hint = self._hint
	return if hint and os.clock() < hint.untilAt then hint.text else nil
end

function OverlayController:Ask(action: string)
	self:_ask(action)
end

function OverlayController:CloseMenu()
	self:_closeMenu()
end

function OverlayController:Voted(): boolean
	return self:_voted()
end

--- Seconds left on the vote or the pause; -1 for a pause with no limit (solo).
function OverlayController:SecondsLeft(): number
	return self:_secondsLeft()
end

-- ---------------------------------------------------------------- the menu

function OverlayController:_openMenu(mode: string)
	if self._menuMode == mode then
		self._menu:Refresh()
		return
	elseif not self._menu:Ready() then
		return -- the menu's ScreenGui has not arrived yet (the first moments after joining)
	end
	self._menuMode = mode
	self._menu:Open(mode)
	self._camera:SetUiOpen("pause", true)
	Knit.GetController("MinimapController"):SetBigMap(false) -- the menu has its own map
	self:_renderNotice()
end

function OverlayController:_closeMenu()
	if not self._menuMode then
		return
	end
	self._menuMode = nil
	self._menu:Close()
	self._camera:SetUiOpen("pause", false)
	self:_sendVolumes()
	if self._returnFocus then
		UiKit.focus(self._returnFocus)
		self._returnFocus = nil
	end
	self:_renderNotice()
end

function OverlayController:_inRun(): boolean
	local state = self._state
	return state:IsLive() and state.me ~= nil
end

function OverlayController:_ask(action: string)
	if self._askRemote then
		self._askRemote:FireServer(action)
	end
end

function OverlayController:_voted(): boolean
	return table.find(self._info.votes or {}, player.UserId) ~= nil
end

--- When the countdown back into play ends (os.clock time), or nil.
function OverlayController:_countdownEnd(): number?
	local info = self._info
	if info.mode == "paused" and info.resuming then
		return self._infoAt + math.max(0, tonumber(info.seconds) or 0)
	end
	return nil
end

function OverlayController:_secondsLeft(): number
	local seconds = tonumber(self._info.seconds) or 0
	if seconds < 0 then
		return -1
	end
	return math.max(0, seconds - (os.clock() - self._infoAt))
end

--- P, Start, or the touch PAUSE button.
function OverlayController:_pausePressed()
	local menu = self._menuMode
	if not self:_inRun() then
		if menu then
			self:_closeMenu()
		else
			self:_openMenu("settings")
		end
		return
	end
	local info = self._info
	if info.mode == "paused" then
		if info.resuming then
			return
		elseif menu == "pause" then
			self:_ask("resume") -- solo: back to play; co-op: READY (or not any more)
		else
			self:_openMenu("pause")
		end
	elseif self:IsSolo() then
		self:_ask("request") -- a solo pause comes at once; the menu opens on the server's word
	elseif menu == "inspect" then
		self:_closeMenu() -- a request or a vote stands: only CANCEL takes it back
	else
		if info.mode == "vote" and info.by ~= player.UserId and not self:_voted() then
			self:_ask("accept") -- as ever, P agrees to a teammate's request
		end
		self:_openMenu("inspect")
	end
end

--- The notice's own button: CANCEL for the asker, ACCEPT for the others.
function OverlayController:_noticePressed()
	local info = self._info
	if info.mode ~= "vote" then
		return
	end
	if info.by == player.UserId then
		self:_ask("withdraw")
	elseif not self:_voted() then
		self:_ask("accept")
	end
end

--- What PauseService says about the player pause.
function OverlayController:_onPause(p)
	if typeof(p) ~= "table" then
		return
	end
	if p.mode == "none" and (tonumber(p.cooldown) or 0) > 0 and self._info.mode == "none" then
		-- our request was refused: say why for a moment
		self._hint = { text = `You can ask again in {math.ceil(p.cooldown)}s`, untilAt = os.clock() + 2 }
	end
	self._info = p
	self._infoAt = os.clock()
	if p.mode == "paused" and not p.resuming then
		if self._menuMode ~= "pause" and self:_inRun() then
			self:_openMenu("pause")
		end
	elseif self._menuMode == "pause" then
		self:_closeMenu()
	end
	self._menu:Refresh()
	self:_renderNotice()
end

function OverlayController:_keyName(): string
	local last = UserInputService:GetLastInputType()
	if string.sub(last.Name, 1, 7) == "Gamepad" then
		return "Start"
	elseif last == Enum.UserInputType.Touch then
		return "PAUSE"
	end
	return "P"
end

--- The notice at the top of the screen, while the menu is closed (the menu
--- shows the same thing itself).
function OverlayController:_renderNotice()
	local n = self._notice
	if not n or not n.frame then
		return
	end
	local info = self._info
	local title, sub, action = nil, nil, nil
	local subColour = AMBER
	if self._menuMode then
		title = nil
	elseif info.mode == "vote" then
		local agreed = #(info.votes or {})
		local left = math.ceil(self:_secondsLeft())
		local who = `{info.byName or "A teammate"} wants to pause`
		local still = `Game still running · {agreed}/{info.need} agreed · {left}s`
		if info.by == player.UserId then
			title, sub, action = "PAUSE REQUESTED", still, "CANCEL"
		elseif self:_voted() then
			title, sub = who, still
		else
			title, sub, action = who, `Game still running · {self:_keyName()} to agree · {left}s`, "ACCEPT"
		end
	elseif info.mode == "paused" and not info.resuming and self:_inRun() then
		local seconds = self:_secondsLeft()
		title = if seconds >= 0 then `PAUSED  {UiKit.clock(math.ceil(seconds))}` else "PAUSED"
		sub, subColour = `{self:_keyName()} to open the menu`, UiKit.Colours.ink
	elseif self._hint and os.clock() < self._hint.untilAt then
		title, sub = "NOT PAUSED", self._hint.text
	end
	UiKit.show(n.frame, title ~= nil)
	if title then
		UiKit.text(n.title, title)
		UiKit.text(n.sub, sub or "")
		UiKit.textColour(n.sub, subColour)
		UiKit.show(n.action, action ~= nil)
		UiKit.text(n.actionLabel, action or "")
		self:_placeNotice()
	end
end

--- The notice sits under everything in the HUD's top centre column (timer,
--- boss bars, banners), never over it.
function OverlayController:_placeNotice()
	local frame = self._notice and self._notice.frame
	if not frame or not frame:IsA("GuiObject") then
		return
	end
	local overlay = frame:FindFirstAncestorOfClass("ScreenGui")
	local scale = overlay and UiKit.scaleOf(overlay)
	local s = if scale and scale.Scale > 0 then scale.Scale else 1
	local top = NOTICE_TOP
	local bottom = self._hud and self._hud:TopBottom()
	if bottom then
		top = math.max(top, bottom / s + NOTICE_GAP)
	end
	local position = UDim2.new(0.5, 0, 0, math.floor(top + 0.5))
	if frame.Position ~= position then
		frame.Position = position
	end
end

-- ---------------------------------------------------------------- volumes

--- The profile's saved volumes, applied once per session (a later profile
--- push must not undo a slider the player is moving).
function OverlayController:_loadVolumes()
	local profile = self._state.profile
	if self._volumesLoaded or not profile then
		return
	end
	self._volumesLoaded = true
	local saved = if typeof(profile.settings) == "table" then profile.settings else {}
	local gui = UiKit.playerGui()
	for key, attribute in VOLUMES do
		if typeof(saved[key]) == "number" then
			gui:SetAttribute(attribute, math.clamp(saved[key], 0, 1))
		end
	end
	if typeof(saved.outlines) == "boolean" then
		gui:SetAttribute("EnemyOutlines", saved.outlines)
	end
	self._volumesSent = self:_volumeSignature()
end

function OverlayController:_volumeSignature(): string
	local gui = UiKit.playerGui()
	return `{gui:GetAttribute("MasterVolume")}:{gui:GetAttribute("MusicVolume")}:{gui:GetAttribute("SfxVolume")}:{gui:GetAttribute(
		"EnemyOutlines"
	)}`
end

--- Hand changed settings to the profile (on closing the menu).
function OverlayController:_sendVolumes()
	local signature = self:_volumeSignature()
	if signature == self._volumesSent or not self._settingsRemote then
		return
	end
	self._volumesSent = signature
	local gui = UiKit.playerGui()
	local out = {}
	for key, attribute in VOLUMES do
		out[key] = tonumber(gui:GetAttribute(attribute))
	end
	out.outlines = gui:GetAttribute("EnemyOutlines") == true
	self._settingsRemote:FireServer(out)
end

-- ---------------------------------------------------------------- setup

function OverlayController:_start()
	local overlay = UiKit.gui("Overlay")
	if not overlay then
		return
	end
	local gui = UiKit.playerGui()
	local state = self._state

	local countdown = UiKit.find(overlay, "ResumeCountdown")
	self._countdown = countdown
	self._cdNumber = UiKit.find(countdown, "Number")
	UiKit.show(countdown, false)
	if self._cdNumber then
		local pop = Instance.new("UIScale")
		pop.Name = "Pop"
		pop.Parent = self._cdNumber
		self._cdPop = pop
	end
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "BonkPauseGrade"
	grade.Enabled = false
	grade.Parent = Lighting
	self._gradeFx = grade

	local notice = UiKit.find(overlay, "PauseNotice")
	self._notice = {
		frame = notice,
		title = UiKit.find(notice, "Title"),
		sub = UiKit.find(notice, "Sub"),
		action = UiKit.find(notice, "ActionButton"),
		actionLabel = UiKit.find(notice, "ActionButton.Label"),
	}
	UiKit.show(notice, false)
	UiKit.button(self._notice.action, function()
		self:_noticePressed()
	end)
	self._hud.TopChanged:Connect(function()
		UiKit.safe("OverlayController.notice", function()
			self:_placeNotice()
		end)
	end)

	self._askRemote = Net.client("PauseAsk")
	self._settingsRemote = Net.client("Settings")
	local pauseRemote = Net.client("Pause")
	if pauseRemote then
		pauseRemote.OnClientEvent:Connect(function(p)
			UiKit.safe("OverlayController.Pause", function()
				self:_onPause(p)
			end)
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonStart or (key == Enum.KeyCode.P and not processed) then
			UiKit.safe("OverlayController.pause", function()
				self:_pausePressed()
			end)
		end
	end)

	state.Changed:Connect(function(key)
		UiKit.safe("OverlayController.state", function()
			if key == "profile" then
				self:_loadVolumes()
			elseif key == "phase" then
				local live = state:IsLive()
				local menu = self._menuMode
				if (menu == "settings" and live) or ((menu == "pause" or menu == "inspect") and not live) then
					self:_closeMenu()
				end
				if not live then
					self._info = noPause()
					self._hint = nil
					self:_renderNotice()
				end
			end
		end)
	end)
	self:_loadVolumes()

	-- every frame: the paused-world look and the 3-2-1; ten times a second:
	-- the timers in the notice, and a co-op inspection making way for a panel
	local tick = 0
	local broken = false
	RunService.Heartbeat:Connect(function(dt)
		if not broken then
			local ok, err = pcall(function()
				self:_renderCountdown(dt)
			end)
			if not ok then
				broken = true -- one warning, not one per frame
				warn(`[OverlayController] countdown stopped: {err}`)
			end
		end
		tick += dt
		if tick < 0.1 then
			return
		end
		tick = 0
		UiKit.safe("OverlayController.notice", function()
			-- a level-up or a chest that opens while inspecting needs the
			-- screen, and its clock is running: the inspection gives way
			local choicesOpen = self._choices:IsOpen()
			if choicesOpen and not self._choicesWere and self._menuMode == "inspect" then
				self:_closeMenu()
			end
			self._choicesWere = choicesOpen
			if self._hint and os.clock() >= self._hint.untilAt then
				self._hint = nil
			end
			if self._info.mode ~= "none" or self._hint then
				self:_renderNotice()
			end
		end)
	end)

	-- ------------------------------------------------------------ touch controls

	local touch = UiKit.find(overlay, "TouchControls")
	self._touch = touch
	UiKit.show(touch, false)
	if not UserInputService.TouchEnabled or not touch then
		return
	end

	local function plain(button: Instance?)
		if button and button:IsA("GuiButton") then
			button.Selectable = false
		end
	end
	-- held buttons: down on the press, up when that same finger lifts, wherever it is
	local function hold(button: Instance?, onChange: (boolean) -> ())
		plain(button)
		if not button or not button:IsA("GuiObject") then
			return
		end
		button.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			onChange(true)
			local conn: RBXScriptConnection
			conn = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				local now = input.UserInputState
				if now == Enum.UserInputState.End or now == Enum.UserInputState.Cancel then
					conn:Disconnect()
					onChange(false)
				end
			end)
		end)
	end

	hold(UiKit.find(touch, "JumpButton"), function(down)
		self._jumpHeld = down
		gui:SetAttribute("BonkJumpHeld", down)
		if down then
			self:_jump()
		end
	end)
	hold(UiKit.find(touch, "SlideButton"), function(down)
		gui:SetAttribute("BonkSlideHeld", down)
	end)

	local interact = Net.client("Interact")
	local interactButton = UiKit.find(touch, "InteractButton")
	plain(interactButton)
	UiKit.button(interactButton, function()
		local id = self._world:PromptId()
		if id and interact then
			interact:FireServer(id)
		end
	end)
	local tabButton = UiKit.find(touch, "TabButton")
	plain(tabButton)
	UiKit.button(tabButton, function()
		Knit.GetController("MinimapController"):ToggleBigMap()
	end)
	local pauseButton = UiKit.find(touch, "PauseButton")
	plain(pauseButton)
	UiKit.button(pauseButton, function()
		self:_pausePressed()
	end)

	-- These replace the buttons ContextActionService and Roblox draw for the same actions.
	task.spawn(function()
		for _ = 1, 20 do
			local done = 0
			for _, action in { "BonkSlide", "BonkInteract" } do
				local ok, button = pcall(function()
					return ContextActionService:GetButton(action)
				end)
				if ok and button then
					button.Visible = false
					done += 1
				end
			end
			local touchGui = gui:FindFirstChild("TouchGui")
			local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
			local jump = frame and frame:FindFirstChild("JumpButton")
			if jump and jump:IsA("GuiObject") then
				jump.Visible = false
				done += 1
			end
			if done >= 3 then
				break
			end
			task.wait(1)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if self._jumpHeld then
			self:_jump() -- holding jump re-jumps on landing
		end
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		-- while the horde is live (the death screen and the results have their
		-- own buttons, and these would sit on top of them), and on the island
		-- hub, where only moving and the menu apply (its prompts are tappable)
		local inRun = state:IsLive() and state.me ~= nil and state:Root() ~= nil
		local onIsland = state:OnIsland() and state:Root() ~= nil
		local visible = (inRun or onIsland) and not self._menuMode and not self._choices:IsOpen()
		UiKit.show(touch, visible)
		UiKit.show(interactButton, inRun)
		UiKit.show(tabButton, inRun)
		if not visible then
			if self._jumpHeld then
				self._jumpHeld = false
				gui:SetAttribute("BonkJumpHeld", false)
			end
			if gui:GetAttribute("BonkSlideHeld") then
				gui:SetAttribute("BonkSlideHeld", false)
			end
		end
	end)
end

--- The 3-2-1 back into play, and the paused world's colour returning with it.
function OverlayController:_renderCountdown(dt: number)
	local endAt = self:_countdownEnd()
	local left = if endAt then endAt - os.clock() else 0
	local live = self._state:IsLive()
	if left > 0 and live then
		self._cdTotal = self._cdTotal or math.max(left, 0.5)
		local digit = tostring(math.ceil(left))
		if digit ~= self._cdShown then
			self._cdShown = digit
			self:_showText(digit)
		end
	elseif self._cdShown then
		-- it just ran out: one quick word, then out of the way
		self._cdShown = nil
		self._cdTotal = nil
		if live then
			self:_showText("GO!")
			local stamp = self._cdStamp
			task.delay(0.45, function()
				if self._cdStamp == stamp then
					UiKit.show(self._countdown, false)
				end
			end)
		else
			UiKit.show(self._countdown, false)
		end
	end

	-- 1 while paused, falling with the countdown, 0 in play
	local target = 0
	if self._cdTotal and left > 0 then
		target = math.clamp(left / self._cdTotal, 0, 1)
	elseif self._state.paused and live then
		target = 1
	end
	self._grade += (target - self._grade) * math.min(1, dt * 8)
	local fx = self._gradeFx
	if fx then
		local g = self._grade
		fx.Enabled = g > 0.002
		fx.Saturation = GRADE_SATURATION * g
		fx.Brightness = GRADE_BRIGHTNESS * g
		fx.Contrast = GRADE_CONTRAST * g
	end
end

function OverlayController:_showText(text: string)
	self._cdStamp += 1
	UiKit.text(self._cdNumber, text)
	UiKit.show(self._countdown, true)
	if self._cdPop then
		self._cdPop.Scale = 1.45
		TweenService:Create(self._cdPop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

function OverlayController:_jump()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and not character:GetAttribute("Downed") then
		humanoid.Jump = true
	end
end

return OverlayController

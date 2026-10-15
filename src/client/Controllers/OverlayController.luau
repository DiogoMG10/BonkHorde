--!nonstrict
-- OverlayController - the Overlay ScreenGui's pause menu, the pause notice and
-- the touch controls. (The big map in the same ScreenGui belongs to
-- MinimapController.)
--
-- Roblox owns Esc, so pausing is P or the gamepad Start button (a PAUSE button
-- on touch). In a live run that asks the server (PauseService) for a pause:
-- solo it pauses at once; co-op it asks the squad, and the notice at the top
-- says plainly that the game is still running until everyone agrees. The menu
-- opens for everyone once the run is really paused. Outside a run, and from
-- the main menu's SETTINGS button, the same sheet opens as plain settings.
--
-- The settings live as attributes on PlayerGui so any controller can read
-- them and listen for changes:
--   MasterVolume  0..1   MusicVolume 0..1   SfxVolume 0..1
--   Sensitivity   0.2..2 (x the configured camera sensitivity; 1 = default)
--   DamageNumbers boolean
-- The volumes are kept in the profile (DataService) between sessions.
-- The touch buttons do what the keys do. Slide and jump are published as the
-- attributes BonkSlideHeld and BonkJumpHeld on PlayerGui for MovementController.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local UiKit = require(script.Parent.Parent.UiKit)

local OverlayController = Knit.CreateController({ Name = "OverlayController" })

local player = Players.LocalPlayer

local SENS_MIN, SENS_MAX = 0.2, 2
local DEFAULTS = {
	MasterVolume = 0.7,
	MusicVolume = 0.45,
	SfxVolume = 0.55,
	Sensitivity = 1,
	DamageNumbers = true,
}
local VOLUMES = { master = "MasterVolume", music = "MusicVolume", sfx = "SfxVolume" }
local PAD_STEP = 0.05
local AMBER = Color3.fromHex("#FFB23A")

local function noPause()
	return { mode = "none", votes = {}, need = 0, seconds = 0 }
end

function OverlayController:KnitInit()
	self._menuMode = nil -- nil, "pause" (the run is paused) or "settings"
	self._returnFocus = nil
	self._info = noPause() -- the last word from PauseService
	self._infoAt = 0
	self._hint = nil -- { text, untilAt }: a short refusal shown in the notice
	self._volumesLoaded = false
	self._volumesSent = nil
	self._sliders = {}
	self._dragging = nil
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
	UiKit.safe("OverlayController", function()
		self:_start()
	end)
end

--- Is the pause or settings sheet open?
function OverlayController:IsPaused(): boolean
	return self._menuMode ~= nil
end

--- The main menu's SETTINGS button. `back` gets the gamepad focus on close.
function OverlayController:OpenSettings(back: Instance?)
	self._returnFocus = back
	self:_openMenu("settings")
end

function OverlayController:_openMenu(mode: string)
	if not self._pause then
		return
	end
	self._menuMode = mode
	UiKit.show(self._pause, true)
	self._camera:SetUiOpen("pause", true)
	self:_renderSettings()
	self:_renderMenuText()
	UiKit.focus(self._resume)
end

function OverlayController:_closeMenu()
	if not self._menuMode then
		return
	end
	self._menuMode = nil
	self._dragging = nil
	UiKit.show(self._pause, false)
	self._camera:SetUiOpen("pause", false)
	UiKit.unfocus(self._pause)
	self:_sendVolumes()
	if self._returnFocus then
		UiKit.focus(self._returnFocus)
		self._returnFocus = nil
	end
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

--- Seconds left on the vote or the pause; -1 for a pause with no limit (solo).
function OverlayController:_secondsLeft(): number
	local seconds = tonumber(self._info.seconds) or 0
	if seconds < 0 then
		return -1
	end
	return math.max(0, seconds - (os.clock() - self._infoAt))
end

--- P, Start, or the touch PAUSE button.
function OverlayController:_pausePressed()
	if not self:_inRun() then
		if self._menuMode then
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
		elseif self._menuMode == "pause" then
			self:_ask("resume")
		else
			self:_openMenu("pause")
		end
	elseif info.mode == "vote" then
		if info.by == player.UserId then
			self:_ask("withdraw")
		elseif not self:_voted() then
			self:_ask("accept")
		end
	else
		self:_ask("request")
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
	self:_renderMenuText()
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

function OverlayController:_renderMenuText()
	if not self._menuMode then
		return
	end
	local title, button = "SETTINGS", "CLOSE"
	if self._menuMode == "pause" then
		local seconds = self:_secondsLeft()
		local coop = seconds >= 0
		title = if coop then `PAUSED  {UiKit.clock(math.ceil(seconds))}` else "PAUSED"
		button = if coop then "RESUME ALL" else "RESUME"
	end
	UiKit.text(self._title, title)
	UiKit.text(self._resumeLabel, button)
end

function OverlayController:_renderNotice()
	local n = self._notice
	if not n or not n.frame then
		return
	end
	local info = self._info
	local title, sub, action = nil, nil, nil
	local subColour = AMBER
	if info.mode == "vote" then
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
	elseif info.mode == "paused" and info.resuming then
		title = `RESUMING IN {math.max(1, math.ceil(self:_secondsLeft()))}`
		sub, subColour = "Get ready!", UiKit.Colours.ink
	elseif info.mode == "paused" and self._menuMode ~= "pause" and self:_inRun() then
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
	self._volumesSent = self:_volumeSignature()
	self:_renderSettings()
end

function OverlayController:_volumeSignature(): string
	local gui = UiKit.playerGui()
	return `{gui:GetAttribute("MasterVolume")}:{gui:GetAttribute("MusicVolume")}:{gui:GetAttribute("SfxVolume")}`
end

--- Hand changed volumes to the profile (on closing the sheet).
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
	self._settingsRemote:FireServer(out)
end

function OverlayController:_start()
	local overlay = UiKit.gui("Overlay")
	if not overlay then
		return
	end
	local gui = UiKit.playerGui()
	local state = self._state

	-- ------------------------------------------------------------ pause menu

	local pause = UiKit.find(overlay, "PauseMenu")
	self._pause = pause
	self._resume = UiKit.find(pause, "ResumeButton")
	self._resumeLabel = UiKit.find(pause, "ResumeButton.Label")
	self._title = UiKit.find(pause, "Panel.Header.Title")
	self._check = UiKit.find(pause, "DamageNumbersToggle.Check")
	UiKit.fillIcons(pause)
	UiKit.show(pause, false)
	UiKit.show(UiKit.find(pause, "LeaveButton"), false) -- there is no way to leave a run yet

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
		self:_pausePressed()
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

	UiKit.button(self._resume, function()
		if self._menuMode == "pause" and self:_inRun() then
			self:_ask("resume")
		else
			self:_closeMenu()
		end
	end)
	UiKit.button(UiKit.find(pause, "DamageNumbersToggle"), function()
		gui:SetAttribute("DamageNumbers", gui:GetAttribute("DamageNumbers") == false)
		self:_renderSettings()
	end)

	local function addSlider(path: string, attribute: string, low: number, high: number)
		local slider = UiKit.find(pause, path)
		if not slider or not slider:IsA("GuiObject") then
			return
		end
		local entry = {
			frame = slider,
			fill = UiKit.find(slider, "Fill"),
			knob = UiKit.find(slider, "Knob"),
			attribute = attribute,
			low = low,
			high = high,
		}
		table.insert(self._sliders, entry)
		slider.Active = true
		slider.Selectable = true
		local function begin(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				self._dragging = entry
				self:_dragTo(entry, input.Position.X)
			end
		end
		slider.InputBegan:Connect(begin)
		if entry.knob and entry.knob:IsA("GuiObject") then
			entry.knob.Active = true
			entry.knob.InputBegan:Connect(begin)
		end
	end
	addSlider("MasterSlider", "MasterVolume", 0, 1)
	addSlider("MusicSlider", "MusicVolume", 0, 1)
	addSlider("SfxSlider", "SfxVolume", 0, 1)
	addSlider("SensitivitySlider", "Sensitivity", SENS_MIN, SENS_MAX)

	UserInputService.InputChanged:Connect(function(input)
		local entry = self._dragging
		if entry and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			UiKit.safe("OverlayController.slider", function()
				self:_dragTo(entry, input.Position.X)
			end)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = nil
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonStart or (key == Enum.KeyCode.P and not processed) then
			UiKit.safe("OverlayController.pause", function()
				self:_pausePressed()
			end)
		elseif self._menuMode and (key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.DPadRight) then
			-- a gamepad nudges the slider it has selected
			local selected = GuiService.SelectedObject
			for _, entry in self._sliders do
				if entry.frame == selected then
					local step = if key == Enum.KeyCode.DPadLeft then -PAD_STEP else PAD_STEP
					self:_setFraction(entry, self:_fraction(entry) + step)
				end
			end
		end
	end)

	state.Changed:Connect(function(key)
		UiKit.safe("OverlayController.state", function()
			if key == "profile" then
				self:_loadVolumes()
			elseif key == "phase" then
				local live = state:IsLive()
				if (self._menuMode == "settings" and live) or (self._menuMode == "pause" and not live) then
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
	self:_renderSettings()

	-- the countdowns in the notice and the menu title
	local tick = 0
	RunService.Heartbeat:Connect(function(dt)
		tick += dt
		if tick < 0.1 or (self._info.mode == "none" and not self._hint) then
			return
		end
		tick = 0
		UiKit.safe("OverlayController.notice", function()
			if self._hint and os.clock() >= self._hint.untilAt then
				self._hint = nil
			end
			self:_renderMenuText()
			self:_renderNotice()
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
		local choices = Knit.GetController("ChoiceController")
		local inRun = state.phase ~= "Lobby" and state.me ~= nil and state:Root() ~= nil
		local visible = inRun and not self._menuMode and not choices:IsOpen()
		UiKit.show(touch, visible)
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

function OverlayController:_jump()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and not character:GetAttribute("Downed") then
		humanoid.Jump = true
	end
end

-- ---------------------------------------------------------------- sliders

function OverlayController:_fraction(entry): number
	local value = tonumber(UiKit.playerGui():GetAttribute(entry.attribute)) or entry.low
	return math.clamp((value - entry.low) / (entry.high - entry.low), 0, 1)
end

function OverlayController:_setFraction(entry, fraction: number)
	fraction = math.clamp(fraction, 0, 1)
	local value = entry.low + (entry.high - entry.low) * fraction
	UiKit.playerGui():SetAttribute(entry.attribute, math.floor(value * 100 + 0.5) / 100)
	self:_renderSlider(entry)
end

function OverlayController:_dragTo(entry, screenX: number)
	local frame = entry.frame
	local width = frame.AbsoluteSize.X
	if width > 0 then
		self:_setFraction(entry, (screenX - frame.AbsolutePosition.X) / width)
	end
end

function OverlayController:_renderSlider(entry)
	local fraction = self:_fraction(entry)
	UiKit.fill(entry.fill, fraction)
	local knob = entry.knob
	if knob and knob:IsA("GuiObject") then
		knob.Position = UDim2.new(fraction, 0, knob.Position.Y.Scale, knob.Position.Y.Offset)
	end
end

function OverlayController:_renderSettings()
	for _, entry in self._sliders do
		self:_renderSlider(entry)
	end
	UiKit.show(self._check, UiKit.playerGui():GetAttribute("DamageNumbers") ~= false)
end

return OverlayController

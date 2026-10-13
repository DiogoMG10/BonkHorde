--!nonstrict
-- OverlayController - the Overlay ScreenGui's pause menu and touch controls.
-- (The big map in the same ScreenGui belongs to MinimapController.)
--
-- Roblox owns Esc, so the pause menu opens with P or the gamepad Start button.
-- It does not stop the run (only the server pauses, for a level-up); it is the
-- settings sheet. The settings live as attributes on PlayerGui so any
-- controller can read them and listen for changes:
--   MusicVolume   0..1            SfxVolume      0..1
--   Sensitivity   0.2..2 (x the configured camera sensitivity; 1 = default)
--   DamageNumbers boolean
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
local DEFAULTS = { MusicVolume = 0.7, SfxVolume = 0.8, Sensitivity = 1, DamageNumbers = true }
local PAD_STEP = 0.05

function OverlayController:KnitInit()
	self._pauseOpen = false
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

function OverlayController:IsPaused(): boolean
	return self._pauseOpen
end

function OverlayController:SetPaused(open: boolean)
	self._pauseOpen = open
	UiKit.show(self._pause, open)
	self._camera:SetUiOpen("pause", open)
	if open then
		self:_renderSettings()
		UiKit.focus(self._resume)
	else
		self._dragging = nil
		UiKit.unfocus(self._pause)
	end
end

function OverlayController:_start()
	local overlay = UiKit.gui("Overlay")
	if not overlay then
		return
	end
	local gui = UiKit.playerGui()

	-- ------------------------------------------------------------ pause menu

	local pause = UiKit.find(overlay, "PauseMenu")
	self._pause = pause
	self._resume = UiKit.find(pause, "ResumeButton")
	self._check = UiKit.find(pause, "DamageNumbersToggle.Check")
	UiKit.fillIcons(pause)
	UiKit.show(pause, false)
	UiKit.show(UiKit.find(pause, "LeaveButton"), false) -- there is no way to leave a run yet

	UiKit.button(self._resume, function()
		self:SetPaused(false)
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
			self:SetPaused(not self._pauseOpen)
		elseif self._pauseOpen and (key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.DPadRight) then
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

	self:_renderSettings()

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
		local state = self._state
		local choices = Knit.GetController("ChoiceController")
		local inRun = state.phase ~= "Lobby" and state.me ~= nil and state:Root() ~= nil
		local visible = inRun and not self._pauseOpen and not choices:IsOpen()
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

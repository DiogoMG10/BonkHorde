--!nonstrict
-- PrimaryController - owns the attack button for the hero's own weapon.
--
-- It tells the server one thing: whether the button is held, and the yaw and
-- pitch the camera is aiming along. It never asks for an attack and never
-- decides a hit; the server fires the weapon on its own cooldown while the
-- button is held. The state is repeated while held, so a server that stops
-- hearing it lets go.
--
-- Mouse and keyboard only for now. How the aim is shown depends on the weapon:
-- a melee swing is a direction on the ground, shown as a marker at the hero's
-- feet; a shot (Fire Staff) flies from the camera's focus along its look, so a
-- crosshair at the centre of the screen is exactly where it goes. A ring
-- around the hero (Frost Ring) shows nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)

local PrimaryController = Knit.CreateController({ Name = "PrimaryController" })

local YAW_STEP = math.rad(2) -- send a new aim once it has moved this far (yaw or pitch)...
local YAW_INTERVAL = 1 / 15 -- ...but no more often than this
local REPEAT_INTERVAL = 0.4 -- and confirm a held button at least this often
local MARKER_DISTANCE = 4.5

function PrimaryController:KnitInit()
	self._down = false -- the physical button
	self._sent = false -- the held state the server was last told
	self._sentYaw = 0
	self._sentPitch = 0
	self._sentAt = 0
end

-- Is this a moment the local hero can attack by hand in? The second value is
-- the primary weapon's kind, which decides how its aim is shown.
function PrimaryController:_enabled(): (boolean, string?)
	local state = self._state
	local me = state.me
	if not me or me.downed or state.paused or not state:IsLive() or not state:Root() then
		return false, nil
	end
	-- a free mouse means a menu or panel is open: clicks belong to it
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		return false, nil
	end
	for _, w in me.weapons do
		if w.primary then
			local def = Roster.Weapons[w.id]
			return true, def and def.kind
		end
	end
	return false, nil
end

function PrimaryController:_send(held: boolean, yaw: number, pitch: number, now: number)
	self._sent, self._sentYaw, self._sentPitch, self._sentAt = held, yaw, pitch, now
	self._remote:FireServer(held, yaw, pitch)
end

function PrimaryController:_marker(): BasePart
	local marker = self._markerPart
	if not marker or not marker.Parent then
		marker = Instance.new("Part")
		marker.Name = "PrimaryAim"
		marker.Size = Vector3.new(0.7, 0.12, 2.6)
		marker.Material = Enum.Material.Neon
		marker.Color = Color3.fromRGB(255, 244, 214)
		marker.Transparency = 0.45
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.CastShadow = false
		marker.Parent = Workspace
		self._markerPart = marker
	end
	return marker
end

-- A small open cross at the centre of the screen: four short ticks around a
-- gap and a pinpoint dot, light with a dark edge so it reads on grass and sky
-- alike without covering what it is pointed at. Its own ScreenGui, because the
-- Hud's UIScale would move a centred element off centre.
function PrimaryController:_crosshair(): ScreenGui
	local gui = self._crosshairGui
	if gui and gui.Parent then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.IgnoreGuiInset = true -- the camera's centre is the whole window's centre
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5 -- under the Hud and every panel
	gui.Enabled = false
	local function tick(size: Vector2, offset: Vector2)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		f.Size = UDim2.fromOffset(size.X, size.Y)
		f.BackgroundColor3 = Color3.fromRGB(255, 244, 214)
		f.BackgroundTransparency = 0.1
		f.BorderSizePixel = 0
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(30, 22, 14)
		stroke.Transparency = 0.35
		stroke.Thickness = 1
		stroke.Parent = f
		f.Parent = gui
	end
	local gap, len, thick = 6, 7, 2
	local reach = gap + len / 2
	tick(Vector2.new(thick, len), Vector2.new(0, -reach))
	tick(Vector2.new(thick, len), Vector2.new(0, reach))
	tick(Vector2.new(len, thick), Vector2.new(-reach, 0))
	tick(Vector2.new(len, thick), Vector2.new(reach, 0))
	tick(Vector2.new(2, 2), Vector2.zero)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._crosshairGui = gui
	return gui
end

function PrimaryController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._camera = Knit.GetController("CameraController")
	self._remote = Net.client("PrimaryInput")
	if not self._remote then
		return -- no remote: the weapon simply never fires by hand
	end

	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		self._down = true
		-- sent at once, not on the next frame: a click released within the same
		-- frame must still reach the server as a press and then a release
		if self:_enabled() and not self._sent then
			self:_send(true, self._camera:Yaw(), self._camera:Pitch(), os.clock())
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self._down = false
		end
	end)
	-- the button-up never arrives if the window lost focus while it was down
	UserInputService.WindowFocusReleased:Connect(function()
		self._down = false
	end)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		self._down = false
	end)

	-- after the camera has turned for this frame
	RunService:BindToRenderStep("BonkPrimary", Enum.RenderPriority.Camera.Value + 2, function()
		local now = os.clock()
		local enabled, kind = self:_enabled()
		local yaw, pitch = self._camera:Yaw(), self._camera:Pitch()
		local want = self._down and enabled

		if want ~= self._sent then
			self:_send(want, yaw, pitch, now)
		elseif want then
			local turned = math.abs((yaw - self._sentYaw + math.pi) % (2 * math.pi) - math.pi)
			turned = math.max(turned, math.abs(pitch - self._sentPitch))
			local since = now - self._sentAt
			if (turned >= YAW_STEP and since >= YAW_INTERVAL) or since >= REPEAT_INTERVAL then
				self:_send(true, yaw, pitch, now)
			end
		end

		local shoots = enabled and kind == "Fireball"
		if shoots or self._crosshairGui then
			self:_crosshair().Enabled = shoots
		end

		local root = enabled and kind == "Arc" and self._state:Root()
		if root then
			local dx, dz = -math.sin(yaw), -math.cos(yaw)
			local x, z = root.Position.X + dx * MARKER_DISTANCE, root.Position.Z + dz * MARKER_DISTANCE
			local at = Vector3.new(x, self._state:HeightAt(x, z) + 0.25, z)
			self:_marker().CFrame = CFrame.lookAt(at, at + Vector3.new(dx, 0, dz))
		elseif self._markerPart then
			self._markerPart:Destroy()
			self._markerPart = nil
		end
	end)
end

return PrimaryController

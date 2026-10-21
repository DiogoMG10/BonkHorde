--!nonstrict
-- MinimapController - the round minimap in the Hud and the big map in the Overlay.
--
-- The minimap is centred on the hero and turns with the camera, so "up" is
-- always where the camera looks; N/E/S/W ride the rim. The big map (Tab, or the
-- gamepad Select button) shows the whole playable world with north up. Both
-- draw the same dots from WorldController's interactables, the boss portal
-- once the squad has found it, and the teammates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Icons = require(ReplicatedStorage.Shared.Config.Icons)
local UiKit = require(script.Parent.Parent.UiKit)

local MinimapController = Knit.CreateController({ Name = "MinimapController" })

local player = Players.LocalPlayer

local MINIMAP_RANGE_STUDS = 120 -- how far the rim is from the hero
local RIM_INSET_PX = 4 -- Dots is the minimap less this on each side; the circle is cut by code
local DOT_PX = 10
local BIG_DOT_PX = 14

local COLOURS = {
	Chest = Color3.fromHex("#FFD23A"),
	ChargeShrine = Color3.fromHex("#B04DFF"),
	GreedShrine = Color3.fromHex("#FF9F1A"),
	ChallengeShrine = Color3.fromHex("#FF4D9A"),
	VacuumShrine = Color3.fromHex("#3D8BFF"),
	SmugStatue = Color3.fromHex("#C9D2CB"),
	DodgyDan = Color3.fromHex("#35D04A"),
	Tombstone = Color3.fromHex("#FFFFFF"),
	BossPortal = Color3.fromHex("#E5121B"),
	Teammate = Color3.fromHex("#4DE1FF"),
}
-- the legend rows of the big map, by the icon key each one ships with
local LEGEND = {
	IconMapChest = COLOURS.Chest,
	IconMapShrine = COLOURS.ChargeShrine,
	IconMapBoss = COLOURS.BossPortal,
	IconMapVendor = COLOURS.DodgyDan,
	IconMapTeammate = COLOURS.Teammate,
}

local function newPool(container: Instance?, template: Instance?)
	return { container = container, template = template, dots = {}, used = 0 }
end

local function poolPut(pool, x: number, y: number, colour: Color3, size: number)
	if not pool.container or not pool.template then
		return
	end
	pool.used += 1
	local dot = pool.dots[pool.used]
	if not dot then
		dot = pool.template:Clone()
		dot.Parent = pool.container
		pool.dots[pool.used] = dot
	end
	dot.Position = UDim2.new(0.5, x, 0.5, y)
	dot.Size = UDim2.fromOffset(size, size)
	dot.BackgroundColor3 = colour
	dot.Visible = true
end

local function poolFinish(pool)
	for i = pool.used + 1, #pool.dots do
		pool.dots[i].Visible = false
	end
	pool.used = 0
end

function MinimapController:KnitInit()
	self._bigOpen = false
end

function MinimapController:KnitStart()
	self._state = Knit.GetController("StateController")
	self._world = Knit.GetController("WorldController")
	self._camera = Knit.GetController("CameraController")
	UiKit.safe("MinimapController", function()
		self:_start()
	end)
end

--- Open or close the big map. The touch MAP button calls this too.
function MinimapController:ToggleBigMap()
	self:SetBigMap(not self._bigOpen)
end

function MinimapController:SetBigMap(open: boolean)
	open = open and self._state.phase ~= "Lobby"
	self._bigOpen = open
	UiKit.show(self._big, open)
end

function MinimapController:_start()
	local hud = UiKit.gui("Hud")
	local overlay = UiKit.gui("Overlay")
	local state = self._state

	local mini = UiKit.find(hud, "Safe.TopRight.Minimap")
	self._miniHolder = UiKit.find(hud, "Safe.TopRight") -- HudController sizes it per screen
	local miniDots = UiKit.find(mini, "Dots")
	local template = UiKit.template(miniDots, "MapDot")
	self._mini = mini
	self._miniArrow = UiKit.find(mini, "PlayerArrow")
	self._miniLetters = {
		N = UiKit.find(mini, "N"),
		E = UiKit.find(mini, "E"),
		S = UiKit.find(mini, "S"),
		W = UiKit.find(mini, "W"),
	}
	self._miniPool = newPool(miniDots, template)

	local big = UiKit.find(overlay, "BigMap")
	local bigDots = UiKit.find(big, "Dots")
	self._big = big
	self._bigArrow = UiKit.find(big, "PlayerArrow")
	self._bigPool = newPool(bigDots, template)
	self._bigSpan = if bigDots and bigDots:IsA("GuiObject") and big and big:IsA("GuiObject") then big.Size.X.Offset - 12 else 748
	UiKit.fillIcons(big)
	UiKit.show(big, false)

	-- until the map icons are uploaded the legend shows each kind's dot colour
	local legend = UiKit.find(big, "Legend")
	if legend then
		for _, row in legend:GetChildren() do
			local icon = row:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				local key = icon:GetAttribute("IconName")
				local colour = LEGEND[key]
				if colour and Icons.get(key) == "" then
					icon.BackgroundColor3 = colour
					icon.BackgroundTransparency = 0
					icon.Size = UDim2.fromOffset(16, 16)
					icon.Position = UDim2.new(0, 6, 0.5, 0)
					local corner = Instance.new("UICorner")
					corner.CornerRadius = UDim.new(0, 4)
					corner.Parent = icon
				end
			end
		end
	end

	-- Tab belongs to the big map, and the minimap sits where the player list would draw.
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.ButtonSelect then
			self:ToggleBigMap()
		end
	end)

	state.Changed:Connect(function(key)
		if key == "phase" and state.phase == "Lobby" then
			self:SetBigMap(false)
		end
	end)

	local broken = false
	RunService.RenderStepped:Connect(function()
		if broken or state.phase == "Lobby" then
			return
		end
		local ok, err = pcall(function()
			self:_frame()
		end)
		if not ok then
			broken = true
			warn(`[MinimapController] frame stopped: {err}`)
		end
	end)
end

--- Every dot both maps draw this frame, as world positions.
function MinimapController:_collect(): { { x: number, z: number, colour: Color3, size: number, pin: boolean } }
	local state = self._state
	local out = {}
	for _, entry in self._world:List() do
		local data = entry.data
		local colour = COLOURS[data.kind]
		if colour and data.kind ~= "BossPortal" and not data.used and data.state ~= "used" then
			table.insert(out, { x = data.x, z = data.z, colour = colour, size = DOT_PX, pin = false })
		end
	end
	local portal = state.portal
	if portal then
		table.insert(out, { x = portal.x, z = portal.z, colour = COLOURS.BossPortal, size = BIG_DOT_PX, pin = true })
	end
	for _, mate in state.squad do
		if mate.userId ~= player.UserId then
			local root = state:RootOfIndex(mate.index)
			if root then
				table.insert(out, { x = root.Position.X, z = root.Position.Z, colour = COLOURS.Teammate, size = DOT_PX, pin = true })
			end
		end
	end
	return out
end

function MinimapController:_frame()
	local state = self._state
	local root = state:Root()
	local miniOn = self._mini ~= nil and root ~= nil
	local bigOn = self._bigOpen and self._big ~= nil
	if not miniOn and not bigOn then
		poolFinish(self._miniPool)
		return
	end
	local dots = self:_collect()
	local px, pz = 0, 0
	local lookX, lookZ = 0, -1
	if root then
		px, pz = root.Position.X, root.Position.Z
		local look = root.CFrame.LookVector
		lookX, lookZ = look.X, look.Z
	end

	if miniOn then
		-- camera space: forward is up on the map, right is right
		local yaw = self._camera:Yaw()
		local sin, cos = math.sin(yaw), math.cos(yaw)
		local holder = self._miniHolder
		local side = if holder and holder:IsA("GuiObject") then holder.Size.X.Offset else 220
		local radius = side / 2 - RIM_INSET_PX
		local rimLetter = side / 2 - 2
		local scale = radius / MINIMAP_RANGE_STUDS
		local pool = self._miniPool
		for _, dot in dots do
			local dx, dz = dot.x - px, dot.z - pz
			local right = (dx * cos - dz * sin) * scale
			local forward = (-dx * sin - dz * cos) * scale
			local limit = radius - dot.size * 0.5 - 1
			local distance = math.sqrt(right * right + forward * forward)
			if distance <= limit then
				poolPut(pool, right, -forward, dot.colour, dot.size)
			elseif dot.pin then
				-- the portal and the squad stay on the rim, pointing the way
				local k = limit / distance
				poolPut(pool, right * k, -forward * k, dot.colour, dot.size)
			end
		end
		poolFinish(pool)

		-- north is world -Z, east is world +X
		local letters = self._miniLetters
		local nx, ny = sin * rimLetter, -cos * rimLetter
		local ex, ey = cos * rimLetter, sin * rimLetter
		if letters.N then
			letters.N.Position = UDim2.new(0.5, nx, 0.5, ny)
		end
		if letters.S then
			letters.S.Position = UDim2.new(0.5, -nx, 0.5, -ny)
		end
		if letters.E then
			letters.E.Position = UDim2.new(0.5, ex, 0.5, ey)
		end
		if letters.W then
			letters.W.Position = UDim2.new(0.5, -ex, 0.5, -ey)
		end
		if self._miniArrow then
			local right = lookX * cos - lookZ * sin
			local forward = -lookX * sin - lookZ * cos
			self._miniArrow.Rotation = math.deg(math.atan2(right, forward))
		end
	end

	if bigOn then
		local scale = self._bigSpan / GameConfig.PlaySizeStuds
		local half = self._bigSpan * 0.5
		local pool = self._bigPool
		for _, dot in dots do
			local x, y = dot.x * scale, dot.z * scale
			if math.abs(x) <= half and math.abs(y) <= half then
				poolPut(pool, x, y, dot.colour, dot.size + 2)
			end
		end
		poolFinish(pool)
		local arrow = self._bigArrow
		if arrow then
			arrow.Position = UDim2.new(0.5, math.clamp(px * scale, -half, half), 0.5, math.clamp(pz * scale, -half, half))
			arrow.Rotation = math.deg(math.atan2(lookX, -lookZ))
			UiKit.show(arrow, root ~= nil)
		end
	end
end

return MinimapController

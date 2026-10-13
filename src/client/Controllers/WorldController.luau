--!nonstrict
-- WorldController - owns the interactables as the player sees them: the models,
-- shrine domes, revive rings, and which one the hero can use right now.
--
-- A model comes from ReplicatedStorage.Assets.Interactables.<Kind> when it
-- exists and is a labelled block otherwise. The server decides every outcome;
-- this controller draws state and sends "I pressed interact on id N".

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Vfx = require(script.Parent.Parent.Vfx)

local WorldController = Knit.CreateController({ Name = "WorldController" })

local LOOK = {
	Chest = { size = Vector3.new(4, 3, 3), colour = Color3.fromRGB(150, 95, 45) },
	ChargeShrine = { size = Vector3.new(3, 6, 3), colour = Color3.fromRGB(120, 125, 135) },
	GreedShrine = { size = Vector3.new(3, 5, 3), colour = Color3.fromRGB(230, 190, 60) },
	ChallengeShrine = { size = Vector3.new(3, 5, 3), colour = Color3.fromRGB(150, 60, 170) },
	VacuumShrine = { size = Vector3.new(3, 5, 3), colour = Color3.fromRGB(70, 130, 230) },
	SmugStatue = { size = Vector3.new(4, 9, 4), colour = Color3.fromRGB(110, 120, 110) },
	DodgyDan = { size = Vector3.new(3, 6, 3), colour = Color3.fromRGB(90, 70, 110) },
	BossPortal = { size = Vector3.new(14, 16, 3), colour = Color3.fromRGB(60, 120, 220) },
	Pot = { size = Vector3.new(2, 2.6, 2), colour = Color3.fromRGB(210, 120, 60) },
	Crate = { size = Vector3.new(3, 3, 3), colour = Color3.fromRGB(170, 125, 70) },
	Tombstone = { size = Vector3.new(2.4, 3.4, 1), colour = Color3.fromRGB(160, 165, 170) },
}
local DOME_COLOURS = {
	Color3.fromRGB(110, 230, 90),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(90, 190, 255),
	Color3.fromRGB(255, 225, 80),
}
local PORTAL_COLOURS = {
	idle = Color3.fromRGB(60, 120, 220),
	found = Color3.fromRGB(60, 120, 220),
	summoned = Color3.fromRGB(200, 50, 50),
	exit = Color3.fromRGB(70, 220, 120),
}

function WorldController:KnitInit()
	self._items = {} -- id -> { data, model, dome, label }
	self.PromptChanged = Signal.new()
	self._prompt = nil
	local folder = Instance.new("Folder")
	folder.Name = "Interactables"
	folder.Parent = Workspace
	self._folder = folder
end

--- Every interactable the client knows about, for the minimap.
function WorldController:List()
	return self._items
end

--- The id of the interactable the prompt is offering right now, if any. Touch
--- and on-screen buttons send it with the Interact remote, as the E key does.
function WorldController:PromptId(): number?
	return self._prompt and self._prompt.id
end

function WorldController:_label(part: BasePart, text: string): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 34)
	gui.StudsOffset = Vector3.new(0, part.Size.Y * 0.5 + 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextSize = 20
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui
	gui.Parent = part
	return label
end

function WorldController:_add(data)
	if self._items[data.id] then
		self:_remove(data.id)
	end
	local look = LOOK[data.kind]
	if not look then
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local source = assets and assets:FindFirstChild("Interactables") and assets.Interactables:FindFirstChild(data.kind)
	local model: Model
	local main: BasePart
	if source and source:IsA("Model") then
		model = source:Clone()
		model:PivotTo(CFrame.new(data.x, data.y, data.z) * CFrame.Angles(0, (data.id % 8) * 0.785, 0))
		main = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	else
		model = Instance.new("Model")
		main = Instance.new("Part")
		main.Size = look.size
		main.Color = look.colour
		main.Material = Enum.Material.SmoothPlastic
		main.CFrame = CFrame.new(data.x, data.y + look.size.Y * 0.5, data.z)
		main.Parent = model
		model.PrimaryPart = main
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanQuery = false
			d.CanTouch = false
			-- breakables and tombstones never block a hero; the rest are solid
			d.CanCollide = not (data.kind == "Pot" or data.kind == "Crate" or data.kind == "Tombstone")
		end
	end
	model.Name = data.kind
	model.Parent = self._folder
	local entry = { data = data, model = model, main = main }
	if data.kind ~= "Pot" and data.kind ~= "Crate" then
		entry.label = self:_label(main, if data.free then "FREE CHEST" else string.upper(data.kind))
	end
	if data.kind == "ChargeShrine" then
		local dome = Instance.new("Part")
		dome.Shape = Enum.PartType.Ball
		dome.Size = Vector3.one * GameConfig.ChargeShrineRadius * 2
		dome.Color = DOME_COLOURS[data.id % #DOME_COLOURS + 1]
		dome.Material = Enum.Material.ForceField
		dome.Transparency = 0.55
		dome.Anchored = true
		dome.CanCollide = false
		dome.CanQuery = false
		dome.CanTouch = false
		dome.CastShadow = false
		dome.CFrame = CFrame.new(data.x, data.y, data.z)
		dome.Parent = model
		entry.dome = dome
	end
	if data.kind == "BossPortal" then
		-- a swirl in the arch, and red wind so the site reads from far away
		pcall(function()
			Vfx.place("PortalSwirl", CFrame.new(data.x, data.y + 6, data.z), 3, model)
			entry.wind = Vfx.place("BossPortalWind", CFrame.new(data.x, data.y + 4, data.z), 18, model)
		end)
	end
	self._items[data.id] = entry
	self:_applyState(entry, data.state)
end

function WorldController:_remove(id: number)
	local entry = self._items[id]
	if entry then
		entry.model:Destroy()
		self._items[id] = nil
	end
end

function WorldController:_applyState(entry, state: string, value)
	local data = entry.data
	data.state = state
	if state == "used" and not data.used then
		local at = Vector3.new(data.x, data.y + 0.4, data.z)
		pcall(function()
			if data.kind == "ChargeShrine" then
				local colour = if entry.dome then entry.dome.Color else Color3.new(1, 1, 1)
				Vfx.ground(at, "ring", colour, 3, GameConfig.ChargeShrineRadius * 1.3, 0.6)
				Vfx.burst("ShrineCharged", at + Vector3.new(0, 3, 0), { tint = colour })
			elseif data.kind == "Chest" then
				Vfx.ground(at, "ring", Color3.fromRGB(255, 225, 90), 1, 9, 0.5)
				Vfx.burst("LevelUpBurst", at + Vector3.new(0, 2, 0))
				Vfx.burst("Confetti", at + Vector3.new(0, 3, 0), { count = 18 })
			else
				Vfx.ground(at, "ring_thin", Color3.fromRGB(255, 255, 255), 1, 8, 0.45)
			end
		end)
	end
	if state == "used" then
		data.used = true
		for _, d in entry.model:GetDescendants() do
			if d:IsA("BasePart") and d ~= entry.dome then
				d.Transparency = 0.6
			end
		end
		if entry.dome then
			entry.dome:Destroy()
			entry.dome = nil
		end
		if entry.label then
			entry.label.Text = "USED"
			entry.label.TextTransparency = 0.4
		end
	elseif state == "charging" then
		if entry.label and typeof(value) == "number" then
			entry.label.Text = `{math.floor(value * 100)}%`
		end
		if entry.dome then
			entry.dome.Transparency = 0.25
		end
	elseif state == "idle" then
		if entry.label and data.kind == "ChargeShrine" then
			entry.label.Text = "!"
		end
		if entry.dome then
			entry.dome.Transparency = 0.55
		end
	elseif data.kind == "BossPortal" and PORTAL_COLOURS[state] then
		if not entry.model:GetAttribute("IsAsset") and entry.main.Transparency < 1 then
			entry.main.Color = PORTAL_COLOURS[state]
		end
		if state == "exit" and entry.wind then
			entry.wind:Destroy() -- the danger is over; only the swirl stays
			entry.wind = nil
		end
		if state == "summoned" or state == "exit" then
			pcall(Vfx.ground, Vector3.new(data.x, data.y + 0.4, data.z), "ring", PORTAL_COLOURS[state], 2, 26, 0.8)
		end
		if entry.label then
			entry.label.Text = if state == "exit" then "EXIT PORTAL" elseif state == "summoned" then "BOSS SUMMONED" else "BOSS PORTAL"
		end
	end
end

function WorldController:KnitStart()
	self._state = Knit.GetController("StateController")
	local interact = Net.client("Interact")

	local list = Net.client("Interactables")
	if list then
		list.OnClientEvent:Connect(function(items)
			for id in self._items do
				self:_remove(id)
			end
			for _, data in items do
				self:_add(data)
			end
		end)
	end
	local stateEvent = Net.client("InteractableState")
	if stateEvent then
		stateEvent.OnClientEvent:Connect(function(id, state, value)
			if state == "spawn" and typeof(value) == "table" then
				value.id = id
				value.state = "idle"
				self:_add(value)
				return
			end
			local entry = self._items[id]
			if not entry then
				return
			end
			if state == "broken" then
				pcall(Vfx.burst, "BreakPuff", Vector3.new(entry.data.x, entry.data.y + 1.5, entry.data.z))
			end
			if state == "gone" or state == "broken" then
				self:_remove(id)
			else
				self:_applyState(entry, state, value)
			end
		end)
	end

	ContextActionService:BindAction("BonkInteract", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and self._prompt and interact then
			interact:FireServer(self._prompt.id)
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("BonkInteract", "Use")
	ContextActionService:SetPosition("BonkInteract", UDim2.new(1, -230, 1, -90))

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		self:_updatePrompt()
	end)
end

function WorldController:_promptText(data): string?
	local kind = data.kind
	if data.used or data.state == "used" then
		return nil
	end
	if kind == "Chest" then
		local me = self._state.me
		local price = if data.free then 0 else (me and me.chestPrice or 0)
		return if price > 0 then `Open chest ({price} gold)` else "Open chest (free)"
	elseif kind == "BossPortal" then
		if data.state == "exit" then
			return "Enter the portal"
		elseif data.state == "summoned" then
			return nil
		end
		return "Summon the boss"
	elseif kind == "ChargeShrine" or kind == "Pot" or kind == "Crate" or kind == "Tombstone" then
		return nil
	end
	return Roster.InteractablePrompt[kind]
end

function WorldController:_updatePrompt()
	local root = self._state:Root()
	local best, bestD, bestText = nil, GameConfig.InteractRange ^ 2, nil
	if root and self._state:IsLive() then
		local p = root.Position
		for _, entry in self._items do
			local data = entry.data
			local d = (data.x - p.X) ^ 2 + (data.z - p.Z) ^ 2
			if d <= bestD then
				local text = self:_promptText(data)
				if text then
					best, bestD, bestText = data, d, text
				end
			end
		end
	end
	local old = self._prompt
	if (best and best.id) ~= (old and old.id) or (old and old.text) ~= bestText then
		self._prompt = if best then { id = best.id, text = bestText } else nil
		self.PromptChanged:Fire(bestText)
	end
end

return WorldController

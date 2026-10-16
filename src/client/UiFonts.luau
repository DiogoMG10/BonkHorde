--!strict
-- UiFonts - the font trial (Config/Fonts) across the game's own interface.
-- Three roles, each a Workspace attribute DevService sets (`font` in BonkDev):
--   numbers  the floating damage numbers (EnemyRenderController reads it)
--   popups   the labels UiFonts.role marks: LEVEL UP!, banners, the stage
--            name, the powerup toasts
--   ui       everything else the game draws: the five ScreenGuis (UiKit.gui
--            watches each as it arrives) and the world's own billboard labels
--            (UiFonts.track)
--
-- Under a "ui" pick, the labels laid out in the display face (Fonts.Display:
-- headings, values, prices) wear the picked face; body text, already Fredoka,
-- keeps it. With no pick every label wears the face it was built with,
-- remembered in a FontBase attribute that clones carry, so a template cloned
-- after a switch still goes back exactly. Nothing scans the interface on a
-- timer: a label is met once as it arrives, and dressed again only when a
-- font attribute changes. Roblox's own CoreGui and chat are never reached.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Fonts = require(ReplicatedStorage.Shared.Config.Fonts)

local UiFonts = {}

local BASE = "FontBase"
local ROLE = "FontRole"
local DISPLAY = Fonts.Faces[Fonts.Display].family

-- every text object met, with the face it was built with
local known: { [Instance]: Font } = setmetatable({}, { __mode = "k" }) :: any

local function isText(inst: Instance): boolean
	return inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
end

local function baseOf(label: any): Font
	local saved = label:GetAttribute(BASE)
	if type(saved) == "string" then
		local family, weight, style = string.match(saved, "^(.-)|(%a+)|(%a+)$")
		if family then
			local ok, face = pcall(function()
				return Font.new(family, (Enum.FontWeight :: any)[weight], (Enum.FontStyle :: any)[style])
			end)
			if ok then
				return face
			end
		end
	end
	local face: Font = label.FontFace
	label:SetAttribute(BASE, `{face.Family}|{face.Weight.Name}|{face.Style.Name}`)
	return face
end

local function dress(label: any)
	local base = known[label]
	if not base then
		return
	end
	local face = base
	if label:GetAttribute(ROLE) == "popups" then
		face = Fonts.face(Workspace:GetAttribute(Fonts.Attributes.popups))
	else
		local pick = Workspace:GetAttribute(Fonts.Attributes.ui)
		if type(pick) == "string" and Fonts.Faces[pick] and base.Family == DISPLAY then
			face = Fonts.face(pick)
		end
	end
	label.FontFace = face
end

local function meet(inst: Instance)
	if known[inst] or not isText(inst) then
		return
	end
	known[inst] = baseOf(inst)
	dress(inst)
end

--- Dress every text object under a game-owned root, now and as clones arrive.
function UiFonts.watch(root: Instance)
	for _, inst in root:GetDescendants() do
		meet(inst)
	end
	root.DescendantAdded:Connect(meet)
end

--- One text object outside the five screens (a world billboard's label).
function UiFonts.track(label: Instance)
	meet(label)
end

--- Give a label a role ("popups"): from now on it wears that role's face.
function UiFonts.role(label: Instance?, role: string)
	if label and isText(label) then
		label:SetAttribute(ROLE, role)
		meet(label)
		dress(label)
	end
end

local function redress()
	for label in known do
		dress(label)
	end
end
Workspace:GetAttributeChangedSignal(Fonts.Attributes.ui):Connect(redress)
Workspace:GetAttributeChangedSignal(Fonts.Attributes.popups):Connect(redress)

return UiFonts

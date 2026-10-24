--!nonstrict
-- Sink - a hero lowered into the ground and raised out of it (T8), as this
-- client draws them. The character itself is never moved: while lowered it is
-- hidden on this client (LocalTransparencyModifier) and a stand-in made of its
-- visible pieces (the hero model, the weapon) is drawn in its place, every
-- frame following the real pieces exactly (so the hero keeps animating), only
-- `studs` lower. The root, the Humanoid, the joints (Motor6D or the newer
-- AnimationConstraint rigs) and everything the server and the physics know stay
-- as they are, and it looks the same for this player's hero and everyone
-- else's. The ground hides what is under it.
--
-- `clear` puts everything back: the stand-in goes, the real pieces show again.
-- A character that goes away takes its stand-in with it.

local Workspace = game:GetService("Workspace")

local Sink = {}

type Piece = { real: BasePart, copy: BasePart }
type Entry = { pieces: { Piece }, folder: Folder, studs: number }

local held: { [Model]: Entry } = {}

-- what a stand-in piece keeps of the real one: how it looks, nothing that acts
local KEEP = {
	SpecialMesh = true,
	Decal = true,
	Texture = true,
	SurfaceAppearance = true,
}

local function standIn(part: BasePart): BasePart?
	local archivable = part.Archivable
	part.Archivable = true
	local ok, copy = pcall(function()
		return part:Clone()
	end)
	part.Archivable = archivable
	if not ok or not copy then
		return nil
	end
	for _, child in copy:GetChildren() do
		if not KEEP[child.ClassName] then
			child:Destroy()
		end
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Massless = true
	copy.LocalTransparencyModifier = 0
	return copy
end

local function build(character: Model): Entry
	local folder = Instance.new("Folder")
	folder.Name = "Sunk_" .. character.Name
	local pieces = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 and d.Name ~= "HumanoidRootPart" then
			local copy = standIn(d)
			if copy then
				copy.Parent = folder
				table.insert(pieces, { real = d, copy = copy })
			end
		end
	end
	folder.Parent = Workspace
	return { pieces = pieces, folder = folder, studs = 0 }
end

local function show(entry: Entry, real: boolean)
	for _, piece in entry.pieces do
		if piece.real.Parent then
			piece.real.LocalTransparencyModifier = if real then 0 else 1
		end
	end
end

--- Draw `character`'s body `studs` under where it stands (negative: a little
--- above). `depth` is unused (kept for callers that pass the hero's height).
function Sink.set(character: Model?, studs: number, _depth: number?)
	if not character or not character.Parent then
		return
	end
	local entry = held[character]
	if not entry then
		entry = build(character)
		held[character] = entry
	end
	entry.studs = studs
	local down = Vector3.new(0, studs, 0)
	for _, piece in entry.pieces do
		local real = piece.real
		if real.Parent then
			real.LocalTransparencyModifier = 1
			piece.copy.CFrame = real.CFrame - down
		else
			piece.copy.Transparency = 1
		end
	end
end

--- How far `character` is lowered now (0 when not at all).
function Sink.studs(character: Model?): number
	local entry = character and held[character]
	return if entry then entry.studs else 0
end

--- Put `character` back exactly as it was.
function Sink.clear(character: Model?)
	local entry = character and held[character]
	if not entry then
		return
	end
	held[character] = nil
	pcall(show, entry, true)
	entry.folder:Destroy()
end

--- Every character this client has lowered.
function Sink.all(): { Model }
	local out = {}
	for character in held do
		table.insert(out, character)
	end
	return out
end

--- Drop the stand-ins of characters that went away.
function Sink.tidy()
	for character, entry in held do
		if not character.Parent then
			held[character] = nil
			entry.folder:Destroy()
		end
	end
end

return Sink

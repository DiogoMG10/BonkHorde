--!strict
-- Wardwood - the look of the map that both the game and the offline previews
-- read: which Roblox terrain material each World.surface key becomes, and its
-- tint. Plain numbers, so the headless tools can load it.

local Wardwood = {
	-- the lobby's sky: "golden", "clear", "dusk", "sunset", "night" or
	-- "enchanted" (server/Wardwood/Look; `sky <name>` in BonkDev compares them)
	Sky = "golden",
	-- each run draws its sky from these, by weight, once at its start; the
	-- whole squad shares it (MapService:DrawRunSky)
	RunSkies = {
		{ name = "golden", weight = 1 },
		{ name = "clear", weight = 1 },
		{ name = "sunset", weight = 1 },
		{ name = "enchanted", weight = 1 },
		{ name = "night", weight = 1 },
	},
	-- how the ground is grassed (Core/World.surface): "short", one continuous,
	-- almost flat grassy surface with no blades or tufts; "less", grass in
	-- drifts between moss and worn earth; or "full", the earlier all-blades look
	-- (`grass short|less|full` in BonkDev rewrites the terrain live)
	Grass = "short",
	-- M3.B: the Blender art kit (tools/art) dresses the whole Wardwood; false
	-- builds the old part-built props instead (`art on|off` in BonkDev)
	Art = true,
	-- the kit's trees: full detail within `near` studs of the camera, their
	-- far version ("_LOD") to `far`, their horizon version ("_FAR") beyond;
	-- `slack` studs of hysteresis, so nothing flickers at a boundary
	ArtLod = { near = 110, far = 280, slack = 12 },
	-- short 3D grass, grown on each client only where its camera looks: a patch
	-- per `cell` studs of grassy ground within `radius` studs of a point `ahead`
	-- studs in front of the hero along the camera's view, pushed on by `lead`
	-- seconds of the hero's speed (at most `leadMax` studs); always within
	-- `keep` studs of the hero; grown nearest the hero first, `budgetMs` of each
	-- frame at most (four times that while ground within `urgent` studs of the
	-- hero, in plain view, is still bare: a teleport, a sharp turn)
	ArtGrass = { cell = 8, radius = 54, ahead = 20, lead = 0.4, leadMax = 26, keep = 30, urgent = 48, budgetMs = 0.8 },
	Surfaces = {
		Meadow = { material = "Grass", color = { 128, 162, 62 } },
		Lush = { material = "LeafyGrass", color = { 86, 130, 56 } },
		-- the short grass carpet: LeafyGrass too (it grows no blades), so it
		-- takes over that material's tint while `grass short` is down (Look.paint)
		Carpet = { material = "LeafyGrass", color = { 118, 166, 60 } },
		-- moss and leaf litter: under the trees, and in the meadows' hollows
		ForestFloor = { material = "Mud", color = { 78, 96, 54 } },
		Mud = { material = "Mud", color = { 78, 96, 54 } },
		Path = { material = "Ground", color = { 142, 114, 78 } },
		Ground = { material = "Ground", color = { 142, 114, 78 } },
		Rock = { material = "Rock", color = { 132, 128, 116 } },
		Slate = { material = "Slate", color = { 104, 106, 106 } },
		Sand = { material = "Sand", color = { 202, 186, 138 } },
		Snow = { material = "Snow", color = { 236, 242, 246 } },
	},
}

--- The run sky a roll in [0, 1) draws from RunSkies.
function Wardwood.runSky(roll: number): string
	local total = 0
	for _, entry in Wardwood.RunSkies do
		total += entry.weight
	end
	local at = roll * total
	for _, entry in Wardwood.RunSkies do
		at -= entry.weight
		if at < 0 then
			return entry.name
		end
	end
	return Wardwood.RunSkies[#Wardwood.RunSkies].name
end

return Wardwood

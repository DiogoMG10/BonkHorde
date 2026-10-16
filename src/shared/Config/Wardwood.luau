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

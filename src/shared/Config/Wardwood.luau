--!strict
-- Wardwood - the look of the map that both the game and the offline previews
-- read: which Roblox terrain material each World.surface key becomes, and its
-- tint. Plain numbers, so the headless tools can load it.

local Wardwood = {
	-- the sky a run starts with: "golden" (the default), "clear", "dusk",
	-- "sunset", "night" or "enchanted" (server/Wardwood/Look; `sky <name>` in
	-- BonkDev compares them live)
	Sky = "golden",
	-- how much of the ground grows grass (Core/World.surface): "less", grass in
	-- drifts between moss and worn earth, or "full", the earlier all-grass look
	-- (`grass full` / `grass less` in BonkDev rewrites the terrain live)
	Grass = "less",
	Surfaces = {
		Meadow = { material = "Grass", color = { 128, 162, 62 } },
		Lush = { material = "LeafyGrass", color = { 86, 130, 56 } },
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

return Wardwood

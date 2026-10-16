--!strict
-- Wardwood - the look of the map that both the game and the offline previews
-- read: which Roblox terrain material each World.surface key becomes, and its
-- tint. Plain numbers, so the headless tools can load it.

local Wardwood = {
	-- the sky a run starts with: "golden" (the baseline), "clear" or "dusk"
	-- (server/Wardwood/Look; `sky <name>` in BonkDev compares them live)
	Sky = "golden",
	Surfaces = {
		Meadow = { material = "Grass", color = { 128, 162, 62 } },
		Lush = { material = "LeafyGrass", color = { 86, 130, 56 } },
		ForestFloor = { material = "Mud", color = { 68, 84, 50 } },
		Mud = { material = "Mud", color = { 68, 84, 50 } },
		Path = { material = "Ground", color = { 142, 114, 78 } },
		Ground = { material = "Ground", color = { 142, 114, 78 } },
		Rock = { material = "Rock", color = { 132, 128, 116 } },
		Slate = { material = "Slate", color = { 104, 106, 106 } },
		Sand = { material = "Sand", color = { 202, 186, 138 } },
		Snow = { material = "Snow", color = { 236, 242, 246 } },
	},
}

return Wardwood

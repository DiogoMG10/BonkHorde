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
	-- how the ground is grassed (Core/World.surface): "native" (approved in
	-- Studio), the grassy ground in Roblox's own Grass material, its engine-drawn
	-- blades covering it seamlessly at GrassLength's 0.1 minimum; kept for
	-- comparison: "short", the same ground as a bladeless LeafyGrass carpet;
	-- "less", grass in drifts between moss and worn earth; "full", the earlier
	-- all-blades look (`grass native|short|less|full` in BonkDev, live)
	Grass = "native",
	-- M3.B: the Blender art kit (tools/art) dresses the whole Wardwood; false
	-- builds the old part-built props instead (`art on|off` in BonkDev)
	Art = true,
	-- the kit's trees: full detail within `near` studs of the camera, their
	-- far version ("_LOD") to `far`, their horizon version ("_FAR") beyond;
	-- `slack` studs of hysteresis, so nothing flickers at a boundary
	ArtLod = { near = 110, far = 280, slack = 12 },
	Surfaces = {
		Meadow = { material = "Grass", color = { 128, 162, 62 } },
		Lush = { material = "LeafyGrass", color = { 86, 130, 56 } },
		-- the short grass carpet: LeafyGrass too (it grows no blades), so it
		-- takes over that material's tint while `grass short` is down (Look.paint)
		Carpet = { material = "LeafyGrass", color = { 118, 166, 60 } },
		-- the same ground in Roblox's Grass material, its blades the colour of
		-- the carpet so they read as its texture (`grass native`, Look.paint)
		Turf = { material = "Grass", color = { 112, 158, 58 } },
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

--!nonstrict
-- GrassChunks - grass option B on trial: static 3D grass over the test meadow
-- (Config/Wardwood.GrassTest), in fixed world-aligned chunks.
--
-- Each chunk's blades (Core/GrassField) are baked once into three MeshParts,
-- one per tone (ArtKit.bakeMesh: no upload), under Workspace.GrassTest. Nothing
-- follows the player and nothing is created or recycled at run time: the
-- parts stay where they are and Roblox streams and draws them like any other.
-- `grass chunks on|off` in BonkDev; `grass test` stands you in the meadow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GrassField = require(ReplicatedStorage.Shared.Core.GrassField)
local Wardwood = require(ReplicatedStorage.Shared.Config.Wardwood)

local ArtKit = require(script.Parent.ArtKit)

local GrassChunks = {}

--- Build the test meadow's chunks (on) or take them away (off). Returns the
--- MeshParts made and the triangles they hold. Yields while it bakes.
function GrassChunks.set(world, on: boolean, mode: string): (number, number)
	local old = Workspace:FindFirstChild("GrassTest")
	if old then
		old:Destroy()
	end
	if not on then
		return 0, 0
	end
	local t = Wardwood.GrassTest
	local base = Color3.fromRGB(t.color[1], t.color[2], t.color[3])
	local folder = Instance.new("Folder")
	folder.Name = "GrassTest"
	local parts, tris = 0, 0
	local started = os.clock()
	for x0 = t.x, t.x + t.size - t.chunk, t.chunk do
		for z0 = t.z, t.z + t.size - t.chunk, t.chunk do
			local model = Instance.new("Model")
			model.Name = `Chunk{x0},{z0}`
			for k, mesh in GrassField.chunk(world, x0, z0, t.chunk, t.spacing, mode) do
				if mesh.tris > 0 then
					local mp = ArtKit.bakeMesh(mesh, GrassField.ToneNames[k])
					if mp then
						local tone = GrassField.Tones[k]
						mp.Color = Color3.new(math.min(base.R * tone, 1), math.min(base.G * tone, 1), math.min(base.B * tone, 1))
						mp.Material = Enum.Material.SmoothPlastic
						mp.CastShadow = false
						mp.Parent = model
						parts += 1
						tris += mesh.tris
					end
				end
			end
			model.Parent = folder
			task.wait()
		end
	end
	folder.Parent = Workspace
	print(`[GrassChunks] {parts} parts, {tris} triangles over {t.size}x{t.size} studs in {string.format("%.1f", os.clock() - started)}s`)
	return parts, tris
end

--- Re-tint the chunks live (`grass tint`).
function GrassChunks.tint(colour: Color3)
	local folder = Workspace:FindFirstChild("GrassTest")
	if not folder then
		return
	end
	for _, d in folder:GetDescendants() do
		if d:IsA("MeshPart") then
			local k = table.find(GrassField.ToneNames, d.Name)
			local tone = if k then GrassField.Tones[k] else 1
			d.Color = Color3.new(math.min(colour.R * tone, 1), math.min(colour.G * tone, 1), math.min(colour.B * tone, 1))
		end
	end
end

return GrassChunks

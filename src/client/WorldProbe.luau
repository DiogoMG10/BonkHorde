--!strict
-- WorldProbe - has the ground round a point streamed in to this client yet?
--
-- The world streams in (Workspace.StreamingEnabled), terrain and parts alike,
-- nearest first. A cover (the loading screen, the portal's light) asks this
-- before it lifts, so nobody watches the ground arrive. The client knows where
-- the ground should be (Core/MapGen for the Wardwood, Core/SkyholdGen for the
-- island), so it looks straight down at points on rings round the hero, where
-- there should be ground, and counts what it finds. Only what the server
-- streams counts: the terrain, and the island's own parts.

local Workspace = game:GetService("Workspace")

local WorldProbe = {}

export type Heights = (x: number, z: number) -> number? -- world height of the ground there, nil for none

-- the rings looked at: radius in studs and points on it; the near ones must be
-- all there, the far one mostly
local NEAR = { { 0, 1 }, { 18, 6 }, { 55, 10 } }
local FAR = { { 130, 14 } }
local ABOVE = 30 -- each look starts this far above the expected ground
local DEPTH = 60

local function share(centre: Vector3, rings, heightAt: Heights, params: RaycastParams): number
	local expected, found = 0, 0
	for _, ring in rings do
		local radius, count = ring[1], ring[2]
		for i = 1, count do
			local a = (i / count) * 2 * math.pi + radius * 0.01
			local x, z = centre.X + math.cos(a) * radius, centre.Z + math.sin(a) * radius
			local h = heightAt(x, z)
			if h then
				expected += 1
				if Workspace:Raycast(Vector3.new(x, h + ABOVE, z), Vector3.new(0, -DEPTH, 0), params) then
					found += 1
				end
			end
		end
	end
	return if expected == 0 then 1 else found / expected
end

--- How much of the ground near `centre` (0..1) and further out (0..1) is
--- there, looking only at `include` (the terrain and the server's own parts).
function WorldProbe.ground(centre: Vector3, heightAt: Heights, include: { Instance }): (number, number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.IgnoreWater = false
	return share(centre, NEAR, heightAt, params), share(centre, FAR, heightAt, params)
end

--- The ground round `centre` is in: all of it near, nearly all further out.
function WorldProbe.streamed(centre: Vector3, heightAt: Heights, include: { Instance }): boolean
	local near, far = WorldProbe.ground(centre, heightAt, include)
	return near >= 0.999 and far >= 0.85
end

return WorldProbe

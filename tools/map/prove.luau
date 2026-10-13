--!nocheck
-- Map prover. Builds the same map the server builds, then checks the promises
-- design/map.json makes and writes the verdict to work/map/report.json plus the
-- layout (heights, anchors, props) to work/map/layout.json for the plan image.
--
--     lune run tools/map/prove.luau

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local GameConfig = require("../../src/shared/Config/GameConfig")
local MapGen = require("../../src/shared/Core/MapGen")

local c = GameConfig
local map = MapGen.build(c.MapSizeStuds, c.HeightCellStuds, c.WallHeight)
local anchors = MapGen.anchors(map, 26, 0.35)
local props = MapGen.props(map, anchors)
MapGen.block(map, props)
local reach = MapGen.reachable(map, 0, 0, c.CliffSlope)

local checks = {}
local function check(name: string, pass: boolean, detail: string)
	table.insert(checks, { name = name, pass = pass, detail = detail })
end

-- every anchor walkable from spawn
local cut = 0
for _, a in anchors do
	if not MapGen.isReachable(map, reach, a.x, a.z) then
		cut += 1
	end
end
check("anchors_reachable", cut == 0, `{#anchors - cut} of {#anchors} anchors can be walked to from spawn`)

-- boss portal sites, tutorial sites
local far, near60, near120 = 0, 0, 0
for _, a in anchors do
	if a.d >= c.BossPortalMinDistance then
		far += 1
	end
	if a.d <= 60 then
		near60 += 1
	end
	if a.d <= 120 then
		near120 += 1
	end
end
check("boss_portal_sites", far >= 5, `{far} anchors at least {c.BossPortalMinDistance} studs from spawn`)
check("tutorial_sites", near60 >= 1 and near120 >= 4, `{near60} anchors within 60 studs, {near120} within 120`)

-- spawn clearing flat and empty
local worst = 0
for dx = -20, 20, 10 do
	for dz = -20, 20, 10 do
		worst = math.max(worst, MapGen.slopeAt(map, dx, dz))
	end
end
local inClearing = 0
for _, p in props do
	if p.x * p.x + p.z * p.z < 42 * 42 then
		inClearing += 1
	end
end
check("spawn_clearing", worst < 0.2 and inClearing == 0, `worst slope {string.format("%.3f", worst)}, {inClearing} props inside 42 studs`)

-- the plateau: reachable, but not straight up its south face
check(
	"plateau_route",
	MapGen.isReachable(map, reach, 0, 240) and not MapGen.canStep(map, 0, 152, 0, 160, c.CliffSlope),
	`top at {string.format("%.1f", MapGen.heightAt(map, 0, 240))} studs, reached by the ramps only`
)

-- the boundary holds
check("boundary_wall", not MapGen.isReachable(map, reach, map.half - 4, 0) and not MapGen.isReachable(map, reach, 0, -(map.half - 4)), "nothing walks out of the map")

-- walkable share, slide runs and cliffs
local n = map.n
local walk, slide, cliff, inside = 0, 0, 0, 0
for iz = 0, n - 1 do
	for ix = 0, n - 1 do
		local x, z = -map.half + ix * map.cell, -map.half + iz * map.cell
		if math.abs(x) < map.half - 30 and math.abs(z) < map.half - 30 then
			inside += 1
			if reach[iz * n + ix + 1] then
				walk += 1
			end
			local s = MapGen.slopeAt(map, x, z)
			if s >= 0.36 and s <= 0.84 then
				slide += 1
			elseif s > c.CliffSlope then
				cliff += 1
			end
		end
	end
end
local share = walk / inside
check("walkable_share", share >= 0.7, `{string.format("%.0f", share * 100)}% of the playfield is walkable from spawn`)
check("slide_runs", slide / inside >= 0.03, `{string.format("%.1f", slide / inside * 100)}% of the playfield is 20 to 40 degree slide ground`)

-- no solid prop traps an anchor, no two solid props touch
local touching = 0
local solid = {}
for _, p in props do
	if p.radius > 0 then
		table.insert(solid, p)
	end
end
for i = 1, #solid do
	for j = i + 1, #solid do
		local a, b = solid[i], solid[j]
		if (a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 < (a.radius + b.radius + 4) ^ 2 then
			touching += 1
		end
	end
end
check("prop_gaps", touching == 0, `{#solid} solid props, {touching} pairs closer than 4 studs apart`)

local kinds = {}
for _, p in props do
	kinds[p.kind] = (kinds[p.kind] or 0) + 1
end

local pass = true
for _, ch in checks do
	if not ch.pass then
		pass = false
	end
end

local report = {
	map = "ForestGrove",
	verdict = if pass then "PASS" else "FAIL",
	size_studs = c.MapSizeStuds,
	cell_studs = c.HeightCellStuds,
	anchors = #anchors,
	props = #props,
	props_by_kind = kinds,
	checks = checks,
	source = "tools/map/prove.luau over src/shared/Core/MapGen.luau (the module the server runs)",
}

if not fs.isDir("work/map") then
	fs.writeDir("work/map")
end
fs.writeFile("work/map/report.json", serde.encode("json", report, true))

local step = 2 -- every second sample is plenty for a plan image
local rows = {}
for iz = 0, n - 1, step do
	local row = table.create(math.ceil(n / step))
	for ix = 0, n - 1, step do
		local i = iz * n + ix + 1
		table.insert(row, math.floor(map.heights[i] * 10 + 0.5) / 10)
	end
	table.insert(rows, row)
end
local reachRows = {}
for iz = 0, n - 1, step do
	local row = {}
	for ix = 0, n - 1, step do
		table.insert(row, if reach[iz * n + ix + 1] then 1 else 0)
	end
	table.insert(reachRows, table.concat(row))
end
fs.writeFile(
	"work/map/layout.json",
	serde.encode("json", { half = map.half, cell = map.cell * step, heights = rows, reach = reachRows, anchors = anchors, props = props }, false)
)

for _, ch in checks do
	print((if ch.pass then "PASS  " else "FAIL  ") .. ch.name .. " - " .. ch.detail)
end
print("verdict: " .. report.verdict)
process.exit(if pass then 0 else 1)

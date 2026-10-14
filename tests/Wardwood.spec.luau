--!strict
-- Specs for the Wardwood prototype's two pure modules: the activation gate and
-- the dressing. The gate is the safety promise (the prototype never switches on
-- in the shared place or a published game); the dressing must keep every
-- promise the normal map keeps. The map-wide checks run in
-- `lune run tools/map/prove.luau wardwood`.

local GameConfig = require("../src/shared/Config/GameConfig")
local MapGen = require("../src/shared/Core/MapGen")
local ProtoGate = require("../src/shared/Core/ProtoGate")
local Wardwood = require("../src/shared/Config/Wardwood")
local WardwoodDressing = require("../src/shared/Core/WardwoodDressing")

local c = GameConfig
local map = MapGen.build(c.MapSizeStuds, c.HeightCellStuds, c.WallHeight)
local anchors = MapGen.anchors(map, 26, 0.35)
local base = MapGen.props(map, anchors)
local props, ward = WardwoodDressing.build(Wardwood, map, anchors, base)

local armed = { studio = true, placeId = 0, gameId = 0, marker = Wardwood.MarkerValue }

local function with(overrides: { [string]: any }): ProtoGate.Env
	local env = table.clone(armed) :: any
	for k, v in overrides do
		env[k] = v
	end
	return env
end

local function isWardwood(kind: string): boolean
	return string.sub(kind, 1, 3) == "WW_"
end

return {
	["the gate opens only in an armed, unpublished local Studio file"] = function()
		local profile = ProtoGate.decide(armed, Wardwood)
		assert(profile == ProtoGate.Prototype, "armed local file should run the prototype, got " .. profile)
	end,

	["the gate stays shut without the marker"] = function()
		local env = with({})
		env.marker = nil
		local profile, reason = ProtoGate.decide(env, Wardwood)
		assert(profile == ProtoGate.Default and reason == "no prototype marker", reason)
	end,

	["the gate refuses a wrong marker, a live server, the live place and any published place"] = function()
		local cases = {
			with({ marker = "yes" }),
			with({ studio = false }),
			with({ placeId = Wardwood.LivePlaceId, gameId = 10770589827 }),
			with({ placeId = Wardwood.LivePlaceId }),
			with({ placeId = 123 }),
			with({ gameId = 456 }),
		}
		for i, env in cases do
			local profile, reason = ProtoGate.decide(env, Wardwood)
			assert(profile == ProtoGate.Default, `case {i} should be refused`)
			assert(string.find(reason, "refused", 1, true), `case {i} should say why: {reason}`)
		end
	end,

	["the ward is placed, away from spawn, with no solid piece near an anchor"] = function()
		assert(ward ~= nil, "no spot for the ward within 40 studs of WardCenter")
		local w = ward :: WardwoodDressing.Ward
		for _, piece in WardwoodDressing.wardPieces(Wardwood, w) do
			assert(piece.x * piece.x + piece.z * piece.z >= Wardwood.SpawnKeepClear ^ 2, piece.kind .. " inside the spawn clearing")
			if piece.radius > 0 then
				for _, a in anchors do
					local need = Wardwood.WardAnchorClearance + piece.radius
					assert((a.x - piece.x) ^ 2 + (a.z - piece.z) ^ 2 >= need * need, piece.kind .. " grows through an anchor")
				end
			end
		end
	end,

	["outside the region the map is exactly MossyWoods"] = function()
		local outsideBase, outsideNew = 0, 0
		for _, p in base do
			if not WardwoodDressing.inRegion(Wardwood, p.x, p.z) then
				outsideBase += 1
			end
		end
		for _, p in props do
			if not WardwoodDressing.inRegion(Wardwood, p.x, p.z) then
				outsideNew += 1
				assert(not isWardwood(p.kind), "a Wardwood prop outside the region: " .. p.kind)
			else
				assert(isWardwood(p.kind), "a MossyWoods prop left inside the region: " .. p.kind)
			end
		end
		assert(outsideBase == outsideNew, `{outsideBase} MossyWoods props outside the region, {outsideNew} kept`)
	end,

	["the clearing, the paths and the viewpoints stay free of trunks and slabs"] = function()
		-- the ward itself stands at the clearing's edge on purpose
		for _, p in props do
			if p.kind == "WW_Trunk" or p.kind == "WW_Slab" then
				assert(p.x * p.x + p.z * p.z >= (Wardwood.ClearingRadius + p.radius) ^ 2, p.kind .. " inside the clearing")
				local d = WardwoodDressing.pathDistance(Wardwood, p.x, p.z)
				assert(d >= Wardwood.PathHalfWidth + p.radius, p.kind .. " on a path")
				for _, v in Wardwood.Viewpoints do
					assert((v.x - p.x) ^ 2 + (v.z - p.z) ^ 2 >= (6 + p.radius) ^ 2, p.kind .. " on viewpoint " .. v.name)
				end
			end
		end
	end,

	["the forest band is at least twice as dense as the ring"] = function()
		local band, ring = 0, 0
		for _, p in props do
			if p.kind == "WW_Trunk" then
				if p.x < Wardwood.BandMaxX then
					band += 1
				else
					ring += 1
				end
			end
		end
		local r = Wardwood.Region
		local bandArea = (Wardwood.BandMaxX - r.minX) * (r.maxZ - r.minZ)
		local clearing = math.pi * (Wardwood.ClearingRadius + 14) ^ 2
		local ringArea = (r.maxX - Wardwood.BandMaxX) * (r.maxZ - r.minZ) - clearing
		assert(band > 0 and ring > 0, `{band} trunks in the band, {ring} in the ring`)
		assert(band / bandArea >= 2 * ring / ringArea, `band {band} over {bandArea}, ring {ring} over {ringArea}`)
	end,

	["every anchor is still reachable from spawn"] = function()
		local m = MapGen.build(c.MapSizeStuds, c.HeightCellStuds, c.WallHeight)
		MapGen.block(m, props)
		local reach = MapGen.reachable(m, 0, 0, c.CliffSlope)
		local cut = 0
		for _, a in anchors do
			if not MapGen.isReachable(m, reach, a.x, a.z) then
				cut += 1
			end
		end
		assert(cut == 0, `{cut} anchors cut off by the Wardwood dressing`)
	end,

	["the dressing is deterministic"] = function()
		local again = WardwoodDressing.build(Wardwood, map, anchors, base)
		assert(#again == #props, "different prop counts between two builds")
		for i, p in props do
			local q = again[i]
			assert(p.kind == q.kind and p.x == q.x and p.z == q.z and p.scale == q.scale, "prop " .. i .. " moved")
		end
	end,
}

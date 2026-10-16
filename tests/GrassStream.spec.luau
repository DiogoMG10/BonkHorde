--!strict
-- Specs for the client's short 3D grass streaming (client ArtController runs
-- the same Core/ArtPlan plan): simulated frame by frame at 60 fps for a hero
-- bunny hopping flat out, sliding with the camera swinging, and teleported,
-- with the creation budget the client allows itself. Grass ahead of the hero,
-- and all of it round the hero, must already be there when it comes into view.

local ArtPlan = require("../src/shared/Core/ArtPlan")
local GameConfig = require("../src/shared/Config/GameConfig")
local Wardwood = require("../src/shared/Config/Wardwood")
local World = require("../src/shared/Core/World")

local world = World.build(GameConfig)
local field = ArtPlan.grassField(world)
local g = Wardwood.ArtGrass

local DT = 1 / 60
-- what the client's 0.8 ms a frame buys, at an assumed ~0.08 ms per patch
-- (pooled copy, move, tint); Studio has the real figure
local PER_FRAME = 10
local CATCHUP = 4
local SEEN = 48 -- studs ahead of the hero that must never be bare

type Frame = { hx: number, hz: number, lx: number, lz: number, vx: number, vz: number }

local function simulate(seconds: number, warm: number, at: (t: number) -> Frame)
	local active: { [number]: boolean } = {}
	local pending: { ArtPlan.GrassCell } = {}
	local nextI, planT = 1, math.huge
	local lastX, lastZ: number? = nil, nil
	local lastLX, lastLZ: number? = nil, nil
	local stats = { ahead = 0, keep = 0, maxActive = 0, grown = 0, firstFull = nil :: number? }
	for frame = 0, math.floor(seconds / DT) do
		local t = frame * DT
		local f = at(t)
		planT += DT
		local moved = if lastX and lastZ then math.sqrt((f.hx - lastX) ^ 2 + (f.hz - lastZ) ^ 2) else math.huge
		local turned = lastLX ~= nil and (f.lx * lastLX + f.lz * lastLZ) < 0.9
		if planT >= 0.1 or moved > g.cell or turned then
			lastLX, lastLZ = f.lx, f.lz
			planT = 0
			lastX, lastZ = f.hx, f.hz
			local gx, gz = ArtPlan.grassCentre(f.hx, f.hz, f.lx, f.lz, f.vx, f.vz)
			local drop
			drop, pending = ArtPlan.grassPlan(active, f.hx, f.hz, gx, gz)
			nextI = 1
			for _, key in drop do
				active[key] = nil
			end
		end
		local budget = PER_FRAME
		local first = pending[nextI]
		if first and first.d < g.urgent * g.urgent then
			budget *= CATCHUP
		end
		local made = 0
		while nextI <= #pending and made < budget do
			local c = pending[nextI]
			nextI += 1
			if active[c.key] == nil then
				active[c.key] = field(c.cx, c.cz) ~= nil
				made += 1
				stats.grown += 1
			end
		end
		local count = 0
		for _ in active do
			count += 1
		end
		stats.maxActive = math.max(stats.maxActive, count)
		-- what the camera shows: the hero's own ground, and the ground ahead
		local missKeep, missAhead = 0, 0
		local ll = math.sqrt(f.lx * f.lx + f.lz * f.lz)
		local r = math.ceil(SEEN / g.cell)
		local fx, fz = math.floor(f.hx / g.cell), math.floor(f.hz / g.cell)
		for cx = fx - r, fx + r do
			for cz = fz - r, fz + r do
				local x, z = (cx + 0.5) * g.cell, (cz + 0.5) * g.cell
				local dx, dz = x - f.hx, z - f.hz
				local d = math.sqrt(dx * dx + dz * dz)
				if active[ArtPlan.grassKey(cx, cz)] == nil and field(cx, cz) then
					if d <= g.keep - g.cell then
						missKeep += 1
					elseif d <= SEEN and (dx * f.lx + dz * f.lz) / ll > 0.5 * d then
						missAhead += 1
					end
				end
			end
		end
		if missKeep == 0 and not stats.firstFull then
			stats.firstFull = t
		end
		if t >= warm then
			stats.keep += missKeep
			stats.ahead += missAhead
		end
	end
	return stats
end

return {
	["bunny hopping flat out, the grass ahead is always already grown"] = function()
		local speed = 50 -- the bunny-hop cap
		local stats = simulate(5, 0.5, function(t)
			return { hx = -120 + speed * t, hz = 250, lx = 1, lz = 0, vx = speed, vz = 0 }
		end)
		assert(stats.keep == 0, `{stats.keep} bare cells round the hero`)
		assert(stats.ahead == 0, `{stats.ahead} bare cells ahead of the hero`)
		assert(stats.maxActive < 260, `{stats.maxActive} cells held at once`)
	end,

	["sliding with the camera swinging round, the hero's ground never goes bare"] = function()
		local speed = 40
		local stats = simulate(6, 0.5, function(t)
			-- the camera and the slide turn a quarter every 0.8 s
			local leg = math.floor(t / 0.8)
			local a = leg * math.pi / 2
			local x, z = -100, 260
			for k = 0, leg - 1 do
				local ak = k * math.pi / 2
				x += math.cos(ak) * speed * 0.8
				z += math.sin(ak) * speed * 0.8
			end
			local tl = t - leg * 0.8
			x += math.cos(a) * speed * tl
			z += math.sin(a) * speed * tl
			return { hx = x, hz = z, lx = math.cos(a), lz = math.sin(a), vx = math.cos(a) * speed, vz = math.sin(a) * speed }
		end)
		assert(stats.keep == 0, `{stats.keep} bare cells round the hero`)
		-- a quarter turn swings fresh ground into view; allow a moment for it
		assert(stats.ahead <= 40, `{stats.ahead} bare cell-frames ahead while turning`)
	end,

	["after a teleport the hero's ground is grown within a quarter of a second"] = function()
		local stats = simulate(1.5, 1.5, function(t)
			if t < 1 then
				return { hx = 0, hz = 0, lx = 0, lz = 1, vx = 0, vz = 0 }
			end
			return { hx = -300, hz = 120, lx = 0, lz = 1, vx = 0, vz = 0 }
		end)
		-- firstFull is the first frame with the hero's ground whole; re-run from the jump
		local after = simulate(0.25, 0.24, function()
			return { hx = -300, hz = 120, lx = 0, lz = 1, vx = 0, vz = 0 }
		end)
		assert(after.keep == 0, `{after.keep} bare cells round the hero 0.25 s after arriving`)
		assert(stats.firstFull ~= nil, "the hero's ground was never whole")
	end,
}

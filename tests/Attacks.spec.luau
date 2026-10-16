--!strict
-- Specs for the regular enemies' special attacks (M4.A, Core/Attacks): the
-- paths stay on walkable ground, they reach where the hero stood, and the
-- numbers leave a walking hero time to step out of every telegraph.

local Attacks = require("../src/shared/Core/Attacks")
local GameConfig = require("../src/shared/Config/GameConfig")
local MapGen = require("../src/shared/Core/MapGen")
local Roster = require("../src/shared/Config/Roster")
local World = require("../src/shared/Core/World")

local world = World.build(GameConfig)
local map = world.map
local cliff = GameConfig.CliffSlope

local CHARGE = Roster.Enemies.GoblinBruiser.attack
local LEAP = Roster.Enemies.Slime.attack

return {
	["a charge runs its full length on open ground and stops short of the map's edge"] = function()
		local bx, bz, t = Attacks.charge(map, 0, 0, 10, 0, CHARGE.run, CHARGE.time, cliff)
		assert(math.abs(bx - CHARGE.run) < 1e-6 and math.abs(bz) < 1e-6, `the charge ended at {bx}, {bz}`)
		assert(math.abs(t - CHARGE.time) < 1e-6, "a full run took the wrong time")
		-- run at the edge of the playable world: it stops where walking would
		local edge = 0
		for x = 0, map.half, 2 do
			if MapGen.outside(x, 0) > -14 then
				edge = x
				break
			end
		end
		local sx = edge - 8
		local ex2, _, t2 = Attacks.charge(map, sx, 0, sx + 30, 0, CHARGE.run, CHARGE.time, cliff)
		assert(ex2 < sx + CHARGE.run, "the charge ran through the edge of the world")
		assert(t2 < CHARGE.time, "a shortened charge took the full time")
		-- every step of it was walkable
		local px = sx
		while px + 1.5 <= ex2 do
			assert(MapGen.canStep(map, px, 0, px + 1.5, 0, cliff), "the charge crossed unwalkable ground")
			px += 1.5
		end
	end,

	["a leap lands where the hero stood, or as far as it reaches"] = function()
		local lx, lz = Attacks.leap(map, 0, 0, 8, 6, LEAP.reach, cliff)
		assert(math.abs(lx - 8) < 1e-6 and math.abs(lz - 6) < 1e-6, `landed at {lx}, {lz} instead of on the hero`)
		local fx, fz = Attacks.leap(map, 0, 0, 40, 0, LEAP.reach, cliff)
		assert(math.abs(fx - LEAP.reach) < 1e-6 and math.abs(fz) < 1e-6, "a long leap went past its reach")
		local sx, sz = Attacks.leap(map, 5, 5, 5, 5, LEAP.reach, cliff)
		assert(sx == 5 and sz == 5, "a leap at its own spot moved")
	end,

	["segment distance measures a lane"] = function()
		assert(math.abs(Attacks.segmentDistance(5, 2, 0, 0, 10, 0) - 2) < 1e-9, "beside the lane")
		assert(math.abs(Attacks.segmentDistance(13, 4, 0, 0, 10, 0) - 5) < 1e-9, "past its end")
		assert(math.abs(Attacks.segmentDistance(3, 4, 0, 0, 0, 0) - 5) < 1e-9, "a point lane")
	end,

	["both attacks reach the hero's spot from anywhere they start"] = function()
		assert(CHARGE.run >= CHARGE.range[2] + 2, "a charge started at its longest range stops short of the hero")
		assert(LEAP.reach >= LEAP.range[2], "a leap started at its longest range falls short")
		assert(CHARGE.range[1] > 0 and LEAP.range[1] > 0, "an attack can start point blank")
	end,

	["a walking hero can step out of every telegraph in time"] = function()
		local walk = GameConfig.PlayerWalkSpeed
		local body = GameConfig.HeroBodyRadius
		-- the charge: sideways out of its lane before it arrives (it is at least windup away)
		local out = CHARGE.width + body
		assert(walk * CHARGE.windup >= out * 2, `a hero needs {out} studs sideways, gets {walk * CHARGE.windup}`)
		-- the leap: out of its ring before it lands
		local ring = LEAP.radius + body
		assert(walk * (LEAP.windup + LEAP.air) >= ring * 2, `a hero needs {ring} studs, gets {walk * (LEAP.windup + LEAP.air)}`)
		-- and the telegraphs last long enough to be seen
		assert(CHARGE.windup >= 0.6 and LEAP.windup + LEAP.air >= 0.8, "a telegraph too short to read")
		-- neither is a bigger hit than a heavy blow should be
		assert(CHARGE.dmg <= 2 and LEAP.dmg <= 2, "an attack hits too hard for a regular enemy")
		assert(CHARGE.recover >= 0.8, "the charger is not winded long enough to punish")
	end,
}

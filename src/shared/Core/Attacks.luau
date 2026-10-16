--!strict
-- Attacks - the rules behind the regular enemies' special attacks (M4.A):
-- the Goblin Bruiser's charge and the Slime's leap (Roster.Enemies.<Type>.attack).
-- EnemyService runs them; they are pure so the specs can check them headless.
--
-- Both are committed: the path is fixed when the windup starts and drawn for
-- every player straight away, so what is shown is exactly what will be hit,
-- and a hero who steps out of it is safe. Neither can carry an enemy where it
-- could not walk: the path is walked along the heightfield first, with the
-- same step rule enemies move by, and stops short of a cliff.

local MapGen = require(script and script.Parent.MapGen or "./MapGen")

local Attacks = {}

local STEP = 1.5 -- studs between path checks

--- How far a straight run from (x, z) along (ux, uz) can go, up to `length`
--- studs, before the ground stops being walkable.
function Attacks.clearRun(map: MapGen.Map, x: number, z: number, ux: number, uz: number, length: number, cliff: number): number
	local s = 0
	local px, pz = x, z
	while s < length do
		local n = math.min(STEP, length - s)
		local nx, nz = px + ux * n, pz + uz * n
		if not MapGen.canStep(map, px, pz, nx, nz, cliff) then
			break
		end
		px, pz = nx, nz
		s += n
	end
	return s
end

--- A charge from (x, z) at a hero at (tx, tz): where it ends, `run` studs
--- toward the hero's spot and on past it when the hero was nearer (or short of
--- a cliff), and how long it takes at `run / time` studs a second.
function Attacks.charge(
	map: MapGen.Map,
	x: number,
	z: number,
	tx: number,
	tz: number,
	run: number,
	time: number,
	cliff: number
): (number, number, number)
	local dx, dz = tx - x, tz - z
	local d = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
	local ux, uz = dx / d, dz / d
	local s = Attacks.clearRun(map, x, z, ux, uz, run, cliff)
	return x + ux * s, z + uz * s, math.max(time * s / run, 0.05)
end

--- A leap from (x, z) at a hero at (tx, tz): it lands where the hero stood
--- when it crouched, or `reach` studs short of there, or short of a cliff.
function Attacks.leap(map: MapGen.Map, x: number, z: number, tx: number, tz: number, reach: number, cliff: number): (number, number)
	local dx, dz = tx - x, tz - z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1e-3 then
		return x, z
	end
	local ux, uz = dx / d, dz / d
	local s = Attacks.clearRun(map, x, z, ux, uz, math.min(d, reach), cliff)
	return x + ux * s, z + uz * s
end

--- M4.B: whether an attack of `kind` may start on a hero at `now`, given that
--- hero's gates (kind -> the time it opens; `any` holds every kind). When it
--- may, the gates close behind it, `gap` for its own kind and `anyGap` for all,
--- so a pack's chargers and leapers wind up one after another, never in step.
--- Returns whether it may, and when the gates open.
function Attacks.turn(gates: { [string]: number }, kind: string, now: number, gap: number, anyGap: number): (boolean, number)
	local opens = math.max(gates[kind] or 0, gates.any or 0)
	if now < opens then
		return false, opens
	end
	gates[kind] = now + gap
	gates.any = now + anyGap
	return true, now
end

--- The distance from (px, pz) to the segment (ax, az)-(bx, bz).
function Attacks.segmentDistance(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local vx, vz = bx - ax, bz - az
	local len2 = vx * vx + vz * vz
	local t = if len2 > 1e-9 then math.clamp(((px - ax) * vx + (pz - az) * vz) / len2, 0, 1) else 0
	local cx, cz = ax + vx * t, az + vz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

return Attacks

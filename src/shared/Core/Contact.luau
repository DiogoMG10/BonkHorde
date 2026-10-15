--!strict
-- Contact - when an enemy's body touches a hero, and when a hero is camping
-- out of reach. Pure.
--
-- Reach is measured body to body: the enemy's visible body radius plus the
-- hero's, plus a hair of margin. An enemy is only counted as touching when it
-- is in reach both where the server has it now and where clients were last
-- told it is (what they are drawing), so a chasing enemy never hits from the
-- stretch of ground it has covered but not yet been seen to cover.
--
-- Camping: a hero standing on something enemies cannot climb (a tree, a roof)
-- with enemies gathered below is out of reach for good. After a few seconds of
-- that, the run answers with a telegraphed strike. A jump or a bunny hop is far
-- too short to count, and coming down resets the clock.

local Contact = {}

--- How far apart two centres can be for an enemy to touch a hero.
function Contact.reach(enemyBody: number, heroBody: number, margin: number): number
	return enemyBody + heroBody + margin
end

--- Is the enemy touching, horizontally? `dist` is from where the server has
--- it, `drawnDist` from where clients were last told it was.
function Contact.touches(dist: number, drawnDist: number, reach: number): boolean
	return dist <= reach and drawnDist <= reach
end

--- Do the hero's body (feet up to feet + height) and the enemy's (low to
--- high) overlap in height, within `tolerance`?
function Contact.overlapsY(heroFeet: number, heroHeight: number, enemyLow: number, enemyHigh: number, tolerance: number): boolean
	return heroFeet <= enemyHigh + tolerance and heroFeet + heroHeight >= enemyLow - tolerance
end

--- Does a strike aimed at height `y` (an anti-camping strike, drawn there)
--- reach a hero whose feet are at `feet`? Only from `below` under it to
--- `above` over it: the hero it was aimed at, not a teammate on the ground
--- far beneath, and not dodged by jumping on the spot.
function Contact.inStrikeBand(feet: number, y: number, below: number, above: number): boolean
	return feet >= y - below and feet <= y + above
end

export type Camp = {
	seconds: number, -- out of reach this long, with enemies below, before a strike
	every: number, -- and then at most one strike this often
}

export type CampState = {
	elevated: number, -- seconds spent continuously above reach
	nextAt: number, -- gameplay time the next strike may come
}

function Contact.newCamp(): CampState
	return { elevated = 0, nextAt = 0 }
end

--- One step of the camping clock. `high` is whether the hero's feet are above
--- what enemies can reach; `watched` whether enemies are gathered below.
--- Returns true when a strike should be called down now.
function Contact.campStep(s: CampState, cfg: Camp, high: boolean, watched: boolean, dt: number, now: number): boolean
	if not high then
		s.elevated = 0 -- back within reach: start over
		return false
	end
	if watched then
		s.elevated += dt -- alone up there is not camping; it only counts with enemies below
	end
	if s.elevated >= cfg.seconds and now >= s.nextAt then
		s.nextAt = now + cfg.every
		return true
	end
	return false
end

return Contact

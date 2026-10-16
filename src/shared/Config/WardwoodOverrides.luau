--!strict
-- WardwoodOverrides - hand-made touches to the generated Wardwood, kept in Git.
--
-- The Wardwood is generated (Core/World), so moving a tree in Studio is lost on
-- the next run. Put the change here instead; World.build applies it to the prop
-- before anything is built, so the server's colliders, the enemies' pathing and
-- every client's art all agree.
--
-- A prop is named by its kind and where the generator put it, rounded to the
-- stud: "Oak@-398,-34" (a second prop of the same kind on the same stud gets
-- "#2"). `art pick` in Workspace.BonkDev prints the nearest prop's key and a
-- line to paste. Fields, all optional:
--   x, z     move it to this spot          dx, dz   or nudge it by this much
--   yaw      turn it to this many degrees  scale    resize it
--   asset    show this kit variation instead (ArtPlan.Families, e.g. "OakC")
--   hide     true: take it out entirely (its collider too)
--
-- Example:
--   ["Oak@-398,-34"] = { dx = 3, yaw = 90, asset = "OakB" },
--   ["Bush@120,44"] = { hide = true },

export type Override = {
	x: number?,
	z: number?,
	dx: number?,
	dz: number?,
	yaw: number?,
	scale: number?,
	asset: string?,
	hide: boolean?,
}

local Overrides: { [string]: Override } = {}

return Overrides

--!strict
-- Specs for the saved player settings (Core/Settings, DataService): the
-- volumes and the enemy-outline toggle survive each other's saves, and a
-- forged message stores nothing odd.

local Settings = require("../src/shared/Core/Settings")

return {
	["volumes are clamped and the outline toggle kept as a boolean"] = function()
		local out = Settings.clean({ master = 1.7, music = -0.2, sfx = 0.555, outlines = true })
		assert(out.master == 1 and out.music == 0 and out.sfx == 0.56, "volumes not clamped to two decimals")
		assert(out.outlines == true, "the outline toggle was dropped")
	end,

	["a forged message stores nothing odd"] = function()
		local out = Settings.clean({ master = "loud", outlines = "yes", admin = true, music = 0 / 0 })
		local n = 0
		for _ in out do
			n += 1
		end
		assert(n == 0, `{n} junk keys kept`)
		assert(next(Settings.clean("not a table")) == nil, "a non-table kept something")
	end,

	["saving the volumes never resets the outlines, nor the other way round"] = function()
		local saved = Settings.merge({}, { master = 0.7, music = 0.45, sfx = 0.55, outlines = true })
		local afterVolumes = Settings.merge(saved, { master = 0.2, music = 0.1, sfx = 0.3 })
		assert(afterVolumes.outlines == true, "a volume save turned the outlines off")
		assert(afterVolumes.master == 0.2, "the volume did not change")
		local afterToggle = Settings.merge(afterVolumes, { outlines = false })
		assert(afterToggle.outlines == false, "the toggle did not change")
		assert(afterToggle.master == 0.2 and afterToggle.music == 0.1 and afterToggle.sfx == 0.3, "a toggle save reset the volumes")
	end,

	["a profile from before the toggle loads with outlines unset (off)"] = function()
		local old = Settings.clean({ master = 0.5, music = 0.5, sfx = 0.5 })
		assert(old.outlines == nil, "an old profile gained an outline setting")
		assert(Settings.merge(nil, { outlines = true }).outlines == true, "a first save from a new profile failed")
	end,
}

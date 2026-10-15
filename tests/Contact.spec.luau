--!strict
-- Specs for enemy contact (M2.D): reach is body to body, measured from the
-- real meshes, a chasing enemy is judged where clients see it, jumping over an
-- enemy clears it; and camping out of reach draws a strike while ordinary
-- jumps and bunny hops never do.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Contact = require("../src/shared/Core/Contact")
local GameConfig = require("../src/shared/Config/GameConfig")
local Roster = require("../src/shared/Config/Roster")

local HERO = GameConfig.HeroBodyRadius
local MARGIN = GameConfig.ContactMargin
local ELITE = GameConfig.EliteScale
local GRAVITY = 196.2 -- Workspace.Gravity default
local DT = 1 / 30

-- the model each enemy is drawn with (EnemyRenderController MODEL_NAME)
local MODEL = { BoulderBro = "EnemyRockGolem", Hamlet = "EnemyHogBrute", OldManTimber = "BossOldManTimber" }

local function reachOf(def, scale: number): number
	return Contact.reach((def.body or def.radius) * scale, HERO, MARGIN)
end

return {
	["every enemy's body radius matches its real mesh, as the client fits it"] = function()
		local manifest = serde.decode("json", fs.readFile("assets/meshes/manifest.json")).assets
		for name, def in Roster.Enemies do
			local mesh = manifest[MODEL[name] or ("Enemy" .. name)]
			assert(def.body, `{name} has no body radius`)
			if mesh then
				local b = mesh.bounds_studs
				local measured = (b[1] + b[3]) / 4 * def.height / b[2]
				assert(math.abs(measured - def.body) < 0.1, `{name}: body {def.body}, mesh says {measured}`)
			end
		end
	end,

	["reach is tighter than before for every regular enemy"] = function()
		for name, def in Roster.Enemies do
			if not def.boss then
				local old = def.radius + GameConfig.PlayerRadius + 0.6
				local new = reachOf(def, 1)
				assert(new < old - 0.6, `{name}: {new} vs old {old}`)
			end
		end
	end,

	["a goblin passed at three studs no longer hurts (it did before)"] = function()
		local runt = Roster.Enemies.GoblinRunt
		local old = runt.radius + GameConfig.PlayerRadius + 0.6
		assert(3 < old, "the old reach hit at three studs")
		assert(not Contact.touches(3, 3, reachOf(runt, 1)), "bodies three studs apart do not touch")
	end,

	["elites and bosses reach further, in proportion to their size"] = function()
		for name, def in Roster.Enemies do
			assert(reachOf(def, ELITE) > reachOf(def, 1), name)
		end
		local timber = reachOf(Roster.Enemies.OldManTimber, 1)
		assert(timber > 8 and timber < 9.5, `the stage boss reaches {timber}`)
	end,

	["every enemy closes to inside its reach without standing in the hero"] = function()
		for name, def in Roster.Enemies do
			for _, scale in { 1, ELITE } do
				-- it closes to 0.85 of its reach, which is outside the hero's own body
				assert(reachOf(def, scale) * 0.85 > HERO, name)
			end
		end
	end,

	["a chasing enemy hits only once clients have seen it arrive"] = function()
		local reach = reachOf(Roster.Enemies.GoblinRunt, 1)
		-- the server has it touching, but the last snapshot (what is drawn) is a stride behind
		assert(not Contact.touches(reach - 0.2, reach + 1.3, reach))
		assert(Contact.touches(reach - 0.2, reach - 0.1, reach))
	end,

	["standing next to an enemy is touched; jumping over it is not"] = function()
		local h = Roster.Enemies.GoblinRunt.height
		local tol = GameConfig.ContactHeightTolerance
		assert(Contact.overlapsY(0, GameConfig.HeroHeight, 0, h, tol), "standing")
		assert(Contact.overlapsY(h + 0.2, GameConfig.HeroHeight, 0, h, tol), "skimming its head")
		assert(not Contact.overlapsY(h + 1, GameConfig.HeroHeight, 0, h, tol), "a jump that clears it")
		local jump = GameConfig.PlayerJumpHeight
		assert(jump > h + 1, "a plain jump clears a goblin")
	end,

	["camping up a tree draws a strike after a few seconds, then at a limited rate"] = function()
		local s = Contact.newCamp()
		local cfg = { seconds = GameConfig.CampSeconds, every = GameConfig.CampEvery }
		local strikes = {}
		local t = 0
		while t < 20 do
			t += DT
			if Contact.campStep(s, cfg, true, true, DT, t) then
				table.insert(strikes, t)
			end
		end
		assert(#strikes > 0 and strikes[1] >= cfg.seconds - 1e-6 and strikes[1] < cfg.seconds + 0.1, "the first comes on time")
		for i = 2, #strikes do
			assert(strikes[i] - strikes[i - 1] >= cfg.every - 1e-6, "then no faster than CampEvery")
		end
	end,

	["alone up a tree, or coming down, is not camping"] = function()
		local cfg = { seconds = GameConfig.CampSeconds, every = GameConfig.CampEvery }
		local s = Contact.newCamp()
		for i = 1, math.floor(30 / DT) do
			assert(not Contact.campStep(s, cfg, true, false, DT, i * DT), "no enemies below: nothing to answer")
		end
		s = Contact.newCamp()
		local t = 0
		for _ = 1, 10 do
			for _ = 1, math.floor(3 / DT) do -- three seconds up...
				t += DT
				assert(not Contact.campStep(s, cfg, true, true, DT, t))
			end
			t += DT
			Contact.campStep(s, cfg, false, true, DT, t) -- ...a moment down resets the clock
		end
	end,

	["jumping and bunny hopping never count as camping"] = function()
		local cfg = { seconds = GameConfig.CampSeconds, every = GameConfig.CampEvery }
		local s = Contact.newCamp()
		local up = math.sqrt(2 * GRAVITY * GameConfig.PlayerJumpHeight)
		local t = 0
		for _ = 1, 200 do -- two hundred hops in a row, all with enemies around
			local air = 2 * up / GRAVITY
			local a = 0
			while a < air do
				a += DT
				t += DT
				local feet = up * a - GRAVITY * a * a / 2
				assert(not Contact.campStep(s, cfg, feet > GameConfig.CampHeight, true, DT, t), "a hop drew a strike")
			end
			t += DT
			assert(not Contact.campStep(s, cfg, false, true, DT, t))
		end
	end,
}

--!strict
-- Specs for the heavier pure modules: Offers, Grid, MapGen, Snapshot.

local GameConfig = require("../src/shared/Config/GameConfig")
local Grid = require("../src/shared/Core/Grid")
local MapGen = require("../src/shared/Core/MapGen")
local Offers = require("../src/shared/Core/Offers")
local Roster = require("../src/shared/Config/Roster")
local Snapshot = require("../src/shared/Core/Snapshot")

-- a small deterministic generator so every run of the suite sees the same draws
local function lcg(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local function levelUp(loadout: any, rnd: () -> number)
	return Offers.levelUp(
		loadout,
		Roster.WeaponOrder,
		Roster.Weapons,
		Roster.TomeOrder,
		Roster.Tomes,
		Roster.RarityOrder,
		Roster.RarityWeights,
		Roster.RarityLuckFactor,
		Roster.RarityMultiplier,
		3,
		rnd
	)
end

local map = MapGen.build(GameConfig.MapSizeStuds, GameConfig.HeightCellStuds, GameConfig.WallHeight)
local anchors = MapGen.anchors(map, 26, 0.35)
local props = MapGen.props(map, anchors)
MapGen.block(map, props)
local reach = MapGen.reachable(map, 0, 0, GameConfig.CliffSlope)

return {
	["rarity rolls run from Common to Legendary"] = function()
		local order, weights = Roster.RarityOrder, Roster.RarityWeights
		assert(Offers.rollRarity(order, weights, Roster.RarityLuckFactor, 0, 0) == "Common")
		assert(Offers.rollRarity(order, weights, Roster.RarityLuckFactor, 0, 0.9999) == "Legendary")
	end,

	["luck makes a Legendary more likely, not less"] = function()
		local order, weights = Roster.RarityOrder, Roster.RarityWeights
		local function share(luck: number): number
			local rnd, hits = lcg(7), 0
			for _ = 1, 4000 do
				if Offers.rollRarity(order, weights, Roster.RarityLuckFactor, luck, rnd()) == "Legendary" then
					hits += 1
				end
			end
			return hits
		end
		assert(share(1) > share(0) * 2, "100% luck should at least double Legendary rolls")
	end,

	["a level-up shows three different offers"] = function()
		local rnd = lcg(42)
		for _ = 1, 50 do
			local offers = levelUp({ weapons = { Sword = 1 }, tomes = {}, banished = {}, luck = 0, weaponSlots = 4, tomeSlots = 4 }, rnd)
			assert(#offers == 3)
			local seen = {}
			for _, o in offers do
				local key = o.kind .. ":" .. o.id
				assert(not seen[key], "duplicate offer " .. key)
				seen[key] = true
			end
		end
	end,

	["a banished weapon never comes back"] = function()
		local rnd = lcg(3)
		for _ = 1, 200 do
			local offers = levelUp({ weapons = { Sword = 1 }, tomes = {}, banished = { ["weapon:Axe"] = true }, luck = 0, weaponSlots = 4, tomeSlots = 4 }, rnd)
			for _, o in offers do
				assert(not (o.kind == "weapon" and o.id == "Axe"), "banished Axe was offered")
			end
		end
	end,

	["full weapon slots stop new weapons being offered"] = function()
		local rnd = lcg(11)
		local loadout = { weapons = { Sword = 1, Axe = 1, Bone = 1, FireStaff = 1 }, tomes = {}, banished = {}, luck = 0, weaponSlots = 4, tomeSlots = 4 }
		for _ = 1, 200 do
			for _, o in levelUp(loadout, rnd) do
				assert(not (o.kind == "weapon" and o.isNew), "offered a fifth weapon: " .. o.id)
			end
		end
	end,

	["a new pick is marked New and an upgrade carries stat lines"] = function()
		local rnd = lcg(5)
		for _ = 1, 100 do
			for _, o in levelUp({ weapons = { Sword = 3 }, tomes = { Damage = 2 }, banished = {}, luck = 0, weaponSlots = 4, tomeSlots = 4 }, rnd) do
				if o.isNew then
					assert(o.rarity == "New" and o.level == 1)
				else
					assert(o.rarity ~= "New" and #o.lines >= 1, "an upgrade must change something")
					assert(o.level == (if o.kind == "weapon" then 4 else 3))
				end
			end
		end
	end,

	["a three-item offer never repeats an item"] = function()
		local rnd = lcg(9)
		for _ = 1, 100 do
			local ids = Offers.items(Roster.ItemOrder, Roster.Items, Roster.ItemRarityOrder, Roster.ItemRarityWeights, {}, 0, 3, nil, rnd)
			assert(#ids == 3 and ids[1] ~= ids[2] and ids[2] ~= ids[3] and ids[1] ~= ids[3])
		end
	end,

	["the vendor can be forced to Legendary stock"] = function()
		local ids = Offers.items(Roster.ItemOrder, Roster.Items, Roster.ItemRarityOrder, Roster.ItemRarityWeights, {}, 0, 3, "Legendary", lcg(1))
		for _, id in ids do
			assert(Roster.Items[id].rarity == "Legendary")
		end
	end,

	["a shrine offers three different boosts"] = function()
		local picks = Offers.shrine(Roster.ShrineBoosts, Roster.RarityOrder, Roster.RarityWeights, Roster.RarityLuckFactor, Roster.RarityMultiplier, 0, 0, 3, lcg(2))
		assert(#picks == 3 and picks[1].index ~= picks[2].index and picks[2].index ~= picks[3].index)
		for _, p in picks do
			assert(Roster.Stats[Roster.ShrineBoosts[p.index].stat] ~= nil, "shrine boosts an unknown stat")
		end
	end,

	["the grid finds a neighbour and ignores a stranger"] = function()
		local g = Grid.new(12)
		Grid.insert(g, 1, 5, 5)
		Grid.insert(g, 2, 300, -200)
		local out = {}
		local n = Grid.query(g, 0, 0, 10, out)
		assert(n == 1 and out[1] == 1)
		Grid.clear(g)
		table.clear(out)
		assert(Grid.query(g, 0, 0, 10, out) == 0, "a cleared grid must be empty")
	end,

	["the grid works across the negative axis"] = function()
		local g = Grid.new(12)
		Grid.insert(g, 7, -1, -1)
		local out = {}
		assert(Grid.query(g, 1, 1, 4, out) == 1, "an enemy just across x=0 must still be found")
	end,

	["the map stays between the floor and the wall"] = function()
		for _, h in map.heights do
			assert(h >= 2 and h <= GameConfig.WallHeight + 0.01, "height out of range: " .. h)
		end
	end,

	["the spawn clearing is nearly flat"] = function()
		assert(MapGen.slopeAt(map, 0, 0) < 0.15, "spawn slope " .. MapGen.slopeAt(map, 0, 0))
		assert(MapGen.slopeAt(map, 20, -15) < 0.2)
	end,

	["the plateau is high, and reachable only by going round"] = function()
		local top = MapGen.heightAt(map, 0, 240)
		assert(top > 35, "plateau top is " .. top)
		assert(MapGen.isReachable(map, reach, 0, 240), "the plateau must be reachable on foot (the ramps)")
		-- straight up its southern face is a cliff
		assert(not MapGen.canStep(map, 0, 152, 0, 160, GameConfig.CliffSlope), "the south face of the plateau should block enemies")
	end,

	["nothing walks out through the boundary wall"] = function()
		assert(not MapGen.canStep(map, 328, 0, 340, 0, GameConfig.CliffSlope))
		assert(not MapGen.isReachable(map, reach, 356, 0))
	end,

	["every anchor can be walked to from spawn"] = function()
		assert(#anchors >= 150, "only " .. #anchors .. " anchors")
		for _, a in anchors do
			assert(MapGen.isReachable(map, reach, a.x, a.z), `anchor at {a.x}, {a.z} is cut off`)
		end
	end,

	["the forest is dressed but the spawn clearing is left open"] = function()
		assert(#props >= 400, "only " .. #props .. " props")
		for _, prop in props do
			assert(prop.x * prop.x + prop.z * prop.z >= 42 * 42, "a prop sits in the spawn clearing")
		end
	end,

	["an enemy cannot walk into a tree but can still walk out of one"] = function()
		local tree
		for _, prop in props do
			if prop.radius > 0 then
				tree = prop
				break
			end
		end
		assert(tree, "no solid prop to test")
		assert(not MapGen.canStep(map, tree.x + tree.radius + 6, tree.z, tree.x, tree.z, 99), "walked into a solid prop")
		assert(MapGen.canStep(map, tree.x, tree.z, tree.x + 1, tree.z, 99), "stuck inside a solid prop")
	end,

	["there is somewhere far enough away to hide the boss portal"] = function()
		local far, near60, near120 = 0, 0, 0
		for _, a in anchors do
			if a.d >= GameConfig.BossPortalMinDistance then
				far += 1
			end
			if a.d <= 60 then
				near60 += 1
			end
			if a.d <= 120 then
				near120 += 1
			end
		end
		assert(far >= 5, "need 5 portal sites beyond 220 studs, got " .. far)
		assert(near60 >= 1 and near120 >= 4, "need tutorial sites near spawn")
	end,

	["a snapshot survives the wire to within its precision"] = function()
		local half = GameConfig.MapSizeStuds / 2
		local b = Snapshot.encode(3, { 1, 40, 349 }, { -359.5, 0.25, 123.456 }, { 359.5, -77.7, 0 }, half, 12.5)
		local slots, xs, zs = {}, {}, {}
		local count, time = Snapshot.decode(b, half, slots, xs, zs)
		assert(count == 3 and time == 12.5)
		assert(slots[1] == 1 and slots[2] == 40 and slots[3] == 349)
		local eps = Snapshot.precision(half)
		assert(math.abs(xs[3] - 123.456) <= eps and math.abs(zs[2] + 77.7) <= eps)
		assert(eps < 0.02, "position error should be under a fiftieth of a stud")
	end,

	["350 enemies fit in a small packet"] = function()
		local slots, xs, zs = {}, {}, {}
		for i = 1, 350 do
			slots[i], xs[i], zs[i] = i, 0, 0
		end
		local b = Snapshot.encode(350, slots, xs, zs, 360, 0)
		assert(buffer.len(b) <= 2200, "snapshot is " .. buffer.len(b) .. " bytes")
	end,
}

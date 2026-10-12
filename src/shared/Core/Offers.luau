--!strict
-- Offers - what a level-up, a chest, a shrine or the vendor puts in front of a
-- player. Pure: roster tables and the random source are passed in.

local Offers = {}

export type Line = { stat: string, amount: number }
export type Offer = {
	kind: string, -- "weapon" | "tome"
	id: string,
	isNew: boolean,
	rarity: string, -- a rarity name, or "New"
	level: number, -- the level the pick would bring it to
	lines: { Line },
}
export type Loadout = {
	weapons: { [string]: number }, -- id -> level
	tomes: { [string]: number },
	banished: { [string]: boolean }, -- "weapon:Id" / "tome:Id" / "item:Id"
	luck: number,
	weaponSlots: number,
	tomeSlots: number,
}

local function count(t: { [string]: number }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

--- Pick a rarity. Luck multiplies every weight above Common by (1 + luck * factor).
function Offers.rollRarity(
	order: { string },
	weights: { [string]: number },
	luckFactor: { [string]: number }?,
	luck: number,
	r: number
): string
	local total = 0
	local scaled: { number } = table.create(#order)
	for i, name in order do
		local factor = if luckFactor then (luckFactor[name] or 0) else (i - 1)
		local w = weights[name] * (1 + math.max(luck, 0) * factor)
		scaled[i] = w
		total += w
	end
	local pick = r * total
	for i, name in order do
		pick -= scaled[i]
		if pick < 0 then
			return name
		end
	end
	return order[#order]
end

-- sorted keys, so a given random sequence always produces the same offers
local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

--- Build up to `n` distinct level-up offers for a loadout.
function Offers.levelUp(
	loadout: Loadout,
	weaponOrder: { string },
	weapons: { [string]: any },
	tomeOrder: { string },
	tomes: { [string]: any },
	rarityOrder: { string },
	rarityWeights: { [string]: number },
	rarityLuck: { [string]: number },
	rarityMult: { [string]: number },
	n: number,
	rnd: () -> number
): { Offer }
	local candidates: { { kind: string, id: string, isNew: boolean, weight: number } } = {}
	local weaponFull = count(loadout.weapons) >= loadout.weaponSlots
	local tomeFull = count(loadout.tomes) >= loadout.tomeSlots

	for _, id in weaponOrder do
		if loadout.banished["weapon:" .. id] then
			continue
		end
		if loadout.weapons[id] then
			table.insert(candidates, { kind = "weapon", id = id, isNew = false, weight = 3 })
		elseif not weaponFull then
			table.insert(candidates, { kind = "weapon", id = id, isNew = true, weight = 1.4 })
		end
	end
	for _, id in tomeOrder do
		if loadout.banished["tome:" .. id] then
			continue
		end
		if loadout.tomes[id] then
			table.insert(candidates, { kind = "tome", id = id, isNew = false, weight = 2.5 })
		elseif not tomeFull then
			table.insert(candidates, { kind = "tome", id = id, isNew = true, weight = 1 })
		end
	end

	local out: { Offer } = {}
	while #out < n and #candidates > 0 do
		local total = 0
		for _, c in candidates do
			total += c.weight
		end
		local pick = rnd() * total
		local index = #candidates
		for i, c in candidates do
			pick -= c.weight
			if pick < 0 then
				index = i
				break
			end
		end
		local c = table.remove(candidates, index) :: any

		local offer: Offer = { kind = c.kind, id = c.id, isNew = c.isNew, rarity = "New", level = 1, lines = {} }
		if c.kind == "weapon" then
			local def = weapons[c.id]
			if c.isNew then
				offer.level = 1
			else
				offer.level = loadout.weapons[c.id] + 1
				offer.rarity = Offers.rollRarity(rarityOrder, rarityWeights, rarityLuck, loadout.luck, rnd())
				local mult = rarityMult[offer.rarity] or 1
				local keys = sortedKeys(def.pool)
				local lineCount = math.min(#keys, if rnd() < 0.5 then 2 else 1)
				for _ = 1, lineCount do
					local key = table.remove(keys, math.floor(rnd() * #keys) + 1) :: string
					table.insert(offer.lines, { stat = key, amount = def.pool[key] * mult })
				end
			end
		else
			local def = tomes[c.id]
			if c.isNew then
				offer.level = 1
				table.insert(offer.lines, { stat = def.stat, amount = def.perLevel })
			else
				offer.level = loadout.tomes[c.id] + 1
				offer.rarity = Offers.rollRarity(rarityOrder, rarityWeights, rarityLuck, loadout.luck, rnd())
				local mult = if def.noRarity then 1 else (rarityMult[offer.rarity] or 1)
				if def.noRarity then
					offer.rarity = "Common"
				end
				table.insert(offer.lines, { stat = def.stat, amount = def.perLevel * mult })
			end
		end
		table.insert(out, offer)
	end
	return out
end

--- Pick `n` distinct item ids, each from a rarity rolled with luck.
function Offers.items(
	itemOrder: { string },
	items: { [string]: any },
	rarityOrder: { string },
	rarityWeights: { [string]: number },
	banished: { [string]: boolean },
	luck: number,
	n: number,
	forceRarity: string?,
	rnd: () -> number
): { string }
	local out: { string } = {}
	local taken: { [string]: boolean } = {}
	for _ = 1, n do
		local rarity = forceRarity or Offers.rollRarity(rarityOrder, rarityWeights, nil, luck, rnd())
		local pool = {}
		for _, id in itemOrder do
			if items[id].rarity == rarity and not taken[id] and not banished["item:" .. id] then
				table.insert(pool, id)
			end
		end
		if #pool == 0 then
			-- nothing left at that rarity: fall back to anything not taken
			for _, id in itemOrder do
				if not taken[id] and not banished["item:" .. id] then
					table.insert(pool, id)
				end
			end
		end
		if #pool == 0 then
			break
		end
		local id = pool[math.floor(rnd() * #pool) + 1]
		taken[id] = true
		table.insert(out, id)
	end
	return out
end

--- Pick `n` distinct charge-shrine boosts, each with a rolled rarity.
function Offers.shrine(
	boosts: { any },
	rarityOrder: { string },
	rarityWeights: { [string]: number },
	rarityLuck: { [string]: number },
	rarityMult: { [string]: number },
	luck: number,
	bonus: number,
	n: number,
	rnd: () -> number
): { { index: number, rarity: string, amount: number } }
	local indices = {}
	for i = 1, #boosts do
		indices[i] = i
	end
	local out = {}
	for _ = 1, math.min(n, #indices) do
		local index = table.remove(indices, math.floor(rnd() * #indices) + 1) :: number
		local rarity = Offers.rollRarity(rarityOrder, rarityWeights, rarityLuck, luck, rnd())
		local amount = boosts[index].amount * (rarityMult[rarity] or 1) * (1 + bonus)
		table.insert(out, { index = index, rarity = rarity, amount = amount })
	end
	return out
end

return Offers

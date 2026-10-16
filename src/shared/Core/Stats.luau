--!strict
-- Stats - resolve a player's final stat block from its sources.
--
-- Everything is additive on the stat's default: a hero's base deltas, the hero
-- passive (amount per level), and one running `bonus` table that tomes, items
-- and shrine boosts all add into, then held inside each stat's `min` and `max`.
-- Pure: the stat definitions are passed in.

local Stats = {}

export type StatDef = { name: string, default: number, fmt: string, hidden: boolean?, min: number?, max: number? }
export type Block = { [string]: number }

--- A fresh block holding every stat's default.
function Stats.defaults(defs: { [string]: StatDef }): Block
	local out: Block = {}
	for key, def in defs do
		out[key] = def.default
	end
	return out
end

--- Final stats for a hero at `level` with the accumulated `bonus` deltas.
function Stats.compute(
	defs: { [string]: StatDef },
	heroBase: Block?,
	passiveStat: string?,
	passivePerLevel: number?,
	level: number,
	bonus: Block?
): Block
	local out = Stats.defaults(defs)
	if heroBase then
		for key, delta in heroBase do
			out[key] = (out[key] or 0) + delta
		end
	end
	if passiveStat and passivePerLevel then
		out[passiveStat] = (out[passiveStat] or 0) + passivePerLevel * math.max(level - 1, 0)
	end
	if bonus then
		for key, delta in bonus do
			out[key] = (out[key] or 0) + delta
		end
	end
	for key, def in defs do
		local v = out[key]
		if def.max and v > def.max then
			out[key] = def.max
		elseif def.min and v < def.min then
			out[key] = def.min
		end
	end
	return out
end

--- Add `delta` into a bonus table in place.
function Stats.add(bonus: Block, key: string, delta: number)
	bonus[key] = (bonus[key] or 0) + delta
end

local function trim(n: number): string
	local s = string.format("%.2f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

--- How a value reads in the stats panel.
function Stats.format(fmt: string, value: number): string
	if fmt == "pct" then
		return trim(value * 100) .. "%"
	elseif fmt == "mult" then
		return trim(value) .. "x"
	end
	return trim(value)
end

return Stats

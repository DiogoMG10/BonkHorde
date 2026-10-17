--!strict
-- Pacing - the horde's rhythm (M4.B). Pure.
--
-- After a calm opening the horde breathes in a cycle: it builds, surges (a pack
-- arrives at once, from one side or several), ebbs, then lulls long enough to
-- open a chest or charge a shrine. The cycle's average is about the old steady
-- rate, so a run is no harder overall; the pressure comes in spikes instead.

local Pacing = {}

export type Cycle = { build: number, surge: number, ebb: number, lull: number }
export type Rates = { calm: number, buildFrom: number, buildTo: number, surge: number, ebb: number, lull: number }

local function length(cycle: Cycle): number
	return cycle.build + cycle.surge + cycle.ebb + cycle.lull
end

--- Where `seconds` falls in the rhythm: the phase ("calm", "build", "surge",
--- "ebb", "lull"), the spawn rate's multiplier there, the cycle's number (0 in
--- the calm, then 1, 2, ...) and how far into the phase it is.
function Pacing.phase(seconds: number, calm: number, cycle: Cycle, rates: Rates): (string, number, number, number)
	if seconds < calm then
		return "calm", rates.calm, 0, seconds
	end
	local into = seconds - calm
	local total = length(cycle)
	local index = 1 + math.floor(into / total)
	local p = into - (index - 1) * total
	if p < cycle.build then
		local s = p / cycle.build
		return "build", rates.buildFrom + (rates.buildTo - rates.buildFrom) * s, index, p
	end
	p -= cycle.build
	if p < cycle.surge then
		return "surge", rates.surge, index, p
	end
	p -= cycle.surge
	if p < cycle.ebb then
		return "ebb", rates.ebb, index, p
	end
	return "lull", rates.lull, index, p - cycle.ebb
end

--- The clock time the next surge starts at, from `seconds` (itself if a surge
--- starts exactly then).
function Pacing.nextSurge(seconds: number, calm: number, cycle: Cycle): number
	local total = length(cycle)
	local first = calm + cycle.build
	if seconds <= first then
		return first
	end
	return first + math.ceil((seconds - first) / total) * total
end

--- The average rate multiplier over one cycle.
function Pacing.average(cycle: Cycle, rates: Rates): number
	local sum = cycle.build * (rates.buildFrom + rates.buildTo) / 2
		+ cycle.surge * rates.surge
		+ cycle.ebb * rates.ebb
		+ cycle.lull * rates.lull
	return sum / length(cycle)
end

export type Group = { type: string, n: number, side: number?, depth: number?, spread: number? }
export type Pack = { id: string, name: string, from: number?, to: number?, overtime: boolean?, hint: string?, groups: { Group } }

--- The packs that may come at `seconds` (in overtime only the overtime ones).
function Pacing.packsAt(packs: { Pack }, seconds: number, overtime: boolean): { Pack }
	local out = {}
	for _, pack in packs do
		if (pack.overtime == true) == overtime and seconds >= (pack.from or 0) and seconds < (pack.to or math.huge) then
			table.insert(out, pack)
		end
	end
	return out
end

--- Which pack comes next: one not seen yet first (the newest, so each kind of
--- spike is introduced on its own), else any but the last one, by `roll` in [0, 1).
function Pacing.pick(eligible: { Pack }, seen: { [string]: boolean }, last: string?, roll: number): Pack?
	for i = #eligible, 1, -1 do
		if not seen[eligible[i].id] then
			return eligible[i]
		end
	end
	local pool = {}
	for _, pack in eligible do
		if pack.id ~= last then
			table.insert(pool, pack)
		end
	end
	if #pool == 0 then
		pool = eligible
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.clamp(1 + math.floor(roll * #pool), 1, #pool)]
end

--- How many of a group come: more each cycle (to a ceiling) and more with
--- every extra player.
function Pacing.count(n: number, cycleIndex: number, players: number, growth: number, growthMax: number, perPlayer: number): number
	local k = math.min(1 + growth * math.max(cycleIndex - 1, 0), growthMax) * (1 + perPlayer * math.max(players - 1, 0))
	return math.max(1, math.floor(n * k + 0.5))
end

return Pacing

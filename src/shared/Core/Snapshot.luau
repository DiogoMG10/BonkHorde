--!strict
-- Snapshot - the wire format for the horde. The server packs every living
-- enemy's slot and x/z into a buffer ten times a second; clients unpack it and
-- interpolate. Height is not sent: both sides compute it from the map. Pure.

local Snapshot = {}

local BYTES_PER_ENEMY = 6
local HEADER = 6 -- u16 count, f32 server time

local function quantise(v: number, half: number): number
	local t = (v + half) / (2 * half)
	return math.clamp(math.floor(t * 65535 + 0.5), 0, 65535)
end

local function restore(q: number, half: number): number
	return q / 65535 * (2 * half) - half
end

--- Pack `count` enemies. slots/xs/zs are parallel arrays indexed 1..count.
function Snapshot.encode(count: number, slots: { number }, xs: { number }, zs: { number }, half: number, time: number): buffer
	local b = buffer.create(HEADER + count * BYTES_PER_ENEMY)
	buffer.writeu16(b, 0, count)
	buffer.writef32(b, 2, time)
	local o = HEADER
	for i = 1, count do
		buffer.writeu16(b, o, slots[i])
		buffer.writeu16(b, o + 2, quantise(xs[i], half))
		buffer.writeu16(b, o + 4, quantise(zs[i], half))
		o += BYTES_PER_ENEMY
	end
	return b
end

--- Unpack into the three arrays (cleared first). Returns count and server time.
function Snapshot.decode(b: buffer, half: number, slots: { number }, xs: { number }, zs: { number }): (number, number)
	local count = buffer.readu16(b, 0)
	local time = buffer.readf32(b, 2)
	table.clear(slots)
	table.clear(xs)
	table.clear(zs)
	local o = HEADER
	for i = 1, count do
		slots[i] = buffer.readu16(b, o)
		xs[i] = restore(buffer.readu16(b, o + 2), half)
		zs[i] = restore(buffer.readu16(b, o + 4), half)
		o += BYTES_PER_ENEMY
	end
	return count, time
end

--- Worst-case position error in studs for a map of this half-size.
function Snapshot.precision(half: number): number
	return (2 * half) / 65535
end

return Snapshot

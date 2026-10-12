--!strict
-- Grid - a spatial hash over x/z so "who is near this point" does not mean
-- walking every enemy. Rebuilt every simulation tick. Pure.

local Grid = {}

export type Grid = {
	cell: number,
	cells: { [number]: { number } },
	pool: { { number } },
}

local OFFSET = 512 -- keeps cell coordinates positive for the key
local STRIDE = 2048

function Grid.new(cellSize: number): Grid
	return { cell = cellSize, cells = {}, pool = {} }
end

--- Empty the grid, keeping its tables for reuse.
function Grid.clear(g: Grid)
	for key, list in g.cells do
		table.clear(list)
		table.insert(g.pool, list)
		g.cells[key] = nil
	end
end

local function keyOf(g: Grid, x: number, z: number): number
	local cx = math.floor(x / g.cell) + OFFSET
	local cz = math.floor(z / g.cell) + OFFSET
	return cx * STRIDE + cz
end

function Grid.insert(g: Grid, id: number, x: number, z: number)
	local key = keyOf(g, x, z)
	local list = g.cells[key]
	if not list then
		list = table.remove(g.pool) or {}
		g.cells[key] = list
	end
	table.insert(list, id)
end

--- Append to `out` every id whose cell overlaps the circle (x, z, r).
--- This is the broad phase: the caller still checks the exact distance.
--- Returns the new length of `out`.
function Grid.query(g: Grid, x: number, z: number, r: number, out: { number }): number
	local n = #out
	local cell = g.cell
	local x0 = math.floor((x - r) / cell) + OFFSET
	local x1 = math.floor((x + r) / cell) + OFFSET
	local z0 = math.floor((z - r) / cell) + OFFSET
	local z1 = math.floor((z + r) / cell) + OFFSET
	for cx = x0, x1 do
		local row = cx * STRIDE
		for cz = z0, z1 do
			local list = g.cells[row + cz]
			if list then
				for i = 1, #list do
					n += 1
					out[n] = list[i]
				end
			end
		end
	end
	return n
end

return Grid

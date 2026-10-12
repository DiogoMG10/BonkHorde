--!strict
-- RunState - the phases a run moves through, and which moves are legal.
-- The server is the only thing that changes phase; this module is the rule it
-- checks against, so an illegal jump is a refused call rather than a bug. Pure.

local RunState = {}

RunState.Lobby = "Lobby"
RunState.Intro = "Intro"
RunState.Playing = "Playing"
RunState.Overtime = "Overtime"
RunState.Victory = "Victory"
RunState.Wipe = "Wipe"
RunState.Results = "Results"

local ALLOWED: { [string]: { [string]: boolean } } = {
	Lobby = { Intro = true },
	Intro = { Playing = true, Lobby = true },
	Playing = { Overtime = true, Victory = true, Wipe = true, Lobby = true },
	Overtime = { Victory = true, Wipe = true, Lobby = true },
	Victory = { Results = true },
	Wipe = { Results = true },
	Results = { Lobby = true },
}

function RunState.canMove(from: string, to: string): boolean
	local row = ALLOWED[from]
	return row ~= nil and row[to] == true
end

--- Is the horde being simulated in this phase?
function RunState.isLive(phase: string): boolean
	return phase == RunState.Playing or phase == RunState.Overtime
end

--- The quest lines for the tracker, as { text, done } pairs.
function RunState.quests(portalFound: boolean, bossSummoned: boolean, bossDead: boolean): { { text: string, done: boolean } }
	if not bossSummoned then
		return { { text = "Find the Boss Portal", done = portalFound } }
	end
	local out = {
		{ text = "Find the Boss Portal", done = true },
		{ text = "Defeat the Boss", done = bossDead },
	}
	if bossDead then
		table.insert(out, { text = "Enter the Portal", done = false })
	end
	return out
end

return RunState

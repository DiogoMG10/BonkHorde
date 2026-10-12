--!strict
-- GameConfig - every tunable in the game, in one place.
--
-- A number that a designer might want to change must live here, never inline in
-- a Service or Controller. This is what makes a balance pass a data edit.

export type Config = {
	RespawnSeconds: number,
	MaxPlayers: number,
}

local GameConfig: Config = {
	RespawnSeconds = 3,
	MaxPlayers = 4,
}

return GameConfig

--!strict
-- ProtoGate - decides which map profile a server runs. Pure.
--
-- The Wardwood prototype must never switch on in the shared BonkHorde place or
-- in a published game. It needs ALL of:
--   1. an explicit marker in the place (ServerStorage.<MarkerName> = MarkerValue),
--      which only the arm snippet in tools/proto creates;
--   2. Roblox Studio;
--   3. an unpublished local file (PlaceId 0 and GameId 0);
--   4. a place id that is not the live place's.
-- Anything else falls back to the normal map. A marker found where the other
-- checks fail is reported, so a misplaced marker is visible rather than silent.

local ProtoGate = {}

export type Env = {
	studio: boolean,
	placeId: number,
	gameId: number,
	marker: string?, -- the marker's value, nil when there is no marker
}

export type Rules = {
	MarkerValue: string,
	LivePlaceId: number,
}

ProtoGate.Default = "MossyWoods"
ProtoGate.Prototype = "Wardwood"

--- Returns the profile name and a one-line reason.
function ProtoGate.decide(env: Env, rules: Rules): (string, string)
	if env.marker == nil then
		return ProtoGate.Default, "no prototype marker"
	end
	if env.marker ~= rules.MarkerValue then
		return ProtoGate.Default, `refused: unknown marker value "{env.marker}"`
	end
	if not env.studio then
		return ProtoGate.Default, "refused: not running in Studio"
	end
	if env.placeId == rules.LivePlaceId then
		return ProtoGate.Default, "refused: this is the live BonkHorde place"
	end
	if env.placeId ~= 0 or env.gameId ~= 0 then
		return ProtoGate.Default, `refused: place {env.placeId} / game {env.gameId} is published, not a local file`
	end
	return ProtoGate.Prototype, "armed local Studio file"
end

return ProtoGate

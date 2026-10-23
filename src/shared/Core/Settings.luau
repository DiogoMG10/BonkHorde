--!strict
-- Settings - the player preferences kept in the profile (DataService): what
-- may be stored, and how a change from the client is folded in. Pure, so the
-- specs can check it headless.
--
--   master, music, sfx   volumes, 0..1 (two decimals)
--   outlines             enemy outlines on or off (OverlayController's toggle)
--   numbers              damage numbers on or off (the same)
--
-- A key the player never set is simply absent: the client falls back to its
-- default. A message that carries only some keys changes only those, so
-- saving the volumes can never reset a toggle, or the other way round.

local Settings = {}

local VOLUMES = { "master", "music", "sfx" }
local FLAGS = { "outlines", "numbers" }

--- Only known keys of the right type, volumes clamped: a forged message
--- stores nothing odd.
function Settings.clean(raw: unknown): { [string]: any }
	local out = {}
	if typeof(raw) == "table" then
		for _, key in VOLUMES do
			local value = (raw :: any)[key]
			if typeof(value) == "number" and value == value then
				out[key] = math.floor(math.clamp(value, 0, 1) * 100 + 0.5) / 100
			end
		end
		for _, key in FLAGS do
			local value = (raw :: any)[key]
			if typeof(value) == "boolean" then
				out[key] = value
			end
		end
	end
	return out
end

--- The saved settings with a client's change folded in: the keys it sends
--- replace theirs, every other key keeps its saved value.
function Settings.merge(saved: { [string]: any }?, raw: unknown): { [string]: any }
	local out = table.clone(Settings.clean(saved))
	for key, value in Settings.clean(raw) do
		out[key] = value
	end
	return out
end

return Settings

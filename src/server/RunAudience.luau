--!nonstrict
-- RunAudience - who hears the run (T6). One server holds the island hub and at
-- most one Wardwood run; only the party in that run may receive its phase,
-- clock, horde, pickups, effects, banners and results. Every run service sends
-- through `fire` instead of FireAllClients, so a player waiting on the island
-- never gets a single run message.
--
-- RunDirectorService sets the members when a run starts and clears them when
-- the party is back on the island. A member who leaves the server is simply
-- skipped.

local Players = game:GetService("Players")

local RunAudience = {}

local members: { Player } = {}

function RunAudience.set(list: { Player })
	members = table.clone(list)
end

function RunAudience.clear()
	members = {}
end

function RunAudience.has(player: Player): boolean
	return table.find(members, player) ~= nil
end

--- The run's players still in the server.
function RunAudience.list(): { Player }
	local out = {}
	for _, player in members do
		if player.Parent == Players then
			table.insert(out, player)
		end
	end
	return out
end

--- Send to every player in the run, nobody else.
function RunAudience.fire(remote: RemoteEvent, ...: any)
	for _, player in members do
		if player.Parent == Players then
			remote:FireClient(player, ...)
		end
	end
end

return RunAudience

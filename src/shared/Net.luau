--!strict
-- Net - the ONLY networking transport for gameplay and cross-client paths.
--
-- Knit's auto-generated remotes are deliberately NOT used here. When play-mode
-- introspection is unreachable, the most primitive debuggable transport wins:
-- one folder of plain RemoteEvents, created server-side, awaited client-side,
-- every name declared in this file and nowhere else.
--
-- Server: Net.server("EventName") -> RemoteEvent (creates on first use)
-- Client: Net.client("EventName") -> RemoteEvent? (nil on timeout - callers
--         must fail inert, never error)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "BonkHordeNet"
local CLIENT_WAIT_TIMEOUT = 10

-- Every remote in the game is declared here. A name not on this list is a bug.
-- S>C = server to client, C>S = client to server. Payload shapes are documented
-- at the sending site and must match at all three ends (sender, relay, receiver).
export type EventName =
	-- lobby and profile
	"Roster" -- S>C all: { players = { { userId, name, hero, ready, host } }, map }
	| "Profile" -- S>C owner: { silver, unlocked, runs, best, canSave, settings }
	| "PickHero" -- C>S: heroId
	| "PickMap" -- C>S: mapId (host only)
	| "SetReady" -- C>S: boolean
	| "UnlockHero" -- C>S: heroId
	| "Settings" -- C>S: { master, music, sfx } volumes 0..1, kept in the profile
	-- run state
	| "Phase" -- S>C all: { phase, clock, tier, paused, kills, quests, map }
	| "Clock" -- S>C all: clock seconds, tier, paused, kills
	| "Banner" -- S>C all: text, style
	| "Toast" -- S>C one/all: title, text
	| "Results" -- S>C all: results table
	| "Pause" -- S>C all: { mode, by, byName, votes, ready = { userId }, need, seconds, resuming, cooldown }
	| "PauseAsk" -- C>S: action ("request" | "accept" | "withdraw" | "resume")
	-- player state
	| "PlayerState" -- S>C owner: full run state for the HUD and panels
	| "Squad" -- S>C all: { { userId, hp, maxHp, shield, maxShield, downed, level } }
	| "XP" -- S>C all: level, xp, need
	| "Hurt" -- S>C owner: amount, dodged, shieldBroke, hpLost
	-- choices
	| "Offers" -- S>C owner: { id, kind, offers, seconds, charges }
	| "ChooseOffer" -- C>S: id, action ("pick" | "skip" | "banish" | "refresh"), index
	| "Panel" -- S>C owner: { id, kind, ... } chest / shrine / shop / statue
	| "PanelChoice" -- C>S: id, action, index
	-- the horde
	| "EnemySpawn" -- S>C all: buffer of (u16 slot, u8 type, u8 flags)
	| "EnemySnap" -- S>C all: Snapshot buffer
	| "EnemyGone" -- S>C all: buffer of (u16 slot, u8 reason)
	| "Hits" -- S>C all: buffer of (u16 slot, u16 damage, u8 flags)
	| "Boss" -- S>C all: { { slot, name, hp, maxHp, kind } }
	| "Telegraph" -- S>C all: x, z, radius, delay, kind
	-- weapons and world
	| "Fx" -- S>C all: name, ...
	| "Proj" -- S>C all: op ("spawn" | "turn" | "end"), id, ...
	| "PickupSpawn" -- S>C all: buffer of (u16 id, u8 kind, u8 value, u16 x, u16 z)
	| "PickupTaken" -- S>C all: buffer of (u16 id, u8 playerIndex)
	| "Interactables" -- S>C all: full list for this run
	| "InteractableState" -- S>C all: id, state, data
	| "Interact" -- C>S: interactable id
	| "PrimaryInput" -- C>S: held (boolean), yaw, pitch (radians). A state, not a request per attack

local Net = {}

local function serverFolder(): Folder
	assert(RunService:IsServer(), "Net.server is server-only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

--- Server side: get (or create) the RemoteEvent for `name`.
function Net.server(name: EventName): RemoteEvent
	local folder = serverFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

--- Client side: wait for the RemoteEvent for `name`. Returns nil rather than
--- erroring, so a missing remote degrades one feature instead of the client.
function Net.client(name: EventName): RemoteEvent?
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_WAIT_TIMEOUT)
	if not folder then
		warn(`[Net] no {FOLDER_NAME} folder after {CLIENT_WAIT_TIMEOUT}s`)
		return nil
	end
	local remote = folder:WaitForChild(name, CLIENT_WAIT_TIMEOUT)
	if not remote or not remote:IsA("RemoteEvent") then
		warn(`[Net] remote {name} never arrived`)
		return nil
	end
	return remote
end

--- Every declared name, so the server can create all remotes up front and a
--- client never waits on one that a late service has not made yet.
Net.All = {
	"Roster",
	"Profile",
	"PickHero",
	"PickMap",
	"SetReady",
	"UnlockHero",
	"Settings",
	"Phase",
	"Clock",
	"Banner",
	"Toast",
	"Results",
	"Pause",
	"PauseAsk",
	"PlayerState",
	"Squad",
	"XP",
	"Hurt",
	"Offers",
	"ChooseOffer",
	"Panel",
	"PanelChoice",
	"EnemySpawn",
	"EnemySnap",
	"EnemyGone",
	"Hits",
	"Boss",
	"Telegraph",
	"Fx",
	"Proj",
	"PickupSpawn",
	"PickupTaken",
	"Interactables",
	"InteractableState",
	"Interact",
	"PrimaryInput",
} :: { EventName }

return Net

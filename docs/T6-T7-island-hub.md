# T6 + T7 Skyhold: island hub, parties and isolated runs

Branch `feat/t6-t7-island-hub`. Direction approved by Tiago on 2026-10-21; this file is the
record of those answers and of the plan.

## Approved direction

- **Skyhold**, a stylized floating island in a warm golden afternoon: moss greens and natural
  stone, a teal portal, soft clouds and floating islets. A distinctive Portal Plaza, Hall of
  Heroes and scenic viewpoints, and space kept for future features (scenery only, never fake
  buttons). Original, combining the four references (Skyloft, Sky Surge, the island portal,
  Sky) and continuous with Wardwood's art.
- **Blender** (4.5.14 LTS, the line the M3.B kit was built with) is the primary tool for the
  island's custom geometry and architecture, through the M3.B pipeline, with editable sources
  kept. Roblox does terrain, lighting, VFX, collisions and gameplay. No permanent uploads.
- **Heroes:** players walk the hub as their selected hero. Choosing another at a plinth
  updates the character in place, with normal movement and camera. The last pick is
  remembered in the profile.
- **Parties:** rune circles, up to 3 per squad. Joining and leaving are deliberate interactions
  (E / gamepad X / touch); walking across a circle changes nothing. Membership, leader and
  READY are clearly visible. Direct invitations later.
- **Starting:** the leader starts preparation, every member confirms READY, then a short
  visible countdown activates the portal. Someone leaving or unreadying cancels it safely.

## Local vertical slice (this milestone)

- One server holds the hub and the Wardwood, far apart, with at most one Wardwood run at a
  time. Only the party enters it.
- Players in the hub receive no run UI, world state or gameplay events: run traffic goes to
  the run's members only, and sky, lighting and sounds are applied per player.
- Joiners always arrive in the hub; nobody drops into a running run. A ready party waits
  while another run is on, and the portal says so.
- After the results the party comes back to the hub together, still formed.
- Multiplayer gameplay, rewards and progression are unchanged.

## Production transition (not built in this milestone)

- A public Hub place and a Run place reached only through reserved servers, both built from
  this codebase. Which existing place becomes the hub is not decided.
- The hub server teleports a ready party with `TeleportService:TeleportAsync` and
  `TeleportOptions.ShouldReserveServer = true`, putting the party, heroes and run settings
  in `SetTeleportData`. Calls are wrapped in `pcall` with retries, and `TeleportInitFailed`
  is handled (wait when Flooded, retry on Failure). `ReserveServer`, `TeleportPartyAsync` and
  `TeleportToPrivateServer` are deprecated.
- The run server reads `Player:GetJoinData()` and re-checks it against the saved profile,
  because teleport data is visible to the client. After the results it teleports the party
  back to the hub together. Place access: "Secure within universe only".
- **Profile concurrency risk:** DataService loads with `GetAsync` and saves with `SetAsync`,
  with no session lock. When a player moves between servers, a load can happen before the
  previous server's save lands, and the stale copy then overwrites newer progress (for
  example a hero unlocked just before teleporting). Before teleports go live: save and
  confirm before teleporting, and load under a session lock (`UpdateAsync` with a lock and
  version, or a proven profile library).
- TeleportService cannot be play-tested in Studio. It needs a published test experience,
  which is a separate authorisation.
- Later: Roblox parties (`Player.PartyId`, `SocialService:GetPlayersByPartyId`) to put
  friends who arrive together in one circle; direct invites.

## Plan

1. Hub characters: spawn on the island dressed as the hero, re-dress in place, last hero.
2. Run isolation: a run audience for every run broadcast, per-player look, hub and run
   modes on the client, return to the hub.
3. Rune circles: party rules in `Core/HubParty`, prompts, circle visuals, nameplates.
4. Hall of Heroes: plinths, camera focus, hero card.
5. Skyhold art: island plan, Blender kit (`tools/art/skyhold.py`,
   `assets/art/skyhold_kit.blend`), terrain, lighting, VFX.
6. Specs, gates, Studio checks, playtest checklist.

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

## What is built

**The island.** Skyhold floats at `Config/Skyhold.Origin`, far from the Wardwood. Its
ground is Roblox Terrain written from `Core/SkyholdGen` (rim, terraces, paths; native
grass like the Wardwood's). Spawn on the meadow facing north, a lantern-lit way up under
bunting to the round Portal Plaza, the Skygate on its dais between two crystal obelisks
with rune monoliths circling it, four rune circles before it, the Hall of Heroes on the
west terrace, the Elder on the east knoll with benches over the clouds, a lookout with a
telescope in the south-west, a trophy wall with empty niches in the north-east, the
market islet over a rope bridge (stalls closed until there is something to sell),
floating isles, a waterfall off the east cliff, a sea of clouds below and a far peak.
An invisible wall follows the rim; anyone who still falls is put back on the meadow.
The ground under the kit's paving (plaza, dais, stairs, hall terrace: `Config/Skyhold.Paving`)
is bare earth, so Roblox's grass blades do not grow through it.

**Server.**
- `RunAudience`: every run broadcast goes to the run's party only (it replaced every
  `FireAllClients` in the run services).
- `PartyService` (rules in `Core/HubParty`): the server's players with stable indices and
  their hero; parties at the circles; `Launch` when a countdown ends and the run is free.
- `HubService`: builds the island once the Wardwood is down (`Skyhold/Builder`), gives
  each player an island character dressed as their hero (`HeroDress`, welded from the
  rig's rest pose), re-dresses it in place, catches falls, and returns a party from its run
  at the portal.
- `RunDirectorService`: `StartRun(players, circle)`; no late joins; the run's sky is drawn
  per run and sent to its party (`Phase.sky`); `RunEnded` hands the party back.
- `DataService`: remembers `lastHero`.

**Client.** `HubController` (circle glow and slots, the party boards, prompts, party card,
nameplates, portal state, the white crossing), `HeroHallController` (statues, plinth
prompts, the hero card, the borrowed camera shot), `HubDecorController` (clouds, far
scenery, the orbiting monoliths), `SkyController` (each player's own sky and, on the
island, its own grass tint). The camera follows the hero on the island with the mouse free
for the hub's buttons (right button held turns it; the Wardwood keeps its locked aim); the
canopy fader also ghosts the island's trees and banners in its way; slides read the
island's slopes; the old 2D menus are gone.

**Art pipeline (Blender is the source).**

    lune run tools/art/skyhold_plan.luau            # the island's plan, from the game's own code
    "$BLENDER" -b -P tools/art/skyhold.py -- [--render DIR] [--no-glb]
    "$BLENDER" -b assets/art/skyhold_kit.blend -P tools/art/skyhold.py -- --from-blend

`skyhold_land.py` (the island's rock hung from the Terrain's rim: strata, moss, vines,
crystals; isles, clouds, far peak, falls) and `skyhold_props.py` (portal, plaza, circles,
plinths, hall, ruins, lanterns, braziers, stalls, bridge, bunting, banners, flowers...)
build with bmesh and modifiers (bevel, Voronoi displacement, decimate, voxel remesh,
boolean, solidify), bake ambient occlusion into vertex colours and export packed meshes
(`src/server/Skyhold/Meshes`), the layout (`Skyhold/Layout`), the client scenery
(`Config/SkyholdDecor`), GLBs and `assets/art/skyhold_manifest.json`. The `.blend` keeps
every asset under "Kit" and the island under "Layout": move a piece there and export with
`--from-blend`. The server bakes the meshes at start (EditableMesh, vertex colours
included); nothing is uploaded. A Blender render shows shape and palette only.

**Dev commands** (Workspace attribute `BonkDev`, Studio only): `solo` (straight into a
solo run), `island` (back to the meadow), `party` (circles and run state), `sky <name>` /
`sky off` (every client's sky).

## Validation (2026-10-22)

- **Offline:** the four gates; specs for the party rules (`HubParty`), the island's ground
  (`Skyhold`, paving included) and the exported kit (`SkyholdKit`).
- **Run in Studio by Claude** (Studio MCP, Tiago's unpublished local place, one player):
  the island builds with no errors (341 kit pieces); spawn on the meadow as the saved hero;
  hero card, CHOOSE and back, re-dressed in place twice; solo start, countdown, the run
  under its own sky, results, CONTINUE, back out of the portal with the party kept; a lone
  squad's BEGIN, CALL IT OFF and LEAVE; walking across a circle joins nothing; a fall off
  the rim lands on the meadow. The look was tuned there (golden light, clouds, cliffs).
- **Fixed in that pass:** grass through the paving; the camera inside a banner; a
  re-dress killed the character (the hero's "Head" part became the humanoid's head); the
  mouse was locked on the island, so the party card and MENU could not be clicked.
- **Run in Studio by Claude, multiplayer (2026-10-23):** a local server test started with
  `StudioTestService:ExecuteMultiplayerTestAsync` (two simulated players, two more added
  mid-test with `AddPlayers`; one machine, so no real latency), each window driven through
  the Studio MCP with real key presses and clicks where timing allowed, and a recorder on
  each client logging every run message it received:
  - OPEN SQUAD with F at circle I, JOIN with E, BEGIN with E, READY with E: the squad's
    countdown and both players into one Wardwood run together;
  - NOT READY during the countdown: back to preparing, no run; LEAVE (the card's button)
    during preparation: the squad forming again with the leader alone; the leader leaving:
    the lead passes to the other member;
  - a second party (solo) while a run was on: "The portal is in use: you go next", then its
    short countdown and its run as soon as the first party pressed CONTINUE;
  - the player left on Skyhold during another's run received no run message at all (not
    even the half-second clock), kept the island's light (ClockTime 16.9, brightness 3.1)
    and the menu music while the runner had the forest's; a player joining mid-run arrived
    on the island and heard nothing of the run either;
  - in a squad run: per-player level-up choices (the XP strip's rainbow followed each
    player's own choice), the co-op pause (REQUEST PAUSE, P to agree, PAUSED, READY 1/2 and
    2/2, the 3-2-1), the end-of-run vote (1/2, 2/2, back to Skyhold together, squad kept),
    and a player disconnecting mid-run (the run went on for the other, the party dropped
    them, the team panel emptied).
- **Fixed in the multiplayer pass:** the run HUD blinked off for a moment as every run left
  its intro (no PlayerState reached the client before play began: it is now sent during the
  intro); a READY leader's nameplate was cut off ("leads circle I · READY"). Added
  `god all` (every hero in the run) for co-op playtests.
- **Not validated yet (needs people):** all of the above with real players and real
  latency, phone and gamepad, and the feel of it.

## Limits of this milestone

- Locally one Wardwood run per server: a second ready party waits for the portal.
- A player who disconnects mid-run comes back to the island, not to the run.
- The kit's meshes are rebuilt at every server start (like the Wardwood's); a published
  game should use uploaded meshes, which is a separate authorisation.
- Reserved run servers are designed above, not built; nothing about teleports is tested.

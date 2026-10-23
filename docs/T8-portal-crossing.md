# T8 The portal crossing: Skyhold to the Wardwood and back

On the T6/T7 line (`feat/t6-t7-island-hub`, `bonk-0.25.0-t8`), since the crossing depends on
Skyhold. Direction from the 2026-10-22 brief: the existing portal as the centrepiece, its teal
energy surging, a short departure and a brief arrival, about two to three seconds, the party
going through together, nothing for the players left on the island but what the island itself
shows. After the first playtest (`bonk-0.26.3-ux`) each cover of light waits for the world
behind it, so the Wardwood (and the island, coming home) is never seen being built.

## What happens

- **The portal** (everyone on Skyhold): its face is a vortex now, not a flat disc: a deep well,
  three swirls turning against each other, a bright core and a cream rim of light, motes drawn
  in from the ring, a teal light on the plaza. It idles, sleeps (cool and slow) while the run is
  in use, and surges through any party's countdown: the swirls speed up, the core and the light
  grow, the ring's runes, the obelisks' crystals, the plaza's inlay and the orbiting stones'
  glyphs brighten, and the stones speed up and draw in. When a party goes through, a burst of
  light, and a portal sound heard from the plaza.
- **Departure** (the last 1.3 s of the party's countdown): the party is held still; each
  member's camera swings in behind their hero to frame the portal and widens; the heroes glow
  mint and turn to light, which the rest of the island also sees; a hum rises; the light
  blooms out of the portal and fills the screen over the last 0.55 s (`portal_open`).
- **Arrival** (the run's intro): in the light until the Wardwood behind it is ready (below),
  the camera already waiting where it will drop in from; then the light clears in 0.85 s while
  the camera drops in from above and behind over 1.25 s; every member takes shape over a
  spinning swirl of light on the ground with a ring and a burst (`portal_enter`, as before);
  controls back 0.9 s in. The intro's stage title sits higher, above the hero stepping out.
- **Home** (back from the results): in the light until the island round the portal is ready,
  then out of it onto the plaza with the same swirl and burst, the light clearing in 0.9 s;
  the portal flares for everyone on the island.
- **Called off** (NOT READY, CALL IT OFF, LEAVE, a member leaving the server, the portal busy
  after all): controls, camera, heroes and light go back as they were.

## Waiting for the world (readiness)

The light (and the loading screen on joining, `docs/T6-T7-island-hub.md`) is a cover: it
stays up until the client can see that the place behind it is ready, for a short minimum and
never past a maximum (`Core/Crossing.step`, gates in `Config/Skyhold.Crossing`):

1. **hero**: the hero stands where the server set them down (the character's `PlacedAt`
   attribute, written right after the server places it, in the Wardwood or on the island).
2. **world**: streaming is not pausing the player (`Player.GameplayPaused`) and the ground
   round them is there: rays straight down at points on rings 18, 55 and 130 studs out, where
   the client's own plan says there is ground (Core/MapGen, Core/SkyholdGen), all near and 85%
   far, counting only the terrain and the island's own parts (`client/WorldProbe`).
3. **detail**, waited for a while at most: in the Wardwood every prop's art drawn round the
   hero (ArtController.Prepare swaps up to 400 a frame under the light instead of 60 a tick)
   and the rest of the party set down; on the island the portal's vortex lit again.
4. **steady**: a moment more for the first frames of the new place.

| Cover | min | steady | detail at most | max |
|---|---|---|---|---|
| arrive (into the Wardwood) | 0.45 s | 0.15 s | 2.5 s | 8 s |
| home (back on Skyhold) | 0.35 s | 0.15 s | 2 s | 8 s |
| join (the loading screen) | 0.6 s | 0.25 s | 6 s | 40 s |

Each lift prints one line, for example `[PortalController] the Wardwood shown after 0.92s
(hero 0.34  world 0.30  steady 0.26)`. While a cover is up Roblox's own "gameplay paused"
notice is off (the cover says it better), and attacks and USE are refused
(PrimaryController, WorldController) for as long as the controls are held. If the run ends
before the hero is seen, the arrival simply stops.

## Where it lives

| File | What |
|---|---|
| `src/client/Controllers/PortalController.luau` | the portal's vortex and surge, the departure, arrival and way home, the readiness of each cover |
| `src/shared/Core/Crossing.luau` | the curves (charge, departure, arrival, home) and the gate (`wait`, `step`); specs in `tests/Crossing.spec.luau` |
| `src/client/WorldProbe.luau` | is the ground round a point streamed in yet |
| `src/shared/Config/Skyhold.luau` | `Crossing` timings, `PortalSpin` |
| `src/client/ControlLock.luau` | holds the hero still with a deadline; MovementController keeps them standing |
| `CameraController:SetCrossing` | the crossing leans the camera towards its own framing |
| `src/client/Vfx.luau` | `PortalSurge`, `PortalDepart`, `PortalArrive`, `PortalMotes`, `DepartMotes` |

The run starts exactly as before (PartyService, RunDirectorService); the server only marks
where it set each hero down (`PlacedAt`).
Every effect is pcall-isolated and every hold on the controls lets go on its own. On the lowest
graphics settings the vortex drops a swirl and its motes. Studio only:
`Workspace:SetAttribute("BonkCrossingSlow", 4)` plays the arrival and the way home four times
slower, to look at them.

## Validation (2026-10-23)

- **Offline:** the four gates; `Crossing.spec` (timings stay between two and three seconds,
  the charge, the departure and arrival curves).
- **Run in Studio by Claude:** solo (a disposable place built from disk): the vortex idle and
  surging, the departure, the arrival (slowed and at full speed), the way home, the controls
  held 1.3 s before the countdown ends until 0.85 s into the arrival and back after it, no
  errors. Local multiplayer test (three simulated players): a squad's two members through
  together with the same timings, the watcher on the plaza seeing them glow and turn to light
  with no light, lock or camera change of their own; NOT READY during the departure putting
  both members' controls, camera and heroes back within a frame or two.
- **Fixed on the way:** the departure's surge burst flew into the camera on the way home (the
  camera stands near the portal there); stars of the arrival burst could reach the camera; a
  frame of the empty Skyhold view showed between the end of a run and the light; party
  members' nameplates overlapped (they now stack).
- **Not validated by people:** the feel and the timing, phones (the camera's framing), gamepad,
  low graphics settings, real latency.

## Validation of the readiness pass (2026-10-23, `bonk-0.26.3-ux`)

- **Offline:** the four gates; `Crossing.spec` (the gate waits for the hero, then the world,
  then the detail; a minimum and a steady moment; detail given up, the rest only at the
  maximum; a fact going missing starts the steady moment over).
- **Run in Studio by Claude (solo, 1593x752):** recorded every frame at the end of the frame:
  under full light the hero was set down, the camera moved to its drop-in place and all
  1,345 art models were drawn before the light cleared; the Wardwood shown 0.7 to 1.2 s after
  the run started (waiting up to 0.43 s for its ground to stream in), home 0.36 to 0.55 s
  after the hero left; the frame where the Wardwood hero vanishes is already full light.
  With 0.5 s of replication lag (Studio's network setting): the arrival waited 1.03 s for the
  ground, home 0.84 s, both under full light. Five runs in a row without a lock or light left
  behind.
- **Local multiplayer test (two simulated players):** a squad through together (shown after
  0.80 and 0.93 s, the second waiting for its mate to land), home together after the co-op
  CONTINUE vote; NOT READY with 0.78 s left (held, then released) and with 0.33 s left (the
  light at 0.3 to 0.4 unwinding to nothing in 0.5 s, controls back at once) on both clients.
- **Not validated by people:** the new pacing, real networks, phones, gamepad.

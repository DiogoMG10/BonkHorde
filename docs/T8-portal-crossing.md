# T8 The portal crossing: Skyhold to the Wardwood and back

On the T6/T7 line (`feat/t6-t7-island-hub`, `bonk-0.25.0-t8`), since the crossing depends on
Skyhold. Direction from the 2026-10-22 brief: the existing portal as the centrepiece, its teal
energy surging, a short departure and a brief arrival, about two to three seconds, the party
going through together, nothing for the players left on the island but what the island itself
shows.

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
  blooms out of the portal and fills the screen over the last 0.45 s (`portal_open`).
- **Arrival** (the run's intro): in the light until this player's Wardwood hero is there (1.6 s
  at most), then the light clears in 0.7 s while the camera drops in from above and behind
  over 1.15 s; every member takes shape over a spinning swirl of light on the ground with a
  ring and a burst (`portal_enter`, as before); controls back 0.85 s in. The intro's stage
  title now sits higher, above the hero stepping out.
- **Home** (back from the results): in the light until the island hero stands at the portal,
  then out of it onto the plaza with the same swirl and burst, the light clearing in 0.8 s;
  the portal flares for everyone on the island.
- **Called off** (NOT READY, CALL IT OFF, LEAVE, a member leaving the server, the portal busy
  after all): controls, camera, heroes and light go back as they were.

## Where it lives

| File | What |
|---|---|
| `src/client/Controllers/PortalController.luau` | the portal's vortex and surge, the departure, arrival and way home |
| `src/shared/Core/Crossing.luau` | the curves (charge, departure, arrival, home); specs in `tests/Crossing.spec.luau` |
| `src/shared/Config/Skyhold.luau` | `Crossing` timings, `PortalSpin` |
| `src/client/ControlLock.luau` | holds the hero still with a deadline; MovementController keeps them standing |
| `CameraController:SetCrossing` | the crossing leans the camera towards its own framing |
| `src/client/Vfx.luau` | `PortalSurge`, `PortalDepart`, `PortalArrive`, `PortalMotes`, `DepartMotes` |

The server is unchanged: the run starts exactly as before (PartyService, RunDirectorService).
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

# T8 The crossing: Skyhold to the Wardwood and back, through the ground

On the T6/T7 line (`feat/t6-t7-island-hub`). The first version (`bonk-0.25.0-t8`) took the
party through Skyhold's standing portal in a flash of light; after the playtest it was too
fast, had no anticipation, and the Wardwood could still be seen loading. The brief of
2026-10-24 (Diogo) replaced it with this concept, built in `bonk-0.27.0-t8`:

**Skyhold → a portal opens on the ground under the party → five-second countdown → the
heroes sink into it → black → the Wardwood ready → a portal opens on the ground → the
heroes rise out of it → it closes → the run begins.** Home again the same way, shorter.

## What happens

- **Countdown (5 s, solo or squad):** the moment the party is ready, a portal opens on the
  ground of its rune circle (0.9 s) and grows stronger to the end: a soft teal pool of light,
  a dark well, three swirls turning against each other over a bright core, a gold rim, a teal
  outer ring with twelve runes orbiting between them, motes rising, a teal light on whoever
  stands in it. Skyhold's standing portal surges with it. The members see a big 5, 4, 3, 2, 1
  at the top centre, each landing with a pulse and a soft tick, and hear a rising hum. They
  can still move; anyone off the portal is asked "Step into the portal". Everyone on the
  island sees the portal.
- **Departure (1.6 s, committed):** at zero the server holds the party still (anchored) and
  sets anyone off the portal down just inside it; READY can no longer be taken back.
  Everyone on the island sees the heroes rise a little, then sink into the portal (their
  nameplates hidden), rays of light shooting up from its rim, the standing portal flaring;
  the portal closes after them. For the party: controls held, the camera eases (0.6 s) to a
  close shot of them in the portal, turned at most 50° from where it looked, the standing
  portal behind them; the screen fades to black from 0.5 s to 1.3 s; the run takes them
  at 1.6 s, under full black.
- **Arrival:** black until this client's Wardwood is ready (below), then until the server
  says every member's client is (a synced reveal). Under the black a portal is already open
  at the spawn and every hero is held under it, the camera at its arrival shot. Then the
  black clears (0.5 s) while every member rises out of the one portal together (from 0.12 s,
  eased, a small hop at the top, risen at 1.07 s), the portal closes after them (0.45 s), the
  camera hands back to the hero's own (by 1.55 s); controls back at 1.15 s, when the server
  starts the run. The stage title and letterbox show over it. A member set down late rises on
  their own.
- **Home (from CONTINUE):** black while the run lets go and the plaza round the hero streams
  in, then the black clears (0.35 s) as the party rises out of a portal at the plaza's return
  spot; controls back at 0.9 s. Everyone else on the island sees them rise there.
- **Called off** (NOT READY, CALL IT OFF, LEAVE during the countdown, a member leaving the
  server before it ends): the portal collapses (0.45 s), the countdown goes, nothing is held.
  A member leaving the server during the departure just drops out; the rest go on. If the
  run could not start after all, the party stands up out of the portal again.

A party size picks the portal: one hero 5.2 studs; a party (they start 3.5 studs apart
round the spawn) 6.7 studs; a rune circle's portal 6.5 studs, which holds a squad of three.

## How heroes sink and rise (client/Sink)

The character is never moved. While a hero is lowered, each client hides their character
(`LocalTransparencyModifier`) and draws a stand-in of its visible pieces (the hero model and
the weapon) that follows the real pieces every frame, so the hero keeps animating, only
lower. The ground hides what is under it. The root, the Humanoid, the joints and the
physics are untouched, so nothing can fall, take damage or desync, and it works the same
for every client and for both rig kinds: the avatars here use Roblox's newer
`AnimationConstraint` joints, whose `C0` cannot be moved and whose limbs follow their owner's
physics, so moving a root joint was not an option.

## The Wardwood is never seen being built

The black is a cover that stays up until the client can see the place behind it is ready,
for a short minimum and never past a maximum (`Core/Crossing.step`, gates in
`Config/Skyhold.Crossing`):

1. **hero**: the hero stands where the server set them down (`PlacedAt`).
2. **world**: streaming is not pausing the player and the ground round them is there (rays
   on rings 18, 55 and 130 studs out, `client/WorldProbe`).
3. **detail**, waited for a while at most: every prop's art drawn round the hero (all at
   once under the cover, `ArtController.Prepare`), the rest of the party set down, the
   arrival's portal built. On the island: the standing portal lit.
4. **steady**: a moment more for the first frames.
5. **the party** (the Wardwood only): the client tells the server (`CrossingReady`, with the
   run's number); the server reveals to everyone once all members still here have, or after
   `revealMax` (12 s). A client whose own cover is still up waits for it before showing.

| Cover | min | steady | detail at most | max |
|---|---|---|---|---|
| arrive (into the Wardwood) | 0.45 s | 0.15 s | 2.5 s | 8 s |
| home (back on Skyhold) | 0.35 s | 0.15 s | 2 s | 8 s |
| join (the loading screen) | 0.6 s | 0.25 s | 6 s | 40 s |

After 2.5 s of black a quiet line appears ("Opening the way...", "Waiting for your
party...", "Back to Skyhold..."). Each lift prints one line, for example
`[PortalController] the Wardwood shown after 1.15s (hero 0.34  world 0.29  steady 0.37
party 0.13)`, and the server `[RunDirectorService] the party is shown the Wardwood 1.16s
after the run started`.

## The run starts when the controls come back

The run's intro has no fixed length any more (`GameConfig.IntroSeconds` is gone): the stage
clock does not run and nothing spawns or attacks during it. It lasts until the reveal plus
the rise's `release` (1.15 s), then `Playing`; held attack input is released at that moment.
Clients only decide when the party is shown, never anything about rewards. The run's number
and an unrevealed intro go out with the intro's first message, so a client never acts on the
last run's reveal.

## Where it lives

| File | What |
|---|---|
| `src/client/Controllers/PortalController.luau` | the standing portal, every ground portal on the island, the party's departure, the arrival and the way home, the covers and their readiness |
| `src/client/GroundPortal.luau` | the portal on the ground (one SurfaceGui card, a light, motes and rays) |
| `src/client/Sink.luau` | heroes drawn under the ground (stand-ins) |
| `src/shared/Core/Crossing.luau` | the curves (`charge`, `gather`, `descent`, `emerge`) and the gate; specs in `tests/Crossing.spec.luau` |
| `src/shared/Core/HubParty.luau` | the committed `departing` phase between the countdown and the run; specs in `tests/HubParty.spec.luau` |
| `src/server/Services/PartyService.luau` | holds a departing party still, inside its portal |
| `src/server/Services/RunDirectorService.luau` | the intro's synced reveal, then `Playing` |
| `src/client/Controllers/HubController.luau` | the countdown's numbers and nudge; nameplates hidden while under |
| `src/shared/Config/Skyhold.luau` | `Crossing` timings, portal sizes, gates; `CountdownSeconds` 5, `SoloCountdownSeconds` 5, `ResumeCountdownSeconds` 3 |

Every effect is pcall-isolated; every hold on the controls lets go on its own; if the
controller ever breaks, it shows everything and stands every hero up. On the lowest
graphics settings the portals drop a swirl, the runes' flicker and the motes. Studio only:
`Workspace:SetAttribute("BonkCrossingSlow", 3)` (set on the server) plays the departure,
the arrival and the way home three times slower on every screen, the server waiting with
them.

## Validation (2026-10-24, `bonk-0.27.0-t8`)

- **Offline:** the four gates; `Crossing.spec` (five-second countdowns, the descent and the
  rise within 1 to 2 s, black before the world changes, the rise mostly seen after the black
  clears, ends exactly where the hero stands, the portal sized for its group, the gates) and
  `HubParty.spec` (departing is committed, a member leaving the server drops out, a departing
  party holds the portal, a failed start stands the party up).
- **Run in Studio by Claude**, a disposable place built from disk, 1593x752:
  - solo, recorded every frame at the end of the frame: countdown 5 to 1; at zero the server
    anchors, the lift and the sink to 7.4 studs, black 0.5 to 1.3 s; the run under full
    black; the Wardwood shown 1.1 to 1.2 s after the run started; the black clears in 0.45 s
    while the hero rises (from 7.4 studs, a 0.27-stud hop, exactly back); controls back;
    three runs in a row and home each time (shown 0.5 s after), nothing left held, dark,
    anchored, hidden or drawn; screenshots slowed x3 of the countdown, the descent, the rise
    and the way home;
  - CALL IT OFF during the countdown: the portal collapses, controls back at once;
  - wandering off the portal: "Step into the portal", set down 4.4 studs from the centre at
    zero;
  - 0.5 s of replication lag: the Wardwood shown after 3.2 s (1.36 s for the ground, 1.13 s
    for the reveal), the quiet line after 2.5 s; the forest's art round the hero complete at
    the first lifted frame (96 parts within 120 studs, as many 3 s later);
  - iPhone 16 Pro simulator: the countdown readable beside the party card.
- **Local multiplayer test by Claude** (three simulated players): a squad of two sinking
  together, both clients revealed together and both heroes rising in sync, controls back on
  both; the third player on the plaza saw them sink and later rise at the return spot, with
  no black, camera change or hold of their own; NOT READY at 3 s: countdown and portal gone on
  all three, nobody held; a member disconnected mid-descent: the other went on alone.
- **Not validated by people:** the feel and the pacing, real networks, gamepad, low
  graphics settings, Roblox's own top-bar buttons over the XP strip (Studio's capture leaves
  them out).

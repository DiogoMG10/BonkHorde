# M1 Hybrid Combat: progress

Last updated 2026-10-13. Branch `m1-hybrid-combat`, build stamp `bonk-0.3.0-m1b`.

Approved scope so far: **M1.A** (gameplay clock) and **M1.B** (manual Sword for Sir Clonk
only). M1.C (Fire Staff, Frost Ring), M1.D (Auto-Trigger) and M1.E are **not started** and
wait for Tiago and Diogo's playtest of the Sword.

## State

| Stage | Code | Offline checks | Studio | Human playtest |
|---|---|---|---|---|
| M1.A gameplay clock | done | pass | **not run** | n/a |
| M1.B manual Sword | done | pass | **not run** | **pending** |

**Nothing in M1 has run in Roblox Studio yet.** The session that wrote it had no Studio
connection, and pushing to the place needs the developers' approval and a backup first.
Everything below marked "offline" was checked with `lune run test`, `selene src`,
`stylua --check src lune` and `rojo build` only.

## M1.A: gameplay clock

Simulation timestamps came from `os.clock()`, which keeps running through a level-up pause.
A boss strike telegraphed before a pause came due during it and landed on the first tick
after; freezes, poison, frenzy, lingering zones and invulnerability ran out.

- `src/shared/Core/SimClock.luau`: gameplay time that only moves when the director steps a
  tick. Never reset, so a stamp from an earlier run is always in the past.
- `RunDirectorService` owns it, passes it to every `Step`, and exposes `Now()`.
- Stamps taken outside the tick now use `Now()`: the `Interact` remote, revive
  invulnerability, the boss summon, the exit countdown, the dev hooks.
- Left on real time on purpose: offer and panel deadlines, intro and results timers, the
  player-state send throttle (it must run while paused).
- `BossService:Resync` redraws the warning of every pending strike when a pause ends, with
  the gameplay time it has left. The warning sound plays again with it.
- Client projectiles stop moving while the run is paused.

Not changed: other client effects (slash crescents, bursts, the first telegraph ring) still
play out in real time during a pause.

## M1.B: manual Sword

**Rule:** the weapon in slot 1 is the hero's primary. For heroes listed in
`GameConfig.ManualPrimaryHeroes` (only `Knight` now) it waits for the attack button. It is a
matter of slot, not weapon type: a Sword picked up by another hero is an ordinary automatic
secondary, and Zib and Mint play exactly as before.

**Input.** `PrimaryController` sends `PrimaryInput(held, yaw)`: on press, on release, when
the aim turns more than 2 degrees (at most 15 a second) and at least every 0.4 s while held.
It is a state, not a request per attack. No position is sent.

**Server.** `CombatService` records the state. In `Step` the primary's cooldown counts down
and waits at zero; when it is ready and the button is held (or one click is remembered) it
calls the same `Fire.Arc` every automatic sword uses, with the player's direction. The pure
rules are in `src/shared/Core/PrimaryTrigger.luau`.

| Rule | Value | Where |
|---|---|---|
| A click during the cooldown is remembered for | 0.25 s of gameplay time, one click at most | `PrimaryClickBuffer` |
| A held button the client stops confirming is dropped after | 1 s | `PrimaryHeldTimeout` |
| Attack-button messages accepted | 20 a second per player; a release always passes | `PrimaryInputRate`, `PrimaryInputBurst` |
| Vertical reach of a primary melee swing | 9 studs above or below the hero's root | `PrimaryReachY` |

All four are provisional.

**Hold and click are cleared** when the hero is downed, when a pause begins, and when a
press arrives while downed, frozen, paused or outside a live phase. The client stops
reporting "held" when the window loses focus, a panel frees the mouse, the game pauses, the
hero is downed or the character is removed, and reports it again by itself when play
resumes with the button still down.

**Reach.** A hand-fired swing only hits an enemy whose body is within vertical reach and
with no ground between it and the hero (`MapGen.sightClear`, a line against the
heightfield). This is deliberately not `MapGen.canStep`: a face an enemy cannot climb does
not hide what stands on it.

**Direction.** The slash effect is drawn along the direction the server used. The swing
animation turns the upper body towards it (up to 100 degrees either side) and back; the
hero itself is not rotated and keeps facing the way it runs. A ground marker at the hero's
feet shows the aim.

## Offline results (2026-10-13)

| Check | Result |
|---|---|
| `lune run test` | 79 passed, 0 failed (45 before M1; 4 clock specs, 30 primary specs) |
| `selene src` | 0 errors, 0 warnings |
| `stylua --check src lune` | clean |
| `rojo build` | builds |

What the new specs establish, on the pure rules only:
- one click of any length, including shorter than a tick, is one attack;
- a click early in the cooldown is dropped; clicks never accumulate;
- holding for 10, 60 and 600 s fires within one attack of an automatic weapon's count;
- 100 clicks a second fires no more than holding;
- waiting with the weapon ready does not bank a second attack;
- non-boolean, non-number, NaN, infinite and absurd inputs are refused;
- a flood of presses is cut to the rate; a release still passes;
- a silent client's hold is dropped; a confirmed one is kept;
- vertical reach and the ground blocking a swing, on the real map's plateau, ramp and ridge.

Mutation check: breaking the click expiry, and breaking the ground test, each made specs fail.

## Not verified

- Anything in Studio: that the place boots on this build, that the remote reaches the
  server, that a click swings, that the pause fix holds in play.
- The server wiring itself (`CombatService` handler and `_stepPrimary`) has no offline test:
  it needs Knit and Roblox services.
- Whether the swing animation turns the correct way round. The sign was derived, not seen.
- Hit rate under latency. The swing starts from the server's view of the hero, which
  ProjetoTD measured 0.15 to 0.18 s behind the client. No compensation was added.
- Click-to-swing delay: the animation still starts when the server's effect arrives.
- Two clients. Performance before and after (no baseline was recorded).

## Known limitations

- Scenery props never block a hand-fired swing; only the terrain does.
- Secondaries, including a secondary Sword, ignore terrain entirely, as before.
- Item procs set off by a primary hit (Static Mitts, Volatile Meatball) still hit through
  terrain.
- A swing aimed more than 100 degrees from the way the hero runs is animated at the limit.
- A click made in the last moments of the intro is spent on the first tick of play.
- The aim marker follows the terrain, so it sits low when the hero stands on a prop.
- Mouse and keyboard only.

## Studio tests still to run (after backup and approved push)

Dev hooks are Studio-only: set the Workspace attribute `BonkDev`. `status` now also prints
`manual`, `held` and `swings`.

1. Output shows `BUILD bonk-0.3.0-m1b` on server and client.
2. Clock: `god`, `goto BossPortal`, `use BossPortal`, wait for a root warning, `level 1`
   while it shows. The strike must not land during the choice and must land a full warning
   after resuming, with the ring redrawn.
3. Click once: `swings` rises by 1. Hold 30 s: about 27 swings (1.1 s cooldown).
4. Spam clicks for 30 s: no more swings than holding.
5. Hold, then: release, Alt-Tab away, open the pause menu, level up, `hurt 9999`. After each,
   `held=false` within 1 s and `swings` stops.
6. From the command bar on the client, fire `PrimaryInput` with `("x", 1)`, `(true, 0/0)`,
   `(true, math.huge)` and 1000 presses in a loop: no error, no extra swings.
7. Studio network settings, incoming replication lag 0.1 and 0.2: still playable; note how
   often a swing that crosses an enemy on screen misses.
8. Zib and Mint: their weapons fire by themselves exactly as before.
9. Two clients: both see each other's slashes; one Knight, one Fox.
10. `spawn Skeleton 250`, then `status`: record `tickMs` and client frame time.

## Playtest checklist for Tiago and Diogo (Sir Clonk)

1. Does one click feel like one swing? Does holding feel steady?
2. Does aiming with the camera feel like control, or like work?
3. Running from a pack while looking back at it: does that feel right?
4. Did a swing ever visibly cross an enemy and not hit?
5. Does the swing start late after the click?
6. Does the body turn towards the swing, and does it look right when you swing sideways?
7. Is the ground marker enough to aim by? Too much?
8. Enemies on a ledge above or a drop below: is it fair that you cannot hit them?
9. Should the hero turn to face the attack?
10. Would you play another run like this?

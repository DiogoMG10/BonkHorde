# M1 Hybrid Combat: progress

Last updated 2026-10-15. M1.A and M1.B on `main`; M1.C and M1.D on branch
`m1c-d-primaries-autotrigger`, build stamp `bonk-0.4.1-m1d`. Roadmap: `docs/ROADMAP.md`.

Done: **M1.A** (gameplay clock), **M1.B** (manual Sword), **M1.C** (manual Fire Staff and Frost
Ring) and **M1.D** (Auto-Trigger item). M1.E is not started.

## State

| Stage | Code | Offline checks | Studio | Human playtest |
|---|---|---|---|---|
| M1.A gameplay clock | done | pass | boots and runs; **pause fix not tested** | n/a |
| M1.B manual Sword | done | pass | click and hold swing | **validated** by Tiago and Diogo |
| M1.C manual Fire Staff, Frost Ring | done | pass | playtested on `bonk-0.4.0-m1d` | **validated**; polish pass (below) not yet seen |
| M1.D Auto-Trigger | done | pass | playtested on `bonk-0.4.0-m1d` | **validated** |

In Studio, during the Rojo migration test on 2026-10-14 (`docs/ROJO-WORKFLOW.md`): server and
client printed `BUILD bonk-0.3.0-m1b`, a run started, Sword click and hold worked, no errors.
That covers Studio test 1 below and the basic part of test 3; the rest of that list, including
the clock test (2), has not been run. Tiago and Diogo then validated the Sword in Studio.
Everything below marked "offline" was checked with `lune run test`, `selene src`,
`stylua --check src lune` and `rojo build` only, and is left as written on 2026-10-13.

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

## M1.C: manual Fire Staff and Frost Ring

`ManualPrimaryHeroes` now lists all three heroes, so every hero's weapon in slot 1 uses the
M1.B input and cooldown rule unchanged. Secondaries stay automatic, whatever their type.

- **Zib, Fire Staff:** each attack throws the weapon's fireballs along the camera aim (extra
  projectiles fan out 0.35 rad either side). Damage, speed, range and the explosion are the
  automatic ones; a fireball that meets nothing explodes at the end of its range, as before.
- **Mint, Frost Ring:** each attack is one ring around the hero, with the automatic radius,
  damage and freeze. It ignores the aim, so no aim marker is drawn for it.
- **Sword slash effect:** the crescent's start angle moved 90 degrees (was drawn well left of
  the swing). Derived from the texture, not yet seen in Studio.

### Polish pass after the playtest (`bonk-0.4.1-m1d`, offline checks only)

The human playtest of `bonk-0.4.0-m1d` passed all three primaries and Auto-Trigger, and found
three game-feel issues:

- **Sword slash sat slightly right of the aim.** Measured rather than turned another 90
  degrees: the texture's mass is 37 degrees clockwise of its top, a Top-face SurfaceGui's top
  points 90 degrees left of the part's look (both reported directions fit only this), and the
  eased spin plus fade put what is seen 0.62 of the way through the spin. The old start angle
  put that average 8 degrees right; the new one (`sweep * 0.62 + 37 - 90`) puts it on the aim.
  The damage arc is unchanged.
- **Zib had no crosshair.** A small open cross (four ticks round a gap, pinpoint dot) at the
  screen centre while the Fire Staff is the primary, in its own ScreenGui (the Hud's UIScale
  would move a centred element). Sir Clonk keeps the ground marker; Mint shows nothing.
- **Fireballs flew flat.** The camera now looks from -75 to +45 degrees (was +25;
  `CameraPitchMin/Max`). The client sends `PrimaryInput(held, yaw, pitch)`; the server checks
  the pitch is a real number and clamps it to the same range. A hand-fired fireball starts at
  the camera's focus (hero root + `CameraHeight`) and flies along the camera's look, so its
  whole path lies under the crosshair. On the server it has a height: it bursts on the ground
  it meets, on a body it passes within 1.8 studs of (vertically too), or at the end of its
  range in the air, and its blast only hits bodies within the blast radius of that height.
  Damage, cooldown, range (70 studs, now along the 3D path), speed and radius are unchanged.
  Fan shots keep the same pitch.
- Explosion sounds: the audio handler read the wrong argument of the projectile `end`
  event, so fireball and rocket explosions were silent. Fixed.

## M1.D: Auto-Trigger

Rare item, `AutoTrigger` in `Roster.Items`, offered once (taking it banishes it from later
offers and chests). Icon is a placeholder (the Cooldown tome's).

- When the primary is ready and the button is idle, it fires by itself if something is in
  reach: Sword, the nearest enemy a hand swing could touch (same reach and ground rules);
  Fire Staff, any enemy within its range, aimed as the old automatic staff; Frost Ring, any
  enemy inside the ring.
- `PrimaryTrigger.step` asks the item only on a tick where the weapon is ready and the player
  is not attacking, so the button always comes first and both share one cooldown. With
  nothing in reach the weapon waits at zero and banks nothing.
- Dev hook `status` prints `auto=` (attacks fired by the item) next to `swings=` (by hand).
  `item AutoTrigger` grants it.

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

M1.C and M1.D (2026-10-15): `lune run test` 88 passed, 0 failed (9 new specs in
`tests/AutoTrigger.spec.luau`: the cadence for each hero's weapon held and automated, the
item never adds an attack or overrides the button, banks nothing when idle); `selene src`,
`stylua --check src lune`, `rojo build` clean. Server wiring and visuals are not covered.

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
- A hand-fired fireball leaves from just above the hero's head (the camera focus), not
  from the staff: that is what keeps it exactly on the crosshair.
- At the default camera pitch (-18 degrees) the crosshair, and so a fireball, meets flat
  ground about 20 studs ahead; aiming farther means looking up a little.
- Auto-Trigger's and a secondary Fire Staff's fireballs still fly flat along the ground and
  hit at any height, as before; only a hand-fired shot is 3D.
- Scenery props (trees, rocks) do not stop a fireball; only the terrain does.

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

## Quick playtest for the polish pass (`bonk-0.4.1-m1d`)

1. **Sir Clonk:** the slash crescent is centred on the aim marker (not left, not right).
2. **Zib:** the crosshair shows only for Zib, only while playing (not in menus or panels).
3. **Zib:** look up at an enemy on a ledge and fire: the fireball rises to it and explodes on
   it. Look down near your feet: it bursts on the ground there. Look at the sky: it bursts in
   the air at range and hurts nothing below.
4. **Zib:** a fireball travels through the crosshair the whole way; it hits what the
   crosshair was on.
5. Camera: looking up now goes further (to 45 degrees); nothing feels broken looking up.
6. Auto-Trigger and secondaries behave as before; explosions are now audible.

## Playtest checklist for M1.C and M1.D (all three heroes)

Set the Workspace attribute `BonkDev` for the `status` and `item` hooks. Output must show
`BUILD bonk-0.4.0-m1d`.

1. **Sir Clonk:** click once = one swing, hold = steady swings. Does the slash crescent now
   sit across the aim marker, not to its left?
2. **Zib:** click = one fireball (`swings` +1) along the aim marker; hold = one every 1.4 s.
   Spam-clicking is no faster than holding. Does aiming fireballs feel better than auto-aim?
3. **Mint:** click = one frost ring around the hero, enemies freeze/slow as before; hold =
   one every 1.6 s. No aim marker. Does a manual ring feel worth clicking?
4. For each hero, pick up a secondary (e.g. `weapon Sword` on Zib): it fires by itself.
5. **Auto-Trigger** (`item AutoTrigger`, or find it in a chest; it shows as Rare): standing
   idle, each hero attacks only when an enemy is in reach; `auto` rises, `swings` does not.
6. With Auto-Trigger, hold or spam-click: no faster attacks than without it, no double
   slashes/fireballs/rings in one moment; clicks aim where you look.
7. Sir Clonk with Auto-Trigger next to an enemy on a ledge he cannot reach: no swing.
8. Auto-Trigger never appears again in a chest or offer once taken.

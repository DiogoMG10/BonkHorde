# M4.B Horde & Pressure

The horde comes in waves of pressure instead of a steady stream. Branch
`feat/m4b-horde-pressure`, from `main` after M4.A. Same spawn director, roster, caps and
combat; only when and how enemies arrive changes.

## The rhythm

`Core/Pacing` (pure, specced), numbers in `GameConfig.Pace*`, run by `EnemyService:Direct`.

| Phase | Seconds | Spawn rate | Meant for |
|---|---|---|---|
| calm | the first 40 | x1 (as before) | an accessible start |
| build | 25 | x0.8 rising to x1.25 | pressure mounting |
| surge | 10 | x1.7, and a **pack** arrives | the spike |
| ebb | 6 | x0.6 | mopping up |
| lull | 14 | x0.3 | breathing room: chests, shrines, the shop |

The cycle (55 s) with its pack averages about the old steady rate, so a run is as dense
overall, but in spikes. The first surge comes at 1:05. Overtime keeps the rhythm, but its
ebb and lull stay at x0.75 or more. While a boss or a miniboss is up, the rhythm holds
at x1 and sends no pack: the boss is the spike. Caps, elites, overtime toughness,
runners and bosses are unchanged.

## Packs

One arrives as each surge starts (`Roster.Packs`): its groups gather on arcs about 66
studs from one hero and come in together, so the spike reads as an event. A short gold
banner names it (with a one-line hint the first time) and a horn sounds (a wail for
ghosts). Each new pack is introduced on its own the first time it unlocks, then they vary
(never the same twice in a row). Packs grow 5% a cycle (to x1.6) and 50% per extra
player.

| Pack | From | Make-up and shape |
|---|---|---|
| Goblin mob | 0:00 to 4:00 | 9 Runts from one side |
| Bruiser escort | 2:00 | 7 Runts in front screening 2 Bruisers |
| Slime swarm | 1:30 to 7:00 | 7 Slimes, 4 Runts ahead |
| Pincer | 3:00 | 2 Bruisers and 4 Runts on one side, 7 Slimes on the other |
| Bone line | 5:00 | 4 Shield Skeletons in a wide front, 7 Skeletons behind |
| Stampede | 5:00 | 5 Bruisers abreast, 5 Slimes on the flank |
| Surrounded | 7:00 | Golems, Skeletons and Slimes from three sides |
| Ghost tide | overtime | Ghosts from three sides |
| Shield wall | overtime | Shields in front, Ghosts behind, Golems at the back |

A sample stage: mob 1:05, escort 2:00, slimes 2:55, pincer 3:50, escort 4:45, stampede
5:40, bone line 6:35, (miniboss 7:30), escort 8:25, surrounded 9:20, then overtime packs.

## Attacks take turns

On any one hero, a charge cannot start within 0.7 s of another charge, a leap within
0.45 s of another leap, and no two special attacks start within 0.25 s of each other
(`Attacks.turn`, `stagger` in each attack). A pack of Bruisers winds up one after another,
each lane readable; the rest keep chasing until their turn. A specced queue of 5 Bruisers
and 6 Slimes all ready at once clears in under 5 s.

## Cost

Per tick: one phase lookup (a few divisions). Per surge (about once a minute): one pack
of 9 to 30 spawns with a few walkability checks each. Per attack start: two table
lookups. No per-enemy work was added to the tick, and no measurement showed a bottleneck
to optimise.

## Playtest

In `Workspace.BonkDev`: `surge` starts the next surge now, `surge escort` (or mob, slimes,
pincer, boneline, stampede, ring, ghosts, wall) with that pack; `pace` prints the phase and
the time to the next surge; `clock 300` jumps to the later packs. In Studio, Output logs
each phase change (`[Pace] 2:00 surge 2: Bruiser escort, 9 enemies x1.70`).

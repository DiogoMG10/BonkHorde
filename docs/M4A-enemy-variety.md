# M4.A Enemy variety and readability

Two regular enemies now ask for different answers, and three get Blender models that read
against the Wardwood's grass. Branch `feat/m4a-enemy-variety`, from `main` after M3.B.

## The attacks

Data in `Roster.Enemies.<Type>.attack`, rules in `Core/Attacks` (pure, specced), run by
`EnemyService` on the server: damage, timing and paths are the server's; clients only
draw them. Bosses, elites and overtime runners keep everything they had; an elite's
attack hits as its contact does (x1.5).

| | Goblin Bruiser: **charge** | Slime: **leap** |
|---|---|---|
| starts | 8-15 studs from its hero, every 4.5-7 s | 6-13 studs, every 3.5-5.5 s |
| windup | 0.85 s braced and still, its lane drawn on the ground (orange, filling) | 0.55 s squatting, the landing ring drawn (amber, filling) |
| the attack | 18 studs straight at where the hero stood, in 0.42 s, committed | an arc to where the hero stood (14 studs at most), 0.5 s, no steering |
| hits | heroes the lane passes over (1.5 studs + body), once each, x1.5 contact damage | heroes in the 3-stud splash when it lands, x1.4 contact damage |
| recover | 1.1 s winded, swaying, no contact damage: punish it | 0.6 s splattered flat |
| dodge | step sideways out of the lane | move, slide or jump out of the ring (a hero in the air is clear) |

Both paths are fixed when the windup starts and walked along the heightfield first, so a
charge or a leap never crosses a cliff or leaves the world. A freeze calls an attack off;
the gameplay clock drives it, so a pause holds it, and when a pause ends the windup's
telegraph is drawn again for the time it has left (`EnemyService:Resync`). Height overlap
(M2.D) applies to both: jumping over a charge or a landing avoids it. The `EnemyAct` event
(slot, code, end point, windup, duration) tells clients to draw the telegraph and play the
moves: the Bruiser leans back and trembles, runs leaning in, then sways; the Slime
squats, arcs 4.5 studs high, lands flat.

`tests/Attacks.spec.luau` checks the paths stay walkable and reach the hero's spot, and
that a walking hero (20 studs/s) can step out of the lane (0.85 s for 2.7 studs) and the
ring (1.05 s for 4.2 studs) with room to spare.

## Enemy models

`tools/art/enemies.py`, built with the rest of the kit (`"$BLENDER" -b -P tools/art/kit.py`)
into `assets/art/wardwood_kit.blend`, `assets/art/export/KitEnemy*.glb` and
`src/server/Wardwood/ArtMeshes/KitEnemy*.luau`; baked by the server at start, enemies
first, and used by `EnemyRenderController` when baked (else the old meshes):

| | Old | Kit | Read |
|---|---|---|---|
| Goblin Runt (fodder) | green, 1,498 tris, 6 parts | ochre skin, tall red drooping cap, big ears and eyes, brown tunic; 1,410 tris, 8 parts | small, a red point |
| Goblin Bruiser (charger) | green, 1,798 tris | dusky purple, iron helm and pauldrons, bone horns and tusks, glowing eyes, orange loincloth, huge fists; 1,694 tris, 10 parts | big, wide, horned |
| Slime (leaper) | lime green, 600 tris | magenta dome, big white eyes; 880 tris, 4 parts | a pink blob |

Every part is one colour (no textures, nothing uploaded); the limbs are the parts the
renderer already swings. Preview: `work/art/enemies_sheet.jpg`.

## Performance

Offline (estimates, not Studio):
- an attack starting costs ~2 microseconds (its path walk, Lune); running one is a few
  comparisons a tick
- the bench mix of 250 enemies: ~333k enemy triangles (was ~328k), 1,940 parts moved a
  frame (was 1,440: the kit models are split by colour)

In Studio, `bench 250` in `Workspace.BonkDev` spawns the early-run mix round the hero and
times 15 s: the server's enemy tick (mean and worst) and each client's frames (mean fps,
worst frame, the enemy drawing's own share), printed to Output. Run it once on `main` and
once here for the before and after; record the numbers below.

| Build | Where | Server tick mean / worst | Client fps / worst frame | Enemy drawing |
|---|---|---|---|---|
| (to measure in Studio) | | | | |

## Playtest

`pack` in `Workspace.BonkDev` drops 4 Goblin Bruisers, 8 Slimes and 10 Goblin Runts round
the hero; `spawn GoblinBruiser 6` or `spawn Slime 12` for one kind.

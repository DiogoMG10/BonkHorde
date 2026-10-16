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
| hits | heroes the lane passes over (1.8 studs + body), once each, x1.5 contact damage | heroes in the 3-stud splash when it lands, x1.4 contact damage |
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
first, and used by `EnemyRenderController` when baked (else the old meshes). Second pass
(`bonk-0.18.1-m4a`) after the references in `D:/Dev.2/Enemie References`: bigger, stronger
silhouettes, muted colours.

| | Height (hero 5.4) | Look | Tris, parts |
|---|---|---|---|
| Goblin Runt (fodder) | 3.2 -> **3.8** studs | a big expressive head on a scrawny body: huge leaf ears out to the sides, heavy brow, long nose, big eyes, a toothy grin; rust tunic with a leather strap, pointy shoes; khaki-olive skin | 1,899, 9 |
| Goblin Bruiser (heavy) | 4.6 -> **6.2** studs | a hunched burgundy brute, head low between massive shoulders and a hump; iron cap with sweeping bone horns, tusks, amber eyes; one spiked iron pauldron; long bandaged forearms to the knees; leather loincloth | 2,391, 10 |
| Slime (leaper) | 2.4 -> **2.9** studs | a soft mauve egg-dome on a spreading foot, a glossy highlight, two little nubs, dark oval eyes with catch-lights | 1,060, 3 |

Contact stays fair at the new sizes (M2.D: reach matches what is drawn): their body and
spacing radii grow with them (Runt 1.2/1.3 -> 1.4/1.5, Bruiser 1.35/1.7 -> 1.8/2.2, Slime
0.95/1.4 -> 1.2/1.65) and the charge's lane widens to the Bruiser's body (half-width 1.5 ->
1.8). Nothing else about them changes.

Influences: the goblin from the big-eared, big-nosed, grinning goblin references (head
size, ears, nose, teeth, pointy shoes) and the Bokoblin's hunched stance; the Bruiser from
the hunched horned brute (burgundy skin, bandaged forearms, loincloth, sweeping horns) and
the orc warriors (iron cap and pauldron, tusks, sheer bulk); the slime from the simple
glossy egg-slimes and the dome slimes with small nubs and oval eyes, in a muted mauve.
Previews: `work/art/enemies_lineup.jpg` (game scale beside a hero-sized stand-in,
`tools/art/render_lineup.py`), `work/art/enemies_sheet.jpg`.

## Performance

Offline (estimates, not Studio):
- an attack starting costs ~2 microseconds (its path walk, Lune); running one is a few
  comparisons a tick
- the bench mix of 250 enemies: ~413k enemy triangles (was ~328k with the old meshes),
  ~1,970 parts moved a frame (was 1,440: the kit models are split by colour)

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

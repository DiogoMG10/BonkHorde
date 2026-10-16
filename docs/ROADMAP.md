# Roadmap

The only active roadmap. Keep each phase to a few lines; detail belongs in the phase's own doc
(for M1, `docs/M1-hybrid-combat.md`). `PLAN.md` is the historical plan of the original build.

M2 and M3 can go in either order. Working on both at once is a parallel line and needs an
explicit decision by Tiago and Diogo.

## M1 Hybrid Combat — done

- **State:** M1.A clock, M1.B Sword, M1.C Fire Staff / Frost Ring and M1.D Auto-Trigger on
  `main`. `bonk-0.4.1-m1d` validated in Studio by Tiago and Diogo. The M1.A pause fix had not
  been tested in Studio on its own; M2.A rebuilds player pause on top of it.
- **Blockers:** none.

## M2 Movement & Game Feel — in progress

- **Scope:** momentum, bunny hop, slide, camera, impact, animation and audio.
- **State:** M2.A (player pause, volume settings, damage feedback, Sword slash,
  `bonk-0.5.4-m2a`, PR #4) and M2.B (bunny hop to 2.5x base over ~10 hops, speed-keeping air
  steering, slide/hop momentum hand-offs, slides to 2.8x, `bonk-0.6.2-m2b`) validated in
  Studio by Tiago and Diogo and merged to `main`. Studio speed readout: `hop` in
  Workspace.BonkDev.
- **M2.C Minty Frost Ring** (`bonk-0.7.0-m2c`): each enemy the ring hits has its own 25 %
  chance (+ Freeze Chance) to be frozen for 2 s, with an ice shell; validated in Studio by
  Diogo and merged. Fallback if it ever feels wrong: option B, a 15 % chance per ring
  activation to freeze every enemy it hit for 2 s.
- **M2.D enemy fairness** (`bonk-0.8.1-m2d`): body-to-body contact reach measured from the
  meshes and judged where clients draw the enemy, real height overlap, and a telegraphed root
  strike for heroes camping out of reach; validated in Studio by Diogo and merged.
- **Next playable result:** M3.A Wardwood (see M3).
- **Blockers:** none.

## M3 Art Direction & Wardwood — done

- **State:** M3.A (`bonk-0.11.0-m3a`, with its M5.A-line follow-ups) and M3.B
  (`bonk-0.17.4-m3b`) merged to `main`, both approved in Studio by Tiago and Diogo.
  The Wardwood: 1200-stud terrain, ~940-stud playable world, regions and landmarks,
  thinned forest with lanes and glades, six skies (one drawn at random per run, golden in
  the lobby). M3.B dresses all of it with the seeded Blender kit (`tools/art`, source
  `assets/art/wardwood_kit.blend`): tree families with variants and far/horizon versions,
  the ancients, the Elder, the Fallen Giant, bushes, ferns, stumps, logs, rocks, menhirs,
  pillars and ruin walls; the server bakes each model once and keeps only colliders,
  clients draw from shared templates; hand edits in `Config/WardwoodOverrides`
  (`art pick`); `art off` restores the old props. Roblox's native terrain grass is the
  ground (`grass native`). Enemy outlines are a per-player setting, off by default.
  Details: `docs/M3B-art-pipeline.md`.
- **Not yet verified for production:** the kit's meshes are baked at each server start
  through EditableMesh/DataModelContent (no uploads); the published game should use
  uploaded meshes, a separate authorization decision (GLBs in `assets/art/export`). No
  frame-time measurement under a full horde on mobile yet (see M4).
- **Blockers:** none.

## M4 Horde & Performance — in progress

- **Scope:** distinct enemy behaviours, telegraphs, pressure; enemy models redone for
  readability; optimisations only where a measurement justifies them.
- **State:** M4.A on branch `feat/m4a-enemy-variety`, `bonk-0.18.0-m4a`: the Goblin
  Bruiser charges (braced 0.85 s with its lane drawn, 18 studs committed, winded 1.1 s)
  and the Slime leaps (squats 0.55 s with its landing ring drawn, a 0.5 s arc, no
  steering); server-authoritative, freeze, pause and height overlap respected. Blender
  models for the Goblin Runt, Goblin Bruiser and Slime in colours that read against the
  grass. `pack` and `bench` dev commands. Details: `docs/M4A-enemy-variety.md`. Offline
  checks only.
- **Next playable result:** Studio: the charge and the leap in a horde (telegraphs read,
  dodges fair, punish windows), the new models against the forest, `bench 250` on `main`
  and here for a first performance baseline.
- **Blockers:** none.

## M5 Builds & Replayability — in progress

- **Scope:** balance, caps, synergies, evolutions, a mechanical identity per hero.
- **State:** M5.A (`feat/m5a-balance-feedback`, `bonk-0.15.2-m5a`) approved in human Studio
  playtests and merged to `main`: weapons, tomes and stackable items cap at 20; a finished
  build shows LVL MAX with no more level-up panels (extra levels pay 15 gold); Lifesteal
  removed; overtime compounds enemy HP x1.2 and damage x1.13 per 30 s tier to finite
  ceilings and adds pace (horde x1.45, up to 30% ember-trailing runners); Armor 70%,
  Evasion 60%, freeze 75% caps; bounded Silver; gems and coins fly home, no +XP tally;
  Fredoka for damage numbers and popups (`font <name> [numbers|popups|ui|all]` to compare).
- **Next playable result:** synergies, evolutions and hero identities (M5.B, to be planned).
- **Blockers:** none.

## M6 Complete Experience — not started

- **Scope:** bosses, co-op, progression, polish, publishing.
- **Next playable result:** to be set when M1 to M5 are further along.
- **Blockers:** release to the shared place is not rehearsed (`docs/ROJO-WORKFLOW.md`).

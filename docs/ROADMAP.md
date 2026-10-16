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

## M3 Art Direction & Wardwood — in progress

- **State:** M3.A (`feat/m3a-wardwood`, up to `bonk-0.11.0-m3a`) merged to `main` together
  with its follow-ups from the M5.A line: the Wardwood's 1200-stud terrain, ~940-stud playable
  world, regions and landmarks, the forest thinned with crown spacing, lanes and glades,
  six skies with one drawn at random per run (golden in the lobby), and the flat
  `grass short` ground. Layout, movement and atmosphere approved by Tiago and Diogo in
  Studio playtests. The part-built trees and the LeafyGrass ground are accepted as
  provisional art, to be replaced in M3.B.
- **M3.B Blender art overhaul:** branch `feat/m3b-blender-art`. `bonk-0.16.0-m3b` showcase
  approved in Studio by Tiago and Diogo. `bonk-0.17.0-m3b` dresses the whole Wardwood: every
  tree family (variants, far and horizon versions), the ancients, the Elder, bushes, ferns,
  stumps, logs, rocks, menhirs, pillars and ruin walls from the Blender kit; the server bakes
  each model once (no upload) and keeps only colliders, clients draw from shared templates
  with distance detail, per-plant tint and short 3D grass streamed round the hero; hand edits
  kept in `Config/WardwoodOverrides` (`art pick`); `art off` restores the old props. Details:
  `docs/M3B-art-pipeline.md`. Offline checks and Blender previews only.
- **Next playable result:** Studio: the whole Wardwood under every sky, bunny hops through
  woods and meadows, frame rate in a big fight; then decide on uploading the kit for good.
- **Blockers:** none.

## M4 Horde & Performance — not started

- **Scope:** distinct enemy behaviours, telegraphs, pressure; optimisations only where a
  measurement justifies them.
- **Next playable result:** enemy types that ask for different responses.
- **Blockers:** no performance baseline recorded yet; take one before optimising.

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

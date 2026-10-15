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

- **State:** M3.A (`bonk-0.9.0-m3a`, branch `feat/m3a-wardwood`) turns the map into the
  Wardwood, golden-hour Meadows look, built for hops and slides: reshaped landforms (Thunder
  Chute slide run, Elder Hill, curved Terraced Gardens, the Moonwell wading pond, the falls
  down the Highwatch's face, a mountain rim), landmarks (the Ward, the Runic Gate, the
  Highwatch ruins, the Elder tree, the Moonwell stones, ridge standing stones), cool spruce
  forest and warm oak/birch groves, paths, lighting, ambient effects. Pure layout in
  `Core/World` + `Core/Blueprints`; offline previews from `tools/map/export_world.luau` and
  `preview_blender.py`. Offline checks only: **not yet seen in Studio**. Supersedes the
  `proto/wardwood` greybox (its ward platform, paths and golden/teal looks were reused; its
  ProtoPull tooling was not).
- **Next playable result:** Studio playtest of M3.A: the look (lighting, haze, terrain
  colours, grass), the first view and the lobby, chute/ridge/garden slides, frame rate with a
  horde. `site <name>` in Workspace.BonkDev jumps to each landmark.
- **Blockers:** none.

## M4 Horde & Performance — not started

- **Scope:** distinct enemy behaviours, telegraphs, pressure; optimisations only where a
  measurement justifies them.
- **Next playable result:** enemy types that ask for different responses.
- **Blockers:** no performance baseline recorded yet; take one before optimising.

## M5 Builds & Replayability — not started

- **Scope:** balance, caps, synergies, evolutions, a mechanical identity per hero.
- **Next playable result:** builds that play differently from run to run.
- **Blockers:** depends on M1 settling how each hero's primary works.

## M6 Complete Experience — not started

- **Scope:** bosses, co-op, progression, polish, publishing.
- **Next playable result:** to be set when M1 to M5 are further along.
- **Blockers:** release to the shared place is not rehearsed (`docs/ROJO-WORKFLOW.md`).

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

- **State:** M3.A on branch `feat/m3a-wardwood`. `bonk-0.9.0-m3a` playtested in Studio: the
  heart (clearing, ruins, golden-hour light) was liked; grass hid enemies, the outer forest
  was a dense belt and the rim could be climbed to camp. `bonk-0.10.0-m3a` answers that:
  1200-stud terrain with a ~940-stud rounded playable world (the heart unchanged), new regions
  (Sunspire Hill and its Sun Temple, the Old Grove, the Fallen Giant's gully, Stoneglen,
  the North Vale and its long slope, Windhill, Thornwood), part-built ancient oaks and pines,
  dense forest only in patches, mountains rising straight from the edge behind an invisible
  barrier, shorter grass, interactable counts scaled to the area. Offline checks only.
  `bonk-0.11.0-m3a` (after a second playtest with screenshots): every tree family remodelled
  as part-built stylized trees from one kit (beech, oak, leaning oak, sapling, birch, spruce,
  pine, ancient oak, ancient fir, the Elder; no mesh trees left, nothing uploaded), foliage
  fades when it stands between the camera and the hero, lanterns at junctions, landmark
  approaches and bends instead of every 46 studs (60 -> 34), three skies to compare
  (`sky golden|clear|dusk`), foliage material A/B (`leaves <material>`), grass at Roblox's
  minimum 0.1. Offline checks only; the tree direction awaits human review in Studio.
- **Next playable result:** Studio review of `bonk-0.11.0-m3a`: the trees up close and at
  range, the three skies from the same spots, foliage material, frame rate in the woods.
- **Blockers:** none.

## M4 Horde & Performance — not started

- **Scope:** distinct enemy behaviours, telegraphs, pressure; optimisations only where a
  measurement justifies them.
- **Next playable result:** enemy types that ask for different responses.
- **Blockers:** no performance baseline recorded yet; take one before optimising.

## M5 Builds & Replayability — in progress

- **Scope:** balance, caps, synergies, evolutions, a mechanical identity per hero.
- **State:** M5.A on branch `feat/m5a-balance-feedback`, stacked on `feat/m3a-wardwood` (merge
  M3.A first). `bonk-0.13.1-m5a`: weapons, tomes and stackable items cap at 20 (maxed-out
  picks pay gold); overtime compounds (enemy HP x1.2 and damage x1.13 per 30 s tier, more
  elites); Armor cap 70%, Evasion 60%, lifesteal 4% max HP/s, freeze chance 75% per hit;
  Silver bounded (early defeat 6, normal win 53, strong run 90, cap 120 a run); gems and
  coins fly home, magnet and vacuum shrine sweep coins too; one-shot kills show numbers,
  crits by colour; projectile caps. Offline checks only.
- **Next playable result:** Studio playtest: a normal run's Silver, how long overtime lasts
  for a strong build, the magnet sweep, numbers on one-shot kills, frame rate late on.
- **Blockers:** M3.A's tree pass needs human review before either branch merges.

## M6 Complete Experience — not started

- **Scope:** bosses, co-op, progression, polish, publishing.
- **Next playable result:** to be set when M1 to M5 are further along.
- **Blockers:** release to the shared place is not rehearsed (`docs/ROJO-WORKFLOW.md`).

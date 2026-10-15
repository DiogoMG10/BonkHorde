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
- **State:** M2.A (player pause, volume settings, damage feedback, Sword slash) validated in
  Studio (`bonk-0.5.4-m2a`) and merged to `main` (PR #4). M2.B bunny hop and momentum
  on branch `feat/m2b-bunny-hop`. `bonk-0.6.0-m2b` playtested: hops barely sped up and
  slide/hop transitions lost speed. Fixed in `bonk-0.6.1-m2b` (speed written to the body,
  looser take-off check, slide/hop hand-offs), validated in Studio. `bonk-0.6.2-m2b`: air
  steering turns the heading and keeps the speed (A/D no longer brakes), gain 0.15 to a 2.5x
  cap over ~10 hops, slides to 2.8x. Offline checks only; readout: `hop` in Workspace.BonkDev.
- **Next playable result:** Studio playtest of `bonk-0.6.2-m2b` (W+Space chain to ~50,
  W+A/W+D and A/D at speed, hop to slide to jump, stop and wall), then tune and merge.
- **Blockers:** none.

## M3 Art Direction & Wardwood — prototype

- **State:** visual direction chosen; greybox on branch `proto/wardwood` (on top of M1.B, not
  merged).
- **Next playable result:** a validated, playable Wardwood version integrated into `main`.
- **Blockers:** the branch needs a review and Studio validation; it still uses ProtoPull
  (`tools/proto`), to be moved to the Rojo workflow when it is integrated.

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

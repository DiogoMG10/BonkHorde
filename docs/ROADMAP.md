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

## M2 Movement & Game Feel — not started

- **Scope:** momentum, bunny hop, slide, camera, impact, animation and audio.
- **Next playable result:** a run where moving and hitting feel better than now.
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

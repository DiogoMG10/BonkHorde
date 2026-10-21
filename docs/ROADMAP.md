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
- **State:** M4.A (`feat/m4a-enemy-variety`, `bonk-0.18.1-m4a`) merged to `main`. Gameplay
  approved in human Studio playtests: the Goblin Bruiser charges (braced 0.85 s with its
  lane drawn, 18 studs committed, winded 1.1 s) and the Slime leaps (squats 0.55 s with its
  landing ring drawn, a 0.5 s arc, no steering); server-authoritative, freeze, pause and
  height overlap respected. Enemy art is **provisional**: Blender models for the Goblin
  Runt, Goblin Bruiser and Slime (sources and references kept; to be revisited, not
  redesigned now). `pack` and `bench` dev commands. Details: `docs/M4A-enemy-variety.md`.
- **Performance:** offline estimate only: the 250-enemy bench mix draws ~413k enemy
  triangles (was ~328k) and moves ~1,970 parts a frame (was ~1,440), in one BulkMoveTo; an
  attack start costs ~2 microseconds. No Studio frame-time numbers recorded, and nothing
  about mobile or other hardware is validated.
- **M4.B** (`feat/m4b-horde-pressure`, `bonk-0.19.0-m4b`) approved in a human multiplayer
  Studio playtest and merged to `main`: the horde
  comes in a rhythm (40 s calm, then build, surge, ebb and a 14 s lull, every 55 s, as dense
  on average as before); each surge brings a named pack from one side or several (Goblin
  mob, Bruiser escort, Slime swarm, Pincer, Bone line, Stampede, Surrounded; Ghost tide and
  Shield wall in overtime) with a short banner and horn; charges and leaps on one hero take
  turns. Bosses hold the rhythm. `surge [pack]` and `pace` dev commands. Details:
  `docs/M4B-horde-pressure.md`.
- **Next playable result:** the post-playtest backlog below.
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

## Post-playtest backlog (2026-10-17)

From the multiplayer playtest after M4.B. Separate tasks, one at a time, each with its own
questions, branch and playtest approval. Untouched by all of them unless asked: enemy art,
Wardwood, native grass; no publishing or permanent uploads without authorization.

- **T1 — done.** No accidental picks on any choice panel (`feat/t1-levelup-guard`,
  `bonk-0.20.2-t1`), approved in human Studio playtests and merged to `main`. Level-up cards
  pop in dimmed and ignore all input for 0.5 s (0.35 s for a follow-up level-up, a
  Refresh/Banish hand, or an offer shown again from under a panel); Charge Shrine 0.5 s;
  Smug Statue, Dodgy Dan and Chest 0.35 s, and 0.35 s again after a purchase or a chest
  Banish. Then only a press begun after the lock commits (cards, rewards, Banish, Skip,
  Refresh, Ignore, keys 1-9); Dan's Leave is never locked; one answer in flight at a time;
  the gamepad selects only on unlock; a soft tick; co-op timers get the lock back
  (`Core/InputGuard`).
- **T2 — done.** HUD overhaul (`feat/t2-hud-overhaul`, `bonk-0.21.0-t2`), approved in Studio
  by Tiago and merged to `main`: Wardwood storybook look (moss panels, thin gold rim); corners
  by role (vitals card, purse, objectives and team top left; countdown plate, overtime pill,
  boss bars, banner and toasts top centre; minimap top right; build tray bottom centre); a
  safe-area root on Roblox's CoreUISafeInsets, compact layout on small screens
  (`Core/HudLayout`). Details: `assets/ui/NOTES.Hud.md`.
- **T3 — done.** Pause menu, inspector and end of run (`feat/t3-pause-results`, on top of
  T2, `bonk-0.22.0-t3`), approved in Studio by Tiago and merged to `main`: a three-column
  menu in the T2 look (build with a details card, actions with the run card, the stats sheet
  in sections; tabs on small screens) with map and settings inside; solo P pauses, co-op P
  opens it with the world still running (GAME STILL RUNNING; REQUEST PAUSE is the existing
  vote, closing keeps it). Death screen SKIP; results with the Silver breakdown and
  CONTINUE: solo back to the lobby at once (verified in Studio), co-op when everyone still
  here has pressed or the old fallback ends (`Core/EndVote`, run-numbered). PLAY AGAIN waits
  for T7. **Not yet verified in Studio:** the co-op flows (REQUEST PAUSE from the menu, the
  results vote). Details: `assets/ui/NOTES.Pause.md`.
- **T4** Audio audit and references for a softer sound direction.
- **T5** SFX, ambience and music redone; volume balance, nothing harsh or fatiguing.
- **T6 — next, together with T7.** Solo and co-op runs isolated: joiners never enter or
  disturb a running run; parties and run instances.
- **T7 — next, together with T6.** A stylized 3D floating-island hub replaces the 2D menu
  flow: gather, heroes, parties, start runs.
- **T8** A short portal-arrival sequence into Wardwood.
- **T9** Replayability: build variety, unlocks, challenges, persistent progression, no
  excessive power creep.
- **T10** Reliable published playtest builds: runtime Blender assets, multi-place testing.

# Bonk Horde: instructions for Claude Code

Active roadmap: `docs/ROADMAP.md`. Local sync and release: `docs/ROJO-WORKFLOW.md`. Code rules:
the five standing rules in `README.md`. `PLAN.md`, `BUILD.md`, `HANDOFF.md` and `HANDOVER.md`
are records of the original build run, not current instructions.

## How to work

- Act as the implementer of whole features. Plan briefly before a substantial change, then
  build it through to something playable.
- Gameplay, game feel and visible art come first.
- No prompt loops, long reports, unrequested refactors or new infrastructure without a
  concrete reason. Keep the existing architecture and decisions; do not add complexity early.

## Before every feature or task (mandatory)

1. Read the request, the references supplied and the relevant existing implementation.
2. Ask one concise, grouped set of questions on the intended design, gameplay, UX, visual
   direction and edge cases, with options and a recommendation where useful. Never ask for
   what the request already states.
3. Wait for the answers. Do not implement before the direction is approved.
4. Then implement autonomously: technical decisions, tests, bug fixes and integration within
   the agreed scope, without asking about minor or reversible details.
5. If a new design decision that materially changes the approved scope comes up, ask one
   focused question before going on.

This takes priority over any older instruction to ask only about scope or irreversible
decisions.

## Testing

- Test in proportion to risk: targeted specs while building when they help; the relevant gates
  (`rojo build`, `lune run test`, `selene src`, `stylua --check src lune`) before integrating.
  Markdown-only changes need no gameplay tests.
- Do not repeat Rojo tests, backups, audits or infrastructure checks that already passed unless
  there is a concrete cause.
- Always say which kind of check something had: offline (specs, gates), run in Studio by you,
  or validated by a person. Never present one as another.

## Collaboration

- Tiago and Diogo work on the same feature one after the other, taking turns with Claude Code.
  One active line of development by default; parallel work only when both decide it.
- One branch per feature, no permanent per-developer branches. GitHub is the source of truth.
- One developer's approval in a human Studio playtest is enough to integrate a feature into
  `main`, after the gates. Its roadmap line says who approved it and what is still unverified.
- Each developer has their own local `.rbxl` and Rojo session. Never switch branches while Rojo
  is connected.
- Local Claude Code sessions do not share context. Start from `git pull`, the roadmap and the
  last commit messages, not from memory of another session.
- Never publish to the shared Roblox place without explicit permission.

## Ending a session

Commit, and push when the developer asks (the push is part of the handoff). Give a short summary: feature delivered, tests (and their kind), limitations,
Git state (branch, commits, pushed or not). Update the phase's line in `docs/ROADMAP.md` if
its state changed; that line and the commit message are the handoff to the other developer.

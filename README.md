# Bonk Horde

Current roadmap: `docs/ROADMAP.md`. Local development and release: `docs/ROJO-WORKFLOW.md`.
Instructions for Claude Code: `CLAUDE.md`.

## The five standing rules

1. **Disk is the only source of truth.** Studio connects via `rojo serve`. Never
   edit scripts inside Studio, never `set_script_source` over MCP. MCP is for
   building geometry, inspection and screenshots only.
2. **Pure logic lives in `src/shared/Core/`, Instances live at the edges.** If a
   function can be written without touching an Instance, it must be. That is
   what makes it testable when play mode cannot be inspected.
3. **Gameplay and cross-client paths use `src/shared/Net.luau`** (plain
   RemoteEvents). Knit is lifecycle and DI scaffolding, not transport.
4. **Cosmetics can never break gameplay.** Effects resolve async, fail inert,
   and every one is pcall-isolated.
5. **Every tunable lives in `src/shared/Config/`.** Never hardcode a number in a
   Service or Controller.

## Layout

```
src/shared/Core/        pure Luau, headless-tested   - no Instances
src/shared/Config/      every design tunable         - data only
src/shared/Net.luau     the one networking module    - plain RemoteEvents
src/server/Services/    server-authoritative logic   - Knit Services
src/client/Controllers/ input, camera, rendering     - Knit Controllers
tests/                  *.spec.luau, headless        - `lune run test`
```

## Commands

```sh
aftman install                 # pinned tools
wally install                  # Knit, Promise, Signal, Trove -> Packages/
rojo serve                     # live-sync to your local DEV place (not the release process)
lune run test                  # headless test suite
selene src                     # lint
stylua src lune                # format
python check.py                # all gates in order
```

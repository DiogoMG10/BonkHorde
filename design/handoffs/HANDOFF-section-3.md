<!-- section: 3 -->
# HANDOFF: section 3 of 6 closed (World and visuals)

Game: `D:\Dev.2\BonkHorde`
Written: 2026-10-13T08:12:33+01:00

A cleared session starts from this file alone. Read it in full, then run:

```bash
python ~/.claude/skills/create-roblox-game/scripts/section.py resume --dir "D:\Dev.2\BonkHorde"
```

## Where things are
- `design/mesh_jobs.json`: the 51 mesh jobs (name, class, prompt, size, triangle budget, parts). `assets/meshes/manifest.json`: every generated mesh measured in Studio (mesh id, texture id, size, part offsets). `tools/assets/emit_assets.py` turns the manifest into `assets/models/Assets.rbxmx`, which Rojo maps to `ReplicatedStorage.Assets/{Enemies,Heroes,Weapons,Pickups,Interactables,Props}`.
- `tools/studio/bridge.py` (127.0.0.1:34881: serves project files to Studio, accepts `POST /save?path=work/..|assets/..`). `ServerStorage.BonkStage` in Studio: `.collect()` names generated models and lays them out in `Workspace.Staging`, `.manifest()` posts the measurements to disk. Dev only.
- Map: `src/shared/Core/MapGen.luau` gained `props`, `block` and `map.blocked`; `src/server/Services/MapService.luau` writes terrain, clones props into `Workspace.Map`, and sets lighting, sky, atmosphere and terrain colours in `_light()`. `tools/map/prove.luau` (the prover) and `tools/map/emit_map.py` write `work/map/{report.json,layout.json,plan.png,map.rbxmx,build.lua}`.
- Interface: `src/ui/{Hud,Choices,Menu,EndScreens,Overlay}.model.json` (StarterGui), `src/client/UiKit.luau`, `src/client/Controllers/{Hud,Minimap,Choice,Menu,Overlay,Lobby}Controller.luau`, `src/shared/Config/Icons.luau` (69 uploaded icon ids), `assets/ui/icons/*.png`, `assets/ui/icon_ids.json`, `tools/icons/` (Forge prompts and scripts), `tools/ui/fix_strokes.py`, `assets/ui/mockup.png` and `assets/ui/mockups/`.
- Heroes: `PlayerStateService:_dress` hides the avatar and welds `Assets.Heroes.Hero<Id>` parts to the R15 limbs, weapon mesh in the right hand.
- `tools/push/build.ps1` now builds six trees (Packages, Shared, Server, Client, Ui, Assets).

## Done this section
- 51 of 51 meshes generated with Studio `generate_mesh`, collected and measured (`BonkStage.manifest()` reported 51 assets). Segmented characters face -Z in model space (checked from left and right arm offsets).
- Map prover `lune run tools/map/prove.luau`: PASS on 9 checks (391 of 391 anchors reachable, 207 portal sites beyond 220 studs, spawn clearing slope 0.068 with 0 props, plateau reached by ramps only, boundary holds, 97% walkable, 14.5% slide ground, 262 solid props with no pair closer than 4 studs).
- 477 props placed in play (`[MapService] terrain ready, 391 anchors, 477 props`). Terrain surface measured against the simulated height at 9 points: was +2.0 studs everywhere, fixed to match.
- Twilight lighting, lobby scene with the squad's hero models, real menus (main, character select, map select), HUD, level-up panel with inventory and stats, minimap: each seen in a Studio play screenshot (`work/shots/`).
- 69 icons generated with Forge, uploaded with `upload_image`, all 69 keys in `Icons.luau` filled.
- Gates: rojo build PASS, 45 Lune specs pass, selene PASS, stylua PASS. No errors in Output during play.

## Decisions and why
1. **Meshes from Studio `generate_mesh`, not Forge or Blender.** Reason: it returns a textured, persistent mesh and texture id per part with no upload step, and the cartoon prompt style was consistent. Moderation rejects the word goblin (the prompt says forest imp) and more than about three jobs at once are rate limited.
2. **Props are scattered by a deterministic function in MapGen**, and solid ones (trees, big boulders, the tower) block enemy steps through `map.blocked`. Reason: server and client agree with no data sent, and enemies walk round trees instead of through them.
3. **Lighting and terrain colours are set in code at server start.** Reason: the place file then carries no hand-set look that can drift from the repository.
4. **UIScale does not scale Scale components**, so UiKit's compensation is off unless PlayerGui attribute `BonkUiScaleCompensate` is true. Measured in Studio at a 1380 px viewport.
5. **Nobody has a character in the lobby**, so the server gives each player a `ReplicationFocus` part at spawn (otherwise nothing streams in) and `LobbyController` shows local copies of the hero models.
6. **Icons go up through Studio `upload_image` in batches of 8.** Reason: it needs no key; batches of 35 timed out and dropped the Studio connection.

## Unproven
- Multiplayer with two or three clients: still never run.
- Unsegmented meshes (slime, ghost, pickups, weapons, props) have not had their facing checked one by one.
- The Bone icon reads as an animal, the knight portrait is pink while the model is silver: both to redo.
- A faint lighter rectangle shows on the ground near spawn in some screenshots; cause not found.
- Touch layout and gamepad have not been looked at on a device.
- Chest, shrine, shop and statue panels and the end screens have not been screenshot with the real interface (only the level-up panel has).
- Frame rate with real meshes and 300 enemies has not been re-measured.

## Debts
- Interventions this section: 1 (art direction changed to cartoon; logged). The user also renamed the key variable to `Key1` and asked for a one-shot run with no stops at section closes.
- Fallbacks: Rojo live sync replaced by the one-way push (carried over); icons uploaded with `upload_image` instead of Open Cloud (logged, nothing to heal).
- Stall: the ledger shows the ui and 3d-meshes stages hours over budget. About four hours of that was a usage-limit pause, and the three interface workers were each stopped once by the same limit and resumed.

## Ledger

Initialised once in section 1. Never run `init` again.

```bash
python ~/.claude/skills/roblox-build-orchestrator/scripts/run_log.py counter --dir "D:\Dev.2\BonkHorde\build-runs" --run "bonk-horde"
```

## Place
Place id `125855916502243`, universe id `10770589827`, owner user id `1600089176`, private. The open Studio session holds unsaved changes and nothing in it is unique: `tools/push/build.ps1` then `return require(game.ServerStorage.BonkPull)()` rebuilds scripts, interface and assets from disk; meshes and images are asset ids recorded in `assets/meshes/manifest.json`, `assets/ui/icon_ids.json` and `src/client/Vfx.luau`. `Workspace.Staging` (the generated source models) exists only in Studio and is not needed again. The place was last saved by the user before section 2; it gets saved or published at the end of the run.

## Rules

1. ONE SECTION PER SESSION. Finish this section's whole scope, then stop. Inside a section the skill's 'the run does not stop' rule applies in full; `section.py close N` passing is the only place you stop. Never start the next section's work, even with budget left.
2. STAY INSIDE CLAUDE CODE AND ROBLOX STUDIO. Work through the skills, MCPs and CLIs. No browser-driving tools (browser pane, Chrome), no web-GUI generators. WebSearch and WebFetch inside Claude Code are fine. Screen access is for Roblox Studio only.
3. NOTHING IN STUDIO BY THE USER'S HAND. Never ask the user to place, type, edit or configure anything in Studio, and never ask them to leave Claude Code or Studio. You may ask for: pressing Play or Stop, clicking Publish, approving a tool call, restarting a stuck MCP, or something purely mechanical no API or screen action of yours can reach.
4. LOG INTERVENTIONS AS THEY HAPPEN (run_log.py event --kind intervention): the user writes or edits code, makes a design or art decision (a genre named in the section 1 prompt is the brief, not an intervention), chooses between options, tells you WHAT is wrong rather than THAT something is wrong, or does something in Studio by hand. So never offer options: decide, and say why.
5. TIER 2 FIRST, fallback pre-authorised: take it without asking and log it as a fallback. 30-minute stall rule: one problem eats 30 minutes, fall back, log it, keep moving.
6. EVERY SESSION: ask for Roblox Studio screen access first (a grant does not survive a cleared session). 'Continue with the development of the <genre> game' means `section.py resume --game "<genre>"`: it finds the game and says which section is next.
7. THE LEDGER IS INITIALISED ONCE, in section 1. Every later call passes the --dir and --run recorded in HANDOFF.md. Bracket each ledger stage with start/end.
8. BEFORE CLOSING: save the place, write HANDOFF.md with `section.py handoff N`, replace every placeholder, run `section.py close N`. Then stop and ask the user to approve. Approval is free. If the user asks for changes, make them, log an intervention if they named what was wrong, update HANDOFF.md and close again. When the user approves ("approved", "yes that's all good"), run `section.py approve N` and say it is safe to clear the chat. Do not start the next section.

## Next section: first step
Section 4: Motion and sound (7 animation, 8 vfx, 9 sfx).
Sections 3 and 4 were built back to back in one session at the user's request, so section 4's work (effects kit, sound bank, animation overlays) is already on disk. Start by reading the section 4 handoff that replaces this file.

## Earlier handoffs

- `D:\Dev.2\BonkHorde\design\handoffs\HANDOFF-section-1.md`
- `D:\Dev.2\BonkHorde\design\handoffs\HANDOFF-section-2.md`

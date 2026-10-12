<!-- section: 1 -->
# HANDOFF: section 1 of 6 closed (Research and design)

Game: `D:\Dev.2\BonkHorde`
Written: 2026-10-12T22:30:31+01:00

A cleared session starts from this file alone. Read it in full, then run:

```bash
python ~/.claude/skills/create-roblox-game/scripts/section.py resume --dir "D:\Dev.2\BonkHorde"
```

## Where things are
- `D:\Dev.2\BonkHorde\` is the game folder (roblox-code scaffold from `new_game.py`: `src/`, `tests/`, `lune/`, `default.project.json`, `aftman.toml`, `wally.toml`, `BUILD.md`). No game code written yet.
- `design/game.json` is THE CONTRACT: pitch, core loop, scope, 25 systems, config, `roster` (3 heroes, 8 weapons, 12 tomes, 25 items, 8 enemies, 2 minibosses, 1 boss, 11 interactables, 5 pickups, 31 stats, spawn timeline), the 23-section `plan` and the `asset_plan` (47 entities, 280 rows).
- `design/map.json`, `design/meshes.json` (55 assets), `design/ui.json` (21 screens, 66 icons, logo and rivet ornament), `design/animations.json` (13 clips), `design/vfx.json` (35 effects), `design/sfx.json` (63 roles). All six stages are `todo`, none `skip`.
- `design/research.md` is the findings file with sources opened.
- `design/refs/REFERENCE.md` is the reference study: run flow by timestamp, HUD and panel measurements at 1920x1080, colours, world look. Read it before any visual work.
- `design/refs/` holds the user's five stills (`1.png`, `2.webp` .. `5.webp`), `sheets/a_01..06.jpg` and `sheets/b_01..08.jpg` (one frame per 10 s of each reference video, timestamped) and `frames/*.jpg` (16 full-resolution stills of each menu and HUD state).
- Reference videos stay where the user put them: `C:\Users\diogo\Downloads\Megabonk - PC Gameplay (No commentary) - Brunoborne (1080p).mp4` (forest run, 14:19) and `C:\Users\diogo\Downloads\Megabonk gameplay no commentary - WillTheDude (720p).mp4` (desert run, 19:32).
- Ledger: `D:\Dev.2\BonkHorde\build-runs\bonk-horde\`.
- `PLAN.md` is the plain-language plan the user reads and approves.
- Git: the game folder is a clone of the user's private repository `https://github.com/DiogoMG10/BonkHorde` (branch `main`). Reference footage frames under `design/refs/` are deliberately not committed (see `.gitignore`).
- Forge: `D:\Forge` (see Unproven for its state).
- Studio: nothing was created or changed. The open place is the user's saved experience "BonkHorde", still the empty default (Baseplate, SpawnLocation, Terrain, Camera).

## Done this section
- Stage 0 preflight: `preflight.py` ran. Skills 9/9 ok, tools 8/8 ok (python 3.14.7 via `py`, rojo 7.7.1, wally 0.3.2, selene 0.32.0, stylua 2.5.2, lune 0.10.5, git, Blender 4.5). Creator Store audio reachable. FAIL: place not saved. Degraded: `ROBLOX_API_KEY` unset, Kaggle not installed.
- Stage 1 research: both reference videos sampled at one frame per 10 s (203 frames on 14 contact sheets, all read), 16 full-resolution stills read, 5 user stills read. Seven web origins opened. Roblox market measured live through Roblox's own search and games endpoints (player counts in `design/research.md`).
- Stage 2 design, 2a plan, 2b asset plan: `validate.py --dir D:\Dev.2\BonkHorde` prints `contract valid: Bonk Horde`, plan `22 sections answered, 1 explicitly declined, 0 unaddressed`. A cross-check in the generator confirmed every asset-plan name exists in its stage spec and every spec entry is planned (0 missing, 0 unused, all six stages).
- Live probes in Studio (edit mode, `execute_luau`): `AssetService:CreateEditableMesh` and `CreateMeshPartAsync` work in-session; `AssetService:CreateAssetAsync` returns "CreateAssetAsync and CreateAssetVersionAsync are not available yet". Studio user id 1600089176, place id 0.
- Ledger stages `market-research` (14 m) and `design-spec` (5 m recorded; the design work overlapped research) are both bracketed start and end, status ok.

## Decisions and why
1. **Own name, characters and art; same structure and look.** The user asked for a game "exactly like" the reference. Mechanics and screen layout are followed closely; the title (Bonk Horde), heroes, bosses, item names, jokes and all artwork are original. Reason: a direct copy of another studio's game is removed by Roblox and is not something to ship.
2. **Forest only in this build; Desert is the first content update.** Reason: one map finished to the reference's standard, with repeated fidelity passes, beats two half-finished ones, and the loop only has to be proven once. Map select still shows Desert and Graveyard, locked. The desert reference study is kept.
3. **Single-stage runs (the reference's Tier 1 shape) with a clean win.** After the boss dies the portal becomes an exit; entering it is victory. Staying for the final horde is optional score chasing. Reason: a Roblox squad needs a win state, and multi-stage tiers are out of scope.
4. **A server is one squad of up to 3; menus and the run live in the same place.** Reason: testable in Studio with a 3-client test, no TeleportService or reserved servers.
5. **Co-op rules:** shared XP and level; level-up pauses the simulation for everyone and all players choose at once with a 12 s limit; other panels (chest, shrine, shop) pause only in solo and make the chooser untouchable in co-op; loot, prices and vendor stock are per player; tombstone revive in 3 s; enemy cap and boss HP scale with squad size. Reason: keeps the reference's pause-and-choose moment without one player's menu stalling the others.
6. **The horde is server data, not instances.** Up to 350 enemies simulated at 20 Hz on the map's heightfield and a blocked-cell grid, streamed as buffer snapshots at 10 Hz, rendered by each client from pooled models moved with one `BulkMoveTo`. Reason: hundreds of Humanoids cannot run on Roblox; this is the only route to reference-scale crowds.
7. **Enemies are rigid segmented models animated in code** (body, head, arms, legs swung procedurally), not skinned meshes. Reason: no Animator and one bulk move per frame is what makes 350 enemies affordable, and chunky jointed limbs suit the cartoon toy look. Revisit skinned meshes in section 3 only if Open Cloud upload is proven and the frame budget allows.
8. **Heroes are R15-compatible custom rigs** (15 limb meshes sharing one painted atlas, plus head gear), animated with authored R15 clips. Reason: gets Roblox's Animator and the roblox-animation toolchain for free.
9. **Light persistence is in scope** (silver, one unlockable hero, run counts, best time and score), overriding the skill's default "no datastore". Reason: the reference's menus show these numbers and a third hero to save for is the cheapest retention hook. Quests, ranks, skins and the unlock shop are out.
10. **ART DIRECTION IS CARTOON, NOT PIXELATED. The user changed this on 2026-10-12 (intervention 1).** The reference decides what is on screen and where; the look is clean stylised cartoon: chunky rounded shapes, smooth shading, hand-painted textures, saturated colour, rounded UI with thick outlines. Full text in `game.json` `plan.art_direction`. `design/refs/REFERENCE.md` still describes the pixel-art reference as it is; use it for layout, proportions, timing and colour roles, never for texture or font style.
11. **Fonts are Roblox's own Luckiest Guy (titles, numbers) and Fredoka One (body), with UIStroke outlines.** Panels, cards and buttons are native rounded corners, strokes and gradients, not image nine-slices. Reason: cartoon skin, crisp at every screen size, no font atlases to build.
12. **A one-page style sheet comes before any batch asset work** (one hero, one enemy, one prop, one icon, one panel), judged against the reference. Reason: with the style now original rather than copied, every worker needs one agreed target.
13. **Mesh routes:** exact meshes (hero limb sets, terrain chunks, chest, portal, weapons) are authored in Blender and uploaded through Open Cloud with the user's API key; organic meshes (enemies, bosses, trees, statues) come from Studio `generate_mesh` off a Forge concept image that was judged first. Reason: `CreateAssetAsync` is unavailable in this Studio, and AI generation is strongest at exactly the organic cartoon shapes Blender scripting is weakest at.
13b. **Forge is the image generator** (concepts, textures, icons, portraits, logo, sky), driven through its local API rather than its web page. Reason: the user asked for Forge; the section rules forbid driving web GUIs.
13c. **Work is committed to `main` of the user's GitHub repository and pushed at every section close.** Reason: the user asked for add, commit and push there; it is their solo repository, so there are no pull requests.
14. **Game folder is `D:\Dev.2\BonkHorde`**, not `C:\Dev`. Reason: `D:\Dev.2` is the folder this project's threads are allowed to work in. `resume --game` still finds it through the registry.

## Unproven
- Forge: the official package `webui_forge_cu121_torch231.7z` (1.87 GB) is downloaded to `D:\Forge` with the user's approval. Whether it is extracted, updated, has a model and answers on its API is recorded at the bottom of this file under 'Forge state'. Until that says PROVEN, treat Forge as unproven on this 8 GB RTX 4060.
- The cartoon style sheet does not exist yet. Nothing visual is approved until it does.
- `upload_image` (Studio MCP) and Open Cloud upload have not been exercised. Test each with one asset at the start of section 3.
- `generate_mesh` has not been exercised. Its match to the cartoon style, its part segmentation and its triangle counts are untested.
- `ROBLOX_API_KEY` was not set when section 1 closed. The user has a key and was told how to store it as a user environment variable. Read it with `[Environment]::GetEnvironmentVariable('ROBLOX_API_KEY','User')` (works without restarting anything) and NEVER print it. The Roblox user id is 1600089176.
- The 350-enemy server simulation and 10 Hz snapshot stream are a design, not a measurement. Section 2 must measure server frame time and client frame rate with 350 dummy enemies before building on it.
- Enemy numbers (HP, damage, speed) are the reference's published values scaled by `EnemySpeedScale`; balance is untested until the loop is played.
- The XP curve, chest prices and rarity weights are estimates fitted to the reference footage; untested.
- Roblox VFX library at `C:\Users\diogo\Roblox-VFX-Library` is empty; the VFX stage starts with a harvest.
- Mobile performance and touch controls are designed for, not tested.

## Debts
- Interventions: 1. Fallbacks: 0. Stalls: 0.
- Intervention 1 (2026-10-12, after the first close): the user changed the art direction from the reference's pixelated look to a cartoon look. The contract, all six stage specs, PLAN.md and this file were regenerated to match and `validate.py` is green again. Healed.
- Not a debt but not done: Studio screen access was not requested, because this session has no screen-control tool for Studio; the Studio MCP's own `screen_capture` and play tools are the route. Nothing in section 1 needed the screen.
- megabonk.wiki, the Steam guide and the Fandom wiki refused connections; the same facts were taken from megabonk.org, bonkmaster.com and Fextralife instead. Healed.
- A PowerShell `Set-Content -Encoding UTF8` wrote a BOM into `game.json` and broke the validator; rewritten without it and re-validated. Healed. Edit JSON with Python or the Edit tool, never PowerShell 5.1 `Set-Content`.

## Ledger

Initialised once in section 1. Never run `init` again.

```bash
python ~/.claude/skills/roblox-build-orchestrator/scripts/run_log.py counter --dir "D:\Dev.2\BonkHorde\build-runs" --run "bonk-horde"
```

## Place
**Saved to Roblox by the user as "BonkHorde".** Place id `125855916502243`, universe id `10770589827`, owner user id `1600089176`, private. It can be reopened from the Roblox account after a crash. There is no local `.rbxl` file, so `place_state.py` must be called with the id: `py <skills>\create-roblox-game\scripts\place_state.py --place-id 125855916502243`. Ids are also in `game.json` under `publish`. Never publish it publicly without the user's explicit approval.

On this machine Python is `py` (there is no `python` on PATH), so every skill command is `py <script>` from PowerShell with `$env:PYTHONIOENCODING='utf-8'`.

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
Section 2: Code and the playable loop (3 code, 4 map BLOCKOUT only, then play the loop on placeholder art).
1. `py "$env:USERPROFILE\.claude\skills\create-roblox-game\scripts\place_state.py" --place-id 125855916502243` and confirm the open Studio window is "BonkHorde".
2. In `D:\Dev.2\BonkHorde`: `rokit install`, then `wally install`, then `py "$env:USERPROFILE\.claude\skills\roblox-code\scripts\check.py"` and get all four gates green on the bare scaffold.
3. Read `design/game.json` (`systems`, `config`, `roster`, `plan.mechanics`, `plan.multiplayer`, `plan.security`) and `design/refs/REFERENCE.md`.
4. First code: the pure Core modules with Lune specs (`Stats`, `Damage`, `XPCurve`, `Offers`, `SpawnDirector`, `Economy`, `Grid`, `Steering`, `Snapshot`, `RunState`), then `EnemyService` with 350 dummy enemies on a flat blockout to **measure** server frame time and snapshot size before anything else is built on the horde design.
5. Blockout only for the map in this section (`design/map.json`), placeholder parts for everything visual, then PLAY the loop: move, kill, level up, chest, shrine, boss portal, boss, exit, results.

6. Commit and push to `origin main` before closing the section.

Carried from section 1: the user was asked to store their Roblox API key as the `ROBLOX_API_KEY` user environment variable; check that it is set before section 3 needs it.

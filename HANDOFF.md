<!-- section: 2 -->
# HANDOFF: section 2 of 6 closed (Code and the playable loop)

Game: `D:\Dev.2\BonkHorde`
Written: 2026-10-13T00:24:38+01:00

A cleared session starts from this file alone. Read it in full, then run:

```bash
python ~/.claude/skills/create-roblox-game/scripts/section.py resume --dir "D:\Dev.2\BonkHorde"
```

## Where things are
- `src/shared/Config/GameConfig.luau` (every scalar tunable) and `src/shared/Config/Roster.luau` (stats, heroes, weapons, tomes, items, enemies, bosses, shrine boosts, rarities, maps).
- `src/shared/Core/`: `Stats`, `Damage`, `Progress` (XP curve, chest price, silver), `Offers`, `Spawn`, `Grid`, `MapGen` (the map as a heightfield function, anchors, reachability), `Snapshot`, `RunState`. Pure, no Instances.
- `src/shared/Net.luau`: all 32 RemoteEvent names with payload notes.
- `tests/Rules.spec.luau`, `tests/Systems.spec.luau`: 43 Lune specs.
- `src/server/Services/`: `DataService`, `PartyService`, `MapService`, `PlayerStateService`, `XPService`, `UpgradeService`, `EnemyService`, `CombatService`, `PickupService`, `InteractableService`, `BossService`, `RunDirectorService`, `DevService` (Studio-only test hooks).
- `src/client/Controllers/`: `StateController`, `CameraController`, `MovementController`, `EnemyRenderController`, `PickupRenderController`, `WeaponFxController`, `WorldController`, `DebugUiController`.
- `tools/push/`: `build.ps1` (gates + four `rojo build`s + local file server), `pull.luau` (the Studio-side pull), four `*.project.json`. Output goes to `work/push/*.rbxmx`.
- `aftman.toml`: rojo pinned to 7.7.1 to match the installed Studio plugin. `stylua.toml`: column width 140.
- Studio (place 125855916502243): `ReplicatedStorage.Packages`, `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayer.StarterPlayerScripts.Client` are pushed from disk. `ServerStorage.BonkPull` is the pull helper (dev only, delete before publishing). Baseplate and SpawnLocation were removed. `HttpService.HttpEnabled` is ON (needed for the pull; turn OFF before publishing). `Players.CharacterAutoLoads` is false.

## Done this section
- All game code for the loop. `roblox-code/scripts/check.py`: rojo build PASS, `lune run test` 43 passed 0 failed, selene PASS, stylua PASS.
- Build stamp `[Bonk Horde] Server started - BUILD bonk-0.2.0` and the client stamp both seen in Output on Play.
- Scripted playtests in Studio (solo), read back through `[Dev] status` lines in Output and a client-side probe of the HUD text:
  - lobby, hero pick, ready, run start, terrain written from the heightfield, hero spawned at 5,12,0
  - auto-attacks kill enemies, gems and coins drop and are collected, shared XP levels the squad
  - level-up pauses the run and anchors the hero; offers show before and after values; pick, skip, banish and refresh are wired
  - chest (30 gold, item panel, take), charge shrine (charged in 9.8 s, reward applied), statue, vendor (bought an item, gold deducted), greed shrine, vacuum shrine, challenge shrine (elites spawn, free chest after)
  - miniboss spawn, stage boss summon at the portal, boss death flips the portal to exit, exit countdown, VICTORY results (+13 silver), back to lobby
  - second run with the other hero: overtime starts at 10:00, minibosses at 4:00 and 7:30, hero downed, Wipe, Results
- Measured with 340 enemies alive at once (dev PC, solo Play): server simulation tick 1.62 ms at 20 Hz, client 60 fps average, worst frame 18.7 ms, 340 enemy models moved in one BulkMoveTo.

## Decisions and why
1. **One-way push instead of Rojo live sync** (`tools/push`). Reason: the Rojo plugin needs a Connect click no tool can make, and the user asked not to be interrupted. `rojo build` still assembles the tree, so the build gate is unchanged. If the user ever connects the Rojo plugin as well, stop using the push: two writers on one tree is the duplicate-module trap.
2. **Studio is a cache; disk plus asset ids is the source of truth.** Nothing may exist only in the open place. Anything generated in Studio (meshes) must be serialised back to disk (SerializationService) or recorded by asset id. Reason: the place cannot be saved from a script, and Studio crashes.
3. **The terrain is Roblox Terrain written at server start from `MapGen`** (Grass on gentle ground, Ground on slopes, Rock on cliffs). Reason: characters get real collision for free, enemies and clients share the same height function, and smooth grassy terrain suits the cartoon direction better than faceted mesh chunks. The `TerrainMossyWoods` asset therefore becomes terrain materials and colours, not mesh chunks.
4. **Enemy network format:** reliable RemoteEvents carrying buffers. Spawn (4 bytes), snapshot at 10 Hz (6 bytes per enemy: slot, x, z), gone (3 bytes), hits (5 bytes). Height is never sent. Reason: an UnreliableRemoteEvent drops payloads over about 900 bytes and a full snapshot is 2.1 KB.
5. **Item effects live where they act** (CombatService, PlayerStateService, PickupService, InteractableService) and are driven by `Roster.Items`. There is no separate ItemService. `game.json` `systems` was updated to the services and controllers that exist.
6. **XP curve refitted to the reference footage:** `xpToNext = 4 + 5.5 * level` (level 16 at about 720 XP, level 24 at about 1,600). The first estimate in section 1 was too steep.
7. **Rarity multipliers refitted to the reference:** Common 1.0, Uncommon 1.2, Rare 1.4, Epic 1.6, Legendary 2.0 (the reference shows +25 shield Common and +50 Legendary).
8. **`EnemyDamageScale = 0.7`** as a starting point. Reason: reference damage values with an 0.8 s contact cooldown took 70 of 150 HP in 15 s standing still in the first playtest; needs tuning by real play.
9. **Pots and crates break when a hero runs into them** rather than when a weapon touches them. Reason: one cheap server check instead of weapon-versus-prop collision.
10. **DebugUiController is the interface for now** and stays as the always-wired fallback. The real screens replace it in section 3.
11. **DevService test hooks** (Studio only, `RunService:IsStudio()`): set the Workspace attribute `BonkDev` to commands separated by `;`. Commands: `status`, `auto` (answer every level-up and panel), `god`, `gold N`, `level N`, `clock N`, `hurt N`, `killall`, `item Id`, `weapon Id`, `tp x z`, `goto Kind`, `use Kind`, `spawn Type N hpMult`, `boss`, `mini Type`, `bosshp F`, `pick N`, `panel action index`. Reason: a running game cannot be queried from outside its own scripts.

## Unproven
- Multiplayer: every test so far was solo. Co-op level-up timeout, per-player panels, tombstone revive, late join and squad scaling have never run with two clients.
- Movement feel (slide, bunny hop, extra jumps), the camera and touch or gamepad input have been exercised only through scripted key presses; nobody has played by hand.
- Balance: damage taken, kill speed, XP pace and gold pace are untuned.
- Boss attacks (telegraphs, thorns, stomp) fire in code but nobody has watched them land on a hero who is not invulnerable.
- Bone, Boomernana, Axe and Party Rocket ran without errors but their visuals have not been looked at closely.
- Terrain `GrassLength = 0.25` is set at server start and did not visibly shorten the grass in a screenshot; fix in the map stage.
- DataStore cannot be reached from this Studio session ("Studio access to APIs is not allowed"), so saving has only been tested on its failure path.
- The client frame rate was measured on the dev PC only, with placeholder blocks, not meshes.
- Forge, upload_image, generate_mesh and Open Cloud upload: see the section 1 handoff; none has been used for a real asset yet. The API key is in the user variable `Key1` (length checked, key never printed, not yet used).

## Debts
- Interventions this section: 0 (run total 1, from section 1).
- Fallback 1: Rojo live sync replaced by the one-way push (see Decisions 1). Not healed and does not need to be for the game; it is a workflow difference. Logged in the ledger.
- Stall: about 25 minutes went on Forge's launcher earlier in the session (batch file line endings and path handling), before this section. Healed; recorded in the section 1 handoff.

## Ledger

Initialised once in section 1. Never run `init` again.

```bash
python ~/.claude/skills/roblox-build-orchestrator/scripts/run_log.py counter --dir "D:\Dev.2\BonkHorde\build-runs" --run "bonk-horde"
```

## Place
Place id `125855916502243`, universe id `10770589827`, owner user id `1600089176`, private, saved to Roblox by the user as "BonkHorde". The open Studio session holds unsaved changes (the pushed scripts, the removed baseplate, HttpEnabled). **Nothing in it is unique**: `tools/push/build.ps1` then `return require(game.ServerStorage.BonkPull)()` in the edit DataModel rebuilds it from disk. If `ServerStorage.BonkPull` is missing, run `tools/push/pull.luau` through `execute_luau`. No script can save the place; the user saves or publishes at the end, or the place file is published through Open Cloud.

The Studio MCP id changes when Studio restarts: call `list_roblox_studios` first. In this session it was `ad70265a-fa52-4455-804e-10185a4a02c4`.

## Loop playtest
Played through DevService hooks on placeholder blocks, solo, on 2026-10-13.

| Check | Result |
|---|---|
| Lobby to run | hero picked, ready, run started, hero at 5,12,0, timer 9:50 after 10 s |
| Core verb | 12 kills in the first 15 s with the starting Sword |
| Level-up | level 2 at 0:15, run paused, three offers shown with before and after values |
| Chest | 30 gold spent, item panel opened, item taken, Max HP 150 to 160 |
| Charge shrine | charged in 9.8 s standing inside, reward applied |
| Boss | summoned at the portal, killed, portal became the exit |
| Run end (win) | Victory at 0:40, results row, +13 silver, lobby again |
| Run end (loss) | overtime at 10:00 (177 enemies alive 45 s later), hero downed, Results |
| Server cost | 1.62 ms per tick with 340 enemies alive |
| Client cost | 60 fps, worst frame 18.7 ms, 340 enemy models |

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
Section 3: World and visuals (4 map (full), 5 meshes + colour + materials, 6 ui).
1. `list_roblox_studios`, then confirm the place is BonkHorde (place id 125855916502243).
2. Start Forge (command in the section 1 handoff, archived at `design/handoffs/HANDOFF-section-1.md`) and make the one-page cartoon style sheet first: one hero, one enemy, one prop, one icon, one panel. Judge it against `design/refs` for what is shown and against `game.json` `plan.art_direction` for style.
3. Prove the asset routes with one asset each before any batch: Forge image to `upload_image`; Studio `generate_mesh`; Open Cloud upload with the key in `Key1`.
4. Then fan out: map dressing, meshes, interface. Every asset ends up either as an rbxm on disk or as an asset id in a manifest on disk.

## Earlier handoffs

- `D:\Dev.2\BonkHorde\design\handoffs\HANDOFF-section-1.md`

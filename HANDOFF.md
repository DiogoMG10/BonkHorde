<!-- section: 5 -->
# HANDOFF: section 5 of 6 closed (Assembly, playtest and self-correction)

Game: `D:\Dev.2\BonkHorde`
Written: 2026-10-13T08:24:42+01:00

A cleared session starts from this file alone. Read it in full, then run:

```bash
python ~/.claude/skills/create-roblox-game/scripts/section.py resume --dir "D:\Dev.2\BonkHorde"
```

## Where things are
- `HANDOVER.md`: how to run the game, the gates, the pre-handover matrix, the not-verified list and the debts.
- World effects: `src/client/Vfx.luau` gained `Vfx.place`; `WorldController.luau` (portal swirl and wind, shrine, chest and break bursts), `EnemyRenderController.luau` (crown mesh with glint, ghost wisps), `WeaponFxController.luau` (embers), `HeroAnimController.luau` (dust on landing and sliding).
- `tools/ui/bake_icons.py` writes the uploaded icon ids into `src/ui/*.model.json`; `assets/ui/IconSet.model.json` is the record of all 69 icons by key.
- `tools/sfx/install_bank.py` writes `src/shared/Sounds.model.json` (ReplicatedStorage.Shared.Sounds, 63 Sound instances) and points `src/shared/Sfx.luau` at it.
- `MenuController:_deathHero` puts the fallen hero in the death screen viewport; the unlock button label is capped at 44 px.
- `design/game.json` asset plan: six entries updated to say how they were really delivered (terrain and sky through the map stage, two optional, `Hud` and `Rivet` renamed).
- `work/wired_probe.lua`, `work/wired_report.txt`: the live wiring pass.

## Done this section
- `validate.py --stage-gate`: contract valid. `verify_wired.py --report`: static and live pass (212 MeshParts, 92 ImageLabels, 63 Sounds, 5 ScreenGuis, nothing empty or pending). Before the fixes it reported 92 empty ImageLabels and 0 Sounds.
- Two full runs through the real interface in Studio: a win (boss summoned and killed, exit portal, Victory screen, +10 silver, lobby) and a death (death screen with the hero, lobby).
- Second hero chosen by clicking his tile and played to level 5; locked hero shows the unlock card.
- Chest and vendor panels, boss bar, boss portal effects, fire explosion and boomernana trail seen in screenshots.
- Gates: rojo build PASS, 45 specs, selene PASS, stylua PASS.

## Decisions and why
1. **Icon ids are baked into the interface files as well as set at runtime.** Reason: the wiring check found every ImageLabel in the place empty; a place whose images only exist after a controller runs cannot be checked and shows blanks if a controller fails.
2. **The sound bank is installed as Sound instances under ReplicatedStorage.Shared.Sounds.** Reason: same check, 0 Sounds in the place. The generated runtime now uses the installed instance first and still builds one on demand if it is missing.
3. **The asset plan was edited to match delivery rather than the manifests bent to match the plan**, for the six entries where the build took a different route (terrain, sky, grass, embers, HUD name, rivets). Each entry says what was done instead.
4. **Multiplayer is handed over as UNTESTED** rather than inferred from code. Reason: no tool here can start a second client, and the skill's rule is that a row that could not be tested is written down.

## Unproven
- Everything in HANDOVER.md under 'Not verified': multiplayer, every sound, Mint in play, elites, four weapon effects on screen, most animations, shrine and statue panels, vendor buying, card clicks, pause menu, big map, touch, boss attacks on a vulnerable hero, balance, saving, performance with real art.

## Debts
- Interventions this section: 0.
- Fallbacks: none new.
- Known flaws listed in HANDOVER.md (Bone icon, knight portrait colour, enemy stacking, ground rectangle, flat sky, no chest beam fan).
- Publishing chores not done yet: HttpEnabled off, remove BonkPull, BonkStage and Workspace.Staging, save the place.

## Ledger

Initialised once in section 1. Never run `init` again.

```bash
python ~/.claude/skills/roblox-build-orchestrator/scripts/run_log.py counter --dir "D:\Dev.2\BonkHorde\build-runs" --run "bonk-horde"
```

## Place
Place id `125855916502243`, universe id `10770589827`, private, owner user id `1600089176`. Studio holds the current build, unsaved. Rebuild with `tools/push/build.ps1` and `return require(game.ServerStorage.BonkPull)()` (bridge on 34881 and the push server on 34880 must be running).

## Playtest findings
- Found and fixed: the terrain surface sat 2.0 studs above the simulated ground (enemies and props buried); the interface scale compensation pushed panels off screen; nothing streamed in behind the menu because nobody has a character in the lobby; hero animation overlays did nothing because new avatars use AnimationConstraint; every icon in the place was empty until a controller ran; the place had no Sound instances; the death screen had no hero; the unlock label overflowed its button.
- Found and not fixed: enemies stack on the hero's exact position when he cannot be hurt; the Bone icon reads as an animal; the knight portrait colour does not match the model; a faint lighter rectangle on the ground near spawn.
- Not reached: anything needing a second client, a human ear, or a human hand on the controls. See HANDOVER.md.

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
Section 6: Publish (12 publish).
1. Ask the user to run a two-player test (Test tab, Clients and Servers, 2 players, Start) and report or let Claude read the Output of each window through `list_roblox_studios`.
2. Clean the place for saving: `HttpService.HttpEnabled = false`, destroy `ServerStorage.BonkPull`, `ServerStorage.BonkStage`, `Workspace.Staging`.
3. Ask the user to save to Roblox (File, Save to Roblox). The game stays private; never publish publicly without their explicit yes.
4. Record `publish` in `design/game.json`, then `section.py close 6`.

## Earlier handoffs

- `D:\Dev.2\BonkHorde\design\handoffs\HANDOFF-section-1.md`
- `D:\Dev.2\BonkHorde\design\handoffs\HANDOFF-section-2.md`
- `D:\Dev.2\BonkHorde\design\handoffs\HANDOFF-section-3.md`
- `D:\Dev.2\BonkHorde\design\handoffs\HANDOFF-section-4.md`

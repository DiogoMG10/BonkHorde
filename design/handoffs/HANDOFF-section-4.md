<!-- section: 4 -->
# HANDOFF: section 4 of 6 closed (Motion and sound)

Game: `D:\Dev.2\BonkHorde`
Written: 2026-10-13T08:13:37+01:00

A cleared session starts from this file alone. Read it in full, then run:

```bash
python ~/.claude/skills/create-roblox-game/scripts/section.py resume --dir "D:\Dev.2\BonkHorde"
```

## Where things are
- Effects: `src/client/Vfx.luau` (the kit: `Vfx.burst`, `Vfx.ground`, `Vfx.bolt`, `Vfx.attach`; 30 presets; 17 texture ids), `tools/vfx/make_textures.py` and `assets/vfx/tex/*.png` (the game's own particle textures), `assets/vfx/manifest.json` (which design effect is wired where). `src/client/Controllers/WeaponFxController.luau` plays weapon, projectile and telegraph effects through the kit; `EnemyRenderController.luau` fires hit sparks, crit bursts and death puffs.
- Sound: `src/shared/Config/SoundBank.luau` (63 roles, generated), `src/shared/Sfx.luau` (generated runtime), `src/client/Controllers/AudioController.luau` (music by phase, ambience, every event sound, UI clicks), `assets/sfx/manifest.json` and `work/manifest.json` (the measured picks), `work/sfx/` (candidates, probe reports, retry specs).
- Animation: `src/client/Controllers/HeroAnimController.luau` (code-driven joint overlays), `assets/animations/manifest.json` (13 clips and the route each takes).
- `src/client/Controllers/MovementController.luau`: the slide now also reads the touch button (PlayerGui attribute `BonkSlideHeld`).
- Everything from section 3 is unchanged; its handoff is archived at `design/handoffs/HANDOFF-section-3.md`.

## Done this section
- Effects: 17 textures drawn and uploaded; slash crescent, death puffs and level-up burst seen in Studio play screenshots; no effect errors in Output across four play sessions. 21 of the 35 designed effects are wired, the other 14 are presets or world effects not yet fired (list in `assets/vfx/manifest.json`).
- Sound: 625 candidates created and measured in Studio across three passes (315 + 130 + 180, all `IsLoaded`), 63 of 63 roles filled inside their length bands. Nine scored picks were swapped by hand because they were rips from other games or the wrong kind of sound. Nobody has listened to the bank.
- Animation: Waist joint measured at 38.7 degrees of yaw during sword swings in play (0.8 before the fix), which shows the overlays land on top of the stock walk cycle.
- Gates: rojo build PASS, 45 Lune specs pass, selene PASS, stylua PASS. `validate.py`: contract valid, all six stages done with their artifacts.

## Decisions and why
1. **The effect kit is authored, not harvested.** Reason: the user's effect library was empty, taking a Creator Store pack needs the user's hand, and a store search returned nothing usable. Own textures plus written emitter values keep the cartoon look consistent and owe nothing to anyone. Logged as a fallback.
2. **Flat effects (slash, rings, telegraphs) are unlit SurfaceGuis on thin parts**, pooled. Reason: Decals are lit by the scene and go dark at night; a SurfaceGui with LightInfluence 0 stays bright.
3. **Hit sparks are capped at 6 per frame** and busy sounds have a minimum gap each. Reason: a frost tick on 300 enemies would otherwise flood the screen and the speakers.
4. **No animation is uploaded.** Idle, Run, Jump and Fall are Roblox's stock R15 set; swings, casts, throws, landing, slide, downed and cheer are joint transforms written after the animator each frame. Reason: no upload quota, no asset to moderate, and it works for every hero model. New avatars use AnimationConstraint, not Motor6D, so the controller accepts both. Logged as a fallback.
5. **Sounds are Creator Store assets used by id**, chosen by measured length, never by listing. Picks whose names showed they were taken from another game were replaced with library sounds (ProSoundEffects, APM, Roblox).
6. **Music follows the phase**: menu, forest, boss (while a boss is alive), overtime, results; ambience runs during a run.

## Unproven
- Nobody has heard the sound bank or the mix; volumes are the design values.
- 14 designed effects are not fired yet: freeze shatter, pickup glint, dust puffs, poison, portal swirl, boss portal wind, shrine dome and charged burst, chest beams, break puffs, shockwave, elite glow, ghost trail, revive ring, ambient embers.
- Slash orientation was judged from one screenshot; fire, lightning, frost, rocket and axe effects have not been captured on screen.
- Cast, throw, downed, cheer, slide and portal-step poses have not been looked at, only the swing was measured.
- Chest, shrine, shop and pot sounds depend on payload fields (`panel.kind`, `data.kind`) that were read from the code, not exercised.
- Everything listed as unproven in the section 3 handoff still stands, multiplayer first of all.

## Debts
- Interventions this section: 0.
- Fallbacks: effects authored instead of harvested; animation in code instead of authored clips (both logged, both deliberate, nothing to heal unless the look falls short).
- The icon worker was stopped by the usage limit mid-check; its 69 icons were complete and were uploaded by hand afterwards.

## Ledger

Initialised once in section 1. Never run `init` again.

```bash
python ~/.claude/skills/roblox-build-orchestrator/scripts/run_log.py counter --dir "D:\Dev.2\BonkHorde\build-runs" --run "bonk-horde"
```

## Place
Unchanged from section 3: place id `125855916502243`, universe id `10770589827`, private. Studio holds unsaved state that `tools/push/build.ps1` plus `return require(game.ServerStorage.BonkPull)()` rebuilds. `HttpService.HttpEnabled` is still ON and `ServerStorage.BonkPull` and `BonkStage` still exist: all three go before publishing. The bridge (`py tools/studio/bridge.py`, port 34881) and the push file server (port 34880) must be running for pulls.

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
Section 5: Assembly, playtest and self-correction (9b integration, 10 assembly, 10b wiring, 11 playtest).
1. `list_roblox_studios`, confirm BonkHorde, run `tools/push/build.ps1` and the pull.
2. Wire the 14 remaining effects into `WorldController` and `EnemyRenderController`, then capture each weapon effect on screen.
3. Screenshot every panel and end screen with the real interface and fix what is off.
4. Start a two or three client test (Studio Test tab, local server) for the co-op paths: level-up timeout, per-player panels, revive, late join.
5. Then `validate.py --stage-gate`, `verify_wired.py`, and write HANDOVER.md.

## Earlier handoffs

- `D:\Dev.2\BonkHorde\design\handoffs\HANDOFF-section-1.md`
- `D:\Dev.2\BonkHorde\design\handoffs\HANDOFF-section-2.md`
- `D:\Dev.2\BonkHorde\design\handoffs\HANDOFF-section-3.md`

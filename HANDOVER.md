# Bonk Horde: handover

Written 2026-10-13. Place id `125855916502243`, universe id `10770589827`, private.
Repository: `https://github.com/DiogoMG10/BonkHorde` (branch `main`).

A horde-survival roguelite for one to three players: pick a hero, survive ten minutes of
swarming enemies with weapons that fire on their own, level up, loot chests and shrines,
find the boss portal, kill Old Man Timber and leave through the portal.

## How to run it

1. Open the BonkHorde place in Studio.
2. From `D:\Dev.2\BonkHorde`: `py tools/studio/bridge.py` (port 34881), then
   `powershell -ExecutionPolicy Bypass -File tools/push/build.ps1` (runs the gates, builds six
   trees, serves them on port 34880).
3. In Studio's command bar: `return require(game.ServerStorage.BonkPull)()`.
4. Press Play. Controls: WASD, mouse look, Space (hold to bunny hop), Left Shift or C to
   slide, E to interact, Tab for the big map, P to pause.
   Since M1.B (unverified in Studio, see `docs/M1-hybrid-combat.md`): Sir Clonk's Sword is
   fired by hand, left mouse button, click or hold, aimed with the camera.

Test hooks (Studio only): set the Workspace attribute `BonkDev` to a command, for example
`god`, `auto`, `gold 500`, `weapon Axe`, `spawn Skeleton 40`, `goto BossPortal`,
`use BossPortal`, `bosshp 0.01`, `hurt 9999`. Full list in `src/server/Services/DevService.luau`.

## Gates at handover

| Gate | Result |
|---|---|
| `roblox-code/scripts/check.py` | rojo build PASS, 45 Lune specs pass, selene PASS, stylua PASS |
| `tools/map/prove.luau` | PASS on 9 checks (391 of 391 anchors reachable, 97% walkable) |
| `validate.py --stage-gate` | contract valid, six stages done, asset plan reconciled |
| `verify_wired.py --report work/wired_report.txt` | static and live pass: 212 MeshParts, 92 ImageLabels, 63 Sounds, 5 ScreenGuis, nothing empty or pending |

## Pre-handover matrix

Every row is either measured in a Studio play session on 2026-10-13 (solo, one client) or
marked UNTESTED. Screenshots referred to are the Studio captures taken during the session;
three are kept in `work/shots/`.

| What | Result |
|---|---|
| Hero: Sir Clonk (Knight) | Chosen through the real menu (Play, character select, Confirm, map select, Ready). Spawned with the knight model, sword in the right hand (weapon part welded 1.28 studs right, 1.14 below the root). Played through a full win and a death. |
| Hero: Zib (Fox) | Chosen through the real menu by clicking his tile. Spawned with 100 HP and the Fire Staff, played with four weapons to level 5. |
| Hero: Mint (Frostling) | Tile shows locked, detail card shows the 150 silver unlock and LOCKED. **UNTESTED in play**: could not be unlocked, because saving does not work from Studio and the profile has 0 silver. |
| Weapon: Sword | Slash crescent seen on screen sweeping in front of the hero; hits and kills registered. |
| Weapon: Fire Staff | Fireball explosion (orange cartoon puffs and hit star) seen on golems. |
| Weapon: Boomernana | Banana meshes with pale trails seen in flight. |
| Weapon: Frost Ring, Lightning Staff | Equipped (icons in the HUD row) and firing without errors. **Effect not captured on screen: UNTESTED visually.** |
| Weapon: Bone, Axe, Party Rocket | Ran without errors in section 2. **Not looked at with the real meshes and effects: UNTESTED visually.** |
| Enemies | Imp runt, bruiser, slime, skeleton, shield skeleton, golem, ghost, twiglet and hog brute all seen with their real meshes, standing on the ground and facing the hero. |
| Elites and minibosses | Crown mesh and glint are wired. **UNTESTED in this session.** |
| Boss: Old Man Timber | Summoned at the portal through the dev hook, real mesh, boss bar 9,000 HP, quest line added; killed, portal became the exit. Telegraphed attacks **UNTESTED on a hero who can be hurt**. |
| Level up | Pause, rainbow XP bar, light rays, three offer cards with rarity, level and before and after values, inventory and stats panels: seen with live values. Picking was done through the dev hook, **not by clicking a card: UNTESTED by click**. |
| Chest panel | Opened at a real chest for 30 gold: rarity word, item name, text, item over light rays over the chest, Banish and Take. Taken through the dev hook. |
| Vendor panel | Opened at Dodgy Dan: three priced items, gold shown, Leave. Buying **UNTESTED with the real panel**. |
| Shrine and statue panels | **UNTESTED with the real interface** (worked with the debug interface in section 2). |
| Main menu, character select, map select | Seen and driven by mouse clicks. Squad list, portraits, locked tiles, map rows, best time and ready state show live values. |
| HUD | Run clock, silver, gold, kills, stage timer, next chest price, level, HP bar, weapon and tome rows with icons and levels, quest tracker, minimap with dots and the player arrow, interact prompt, boss bar: all seen with live values. Teammate bars **UNTESTED** (solo). |
| Victory and results | Seen: VICTORY, kills, level, time, boss time, player row with portrait, kills, damage and silver, lobby countdown. |
| Death screen | Seen: title, a joke line, the fallen hero model, Confirm. |
| Pause menu, big map, touch controls | **UNTESTED in play.** |
| Effects | Seen at the right place and a sane size: slash, hit spark, death puff, fire explosion, level-up ring, boss portal swirl and red wind, lantern glow, boomernana trail. Wired but **not seen: lightning, frost ring, rocket, axe, telegraph, shrine burst, chest burst, break puff, elite glint, ghost wisp, embers, dust, heal, magnet, frenzy.** Not wired: pickup glint, poison cloud, revive ring, freeze shatter. |
| Animation | Sword swing measured on the hero: waist twists 38.7 degrees during a slash (0.8 with the overlay off). Cast, throw, land, slide, downed, cheer and portal step **UNTESTED**. Stock idle, run and jump play; **the legs have not been watched**. |
| Sound | 63 roles installed as Sound instances and 625 candidates measured in Studio. **Nothing in this pipeline can hear: every role is unheard.** |
| Run loop | Two full runs in this session: one win through the boss and exit portal back to the lobby, one death back to the lobby. Overtime and the final swarm were run in section 2 only. |
| Multiplayer (2 or 3 players) | **UNTESTED.** No tool here can start a multi-client test. Co-op level-up timeout, per-player panels, tombstone revive, late join, squad scaling and teammate bars have never run with two clients. |
| Saving | **UNTESTED.** Studio refuses DataStore calls in this place ("Studio access to APIs is not allowed"); only the failure path has run. |
| Performance | 340 enemies at 1.62 ms per server tick and 60 fps was measured with placeholder blocks in section 2. **Not re-measured with real meshes, effects and sound.** |
| Touch and gamepad | **UNTESTED on a device.** |

## Not verified (the list to read first)

1. Multiplayer with two or three clients.
2. Every sound: none has been heard.
3. Mint in play; elites and minibosses in this build.
4. Lightning, frost, rocket and axe effects on screen, and the animations other than the swing.
5. Shrine and statue panels, buying from the vendor, clicking an offer card, the pause menu, the big map, touch controls.
6. Boss attacks landing on a hero who can be hurt; balance in general.
7. Saving; performance with the real art; phones and gamepads.

## Debts

- **Fallbacks taken:** one-way push instead of Rojo live sync; effects authored from own textures instead of harvested; hero animation in code instead of authored clips; icons uploaded through Studio instead of Open Cloud. All logged in the ledger (`build-runs/bonk-horde`).
- **Known flaws:** the Bone icon reads as an animal; the knight portrait is pink and the model is silver; a pack still crowds tightly round the hero; the sky has moving clouds but no painted mountains; the chest effect has no beam fan.
- **Before publishing:** turn `HttpService.HttpEnabled` off, delete `ServerStorage.BonkPull`, `ServerStorage.BonkStage` and `Workspace.Staging`, then save. Enable Studio access to API services in Game Settings if saving should be tested in Studio.
- **Not built (declared out of scope in `design/game.json`):** Desert and Graveyard maps, later tiers, quests and unlock shop, weapon evolutions, purchases, leaderboards.

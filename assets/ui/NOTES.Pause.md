# Pause menu and end screens notes (T3)

The in-run pause menu, the death screen and the results were rebuilt in T3
(`bonk-0.22.0-t3`) in the T2 HUD's look. The old one-column pause sheet is gone from
`Overlay.model.json` (removed by a JSON edit, not by regenerating Overlay), and
`Menu_build.py` no longer runs without `--overwrite-anyway`: it would put that sheet back
and overwrite EndScreens.

## Files

| File | What |
|---|---|
| `design/ui_specs/Screens_build.py` | the one source for both screens: builds the trees, writes the models, the manifests and the previews (T2's `Hud_build.py` supplies the look, the node helpers and the renderer) |
| `design/ui_specs/screens_cases.luau` | the preview screens (1080p, 1366x768, notched phone) laid out by `Core/PanelLayout`, and a sample run whose cards, stats and Silver come from `Core/Inspect` and `Core/Progress` |
| `src/ui/Pause.model.json` | the pause menu ScreenGui (DisplayOrder 45: above EndScreens, under Overlay's notice and 3-2-1) |
| `src/ui/EndScreens.model.json` | the death screen and the results |
| `src/shared/Core/PanelLayout.luau`, `Inspect.luau`, `EndVote.luau` | arrangement and scale; what the inspector and stats sheet say; who pressed CONTINUE (specs in `tests/`) |
| `assets/ui/manifest.Pause.json`, `manifest.EndScreens.json` | every named element with its path, class and default `Visible` |
| `assets/ui/mockups/Pause_*.png`, `EndScreens_*.png`, `Screens_sheet.png` | previews over a Wardwood backdrop with the real icons and fonts |

Rebuild from the project root (fonts as in `NOTES.Hud.md`; `--no-png` needs neither them
nor Pillow):

    python design/ui_specs/Screens_build.py --fonts <folder with LuckiestGuy and Fredoka TTFs>

Previews are a guide for layout and colour, not a Studio capture. `pause_layout` and
`end_layout` in the builder mirror `PauseMenuController._layout` and
`MenuController._layoutEnd`; keep them in step.

## Structure

`Pause.Root`: `Scrim`, `Edge` (the amber frame while a co-op world runs), `Safe` (Roblox's
CoreUISafeInsets, as the HUD) holding:

| Element | Holds |
|---|---|
| `Build` | `WeaponRow` / `TomeRow` (four `Slot` sockets each), `ItemGrid` (`ItemTile` per item), `Details` (the inspector card: `IconTile`, `Name`, `Tags.KindTag` / `LevelTag`, `Text`, `Lines` of `Line`, `Note`) |
| `Centre` | `Heading`, `Status` pill, `Sub`, `RunCard`, `Actions` (`PrimaryButton`, `VoteInfo`, `MapButton`, `SettingsButton`, `CancelButton`, `CloseButton`), `SettingsView` (`List`: four slider rows, `DamageNumbersToggle`, `EnemyOutlinesToggle`, `BackButton`), `Hints` |
| `Stats` | `Hero` (name, portrait), `StatList` of `StatSection` (`Title`, `StatRow`: `Name`, `Value`) |
| `Tabs` | `BuildTab`, `StatsTab`, `SettingsTab` (tabs arrangement only) |
| `MapView` | `Map` (`Dots`, `PlayerArrow`, N/E/S/W; MinimapController draws in it), `Legend`, `BackButton` |

`EndScreens`: `DeathScreen` (`Backdrop`, `Safe.Stage`: `DeathTitle`, `DeathJoke`,
`HeroViewport`, `SkipButton`, `AutoBar`) and `Results` (`Backdrop`, `Safe.Panel`:
`ResultTitle`, `Subtitle`, `StatTable` (`Kills`, `Level`, `Time`, `BossTime`, each with
`Label`, `Value`, `Best`), `SilverCard` (`Amount`, `Total`, `Breakdown` of `Part`, `Gain`),
`Squad.PlayerRows` of `PlayerRow` (with `ReadyTag`), `ContinueButton`, `ContinueLabel`).

## Behaviour

- **Solo:** P / Start / PAUSE pauses at once and opens the menu; RESUME, P or B resumes.
- **Co-op:** the same key opens the menu at once while the world keeps running: heading
  GAME STILL RUNNING, the amber edge (it flashes red on a hit), a lighter scrim. REQUEST
  PAUSE is PauseService's vote (cooldown, 60 s limit and 3-2-1 unchanged); ACCEPT when a
  teammate asked; CANCEL REQUEST withdraws. P, B or CLOSE close the menu and keep any
  request or vote. When everyone agrees the open menu becomes the pause (READY n/m). A
  level-up or chest panel that opens while inspecting closes the menu (its clock runs).
- **Inspector:** pointing at, tapping or selecting a tile fills the details card; it stays
  until another tile is chosen (a gold ring marks which). Weapons show the server's own
  numbers, tomes what they have given (`gained`, recorded by the server since T3), items
  their exact totals for flat stats. The stats sheet is the server's resolved block in
  titled sections; Overheal (read by nothing) is left out.
- **Inputs while open:** gamepad B is back, LB / RB move between columns or tabs, X and E
  are swallowed; a mouse press made on the menu is never an attack (PrimaryController).
  Tab or Select opens the menu's map page. Enter presses the main action.
- **End of run:** a wipe shows the death screen for `DeathScreenSeconds` (SKIP sooner); a
  victory goes straight to the results. SKIP and CONTINUE ignore input for
  `EndScreenLockSeconds`, then answer only a fresh press (T1's InputGuard). CONTINUE is
  sent once with the run number; the server (`Core/EndVote`) sends the squad to the lobby
  when every player still here has pressed, or when `EndHoldSeconds + ResultsSeconds` run
  out. Rewards are paid and saved when the run ends, before any of this.
- **Studio:** `endrun` / `endrun win` in Workspace.BonkDev ends a run at once.

## Layout rules

- Three columns (build 560, actions 520, stats 470 design px) wherever the screen keeps
  them at scale 0.6 or more; otherwise a 300 px rail of actions beside BUILD / STATS /
  SETTINGS tabs (`Core/PanelLayout`). At 1080p and 1366x768 every stat fits unscrolled.
- The end screens are one panel each, drawn as large as fits (results 1300x640, death
  900x660 design px, margins included).
- Sizes are offsets set by the controllers; full-screen layers are sized in offsets too,
  so they cover the screen whatever the UIScale does to scale components.

## Checks

Offline only: `rojo build`, `lune run test` (PanelLayout, Inspect, EndVote specs),
`selene src`, `stylua --check src lune`, and a check that every path the controllers bind
exists in the models. Nothing here was run in Studio by Claude.

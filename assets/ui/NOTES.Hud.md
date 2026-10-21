# Hud notes (T2)

The in-run HUD was rebuilt in T2 (`bonk-0.21.0-t2`). The old pipeline (`Hud_gen.py`,
`Hud_post.py`, the roblox-ui skill's `ui_build.py`) is gone: running it would have
overwritten this HUD.

## Files

| File | What |
|---|---|
| `design/ui_specs/Hud_build.py` | the one source: builds the tree, writes the model, the manifest and the previews |
| `design/ui_specs/hud_cases.luau` | the preview screens (1080p, 1366x768 laptop, notched phone), laid out by the game's own `Core/HudLayout` through Lune |
| `src/ui/Hud.model.json` | the shipped ScreenGui |
| `src/shared/Core/HudLayout.luau` | scale, compact mode, top-bar rise and touch-button clearance; specs in `tests/HudLayout.spec.luau` |
| `assets/ui/manifest.Hud.json` | every named element with its path, class and default `Visible` |
| `assets/ui/mockups/Hud_play.png`, `Hud_boss.png`, `Hud_levelup.png`, `Hud_phone.png`, `Hud_sheet.png` | previews over a Wardwood backdrop with the real icons and fonts |

Rebuild from the project root:

    python design/ui_specs/Hud_build.py --fonts <folder with LuckiestGuy and Fredoka TTFs>
    rojo build default.project.json -o work/tmp/t2-check.rbxlx

`--no-png` writes the model only (no Pillow, Lune or fonts needed). The fonts are Google
Fonts (`LuckiestGuy-Regular.ttf`, Apache; `Fredoka[wdth,wght].ttf`, OFL, drawn at
SemiBold for Fredoka One); they are not in the repo. Previews are a guide for layout and
colour, not a Studio capture: Roblox's text metrics and strokes differ in detail.

## Structure

`HurtFlash`, `DownedOverlay` and `Letterbox` stay full-screen children of the ScreenGui.
Everything else sits in `Safe`, which `HudController._layout` places over Roblox's
`CoreUISafeInsets` (UiKit's inset probes) at the scale `Core/HudLayout` picks:

| Cluster | Holds |
|---|---|
| `Safe.TopLeft` | `Vitals` (`LevelBadge`, `Bars.ShieldBar`, `Bars.HPBar`, `Bars.XPBar`), `Purse` (gold, `NextChest`, silver, kills), `QuestTracker`, `TeammateBars` |
| `Safe.TopCenter` | `TimerPlate` (`TimerCaption`, `StageTimer`, `RunClock`), `DifficultyPill`, `BossBars`, `Banner`, `Toast` |
| `Safe.TopRight` | `Minimap` (MinimapController reads its size for the radius) |
| `Safe.BottomCenter` | `InteractPrompt` over `BuildTray` (`ItemStrip`, `Loadout.WeaponRow`, `Loadout.TomeRow`) |
| `Safe` | `PickupToast`, `LevelUpText`, `StageTitle` |

Every contract name is kept; the paths changed (see `design/ui_contract.md`). New names:
`Safe`, the four clusters, `Vitals`, `LevelBadge`, `LevelCaption`, `Bars`, `HPBar.Trail`,
`Purse` and its chips, `TimerPlate`, `TimerCaption`, `Header` (objectives, team),
`HPBack.ShieldFill`, `Main.Back.Trail`, `Banner.Band/RuleTop/RuleBottom`,
`Toast.PortraitBack`, `BuildTray`, `Loadout`, `Divider`, `KeyCap.Key` (was a sibling).

## Layout rules

- The left column always starts under Roblox's top bar. The timer plate and the minimap
  may rise into the bar where `GuiService.TopbarInset` reports that span free; whatever
  is stacked under the plate still starts below the bar. `Hud:SetAttribute("BonkTopbarRise",
  false)` (on PlayerGui's copy) turns the rise off.
- Scale: the plain 1920x1080 fit, raised to at least 0.6 so a 20 px label stays 12 px,
  capped where the layout still fits the safe area; times 1.08 to 1.25 for a larger
  `PreferredTextSize`, 1.15 on a TV. Compact arrangement (narrower column, 160 px minimap,
  one item row with a `+N` tile, two objectives) only when it lets the HUD be drawn larger.
- On touch, the minimap steps left of the Overlay's Tab and Pause buttons if it would cover them.
- Text is fixed-size (no `TextScaled`) except banner, stage and boss names, which shrink to fit.

## Look

Moss panels `#16231B` at 0.2 to 0.32 transparency, a 1.5 px gold rim `#D9B85C`, 10 to 14 px
corners, a soft top-to-bottom shade. HP `#F2554D` with a pale trail, shield ice `#9EE6F7`,
XP gem blue `#45A3FF` (the gems' colour), gold `#FFCB45`, captions tan `#D9B45A`. Weapon
tiles have gold rims, tome tiles teal, item tiles their rarity colour. LuckiestGuy for
numbers and titles, Fredoka One for captions and body text.

## Checks

Offline only: `rojo build`, `lune run test` (HudLayout specs), `selene src`, `stylua --check`,
and a path check that every element HudController and MinimapController bind exists in the
model. Nothing here was run in Studio by Claude; see the T2 commit for the playtest list.

# Hud notes (T2; the top of the screen redone on the T6/T7 line)

The in-run HUD was rebuilt in T2 (`bonk-0.21.0-t2`). On the T6/T7 line (`bonk-0.24.0-t6t7`)
XP moved to a strip along the top of the screen, every top-centre element went into one
column, and the strip wears a rainbow while a level-up waits for the player's choice. After
the playtest (`bonk-0.26.0-ux`) the strip spans the whole screen, edge to edge, just under
Roblox's bar, and the HUD steps aside for the end screens. The old pipeline (`Hud_gen.py`,
`Hud_post.py`, the roblox-ui skill's `ui_build.py`) is gone: running it would have
overwritten this HUD.

## Files

| File | What |
|---|---|
| `design/ui_specs/Hud_build.py` | the one source: builds the tree, writes the model, the manifest and the previews |
| `design/ui_specs/hud_cases.luau` | the preview screens (1080p, 1366x768 laptop, notched phone), laid out by the game's own `Core/HudLayout` through Lune |
| `src/ui/Hud.model.json` | the shipped ScreenGui |
| `src/ui/XpBar.model.json` | the XP strip's own ScreenGui (DisplayOrder 21, over the level-up panels) |
| `src/shared/Core/HudLayout.luau` | scale, compact mode, the XP strip, where each column starts, touch-button clearance; specs in `tests/HudLayout.spec.luau` |
| `src/shared/Core/XpStrip.luau` | when the strip wears its rainbow, and its colours as they flow; specs in `tests/XpStrip.spec.luau` |
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
| `Safe.TopLeft` | `Vitals` (`LevelBadge`, `Bars.ShieldBar`, `Bars.HPBar`), `Purse` (gold, `NextChest`, silver, kills), `QuestTracker`, `TeammateBars` |
| `Safe.TopCenter` | one column: `TimerPlate` (`TimerCaption`, `StageTimer`, `RunClock`), `LevelUpText`, `DifficultyPill`, `BossBars`, `Banner`, `Toast`, `PickupToast` |
| `Safe.TopRight` | `Minimap` (MinimapController reads its size for the radius) |
| `Safe.BottomCenter` | `InteractPrompt` over `BuildTray` (`ItemStrip`, `Loadout.WeaponRow`, `Loadout.TomeRow`) |
| `Safe` | `StageTitle` |
| `XpBar.Strip` (own ScreenGui) | `Back`, `Fill` (`Shine`), `Rainbow` (`Gradient`) |

Every contract name is kept; the paths changed (see `design/ui_contract.md`). New names:
`Safe`, the four clusters, `Vitals`, `LevelBadge`, `LevelCaption`, `Bars`, `HPBar.Trail`,
`Purse` and its chips, `TimerPlate`, `TimerCaption`, `Header` (objectives, team),
`HPBack.ShieldFill`, `Main.Back.Trail`, `Banner.Band/RuleTop/RuleBottom`,
`Toast.PortraitBack`, `BuildTray`, `Loadout`, `Divider`, `KeyCap.Key` (was a sibling).

## Layout rules

- The XP strip spans the whole screen, from its left edge to its right, 4 design px under
  Roblox's top bar (`CoreUISafeInsets.top`), 14 px thick (16 compact). Its ScreenGui
  ignores every inset (`ScreenInsets` None), so the strip is `UDim2(1, 0)` wide from x 0:
  centred by construction at any size and scale. It carries no text, so a phone's
  rounded corners or cut-out can only trim its very ends. (It used to sit in the free part
  of the top bar beside Roblox's buttons, which left it short and off-centre.)
- Every column starts under the strip: left column and timer plate one gap below it, the
  minimap far enough down that its compass letters clear it.
- The HUD and the strip are hidden in the lobby and behind the end screens (Victory, Wipe,
  Results: the death screen and the results take the whole screen).
- The top centre is one list: plate, LEVEL UP!, overtime pill, boss bars, banner, toast,
  pickup popup. Nothing there is placed by a share of the screen any more, so nothing can
  cover anything else; LEVEL UP! sits right under the plate, above the level-up panel. The
  co-op pause notice (Overlay) is placed under the column (`HudController:TopBottom`).
- The timer plate is 76 tall: the caption keeps to its top 22 px and the digits' box starts
  at 30, because LuckiestGuy's digits stand taller than their line and used to cover it.
- Scale: the plain 1920x1080 fit, raised to at least 0.6 so a 20 px label stays 12 px,
  capped where the layout still fits the safe area; times 1.08 to 1.25 for a larger
  `PreferredTextSize`, 1.15 on a TV. Compact arrangement (narrower column, 160 px minimap,
  one item row with a `+N` tile, two objectives) only when it lets the HUD be drawn larger.
- On touch, the minimap steps left of the Overlay's Tab and Pause buttons if it would cover them.
- Text is fixed-size (no `TextScaled`) except banner, stage and boss names, which shrink to fit.

## Look

Moss panels `#16231B` at 0.2 to 0.32 transparency, a 1.5 px gold rim `#D9B85C`, 10 to 14 px
corners, a soft top-to-bottom shade. HP `#F2554D` with a pale trail, shield ice `#9EE6F7`,
XP gem blue `#45A3FF` (the gems' colour; a full gold strip at LVL MAX), gold `#FFCB45`, captions tan `#D9B45A`. Weapon
tiles have gold rims, tome tiles teal, item tiles their rarity colour. LuckiestGuy for
numbers and titles, Fredoka One for captions and body text.

## The level-up rainbow

The strip's `Rainbow` shows from the moment an upgrade offer reaches the player until the
last level-up waiting for their choice is answered: the server's count (`levelUps` in
PlayerState, kept by UpgradeService) or an offer open on the client (ChoiceController
`HasOffer`, `OfferChanged`). Refresh and Banish re-deal the offer and keep it; a panel
opened over the offer keeps it; a 0.3 s hold stops a blink between two queued offers; the
run ending turns it off at once; a finished build never shows it. It fades in over 0.2 s
and out over 0.5 s; while it shows, its colours flow along the strip (one turn in 2.4 s,
the gradient redrawn 30 times a second, nothing rebuilt) and the strip's rim breathes gold
to white. LEVEL UP! itself still goes after 1.6 s.

## Checks

Offline (T2): `rojo build`, `lune run test` (HudLayout specs), `selene src`, `stylua --check`,
and a path check that every element HudController and MinimapController bind exists in the
model. Nothing here was run in Studio by Claude; see the T2 commit for the playtest list.

Run in Studio by Claude for the top-of-screen pass (one player, a disposable place built
from disk, 1593x792 and the iPhone 16 Pro simulator): the plate's caption clear of the
digits; the strip then beside Roblox's buttons; LEVEL UP! above the level-up panel; the rainbow
through two queued offers without a blink, through REFRESH and BANISH clicked on the panel,
off with a fade after the last pick and at once when the run ended under an open offer;
plate, pill, boss bar, four miniboss bars and a banner stacked without overlap; LVL MAX
full and gold; the strip hidden on Skyhold and under the intro's letterbox.

Run in Studio by Claude for the full-width strip (`bonk-0.26.0-ux`, one player, 1593x752):
the strip measured from x 0 to 1593 (the whole viewport) at y 60.6 to 70.3, under the 58 px
bar; its blue fill, the rainbow over the level-up panel and the gold LVL MAX strip all edge
to edge; nothing under it overlapping.

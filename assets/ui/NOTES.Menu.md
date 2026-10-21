# NOTES: Menu, EndScreens, Overlay

> **T3 (`bonk-0.22.0-t3`):** the pause menu is now its own ScreenGui, `Pause`, and
> EndScreens is built by `design/ui_specs/Screens_build.py`; see `NOTES.Pause.md`. The
> old pause sheet was removed from `Overlay.model.json` and EndScreens' old specs,
> builder and mockups are deleted. What follows describes the original Menu, EndScreens
> and Overlay build and is history for EndScreens and the pause sheet.

Built by `design/ui_specs/Menu_build.py` (run with `D:\Forge\system\python\python.exe`).
One run writes the 8 spec files, the 8 mockups, the 3 `.model.json`, the 3 Luau
builders and `assets/ui/manifest.Menu.json`, then runs `verify_ui` and a contract
name check.

## Checks

- `rojo build default.project.json -o work/ui-check-menu.rbxl`: passes.
- Contract check (every name in the three contract tables, its class, its default
  `Visible`): all present, none renamed.
- Luau builders run under Lune and compared with the rojo-built place, node by node
  (class, name, Visible, ZIndex, Size, Text, font family, IconName):
  Menu 867 nodes, EndScreens 174, Overlay 196, 0 differences.
  They have NOT been run in Studio.

## verify_ui.py verdict per screen

Layout checks (sibling_overlap, sibling_gap, off_centre, wrapper_box, overflow,
stroke_mix, rotated_clip, grid_aspect) are clean on all 8 screens. Every remaining
failure is a phone size floor or a control zone.

| Screen | stock verdict | without the 640x360 device |
|---|---|---|
| Menu.MainMenu | 19 fail (text_fit) | 0 |
| Menu.CharacterSelect | 63 fail (40 text_fit, 23 touch_target) | 31 |
| Menu.MapSelect | 32 fail (30 text_fit, 2 touch_target) | 7 |
| EndScreens.DeathScreen | 3 fail (2 text_fit, 1 touch_target) | 0 |
| EndScreens.Results | 15 fail (text_fit) | 4 |
| Overlay.BigMap | 6 fail (text_fit) | 0 |
| Overlay.PauseMenu | 7 fail (4 text_fit, 3 touch_target) | 0 |
| Overlay.TouchControls | 4 fail (3 safe_zone, 1 touch_target), 1 warn | 3 |

Why they remain:

- **640x360 floor.** The contract fixes a 1920x1080 design, so the checker's smallest
  device scales it by 0.333: it wants 132 px buttons and 33 px text. Buttons here are
  116 px and body text 30 px, which pass on the 896x414 phone (scale 0.383) and up.
  Meeting the 640x360 floor would break the reference proportions.
- **Character tiles** (31 of the remaining fails): the contract fixes 126 px tiles
  with the name under each, which leaves a 22 px name (8 pt on a phone).
- **20-character player names** (8 fails) shrink to about 26 px in SquadRow-sized
  boxes; shorter names are at 30 px.
- **MapRow.Blurb** (24 px, three lines) and the two longest ability texts (25 to 27 px).
- **TouchControls safe_zone**: JumpButton, SlideButton and InteractButton sit in the
  checker's "Roblox jump button" zone on purpose. The game must hide Roblox's own
  jump button on touch. The top-bar warning on InteractButton is an artefact of the
  checker re-resolving offset positions at 640x360.

## What the skill's spec language could not express, and what was done

All of these are applied in `Menu_build.py` in a wrapper round `ui_build.to_instances`,
so the model and the Luau still come from the same node.

1. **Per-element font.** The skill has one font per theme and does not know
   LuckiestGuy. Spec key `font` sets `FontFace` on the label or button caption.
   There is no LuckiestGuy TTF on this PC, so **the mockups draw titles and numbers
   in Fredoka**; the shipped trees carry LuckiestGuy. LuckiestGuy draws lower case
   as capitals, so title labels are fit-checked on the upper-cased text too.
2. **ViewportFrame.** Spec key `cls` (used for `HeroViewport`). The mockup draws an
   outlined placeholder.
3. **Root shape.** `ui_build.build_root` wraps everything in a `CanvasFrame` with a
   `UIScale` and sets `Enabled` by page kind. The contract wants the screens as direct
   children of the ScreenGui, `Enabled=true`, `IgnoreGuiInset=true`, and adds its own
   UIScale at runtime, so the ScreenGui is built directly with **no CanvasFrame and no
   UIScale**.
4. **Panel children.** The skill puts a panel or button's content inside an inner
   `Face` frame. A `hoist` pass lifts it out so the bound names are direct children
   (`DetailCard.CharacterName`, `PortraitTile.Focus`). Face is the same rectangle as
   its parent, so nothing moves; ZIndex is raised by 2 to stay above the Face.
5. **Luau builder.** `ui_build.luau` declares one local per instance and Luau allows
   200 per function; Menu has 867. `luau_scoped` emits the same statements with one
   do-block per instance, and fixes the skill's `Font` value, which always emitted
   FredokaOne.
6. **Icon attributes.** The skill adds a `PendingIcon` attribute next to `IconName`;
   only `IconName` is shipped. `Image` is left out of the `.model.json` (the skill
   strips Content properties for Rojo), which leaves it empty.
7. **Hidden elements in mockups.** The skill draws `visible:false` nodes. Here the
   mockup hides them unless the node says `mockShow` (the screens themselves, the
   first tile's `Focus`, `UnlockButton`, `LockTag` on the two locked maps).
8. **Icon placeholders.** Mockup only: a tinted tile with two letters of the key.
9. **Clipping.** Spec key `clips` sets `ClipsDescendants` on `BigMap.Dots`. Nothing
   rotated sits inside it.

## Decisions to know about

- **Scale sizes.** Each screen Frame is `Size 1,0,1,0`; `MainMenu`, `CharacterSelect`,
  `MapSelect`, `DeathScreen`, `Results`, `PauseMenu` and `TouchControls` are full
  screen, `BigMap` is the 760 px square itself. Everything inside is offset sized
  and anchored by scale position, except the builder's own Shadow, Face and caption
  frames (`1,0,1,0` of an offset parent) and slider `Fill` (scale width, as the
  contract allows for fills). `DeathScreen` and the `Results` and `PauseMenu` scrims
  are black fills on the screen Frame, so they only cover the screen if the runtime
  UIScale leaves a `1,0,1,0` child full size.
- **Background panels are siblings, not parents.** `ListPanel` (both selection
  screens) and `Panel` (Results, PauseMenu) are decoration; `CloseButton`,
  `CharacterGrid`, `MapList`, `ResultTitle`, `ResumeButton` and the rest are direct
  children of the screen Frame, drawn over it.
- **Dynamic labels ship sample text**, as contract rule 5 says, not the skill's
  `<unbound>` sentinel. The skill's dead-label gate therefore cannot be used on these.
- **Classes the contract left open:** `SilverTotal`, `RunCount`, `Highscore` and
  PlayerRow `Silver` are TextLabels with a child ImageLabel `Icon`. `ReadyTag`,
  `HostTag` and `LockTag` are Frames with a child TextLabel `Text`. `LogoBanner` is a
  Frame (Rotation -5) holding `Lip`, `Strip` and `Strip.Wordmark`. `UnlockButton` and
  `DamageNumbersToggle` have a child TextLabel `Label` and no builder caption.
  `Focus` is a Frame of eight white `Bracket` frames.
- **CharacterGrid ships 20 children**: 3 `PortraitTile` (Sir Clonk, Zib, Mint) and 17
  `LockedTile`, to match the reference; the code deletes them all anyway.
- **New icon keys not in `design/ui.json`:** `ThumbMossyWoods`, `ThumbDesert`,
  `ThumbGraveyard` (MapRow `Thumb`). The contract asks for a thumb icon and lists no
  key. `LogoBanner` and `IconRivet` from `ui.json` `frames` are not used: both are
  built procedurally.
- **Not built, because the contract tables do not list them:** `SettingsButton` on the
  main menu, `SilverTotal` on the selection screens, a tier table, Results
  `PlayAgainButton` / `LobbyButton` / `SilverEarned` (all appear only in `ui.json`).
- **Extra names added:** `SquadTitle`, `ListPanel`, `PortraitWell`, `ScoreBox`,
  `HighscoreCaption`, `BestTimeCaption`, `ReadyTitle`, `Panel`, `ColumnHeads`,
  `MusicLabel`, `SfxLabel`, `SensitivityLabel`, `LegendItem`, `Rivet`, `Bracket`.
- **Map names and blurbs** for the two locked maps ("Dusty Dunes", "Spooky Yard") and
  the death joke are placeholder copy.
- **Gradient.** The shared theme lightens the top by 14% of value (the skill's
  default), not the contract's 8%; kept so these match the other ScreenGuis.
- **Button sizes.** CONFIRM, READY, RESUME and the close buttons are 116 px tall for
  touch, larger than the reference's 62 px. The close button sits proud of the panel
  corner.
- The Luau builders live in `design/ui_specs/*.build.lua`, which is outside the
  file list given in the brief (`src/ui` would have synced them into StarterGui).

## Known drift: the Overlay pause sheet (checked 2026-10-16; superseded by T3)

Since T3 `Menu_build.py` refuses to run unless given `--overwrite-anyway`: it would put
the old pause sheet back into Overlay, overwrite EndScreens and drop the features below.
The sheet's settings (Master, Music, SFX, sensitivity, damage numbers, enemy outlines)
live on in the Pause ScreenGui's `SettingsView`; the pause notice and the 3-2-1 stay in
Overlay.

`Menu_build.py` is behind `src/ui/Overlay.model.json`. M2.A (`bonk-0.5.x-m2a`) built the
pause sheet's Master slider, pause notice and 3-2-1 countdown straight into the model
JSON, and re-laid the sheet out, without updating the generator. Running
`Menu_build.py` + `tools/ui/bake_icons.py` + `tools/ui/fix_strokes.py` today rewrites
`Overlay.model.json` and `Menu.model.json` and **drops those features**, so do not
regenerate them until the generator has caught up. Until then, additions to the pause
sheet are made in `OverlayController` from the existing elements: the "Enemy outlines"
row (M3.B) is a runtime copy of `DamageNumbersToggle`, placed below it.

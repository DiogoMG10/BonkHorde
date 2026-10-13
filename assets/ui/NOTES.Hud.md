# Hud notes

## Files

| File | What |
|---|---|
| `src/ui/Hud.model.json` | the shipped tree |
| `design/ui_specs/Hud_gen.py` | spec generator; writes `Hud.json` (full) and `Hud_<state>.json` (mockup subsets of the same nodes) |
| `design/ui_specs/Hud_post.py` | post-processor: raw `ui_build.py` model -> shipped model, Luau builder, manifest, contract check |
| `design/ui_specs/Hud.lua` | Luau builder, emitted from the same final tree as the model. Not run (no Studio in this stage) |
| `assets/ui/mockups/Hud_play.png`, `Hud_swarm.png`, `Hud_stage.png`, `Hud_downed.png`, `Hud_levelup.png` | mockups, one per play state |
| `assets/ui/manifest.Hud.json` | every named element with class and default Visible; every icon key with the paths using it |

Rebuild (from the project root, `PY` = `D:\Forge\system\python\python.exe`, `S` = the roblox-ui skill's `scripts` folder):

    PY design/ui_specs/Hud_gen.py
    PY S/ui_build.py design/ui_specs/Hud.json --out <tmp> --model
    PY S/ui_build.py design/ui_specs/Hud_<state>.json --out assets/ui/mockups --icons <placeholder icons> --png
    PY design/ui_specs/Hud_post.py <tmp>/Hud.model.json . S
    rojo build default.project.json -o work/ui-check-hud.rbxl

## Validation

- `rojo build default.project.json -o work/ui-check-hud.rbxl`: passed.
- Contract check in `Hud_post.py` (27 top-level names with class and default Visible, their required children, 12 sample/child templates, `IconName` on every ImageLabel, no `Image`, `HurtFlash` transparency 1, `Rainbow` hidden with a UIGradient): 0 failures.
- `verify_ui.py design/ui_specs/Hud.json`: **75 fail, 8 warn**. No overlap, gap, off-centre, overflow, stroke-mix or shrink-ratio finding. All of it is two things:
  - **75 x `text_fit`, all "under the 11pt legibility floor on phone-small"**. The checker scales the 1920x1080 page to a 640x360 phone (x0.33), so any text under 33 px at the reference fails. The contract fixes these sizes from the desktop reference (30 px bars, 50 px icons with a level under them, 48 px item sprites, a 26 px compass letter, a 30 px boss bar). Nothing shrinks below its designed size at 1920x1080. Not fixable without leaving the contract layout; on a small phone this HUD text is small. Labels affected: `Level`, `Count`, `Name`, `DownedTag`, `N/E/S/W`, bar `Text`, quest `Text`, `Key`, prompt `Text`, `BannerSub`, `StageJoke`, `ToastTitle`, `ToastText`, `TierName`, `TierMult`, stat counts.
  - **8 x `wrapper_box` warnings**: `HPBack`/`HPFill` (3), `Back`/`Fill` (4), `ReviveBack`/`ReviveFill` (1). These are bar tracks with a scale-width fill as the only child, which is what the contract asks for.
- Dead-label gate (`verify_labels.py`) not applicable: contract rule 5 asks for realistic sample text, so no label carries the `<unbound>` sentinel. This is the opposite of the skill's placeholder rule; the contract was followed.

## Names

No contract name was changed. Names added (not in the contract):

- `Icon` under `RunClock`, `SilverCount`, `GoldCount`, `KillCount`, `TierMult`: the icon is a child of its TextLabel, hanging off the left edge, so hiding or moving the label takes the icon with it.
- `Tile` in `LoadoutSlot` (the dark rounded slot behind `Icon`).
- `Field` in `Minimap` (the navy disc). `Ring` is a tan disc with the dark stroke behind `Field`, so 6 px of it shows as the rim; it is not a bare UIStroke.
- `KeyCap` in `InteractPrompt` (the grey keycap; `Key` is the TextLabel on top of it).
- `RuleTop`, `RuleBottom` in `StageTitle`; four `Rivet` frames in `Toast`.

Structure: all 27 top-level names are direct children of the ScreenGui. There is no `CanvasFrame` and no `UIScale` (see below).

## Fonts and corners

- LuckiestGuy (46 labels): every number, name and title. Text stroke 3 px on the large ones (stat row, timer, level, banner, stage name, level up, downed), 2 px on small ones.
- FredokaOne (6 labels): `QuestLine.Text`, `InteractPrompt.Text`, `BannerSub`, `StageJoke`, `ToastText`.
- Corner radius: panels (`Toast`, `InteractPrompt`) 12 px; cards, slots, bar tracks and fills, `QuestLine`, `KeyCap` 8 px; `DifficultyPill` 19 px (full pill); teammate HP bar 7 px (full pill); checkbox `Box` 6 px; `MapDot` 3 px; minimap discs and rivets 50%; `XPBar`, `Letterbox`, `DownedOverlay`, `HurtFlash` 0.
- Frame stroke 3 px `#101512` everywhere a frame has one. Fills, `MapDot`, rules, rivets and full-screen frames carry none.

## Not expressible in the skill's spec language (done in `Hud_post.py`)

1. Per-element font. `ui_build.py` has one font per theme.
2. The contract's flat structure. `ui_build.py` always wraps the page in `CanvasFrame` + `UIScale`; both removed, since the game adds its own UIScale.
3. Runtime-tintable frames. `ui_build.py` ships a frame as white + a coloured UIGradient, and UIGradient multiplies BackgroundColor3, so a controller writing a colour would get it multiplied by the old one. Every coloured Frame now ships as `BackgroundColor3 = colour` plus a neutral gradient (white at the top to 92% grey at the bottom). The spec colours were authored as the same two stops, so the mockup shows the same result. `Letterbox` bars, `DownedOverlay` and `HurtFlash` have no gradient.
4. Vertical UIListLayout alignment. `ui_build.py` emits `VerticalAlignment = Center` for every list while its preview packs a vertical list from the top. Fixed to Top/Left on `QuestTracker` and `TeammateBars`.
5. `ItemStrip` wrapping: `UIListLayout.Wraps = true`, `VerticalAlignment = Bottom`, so a second row grows upward from y 1015. The mockup only shows one row.
6. `Rainbow`'s seven-step UIGradient; `ClipsDescendants` and a UICorner on `Dots`.
7. `PendingIcon` attribute removed; `IconName` kept.

## Limits and risks for the wiring stage

- **`Dots` clips to its square, not to the circle.** ClipsDescendants ignores UICorner. A `MapDot` in a corner of the square shows outside the ring unless the code culls by radius (114 px).
- **Mockup font.** No LuckiestGuy TTF on this PC, so the PNGs draw every label in Fredoka One. Glyph widths in Studio will differ; labels are TextScaled with a size cap, so they shrink rather than overflow.
- **Mockup icons** are coloured placeholder discs with two letters; shipped ImageLabels have no Image.
- **`Rainbow` is in no mockup** (the renderer cannot draw a multi-stop gradient).
- **Roblox top bar.** With `IgnoreGuiInset = true` the stat row (y 43 to 77) and `Toast` sit where Roblox draws its own menu and chat buttons top-left, and `LevelLabel`/`Minimap` sit where the player list appears top-right. The positions are the contract's; the game needs to hide the player list or accept the overlap.
- **Bars are 8 px apart, not flush**: `ShieldBar` y 95, `HPBar` y 133 (contract: directly under at 125), which moves `WeaponRow` to 171, `TomeRow` to 241, `QuestTracker` to 311. Done for ground rule 8.
- `LoadoutSlot.Level` overlaps the bottom 8 px of the icon, as in the reference; declared as an overhang.
- `QuestLine` is a fixed 320 px wide, not sized to its text. Sample 1 is not done (`Check` hidden, white `Box`); sample 2 is done (green `Box`, dark-green line) to show the look.
- `Fill`, `HPFill`, `ReviveFill` use X scale width; every other size is offset. Full-screen and full-width frames (`XPBar`, `Letterbox`, `DownedOverlay`, `HurtFlash`) use scale 1.
- `TeammateBars` ships visible with three samples; `DownedTag` hidden in each.
- Nothing was rendered in Studio. Font metrics, the wrapped item row and stroke weight are unverified there.

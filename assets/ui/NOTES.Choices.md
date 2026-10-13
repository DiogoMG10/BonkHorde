# NOTES: ScreenGui `Choices`

Built by `design/ui_specs/Choices_build.py` (run with `D:\Forge\system\python\python.exe`).
It imports the roblox-ui skill's `ui_build.py` and emits every output from one generator:

- `src/ui/Choices.model.json` (shipped tree, 970 instances)
- `design/ui_specs/Choices.lua` (Luau builder, same tree)
- `design/ui_specs/Choices.json` (shipped spec) and `Choices_<State>.json` (mockup specs)
- `assets/ui/mockups/Choices_UpgradeOffers.png`, `_ChestPanel`, `_ShrineOffers`, `_ShopPanel`, `_StatueOffers`
- `assets/ui/manifest.Choices.json`

Running plain `ui_build.py` on the spec JSONs does NOT reproduce the shipped tree: the
spec uses extra keys that only `Choices_build.py` applies (see below).

## Checks

- `rojo build default.project.json -o work/ui-check-choices.rbxl`: passes.
- `Choices.lua` compiles (checked with lune `luau.compile`). Not run in Studio.
- Contract check inside the build script: 91 name/class paths, the five ScreenGui
  properties, default Visible, and IconName/empty Image on every ImageLabel: 0 problems.
- Nothing here has been rendered in Studio. Fonts, gradients and AutomaticSize rows
  are unverified against the real renderer.

## verify_ui.py verdict

Every spec reports failures, and all of them are one of two kinds. There are no
overlap, off-centre, overflow, wrapper-box or shrink-ratio failures.

| Spec | fail | warn |
|---|---|---|
| Choices.json (shipped) | 208 | 3 |
| Choices_UpgradeOffers.json | 314 | 34 |
| Choices_ChestPanel.json | 262 | 34 |
| Choices_ShrineOffers.json | 269 | 34 |
| Choices_ShopPanel.json | 334 | 34 |
| Choices_StatueOffers.json | 280 | 34 |

(The mockup specs count higher because they carry 31 stat rows and 12 to 28 items.)

1. `text_fit`, "under the 11pt legibility floor on phone-small": the checker scales the
   1920x1080 reference to a 640x360 phone (x0.33), so any text under 33 px fails. The
   contract fixes StatRow at about 20 px and the cards at 630x145, so stat rows (6pt),
   slot levels, counts, rarity tags, stat lines, descriptions and button captions all
   fail. Not fixable without leaving the contract's measurements. On 1920x1080 nothing
   is shrunk below its designed size.
2. `touch_target`: the footer buttons are 56 px tall (19pt on that phone; the checker
   wants 132 px). The reference footer strip is about 95 px tall. Cards and rows are
   large enough and pass.
3. Warnings: `sibling_gap`, StatRow/StatGap 1 px apart. 31 rows of 20 px plus 4 gaps of
   12 px in a 720 px list leaves 1 px between rows (702 px used).

If phones are a target, these panels need a separate decision; this file does not hide it.

## Departures from the skill, and why

- **Sentinel rule not followed.** The skill wants dynamic labels to ship `<unbound>`;
  contract rule 5 wants realistic sample text. Contract followed, so `verify_labels.py`
  has nothing to gate on here. Longest strings are declared as `samples` for text fit.
- **No CanvasFrame, no UIScale.** The skill wraps everything in `CanvasFrame` with a
  `UIScale`. The contract says top-level screens are Frames inside the ScreenGui and
  the game adds its own UIScale, so both are removed and the eight panels are direct
  children of `Choices`. `RefWidth`/`RefHeight` attributes are kept on the ScreenGui.
  The other ScreenGuis should agree on this.
- **Named children hoisted out of `Face`.** The skill puts a panel's or button's
  children inside its `Face` frame. They are moved up so `BanishButton.Count`,
  `InventoryPanel.WeaponSlots` and so on are direct children, as the contract reads.
  Each panel and lipped button still has `Shadow` and `Face` decoration children.

## Could not be expressed in the spec language (added by the build script)

- Per-element font (`font: LuckiestGuy`). The skill has one font per theme.
- TextButton as a card root with its own recolourable BackgroundColor3 (`as`, `paint`):
  OfferCard, ShopCard, ItemCard, RewardRow, IgnoreRow, plus IconTile and the chest
  light rays. These carry the real colour under a neutral white-to-90% gradient, so
  the game can write BackgroundColor3 directly. The chest `Ray` frames have no gradient.
- RichText (`rich`) on `RewardRow.Text`.
- Self-sizing labels (`autoX`): StatLine's `Label`/`From`/`Arrow`/`To` and
  `PriceTag.Price` use AutomaticSize X with a fixed TextSize inside a horizontal
  UIListLayout, so they pack whatever text the code writes.

## Mockup is not exact in these places

- LuckiestGuy is not installed on this PC. Mockups draw those labels in Fredoka,
  capitalised. Real glyph widths will differ.
- Icons are coloured placeholder discs with two letters.
- `RewardRow.Text` is drawn plain; the green number only exists in the shipped rich text.
- Hidden parts are left out of the picture: `Focus` is drawn on one card per panel,
  `SoldTag` on none, and each OfferCard shows either `Lines` or `Description`.
- Mockups show 31 stat rows and 12 items (28 in the shop mockup); the shipped tree has
  sample children only.

## Skill defects hit

- UIListLayout alignment: the PNG applies `align` along the fill direction, the emitter
  wrote it to HorizontalAlignment and always centred vertically. A top-aligned vertical
  list would have shipped vertically centred. The build script emits what the PNG draws.
- Text strokes were emitted with ApplyStrokeMode=Border, which outlines the label's
  rectangle. Changed to Contextual under every TextLabel. Unverified in Studio.
- The Luau builder declared one `local` per instance (limit 200). Rewritten to a table.
- The Luau builder hardcoded FredokaOne for every FontFace. Patched to use the real family.

## Names

No contract name was changed. Names added that the contract does not list:

- `Footer` (Frame) in UpgradeOffers, ChestPanel, ShopPanel, StatueOffers. The buttons,
  `ChoiceTimer` and `GoldLabel` are children of `Footer`, not of the panel. Code that
  indexes `UpgradeOffers.BanishButton` directly will miss; use a recursive find or
  `Footer.BanishButton`.
- `Header` with child `Title` on each titled panel; `Rivet` x4 per panel.
- `ShrineOffers.Intro` (the "The shrine offers you a reward:" line).
- `RewardRow.RarityBox` (the box behind `RarityTag`; it is not recoloured with the tag).
- `IgnoreRow.Label`.
- `Focus` also exists on ShopCard, ItemCard (hidden), with children `TLH TLV TRH TRV BLH BLV BRH BRV`.
- `LevelUpFx.RayBurst` holds 6 rotated `Ray` frames (12 rays); `Stage.LightRays` holds 8.
- ImageLabels also carry the skill's `PendingIcon` attribute next to `IconName`.

## Layout choices to know about

- InventoryPanel is 504x668 (reference about 500 tall) so `ItemGrid` holds 4 rows of 7.
  A 29th item would overflow the panel.
- ShrineOffers is 824 wide, as in the reference still, not the 744 of the other centre panels.
- Sample children shipped: 4 InvSlot per row, 3 InvItem, 3 StatRow + 1 StatGap, 3 cards
  per list, 2 StatLine per OfferCard (1 in the third).
- In sample OfferCards, `Description` ships Visible=false where `Lines` is shown, and
  the reverse on the second card. The first card (the template) has `Lines` visible.

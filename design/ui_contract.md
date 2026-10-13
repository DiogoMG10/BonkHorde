# UI contract

What the interface stage must deliver and the exact instance names the game code
binds to. The game's controllers find these by name; a missing or renamed one is
a dead label in play. `design/ui.json` holds the theme and the screen list;
`design/refs/REFERENCE.md` holds the layout measurements; this file is the wiring.

## Ground rules

1. **Layout from the reference, skin from the art direction.** Positions,
   proportions and what each element shows follow `design/refs/REFERENCE.md` and the
   stills in `design/refs/frames/` (1920x1080). The LOOK is cartoon, not the
   reference's pixel art: rounded corners (12 px panels, 8 px cards and buttons),
   3 px dark stroke `#101512`, a soft top-to-bottom gradient (8% lighter at the
   top), chunky buttons with a darker bottom lip, `LuckiestGuy` for titles, names
   and all numbers (with a dark UIStroke so it reads over the world), `FredokaOne`
   for body text. No pixel fonts, no riveted metal frames; a small round rivet in
   each panel corner is the nod to the reference.
2. **Design at 1920x1080 in offset pixels**, anchored by scale to the nearest
   corner, edge or centre (AnchorPoint + scale position + offset size). The game
   adds one `UIScale` per ScreenGui at runtime, so do not use scale sizes.
3. **Five ScreenGuis**, each one `.model.json` in `src/ui/`, each with
   `ResetOnSpawn = false`, `IgnoreGuiInset = true`, `ZIndexBehavior = Sibling`,
   and `Enabled = true`. Top-level screens inside a ScreenGui are Frames that the
   code shows and hides with `Visible`; ship them with the `Visible` value given
   below.
4. **Repeated elements are sample children.** Where a list is filled at runtime
   (cards, slots, rows), put two or three complete sample children in the container,
   each named exactly as the template name given here. At runtime the code clones
   the first one as its template and deletes the samples, so every sample must be
   self-contained and the container must lay its children out by itself
   (UIListLayout or UIGridLayout).
5. **Every dynamic label ships with realistic sample text** (the longest it will
   ever show is given as `max`). The code overwrites it.
6. **Icons are ImageLabels named `Icon` (or as given) carrying a string attribute
   `IconName`** with the icon key (for example `IconGold`, `IconSword`,
   `IconItemLuckyClover`). Leave `Image` empty; the code fills it from the icon
   table at runtime. Size them square. The icon keys are listed in `design/ui.json`
   under `icons`.
7. **Colours.** Use the tokens in `design/ui.json` `theme`: panel fill `#222A25`,
   header `#2E4637`, ink white, tan labels `#D9B45A`, value-up green `#35D04A`,
   XP `#11B4F4`, HP `#E5121B`, shield `#12A8E8`; rarity text and card fills as
   listed there; buttons confirm blue `#2E7FD1`, skip green `#2E9E4C`, banish red
   `#B3263A`, leave grey `#6B6F6B`.
8. **Nothing touches**: 8 px minimum between siblings. Run the skill's
   `verify_ui.py` on every screen and fix what it reports.
9. On this PC run the skill's Python scripts with
   `D:\Forge\system\python\python.exe` (it has Pillow; the system `py` does not).
   Never `pip install`. Validate with `rojo build default.project.json -o work/ui-check.rbxl`
   from `D:\Dev.2\BonkHorde`.

## ScreenGui `Hud` (DisplayOrder 10)

Everything read during play. Reference: `frames/a_hud_mid.jpg`,
`frames/a_hud_bosses.jpg`, `frames/a_final_swarm.jpg`, `2.webp`.

| Name | Class | Notes |
|---|---|---|
| `XPBar` | Frame | full width, 26 px, top. Child `Fill` (Frame, cyan, width set as X scale 0..1 by code, so `Fill` alone may use a scale width). Child `Rainbow` (Frame, same size, `Visible=false`, a UIGradient of green, cyan, magenta, red, orange, yellow, green) |
| `RunClock` | TextLabel | "12:34" top-left row at y about 60, with `IconClock` to its left |
| `SilverCount` | TextLabel | max "9,999", with `IconSilver` |
| `GoldCount` | TextLabel | max "99,999", with `IconGold` |
| `KillCount` | TextLabel | max "99,999", with `IconSkull` |
| `StageTimer` | TextLabel | "9:37", top centre, about 44 px tall; the code turns it red in overtime |
| `DifficultyPill` | Frame | under the timer, `Visible=false`. Children `TierName` ("Insane"), `TierMult` ("x1.45") with `IconSilver` |
| `LevelLabel` | TextLabel | "LVL 101", top right |
| `NextChest` | Frame | left of the level. Children `Icon` (`IconChest`), `Price` ("1,346") |
| `ShieldBar` | Frame | 250x30 at x 20, y 95. Children `Fill` (scale width), `Text` ("205/205") |
| `HPBar` | Frame | 250x30 under it. Children `Fill`, `Text` ("199/199") |
| `WeaponRow` | Frame | at y about 170, lays out up to 4 `LoadoutSlot` |
| `TomeRow` | Frame | under it, up to 4 `LoadoutSlot` |
| `LoadoutSlot` | Frame (sample child) | 50 px `Icon` + `Level` ("LVL 28") under it |
| `QuestTracker` | Frame | at y about 305, lays out `QuestLine` vertically |
| `QuestLine` | Frame (sample child) | dark box, `Check` (ImageLabel, `IconCheck`, hidden when not done), `Box` (the empty checkbox), `Text` ("Find the Boss Portal"). The code tints the box green when done |
| `TeammateBars` | Frame | under the quest tracker, lays out `Teammate` vertically |
| `Teammate` | Frame (sample child) | `Portrait` (ImageLabel, icon), `Name` (max 20 chars), `HPBack` with `HPFill` (scale width), `DownedTag` ("DOWN", hidden) |
| `Minimap` | Frame | 240 px circle, top right under the level. Children: `Dots` (Frame, clips to the circle; the code puts `MapDot`s in it), `Ring` (stroke), `N` `E` `S` `W` (TextLabels the code moves round the rim), `PlayerArrow` (ImageLabel, `IconArrowPlayer`, centred) |
| `MapDot` | Frame (sample child of `Dots`) | 10 px, rounded; the code sets colour and position |
| `ItemStrip` | Frame | bottom centre, y about 1015, lays out `ItemSlot` horizontally and centred, wraps to a second row |
| `ItemSlot` | Frame (sample child) | 48 px `Icon`, `Count` ("x2", bottom right) |
| `BossBars` | Frame | top centre under the timer, `Visible=false`. Children: `Main` (Frame: `Name`, `Back` with `Fill`, `Text` "4.432 / 4.736"), `Minis` (Frame laying out `MiniBar` horizontally) |
| `MiniBar` | Frame (sample child of `Minis`) | `Name`, `Back` with `Fill`, `Text` |
| `InteractPrompt` | Frame | bottom centre above the item strip, `Visible=false`. Children `Key` ("E" in a keycap), `Text` (max "Open chest (1,346 gold)") |
| `Banner` | Frame | centre, upper third, `Visible=false`. Children `BannerText` (max "FINAL HORDE INCOMING!"), `BannerSub` |
| `StageTitle` | Frame | centre, `Visible=false`. Children `TierLabel` ("Tier 1"), `StageName` ("MOSSY WOODS" between two rules), `StageJoke` |
| `Letterbox` | Frame | `Visible=false`. Children `Top`, `Bottom` black bars, 110 px |
| `Toast` | Frame | top left, `Visible=false`. Children `ToastPortrait` (ImageLabel icon), `ToastTitle`, `ToastText` |
| `PickupToast` | TextLabel | above the hero, centre screen, `Visible=false` ("MAGNET") |
| `DownedOverlay` | Frame | full screen dim, `Visible=false`. Children `DownedLabel` ("YOU ARE DOWN"), `ReviveBack` with `ReviveFill`, `SpectateName` |
| `HurtFlash` | Frame | full screen red, `BackgroundTransparency=1`; the code pulses it |
| `LevelUpText` | TextLabel | "LEVEL UP!", centre, `Visible=false` |

## ScreenGui `Choices` (DisplayOrder 20)

Every pause panel. Reference: `frames/a_levelup.jpg`, `frames/b_levelup.jpg`,
`frames/a_chest_item.jpg`, `frames/a_charge_shrine.jpg`, `frames/a_shop.jpg`.
The upgrade offers, chest, shrine, shop and statue panels all sit in the centre
(about x 588 to 1332) and are flanked by `InventoryPanel` on the left (x 22 to 526)
and `StatsPanel` on the right (x 1530 to 1898).

| Name | Class | Notes |
|---|---|---|
| `LevelUpFx` | Frame | full screen, behind the panels, `Visible=false`. Children `RayBurst` (Frame; pale yellow rays from the centre, built from rotated thin frames or a gradient), `Confetti` (empty Frame the code fills) |
| `InventoryPanel` | Frame | `Visible=false`. Header "Inventory". Sections `Weapons` (label) with `WeaponSlots` (4 x `InvSlot`), `Tomes` with `TomeSlots` (4 x `InvSlot`), `Items` with `ItemGrid` (wrapping grid of `InvItem`) |
| `InvSlot` | Frame (sample child) | `Icon`, `Level` ("LVL 3"); empty slots are shown by the code with `Icon` hidden |
| `InvItem` | Frame (sample child of `ItemGrid`) | `Icon`, `Count` ("x2") |
| `StatsPanel` | Frame | `Visible=false`. Header "Stats". `Rows` (Frame, vertical list) of `StatRow` and `StatGap` |
| `StatRow` | Frame (sample child of `Rows`) | `Name` (left, max "Elite Spawn Increase"), `Value` (right, max "1.25x"). 31 rows plus 4 gaps must fit the panel height (about 800 px): row height about 20 px |
| `StatGap` | Frame (sample child of `Rows`) | 12 px spacer between groups |
| `UpgradeOffers` | Frame | `Visible=false`. Header "UPGRADE OFFERS". `Cards` (vertical list of `OfferCard`), footer with `BanishButton`, `SkipButton`, `RefreshButton` (each a TextButton with child `Label` and a small `Count` above it), `ChoiceTimer` (TextLabel, "12", hidden by the code in solo) |
| `OfferCard` | TextButton (sample child of `Cards`) | 630x145. Children: `RarityTag` ("Legendary"), `IconTile` (100 px, rarity-tinted) containing `Icon`, `OfferName` (max "Lightning Staff"), `Lines` (vertical list of `StatLine`), `Description` (wrapped text for a new weapon, max 70 chars), `LevelTag` ("LVL 28" or "NEW", right, gold), `Focus` (four white corner brackets, `Visible=false`, shown on hover or selection). The code sets the card's BackgroundColor3 and `RarityTag` colour by rarity |
| `StatLine` | Frame (sample child of `Lines`) | `Label` ("Projectile Count:", tan), `From` ("3.6", white), `Arrow` ("->" or an arrow image), `To` ("4.6", green) |
| `ChestPanel` | Frame | `Visible=false`. Deep teal field. `RarityWord` ("LEGENDARY"), `ItemName` (max "Second Wind Clock"), `ItemText` (two lines, max 110 chars), `Stage` (Frame holding `LightRays` (rarity-coloured rays, the code tints them) and `ItemSprite` (ImageLabel, 180 px, `IconName` set by the code) above `ChestIcon` (ImageLabel `IconChest`, 200 px)), footer `BanishButton` (with `Count`) and `TakeButton` |
| `ShrineOffers` | Frame | `Visible=false`. Header "Charge Shrine", line "The shrine offers you a reward:", `Rows` (vertical list of `RewardRow`), then `IgnoreRow` (TextButton, dark red, "Ignore Offers") |
| `RewardRow` | TextButton (sample child of `Rows`) | boxed `RarityTag` ("Common"), `Text` ("Gain 10% Jump Height", rich text: the code colours the number green) |
| `ShopPanel` | Frame | `Visible=false`. Header "DODGY DAN'S DEALS", `FlavourLine`, `Cards` (vertical list of `ShopCard`), `GoldLabel` ("Your gold: 1,234"), `LeaveButton` |
| `ShopCard` | TextButton (sample child of `Cards`) | `RarityTag`, `IconTile` with `Icon`, `ItemName`, `ItemText` (3 lines), `PriceTag` (Frame: `IconGold` + `Price` "298"), `SoldTag` ("SOLD", hidden) |
| `StatueOffers` | Frame | `Visible=false`. Header "ITEM OFFERS", `FlavourLine`, `Cards` (vertical list of `ItemCard`), `SkipButton` |
| `ItemCard` | TextButton (sample child of `Cards`) | same as `ShopCard` without the price |

## ScreenGui `Menu` (DisplayOrder 30)

Reference: `frames/a_charselect.jpg`, `frames/b_mapselect.jpg`, `1.png` for the logo.

| Name | Class | Notes |
|---|---|---|
| `MainMenu` | Frame | `Visible=true`. `LogoBanner` (a tilted white strip with bold black "BONK HORDE"; build it from frames and a rotated TextLabel, or leave an ImageLabel with `IconName` = `LogoBanner`), `PlayButton`, `SquadList` (vertical list of `SquadRow`), `SilverTotal` (top right with `IconSilver`), `VersionLabel` (bottom right) |
| `SquadRow` | Frame (sample child) | `Portrait` (icon), `Name`, `Hero` ("Sir Clonk"), `ReadyTag` ("READY", hidden when not ready), `HostTag` ("HOST") |
| `CharacterSelect` | Frame | `Visible=false`. Left panel "CHARACTER SELECTION" with `CloseButton` and `CharacterGrid` (4 columns x 5 rows of 126 px tiles: `PortraitTile` and `LockedTile` samples). Right `DetailCard`: `Portrait`, `CharacterName`, `RunCount` ("5 Runs" with `IconRun`), `Blurb`, `StartWeaponRow` (`Icon`, `Name` in yellow, `Text`), `PassiveRow` (`Icon` = `IconPassive`, `Name`, `Text`), `UnlockButton` ("UNLOCK 150" with `IconSilver`, hidden), `ConfirmButton` |
| `PortraitTile` | TextButton (sample child of `CharacterGrid`) | `Portrait` (icon), `Name` under it, `Focus` brackets |
| `LockedTile` | TextButton (sample child of `CharacterGrid`) | dark silhouette, `Name` ("??"), `Padlock` (`IconPadlock`) |
| `MapSelect` | Frame | `Visible=false`. Left panel "MAP SELECTION" with `CloseButton` and `MapList` (vertical list of `MapRow`). Right `DetailCard`: `MapName`, `TierLabel` ("Tier 1"), `Highscore` (with `IconSkull`), `BestTime`, `StageCount` ("Stages: 1"), `ReadyList` (vertical list of `ReadyRow`), `ConfirmButton` ("READY") |
| `MapRow` | TextButton (sample child) | `Thumb` (ImageLabel icon), `Name`, `Blurb`, `LockTag` ("LOCKED", hidden) |
| `ReadyRow` | Frame (sample child) | `Name`, `State` ("ready" or "choosing") |

## ScreenGui `EndScreens` (DisplayOrder 40)

Reference: `frames/a_death.jpg`.

| Name | Class | Notes |
|---|---|---|
| `DeathScreen` | Frame | full screen black, `Visible=false`. `DeathTitle` ("you got bonked"), `DeathJoke`, `HeroViewport` (ViewportFrame, 500x600, centre), `ConfirmButton` with corner brackets |
| `Results` | Frame | `Visible=false`. Panel: `ResultTitle` ("VICTORY"), `StatTable` with `Kills`, `Level`, `Time`, `BossTime` (each a Frame with `Label` and `Value`), `PlayerRows` (vertical list of `PlayerRow`), `ContinueLabel` ("Back to the lobby in 12") |
| `PlayerRow` | Frame (sample child) | `Portrait`, `Name`, `Kills`, `Damage`, `Silver` (with `IconSilver`) |

## ScreenGui `Overlay` (DisplayOrder 50)

| Name | Class | Notes |
|---|---|---|
| `BigMap` | Frame | `Visible=false`. 760 px square, left of centre, dark. `Dots` (clips; the code fills it with `MapDot` clones from `Hud`), `PlayerArrow`, `N` `E` `S` `W`, `Legend` |
| `PauseMenu` | Frame | `Visible=false`. Panel "PAUSED": `ResumeButton`, `MusicSlider` and `SfxSlider` (Frame with `Fill` and `Knob`), `SensitivitySlider`, `DamageNumbersToggle` (TextButton with `Check`), `LeaveButton` |
| `TouchControls` | Frame | `Visible=false`. Bottom right: `JumpButton` (140 px round), `SlideButton`, `InteractButton`, `TabButton` (top right, small). Leave the bottom-left free for Roblox's own move stick |

## Deliverables

- `src/ui/Hud.model.json`, `Choices.model.json`, `Menu.model.json`,
  `EndScreens.model.json`, `Overlay.model.json`
- one mockup PNG per screen state under `assets/ui/mockups/`, and a combined
  contact sheet at `assets/ui/mockup.png`
- `assets/ui/manifest.json`: for each ScreenGui the list of named elements it
  contains, and for each icon key where it is used
- `assets/ui/NOTES.md`: anything you could not express, any name you had to change
  (do not change names without saying so), and the `verify_ui.py` verdict per screen

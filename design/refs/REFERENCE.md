# Reference study

> **Art direction note (2026-10-12).** The user asked for a cartoon look, not the
> reference's pixelated one. Use this file for layout, proportions, timing, colour
> roles and what each thing is. Do NOT copy its pixel textures, pixel fonts or hard
> facets. The style to build is in `design/game.json` under `plan.art_direction`.

What the supplied footage shows, written down so later stages match it without
re-watching. Measurements are in pixels on a 1920x1080 frame unless noted.

## Files in this folder

| File | What it is |
|---|---|
| `1.png` | store banner: bold black wordmark on a tilted white strip, painted knight, fire, skeleton, goblin |
| `2.webp` | late-game forest (red palette), level 101, full HUD with 8 weapon/tome icons and 20+ item strip |
| `3.webp` | early build forest, boss bar, sword crescent slash, minimap |
| `4.webp` | desert, fox mage, interact prompt "[E] Katana", damage numbers |
| `5.webp` | forest night, knight against a wood golem, embers, ruins |
| `sheets/a_01..06.jpg` | video A (Forest, knight, 14:19), one frame per 10 s, 16 per sheet, timestamped |
| `sheets/b_01..08.jpg` | video B (Desert, frost mage, 19:32), same layout |
| `frames/a_*.jpg`, `frames/b_*.jpg` | full-resolution stills of each menu and HUD state |

Sheet timestamps run about 5 s behind the real video time. To pull a new still:
`ffmpeg -ss <sheet time + 5 s> -i <video> -frames:v 1 -q:v 2 out.jpg`.

Source videos (not copied, 0.9 GB): `C:\Users\diogo\Downloads\Megabonk - PC Gameplay (No commentary) - Brunoborne (1080p).mp4`
and `C:\Users\diogo\Downloads\Megabonk gameplay no commentary - WillTheDude (720p).mp4`.

## Run flow, video A (forest)

| Time | Beat |
|---|---|
| 0:00 | Character selection over a blurred forest diorama |
| 0:10 | Letterboxed spawn: character steps out of a blue swirling portal ring |
| 0:20 | Play. Goblins, a crate, a chest. Countdown 9:51 |
| 0:45 | First level-up: rays, rainbow XP bar, gem confetti, three upgrade cards |
| 1:05 | Chest prompt: button glyph, price 30, coin |
| 1:50 | Charge shrine: stone pedestal with "!" above, translucent green dome zone |
| 2:55 | Chest reveal: rarity word, item name, description, item bursting from a chest, BANISH / TAKE |
| 3:35 | Charge shrine reward panel: three stat offers plus "Ignore Offers" |
| 4:05 | Miniboss with a boss bar ("Stone Golem 965 / 965"); red dome telegraphs on the ground |
| 6:05 | "Magnet" pickup text; all gems fly to the player |
| 6:55 | Vendor shop panel: three items priced in gold, LEAVE |
| 7:35 | Golem pack; lightning staff bolts turn targets white |
| 10:15 | Bosses summoned; quest flips to "Defeat the Boss"; several boss bars stacked |
| 12:55 | Timer 0:00 in red, "FINAL SWARM INCOMING!", difficulty pill under the timer, white ghosts |
| 14:15 | Death: black screen, title, joke subtitle, kneeling character, CONFIRM |

Video B adds: map selection (Forest / Desert / Graveyard with tier checkboxes, highscore
and speedrun, CHALLENGES and CONFIRM), stage title card ("Tier 3", stage name, one-line
joke), BANISH / SKIP / REFRESH with charge counts above each button, a statue with
"ITEM OFFERS", tornadoes, a big square map overlay, the boss portal (skull-topped stone
arch on a three-step octagonal dais with a blue swirl), "Enter the Portal", and a second
stage with a night palette.

## HUD (frames/a_hud_mid.jpg, a_hud_bosses.jpg)

- **XP bar**: full width, y 0 to 26, cyan fill `#11B4F4` on near-black, 2 px dark border.
  Turns into seven rainbow segments (green, cyan, magenta, red, orange, yellow, green)
  during a level-up.
- **Stat row**, y about 60, white pixel digits with black shadow: clock icon + elapsed
  time at x 22; silver coin + silver at x 180; gold coin + gold at x 340; skull + kills at
  x 500. Video B adds a chest icon + next chest price left of the level.
- **Countdown**: centred, y 62, about 44 px tall, white; red once it reaches 0:00.
  Under it in overtime: a pill with the difficulty name on dark green and a silver
  multiplier coin.
- **Level**: "LVL 24", top right, x 1760 to 1900, same size as the countdown.
- **Bars**: shield (cyan `#12A8E8`, text "25/25") stacked on HP (red `#E5121B`, text
  "158/158"), each 250 x 30 at x 20, y 95 and y 125. Empty part is near-black.
- **Weapons row** at y 170 and **tomes row** at y 240: 50 px icons, 66 px pitch, "LVL n"
  under each in the blackletter face.
- **Quest tracker**: black boxes at x 20, y 305 and y 363, white checkbox + label in the
  plain pixel sans; a finished line gets a dark-green box and a green tick.
- **Minimap**: circle, 240 px, centre about (1777, 238), navy-black fill with slightly
  lighter terrain silhouettes, thin tan ring, N / E / S / W letters riding the rim and
  rotating with the camera, blue arrow for the player, yellow diamonds, green squares,
  red marks for bosses and the portal.
- **Item strip**: bottom centre, y 1015, 48 px sprites at 75 px pitch, "x2" stack counts.
- **Boss bars**: name in blackletter above a red bar with "4.432 / 4.736" centred; the
  main boss bar spans x 362 to 1558 at y 256; extra bosses get three short bars at y 176.
- **Player**: thin cyan outline once shielded; a 75 x 8 red bar (plus a cyan line) under
  the feet; a soft blob shadow.
- **World text**: damage numbers are white pixel digits with a black outline, randomly
  tilted, bigger for bigger hits; crits are yellow with a small "CRIT!"; gold gains are
  yellow "$33"; XP gains are cyan "+29"; pickups name themselves ("Magnet").

## Panels (frames/a_levelup.jpg, a_chest_item.jpg, a_shop.jpg, a_charge_shrine.jpg)

- **Frame**: fill `#1F2622` to `#262E29`, header strip `#2E4637` with a lighter top
  edge, 3 px stone-grey border `#A3A69F` with small riveted squares on every corner,
  thin dark inner line. Header text white with a dark shadow, small caps blackletter.
- **Upgrade offers**: panel x 588 to 1332, y 163 to 915. Three cards, each 630 x 145,
  20 px apart: 100 px icon tile on the left with the rarity word above it, name in
  blackletter (about 34 px), stat line under it ("Size: 100% -> 120%", label tan,
  old value white, new value green), "LVL 2" or "NEW" in gold at the right. Card fill
  follows rarity: common dark green `#0F3B24`, new item dark grey `#2B2B2B`, uncommon
  dark blue, rare dark purple, legendary olive-gold `#4A4309` with gold text.
  White corner brackets mark the focused card. Footer strip holds the buttons.
- **Inventory** (left, x 22 to 526) and **Stats** (right, x 1530 to 1898) flank every
  pause panel. Inventory: Weapons (4 slots), Tomes (4 slots), Items (wrapping grid).
  Stats: 31 lines in five groups, name left, value right.
- **Chest reveal**: deep teal field `#04303F`, rarity word in the rarity colour, item
  name, two-line description, chest with coloured light rays behind the item, BANISH
  (dark red) and TAKE (blue).
- **Shop**: flavour line under the header, three legendary-style cards with a coin price
  top right, LEAVE in grey.
- **Charge shrine**: "The shrine offers you a reward:", three rows with a boxed rarity
  tag and "Gain 10% Jump Height" in the pixel sans with the number in green, and a
  dark-red "Ignore Offers" row.
- **Buttons**: chunky, darker bottom lip, white blackletter caps: CONFIRM / TAKE /
  REFRESH / OPEN blue `#2E7FD1`, SKIP green `#2E9E4C`, BANISH red `#B3263A`, LEAVE grey.
- **Menus** (a_charselect.jpg, b_mapselect.jpg): character grid 4 x 5 of 126 px portrait
  tiles with the name under each, locked tiles are black silhouettes labelled "??";
  detail card on the right with portrait, name, rank bar, run count, description,
  starting weapon, passive, skin row, CONFIRM. Silver total top right. Map selection
  mirrors it with three map rows and a tier table.
- **Death** (a_death.jpg): black screen, title in grey-white blackletter, smaller joke
  line, the character kneeling on their weapon, CONFIRM with corner brackets.

## World look

- **Forest**: hilly grass terrain with steep dirt sides and big cliff walls; pixelated
  grass texture with dirt paths and stone-tile patches; trees with leaning brown trunks
  and three or four faceted blob canopies in a camo-green pixel texture; grey faceted
  boulders; ivy-covered stone-brick towers and walls; crates, logs, clay pots, lantern
  posts; dark fern tufts. Night palette: teal-blue sky with dark pixel-edged clouds,
  blue distance fog, red ember streaks in the air.
- **Enemies (forest)**: small green goblins, bigger goblins with shield and sword,
  bright green slimes, bone-white skeletons, armoured skeletons, grey rock golems with
  cyan eyes, tree-stump creatures, a huge pig brute, white ghosts in the final swarm.
  Elites carry a small gold crown above the head. Hit enemies flash white.
- **Weapon effects**: sword = a white-blue crescent with stair-stepped pixel edges;
  lightning = a white jagged bolt from the sky; frost aura = cyan pixel-stepped octagon
  rings on the ground; boomerang = a spinning banana with a pale trail; rockets and a
  magenta piercing blade beam appear in video B.
- **Pickups**: XP gems are blue elongated hexagonal crystals that grow when merged; gold
  coins; a red horseshoe magnet; chests are wood with grey iron bands.
- **Shrine zones**: translucent domes (green, purple, pink, blue, yellow variants), a
  white "!" over the pedestal until used. Boss attacks telegraph as translucent red
  domes on the ground.

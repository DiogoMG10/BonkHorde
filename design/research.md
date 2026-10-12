# Bonk Horde: research findings

Section 1, stage 1. Written 2026-10-12. The brief names the game to follow (Megabonk),
so the genre is fixed: a **3D survivors-like roguelike** (auto-attacking weapons, horde
of enemies, level-up choices, 10-minute stage timer, boss, final swarm). Everything
below is research *inside* that genre.

## 1. What the reference game is

Megabonk is a 2025 single-player 3D survivors-like by a solo developer. A run:
pick a character and a map, weapons fire on their own, you run / jump / slide through
a hilly low-poly map killing a horde, collect XP gems and gold, pick one of three
upgrade offers on each level-up, spend gold on chests, charge shrines for stat boosts,
find the boss portal and beat the stage boss before a 10:00 countdown ends. When the
timer hits zero a final swarm arrives and difficulty ramps until you die.

Primary evidence is the footage the user supplied, studied frame by frame
(see `refs/REFERENCE.md`): two full runs (Forest Tier 1 with the knight, 14:19; Desert
Tier 3 with the frost mage, 19:32) plus five stills.

Content numbers from the pages I opened:

| Thing | Reference game | Source |
|---|---|---|
| Weapons | 30 (7 default, 23 unlockable) | megabonk.org weapons database |
| Tomes | 23 (13 default), each +X of one stat per level | megabonk.org tomes database |
| Items | 85 to 86 across four rarities | megabonk.org items database, bonkmaster.com/items |
| Enemies | 51 entries with HP, damage, speed | Fextralife enemies page |
| Maps | Forest, Desert (Graveyard added later), 3 tiers each, 1 to 3 stages per run | megabonk.org maps guide |
| Stage timer | 10:00, then final swarm / overtime | megabonk.org timer page (search summary) |

Per-level tome values used as the baseline for our numbers: Agility +15% move speed,
Cooldown +7.5% attack speed, Damage +0.08x, Health +25, Precision +7% crit, Regen
+40/min, Shield +25, Size +10%, Attraction +75% pickup range, Luck +7%, XP +7%,
Quantity +1 projectile. Enemy baselines used: weak goblin 7 HP / 15 dmg / speed 5,
strong goblin 15/25/5.5, slime 6/8/6.5, skeleton 20/20/5.5, armoured skeleton 30/25/4,
golem 20/20/5, totem miniboss 250/40/6, stage bosses 8,000 to 10,000 HP.

## 2. The Roblox market, measured live on 2026-10-12

Queried Roblox's own search and games endpoints (not a third-party tracker).

| Game | Playing now | Visits | Likes | What it is |
|---|---|---|---|---|
| Survive a Million Monkeys | 18,820 | 18.3M | 97.6% | co-op horde survival with classes and guns, created 2026-08 |
| Zombie Rush Survival | 6,836 | 132.9M | 97.4% | co-op wave survival with upgrades and turrets |
| Robong Survivors | 46 | 6.8M | 94.6% | the closest survivors-like: auto-firing weapons, level-up choices, weapon evolutions, boss portal |
| Orbit Survivors: Roguelike Arena | 0 | 28K | 77.9% | top-down survivors arena, 2 players max |

Searching "megabonk", "bonk roguelike", "bullet heaven" and "vampire survivors" returned
no game that reproduces the 3D movement-driven formula: nothing with jump/slide momentum
on a vertical map, the PS1 look, or the 10-minute boss-then-swarm structure.

**Read.** Co-op horde survival has proven demand right now (two games at 6.8K and 18.8K
concurrent, both above 97% likes). The true survivors-like build-crafting niche is
occupied by one well-liked but small game (Robong Survivors, 46 concurrent on 6.8M
visits), which suggests the format is liked but nobody has shipped the version with
the movement and feel that made the reference a hit. That is the gap this build aims
at: the horde-survival audience, with real build depth and movement skill.

**Risk.** A direct copy of another studio's game gets taken down on Roblox and is not
something to ship. Mechanics, genre conventions and a general art direction are free to
follow; names, logo, characters, item art and jokes are not. So this build keeps the
structure and look-and-feel and uses its own title, characters, bosses, item names and
artwork.

## 3. What the references say the game must nail

1. **Movement.** Fast run, hold-jump bunny hopping, slope slides, jump height and extra
   jumps as stats. The map is vertical: hills, cliffs, ramps, ruins.
2. **Readable chaos.** Hundreds of enemies, floating pixel damage numbers, gems and
   coins everywhere, yet the player always reads (cyan outline on the player, small HP
   bar under the feet).
3. **The level-up moment.** Game pauses, pale light rays burst from the centre, the XP
   bar turns rainbow, gem confetti flies, three cards slide in.
4. **PS1 crunch.** Low-poly faceted meshes, low-resolution textures with hard pixels,
   distance fog matched to the sky, pixel fonts (a blackletter pixel face for titles and
   numbers, a plain pixel sans for body text).
5. **Dense, legible HUD.** XP bar across the top, clock / silver / gold / kills row, big
   countdown, LVL, HP and shield bars, weapon and tome icons with levels, quest
   checklist, round minimap with compass letters, item strip along the bottom.

**Direction from the user after this was written (2026-10-12):** point 4 describes the
reference. This build does not use the pixelated look; it is cartoon. Points 1, 2, 3
and 5 stand.

## 4. Tooling available on this machine, checked live

| Need | State |
|---|---|
| Roblox Studio MCP | connected; one open place ("Place1", unsaved, place id 0) |
| Rojo, Wally, Lune, Selene, StyLua, Blender 4.5, ffmpeg, git | installed |
| Studio AI mesh generation (`generate_mesh`, textured, up to 20k triangles, part segmentation) | available |
| Image upload from a local folder (`upload_image`) | available, no API key needed |
| Publishing a script-built mesh from inside Studio (`AssetService:CreateAssetAsync`) | **not available** in this Studio build ("not available yet"), probed |
| Open Cloud key (`ROBLOX_API_KEY`) | not set: custom Blender meshes cannot be uploaded and the game cannot be published until it is |
| Forge (Stable Diffusion WebUI Forge) | **not installed**; official package is `webui_forge_cu121_torch231.7z`, 1.87 GB, from the lllyasviel/stable-diffusion-webui-forge GitHub releases; needs a model checkpoint on top |
| GPU | RTX 4060 Laptop, 8 GB VRAM; 798 GB free on D: |
| Kaggle / Hugging Face / Cloudflare tokens | not set (the skills' cloud image and mesh routes are unavailable) |
| Roblox VFX library | empty (first step of the VFX stage is harvesting a pack) |

Consequences for the plan are in `game.json` under `plan.technical_architecture` and
`plan.art_direction`: meshes have a two-route plan (Blender-authored through Open Cloud
when a key exists, Studio AI generation otherwise), textures and icons come from Forge
plus a pixel-crunch pass and go up through `upload_image`.

## Sources opened

- Megabonk weapons database: https://megabonk.org/database/weapons/
- Megabonk tomes database: https://megabonk.org/database/tomes/
- Megabonk items database: https://megabonk.org/database/items/
- Megabonk maps guide: https://megabonk.org/guides/maps/
- All Megabonk items (effects): https://bonkmaster.com/items
- Megabonk enemies (HP, damage, speed): https://megabonk.wiki.fextralife.com/Megabonk_Enemies
- Stable Diffusion WebUI Forge repository and release list: https://github.com/lllyasviel/stable-diffusion-webui-forge
- Roblox search and games endpoints, queried live: `apis.roblox.com/search-api/omni-search`, `games.roblox.com/v1/games`

Read as search summaries only (not opened): megabonk.org timer and boss-portal pages,
megabonk.org character guides, thegamer.com and deltiasgaming.com shrine guides,
Wikipedia's Megabonk article. megabonk.wiki, the Steam guide and the Fandom wiki refused
the connection, so nothing here rests on them.

Seven independent origins were opened: megabonk.org, bonkmaster.com, Fextralife, GitHub,
Roblox's own endpoints, and the two supplied gameplay videos.

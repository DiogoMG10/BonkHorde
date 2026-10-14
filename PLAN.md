# Bonk Horde: the plan

> **Historical.** This is the plan for the original six-stage build (October 2026), kept for
> its design decisions. It is not the active plan: see `docs/ROADMAP.md`.

Stage 1 of 6 (research and plan) is finished. Nothing has been built yet. This is what
I intend to build; say "approved" or tell me what to change.

Updated 2026-10-12 with your changes: the look is cartoon instead of pixelated, the
work is pushed to your BonkHorde GitHub repository, Forge is being installed, and the
place you saved to Roblox is recorded.

## What it is

A 3D survivors-like for Roblox that follows your Megabonk references closely: you run,
bunny hop and slide through a cartoon twilight forest, your weapons fire on their own,
you level up and pick one of three upgrades, buy chests, charge shrines, find the boss
portal, beat the boss before the 10:00 timer runs out, then face the final horde.
Solo or with up to 2 friends (3 players per server).

## Three calls I made, and why

1. **Its own name, characters and artwork.** I am matching the structure and the
   screens as closely as I can, but the title (Bonk Horde), heroes, bosses,
   item names and all art are original. Roblox removes direct copies of other games,
   and reusing another studio's characters and art is not something I will ship.
2. **Forest first, Desert next.** This build is the full forest run from your first
   video. The desert from your second video becomes the first content update, so the
   forest gets every fidelity pass instead of sharing them. Map select shows Desert and
   Graveyard as locked.
3. **Co-op rules.** XP is shared. A level-up pauses the game for the whole squad and
   everyone picks at once (12 seconds). Loot, chest prices and shop stock are separate
   for each player, so nobody steals anything. A downed teammate leaves a tombstone;
   stand on it for 3 seconds to revive them. Enemy numbers and boss health scale with
   squad size.

## What is in

| | |
|---|---|
| Heroes | Sir Clonk (knight, Sword), Zib (fox mage, Fire Staff), Mint (frost mage, Frost Ring, costs 150 silver) |
| Weapons | Sword, Fire Staff, Frost Ring, Lightning Staff, Bone, Boomernana, Axe, Party Rocket |
| Tomes | 12: Damage, Agility, Cooldown, Precision, Size, Shield, Health, Regen, XP, Luck, Attraction, Quantity |
| Items | 25 across Common, Rare, Epic and Legendary |
| Stats | all 31 from the reference stats panel |
| Enemies | Goblin Runt, Goblin Bruiser, Slime, Skeleton, Shield Skeleton, Rock Golem, Twiglet, Ghost; any can be a crowned elite |
| Bosses | minibosses Boulder Bro and Hamlet the Hangry; stage boss Old Man Timber |
| World objects | chests, charge / greed / challenge / vacuum shrines, statue, vendor, pots, crates, boss portal, magnet / snack / frenzy powerups |
| Map | Mossy Woods: about 720 x 720 studs of hills, cliffs, ramps and ruins, plus a small lobby glade behind the menus |
| Screens | 21, laid out to the reference measurements: menu, hero select, map select, HUD, upgrade offers with inventory and stats, chest, shrine, shop, statue, big map, stage card, death, results and more |
| Saved between runs | silver, the third hero unlock, run counts, best time and best kill score |

Up to 350 enemies at once, simulated on the server and drawn by each player's client,
which is the only way Roblox handles a crowd that size.

## What is out of this build

Desert and Graveyard maps, multi-stage tiers, procedurally generated terrain, quests,
ranks, skins, the unlock shop, weapon evolutions, hidden bosses, Robux purchases and
global leaderboards.

## The look: cartoon

Your references decide what is on screen and where. The style is clean cartoon, as
you asked, not pixelated.

- Chunky, exaggerated shapes: big heads, big hands, oversized weapons, rounded forms.
- Smooth shading and hand-painted textures in bright, saturated colour.
- A painted twilight sky with soft clouds, blue haze in the distance, warm lanterns,
  fireflies and embers.
- The interface keeps the reference layout (same panels, cards, bars and positions)
  with a cartoon skin: rounded corners, thick outlines, bold rounded lettering and
  sticker-style icons.
- Effects are bold and readable: swooshes, stars, rings and puffs.
- Before any batch work I make a one-page style sheet (one hero, one enemy, one prop,
  one icon, one panel) and show it to you, so the style is agreed once.

The reference study, with timestamps and measurements, is in
`design/refs/REFERENCE.md`. The full design is in `design/game.json`.

## What needs making

55 meshes, 66 icons, 21 screens, 13 animations, 35 effects, 63 sounds.

## The six stages

1. Research and plan (done)
2. Code and a playable loop on placeholder shapes, so the game is proven fun before any art
3. World and visuals: the map, meshes, textures, interface
4. Motion and sound: animations, effects, audio
5. Assembly and playtest, with every hero, weapon, effect and screen checked in play
6. Publish

You approve each stage, then start a fresh chat for the next one.

## What I need from you

1. **Approve this plan**, or tell me what to change.
2. **Store your Roblox API key** as a user environment variable named
   `ROBLOX_API_KEY` (steps are in the chat). I read it from there and it never appears
   in the conversation.

## Already settled

- Forge: approved by you; the official package is downloaded to `D:\Forge`.
- The place: saved to Roblox as BonkHorde (private).
- GitHub: this folder is pushed to your private BonkHorde repository on `main`. The
  frames taken from the reference videos stay on your PC and are not uploaded.

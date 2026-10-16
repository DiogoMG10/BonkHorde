# M3.B Blender art: the Wardwood kit

The Blender kit's direction was approved from the Old Grove showcase (Studio, Tiago and
Diogo). M3.B now dresses the whole Wardwood with it. Layout, paths, colliders, enemy
pathing, skies and gameplay are unchanged.

## What the kit covers

| Old prop kind | Kit models | Detail levels |
|---|---|---|
| Oak, OakLeaning, Beech, Birch, Sapling | OakA/B/C, OakLeaningA/B, BeechA/B, BirchA/B, SaplingA/B | near, `_LOD`, `_FAR` (saplings: near, `_LOD`) |
| Spruce, SpruceFar, SpruceRidge, Pine | SpruceA/B/C, PineA/B | near, `_LOD`, `_FAR` |
| AncientOak, AncientPine, Elder | AncientOakA/B, AncientPine, Elder | near, `_LOD`, `_FAR` |
| Bush, Fern, Stump, FallenLog | BushA/B/C (near, `_LOD`), FernA/B, StumpA/B, FallenLog | |
| FallenGiant (landmark) | FallenGiant: ridged mossy trunk on the same collider, splintered crown end, torn root plate | |
| BoulderLarge, RockSmall, BoulderFlat, Menhir | BoulderLargeA/B, RockSmallA/B, BoulderFlat, MenhirA/B | |
| Pillar, PillarBroken, RuinWall | PillarA/B, PillarBrokenA/B, RuinWallA/B | |
| ElderRoots | retired while the kit is on (the Elder grows its own roots) | |

Still the old models: the landmarks' architecture (Ward, Gate, Sun Temple, ruin tower and
arches, steps, paving, braziers, cairns), rune and moon stones, lanterns, glowcaps, the
Elder's flower ring, the falls. They are the next candidates.

Each plant picks its variation from its seed and gets a small fixed shift of foliage
colour (`ArtPlan.tint`), so a wood of a few models never reads as copies.

## Pipeline

| Step | Command / file |
|---|---|
| Recipes (the editable source of truth) | `tools/art/assets.py` (`TREES`, `build_all`), helpers `tools/art/geo.py` |
| Build: `.blend`, GLBs, game data, manifest | `"$BLENDER" -b -P tools/art/kit.py` (~10 s) |
| Blender source, one collection per asset | `assets/art/wardwood_kit.blend` |
| Roblox-importable meshes | `assets/art/export/<Asset>.glb` |
| Game data (packed positions, normals, triangles) | `src/server/Wardwood/ArtMeshes/<Asset>.luau` |
| Triangles, parts, colours, sizes | `assets/art/manifest.json` |
| Asset renders | `"$BLENDER" -b assets/art/wardwood_kit.blend -P tools/art/render.py -- <outdir> [Asset ...]` |
| Map previews from the game camera, old vs new | `python tools/art/preview_map.py work/art/map` |
| Draw cost, old vs new, and grass option B, offline | `lune run tools/art/measure.luau [near]` |

Change a recipe, rerun the kit, commit the regenerated files. Never hand-edit generated Luau.
A Blender render is evidence of shape and palette only, never of the look in Studio.

## How the game draws it

- **Server** (`server/Wardwood/ArtKit`): at start, rebuilds each kit model once as an
  `EditableMesh`, bakes it with `AssetService:CreateDataModelContentAsync` and keeps it as a
  template Model in `ReplicatedStorage.WardwoodArt` (horizon and far versions first). The
  templates and their content replicate to every client. Nothing is rebuilt per tree.
- **Server** (`Wardwood/Builder`): for every prop the kit dresses, only its colliders are
  built (hidden); bushes and small rocks, which never collided, get nothing. Scenery parts
  the server builds and replicates: 10,218 before, ~1,460 now.
- **Clients** (`ArtController`): rebuild the same deterministic world (`Core/World`, ~0.3 s
  once) and draw every dressed prop from the templates (`Core/ArtPlan` picks the model),
  pooled and reused. Trees: full detail within 110 studs of the camera, `_LOD` to 280,
  `_FAR` beyond, with 12 studs of slack at each boundary (`Config/Wardwood.ArtLod`).
- **Grass**: Roblox's native terrain grass, see below.
- **Canopy fade**: the kit's leaf meshes carry the `WWFoliage` tag; the client's canopy fade
  ghosts them out of the camera's way like the old crowns.

### Measured offline (`tools/art/measure.luau`, within ~600 studs of a client)

| Spot | Old (est.) | New trees and props |
|---|---|---|
| Spawn clearing | ~1.56M tris, 9.8k parts | ~0.61M tris, 5.0k parts |
| Open meadow | ~1.13M, 7.5k | ~0.54M, 3.8k |
| Old Grove | ~0.99M, 6.7k | ~0.62M, 3.5k |
| Dense wood | ~1.13M, 7.3k | ~0.68M, 3.8k |

The old figures estimate Roblox's primitive spheres and cylinders, so they are approximate.
Frame time under a horde needs Studio.

## Grass: Roblox's native grass

Approved in Studio (`bonk-0.17.2-m3b` A/B): `Config/Wardwood.Grass = "native"`. Every grassy
column is Roblox's `Grass` material (surface `Turf`, tinted to the old carpet), so the engine
draws its own blades over all of it: seamless, no instances, nothing streamed by us, faded
with distance by the engine. `Terrain.GrassLength` stays at its 0.1 minimum (it cannot go
lower), and the place's `Terrain.Decoration` must stay on. `grass short|less|full` in
BonkDev bring back the earlier grounds, `grass tint r g b` re-tints the blades live.

Tried and dropped: client patches streamed round the camera (`bonk-0.17.0`/`0.17.1`: discs
of uneven density, 61% variation, each its own tint, with an edge always somewhere in view)
and static world-aligned Blender grass chunks (`bonk-0.17.2`: even and seamless, but
~5.7M triangles map-wide with nothing to thin them at a distance).

## Enemy outlines (a player setting)

Studio playtests kept them as an option, not a look: **Settings > Enemy outlines, off by
default**, each player's own choice, applied at once and saved in the profile with the
volumes (`Core/Settings`; the server folds in only the keys a client sends, so saving one
never resets the other; without a datastore it lasts the session). When on, the enemies
near the hero get a thin ink outline (client `EnemyRenderController`): two Highlights in
all, each on a container Model the near enemies are moved into five times a second, the
nearest 90 within 70 studs (8 studs of slack), enemies 3.5 studs tall or less in their
own, slightly firmer one. No fill; dark by day, moonlit pale at night. `Occluded`, so
hills, walls and trunks still hide them. In Studio, `enemy clarity on|off|through` forces
every client for the session (never saved) and `enemy clarity player` hands it back.

Better enemy readability through the models themselves (silhouettes, contrast against
the grass, faces, type differences) is a later task, with M4.

## Fallbacks

- `Config/Wardwood.Art = false`, or `art off` in `Workspace.BonkDev` (Studio), builds the old
  props over the whole map; `art on` brings the kit back. Nothing is duplicated: whichever
  look is off is not built.
- If any of a family's models fails to bake, the server builds that family's old models and
  lists it in the `BonkArtClassic` attribute; clients skip it.

## Keeping hand-made edits: `Config/WardwoodOverrides`

The Wardwood is generated, so a tree moved in Studio is gone next run. Instead:

1. In a Studio playtest, stand by the prop and run `art pick` in `Workspace.BonkDev`. Output
   prints its stable key (`Oak@-398,-34`: kind and generated spot) and a line to paste.
2. Paste the line into `src/shared/Config/WardwoodOverrides.luau` and edit it: `dx`/`dz` or
   `x`/`z` to move, `yaw` (degrees), `scale`, `asset` (another variation of its family),
   `hide = true` to remove it (collider too).
3. Restart the playtest. `World.build` applies overrides before anything is built, so the
   server colliders, enemy pathing and every client agree. Run `lune run test` and
   `lune run tools/map/prove.luau` to catch a prop moved onto a path.

## Permanent assets (needs a person's go-ahead)

The runtime route needs no upload and works in Studio. It costs one bake at server start
(seconds, in the background; the old horizon is replaced as templates arrive), and its
content lasts the session only. For the published game, uploaded meshes are the more robust
route: Roblox streams and LODs them itself, nothing is baked at start, and the place stops
depending on the EditableMesh and DataModelContent APIs.

To switch, with authorization:

1. Upload `assets/art/export/<Asset>.glb` as `Model` assets (Studio's 3D Importer, or Open
   Cloud with an API key; the roblox-3d-model skill has the steps). About 85 models.
2. Record each part's MeshId in `assets/meshes/manifest.json` and run
   `python tools/assets/emit_assets.py`, so `Assets.rbxmx` carries them through Rojo.
3. Point `ArtKit.bakeAll` at copying those into `ReplicatedStorage.WardwoodArt` instead of
   baking; the client side does not change.

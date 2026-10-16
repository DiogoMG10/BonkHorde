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
| Draw cost, old vs new, offline | `lune run tools/art/measure.luau [near] [grassRadius]` |

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
- **Short 3D grass**: grown on each client where its camera looks: a patch (0.2-0.5 studs
  tall, three tones, ~9 studs across) per 8-stud cell of grassy ground, within 54 studs of a
  point 20 studs ahead of the hero along the camera's view, pushed a further 0.4 s of the
  hero's speed (up to 26 studs) ahead, and always within 30 studs of the hero. Re-planned ten
  times a second and whenever the hero moves a cell or the camera swings ~25 degrees; grown
  nearest the hero first in 0.8 ms of each frame (four times that while ground within 48
  studs is still bare); dropped a cell outside; pooled. Never on paths, rock, sand or under
  trunks and rocks (`Config/Wardwood.ArtGrass`). The edge ahead sits 60-80 studs from the
  camera, where blades are a pixel or two tall; the terrain's grass carpet carries the rest.
  `tests/GrassStream.spec.luau` simulates it frame by frame: bunny hopping at 50 studs/s
  leaves no bare cell ahead, a quarter-turn of the camera at most a few frames of the new
  view's edge, a teleport is grown round within 0.25 s.
- **Canopy fade**: the kit's leaf meshes carry the `WWFoliage` tag; the client's canopy fade
  ghosts them out of the camera's way like the old crowns.

### Measured offline (`tools/art/measure.luau`, within ~600 studs of a client)

| Spot | Old (est.) | New trees and props | New grass |
|---|---|---|---|
| Spawn clearing | ~1.56M tris, 9.8k parts | ~0.61M tris, 5.0k parts | ~145k tris, ~135 patches |
| Open meadow | ~1.13M, 7.5k | ~0.54M, 3.8k | ~149k, ~138 |
| Old Grove | ~0.99M, 6.7k | ~0.62M, 3.5k | ~137k, ~127 |
| Dense wood | ~1.13M, 7.3k | ~0.68M, 3.8k | ~140k, ~130 |

The old figures estimate Roblox's primitive spheres and cylinders, so they are approximate.
Frame time under a horde needs Studio.

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

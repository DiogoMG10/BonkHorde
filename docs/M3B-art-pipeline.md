# M3.B Blender art: direction, pipeline, showcase

The Wardwood's layout, movement and atmosphere are approved; its environment models are
not. M3.B replaces them with a cohesive Blender-made kit, starting with a showcase in the
Old Grove for human visual approval. Nothing map-wide changes until that approval.

## Visual assessment (before M3.B)

- **Trees** are part-built: cylinder trunks under clusters of smooth spheres, conifers as
  stacked cones. They read as toys, not foliage, and clash with the meshed props.
- **Ground** is a LeafyGrass carpet (`grass short`): clean, but reads as flat texture.
- **Rocks, bushes, logs, ruin walls** are generated textured meshes (`generate_mesh`):
  decent alone, a different style from the part-built trees and pillars.
- **Pillars and ruins** are stacked primitives: the most placeholder-looking pieces.
- **Characters and enemies** are chunky, colourful cartoon meshes: the environment should
  meet them with soft, rounded, stylized shapes, not realism or high-frequency detail.
- **Light** (golden default, random sky per run) is good and stays.

**Direction:** stylized fantasy forest. Crowns as layered leaf masses (shaded cores fringed
with leaf cards, cel-like light bands, normals bent away from the crown's heart so it lights
as one soft volume); conifers as drooping layered boughs; warm bark and stone; chunky
faceted rocks with moss caps; one warm palette shared by every asset.

## Pipeline

| Step | Command / file |
|---|---|
| Recipes (the editable source of truth) | `tools/art/assets.py`, geometry helpers `tools/art/geo.py` |
| Build: `.blend`, GLBs, game data, manifest | `"$BLENDER" -b -P tools/art/kit.py` (5 s) |
| Blender source, one collection per asset | `assets/art/wardwood_kit.blend` |
| Roblox-importable meshes | `assets/art/export/<Asset>.glb` (one object per colour part) |
| Game data (packed positions, normals, triangles) | `src/server/Wardwood/ArtMeshes/<Asset>.luau` |
| Triangles, parts, colours, sizes | `assets/art/manifest.json` |
| Asset renders | `"$BLENDER" -b assets/art/wardwood_kit.blend -P tools/art/render.py -- <outdir>` |
| Showcase from the game camera, offline | `lune run tools/map/export_world.luau <out.json> short art`, then `tools/map/preview_blender.py` |

Change a recipe, rerun the kit, commit the regenerated files. Never hand-edit the generated
Luau. Blender renders show shape and palette only; they are not Studio evidence.

## In the game now: no upload

`server/Wardwood/ArtKit` rebuilds each packed part as an `EditableMesh`, bakes it with
`AssetService:CreateDataModelContentAsync` (static content that replicates to every client
with the parts using it), and keeps a template Model in `ServerStorage.WardwoodArt`.
`server/Wardwood/Showcase` clones templates where `Core/ArtShowcase` plans them. The content
lasts for the server session: nothing is saved into the place, nothing is uploaded, no
asset id exists. Every art part is visual only (no collision, query or touch); the props
it stands in for keep their colliders, only hidden. Leaf meshes carry the `WWFoliage` tag
so the canopy fade (client `CanopyController`) ghosts them out of the camera's way.

Studio: `Config/Wardwood.ArtShowcase` turns it on at server start. BonkDev:
`art on | art off | art goto | art grass <r> <g> <b>`.

## Making assets permanent (needs a person's go-ahead)

1. Import `assets/art/export/<Asset>.glb` with Studio's 3D Importer (or upload as `Model`
   through Open Cloud: see the roblox-3d-model skill). This creates Roblox assets.
2. Record each part's MeshId in `assets/meshes/manifest.json`; set colours from
   `assets/art/manifest.json` (the GLB materials carry them, but set `MeshPart.Color`).
3. `python tools/assets/emit_assets.py` writes them into `assets/models/Assets.rbxmx`.
4. Point `ArtKit.template` at `ReplicatedStorage.Assets` instead of the runtime build.

## After approval: the rest of the Wardwood

- Map-wide: Builder places kit assets for the swapped kinds instead of blueprints (the
  colliders as today), the showcase's swap table becoming the map's.
- Grass: the showcase's 3D grass is ~250k triangles for ~8,500 studs²; map-wide it must be
  client-side and streamed in near the camera, with fewer blades per patch.
- Distance: lighter LOD variants of the broadleaf and spruce for far trees; the ancients
  can stay full.
- Still to model: bushes, ferns, logs, stumps, ruin walls, arches, the Elder, the ancient
  fir and the Sun Temple, in the same palette.

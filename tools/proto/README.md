# Wardwood prototype: Studio workflow

Branch `proto/wardwood`. Everything here runs in a **local, unpublished copy** of the
place. The shared BonkHorde place is never opened for writing, synced or pulled into.

## Safety, in one paragraph

The prototype only switches on when **all** of these hold (`src/shared/Core/ProtoGate.luau`,
specced in `tests/Wardwood.spec.luau`): the place carries the marker
`ServerStorage.BonkProto = "wardwood"`, it is running in Studio, `game.PlaceId` and
`game.GameId` are both 0 (a local file), and the place id is not the live one. Anything
else runs the normal MossyWoods map, and a marker that was refused prints a warning. The
prototype also has its own build (`work/push-proto`), its own port (34882) and its own pull
script (`ProtoPull`, which refuses to run in a published place), so the shared place's
`BonkPull` on port 34880 never sees prototype code.

## One-time setup

1. Open the shared place as usual, change nothing, then **File → Save to File As…** and save
   `D:\Dev.2\BonkHorde-protos\Wardwood.rbxl`. Close the shared place.
2. **File → Open from File…** → `Wardwood.rbxl`. In the command bar:
   `print(game.PlaceId, game.GameId)` must print `0 0`. If it does not, stop: the gate will
   refuse anyway, and we use a place built from disk instead.
3. In the copy, delete `ServerStorage.BonkPull` (so the copy can only pull the prototype) and
   add a ModuleScript `ServerStorage.ProtoPull` with the source of `tools/proto/ProtoPull.luau`.
   Save (Ctrl+S).

## Every update

```powershell
git switch proto/wardwood
powershell -ExecutionPolicy Bypass -File tools\proto\build.ps1   # gates, map proof, trees, port 34882
```

In the copy's command bar: `return require(game.ServerStorage.ProtoPull)()`. It must answer
`PROTO Packages.rbxmx ok … | Ui.rbxmx ok …`. On Play, Output must show
`BUILD bonk-0.3.0-m1b-ww0`.

## Arm and disarm (command bar, edit mode, then Ctrl+S)

Arm:

```lua
assert(game.PlaceId == 0 and game.GameId == 0, "not a local file") local v = game.ServerStorage:FindFirstChild("BonkProto") or Instance.new("StringValue") v.Name = "BonkProto" v.Value = "wardwood" v.Parent = game.ServerStorage print("armed")
```

Disarm (the copy then runs the normal map, which is how the baseline is measured):

```lua
local v = game.ServerStorage:FindFirstChild("BonkProto") if v then v:Destroy() end print("disarmed")
```

Armed, Play prints `[MapService] map profile Wardwood: armed local Studio file`. Disarmed, it
prints no profile line.

## Hooks (Play, set the Workspace attribute `BonkDev` on the server view)

| Command | Does |
|---|---|
| `look cam 1` / `2` / `3` | Stand at a fixed viewpoint and turn the camera (both profiles) |
| `look light golden` / `look light teal` | Switch the lighting condition (prototype only) |
| `look status` | Profile, lighting, ward position, light count, Wardwood prop counts |
| `perf 20` | Prints `status`, then the client samples 20 s and prints one `[Perf]` line |

`[Perf]` reports average and 1%-low FPS, the worst frame, enemy visuals on screen, map parts,
lights (and how many cast shadows), memory by tag (texture, mesh, parts, terrain, particles) and
the graphics quality level.

## Measurement recipe (same for the baseline and every configuration)

Before the first run: maximise the Studio window, and in Play open the game menu and set
Graphics to **Manual** at one fixed level. Keep both identical for every run. Studio numbers are
only good for **comparing configurations on the same machine**, never as player budgets.

1. Pick Sir Clonk, start the run, then:
   `god; level 20; weapon FireStaff; weapon LightningStaff; weapon Axe; weapon FrostRing`
2. `killall; look cam 2`, wait 5 s, `perf 20`: the **empty** reading.
3. `clock 480; spawn GoblinRunt 60; spawn Skeleton 60; spawn Slime 50; spawn RockGolem 30; spawn GoblinBruiser 30; spawn Twiglet 20`,
   wait until `status` shows about 250 enemies, then `perf 20`: the **load** reading.
4. At load, screenshot `look cam 1`, `2`, `3` into `work/proto/shots/<config>_cam<n>.png`.
5. Movement: bunny-hop from cam 1 to the ward, along the path into the band and back. Note
   every snag or lost hop chain, and where.
6. Occlusion: from cam 3 run back to the clearing at full speed. Note every moment the hero or a
   threat was hidden.

Configurations: **baseline** (disarmed), **golden** (armed, `look light golden`), **teal**
(armed, `look light teal`). The texture A/B comes later, with the first assets.

## Comparison sheet

| Config | Empty avg / 1% low FPS | Load avg / 1% low FPS | Texture MB | Lights (shadowed) | Snags | Occlusions | Readability 1–5 | Mood 1–5 | Notes |
|---|---|---|---|---|---|---|---|---|---|
| baseline | | | | | | | | | |
| golden | | | | | | | | | |
| teal | | | | | | | | | |

Paste the `[Perf]` lines under the table so the raw numbers are kept.

## Rollback

- **Prototype off:** disarm (above). The copy runs the normal map.
- **Prototype gone:** delete `Wardwood.rbxl`, then in the repo
  `git switch m1-hybrid-combat` and `git branch -D proto/wardwood` (after committing or
  discarding the branch's changes; uncommitted files follow a branch switch).
- `work/push` (the shared place's pull source) is built from `m1-hybrid-combat` and is never
  written by `tools/proto/build.ps1`.

## Plan image

`lune run tools/map/prove.luau wardwood` (map promises on the dressed layout), then
`python tools/proto/plan.py` → `work/proto/plan_wardwood.png`.

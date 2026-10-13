# Stage 3 progress notes (working file)

- Mesh route: Studio `generate_mesh` (async). Job list and prompts in `design/mesh_jobs.json`.
  Generated Models are named after the (truncated) prompt. `require(game.ServerStorage.BonkStage).collect()`
  in the edit DataModel renames them, moves them to `Workspace.Staging` on a grid starting at
  (1000, 0, 1000), 40 studs apart, 8 per row in job order, and returns what is still missing.
  `.manifest()` posts measured data to `assets/meshes/manifest.json` through the bridge.
- All 51 jobs were queued once on 2026-10-13. Re-queue only what `collect()` reports missing.
  Moderation rejects the word "goblin"; "forest imp" passes.
- Generated models face +Z (the goblin did); the renderer assumes -Z, so bake a 180 degree yaw when emitting.
- Local servers: Forge API 127.0.0.1:7860, push file server 34880 (`work/push`), bridge 34881
  (`tools/studio/bridge.py`, GET project files, POST /save?path=work/.. or assets/..).
- Python with Pillow: `D:\Forge\system\python\python.exe`. System `py` has no Pillow.
- Three roblox-asset-ui workers are building `src/ui/*.model.json` from `design/ui_contract.md`
  (Hud; Choices; Menu + EndScreens + Overlay). They were resumed after a usage-limit stop.
- Next: view staging contact sheets, regenerate rejects, emit rbxmx from the manifest into the Rojo
  tree as ReplicatedStorage.Assets, wire heroes (R6 limbs + generated parts), props scatter, sky,
  terrain materials, icons with Forge, then the real UI controllers.

## UI workers finished (2026-10-13)
- src/ui/Hud, Choices, Menu, EndScreens, Overlay .model.json exist, rojo build passes. Reports in assets/ui/NOTES.*.md.
- Gotchas for the controllers: no UIScale in the trees (add one per ScreenGui at runtime); Choices buttons,
  ChoiceTimer and GoldLabel are under a child named Footer; Minimap Dots clips square (cull dots past 114 px);
  Menu panels are siblings (CloseButton etc. are direct children of the screen Frame); tags like ReadyTag are
  Frames with a child Text; extra icon keys ThumbMossyWoods/ThumbDesert/ThumbGraveyard; hide Roblox jump button on touch.
- Icons: ImageLabels carry attribute IconName; Image empty, to be filled from an icon table.

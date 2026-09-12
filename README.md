# Scene Studio

Procedural game scenes built layer by layer in Godot 4, exported to the web
and served by GitHub Pages.

**Play:** https://mlobree.github.io/boulder-hill/ (landing page) ·
Beach Walk: https://mlobree.github.io/boulder-hill/play/#world=beach

Design note: [Specialised models for building game scenes](design/specialist-models.md)
describes how the layered scenes become a training and agentic pipeline.

## Worlds

### Beach Walk (`#world=beach`)

A stylised recreation of a third-person beach stroll: a walker on wet sand
along the surf line, sunbathers and striped umbrellas, palms, pastel art-deco
hotels, lifeguard huts, drifting clouds and gulls.

Controls: **Up** steps the pace up (stop → walk → jog), **Down** steps it
down, **Left / Right** (or A / D) turn freely, **Space** jumps, hold the
mouse (or a finger) and drag to orbit the camera. The beach is endless in
both directions; loungers, umbrellas, palms, lamps, benches, huts and people
are soft obstacles. Flags: `&inspect` orbits the walker, `&inspect&crowd`
orbits the lounger rows, `&mpfb` swaps in the MPFB-generated body.

Everyone on the beach uses the same CC0 rigged bodies and animation library
as the player (female and male bases, four hairstyles, ten painted swimwear
textures, five skin tones, seven body builds, four gaits).

## Layout

```
game/                          one Godot project, all worlds
  main.gd                      picks the world from #world=<name>, runs the tick loop
  core/                        the framework every world uses
    world_context.gd           shared state + the terrain/walkability interface
                               (ground_height, walk_height, constrain, wetness_at),
                               obstacle field, signals, palette, textures
    layers/scene_layer.gd      base class: setup(ctx) -> build(), tick(delta), on_world_wrapped()
    layers/chunked_layer.gd    scenery repeated every 200 m (3 identical copies)
    layers/mesh_batch.gd       merges primitives / posed meshes into one draw call
    layers/sky_layer.gd        environment, sun, fog, clouds; publishes the palette
    layers/camera_layer.gd     chase camera with drag-orbit and inspect modes
    layers/player_layer.gd     procedural-rig player (kept for reference)
    layers/skinned_player_layer.gd  player on a rigged body: pace, jump, footsteps
    layers/mpfb_player_layer.gd     variant using the MPFB body
    layers/tracks_layer.gd     footprints from player_step
    layers/hud_layer.gd
    characters/                humanoid rig, body/texture generators, hair ribbons,
                               SkinnedPeople (live characters + CPU pose baking,
                               body builds, contact helpers), CC0 assets, bone maps
    shaders/                   skin, hair
    web/shell.html             branded web loader
  worlds/beach/
    beach_world.gd             make_context() / make_layers() / validators()
    beach_context.gd           sand slope, sea level, tide, promenade deck
    layers/                    ocean, sand, architecture, vegetation, furniture,
                               crowd (with contact validator), fauna
    shaders/                   sand, water
docs/                          GitHub Pages: index.html (landing), play/ (the build),
                               beach/ (redirect for the old URL)
examples/                      reference clips (gitignored) and their study frames;
                               index.json tags each clip's scene family
tools/                         Blender / Python pipeline: clip trimming, walk
                               measurement, MPFB body generation, UV outfit painting,
                               reference.py (clip -> contact sheet + frames + crops)
shots/                         headless capture harness (keys, holds, drags)
design/                        the specialist-models design document
```

## Adding a world

1. `worlds/<name>/<name>_context.gd` extending `WorldContext`: implement
   `ground_height`, and `walk_height` / `constrain` / `wetness_at` if they
   differ from the terrain.
2. Layers under `worlds/<name>/layers/` extending `SceneLayer` or
   `ChunkedLayer`; reuse the core sky, camera, player, tracks and HUD layers.
3. `worlds/<name>/<name>_world.gd` with `make_context()`, `make_layers()`
   and `validators()`; register it in `main.gd`'s `WORLDS`.
4. Study the reference: `python3 tools/reference.py "examples/<clip>.mp4"`.
5. Verify headless (`godot --headless --path game --quit-after 30 | grep contacts`),
   export, capture with `shots/cdp_gpu.py`, publish.

## Pipeline

- Export: `godot --headless --path game --export-release Web docs/play/index.html`
  (GL Compatibility, single-threaded, so it runs on Pages without special headers).
- Capture: `python3 shots/cdp_gpu.py <url> 8,16 out "6:ArrowUp,10:Space,12:Drag_-260_0"`.
- Characters: Quaternius Universal Base Characters + Universal Animation Library
  (CC0), retargeted at import via `core/characters/assets/bonemap_*.tres`;
  outfits painted in UV space by `tools/paint_*.py`; MPFB bodies from
  `tools/mpfb_build.py` in headless Blender.

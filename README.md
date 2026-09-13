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

### Street Drive (`#world=street`)

A suburban street modelled on the driving clips: a small yellow hatchback
with a black roof on a two-lane road with a double yellow centre line,
parked cars along both kerbs, traffic in both lanes that keeps its distance,
kerbs and sidewalks, grass verges with fan palms and leafy trees, garden
walls and pitched-roof houses, lamps, a stop sign, pedestrians in casual
clothes, and a downtown skyline far off.

Controls: **Up** accelerates, **Down** brakes / reverses, **Left / Right**
steer (less lock at speed), drag to orbit (the camera boom pulls in rather
than clipping into parked cars). The road is endless.
`&variant=walk` puts the on-foot player on the street instead.

Segments added for it: `segments/vehicles/` (procedural cars: hatch, sedan,
suv, pickup; parked + traffic layer with car-following) and the vehicle
player mode `segments/player/vehicle_player_layer.gd`. Shared palm and tree
generators live in `segments/vegetation/species/`.

## Layout

Segment-first: each specialist owns one directory under `game/segments/`;
a world is only its assembly, its terrain context and its brief.

```
game/
  main.gd                      picks the world from #world=<name>, runs the tick loop
  core/                        the contract, nothing else
    world_context.gd           shared state + terrain/walkability interface
                               (ground_height, walk_height, constrain, wetness_at),
                               obstacle field, signals, palette, textures
    layers/scene_layer.gd      base class: setup(ctx) -> build(), tick(delta), on_world_wrapped()
    layers/chunked_layer.gd    scenery repeated every 200 m (3 identical copies)
    layers/mesh_batch.gd       merges primitives / posed meshes into one draw call
    web/shell.html             branded web loader
  segments/                    one directory per specialist
    sky/                       environment, sun, fog, clouds; publishes the palette
    ground/                    terrain surface; variants/beach.gd + shaders/sand.gdshader
    water/                     variants/beach.gd + shaders/water.gdshader
    architecture/              variants/beach.gd (hotels, promenade, lifeguard huts)
    vegetation/                species/palm.gd (palms, leafy trees); variants/beach.gd, street.gd
    props/                     variants/beach.gd (loungers, umbrellas, clutter; exposes spots)
    characters/                humanoid rig, body/texture generators, hair ribbons,
                               SkinnedPeople (live characters, CPU pose baking, builds,
                               contact helpers), CC0 assets, bone maps, skin/hair shaders
    crowd/                     variants/beach.gd (sunbathers, sitters, waders, swimmers,
                               strollers; contact validator)
    fauna/                     variants/beach.gd (gulls)
    player/                    on-foot player (pace, jump, footsteps) and vehicle mode
    vehicles/                  car generator; variants/street.gd (parked cars + traffic)
    camera/                    chase camera, drag-orbit, inspect modes
    tracks/                    footprints
    hud/
  worlds/beach/, worlds/street/
    <name>_world.gd            make_context() / make_layers() / validators()
    <name>_context.gd          terrain, walkable area, constants
    brief.md                   reference digest and per-segment briefs
docs/                          GitHub Pages: index.html (landing), play/ (the build),
                               beach/ (redirect for the old URL)
examples/                      reference clips (gitignored) and their study frames;
                               index.json tags each clip's scene family
tools/                         Blender / Python pipeline: clip trimming, walk measurement,
                               MPFB body generation, UV outfit painting, reference.py
shots/                         headless capture harness (keys, holds, drags)
design/                        the specialist-models design document
```

Naming: a segment's shared code has a plain name (`VegetationLayer`); a
world's variant is prefixed (`BeachVegetation`). The word "beach" appears
only in variant files and under `worlds/beach/`.

## Adding a world

1. `worlds/<name>/<name>_context.gd` extending `WorldContext`: implement
   `ground_height`, and `walk_height` / `constrain` / `wetness_at` if they
   differ from the terrain.
2. One variant per segment under `segments/<segment>/variants/<name>.gd`
   extending `SceneLayer` or `ChunkedLayer`; reuse the segment's generators
   and the generic sky, camera, player, tracks and HUD layers.
3. `worlds/<name>/<name>_world.gd` with `make_context()`, `make_layers()`
   and `validators()`; register it in `main.gd`'s `WORLDS`.
4. Study the reference: `python3 tools/reference.py "examples/<clip>.mp4"`.
5. Verify headless (`godot --headless --path game --quit-after 30 | grep contacts`),
   export, capture with `shots/cdp_gpu.py`, publish.

## Pipeline

- Export: `godot --headless --path game --export-release Web docs/play/index.html`
  (GL Compatibility, single-threaded, so it runs on Pages without special headers).
- Capture: `python3 shots/cdp_gpu.py <url> 8,16 out "6:ArrowUp~2.0,10:Space,12:Drag_-260_0"`
  (`~s` holds a key; the harness clicks the canvas before each key so it has focus).
- Export from the repo root with an absolute target path; a relative one is
  resolved against `game/` and fails.
- Characters: Quaternius Universal Base Characters + Universal Animation Library
  (CC0), retargeted at import via `segments/characters/assets/bonemap_*.tres`;
  outfits painted in UV space by `tools/paint_*.py`; MPFB bodies from
  `tools/mpfb_build.py` in headless Blender.

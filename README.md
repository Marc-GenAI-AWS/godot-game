# Godot web demos

Two small Godot 4 scenes exported to the web and served by GitHub Pages.

## Beach Walk

**Play it:** https://mlobree.github.io/boulder-hill/beach/

A stylised recreation of a third-person beach stroll: a walker on wet sand
along the surf line, sunbathers and striped umbrellas, palms, pastel art-deco
hotels, a lifeguard tower, drifting clouds and a passing seagull. Steer with
the arrow keys or A/D; Space or tap stops and starts walking. The scenery
repeats every 200 m so the walk loops seamlessly.

The scene is built as a stack of independent **layers** so any one element
can be specialised without touching the rest:

```
beach/
  main.gd                    composition root: instantiates layers, runs the tick loop
  world_context.gd           shared state: time, tide line, sand_height(), textures, signals
  characters/humanoid.gd     primitive-based person: walk cycle, sit/lie poses, bake_static()
  shaders/sand.gdshader      dry/wet sand with a moving tide line
  shaders/water.gdshader     swells, depth colour, edge foam, breaker lines
  layers/
    beach_layer.gd           base class: setup(ctx) -> build(), tick(delta), on_world_wrapped()
    chunked_layer.gd         base for scenery repeated every 200 m (3 identical copies)
    mesh_batch.gd            merges many primitives into one mesh (one draw call)
    sky_layer.gd             environment, sun, fog, drifting cloud sprites
    ocean_layer.gd           the sea mesh + water shader
    sand_layer.gd            the beach mesh + sand shader, shell scatter
    tracks_layer.gd          footprints stamped on player_step, fading over time
    architecture_layer.gd    hotels with balconies, boardwalk, lamps, lifeguard tower
    vegetation_layer.gd      palms (batched trunk, alpha-cut fronds that sway), hedges
    furniture_layer.gd       loungers, umbrellas, towels, beach balls; exposes `spots`
    crowd_layer.gd           sunbathers/sitters on furniture spots, strollers, waders, swimmers
    fauna_layer.gd           circling gull flock; gulls on the sand that flush when approached
    player_layer.gd          the walker, steering, footstep events, seamless chunk wrap
    camera_layer.gd          over-the-shoulder chase cam with step-synced bob
    hud_layer.gd             text overlay
```

Layers never reference each other directly; they read `WorldContext` or
listen to its signals (`player_step`, `world_wrapped`). The two exceptions
(crowd needs furniture spots, camera needs the player's heading) are wired
explicitly in `main.gd`. To work on one element, edit its layer; to replace
it, subclass `BeachLayer`/`ChunkedLayer` and swap it in the list in `main.gd`.

## Boulder Hill

A small Godot 4 scene: a large boulder rolls down a grassy hillside, kicking up
dust and flattening the grass in its path, with a chase camera following it
into the valley. The grass is ~70k shader-animated blades in a MultiMesh,
swaying in a scrolling wind field. Click, tap, or press
R / Space to roll it again. It restarts on its own once the rock comes to rest.

**Play it:** https://mlobree.github.io/boulder-hill/

The web build in `docs/` is served by GitHub Pages.

## Layout

- `boulder/` – the Godot project. Everything (terrain, trees, rock, camera,
  particles, lighting, grass placement) is generated in `main.gd`, so the
  scene file is tiny. `grass.gdshader` bends the blades with wind noise and
  pushes them away from the boulder.
- `docs/` – the exported Web build (HTML + JS + WASM + PCK). Regenerate with:

  ```bash
  cd boulder
  godot --headless --export-release Web ../docs/index.html
  ```

- `shots/` – a small DevTools-protocol script that drives headless Chromium to
  screenshot the web build at fixed times, used to check renders without a GUI.

Built with Godot 4.7.2 using the GL Compatibility renderer and a
single-threaded web export, so it runs on GitHub Pages without special headers.

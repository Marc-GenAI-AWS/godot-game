# 1. The game

A Godot 4.7 project in `game/`, rendered with the GL Compatibility backend so
the web export runs on GitHub Pages without special headers.

## Run it

```bash
godot --path game -- --world=beach          # or --world=street
```

Flags after `--` mirror the URL fragment the web build reads
(`#world=beach&inspect`): `--inspect` orbits the player, `--crowd` orbits the
lounger rows, `--lite` thins the scene, `--variant=walk|drive` picks a player
mode on the street, `--nomenu` suppresses the right-click menu, `--validate`
runs the world's assertions.

Controls are in the HUD. Right-click opens the menu that swaps any
model-written layer, changes the character's outfit and hair, or resets.

Headless (no GPU, no window) is how the verifier gates a layer:

```bash
godot --headless --path game --quit-after 30 | grep contacts
```

## How a scene is put together

Three ideas, and that is the whole framework:

**A layer** is one file implementing `build()`. `game/core/layers/scene_layer.gd`:

```gdscript
class_name SceneLayer extends Node3D
var ctx: WorldContext

func build() -> void: pass                    # the one method a layer implements
func tick(_delta: float) -> void: pass        # optional, per frame
func on_world_wrapped(_dz: float) -> void: pass   # optional, player looped a chunk
```

with helpers `box()`, `cylinder()`, `sphere()` and `grid_mesh()`.
`ChunkedLayer` replaces `build()` with `build_chunk(chunk, rng)`, called three
times with the same seed at −200 m, 0 and +200 m so scenery repeats seamlessly
as you walk. `MeshBatch` merges primitives into one draw call — the difference
between a scene that runs at 140 fps and one that does not.

**The context** (`game/core/world_context.gd`) is the only thing layers share:
elapsed time and wind, the player and camera, the palette the sky publishes
(`sky_zenith`, `sky_horizon`, `sun_dir`, `sun_color`, `fog_color`), the
procedural textures, the obstacle field (`add_obstacle`, `resolve_obstacles`,
`free_distance`), and the terrain interface a world overrides: `ground_height`,
`walk_height`, `constrain`, `wetness_at`.

**A world** is an assembly, nothing more. `game/worlds/beach/beach_world.gd`:

```gdscript
class_name BeachWorld extends RefCounted

static func make_context() -> WorldContext: return BeachContext.new()

static func make_layers(ctx: WorldContext) -> Array[SceneLayer]:
    var sky := ctx.layer("sky", SkyLayer)            # ctx.layer() honours --swap overrides
    ...
    return [sky, ocean, sand, tracks, architecture, vegetation, furniture,
            crowd, player, fauna, camera, hud]       # draw/update order

static func validators(layers: Array[SceneLayer]) -> void:
    ...                                              # post-build assertions
```

Every layer is created through `ctx.layer("<segment>", DefaultScript)`. That
indirection is what lets the verifier and the in-game menu replace one layer
with a model-written one without touching anything else.

## Grow it

### Add a layer to an existing world

Write `game/segments/<segment>/variants/<world>.gd` extending `SceneLayer` or
`ChunkedLayer`, then add it to that world's `make_layers()` in the right
position. Naming rule: shared segment code gets a plain name
(`VegetationLayer`), a world's variant is prefixed (`BeachVegetation`). The
word "beach" appears only in variant files and under `worlds/beach/`.

### Add a whole new world

1. `worlds/<name>/<name>_context.gd` extending `WorldContext`: implement
   `ground_height`, plus `walk_height` / `constrain` / `wetness_at` where the
   walkable area differs from the terrain.
2. One variant per segment under `segments/<segment>/variants/<name>.gd`,
   reusing the segment's generators and the generic sky, camera, player,
   tracks and HUD layers.
3. `worlds/<name>/<name>_world.gd` with the three static methods above, and
   register it in `main.gd`'s `WORLDS` dictionary.
4. `worlds/<name>/brief.md`: the reference digest and a brief per segment.
   This is what the specialists are eventually asked to match.
5. Verify headless, then export and capture.

A new world costs the models nothing: sky layers are world-agnostic, and the
other specialists were trained on two worlds, so their output generalises
better than you would expect. What they cannot do is invent a segment that has
no contract.

### Add a segment a specialist can write

This is the expensive one, and the order matters:

1. **Build it by hand first**, for at least one world. You need a gold example.
2. **Write the contract** (`pipeline/contract/<segment>.md`): the engine
   version, the base class, which `WorldContext` fields may be read, the
   conventions, the capture recipe, and one or two complete gold layers. Copy
   the shape of `pipeline/contract/sky.md`. Where a layer would otherwise have
   to author a shader, expose *knobs* instead — ground and water learned this
   the hard way (page 6).
3. **Write the rubric** (`pipeline/rubrics/<segment>.md`): the attributes the
   judge scores 0-10 with evidence.
4. **Add a brief sampler** in `pipeline/briefs.py` and an entry in
   `pipeline/common.py`'s `SEGMENTS`: which world to capture in, the shot
   times, the capture script, optional per-world variants, reference frames and
   a pass bar.
5. Then [page 2](02-retrain-a-specialist.md).

### Assets

Characters use Quaternius Universal Base Characters and the Universal
Animation Library (both CC0), retargeted at import through
`game/segments/characters/assets/bonemap_*.tres`. Outfits are painted in UV
space by `tools/paint_*.py`; the alternative MPFB bodies come from
`tools/mpfb_build.py` in headless Blender. Everything else in the game is
procedural — generated from code at load time, which is exactly why a model
can write it.

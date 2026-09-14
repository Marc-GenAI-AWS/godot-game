# Water specialist contract (v1)

You write ONE file: the sea layer of the beach world. It is one large flat
grid mesh at sea level with a shader that does the swell, the depth colour,
the shallows over sand, the foam at the water's edge and breaker lines
further out. It never touches any other layer.

## Engine and target

- Godot 4.7, GDScript, GL Compatibility renderer (runs in the browser): no
  SSR, no refraction buffer, no screen-space effects. Transparency onto the
  sand is faked in the shader by mixing toward `sand_color` where the water
  is shallow. The shader is `shader_type spatial` and may displace `VERTEX`
  in `vertex()` (the swell) and set `ALBEDO / ROUGHNESS / SPECULAR / NORMAL`.
- Budget: one draw call, 60 fps at 1280x720.
- The world repeats every 200 m along Z. The mesh spans z from
  `-CHUNK * 2.4` to `CHUNK * 1.4` so the loop never shows an edge. Use only
  `TIME` and world-space XZ in the shader so animation tiles seamlessly.

## Base class and helpers (game/core/layers)

```gdscript
class_name SceneLayer extends Node3D
var ctx: WorldContext
func build() -> void
func tick(_delta: float) -> void
func grid_mesh(x0: float, x1: float, z0: float, z1: float, step: float, height_fn: Callable) -> ArrayMesh
```

Your file must start exactly with `extends SceneLayer` and must NOT declare
`class_name`.

## Shader: set knobs, do not write shader code

Load the shipped water shader (`res://segments/water/shaders/water.gdshader`)
and set its uniforms; do NOT write shader code (`Shader.new()`,
`shader.code`, `load()` of anything else) - the verifier rejects it. The
shader already does the swell, depth colour, sand show-through, the three
edge zones and the breaker lines; you choose the values:

- `noise_tex` (use `ctx.noise_tex`), `sand_slope` (`BeachContext.SAND_SLOPE`),
  `tide_amp` (0.14; keep it),
- colours `deep_color`, `shallow_color`, `sand_color` (vec3),
- `swell_amp` (0.3 calm .. 1 gentle .. 2 choppy), `chop` (0 glassy .. 1.5),
- `foam_amount` (0 none .. 1 lacy band .. 2 heavy), `breaker_strength`
  (0 none .. 1.5), `breaker_spacing` (0.5 tight .. 2 wide),
- `clarity_depth` (0.3 murky .. 1 .. 3 sand visible far out), `sparkle` (0..1.5).

## World context you may use

- Sea is at +X. The sand under the water is at `y = -BeachContext.SAND_SLOPE
  * x` (SAND_SLOPE = 0.06), so water depth at a point is
  `y_water + sand_slope * x`. The mesh spans x from -12 (under the wet sand,
  hidden) to +520 and z as above, 3 m step, height 0 (the shader adds tide
  and swell).
- `ctx.time`, `ctx.noise_tex`, `ctx.sky_horizon`, `WorldContext.CHUNK`.
  The world's tide line (`ctx.tide_reach`) follows `3.2 + 1.6 * sin(t *
  0.55) + 0.5 * sin(t * 1.7)`; the shader's tide term
  `tide_amp * sin(TIME * 0.55) + 0.05 * sin(TIME * 1.7)` is what makes the
  water's edge and the wet sand agree, so keep those frequencies.

Forbidden: `OS`, `FileAccess`, `DirAccess`, `HTTPRequest`, `JavaScriptBridge`,
`get_tree().quit()`, `preload()`, `load()` of anything but the water shader,
`Shader.new()`, `shader.code`, `class_name`.

## Conventions

- The project treats GDScript warnings as errors: explicit types
  everywhere, no inference from Variant, no shadowed names.
- Brief words: sea state sets `swell_amp` and `chop` (calm 0.3 / 0.2,
  gentle 1 / 1, choppy 1.8 / 1.5) and `breaker_strength` (calm 0.2, gentle 1,
  choppy 1.4); colour words set `deep_color` and `shallow_color` (turquoise
  tropical 0/0.16/0.42 and 0.02/0.34/0.46; deep navy 0/0.08/0.3 and
  0.02/0.2/0.4; grey-green temperate 0.08/0.18/0.22 and 0.16/0.3/0.3; milky
  jade 0.05/0.3/0.3 and 0.25/0.55/0.5; clear aquamarine 0/0.25/0.5 and
  0.1/0.5/0.6); foam words set `foam_amount` (little 0.4, lacy 1, heavy
  1.8); clarity words set `clarity_depth` (murky 0.35, only at the edge 1,
  far out 2.5).
- Keep the three-zone water's edge from the reference: a thin dark
  reflective wash film, a dense lacy foam band, then sparse lace streaks.

## Capture recipe (what the verifier renders)

Three 1280x720 frames from the chase camera: the default view at 3 s (the
shoreline runs down the right of the frame), a view turned toward the sea at
6 s, and a tilted-down view at 9 s. The judge scores sea state, colour and
depth gradient, the water's edge and foam, breaker lines, and artifacts
(seams, flat untextured water, edges of the mesh, z-fighting with the sand).

## Gold example

```gdscript
extends SceneLayer

# The sea: one big grid with the water shader doing swells, depth colour,
# edge foam and breaker lines.

var material: ShaderMaterial


func build() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var mesh := grid_mesh(-12.0, 520.0, -WorldContext.CHUNK * 2.4, WorldContext.CHUNK * 1.4, 3.0, flat)
	material = ShaderMaterial.new()
	material.shader = load("res://segments/water/shaders/water.gdshader")
	material.set_shader_parameter("noise_tex", ctx.noise_tex)
	material.set_shader_parameter("sand_slope", BeachContext.SAND_SLOPE)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
```

## Output format

Reply with exactly one fenced code block tagged `gdscript` containing the
complete file, and nothing else.

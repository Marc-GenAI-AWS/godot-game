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

## Shader

Load the shipped water shader and set its uniforms, or write your own with
`Shader.new()` and `shader.code = "..."`. `load()` is allowed ONLY for
`res://segments/water/shaders/water.gdshader`, whose uniforms are
`noise_tex` (sampler2D, use `ctx.noise_tex`), `sand_slope` (float,
`BeachContext.SAND_SLOPE`), `tide_amp` (float, 0.14), `deep_color`,
`shallow_color`, `sand_color` (vec3 colours).

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
`class_name`.

## Conventions

- The project treats GDScript warnings as errors: explicit types
  everywhere, no inference from Variant, no shadowed names.
- Brief words: sea state (calm / gentle / choppy) scales swell amplitudes
  and breaker frequency; colour words set `deep_color` and `shallow_color`
  (turquoise tropical, deep navy, grey-green temperate, milky jade); foam
  words scale the edge foam and breaker foam; clarity words set how far the
  sand shows through (the depth at which `sand_color` fades out).
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

The water shader it loads, for reference (write a variant inline with
`Shader.new()` when the brief needs a different sea):

```glsl
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float sand_slope = 0.06;
uniform float tide_amp = 0.14;
uniform vec3 deep_color : source_color = vec3(0.0, 0.16, 0.42);
uniform vec3 shallow_color : source_color = vec3(0.02, 0.34, 0.46);
uniform vec3 sand_color : source_color = vec3(0.38, 0.31, 0.23);
varying vec3 v_world;
varying float v_depth;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float tide = tide_amp * sin(t * 0.55) + 0.05 * sin(t * 1.7);
	float shore = clamp(w.x / 18.0, 0.0, 1.0);
	float swell = 0.10 * sin(w.x * 0.35 - t * 1.1) + 0.05 * sin(w.z * 0.4 + w.x * 0.2 + t * 0.8)
		+ 0.03 * sin((w.x + w.z) * 1.6 - t * 2.3);
	float y = tide + swell * shore;
	VERTEX.y += y;
	v_world = vec3(w.x, y, w.z);
	v_depth = y + sand_slope * w.x;
	float dx = 0.10 * 0.35 * cos(w.x * 0.35 - t * 1.1) * shore;
	NORMAL = normalize(vec3(-dx, 1.0, 0.0));
}
void fragment() {
	float t = TIME;
	float d = v_depth;
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 7.0, d));
	col = mix(sand_color, col, smoothstep(0.0, 0.28, d));
	float n1 = texture(noise_tex, v_world.xz * vec2(0.25, 0.08) + vec2(-t * 0.08, t * 0.02)).r;
	float n2 = texture(noise_tex, v_world.xz * vec2(0.9, 0.5) + vec2(t * 0.05, -t * 0.07)).r;
	float n4 = texture(noise_tex, v_world.xz * vec2(1.8, 1.1) + vec2(-t * 0.11, t * 0.04)).r;
	float lace = n1 * 0.45 + n2 * 0.5 + n4 * 0.35;
	float wash = smoothstep(0.07, 0.015, d);
	float foam_band = smoothstep(0.03, 0.07, d) * smoothstep(0.24, 0.12, d);
	float outer = smoothstep(0.18, 0.28, d) * smoothstep(0.55, 0.3, d);
	float edge_foam = foam_band * smoothstep(0.28, 0.5, lace + 0.25) + outer * smoothstep(0.42, 0.62, lace);
	edge_foam = max(edge_foam, wash * smoothstep(0.5, 0.7, lace) * 0.5);
	vec3 wet_film = mix(sand_color * 0.75, vec3(0.32, 0.46, 0.64), 0.4);
	col = mix(col, wet_film, wash);
	float band = sin(v_world.x * 0.5 - t * 1.1 + n1 * 2.0);
	float breakers = smoothstep(0.75, 0.95, band) * smoothstep(3.0, 9.0, v_world.x) * smoothstep(40.0, 15.0, v_world.x);
	breakers *= smoothstep(0.3, 0.6, n2);
	float foam = clamp(edge_foam + breakers * 0.9, 0.0, 1.0);
	col = mix(col, vec3(0.88, 0.91, 0.94) * (0.82 + 0.18 * n2), foam);
	float r1 = texture(noise_tex, v_world.xz * 0.6 + vec2(t * 0.06, t * 0.04)).r;
	float r2 = texture(noise_tex, v_world.xz * 0.6 + vec2(0.013, 0.0) + vec2(t * 0.06, t * 0.04)).r;
	float r3 = texture(noise_tex, v_world.xz * 0.6 + vec2(0.0, 0.013) + vec2(t * 0.06, t * 0.04)).r;
	vec3 ripple = normalize(vec3((r1 - r2) * 6.0, 1.0, (r1 - r3) * 6.0));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(ripple, 0.0)).xyz, 0.12));
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.3, 0.05, wash), 0.85, foam);
	SPECULAR = mix(mix(0.3, 0.6, wash), 0.15, foam);
	METALLIC = 0.0;
}
```

## Output format

Reply with exactly one fenced code block tagged `gdscript` containing the
complete file, and nothing else. A custom shader goes inside it as a string
assigned to `shader.code`.

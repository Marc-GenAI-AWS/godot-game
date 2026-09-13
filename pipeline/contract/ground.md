# Ground specialist contract (v1)

You write ONE file: the ground layer for the world named in the brief. On the
beach it is the sand surface (a height-field mesh with a sand shader: grain,
a wet band that follows the tide, a thin water sheet) and the shell scatter.
On the street it is the asphalt road with markings, kerbs, sidewalks and the
lawns. The terrain SHAPE is not yours: heights come from the world context
(`ctx.ground_height`), you give the surface its look. Never touch any other
layer.

## Engine and target

- Godot 4.7, GDScript, GL Compatibility renderer (runs in the browser): no
  SSR, no SDFGI, no tessellation; shaders are `shader_type spatial` with
  `ALBEDO / ROUGHNESS / SPECULAR / NORMAL_MAP / NORMAL_MAP_DEPTH`.
- Budget: at most about 8 draw calls for the whole ground (beach) or per
  chunk (street); 60 fps at 1280x720. Scatter (shells, pebbles) is one
  `MultiMesh`, never many nodes.
- The world repeats every 200 m along Z (`WorldContext.CHUNK`). The beach
  ground is one `SceneLayer` whose mesh spans z from -2.2 to +1.2 chunks so
  the loop never shows an edge; the street ground is a `ChunkedLayer` with
  `build_chunk` (chunk-local z in [-CHUNK, 0)) plus a lawn plane in `build()`.

## Base classes and helpers (game/core/layers)

```gdscript
class_name SceneLayer extends Node3D
var ctx: WorldContext
func build() -> void
func tick(_delta: float) -> void
# helper: a triangulated height-field, normals + tangents generated, UV = xz * 0.1
func grid_mesh(x0: float, x1: float, z0: float, z1: float, step: float, height_fn: Callable) -> ArrayMesh

class_name ChunkedLayer extends SceneLayer
var seed_v := 1
func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void   # implement; call super.build() if you override build()
```

Your file must start with `extends SceneLayer` (beach) or
`extends ChunkedLayer` (street) and must NOT declare `class_name`.

`MeshBatch` (add_box_at / add_box / add_cylinder / add / instance /
commit_with) merges static boxes and cylinders into one draw call per
material; see the street gold example.

## Shaders

You may load the two shipped shaders and set their uniforms, or write your
own with `Shader.new()` and `shader.code = "..."` (a spatial shader string).
`load()` is allowed ONLY for these two paths:

- `res://segments/ground/shaders/sand.gdshader` with uniforms
  `noise_tex` (sampler2D, use `ctx.noise_tex`), `grain_normal` (sampler2D,
  use `ctx.sand_normal_tex`), `reach_x` (float, world X of the wet line; set
  it every frame from `ctx.tide_reach`), `dry_color`, `wet_color`,
  `sky_color` (vec3 colours; `sky_color` from `ctx.sky_horizon`).
- `res://segments/ground/shaders/asphalt.gdshader` with uniforms `noise_tex`,
  `base_color` (vec3), `lane_x` (float, `StreetContext.LANE_X`),
  `track_offset` (float).

Both shaders sample world-space XZ so they tile seamlessly across chunks.

## World context you may use

- `ctx.ground_height(x, z)`: beach sand height (slopes down into the sea at
  +X, up the beach at -X, with gentle undulation); street ground is 0.
- Beach (`BeachContext`): sea at +X, `ctx.tide_reach` is the world X the last
  wave reached (about 1.6 to 4.8, moving), the walker walks the sand from
  x = -62 (promenade deck) to x = +4. The sand mesh must cover x from -130 to
  +70 and z from `-CHUNK * 2.2` to `CHUNK * 1.2` at a 2 m step. Shell scatter
  lives on the tide line (x from -8 to 3, some further up the beach).
- Street (`StreetContext`): `ROAD_HALF` (6), `LANE_X` (1.9), `KERB_H`
  (0.15), `WALK_OUT` (9), `LOT_X` (13.5). The road slab spans |x| < 6 at y = 0;
  kerbs at |x| = 6.15 rise `KERB_H`; sidewalks from 6.3 to 9 at `KERB_H`;
  lawns from 9 outward at y = -0.02 (one big plane in `build()`); a crosswalk
  and stop line 12 m after each chunk start (z = -CHUNK + 12), driveways cut
  the verge every 40 m. Other layers (props, crowd, vehicles) assume exactly
  these heights, so keep them.
- `ctx.noise_tex`, `ctx.sand_normal_tex`, `ctx.sky_horizon`, `ctx.mat(color,
  roughness)`, `WorldContext.CHUNK`.

Forbidden: `OS`, `FileAccess`, `DirAccess`, `HTTPRequest`, `JavaScriptBridge`,
`get_tree().quit()`, `preload()`, `load()` of anything but the two shaders
above, `class_name`.

## Conventions

- Deterministic (seeded RNGs only).
- The project treats GDScript warnings as errors: explicit types everywhere
  (`var n := 3`, `var c: Color = ...`), no inference from Variant, no shadowed
  names, one declaration per name per scope.
- Brief words map to uniforms and geometry: sand tone words set `dry_color`
  and `wet_color` (dark warm tan / golden / pale white / grey volcanic); wet
  band width and sheet strength are yours to express in a custom shader if
  the shipped one does not fit; road tone words set `base_color` (fresh
  black about 0.16, worn grey about 0.34, brownish about 0.36/0.33/0.28);
  marking words choose double yellow centre line, single dashed white, or
  none; kerb words choose plain concrete, red-painted near the crossing, or
  granite grey; sidewalk words set slab length and crack density; lawn
  words set the two greens.

## Capture recipe (what the verifier renders)

Three 1280x720 frames from the chase camera: the default view at 3 s, a
view tilted down at the ground at 6 s, and a side view at 9 s. Numeric checks
read draw calls and fps and that a ground mesh exists. The judge scores
surface look (grain, tone), the wet band / markings, edge and kerb geometry,
grounding of the walker and props (nothing floating or sunk), and artifacts
(z-fighting, seams, tiling).

## Gold example: the beach world

```gdscript
extends SceneLayer

# The beach itself plus small scatter (shells, pebbles).

var material: ShaderMaterial


func build() -> void:
	var mesh := grid_mesh(-130.0, 70.0, -WorldContext.CHUNK * 2.2, WorldContext.CHUNK * 1.2, 2.0, ctx.ground_height)
	material = ShaderMaterial.new()
	material.shader = load("res://segments/ground/shaders/sand.gdshader")
	material.set_shader_parameter("noise_tex", ctx.noise_tex)
	material.set_shader_parameter("grain_normal", ctx.sand_normal_tex)
	material.set_shader_parameter("sky_color", ctx.sky_horizon)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "Sand"
	mi.mesh = mesh
	add_child(mi)

	# Shells and pebbles along the tide line, as one MultiMesh.
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var count := 900
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.028
	sm.height = 0.028
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	sm.material = m
	mm.mesh = sm
	mm.instance_count = count
	for i in count:
		var x := rng.randf_range(-8.0, 3.0) + (rng.randf_range(-30.0, 0.0) if rng.randf() < 0.25 else 0.0)
		var z := rng.randf_range(-WorldContext.CHUNK * 2.1, WorldContext.CHUNK * 1.1)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.8, 2.2), 0.6, rng.randf_range(0.8, 1.6))), Vector3(x, ctx.ground_height(x, z) + 0.01, z))
		mm.set_instance_transform(i, t)
		var shade := rng.randf_range(0.55, 0.85)
		mm.set_instance_color(i, Color(shade, shade * 0.95, shade * 0.85) if rng.randf() < 0.7 else Color(0.35, 0.33, 0.3))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Shells"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func tick(_delta: float) -> void:
	material.set_shader_parameter("reach_x", ctx.tide_reach)
```

The sand shader it loads, for reference (write a variant of it inline with
`Shader.new()` when the brief needs a different surface):

```glsl
shader_type spatial;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grain_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float reach_x = 3.0;
uniform vec3 dry_color : source_color = vec3(0.56, 0.41, 0.26);
uniform vec3 wet_color : source_color = vec3(0.3, 0.22, 0.15);
uniform vec3 sky_color : source_color = vec3(0.62, 0.78, 0.95);
varying vec3 v_world;
void vertex() { v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n1 = texture(noise_tex, v_world.xz * 0.12).r;
	float n2 = texture(noise_tex, v_world.xz * 0.9 + 0.3).r;
	float n3 = texture(noise_tex, v_world.xz * 0.03 + 0.7).r;
	vec3 base = dry_color * (0.84 + 0.2 * n1 + 0.08 * n2 + 0.1 * n3);
	float edge = reach_x + (n1 - 0.5) * 3.0;
	float wet = smoothstep(edge - 10.0, edge - 0.6, v_world.x);
	float sheet = smoothstep(edge - 3.5, edge - 0.4, v_world.x) * (0.6 + 0.4 * n3);
	vec3 col = mix(base, wet_color * (0.9 + 0.2 * n1), wet * 0.92);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	col = mix(col, sky_color * 0.55, sheet * fres * 0.45);
	ALBEDO = col;
	NORMAL_MAP = texture(grain_normal, v_world.xz * 2.5).rgb;
	NORMAL_MAP_DEPTH = mix(0.25, 0.05, sheet);
	ROUGHNESS = mix(0.95, 0.12, max(wet * 0.5, sheet));
	SPECULAR = mix(0.1, 0.45, sheet);
	METALLIC = 0.0;
}
```

## Gold example: the street world

```gdscript
extends ChunkedLayer

# Asphalt (shader: grain, wheel tracks, stains), faded double yellow centre
# line and white edge lines, red-painted kerb by the crosswalk, concrete
# sidewalks with slab joints and cracks, mown lawns with mottling.

var asphalt_mat: ShaderMaterial
var lawn_mat: StandardMaterial3D
var concrete_mat: StandardMaterial3D


func _init() -> void:
	seed_v = 4242


func build() -> void:
	asphalt_mat = ShaderMaterial.new()
	asphalt_mat.shader = load("res://segments/ground/shaders/asphalt.gdshader")
	asphalt_mat.set_shader_parameter("noise_tex", ctx.noise_tex)
	asphalt_mat.set_shader_parameter("lane_x", (ctx as StreetContext).LANE_X)
	# lawn: two greens mottled by noise, mown stripes
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = 12
	n.frequency = 0.04
	n.fractal_octaves = 4
	for y in 256:
		for x in 256:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var stripe: float = 0.96 + 0.04 * signf(sin(x * 0.2))
			var c: Color = Color(0.25, 0.42, 0.16).lerp(Color(0.42, 0.55, 0.2), v) * stripe
			img.set_pixel(x, y, c)
	lawn_mat = StandardMaterial3D.new()
	lawn_mat.albedo_texture = ImageTexture.create_from_image(img)
	lawn_mat.uv1_scale = Vector3(0.15, 0.15, 0.15)
	lawn_mat.uv1_triplanar = true
	lawn_mat.roughness = 1.0
	# concrete: pale with fine speckle
	var cimg := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := n.get_noise_2d(x * 3.0 + 500.0, y * 3.0) * 0.5 + 0.5
			var c: Color = Color(0.62, 0.6, 0.57).lerp(Color(0.72, 0.7, 0.67), v)
			cimg.set_pixel(x, y, c)
	concrete_mat = StandardMaterial3D.new()
	concrete_mat.albedo_texture = ImageTexture.create_from_image(cimg)
	concrete_mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	concrete_mat.uv1_triplanar = true
	concrete_mat.roughness = 0.95
	concrete_mat.vertex_color_use_as_albedo = true
	var pm := PlaneMesh.new()
	pm.size = Vector2(400.0, WorldContext.CHUNK * 3.6)
	pm.material = lawn_mat
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = Vector3(0, -0.02, -WorldContext.CHUNK * 0.5)
	add_child(mi)
	super.build()


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	# road slab with the asphalt shader
	var road := BoxMesh.new()
	road.size = Vector3(sc.ROAD_HALF * 2.0, 0.04, L)
	road.material = asphalt_mat
	var rmi := MeshInstance3D.new()
	rmi.mesh = road
	rmi.position = Vector3(0, 0.0, -L * 0.5)
	chunk.add_child(rmi)
	# paint: slightly faded, broken into dashes of wear along the length
	var paint := MeshBatch.new()
	var yellow := Color(0.82, 0.68, 0.14)
	var white := Color(0.82, 0.82, 0.8)
	var z := -L
	while z < 0.0:
		var seg := rng.randf_range(6.0, 14.0)
		var fade := rng.randf_range(0.75, 1.0)
		paint.add_box_at(Vector3(0.12, 0.012, seg), yellow * fade, Vector3(-0.15, 0.025, z + seg * 0.5))
		paint.add_box_at(Vector3(0.12, 0.012, seg), yellow * rng.randf_range(0.75, 1.0), Vector3(0.15, 0.025, z + seg * 0.5))
		for side: float in [-1.0, 1.0]:
			paint.add_box_at(Vector3(0.12, 0.012, seg), white * rng.randf_range(0.75, 1.0), Vector3(side * (sc.ROAD_HALF - 2.3), 0.025, z + seg * 0.5))
		z += seg
	var cz := -L + 12.0
	for i in 10:
		paint.add_box_at(Vector3(0.5, 0.012, 3.0), white * 0.95, Vector3(-sc.ROAD_HALF + 0.9 + i * 1.15, 0.025, cz))
	paint.add_box_at(Vector3(sc.ROAD_HALF * 2.0, 0.012, 0.3), white * 0.95, Vector3(0, 0.025, cz + 2.2))
	for i in 6:
		paint.add_cylinder(0.35, 0.35, 0.02, Color(0.3, 0.28, 0.26), Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-3.5, 3.5), 0.02, -rng.randf_range(0, L))), 12)
	paint.instance(chunk, "Paint", 0.9)
	# kerbs (red near the crosswalk) and sidewalks in concrete, with joints
	var kerb := MeshBatch.new()
	var walk := MeshBatch.new()
	for side: float in [-1.0, 1.0]:
		var kx := side * (sc.ROAD_HALF + 0.15)
		var zz := -L
		while zz < 0.0:
			var seg := 4.0
			var near_cross := zz > cz - 8.0 and zz < cz + 6.0
			kerb.add_box_at(Vector3(0.3, sc.KERB_H, seg - 0.03), Color(0.75, 0.15, 0.12) if near_cross else Color(1, 1, 1), Vector3(kx, sc.KERB_H * 0.5, zz + seg * 0.5))
			zz += seg
		var wx := side * (sc.ROAD_HALF + 0.3 + (sc.WALK_OUT - sc.ROAD_HALF - 0.3) * 0.5)
		var ww := sc.WALK_OUT - sc.ROAD_HALF - 0.3
		var z2 := -L
		while z2 < 0.0:
			var slab := 2.5
			walk.add_box_at(Vector3(ww, sc.KERB_H, slab - 0.04), Color(1, 1, 1) * rng.randf_range(0.92, 1.0), Vector3(wx, sc.KERB_H * 0.5, z2 + slab * 0.5))
			if rng.randf() < 0.08:
				walk.add_box_at(Vector3(0.03, 0.006, rng.randf_range(0.6, 2.0)), Color(0.5, 0.5, 0.48), Vector3(wx + rng.randf_range(-ww * 0.4, ww * 0.4), sc.KERB_H + 0.003, z2 + rng.randf_range(0.3, 2.0)))
			z2 += slab
		# driveway cuts through the verge every 40 m
		var dz := -L + 20.0
		while dz < 0.0:
			walk.add_box_at(Vector3(sc.LOT_X - sc.WALK_OUT + 0.5, 0.06, 3.2), Color(0.98, 0.98, 0.98), Vector3(side * (sc.WALK_OUT + (sc.LOT_X - sc.WALK_OUT) * 0.5), 0.03, dz))
			dz += 40.0
	var kmi := MeshInstance3D.new()
	kmi.mesh = kerb.commit_with(concrete_mat)
	chunk.add_child(kmi)
	var wmi := MeshInstance3D.new()
	wmi.mesh = walk.commit_with(concrete_mat)
	chunk.add_child(wmi)
```

## Output format

Reply with exactly one fenced code block tagged `gdscript` containing the
complete file for the brief's world, and nothing else.

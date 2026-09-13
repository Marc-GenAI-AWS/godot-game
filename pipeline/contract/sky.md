# Sky specialist contract (v1)

You write ONE file: the sky layer of a procedural Godot 4 scene. It owns the
sky dome, the sun (the scene's only directional light), ambient light, fog,
tonemapping and clouds. It publishes the scene palette other layers read.
It never touches any other layer and never edits the contract.

## Engine and target

- Godot 4.7, GDScript, **GL Compatibility renderer** (the build runs in the
  browser). No SSR, no SDFGI, no volumetric fog, no subsurface scattering.
  `Environment.fog_*`, `ProceduralSkyMaterial`, `DirectionalLight3D` shadows
  and `Sprite3D` billboards are all fine.
- Budget: the layer adds at most 40 draw calls and must not drop the scene
  below 60 fps at 1280x720 on a mid GPU. Clouds are billboards or a merged
  mesh, never hundreds of separate nodes.
- The world loops every 200 m along -Z. Sky nodes are far away and static,
  so `on_world_wrapped` is usually a no-op for this layer.

## Base class (game/core/layers/scene_layer.gd)

```gdscript
class_name SceneLayer
extends Node3D
var ctx: WorldContext          # set before build()
func build() -> void            # create nodes under self
func tick(_delta: float) -> void
func on_world_wrapped(_dz: float) -> void
```

Your file must start exactly with `extends SceneLayer` and must NOT declare
`class_name` (the verifier swaps it in by path).

## World context fields you may use

Read:
- `ctx.time: float` seconds since start, `ctx.wind: Vector2` (x is the drift
  direction along world X), `ctx.cloud_tex: ImageTexture` (a soft white
  cloud sprite, 256x256, alpha), `ctx.mat(color, roughness)` material cache.

Write (the palette; set them in `build()` before creating nodes, other layers
read them during their own build):
- `ctx.sky_zenith: Color`, `ctx.sky_horizon: Color`
- `ctx.sun_dir: Vector3` unit vector of the light's travel direction
  (pointing DOWN for a sun above the horizon; `sun_dir.y < 0`)
- `ctx.sun_color: Color`, `ctx.fog_color: Color`

Everything else in the context is another segment's business. Do not call
`OS`, `FileAccess`, `DirAccess`, `HTTPRequest`, `JavaScriptBridge`,
`get_tree().quit()`, `load()` or `preload()`.

## Conventions

- Sun elevation and azimuth come from the brief and describe where the sun
  sits in the sky. Elevation is the angle above the horizon; azimuth is
  compass degrees where 0 = the sun is ahead, towards -Z (down the scene),
  90 = towards +X (the sea side on the beach, the right kerb on the street),
  180 = behind the walker. `rotation_degrees = Vector3(-elevation, azimuth_yaw, 0)` on the
  light with `azimuth_yaw = 180 - azimuth` gives a light travelling towards
  the scene; compute `ctx.sun_dir` from the light's basis after adding it to
  the tree (`-basis.z`), with a hand-computed fallback.
- Night briefs: keep a faint fill (moon as the directional light, cool
  colour, low energy), never a black scene.
- Fog is distance fog with `fog_density` in the 0.0003 to 0.004 range for
  haze levels 0 to 1; the fog colour follows the horizon colour.
- Use `Environment.TONE_MAPPER_FILMIC` and a modest exposure (0.7 to 1.0).
- Clouds: `Sprite3D` with `ctx.cloud_tex`, billboard, unshaded, placed on a
  ring 500 to 950 m away at 70 to 190 m height, drifting with `ctx.wind`
  and wrapping at +/-950 m. Cover level 0 to 1 maps to 0 to about 40
  sprites; overcast should also darken and grey the zenith and horizon.
- Deterministic: seed any RandomNumberGenerator.
- The project treats GDScript warnings as errors: give every variable an
  explicit type or a typed initialiser (`var n := 3`, `var c: Color = ...`),
  never infer from a Variant (e.g. from `Array` lookups or `Dictionary`
  values without a type); avoid shadowing variable names in nested scopes.

## Capture recipe (what the verifier renders)

Three 1280x720 frames from the chase camera in the named world: the default
view at 3 s, a tilted-up view at 6 s (more sky), a side view at 9 s. The judge
scores time of day, cloud cover, haze, palette coherence, sun/shadow
direction, and artifacts against the brief.

## Gold example (the shipped sky layer for a clear tropical noon)

```gdscript
extends SceneLayer

# Sky dome, sun, fog/tonemapping and drifting cloud sprites.

var clouds: Array[Sprite3D] = []
var cloud_speed: Array[float] = []


func build() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = ctx.sky_zenith
	sky_mat.sky_horizon_color = ctx.sky_horizon
	sky_mat.sky_curve = 0.09
	sky_mat.ground_bottom_color = Color(0.4, 0.45, 0.5)
	sky_mat.ground_horizon_color = Color(0.68, 0.82, 0.96)
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.82
	env.fog_enabled = true
	env.fog_light_color = ctx.fog_color
	env.fog_density = 0.0006
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = ctx.sun_color
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.2
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.0
	sun.rotation_degrees = Vector3(-58, 40, 0)
	add_child(sun)
	ctx.sun_dir = -sun.global_transform.basis.z if sun.is_inside_tree() else Vector3(-0.35, -0.8, -0.35)

	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 16:
		var s := Sprite3D.new()
		s.texture = ctx.cloud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.pixel_size = rng.randf_range(0.6, 1.1)
		var ang := rng.randf_range(-PI, PI)
		var dist := rng.randf_range(500.0, 950.0)
		s.position = Vector3(cos(ang) * dist, rng.randf_range(70.0, 190.0), sin(ang) * dist)
		s.modulate = Color(1, 1, 1, rng.randf_range(0.8, 1.0))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		clouds.append(s)
		cloud_speed.append(rng.randf_range(0.6, 1.6))


func tick(delta: float) -> void:
	for i in clouds.size():
		var c := clouds[i]
		c.position.x += ctx.wind.x * cloud_speed[i] * delta
		if c.position.x > 950.0:
			c.position.x = -950.0
```

## Output format

Reply with exactly one fenced code block tagged `gdscript` containing the
complete file, and nothing else.

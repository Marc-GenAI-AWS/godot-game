extends SceneLayer

# Sky dome, sun, fog/tonemapping and a heavy overcast cloud sheet with a
# few bright luminous breaks where the sun's glow diffuses through.

var clouds: Array[Sprite3D] = []
var cloud_speed: Array[float] = []


func build() -> void:
	# --- Palette -----------------------------------------------------
	ctx.sky_zenith = Color(0.42, 0.48, 0.58)
	ctx.sky_horizon = Color(0.58, 0.6, 0.62)
	ctx.sun_color = Color(0.85, 0.88, 0.92)
	ctx.fog_color = Color(0.58, 0.6, 0.62)

	# --- Environment / sky --------------------------------------------
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = ctx.sky_zenith
	sky_mat.sky_horizon_color = ctx.sky_horizon
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.42, 0.43, 0.44)
	sky_mat.ground_horizon_color = ctx.sky_horizon.lerp(Color(0.55, 0.57, 0.59), 0.3)
	sky_mat.sun_angle_max = 10.0
	sky_mat.sun_curve = 0.22
	sky_mat.sky_cover = ctx.cloud_cover_tex
	sky_mat.sky_cover_modulate = Color(0.66, 0.68, 0.7, 0.95)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Ambient: greyed down to a muted warm grey-blue, kept well under the
	# sky's own fill so the cloud sheet reads as the dominant light source.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = ctx.sky_horizon.lerp(Color(0.62, 0.62, 0.64), 0.4)
	env.ambient_light_sky_contribution = 0.25
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.fog_enabled = true
	env.fog_light_color = ctx.fog_color
	env.fog_density = 0.0017
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.95
	env.adjustment_contrast = 1.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# --- Sun (energy kept low so shadows stay faint) --------------------
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = ctx.sun_color
	sun.light_energy = 0.45
	sun.shadow_enabled = false
	var azimuth_yaw := 180.0 - 90.0
	sun.rotation_degrees = Vector3(-40.0, azimuth_yaw, 0.0)
	add_child(sun)
	if sun.is_inside_tree():
		ctx.sun_dir = -sun.global_transform.basis.z
	else:
		ctx.sun_dir = Vector3(-0.5, -0.6, 0.0).normalized()

	# --- A handful of bright luminous cloud breaks for depth ------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var count := 10
	for i in count:
		var s := Sprite3D.new()
		s.texture = ctx.cloud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.pixel_size = rng.randf_range(0.8, 1.4)
		var ang := rng.randf_range(-PI, PI)
		var dist := rng.randf_range(550.0, 900.0)
		s.position = Vector3(cos(ang) * dist, rng.randf_range(90.0, 170.0), sin(ang) * dist)
		var tint := Color(0.85, 0.88, 0.92)
		s.modulate = Color(tint.r, tint.g, tint.b, rng.randf_range(0.35, 0.55))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		clouds.append(s)
		cloud_speed.append(rng.randf_range(0.5, 1.2))


func tick(delta: float) -> void:
	for i in clouds.size():
		var c := clouds[i]
		c.position.x += ctx.wind.x * cloud_speed[i] * delta
		if c.position.x > 950.0:
			c.position.x = -950.0
		elif c.position.x < -950.0:
			c.position.x = 950.0

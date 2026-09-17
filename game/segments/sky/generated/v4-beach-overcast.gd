extends SceneLayer

# Sky dome, sun, fog/tonemapping and an overcast cloud sheet with a few
# depth sprites, for a flat, washed-out grey afternoon overcast deck.

var clouds: Array[Sprite3D] = []
var cloud_speed: Array[float] = []


func build() -> void:
	# --- Palette -----------------------------------------------------
	ctx.sky_zenith = Color(0.52, 0.55, 0.58)
	ctx.sky_horizon = Color(0.62, 0.63, 0.64)
	ctx.sun_color = Color(0.78, 0.8, 0.83)
	ctx.fog_color = Color(0.6, 0.62, 0.64)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = ctx.sky_zenith
	sky_mat.sky_horizon_color = ctx.sky_horizon
	sky_mat.sky_curve = 0.08
	sky_mat.ground_bottom_color = Color(0.5, 0.52, 0.54)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.64)
	sky_mat.sun_angle_max = 3.0
	sky_mat.sun_curve = 0.12
	# Heavy broken-to-solid overcast: cloud sheet across the whole dome.
	sky_mat.sky_cover = ctx.cloud_cover_tex
	sky_mat.sky_cover_modulate = Color(0.72, 0.73, 0.75, 0.95)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = ctx.sky_horizon.lerp(Color(0.7, 0.72, 0.74), 0.5)
	env.ambient_light_sky_contribution = 0.3
	env.ambient_light_energy = 0.95
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88

	env.fog_enabled = true
	env.fog_light_color = ctx.fog_color
	env.fog_density = 0.0029
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.5

	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 0.95

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# --- Sun (barely visible through the overcast) --------------------
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = ctx.sun_color
	sun.light_energy = 0.4
	sun.shadow_enabled = false
	var azimuth_yaw: float = 180.0 - 105.0
	sun.rotation_degrees = Vector3(-34.0, azimuth_yaw, 0.0)
	add_child(sun)
	if sun.is_inside_tree():
		ctx.sun_dir = -sun.global_transform.basis.z
	else:
		ctx.sun_dir = Vector3(-0.42, -0.22, -0.87).normalized()

	# --- A few depth sprites on top of the cloud sheet -----------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for i in 8:
		var s := Sprite3D.new()
		s.texture = ctx.cloud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.pixel_size = rng.randf_range(0.9, 1.5)
		var ang: float = rng.randf_range(-PI, PI)
		var dist: float = rng.randf_range(550.0, 900.0)
		s.position = Vector3(cos(ang) * dist, rng.randf_range(90.0, 170.0), sin(ang) * dist)
		s.modulate = Color(0.78, 0.8, 0.82, rng.randf_range(0.5, 0.75))
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

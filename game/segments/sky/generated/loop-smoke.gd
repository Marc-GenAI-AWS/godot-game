extends SceneLayer

# Sky dome, low golden-hour sun, hazy fog/tonemapping and streaky drifting clouds.

var clouds: Array[Sprite3D] = []
var cloud_speed: Array[float] = []


func build() -> void:
	ctx.sky_zenith = Color(0.38, 0.40, 0.48)
	ctx.sky_horizon = Color(0.95, 0.62, 0.44)
	ctx.sun_color = Color(1.0, 0.70, 0.42)
	ctx.fog_color = Color(0.88, 0.63, 0.50)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = ctx.sky_zenith
	sky_mat.sky_horizon_color = ctx.sky_horizon
	sky_mat.sky_curve = 0.16
	sky_mat.ground_bottom_color = Color(0.35, 0.32, 0.34)
	sky_mat.ground_horizon_color = Color(0.80, 0.58, 0.46)
	sky_mat.sun_angle_max = 22.0
	sky_mat.sun_curve = 0.35
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.9
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.78
	env.fog_enabled = true
	env.fog_light_color = ctx.fog_color
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.5
	env.fog_aerial_perspective = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 0.98
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = ctx.sun_color
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.2
	sun.directional_shadow_max_distance = 100.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.5
	var elevation := 8.0
	var azimuth := 95.0
	var azimuth_yaw := 180.0 - azimuth
	sun.rotation_degrees = Vector3(-elevation, azimuth_yaw, 0)
	add_child(sun)
	if sun.is_inside_tree():
		ctx.sun_dir = -sun.global_transform.basis.z
	else:
		ctx.sun_dir = Vector3(-0.85, -0.14, -0.5).normalized()

	var rng := RandomNumberGenerator.new()
	rng.seed = 314

	# A handful of puffy background clouds for general texture.
	var puff_count: int = int(round(clampf(0.25, 0.0, 1.0) * 16.0))
	for i in puff_count:
		var s := Sprite3D.new()
		s.texture = ctx.cloud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.pixel_size = rng.randf_range(0.6, 1.0)
		var ang := rng.randf_range(-PI, PI)
		var dist := rng.randf_range(550.0, 900.0)
		s.position = Vector3(cos(ang) * dist, rng.randf_range(80.0, 150.0), sin(ang) * dist)
		s.modulate = Color(1.0, 0.82, 0.6, rng.randf_range(0.4, 0.6))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		clouds.append(s)
		cloud_speed.append(rng.randf_range(0.4, 1.0))

	# A few long, streaky high-altitude cirrus bands with gold-lit undersides.
	var streak_count: int = 6
	for i in streak_count:
		var s2 := Sprite3D.new()
		s2.texture = ctx.cloud_tex
		s2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s2.shaded = false
		s2.transparent = true
		s2.pixel_size = 1.0
		s2.scale = Vector3(rng.randf_range(7.0, 11.0), rng.randf_range(0.18, 0.28), 1.0)
		var ang2 := rng.randf_range(-PI, PI)
		var dist2 := rng.randf_range(600.0, 900.0)
		s2.position = Vector3(cos(ang2) * dist2, rng.randf_range(170.0, 220.0), sin(ang2) * dist2)
		s2.rotation.z = rng.randf_range(-0.15, 0.15)
		# Warm gold underside, cooler pale top achieved via modulate tint.
		s2.modulate = Color(1.0, 0.78, 0.5, rng.randf_range(0.55, 0.75))
		s2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s2)
		clouds.append(s2)
		cloud_speed.append(rng.randf_range(0.25, 0.6))


func tick(delta: float) -> void:
	for i in clouds.size():
		var c := clouds[i]
		c.position.x += ctx.wind.x * cloud_speed[i] * delta
		if c.position.x > 950.0:
			c.position.x = -950.0
		elif c.position.x < -950.0:
			c.position.x = 950.0

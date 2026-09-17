extends SceneLayer

# Dawn sky: pale apricot horizon fading into a cool blue zenith, a low
# warm sun disc, soft dawn haze and a few scattered cumulus sprites.

var clouds: Array[Sprite3D] = []
var cloud_speed: Array[float] = []


func build() -> void:
	# --- Palette -----------------------------------------------------
	ctx.sky_zenith = Color(0.28, 0.36, 0.52)
	ctx.sky_horizon = Color(0.95, 0.62, 0.42)
	ctx.sun_color = Color(1.0, 0.74, 0.52)
	ctx.fog_color = Color(0.85, 0.6, 0.5)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = ctx.sky_zenith
	sky_mat.sky_horizon_color = ctx.sky_horizon
	sky_mat.sky_curve = 0.14
	sky_mat.ground_bottom_color = Color(0.3, 0.26, 0.28)
	sky_mat.ground_horizon_color = Color(0.85, 0.58, 0.42)
	sky_mat.sun_angle_max = 10.0
	sky_mat.sun_curve = 0.16
	# A little cloud texture even at very low cover, for depth near the band.
	sky_mat.sky_cover = ctx.cloud_cover_tex
	sky_mat.sky_cover_modulate = Color(0.95, 0.72, 0.6, 0.12)

	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = ctx.sky_horizon.lerp(Color(0.7, 0.68, 0.68), 0.5)
	env.ambient_light_sky_contribution = 0.3
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85

	env.fog_enabled = true
	env.fog_light_color = ctx.fog_color
	env.fog_density = 0.0024
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.4

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.03

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# --- Sun -----------------------------------------------------------
	var elevation := 3.0
	var azimuth := 95.0
	var azimuth_yaw := 180.0 - azimuth

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = ctx.sun_color
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.2
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.0
	sun.rotation_degrees = Vector3(-elevation, azimuth_yaw, 0)
	add_child(sun)

	if sun.is_inside_tree():
		ctx.sun_dir = -sun.global_transform.basis.z
	else:
		var el_rad := deg_to_rad(elevation)
		var az_rad := deg_to_rad(azimuth)
		ctx.sun_dir = Vector3(sin(az_rad) * cos(el_rad), -sin(el_rad), -cos(az_rad) * cos(el_rad)).normalized()

	# --- Cumulus sprites (low cover, sparse) ----------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 95
	var count := 4
	for i in count:
		var s := Sprite3D.new()
		s.texture = ctx.cloud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.pixel_size = rng.randf_range(0.7, 1.2)
		var ang := rng.randf_range(-PI, PI)
		var dist := rng.randf_range(550.0, 900.0)
		s.position = Vector3(cos(ang) * dist, rng.randf_range(80.0, 170.0), sin(ang) * dist)
		s.modulate = Color(1.0, 0.82, 0.7, rng.randf_range(0.75, 0.95))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		clouds.append(s)
		cloud_speed.append(rng.randf_range(0.5, 1.3))


func tick(delta: float) -> void:
	for i in clouds.size():
		var c := clouds[i]
		c.position.x += ctx.wind.x * cloud_speed[i] * delta
		if c.position.x > 950.0:
			c.position.x = -950.0
		elif c.position.x < -950.0:
			c.position.x = 950.0

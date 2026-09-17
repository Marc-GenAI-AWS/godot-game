extends SceneLayer

# Sky dome, sun, fog/tonemapping and drifting cloud sprites.
# Clear, cloudless noon: bright blue sky, direct overhead sun, crisp shadows.

var clouds: Array[Sprite3D] = []
var cloud_speed: Array[float] = []


func build() -> void:
	ctx.sky_zenith = Color(0.31, 0.58, 0.92)
	ctx.sky_horizon = Color(0.62, 0.82, 0.94)
	ctx.sun_color = Color(1.0, 0.98, 0.92)
	ctx.fog_color = Color(0.66, 0.82, 0.94)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = ctx.sky_zenith
	sky_mat.sky_horizon_color = ctx.sky_horizon
	sky_mat.sky_curve = 0.09
	sky_mat.ground_bottom_color = Color(0.42, 0.48, 0.56)
	sky_mat.ground_horizon_color = Color(0.68, 0.82, 0.94)
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Ambient: mostly a desaturated daylight grey-blue with a little of the
	# sky's own colour, so shadows and white surfaces do not turn saturated
	# blue (the sky dome's zenith on its own is far too blue as fill light).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = ctx.sky_horizon.lerp(Color(0.78, 0.78, 0.78), 0.5)
	env.ambient_light_sky_contribution = 0.3
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.82
	env.fog_enabled = true
	env.fog_light_color = ctx.fog_color
	env.fog_density = 0.0003 + 0.0005 * 0.05
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
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.2
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.0
	var elevation := 82.0
	var azimuth := 45.0
	var azimuth_yaw := 180.0 - azimuth
	sun.rotation_degrees = Vector3(-elevation, azimuth_yaw, 0)
	add_child(sun)
	if sun.is_inside_tree():
		ctx.sun_dir = -sun.global_transform.basis.z
	else:
		var el_rad := deg_to_rad(elevation)
		var az_rad := deg_to_rad(azimuth_yaw)
		ctx.sun_dir = Vector3(sin(az_rad) * cos(el_rad), -sin(el_rad), -cos(az_rad) * cos(el_rad)).normalized()

	var rng := RandomNumberGenerator.new()
	rng.seed = 45
	var cloud_count := 4
	for i in cloud_count:
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
		elif c.position.x < -950.0:
			c.position.x = 950.0

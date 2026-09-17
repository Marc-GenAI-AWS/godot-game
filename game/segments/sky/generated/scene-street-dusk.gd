extends SceneLayer

# Sky dome, sun, fog/tonemapping and drifting cloud sprites.
# Dusk: sun sitting right on the horizon, amber glow fading into deep indigo.

var clouds: Array[Sprite3D] = []
var cloud_speed: Array[float] = []


func build() -> void:
	ctx.sky_zenith = Color(0.05, 0.10, 0.30)
	ctx.sky_horizon = Color(0.95, 0.42, 0.22)
	ctx.sun_color = Color(1.0, 0.55, 0.28)
	ctx.fog_color = Color(0.72, 0.42, 0.32)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = ctx.sky_zenith
	sky_mat.sky_horizon_color = ctx.sky_horizon
	sky_mat.sky_curve = 0.045
	sky_mat.ground_bottom_color = Color(0.08, 0.06, 0.10)
	sky_mat.ground_horizon_color = Color(0.62, 0.36, 0.26)
	sky_mat.sun_angle_max = 6.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Dusk: muted but still readable ambient fill, not crushed to blue.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = ctx.sky_horizon.lerp(Color(0.55, 0.5, 0.5), 0.4)
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	env.fog_enabled = true
	env.fog_light_color = ctx.fog_color
	env.fog_density = 0.0003 + 0.2 * 0.0037
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = ctx.sun_color
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.2
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.0
	var elevation_deg := 3.0
	var azimuth_deg := 260.0
	var azimuth_yaw := 180.0 - azimuth_deg
	sun.rotation_degrees = Vector3(-elevation_deg, azimuth_yaw, 0)
	add_child(sun)
	if sun.is_inside_tree():
		ctx.sun_dir = -sun.global_transform.basis.z
	else:
		var el_rad := deg_to_rad(elevation_deg)
		var az_rad := deg_to_rad(azimuth_deg)
		ctx.sun_dir = Vector3(sin(az_rad) * cos(el_rad), -sin(el_rad), -cos(az_rad) * cos(el_rad)).normalized()

	var rng := RandomNumberGenerator.new()
	rng.seed = 260
	var cloud_count := 4
	for i in cloud_count:
		var s := Sprite3D.new()
		s.texture = ctx.cloud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.pixel_size = rng.randf_range(0.7, 1.2)
		var ang := rng.randf_range(-PI, PI)
		var dist := rng.randf_range(500.0, 950.0)
		s.position = Vector3(cos(ang) * dist, rng.randf_range(70.0, 190.0), sin(ang) * dist)
		s.modulate = Color(1.0, 0.72, 0.5, rng.randf_range(0.75, 0.95))
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

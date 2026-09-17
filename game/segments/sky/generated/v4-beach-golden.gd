extends SceneLayer

# Sky dome, sun, fog/tonemapping and drifting cloud sprites.
# Golden hour, clear sky, warm amber light from the sea side.

var clouds: Array[Sprite3D] = []
var cloud_speed: Array[float] = []


func build() -> void:
	ctx.sky_zenith = Color(0.20, 0.28, 0.52)
	ctx.sky_horizon = Color(0.98, 0.62, 0.34)
	ctx.sun_color = Color(1.0, 0.72, 0.42)
	ctx.fog_color = Color(0.95, 0.66, 0.46)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = ctx.sky_zenith
	sky_mat.sky_horizon_color = ctx.sky_horizon
	sky_mat.sky_curve = 0.14
	sky_mat.ground_bottom_color = Color(0.32, 0.26, 0.28)
	sky_mat.ground_horizon_color = Color(0.85, 0.55, 0.38)
	sky_mat.sun_angle_max = 10.0
	sky_mat.sun_curve = 0.22
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.9
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	env.fog_enabled = true
	env.fog_light_color = ctx.fog_color
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = ctx.sun_color
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.2
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.0
	var azimuth_yaw: float = 180.0 - 100.0
	sun.rotation_degrees = Vector3(-6.0, azimuth_yaw, 0.0)
	add_child(sun)
	if sun.is_inside_tree():
		ctx.sun_dir = -sun.global_transform.basis.z
	else:
		ctx.sun_dir = Vector3(-0.33, -0.45, 0.83).normalized()

	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var cloud_count: int = int(round(0.05 * 40.0))
	for i in cloud_count:
		var s := Sprite3D.new()
		s.texture = ctx.cloud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.pixel_size = rng.randf_range(0.6, 1.1)
		var ang: float = rng.randf_range(-PI, PI)
		var dist: float = rng.randf_range(500.0, 950.0)
		s.position = Vector3(cos(ang) * dist, rng.randf_range(70.0, 190.0), sin(ang) * dist)
		s.modulate = Color(1.0, 0.85, 0.72, rng.randf_range(0.75, 0.95))
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

extends SceneLayer

# Sky dome, sun, fog/tonemapping and a heavy overcast cloud sheet for a
# damp, muted, low-overcast morning on the street.

var clouds: Array[Sprite3D] = []
var cloud_speed: Array[float] = []


func build() -> void:
	ctx.sky_zenith = Color(0.42, 0.46, 0.5)
	ctx.sky_horizon = Color(0.55, 0.58, 0.62)
	ctx.sun_color = Color(0.92, 0.93, 0.95)
	ctx.fog_color = Color(0.58, 0.6, 0.64)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = ctx.sky_zenith
	sky_mat.sky_horizon_color = ctx.sky_horizon
	sky_mat.sky_curve = 0.14
	sky_mat.ground_bottom_color = Color(0.38, 0.4, 0.42)
	sky_mat.ground_horizon_color = Color(0.5, 0.52, 0.56)
	sky_mat.sun_angle_max = 10.0
	sky_mat.sun_curve = 0.22
	sky_mat.sky_cover = ctx.cloud_cover_tex
	sky_mat.sky_cover_modulate = Color(0.62, 0.64, 0.68, 0.97)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.95
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.fog_enabled = true
	env.fog_light_color = ctx.fog_color
	env.fog_density = 0.0031
	env.fog_sky_affect = 0.45
	env.fog_aerial_perspective = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 0.94
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = ctx.sun_color
	sun.light_energy = 0.45
	sun.shadow_enabled = false
	var azimuth_yaw: float = 180.0 - 120.0
	sun.rotation_degrees = Vector3(-22.0, azimuth_yaw, 0.0)
	add_child(sun)
	if sun.is_inside_tree():
		ctx.sun_dir = -sun.global_transform.basis.z
	else:
		ctx.sun_dir = Vector3(-0.58, -0.61, 0.57).normalized()

	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var count: int = int(round(clampf(0.97, 0.0, 1.0) * 40.0))
	for i in count:
		var s := Sprite3D.new()
		s.texture = ctx.cloud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.pixel_size = rng.randf_range(0.9, 1.6)
		var ang: float = rng.randf_range(-PI, PI)
		var dist: float = rng.randf_range(500.0, 950.0)
		s.position = Vector3(cos(ang) * dist, rng.randf_range(70.0, 190.0), sin(ang) * dist)
		s.modulate = Color(0.55, 0.57, 0.6, rng.randf_range(0.55, 0.75))
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

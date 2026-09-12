class_name SkyLayer
extends BeachLayer

# Sky dome, sun, fog/tonemapping and drifting cloud sprites.

var clouds: Array[Sprite3D] = []
var cloud_speed: Array[float] = []


func build() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.1, 0.34, 0.8)
	sky_mat.sky_horizon_color = Color(0.68, 0.82, 0.96)
	sky_mat.sky_curve = 0.12
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
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.78
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.84, 0.95)
	env.fog_density = 0.0006
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.2
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.0
	sun.rotation_degrees = Vector3(-58, 40, 0)
	add_child(sun)

	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 30:
		var s := Sprite3D.new()
		s.texture = ctx.cloud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.pixel_size = rng.randf_range(0.35, 0.8)
		var ang := rng.randf_range(-PI, PI)
		var dist := rng.randf_range(450.0, 900.0)
		s.position = Vector3(cos(ang) * dist, rng.randf_range(90.0, 220.0), sin(ang) * dist)
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

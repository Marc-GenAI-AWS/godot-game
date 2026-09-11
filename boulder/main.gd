extends Node3D

# Boulder Hill: a big rock rolls down a grassy hillside, with a chase camera.
# Everything is built procedurally here so the whole scene lives in source.

const HILL_HEIGHT := 38.0
const SLOPE_TOP_Z := -55.0
const SLOPE_BOTTOM_Z := 45.0
const TERRAIN_HALF_X := 90
const TERRAIN_HALF_Z := 125
const BOULDER_RADIUS := 2.8
const START_POS := Vector3(0.0, 0.0, -48.0)

var boulder: RigidBody3D
var camera: Camera3D
var dust: GPUParticles3D
var hud: Label
var noise := FastNoiseLite.new()
var rest_timer := 0.0
var pending_reset := false


func _ready() -> void:
	noise.seed = 7
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	_build_environment()
	_build_terrain()
	_build_scenery()
	_build_boulder()
	_build_camera()
	_build_hud()
	_reset_boulder()


# ---------------------------------------------------------------- terrain

func terrain_height(x: float, z: float) -> float:
	var t := clampf((z - SLOPE_TOP_Z) / (SLOPE_BOTTOM_Z - SLOPE_TOP_Z), 0.0, 1.0)
	var profile := 1.0 - (t * t * (3.0 - 2.0 * t))  # smoothstep, 1 at top, 0 at bottom
	var h := HILL_HEIGHT * profile
	# Far bank so the boulder settles in the valley instead of leaving the map.
	var b := clampf((z - 62.0) / 50.0, 0.0, 1.0)
	h += 26.0 * b * b * (3.0 - 2.0 * b)
	h += 0.012 * x * x * (0.3 + 0.7 * profile)  # shallow valley keeps the boulder centred
	h += 0.3 * noise.get_noise_2d(x * 1.5, z * 1.5)  # small bumps
	h += 2.5 * noise.get_noise_2d(x * 0.35 + 100.0, z * 0.35)  # gentle undulation
	return h


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := TERRAIN_HALF_X * 2 + 1
	var d := TERRAIN_HALF_Z * 2 + 1
	var heights := PackedFloat32Array()
	heights.resize(w * d)
	for iz in d:
		for ix in w:
			heights[iz * w + ix] = terrain_height(ix - TERRAIN_HALF_X, iz - TERRAIN_HALF_Z)

	var grass_a := Color(0.15, 0.33, 0.1)
	var grass_b := Color(0.27, 0.43, 0.14)
	var dirt := Color(0.36, 0.27, 0.16)
	for iz in d:
		for ix in w:
			var x := float(ix - TERRAIN_HALF_X)
			var z := float(iz - TERRAIN_HALF_Z)
			var h := heights[iz * w + ix]
			# Slope steepness from neighbours drives grass/dirt blend.
			var hx0 := heights[iz * w + maxi(ix - 1, 0)]
			var hx1 := heights[iz * w + mini(ix + 1, w - 1)]
			var hz0 := heights[maxi(iz - 1, 0) * w + ix]
			var hz1 := heights[mini(iz + 1, d - 1) * w + ix]
			var n := Vector3(hx0 - hx1, 2.0, hz0 - hz1).normalized()
			var steep := clampf((1.0 - n.y) * 4.0, 0.0, 1.0)
			var v := 0.5 + 0.5 * noise.get_noise_2d(x * 3.0 + 400.0, z * 3.0)
			var col := grass_a.lerp(grass_b, v).lerp(dirt, steep * 0.8)
			# Worn track down the centre where the boulder rolls.
			var track := clampf(1.0 - absf(x) / 4.0, 0.0, 1.0)
			col = col.lerp(dirt, track * 0.5)
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, h, z))

	for iz in d - 1:
		for ix in w - 1:
			var i0 := iz * w + ix
			var i1 := i0 + 1
			var i2 := i0 + w
			var i3 := i2 + 1
			st.add_index(i0); st.add_index(i1); st.add_index(i2)
			st.add_index(i1); st.add_index(i3); st.add_index(i2)

	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.05
	body.physics_material_override = pm
	add_child(body)


# ---------------------------------------------------------------- scenery

func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.24, 0.13)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.12, 0.38, 0.14)
	leaf_mat.roughness = 1.0
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.3, 0.29, 0.27)

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.35
	trunk.bottom_radius = 0.5
	trunk.height = 3.0
	var crown := CylinderMesh.new()  # cone
	crown.top_radius = 0.0
	crown.bottom_radius = 2.6
	crown.height = 7.0
	var crown2 := CylinderMesh.new()
	crown2.top_radius = 0.0
	crown2.bottom_radius = 1.9
	crown2.height = 5.0
	var pebble := SphereMesh.new()
	pebble.radius = 0.6
	pebble.height = 1.0

	var trees := Node3D.new()
	trees.name = "Trees"
	add_child(trees)
	for i in 110:
		var x := rng.randf_range(-TERRAIN_HALF_X + 4, TERRAIN_HALF_X - 4)
		var z := rng.randf_range(-TERRAIN_HALF_Z + 4, TERRAIN_HALF_Z - 4)
		if absf(x) < 15.0 and z < 70.0:
			continue  # keep the rolling lane clear
		var y := terrain_height(x, z)
		var s := rng.randf_range(0.6, 1.1)
		var tree := Node3D.new()
		tree.position = Vector3(x, y - 0.2, z)
		tree.scale = Vector3.ONE * s
		tree.rotation.y = rng.randf() * TAU
		var t := MeshInstance3D.new()
		t.mesh = trunk
		t.material_override = trunk_mat
		t.position.y = 1.5
		tree.add_child(t)
		var c := MeshInstance3D.new()
		c.mesh = crown
		c.material_override = leaf_mat
		c.position.y = 5.5
		tree.add_child(c)
		var c2 := MeshInstance3D.new()
		c2.mesh = crown2
		c2.material_override = leaf_mat
		c2.position.y = 8.5
		tree.add_child(c2)
		trees.add_child(tree)
		# Trees collide so the boulder can knock into them at the bottom.
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.5
		cyl.height = 3.0
		cs.shape = cyl
		cs.position.y = 1.5
		sb.add_child(cs)
		tree.add_child(sb)

	for i in 60:
		var x := rng.randf_range(-TERRAIN_HALF_X + 2, TERRAIN_HALF_X - 2)
		var z := rng.randf_range(-TERRAIN_HALF_Z + 2, TERRAIN_HALF_Z - 2)
		var r := MeshInstance3D.new()
		r.mesh = pebble
		r.material_override = rock_mat
		r.position = Vector3(x, terrain_height(x, z) - 0.15, z)
		r.scale = Vector3(rng.randf_range(0.6, 2.0), rng.randf_range(0.5, 1.2), rng.randf_range(0.6, 2.0))
		r.rotation.y = rng.randf() * TAU
		add_child(r)


# ---------------------------------------------------------------- boulder

func _build_boulder() -> void:
	boulder = RigidBody3D.new()
	boulder.name = "Boulder"
	boulder.mass = 800.0
	boulder.angular_damp = 0.05
	boulder.linear_damp = 0.0
	boulder.continuous_cd = true
	boulder.can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.1
	boulder.physics_material_override = pm

	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = BOULDER_RADIUS
	cs.shape = sph
	boulder.add_child(cs)

	# Lumpy rock: displace a sphere's vertices with noise.
	var base := SphereMesh.new()
	base.radius = BOULDER_RADIUS
	base.height = BOULDER_RADIUS * 2.0
	base.radial_segments = 48
	base.rings = 24
	var arrays := base.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rock_noise := FastNoiseLite.new()
	rock_noise.seed = 3
	rock_noise.frequency = 0.9
	for i in verts.size():
		var v := verts[i]
		var dir := v.normalized()
		var bump := rock_noise.get_noise_3d(v.x, v.y, v.z) * 0.35
		bump += rock_noise.get_noise_3d(v.x * 3.0, v.y * 3.0, v.z * 3.0) * 0.08
		verts[i] = dir * (BOULDER_RADIUS * 0.95 + bump)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_normals()
	st.generate_tangents()
	var rock_mesh := st.commit()

	var mat := StandardMaterial3D.new()
	var an := FastNoiseLite.new()
	an.seed = 11
	an.frequency = 0.02
	an.fractal_octaves = 5
	var aimg := an.get_seamless_image(512, 512)
	var dark := Color(0.13, 0.12, 0.11)
	var light := Color(0.4, 0.37, 0.33)
	for y in 512:
		for x in 512:
			aimg.set_pixel(x, y, dark.lerp(light, aimg.get_pixel(x, y).r))
	mat.albedo_texture = ImageTexture.create_from_image(aimg)
	var nn := FastNoiseLite.new()
	nn.seed = 12
	nn.frequency = 0.03
	nn.fractal_octaves = 5
	var nimg := nn.get_seamless_image(512, 512)
	nimg.bump_map_to_normal_map(12.0)
	mat.normal_enabled = true
	mat.normal_texture = ImageTexture.create_from_image(nimg)
	mat.roughness = 0.9
	mat.uv1_scale = Vector3(3, 3, 3)
	rock_mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = rock_mesh
	boulder.add_child(mi)
	add_child(boulder)

	# Dust kicked up while rolling; follows the boulder but does not spin with it.
	dust = GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 120
	dust.lifetime = 1.6
	dust.emitting = false
	dust.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var pp := ParticleProcessMaterial.new()
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pp.emission_sphere_radius = 1.2
	pp.direction = Vector3(0, 1, 0)
	pp.spread = 60.0
	pp.initial_velocity_min = 1.5
	pp.initial_velocity_max = 4.0
	pp.gravity = Vector3(0, 0.6, 0)
	pp.scale_min = 0.6
	pp.scale_max = 1.6
	var scale_curve := CurveTexture.new()
	var cv := Curve.new()
	cv.add_point(Vector2(0.0, 0.4))
	cv.add_point(Vector2(0.3, 1.0))
	cv.add_point(Vector2(1.0, 1.6))
	scale_curve.curve = cv
	pp.scale_curve = scale_curve
	var alpha_ramp := GradientTexture1D.new()
	var ag := Gradient.new()
	ag.set_color(0, Color(0.75, 0.68, 0.55, 0.6))
	ag.set_color(1, Color(0.75, 0.68, 0.55, 0.0))
	alpha_ramp.gradient = ag
	pp.color_ramp = alpha_ramp
	dust.process_material = pp
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(1, 1, 1, 1)
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 1))
	pg.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = pg
	puff.width = 128
	puff.height = 128
	dm.albedo_texture = puff
	quad.material = dm
	dust.draw_pass_1 = quad
	add_child(dust)


func _reset_boulder() -> void:
	pending_reset = true
	rest_timer = 0.0


func _physics_process(_delta: float) -> void:
	if pending_reset:
		pending_reset = false
		var y := terrain_height(START_POS.x, START_POS.z) + BOULDER_RADIUS + 0.5
		boulder.global_transform = Transform3D(Basis.IDENTITY, Vector3(START_POS.x, y, START_POS.z))
		boulder.linear_velocity = Vector3(0, 0, 3.0)
		boulder.angular_velocity = Vector3(1.5, 0, 0)
		if camera:
			camera.global_position = boulder.global_position + Vector3(10, 7, -16)


# ---------------------------------------------------------------- camera / env / hud

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.fov = 62.0
	camera.far = 600.0
	add_child(camera)
	camera.current = true


func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.48, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.92)
	sky_mat.ground_bottom_color = Color(0.3, 0.4, 0.28)
	sky_mat.ground_horizon_color = Color(0.72, 0.82, 0.92)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.83, 0.92)
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.25
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.15
	sun.shadow_normal_bias = 3.0
	sun.rotation_degrees = Vector3(-48, 35, 0)
	add_child(sun)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(18, 14)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hud)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R or event.keycode == KEY_SPACE:
			_reset_boulder()
	elif event is InputEventMouseButton and event.pressed:
		_reset_boulder()
	elif event is InputEventScreenTouch and event.pressed:
		_reset_boulder()


func _process(delta: float) -> void:
	if boulder == null:
		return
	var bp := boulder.global_position
	var speed := boulder.linear_velocity.length()

	# Chase camera: sit up-slope and above, look slightly ahead of the rock.
	var target := bp + Vector3(9.0, 6.5, -15.0)
	var k := 1.0 - exp(-delta * 3.0)
	camera.global_position = camera.global_position.lerp(target, k)
	camera.look_at(bp + boulder.linear_velocity * 0.15 + Vector3(0, 1, 0), Vector3.UP)

	# Dust follows the contact point and only emits while moving on the ground.
	var ground_y := terrain_height(bp.x, bp.z)
	dust.global_position = Vector3(bp.x, ground_y + 0.2, bp.z)
	dust.emitting = speed > 4.0 and bp.y - ground_y < BOULDER_RADIUS + 0.8
	dust.amount_ratio = clampf(speed / 25.0, 0.2, 1.0)

	hud.text = "Boulder Hill   speed %.0f m/s\nClick, tap, R or Space to roll again" % speed

	# Auto-restart once it has come to rest in the valley.
	if speed < 0.6 and bp.z > 20.0:
		rest_timer += delta
		if rest_timer > 3.5:
			_reset_boulder()
	else:
		rest_timer = 0.0
	if bp.y < -30.0:
		_reset_boulder()

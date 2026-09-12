extends Node3D

# Beach Walk: a stylised third-person stroll along a resort shoreline.
# World is built procedurally. The player walks toward -Z; the sea is +X.

const CHUNK := 200.0          # scenery repeats every CHUNK metres along Z
const SAND_SLOPE := 0.06      # sand drops this much per metre into the sea
const LAND_SLOPE := 0.03      # and rises this much per metre up the beach
const WALK_SPEED := 1.6

var player: Humanoid
var player_yaw := 0.0
var walking := true
var camera: Camera3D
var hud: Label
var sand_mat: ShaderMaterial
var noise_tex: ImageTexture
var palm_crowns: Array[Node3D] = []
var walkers: Array = []        # [Humanoid, speed, dir]
var gull: Node3D
var gull_wings: Array[Node3D] = []
var gull_t := 0.0
var frond_mesh: Mesh
var window_tex: ImageTexture
var cloud_tex: ImageTexture
var time := 0.0


func sand_height(x: float, z: float) -> float:
	var h := -SAND_SLOPE * x if x > 0.0 else -LAND_SLOPE * x
	h += 0.06 * sin(z * 0.21 + x * 0.1) + 0.04 * sin(z * 0.7 - x * 0.3)
	return h


func _ready() -> void:
	_make_shared_textures()
	_build_environment()
	_build_sand()
	_build_water()
	_build_clouds()
	frond_mesh = _make_frond_mesh()
	for i in 3:
		_build_chunk(1234, (i - 1) * CHUNK)
	_build_player()
	_build_gull()
	_build_hud()


# ---------------------------------------------------------------- textures

func _make_shared_textures() -> void:
	var n := FastNoiseLite.new()
	n.seed = 3
	n.frequency = 0.02
	n.fractal_octaves = 4
	noise_tex = ImageTexture.create_from_image(n.get_seamless_image(256, 256))

	# Window tile: pale wall with a darker window rectangle, tinted per building.
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 1, 1))
	for y in range(18, 46):
		for x in range(20, 44):
			var c := Color(0.42, 0.5, 0.6) if (y < 48) else Color(0.6, 0.6, 0.6)
			img.set_pixel(x, y, c)
	for y in range(50, 54):
		for x in 64:
			img.set_pixel(x, y, Color(0.9, 0.9, 0.9))
	window_tex = ImageTexture.create_from_image(img)

	# Cloud sprite: soft blobby fbm mask.
	var cn := FastNoiseLite.new()
	cn.seed = 9
	cn.frequency = 0.012
	cn.fractal_octaves = 5
	var w := 384
	var h := 192
	var cimg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x - w * 0.5) / (w * 0.5)
			var v := (y - h * 0.5) / (h * 0.5)
			var r := sqrt(u * u + v * v * 2.2)
			var m := cn.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((m - 0.35) * 3.0 - r * 1.3 + 0.55, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var shade := clampf(1.0 - (v + 0.4) * 0.25, 0.7, 1.0)
			cimg.set_pixel(x, y, Color(shade, shade, shade + 0.02, a))
	cloud_tex = ImageTexture.create_from_image(cimg)


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
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


# ---------------------------------------------------------------- ground / sea

func _grid_mesh(x0: float, x1: float, z0: float, z1: float, step: float, height_fn: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int((x1 - x0) / step) + 1
	var nz := int((z1 - z0) / step) + 1
	for iz in nz:
		for ix in nx:
			var x := x0 + ix * step
			var z := z0 + iz * step
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, height_fn.call(x, z), z))
	for iz in nz - 1:
		for ix in nx - 1:
			var i0 := iz * nx + ix
			var i1 := i0 + 1
			var i2 := i0 + nx
			var i3 := i2 + 1
			st.add_index(i0); st.add_index(i1); st.add_index(i2)
			st.add_index(i1); st.add_index(i3); st.add_index(i2)
	st.generate_normals()
	return st.commit()


func _build_sand() -> void:
	var mesh := _grid_mesh(-130.0, 70.0, -CHUNK * 2.2, CHUNK * 1.2, 2.0, sand_height)
	sand_mat = ShaderMaterial.new()
	sand_mat.shader = load("res://sand.gdshader")
	sand_mat.set_shader_parameter("noise_tex", noise_tex)
	mesh.surface_set_material(0, sand_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func _build_water() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var mesh := _grid_mesh(-12.0, 520.0, -CHUNK * 2.4, CHUNK * 1.4, 3.0, flat)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://water.gdshader")
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.set_shader_parameter("sand_slope", SAND_SLOPE)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 26:
		var s := Sprite3D.new()
		s.texture = cloud_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.no_depth_test = false
		s.pixel_size = rng.randf_range(0.35, 0.7)
		var ang := rng.randf_range(-PI, PI)
		var dist := rng.randf_range(500.0, 900.0)
		s.position = Vector3(cos(ang) * dist, rng.randf_range(110.0, 220.0), sin(ang) * dist)
		s.modulate = Color(1, 1, 1, rng.randf_range(0.8, 1.0))
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)


# ---------------------------------------------------------------- scenery chunk

func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	return Humanoid._mat(c, rough)


func _box_at(parent: Node3D, size: Vector3, c: Color, pos: Vector3, rough := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, rough)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_chunk(seed_v: int, z_off: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var chunk := Node3D.new()
	chunk.position.z = z_off
	add_child(chunk)
	_build_buildings(chunk, rng)
	_build_palms(chunk, rng)
	_build_lifeguard_tower(chunk, Vector3(-26.0, 0.0, -70.0))
	_build_beach_furniture(chunk, rng)
	_build_walkers(chunk, rng)


func _build_buildings(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var palette := [Color(0.95, 0.92, 0.82), Color(0.95, 0.66, 0.7), Color(0.6, 0.86, 0.76),
		Color(0.62, 0.78, 0.95), Color(0.98, 0.78, 0.55), Color(0.9, 0.88, 0.7), Color(0.78, 0.68, 0.92), Color(0.98, 0.9, 0.5)]
	var z := -CHUNK
	while z < 0.0:
		var w := rng.randf_range(14.0, 26.0)
		var d := rng.randf_range(16.0, 30.0)
		var h := rng.randf_range(10.0, 34.0)
		if rng.randf() < 0.12:
			h = rng.randf_range(60.0, 95.0)
		var x := -78.0 - rng.randf_range(0.0, 10.0) - d * 0.5
		var c: Color = palette[rng.randi() % palette.size()]
		var b := Node3D.new()
		b.position = Vector3(x, sand_height(x, z) - 0.5, z + w * 0.5)
		parent.add_child(b)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.albedo_texture = window_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.28, 0.28, 0.28)
		mat.roughness = 0.9
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(d, h, w)
		m.mesh = bm
		m.material_override = mat
		m.position.y = h * 0.5
		b.add_child(m)
		# Stepped art-deco top and a roof slab.
		var top := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(d * 0.6, h * 0.12 + 2.0, w * 0.6)
		top.mesh = tm
		top.material_override = mat
		top.position.y = h + tm.size.y * 0.5
		b.add_child(top)
		_box_at(b, Vector3(d + 0.6, 0.5, w + 0.6), c.darkened(0.15), Vector3(0, h + 0.25, 0))
		z += w + rng.randf_range(2.0, 9.0)
	# A boardwalk / low wall between the beach and the hotels.
	_box_at(parent, Vector3(3.0, 0.5, CHUNK), Color(0.85, 0.82, 0.75), Vector3(-66.0, sand_height(-66.0, 0.0) + 0.25, -CHUNK * 0.5))


func _make_frond_mesh() -> ArrayMesh:
	# A single palm frond: tapered strip that arcs outward and droops.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 7
	var pts := PackedVector3Array()
	for i in segs + 1:
		var t := float(i) / segs
		var ang := 0.35 - t * t * 1.25
		var x := t * 2.6
		var y := sin(ang) * t * 2.6 * 0.6 + t * 0.3 - t * t * 1.1
		var w := 0.32 * sin(PI * (0.15 + 0.85 * t)) + 0.04
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(t, 0))
		st.add_vertex(Vector3(x, y, -w))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(t, 1))
		st.add_vertex(Vector3(x, y, w))
	for i in segs:
		var a := i * 2
		st.add_index(a); st.add_index(a + 1); st.add_index(a + 2)
		st.add_index(a + 1); st.add_index(a + 3); st.add_index(a + 2)
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.42, 0.16)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	m.surface_set_material(0, mat)
	return m


func _build_palm(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var palm := Node3D.new()
	palm.position = pos
	palm.rotation.y = rng.randf() * TAU
	parent.add_child(palm)
	var height := rng.randf_range(7.0, 12.0)
	var segs := 7
	var lean := Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
	var p := Vector3.ZERO
	var trunk_mat := _mat(Color(0.5, 0.42, 0.3), 0.95)
	for i in segs:
		var t := float(i) / segs
		var seg_len := height / segs
		var next := p + Vector3(lean.x * (0.5 + t) * seg_len, seg_len, lean.y * (0.5 + t) * seg_len)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = lerpf(0.26, 0.15, t + 0.15)
		cm.bottom_radius = lerpf(0.3, 0.17, t)
		cm.height = seg_len + 0.15
		cm.radial_segments = 8
		mi.mesh = cm
		mi.material_override = trunk_mat
		mi.position = (p + next) * 0.5
		mi.look_at_from_position(mi.position, mi.position + (next - p).normalized(), Vector3.RIGHT)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		palm.add_child(mi)
		p = next
	var crown := Node3D.new()
	crown.position = p
	palm.add_child(crown)
	palm_crowns.append(crown)
	var n := 9 + rng.randi() % 4
	for i in n:
		var f := MeshInstance3D.new()
		f.mesh = frond_mesh
		f.rotation.y = TAU * i / n + rng.randf_range(-0.2, 0.2)
		f.rotation.z = rng.randf_range(-0.15, 0.25)
		f.scale = Vector3.ONE * rng.randf_range(0.9, 1.25)
		crown.add_child(f)
	# Coconuts
	for i in 3:
		var c := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.28
		c.mesh = sm
		c.material_override = _mat(Color(0.35, 0.28, 0.15))
		c.position = Vector3(rng.randf_range(-0.2, 0.2), -0.2, rng.randf_range(-0.2, 0.2))
		crown.add_child(c)


func _build_palms(parent: Node3D, rng: RandomNumberGenerator) -> void:
	# A row near the boardwalk plus a few loose ones on the sand.
	var z := -CHUNK + rng.randf_range(0.0, 8.0)
	while z < 0.0:
		var x := -60.0 + rng.randf_range(-4.0, 3.0)
		_build_palm(parent, Vector3(x, sand_height(x, z) - 0.2, z), rng)
		z += rng.randf_range(9.0, 16.0)
	for i in 4:
		var x := rng.randf_range(-52.0, -40.0)
		var zz := rng.randf_range(-CHUNK, 0.0)
		_build_palm(parent, Vector3(x, sand_height(x, zz) - 0.2, zz), rng)


func _build_lifeguard_tower(parent: Node3D, pos: Vector3) -> void:
	var t := Node3D.new()
	t.position = Vector3(pos.x, sand_height(pos.x, pos.z), pos.z)
	parent.add_child(t)
	var white := Color(0.95, 0.95, 0.92)
	var blue := Color(0.25, 0.55, 0.8)
	for dx in [-1.4, 1.4]:
		for dz in [-1.4, 1.4]:
			_box_at(t, Vector3(0.25, 3.2, 0.25), white, Vector3(dx, 1.6, dz))
	_box_at(t, Vector3(3.6, 0.2, 3.6), white, Vector3(0, 3.2, 0))
	_box_at(t, Vector3(3.2, 2.4, 3.2), blue, Vector3(0, 4.5, 0))
	_box_at(t, Vector3(3.2, 0.9, 3.2), white, Vector3(0, 5.6, 0))
	_box_at(t, Vector3(4.2, 0.2, 4.2), Color(0.8, 0.2, 0.2), Vector3(0, 6.1, 0))
	# Ramp
	var ramp := _box_at(t, Vector3(1.2, 0.12, 5.0), white, Vector3(0, 1.6, 4.0))
	ramp.rotation.x = -0.6
	_box_at(t, Vector3(0.08, 1.0, 3.6), white, Vector3(-1.7, 3.8, 0))
	_box_at(t, Vector3(3.6, 1.0, 0.08), white, Vector3(0, 3.8, -1.7))


func _make_stripe_tex(a: Color, b: Color) -> ImageTexture:
	var img := Image.create(256, 8, false, Image.FORMAT_RGB8)
	for x in 256:
		var c := a if (x / 32) % 2 == 0 else b
		for y in 8:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _build_beach_furniture(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var stripes := [[Color(0.2, 0.5, 0.9), Color(1, 1, 1)], [Color(0.95, 0.3, 0.45), Color(1.0, 0.9, 0.3)],
		[Color(0.2, 0.7, 0.45), Color(1, 1, 1)], [Color(0.95, 0.5, 0.2), Color(0.98, 0.95, 0.9)],
		[Color(0.55, 0.3, 0.8), Color(0.95, 0.7, 0.85)]]
	var stripe_mats := []
	for s in stripes:
		var m := StandardMaterial3D.new()
		m.albedo_texture = _make_stripe_tex(s[0], s[1])
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		stripe_mats.append(m)
	var skins := [Color(0.9, 0.72, 0.58), Color(0.76, 0.55, 0.4), Color(0.55, 0.36, 0.25), Color(0.95, 0.8, 0.68)]
	var suits := [Color(0.9, 0.2, 0.3), Color(0.1, 0.3, 0.7), Color(0.95, 0.85, 0.2), Color(0.1, 0.1, 0.12), Color(0.2, 0.7, 0.6)]
	var hair_cols := [Color(0.12, 0.08, 0.05), Color(0.35, 0.22, 0.1), Color(0.75, 0.6, 0.35), Color(0.05, 0.05, 0.05)]

	var count := 34
	for i in count:
		var z := -CHUNK + (i + rng.randf_range(0.1, 0.9)) * (CHUNK / count)
		var x := rng.randf_range(-48.0, -14.0)
		var g := Node3D.new()
		g.position = Vector3(x, sand_height(x, z), z)
		g.rotation.y = rng.randf_range(-0.5, 0.5)
		parent.add_child(g)
		# Lounger: two white rails, slats, tilted backrest, facing the sea (+x)
		var lounger := Node3D.new()
		lounger.rotation.y = -PI * 0.5
		g.add_child(lounger)
		var white := Color(0.96, 0.96, 0.96)
		var slat := Color(0.35, 0.55, 0.85) if rng.randf() < 0.5 else Color(0.95, 0.95, 0.9)
		_box_at(lounger, Vector3(0.7, 0.06, 1.4), slat, Vector3(0, 0.36, 0.1))
		_box_at(lounger, Vector3(0.05, 0.08, 1.9), white, Vector3(-0.36, 0.36, 0.0))
		_box_at(lounger, Vector3(0.05, 0.08, 1.9), white, Vector3(0.36, 0.36, 0.0))
		var back := _box_at(lounger, Vector3(0.7, 0.06, 0.75), slat, Vector3(0, 0.55, -0.85))
		back.rotation.x = 0.9
		for dz in [-0.8, 0.8]:
			for dx in [-0.3, 0.3]:
				_box_at(lounger, Vector3(0.05, 0.36, 0.05), white, Vector3(dx, 0.18, dz))
		# Sunbather
		if rng.randf() < 0.7:
			var hmn := Humanoid.new()
			var skin: Color = skins[rng.randi() % skins.size()]
			var suit: Color = suits[rng.randi() % suits.size()]
			hmn.build(skin, suit if rng.randf() < 0.8 else skin, suit, hair_cols[rng.randi() % hair_cols.size()], rng.randf() < 0.6, 0.95)
			hmn.pose_lying()
			hmn.position = Vector3(0.0, 0.42, 0.85)
			lounger.add_child(hmn)
		# Umbrella
		if rng.randf() < 0.55:
			var u := Node3D.new()
			u.position = Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-1.6, -1.0))
			g.add_child(u)
			_box_at(u, Vector3(0.06, 2.4, 0.06), Color(0.85, 0.85, 0.85), Vector3(0, 1.2, 0))
			var cone := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 1.5
			cm.height = 0.55
			cm.radial_segments = 12
			cm.cap_bottom = false
			cone.mesh = cm
			cone.material_override = stripe_mats[rng.randi() % stripe_mats.size()]
			cone.position.y = 2.35
			cone.rotation.z = rng.randf_range(-0.12, 0.12)
			u.add_child(cone)
		# Odd beach bag / cooler
		if rng.randf() < 0.3:
			var cols := [Color(0.9, 0.3, 0.7), Color(0.2, 0.6, 0.9), Color(0.95, 0.6, 0.1)]
			_box_at(g, Vector3(0.4, 0.4, 0.3), cols[rng.randi() % cols.size()], Vector3(rng.randf_range(-1.0, 1.0), 0.2, rng.randf_range(1.2, 1.8)))


func _build_walkers(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var skins := [Color(0.9, 0.72, 0.58), Color(0.76, 0.55, 0.4), Color(0.55, 0.36, 0.25)]
	var tops := [Color(1, 1, 1), Color(0.9, 0.3, 0.3), Color(0.2, 0.4, 0.8), Color(0.95, 0.85, 0.3), Color(0.3, 0.7, 0.5)]
	var bottoms := [Color(0.3, 0.4, 0.6), Color(0.1, 0.1, 0.12), Color(0.9, 0.9, 0.85), Color(0.8, 0.3, 0.2)]
	for i in 5:
		var h := Humanoid.new()
		h.build(skins[rng.randi() % skins.size()], skins[0], bottoms[rng.randi() % bottoms.size()],
			Color(0.1, 0.07, 0.05), rng.randf() < 0.5, rng.randf_range(0.9, 1.05))
		var wx := rng.randf_range(4.0, 9.0)
		var wz := rng.randf_range(-CHUNK, 0.0)
		h.position = Vector3(wx, sand_height(wx, wz), wz)
		h.rotation.y = rng.randf_range(-0.6, 0.6) + PI * 0.5
		h.pose_idle()
		parent.add_child(h)
	for i in 9:
		var h := Humanoid.new()
		h.build(skins[rng.randi() % skins.size()], tops[rng.randi() % tops.size()], bottoms[rng.randi() % bottoms.size()],
			Color(0.1, 0.07, 0.05), rng.randf() < 0.5, rng.randf_range(0.9, 1.05))
		var x := rng.randf_range(-12.0, -1.0)
		var z := rng.randf_range(-CHUNK, 0.0)
		h.position = Vector3(x, sand_height(x, z), z)
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		h.rotation.y = 0.0 if dir < 0 else PI
		parent.add_child(h)
		walkers.append([h, rng.randf_range(1.1, 1.6), dir])


# ---------------------------------------------------------------- player / gull

func _build_player() -> void:
	player = Humanoid.new()
	player.build(Color(0.72, 0.5, 0.36), Color(0.92, 0.45, 0.6), Color(0.42, 0.5, 0.68), Color(0.16, 0.1, 0.06), true, 1.0)
	player.position = Vector3(-4.5, sand_height(-4.5, 0.0), 0.0)
	add_child(player)
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.near = 0.1
	camera.far = 1500.0
	add_child(camera)
	camera.current = true
	camera.global_position = player.global_position + Vector3(0.6, 1.8, 3.8)


func _build_gull() -> void:
	gull = Node3D.new()
	gull.scale = Vector3.ONE * 2.2
	add_child(gull)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.09
	cm.height = 0.5
	body.mesh = cm
	body.material_override = _mat(Color(0.95, 0.95, 0.95))
	body.rotation.x = PI * 0.5
	gull.add_child(body)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	head.mesh = sm
	head.material_override = _mat(Color(0.95, 0.95, 0.95))
	head.position = Vector3(0, 0.05, -0.28)
	gull.add_child(head)
	_box_at(gull, Vector3(0.03, 0.03, 0.12), Color(0.95, 0.7, 0.2), Vector3(0, 0.04, -0.4))
	for side in [-1.0, 1.0]:
		var w := Node3D.new()
		gull.add_child(w)
		var wing := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.75, 0.02, 0.22)
		wing.mesh = bm
		wing.material_override = _mat(Color(0.8, 0.8, 0.82))
		wing.position = Vector3(side * 0.4, 0, 0)
		w.add_child(wing)
		var tip := _box_at(w, Vector3(0.3, 0.02, 0.14), Color(0.25, 0.25, 0.28), Vector3(side * 0.88, 0, 0.02))
		gull_wings.append(w)
	gull_t = 4.0


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


# ---------------------------------------------------------------- per frame

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		walking = not walking
	elif (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		walking = not walking


func _process(delta: float) -> void:
	time += delta
	# Steering
	var steer := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		steer += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		steer -= 1.0
	player_yaw += steer * delta * 1.4
	# Drift back toward walking straight down the beach when not steering.
	if steer == 0.0:
		player_yaw = lerpf(player_yaw, 0.0, 1.0 - exp(-delta * 0.8))
	player_yaw = clampf(player_yaw, -0.9, 0.9)
	player.rotation.y = player_yaw

	var fwd := Vector3(-sin(player_yaw), 0, -cos(player_yaw))
	if walking:
		var p := player.position + fwd * WALK_SPEED * delta
		p.x = clampf(p.x, -50.0, 1.2)
		p.y = sand_height(p.x, p.z)
		player.position = p
		player.pose_walk(delta, WALK_SPEED)
	else:
		player.pose_idle()

	# Seamless loop: scenery repeats every CHUNK, so jump back a chunk.
	if player.position.z < -CHUNK:
		player.position.z += CHUNK
		camera.global_position.z += CHUNK
		gull.position.z += CHUNK

	# Chase camera, slightly over the left shoulder like the reference.
	var right := Vector3(cos(player_yaw), 0, -sin(player_yaw))
	var target := player.position + right * 0.55 + Vector3(0, 1.85, 0) - fwd * 3.9
	target.y = maxf(target.y, sand_height(target.x, target.z) + 0.9)
	var k := 1.0 - exp(-delta * 4.0)
	camera.global_position = camera.global_position.lerp(target, k)
	camera.look_at(player.position + Vector3(0, 1.2, 0) + fwd * 2.5 + right * 0.3, Vector3.UP)

	# Tide reach for the wet sand
	var reach := 3.2 + 1.6 * sin(time * 0.55) + 0.5 * sin(time * 1.7)
	sand_mat.set_shader_parameter("reach_x", reach)

	# Palms sway
	for i in palm_crowns.size():
		var c := palm_crowns[i]
		c.rotation.x = 0.04 * sin(time * 0.9 + i * 1.3)
		c.rotation.z = 0.05 * sin(time * 0.7 + i * 0.7) + 0.03

	# Extras strolling along the waterline
	for w in walkers:
		var h: Humanoid = w[0]
		h.position.z += w[2] * w[1] * delta
		var local_z: float = h.position.z
		if local_z < -CHUNK:
			h.position.z += CHUNK
		elif local_z > 0.0:
			h.position.z -= CHUNK
		h.position.y = sand_height(h.position.x, h.get_parent().position.z + h.position.z)
		h.pose_walk(delta, w[1])

	# Seagull: swoops across the view every so often
	gull_t -= delta
	if gull_t < -9.0:
		gull_t = 12.0 + fmod(time, 5.0)
	if gull_t < 0.0:
		var u := -gull_t / 9.0
		var base := player.position
		var gx := lerpf(-16.0, 14.0, u)
		var gz := base.z - 26.0 + 34.0 * u
		var gy := 3.2 + sin(u * PI) * 2.5 + 0.3 * sin(time * 3.0)
		var prev := gull.position
		gull.position = Vector3(gx, gy, gz)
		var v := gull.position - prev
		if v.length() > 0.001:
			gull.look_at(gull.position + v, Vector3.UP)
		gull.visible = true
		var flap := sin(time * 9.0) * 0.55
		gull_wings[0].rotation.z = flap
		gull_wings[1].rotation.z = -flap
	else:
		gull.visible = false

	hud.text = "Beach Walk   %d fps\nLeft / Right or A / D to steer   Space or tap to stop and go" % Engine.get_frames_per_second()

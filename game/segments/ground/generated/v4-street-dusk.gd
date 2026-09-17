extends ChunkedLayer

# Worn grey asphalt with a single dashed white centre line, plain concrete
# kerbs, weathered concrete sidewalks with frequent joints and cracks, and
# dry yellow-green mown lawns.

var asphalt_mat: ShaderMaterial
var lawn_mat: StandardMaterial3D
var concrete_mat: StandardMaterial3D


func _init() -> void:
	seed_v = 7171


func build() -> void:
	asphalt_mat = ShaderMaterial.new()
	asphalt_mat.shader = load("res://segments/ground/shaders/asphalt.gdshader")
	asphalt_mat.set_shader_parameter("noise_tex", ctx.noise_tex)
	asphalt_mat.set_shader_parameter("lane_x", (ctx as StreetContext).LANE_X)
	asphalt_mat.set_shader_parameter("base_color", Color(0.34, 0.34, 0.34))
	asphalt_mat.set_shader_parameter("grain_scale", 1.1)
	asphalt_mat.set_shader_parameter("track_strength", 0.6)
	asphalt_mat.set_shader_parameter("stain_strength", 0.5)
	asphalt_mat.set_shader_parameter("patch_strength", 0.7)
	asphalt_mat.set_shader_parameter("wear", 1.2)

	# lawn: dry yellow-green mottled by noise, mown stripes
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = 91
	n.frequency = 0.04
	n.fractal_octaves = 4
	for y in 256:
		for x in 256:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var stripe: float = 0.96 + 0.04 * signf(sin(x * 0.2))
			var c: Color = Color(0.5, 0.46, 0.18).lerp(Color(0.62, 0.58, 0.26), v) * stripe
			img.set_pixel(x, y, c)
	lawn_mat = StandardMaterial3D.new()
	lawn_mat.albedo_texture = ImageTexture.create_from_image(img)
	lawn_mat.uv1_scale = Vector3(0.15, 0.15, 0.15)
	lawn_mat.uv1_triplanar = true
	lawn_mat.roughness = 1.0

	# concrete: weathered pale grey with speckle
	var cimg := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := n.get_noise_2d(x * 3.0 + 500.0, y * 3.0) * 0.5 + 0.5
			var c: Color = Color(0.55, 0.54, 0.51).lerp(Color(0.68, 0.67, 0.62), v)
			cimg.set_pixel(x, y, c)
	concrete_mat = StandardMaterial3D.new()
	concrete_mat.albedo_texture = ImageTexture.create_from_image(cimg)
	concrete_mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	concrete_mat.uv1_triplanar = true
	concrete_mat.roughness = 0.95
	concrete_mat.vertex_color_use_as_albedo = true

	var pm := PlaneMesh.new()
	pm.size = Vector2(400.0, WorldContext.CHUNK * 3.6)
	pm.material = lawn_mat
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = Vector3(0, -0.02, -WorldContext.CHUNK * 0.5)
	add_child(mi)
	super.build()


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	# road slab with the asphalt shader
	var road := BoxMesh.new()
	road.size = Vector3(sc.ROAD_HALF * 2.0, 0.04, L)
	road.material = asphalt_mat
	var rmi := MeshInstance3D.new()
	rmi.mesh = road
	rmi.position = Vector3(0, 0.0, -L * 0.5)
	chunk.add_child(rmi)

	# paint: single dashed white centre line only, faded and worn
	var paint := MeshBatch.new()
	var white := Color(0.8, 0.8, 0.78)
	var z := -L
	while z < 0.0:
		var dash := rng.randf_range(2.5, 3.5)
		var gap := rng.randf_range(2.5, 3.5)
		var fade := rng.randf_range(0.65, 1.0)
		paint.add_box_at(Vector3(0.12, 0.012, dash), white * fade, Vector3(0.0, 0.025, z + dash * 0.5))
		z += dash + gap
	var cz := -L + 12.0
	for i in 10:
		paint.add_box_at(Vector3(0.5, 0.012, 3.0), white * 0.9, Vector3(-sc.ROAD_HALF + 0.9 + i * 1.15, 0.025, cz))
	paint.add_box_at(Vector3(sc.ROAD_HALF * 2.0, 0.012, 0.3), white * 0.9, Vector3(0, 0.025, cz + 2.2))
	for i in 6:
		paint.add_cylinder(0.35, 0.35, 0.02, Color(0.3, 0.28, 0.26), Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-3.5, 3.5), 0.02, -rng.randf_range(0, L))), 12)
	paint.instance(chunk, "Paint", 0.9)

	# plain concrete kerbs and weathered sidewalk slabs with frequent joints
	var kerb := MeshBatch.new()
	var walk := MeshBatch.new()
	for side: float in [-1.0, 1.0]:
		var kx := side * (sc.ROAD_HALF + 0.15)
		var zz := -L
		while zz < 0.0:
			var seg := 4.0
			kerb.add_box_at(Vector3(0.3, sc.KERB_H, seg - 0.03), Color(1, 1, 1), Vector3(kx, sc.KERB_H * 0.5, zz + seg * 0.5))
			zz += seg
		var wx := side * (sc.ROAD_HALF + 0.3 + (sc.WALK_OUT - sc.ROAD_HALF - 0.3) * 0.5)
		var ww := sc.WALK_OUT - sc.ROAD_HALF - 0.3
		var z2 := -L
		while z2 < 0.0:
			var slab := 1.2
			walk.add_box_at(Vector3(ww, sc.KERB_H, slab - 0.05), Color(1, 1, 1) * rng.randf_range(0.82, 1.0), Vector3(wx, sc.KERB_H * 0.5, z2 + slab * 0.5))
			if rng.randf() < 0.28:
				walk.add_box_at(Vector3(0.03, 0.006, rng.randf_range(0.5, 1.4)), Color(0.42, 0.41, 0.39), Vector3(wx + rng.randf_range(-ww * 0.4, ww * 0.4), sc.KERB_H + 0.003, z2 + rng.randf_range(0.2, 1.1)))
			z2 += slab
		# driveway cuts through the verge every 40 m
		var dz := -L + 20.0
		while dz < 0.0:
			walk.add_box_at(Vector3(sc.LOT_X - sc.WALK_OUT + 0.5, 0.06, 3.2), Color(0.88, 0.87, 0.83), Vector3(side * (sc.WALK_OUT + (sc.LOT_X - sc.WALK_OUT) * 0.5), 0.03, dz))
			dz += 40.0
	var kmi := MeshInstance3D.new()
	kmi.mesh = kerb.commit_with(concrete_mat)
	chunk.add_child(kmi)
	var wmi := MeshInstance3D.new()
	wmi.mesh = walk.commit_with(concrete_mat)
	chunk.add_child(wmi)

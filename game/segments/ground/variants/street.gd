class_name StreetGround
extends ChunkedLayer

# Asphalt (shader: grain, wheel tracks, stains), faded double yellow centre
# line and white edge lines, red-painted kerb by the crosswalk, concrete
# sidewalks with slab joints and cracks, mown lawns with mottling.

var asphalt_mat: ShaderMaterial
var lawn_mat: StandardMaterial3D
var concrete_mat: StandardMaterial3D


func _init() -> void:
	seed_v = 4242


func build() -> void:
	asphalt_mat = ShaderMaterial.new()
	asphalt_mat.shader = load("res://segments/ground/shaders/asphalt.gdshader")
	asphalt_mat.set_shader_parameter("noise_tex", ctx.noise_tex)
	asphalt_mat.set_shader_parameter("lane_x", (ctx as StreetContext).LANE_X)
	# lawn: two greens mottled by noise, mown stripes
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = 12
	n.frequency = 0.04
	n.fractal_octaves = 4
	for y in 256:
		for x in 256:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var stripe: float = 0.96 + 0.04 * signf(sin(x * 0.2))
			var c: Color = Color(0.25, 0.42, 0.16).lerp(Color(0.42, 0.55, 0.2), v) * stripe
			img.set_pixel(x, y, c)
	lawn_mat = StandardMaterial3D.new()
	lawn_mat.albedo_texture = ImageTexture.create_from_image(img)
	lawn_mat.uv1_scale = Vector3(0.15, 0.15, 0.15)
	lawn_mat.uv1_triplanar = true
	lawn_mat.roughness = 1.0
	# concrete: pale with fine speckle
	var cimg := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := n.get_noise_2d(x * 3.0 + 500.0, y * 3.0) * 0.5 + 0.5
			var c: Color = Color(0.62, 0.6, 0.57).lerp(Color(0.72, 0.7, 0.67), v)
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
	# paint: slightly faded, broken into dashes of wear along the length
	var paint := MeshBatch.new()
	var yellow := Color(0.82, 0.68, 0.14)
	var white := Color(0.82, 0.82, 0.8)
	var z := -L
	while z < 0.0:
		var seg := rng.randf_range(6.0, 14.0)
		var fade := rng.randf_range(0.75, 1.0)
		paint.add_box_at(Vector3(0.12, 0.012, seg), yellow * fade, Vector3(-0.15, 0.025, z + seg * 0.5))
		paint.add_box_at(Vector3(0.12, 0.012, seg), yellow * rng.randf_range(0.75, 1.0), Vector3(0.15, 0.025, z + seg * 0.5))
		for side: float in [-1.0, 1.0]:
			paint.add_box_at(Vector3(0.12, 0.012, seg), white * rng.randf_range(0.75, 1.0), Vector3(side * (sc.ROAD_HALF - 2.3), 0.025, z + seg * 0.5))
		z += seg
	var cz := -L + 12.0
	for i in 10:
		paint.add_box_at(Vector3(0.5, 0.012, 3.0), white * 0.95, Vector3(-sc.ROAD_HALF + 0.9 + i * 1.15, 0.025, cz))
	paint.add_box_at(Vector3(sc.ROAD_HALF * 2.0, 0.012, 0.3), white * 0.95, Vector3(0, 0.025, cz + 2.2))
	for i in 6:
		paint.add_cylinder(0.35, 0.35, 0.02, Color(0.3, 0.28, 0.26), Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-3.5, 3.5), 0.02, -rng.randf_range(0, L))), 12)
	paint.instance(chunk, "Paint", 0.9)
	# kerbs (red near the crosswalk) and sidewalks in concrete, with joints
	var kerb := MeshBatch.new()
	var walk := MeshBatch.new()
	for side: float in [-1.0, 1.0]:
		var kx := side * (sc.ROAD_HALF + 0.15)
		var zz := -L
		while zz < 0.0:
			var seg := 4.0
			var near_cross := zz > cz - 8.0 and zz < cz + 6.0
			kerb.add_box_at(Vector3(0.3, sc.KERB_H, seg - 0.03), Color(0.75, 0.15, 0.12) if near_cross else Color(1, 1, 1), Vector3(kx, sc.KERB_H * 0.5, zz + seg * 0.5))
			zz += seg
		var wx := side * (sc.ROAD_HALF + 0.3 + (sc.WALK_OUT - sc.ROAD_HALF - 0.3) * 0.5)
		var ww := sc.WALK_OUT - sc.ROAD_HALF - 0.3
		var z2 := -L
		while z2 < 0.0:
			var slab := 2.5
			walk.add_box_at(Vector3(ww, sc.KERB_H, slab - 0.04), Color(1, 1, 1) * rng.randf_range(0.92, 1.0), Vector3(wx, sc.KERB_H * 0.5, z2 + slab * 0.5))
			if rng.randf() < 0.08:
				walk.add_box_at(Vector3(0.03, 0.006, rng.randf_range(0.6, 2.0)), Color(0.5, 0.5, 0.48), Vector3(wx + rng.randf_range(-ww * 0.4, ww * 0.4), sc.KERB_H + 0.003, z2 + rng.randf_range(0.3, 2.0)))
			z2 += slab
		# driveway cuts through the verge every 40 m
		var dz := -L + 20.0
		while dz < 0.0:
			walk.add_box_at(Vector3(sc.LOT_X - sc.WALK_OUT + 0.5, 0.06, 3.2), Color(0.98, 0.98, 0.98), Vector3(side * (sc.WALK_OUT + (sc.LOT_X - sc.WALK_OUT) * 0.5), 0.03, dz))
			dz += 40.0
	var kmi := MeshInstance3D.new()
	kmi.mesh = kerb.commit_with(concrete_mat)
	chunk.add_child(kmi)
	var wmi := MeshInstance3D.new()
	wmi.mesh = walk.commit_with(concrete_mat)
	chunk.add_child(wmi)

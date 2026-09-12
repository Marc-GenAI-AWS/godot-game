class_name StreetGround
extends ChunkedLayer

# Asphalt with a double yellow centre line and white edge lines, kerbs,
# concrete sidewalks with joints, grass verges, a crosswalk per chunk.

func _init() -> void:
	seed_v = 4242


func build() -> void:
	# one wide ground plane for the whole loop (grass), then per-chunk detail
	var sc: StreetContext = ctx as StreetContext
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.34, 0.17)
	mat.albedo_texture = ctx.noise_tex
	mat.uv1_scale = Vector3(0.1, 0.1, 0.1)
	mat.roughness = 1.0
	var pm := PlaneMesh.new()
	pm.size = Vector2(400.0, WorldContext.CHUNK * 3.6)
	pm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = Vector3(0, -0.02, -WorldContext.CHUNK * 0.5)
	add_child(mi)
	super.build()


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	var b := MeshBatch.new()
	var asphalt := Color(0.3, 0.29, 0.28)
	var kerb := Color(0.6, 0.58, 0.55)
	var walk := Color(0.55, 0.53, 0.5)
	var yellow := Color(0.9, 0.75, 0.15)
	var white := Color(0.9, 0.9, 0.88)
	b.add_box_at(Vector3(sc.ROAD_HALF * 2.0, 0.04, L), asphalt, Vector3(0, 0.0, -L * 0.5))
	# lines
	b.add_box_at(Vector3(0.12, 0.012, L), yellow, Vector3(-0.15, 0.025, -L * 0.5))
	b.add_box_at(Vector3(0.12, 0.012, L), yellow, Vector3(0.15, 0.025, -L * 0.5))
	for side: float in [-1.0, 1.0]:
		b.add_box_at(Vector3(0.12, 0.012, L), white, Vector3(side * (sc.ROAD_HALF - 2.3), 0.025, -L * 0.5))
		# kerb + sidewalk + joints
		b.add_box_at(Vector3(0.3, sc.KERB_H, L), kerb, Vector3(side * (sc.ROAD_HALF + 0.15), sc.KERB_H * 0.5, -L * 0.5))
		var wx := side * (sc.ROAD_HALF + 0.3 + (sc.WALK_OUT - sc.ROAD_HALF - 0.3) * 0.5)
		b.add_box_at(Vector3(sc.WALK_OUT - sc.ROAD_HALF - 0.3, sc.KERB_H, L), walk, Vector3(wx, sc.KERB_H * 0.5, -L * 0.5))
		var z := -L
		while z < 0.0:
			b.add_box_at(Vector3(sc.WALK_OUT - sc.ROAD_HALF - 0.3, 0.005, 0.05), walk.darkened(0.25), Vector3(wx, sc.KERB_H + 0.003, z))
			z += 2.5
		# driveway cuts through the verge every so often
	# crosswalk near the chunk start
	var cz := -L + 12.0
	for i in 10:
		b.add_box_at(Vector3(0.5, 0.012, 3.0), white, Vector3(-sc.ROAD_HALF + 0.9 + i * 1.15, 0.025, cz))
	b.add_box_at(Vector3(sc.ROAD_HALF * 2.0, 0.012, 0.3), white, Vector3(0, 0.025, cz + 2.2))   # stop line
	# manhole covers / patches
	for i in 6:
		b.add_cylinder(0.35, 0.35, 0.02, Color(0.32, 0.3, 0.28), Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-3.5, 3.5), 0.02, -rng.randf_range(0, L))), 12)
	b.instance(chunk, "Road", 0.9)

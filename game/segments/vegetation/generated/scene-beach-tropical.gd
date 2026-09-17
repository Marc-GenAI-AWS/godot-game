extends ChunkedLayer

var crowns: Array[Node3D] = []


func _init() -> void:
	seed_v = 7734


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK

	# Dense line of giant, tall fan palms just seaward of the promenade deck.
	var z := -L + rng.randf_range(0.0, 4.0)
	while z < 0.0:
		var x := BeachContext.BOARDWALK_X - 2.5 + rng.randf_range(-0.6, 0.6)
		var gy := ctx.ground_height(x, z) - 0.2
		crowns.append(Palm.build(chunk, Vector3(x, gy, z), rng, ctx, true))
		z += rng.randf_range(3.5, 5.5)

	# A second, staggered row further landward for depth and resort density.
	var z2 := -L + rng.randf_range(2.0, 6.0)
	while z2 < 0.0:
		var x2 := BeachContext.BOARDWALK_X - 5.5 + rng.randf_range(-0.9, 0.9)
		var gy2 := ctx.ground_height(x2, z2) - 0.2
		crowns.append(Palm.build(chunk, Vector3(x2, gy2, z2), rng, ctx, true))
		z2 += rng.randf_range(6.0, 9.5)

	# Dense scatter of giant coconut palms on the upper sand.
	var coconut_count := rng.randi_range(10, 16)
	for i in coconut_count:
		var cx := rng.randf_range(-48.0, -38.0)
		var cz := rng.randf_range(-L, 0.0)
		var cy := ctx.ground_height(cx, cz) - 0.2
		crowns.append(Palm.build(chunk, Vector3(cx, cy, cz), rng, ctx, false))

	# Some hedges along the boardwalk's landward side, resort-style clumps.
	var hedges := MeshBatch.new()
	var shrubs := MeshBatch.new()
	var card := QuadMesh.new()
	card.size = Vector2(0.9, 0.9)
	var hz := -L + rng.randf_range(4.0, 10.0)
	while hz < 0.0:
		var len := rng.randf_range(5.0, 10.0)
		var hx := BeachContext.BOARDWALK_X - 8.6 + rng.randf_range(-0.3, 0.3)
		var hh := rng.randf_range(0.9, 1.4)
		hedges.add_box_at(Vector3(1.3, hh, len), Color(0.14, 0.38, 0.16), Vector3(hx, ctx.ground_height(hx, hz) + hh * 0.5, hz + len * 0.5))
		var n := int(len * 3.5)
		for i in n:
			var p := Vector3(
				hx + rng.randf_range(-0.6, 0.6),
				ctx.ground_height(hx, hz) + rng.randf_range(0.2, hh + 0.4),
				hz + rng.randf_range(0.0, len)
			)
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
			shrubs.add(card, Transform3D(b, p), Color(1, 1, 1).lerp(Color(0.75, 0.95, 0.7), rng.randf()) * rng.randf_range(0.75, 1.05))
		var gp: Vector3 = chunk.global_transform * Vector3(hx, 0.0, hz + len * 0.5)
		var obstacles := int(max(1.0, len / 2.0))
		for i in obstacles:
			ctx.add_obstacle(gp + Vector3(0.0, 0.0, (float(i) - obstacles * 0.5) * 2.0), 0.8)
		hz += len + rng.randf_range(4.0, 12.0)
	if not hedges.is_empty():
		hedges.instance(chunk, "Hedges", 0.95)
	if not shrubs.is_empty():
		var smi := MeshInstance3D.new()
		smi.mesh = shrubs.commit_with(LeafyTree.leaf_material())
		chunk.add_child(smi)


func tick(_delta: float) -> void:
	var t := ctx.time
	for i in crowns.size():
		var c := crowns[i]
		c.rotation.x = 0.045 * sin(t * 0.9 + i * 1.3)
		c.rotation.z = 0.055 * sin(t * 0.7 + i * 0.7) + 0.03

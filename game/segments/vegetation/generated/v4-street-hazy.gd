extends ChunkedLayer

var crowns: Array[Node3D] = []


func _init() -> void:
	seed_v = 7734


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	for side: float in [-1.0, 1.0]:
		var count := rng.randi_range(12, 22)
		var z := -L + rng.randf_range(2.0, 6.0)
		var step := L / float(count)
		for i in count:
			var x := side * (sc.WALK_OUT + 1.6 + rng.randf_range(-0.4, 0.8))
			LeafyTree.build(chunk, Vector3(x, 0.0, z), rng, ctx, rng.randf_range(1.0, 1.3))
			z += step * rng.randf_range(0.7, 1.3)
			if z >= 0.0:
				break

		# some hedges along lot fronts, manicured and tidy
		var hz := -L
		var hb := MeshBatch.new()
		var shrubs := MeshBatch.new()
		var card := QuadMesh.new()
		card.size = Vector2(0.8, 0.8)
		while hz < 0.0:
			if rng.randf() < 0.35:
				var len := rng.randf_range(4.0, 9.0)
				var hh := rng.randf_range(0.9, 1.2)
				var hx := side * (sc.LOT_X - 0.6)
				hb.add_box_at(Vector3(0.8, hh, len), Color(0.13, 0.32, 0.14), Vector3(hx, hh * 0.5, hz + len * 0.5))
				var n := int(len * 2.5)
				for j in n:
					var p := Vector3(hx + rng.randf_range(-0.4, 0.4), rng.randf_range(0.2, hh + 0.15), hz + rng.randf_range(0.0, len))
					var b := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
					shrubs.add(card, Transform3D(b, p), Color(1, 1, 1).lerp(Color(0.75, 0.95, 0.7), rng.randf()) * rng.randf_range(0.8, 1.05))
				ctx.add_obstacle(chunk.global_transform * Vector3(hx, 0.0, hz + len * 0.5), 0.8)
				hz += len + rng.randf_range(4.0, 10.0)
			else:
				hz += rng.randf_range(6.0, 14.0)
		if not hb.is_empty():
			hb.instance(chunk, "Hedges", 0.95)
			var smi := MeshInstance3D.new()
			smi.mesh = shrubs.commit_with(LeafyTree.leaf_material())
			chunk.add_child(smi)


func tick(_delta: float) -> void:
	var t := ctx.time
	for i in crowns.size():
		var c := crowns[i]
		c.rotation.x = 0.04 * sin(t * 0.9 + i * 1.3)
		c.rotation.z = 0.05 * sin(t * 0.7 + i * 0.7) + 0.03

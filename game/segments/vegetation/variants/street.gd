class_name StreetVegetation
extends ChunkedLayer

var crowns: Array[Node3D] = []

func _init() -> void:
	seed_v = 5150


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	for side: float in [-1.0, 1.0]:
		var z := -L + rng.randf_range(2.0, 8.0)
		while z < 0.0:
			var x := side * (sc.WALK_OUT + 1.6 + rng.randf_range(-0.4, 0.8))
			if rng.randf() < 0.45:
				crowns.append(Palm.build(chunk, Vector3(x, 0.0, z), rng, ctx, true))
			else:
				LeafyTree.build(chunk, Vector3(x, 0.0, z), rng, ctx, rng.randf_range(0.9, 1.4))
			z += rng.randf_range(10.0, 17.0)
		# hedges and low shrubs along lot fronts, as leaf-card clumps on a green core
		var hz := -L
		var hb := MeshBatch.new()
		var shrubs := MeshBatch.new()
		var card := QuadMesh.new()
		card.size = Vector2(0.9, 0.9)
		while hz < 0.0:
			var len := rng.randf_range(5.0, 12.0)
			if rng.randf() < 0.5:
				var hh := rng.randf_range(0.8, 1.3)
				hb.add_box_at(Vector3(0.8, hh, len), Color(0.12, 0.3, 0.12), Vector3(side * (sc.LOT_X - 0.6), hh * 0.5, hz + len * 0.5))
				var n := int(len * 3.0)
				for i in n:
					var p := Vector3(side * (sc.LOT_X - 0.6) + rng.randf_range(-0.45, 0.45), rng.randf_range(0.2, hh + 0.2), hz + rng.randf_range(0.0, len))
					var b := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
					shrubs.add(card, Transform3D(b, p), Color(1, 1, 1).lerp(Color(0.8, 0.95, 0.75), rng.randf()) * rng.randf_range(0.75, 1.05))
			hz += len + rng.randf_range(2.0, 8.0)
		if not hb.is_empty():
			hb.instance(chunk, "Hedges", 0.95)
			var smi := MeshInstance3D.new()
			smi.mesh = shrubs.commit_with(LeafyTree.leaf_material())
			chunk.add_child(smi)


func tick(_delta: float) -> void:
	var t := ctx.time
	for i in crowns.size():
		var c := crowns[i]
		c.rotation.x = 0.045 * sin(t * 0.9 + i * 1.3)
		c.rotation.z = 0.055 * sin(t * 0.7 + i * 0.7) + 0.03

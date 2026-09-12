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
			if rng.randf() < 0.55:
				crowns.append(Palm.build(chunk, Vector3(x, 0.0, z), rng, ctx, true))
			else:
				Palm.build_leafy(chunk, Vector3(x, 0.0, z), rng, ctx)
			z += rng.randf_range(9.0, 16.0)
		# hedges along some lot fronts
		var hz := -L
		var hb := MeshBatch.new()
		while hz < 0.0:
			var len := rng.randf_range(5.0, 12.0)
			if rng.randf() < 0.5:
				hb.add_box_at(Vector3(0.8, rng.randf_range(0.8, 1.3), len), Color(0.14, 0.36, 0.15), Vector3(side * (sc.LOT_X - 0.6), 0.5, hz + len * 0.5))
			hz += len + rng.randf_range(2.0, 8.0)
		if not hb.is_empty():
			hb.instance(chunk, "Hedges", 0.95)


func tick(_delta: float) -> void:
	var t := ctx.time
	for i in crowns.size():
		var c := crowns[i]
		c.rotation.x = 0.045 * sin(t * 0.9 + i * 1.3)
		c.rotation.z = 0.055 * sin(t * 0.7 + i * 0.7) + 0.03

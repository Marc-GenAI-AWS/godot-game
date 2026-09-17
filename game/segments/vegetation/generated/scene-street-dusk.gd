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
			LeafyTree.build(chunk, Vector3(x, 0.0, z), rng, ctx, rng.randf_range(0.7, 0.9))
			z += step + rng.randf_range(-1.5, 1.5)
			if z >= 0.0:
				break


func tick(_delta: float) -> void:
	var t := ctx.time
	for i in crowns.size():
		var c := crowns[i]
		c.rotation.x = 0.045 * sin(t * 0.9 + i * 1.3)
		c.rotation.z = 0.055 * sin(t * 0.7 + i * 0.7) + 0.03

extends ChunkedLayer

var crowns: Array[Node3D] = []


func _init() -> void:
	seed_v = 7734


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var bc: BeachContext = ctx as BeachContext

	# Sparse line of young, thin fan palms just seaward of the promenade deck.
	var count := rng.randi_range(6, 12)
	var z := -L + rng.randf_range(2.0, 10.0)
	var step := L / float(count)
	for i in count:
		var x := bc.BOARDWALK_X - 2.5 + rng.randf_range(-0.6, 0.6)
		var y := ctx.ground_height(x, z) - 0.2
		var crown := Palm.build(chunk, Vector3(x, y, z), rng, ctx, true)
		crown.scale = Vector3.ONE * rng.randf_range(0.65, 0.75)
		crowns.append(crown)
		z += step * rng.randf_range(0.7, 1.3)
		if z >= 0.0:
			break

	# A few extra young, sun-bleached fan palms closer to the beach line,
	# so the planting reads clearly in the chase and side views.
	var extra := rng.randi_range(2, 4)
	for i in extra:
		var x := rng.randf_range(-52.0, -40.0)
		var zz := rng.randf_range(-L, 0.0)
		var y := ctx.ground_height(x, zz) - 0.2
		var crown := Palm.build(chunk, Vector3(x, y, zz), rng, ctx, true)
		crown.scale = Vector3.ONE * rng.randf_range(0.6, 0.72)
		crowns.append(crown)


func tick(_delta: float) -> void:
	var t := ctx.time
	for i in crowns.size():
		var c := crowns[i]
		c.rotation.x = 0.045 * sin(t * 0.9 + i * 1.3)
		c.rotation.z = 0.055 * sin(t * 0.7 + i * 0.7) + 0.03

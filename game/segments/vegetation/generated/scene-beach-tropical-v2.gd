extends ChunkedLayer

var crowns: Array[Node3D] = []


func _init() -> void:
	seed_v = 7734


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var bc: BeachContext = ctx as BeachContext

	# Dense line of giant, tall fan palms just seaward of the promenade deck.
	var z := -L + rng.randf_range(0.0, 4.0)
	while z < 0.0:
		var x := bc.BOARDWALK_X - 2.5 + rng.randf_range(-0.6, 0.6)
		var y := ctx.ground_height(x, z) - 0.2
		crowns.append(Palm.build(chunk, Vector3(x, y, z), rng, ctx, true))
		z += rng.randf_range(3.0, 4.5)

	# A second, looser scatter of giant fan palms further up the sand for lushness.
	var extra := rng.randi_range(10, 16)
	for i in extra:
		var x2 := rng.randf_range(-50.0, -34.0)
		var z2 := rng.randf_range(-L, 0.0)
		var y2 := ctx.ground_height(x2, z2) - 0.2
		crowns.append(Palm.build(chunk, Vector3(x2, y2, z2), rng, ctx, true))

	# Some hedges along the boardwalk's landward side, less dense than a proper hedge row.
	var hedges := MeshBatch.new()
	var hz := -L + rng.randf_range(4.0, 12.0)
	while hz < 0.0:
		if rng.randf() < 0.4:
			var len := rng.randf_range(4.0, 8.0)
			var hx := bc.BOARDWALK_X - 8.6 + rng.randf_range(-0.5, 0.5)
			var hh := rng.randf_range(0.9, 1.3)
			hedges.add_box_at(Vector3(1.1, hh, len), Color(0.14, 0.38, 0.16), Vector3(hx, ctx.ground_height(hx, hz) + hh * 0.5, hz + len * 0.5))
			ctx.add_obstacle(chunk.global_transform * Vector3(hx, 0.0, hz + len * 0.5), 0.8)
			hz += len + rng.randf_range(6.0, 16.0)
		else:
			hz += rng.randf_range(6.0, 14.0)
	if not hedges.is_empty():
		hedges.instance(chunk, "Hedges", 0.95)


func tick(_delta: float) -> void:
	var t := ctx.time
	for i in crowns.size():
		var c := crowns[i]
		c.rotation.x = 0.045 * sin(t * 0.9 + i * 1.3)
		c.rotation.z = 0.055 * sin(t * 0.7 + i * 0.7) + 0.03

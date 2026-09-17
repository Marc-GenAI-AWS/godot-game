extends ChunkedLayer

var crowns: Array[Node3D] = []


func _init() -> void:
	seed_v = 7734


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var bc: BeachContext = ctx as BeachContext

	# Line of tall, mature fan palms just seaward of the promenade deck.
	var z := -L + rng.randf_range(0.0, 6.0)
	while z < 0.0:
		var x := bc.BOARDWALK_X - 2.5 + rng.randf_range(-0.6, 0.6)
		var y := ctx.ground_height(x, z) - 0.2
		crowns.append(Palm.build(chunk, Vector3(x, y, z), rng, ctx, true))
		z += rng.randf_range(8.0, 13.0)

	# A scattering of tall fan palms scattered on the upper sand, resort-style spacing.
	var extra := rng.randi_range(6, 12)
	for i in extra:
		var sx := rng.randf_range(-48.0, -38.0)
		var sz := rng.randf_range(-L, 0.0)
		var sy := ctx.ground_height(sx, sz) - 0.2
		crowns.append(Palm.build(chunk, Vector3(sx, sy, sz), rng, ctx, true))

	# Some hedges along the boardwalk's landward side, resort-style spacing.
	var hedges := MeshBatch.new()
	var hz := -L + rng.randf_range(4.0, 10.0)
	while hz < 0.0:
		var len := rng.randf_range(5.0, 10.0)
		var hx := bc.BOARDWALK_X - 8.6 + rng.randf_range(-0.6, 0.6)
		var hh := rng.randf_range(0.9, 1.15)
		var hy := ctx.ground_height(hx, hz)
		hedges.add_box_at(Vector3(1.2, hh, len), Color(0.15, 0.4, 0.17), Vector3(hx, hy + hh * 0.5, hz + len * 0.5))
		ctx.add_obstacle(chunk.global_transform * Vector3(hx, 0.0, hz + len * 0.5), 0.8)
		var segs := int(max(1.0, len / 2.0))
		for s in segs:
			ctx.add_obstacle(chunk.global_transform * Vector3(hx, 0.0, hz + (float(s) + 0.5) * (len / float(segs))), 0.8)
		hz += len + rng.randf_range(6.0, 14.0)
	if not hedges.is_empty():
		hedges.instance(chunk, "Hedges", 0.95)


func tick(_delta: float) -> void:
	var t := ctx.time
	for i in crowns.size():
		var c := crowns[i]
		c.rotation.x = 0.045 * sin(t * 0.9 + i * 1.3)
		c.rotation.z = 0.055 * sin(t * 0.7 + i * 0.7) + 0.03

extends ChunkedLayer

var crowns: Array[Node3D] = []


func _init() -> void:
	seed_v = 7734


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var bc: BeachContext = ctx as BeachContext

	# Mostly tall, thin fan palms in a line just seaward of the promenade deck.
	# A handful still drop to fuller coconut-type crowns for variety, keeping
	# the bulk of the line tall and distinct.
	var z := -L + rng.randf_range(0.0, 6.0)
	while z < 0.0:
		var x := bc.BOARDWALK_X - 2.5 + rng.randf_range(-0.6, 0.6)
		var gy := ctx.ground_height(x, z) - 0.2
		var tall := rng.randf() < 0.75
		crowns.append(Palm.build(chunk, Vector3(x, gy, z), rng, ctx, tall))
		z += rng.randf_range(7.0, 11.0)

	# A few fuller coconut palms scattered on the upper sand, mature and
	# distinct from the fan-palm line.
	var coco_count := rng.randi_range(3, 5)
	for i in coco_count:
		var cx := rng.randf_range(-48.0, -38.0)
		var cz := rng.randf_range(-L, 0.0)
		var cy := ctx.ground_height(cx, cz) - 0.2
		crowns.append(Palm.build(chunk, Vector3(cx, cy, cz), rng, ctx, false))

	# Some hedges along the boardwalk's landward side, dry and sun-bleached.
	# Dryer, sun-bleached tones for a clearer "dry scrub" look.
	var hedges := MeshBatch.new()
	var shrubs := MeshBatch.new()
	var card := QuadMesh.new()
	card.size = Vector2(0.85, 0.85)
	var hz := -L
	while hz < 0.0:
		if rng.randf() < 0.7:
			var len := rng.randf_range(6.0, 12.0)
			var hx := bc.BOARDWALK_X - 8.6 + rng.randf_range(-0.3, 0.3)
			var hh := rng.randf_range(0.9, 1.2)
			var dry_color := Color(0.52, 0.52, 0.28).lerp(Color(0.46, 0.46, 0.24), rng.randf())
			hedges.add_box_at(Vector3(1.1, hh, len), dry_color, Vector3(hx, ctx.ground_height(hx, hz) + hh * 0.5, hz + len * 0.5))
			var n := int(len * 2.5)
			for j in n:
				var p := Vector3(
					hx + rng.randf_range(-0.5, 0.5),
					ctx.ground_height(hx, hz) + hh + rng.randf_range(-0.1, 0.35),
					hz + rng.randf_range(0.0, len)
				)
				var b := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
				shrubs.add(card, Transform3D(b, p), dry_color.lerp(Color(0.75, 0.75, 0.45), rng.randf()))
			ctx.add_obstacle(chunk.global_transform * Vector3(hx, 0.0, hz + len * 0.5), 0.8)
			var seg_count := int(max(1.0, len / 2.0))
			for k in seg_count:
				ctx.add_obstacle(chunk.global_transform * Vector3(hx, 0.0, hz + (k + 0.5) * 2.0), 0.8)
			hz += len + rng.randf_range(4.0, 10.0)
		else:
			hz += rng.randf_range(6.0, 12.0)
	if not hedges.is_empty():
		hedges.instance(chunk, "Hedges", 0.9)
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

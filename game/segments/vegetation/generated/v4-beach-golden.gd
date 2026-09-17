extends ChunkedLayer

var crowns: Array[Node3D] = []


func _init() -> void:
	seed_v = 7734


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	# Mostly tall, giant fan palms in a resort-style line just seaward of the deck.
	var z := -L + rng.randf_range(0.0, 5.0)
	while z < 0.0:
		var x := BeachContext.BOARDWALK_X - 2.5 + rng.randf_range(-0.7, 0.7)
		var y := ctx.ground_height(x, z) - 0.2
		var crown := Palm.build(chunk, Vector3(x, y, z), rng, ctx, true)
		# Upscale the whole palm (trunk + crown) to read as giant, keeping the base grounded.
		var s := rng.randf_range(1.4, 1.8)
		crown.scale = Vector3(s, s, s)
		crowns.append(crown)
		z += rng.randf_range(6.5, 9.5)

	# A scattering of fuller, distinctly giant coconut palms on the upper sand,
	# breaking the all-fan-palm row and clearly reading as giant sizing.
	var coco_count := rng.randi_range(5, 8)
	for i in coco_count:
		var cx := rng.randf_range(-48.0, -38.0)
		var cz := rng.randf_range(-L, 0.0)
		var cy := ctx.ground_height(cx, cz) - 0.2
		var ccrown := Palm.build(chunk, Vector3(cx, cy, cz), rng, ctx, false)
		var cs := rng.randf_range(1.6, 1.9)
		ccrown.scale = Vector3(cs, cs, cs)
		crowns.append(ccrown)

	# Some hedges along the boardwalk's landward side, resort-style thickening,
	# with a clearly distinct core and a few fuller leaf-card clumps on top.
	var hedges := MeshBatch.new()
	var shrubs := MeshBatch.new()
	var card := QuadMesh.new()
	card.size = Vector2(0.9, 0.9)
	var hz := -L
	while hz < 0.0:
		var len := rng.randf_range(6.0, 14.0)
		var hx := BeachContext.BOARDWALK_X - 8.6
		var hy := ctx.ground_height(hx, hz) + 0.9
		hedges.add_box_at(Vector3(1.3, 1.1, len), Color(0.14, 0.36, 0.16), Vector3(hx, hy, hz + len * 0.5))
		ctx.add_obstacle(chunk.global_transform * Vector3(hx, 0.0, hz + len * 0.5), 0.8)
		# A second, fuller box on top for a thicker, more resort-style hedge silhouette
		# that still reads clearly as two distinct layers (not a single uniform slab).
		var fh := rng.randf_range(0.9, 1.3)
		hedges.add_box_at(Vector3(1.1, fh, len), Color(0.11, 0.32, 0.14), Vector3(hx, hy + fh * 0.5, hz + len * 0.5))
		# A few extra leaf-card clumps on top of the hedge core for a fuller,
		# resort-style look without turning it into a solid wall.
		var n := int(len * 2.5)
		for i in n:
			var p := Vector3(hx + rng.randf_range(-0.6, 0.6), hy + rng.randf_range(fh * 0.3, fh + 0.3), hz + rng.randf_range(0.0, len))
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
			var tint: Color = Color(1, 1, 1).lerp(Color(0.75, 0.95, 0.7), rng.randf()) * rng.randf_range(0.75, 1.05)
			shrubs.add(card, Transform3D(b, p), tint)
		hz += len + rng.randf_range(4.0, 10.0)
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

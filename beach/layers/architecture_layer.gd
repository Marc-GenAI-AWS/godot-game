class_name ArchitectureLayer
extends ChunkedLayer

# Hotel row modelled on the reference: mostly cream/white mid-rises with strong
# horizontal balcony banding and dark window strips, a few pastels, ornate
# art-deco crowns, one tall dark tower in the distance, the promenade with
# railing, lamps, benches and bins, and lifeguard towers.

func _init() -> void:
	seed_v = 1234


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	_hotels(chunk, rng)
	_boardwalk(chunk, rng)
	_lifeguard_tower(chunk, Vector3(-14.0, 0.0, -70.0), Color(0.93, 0.93, 0.9), Color(0.3, 0.32, 0.35))
	_lifeguard_tower(chunk, Vector3(-13.0, 0.0, -165.0), Color(0.8, 0.2, 0.2), Color(0.95, 0.95, 0.92))
	_far_tower(chunk)


func _hotels(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var creams := [Color(0.95, 0.92, 0.84), Color(0.97, 0.95, 0.9), Color(0.9, 0.86, 0.78), Color(0.93, 0.89, 0.8), Color(0.88, 0.87, 0.84), Color(0.96, 0.9, 0.78)]
	var pastels := [Color(0.94, 0.74, 0.74), Color(0.7, 0.88, 0.8), Color(0.72, 0.82, 0.94), Color(0.98, 0.84, 0.66), Color(0.92, 0.9, 0.7)]
	var window := Color(0.24, 0.29, 0.36)
	var rail := Color(0.9, 0.9, 0.9)
	var z := -WorldContext.CHUNK
	var bx := WorldContext.BOARDWALK_X
	while z < 0.0:
		var w := rng.randf_range(16.0, 30.0)
		var d := rng.randf_range(18.0, 30.0)
		var floors := rng.randi_range(4, 11)
		if rng.randf() < 0.15:
			floors = rng.randi_range(16, 26)
		var fh := 3.1
		var h := floors * fh
		var x := bx - 9.0 - rng.randf_range(0.0, 6.0) - d * 0.5
		var c: Color = creams[rng.randi() % creams.size()] if rng.randf() < 0.65 else pastels[rng.randi() % pastels.size()]
		var b := Node3D.new()
		b.position = Vector3(x, ctx.sand_height(x, z) - 0.5, z + w * 0.5)
		parent.add_child(b)
		var batch := MeshBatch.new()
		# main block
		batch.add_box_at(Vector3(d, h, w), c, Vector3(0, h * 0.5, 0))
		var face_x := d * 0.5
		# horizontal banding: per floor a dark window strip and a balcony slab with rail
		var banded := rng.randf() < 0.85
		for f in floors:
			var y := f * fh
			# window strip recessed into the sea-facing facade
			batch.add_box_at(Vector3(0.12, 1.15, w * 0.92), window, Vector3(face_x + 0.02, y + 2.0, 0))
			if banded and f > 0:
				batch.add_box_at(Vector3(1.7, 0.22, w * 0.94), c.darkened(0.08), Vector3(face_x + 0.85, y + 0.05, 0))
				batch.add_box_at(Vector3(0.05, 0.95, w * 0.94), rail, Vector3(face_x + 1.68, y + 0.6, 0))
				var nd := int(w * 0.94 / 4.5)
				for k in range(1, nd):
					batch.add_box_at(Vector3(1.6, 0.95, 0.06), c.darkened(0.12), Vector3(face_x + 0.85, y + 0.6, -w * 0.47 + k * (w * 0.94 / nd)))
			# side windows (toward -z / +z) as a lighter strip
			batch.add_box_at(Vector3(d * 0.9, 1.5, 0.1), window.lightened(0.15), Vector3(0, y + 1.9, w * 0.5 + 0.02))
			batch.add_box_at(Vector3(d * 0.9, 1.5, 0.1), window.lightened(0.15), Vector3(0, y + 1.9, -w * 0.5 - 0.02))
		# ground floor: darker glazed shopfront and an awning
		batch.add_box_at(Vector3(0.15, 2.6, w * 0.95), Color(0.12, 0.14, 0.18), Vector3(face_x + 0.03, 1.5, 0))
		var awn_c: Color = [Color(0.85, 0.22, 0.25), Color(0.2, 0.45, 0.7), Color(0.2, 0.55, 0.4), Color(0.95, 0.8, 0.3)][rng.randi() % 4]
		batch.add_box_at(Vector3(2.6, 0.12, w * 0.6), awn_c, Vector3(face_x + 1.3, 3.3, 0))
		# roof: parapet, crown variants, rooftop clutter
		batch.add_box_at(Vector3(d + 0.5, 0.6, w + 0.5), c.darkened(0.15), Vector3(0, h + 0.3, 0))
		var style := rng.randf()
		if style < 0.3:
			# stepped art-deco crown with a small dome or spire
			batch.add_box_at(Vector3(d * 0.6, fh * 1.4, w * 0.6), c, Vector3(0, h + fh * 0.7, 0))
			batch.add_box_at(Vector3(d * 0.4, fh * 1.0, w * 0.4), c, Vector3(0, h + fh * 1.9, 0))
			var sm := SphereMesh.new()
			sm.radius = minf(d, w) * 0.14
			sm.height = sm.radius * 2.0
			sm.radial_segments = 14
			sm.rings = 8
			batch.add(sm, Transform3D(Basis.IDENTITY, Vector3(0, h + fh * 2.4 + sm.radius * 0.6, 0)), c.darkened(0.2))
		elif style < 0.55:
			batch.add_box_at(Vector3(d * 0.5, fh * 0.9, w * 0.5), c, Vector3(0, h + fh * 0.45, 0))
		# rounded corner tower on some
		if rng.randf() < 0.35:
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			batch.add_cylinder(w * 0.2, w * 0.2, h + 1.5, c, Transform3D(Basis.IDENTITY, Vector3(face_x, (h + 1.5) * 0.5, side * w * 0.5)), 18)
		for k in rng.randi_range(1, 4):
			batch.add_box_at(Vector3(rng.randf_range(1.5, 3.0), rng.randf_range(1.0, 2.5), rng.randf_range(1.5, 3.0)), Color(0.75, 0.75, 0.72), Vector3(rng.randf_range(-d * 0.35, d * 0.35), h + 1.2, rng.randf_range(-w * 0.35, w * 0.35)))
		batch.instance(b, "Hotel", 0.9)
		z += w + rng.randf_range(1.5, 6.0)


func _far_tower(parent: Node3D) -> void:
	# tall dark glass tower well behind the row, like the one on the reference skyline
	var batch := MeshBatch.new()
	var x := WorldContext.BOARDWALK_X - 120.0
	var z := -WorldContext.CHUNK * 0.62
	batch.add_box_at(Vector3(26.0, 118.0, 30.0), Color(0.22, 0.27, 0.33), Vector3(0, 59.0, 0))
	for f in 36:
		batch.add_box_at(Vector3(26.4, 0.35, 30.4), Color(0.55, 0.6, 0.65), Vector3(0, f * 3.2 + 1.0, 0))
	var mi := batch.instance(parent, "FarTower", 0.5)
	mi.position = Vector3(x, ctx.sand_height(x, z) - 1.0, z)


func _boardwalk(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var bx := WorldContext.BOARDWALK_X
	var y := ctx.sand_height(bx, 0.0)
	var batch := MeshBatch.new()
	batch.add_box_at(Vector3(9.0, 0.5, L), Color(0.74, 0.66, 0.55), Vector3(bx - 3.5, y + 0.25, -L * 0.5))
	batch.add_box_at(Vector3(0.4, 0.6, L), Color(0.85, 0.82, 0.75), Vector3(bx + 1.0, y + 0.3, -L * 0.5))
	# paving joints
	var zz := -L
	while zz < 0.0:
		batch.add_box_at(Vector3(9.0, 0.02, 0.06), Color(0.6, 0.53, 0.44), Vector3(bx - 3.5, y + 0.51, zz))
		zz += 2.0
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 10
	sm.rings = 5
	# Railing along the sand edge with an opening every 8th bay (ramps onto the deck).
	var z := -L + 2.0
	var i := 0
	while z < 0.0:
		var opening := (i % 8) == 4
		if not opening:
			batch.add_box_at(Vector3(0.06, 0.08, 3.5), Color(0.3, 0.3, 0.32), Vector3(bx + 0.6, y + 1.55, z + 1.75))
			var rz := z
			while rz < z + 3.5:
				ctx.add_obstacle(parent.global_transform * Vector3(bx + 0.6, 0, rz), 0.5)
				rz += 0.8
		batch.add_box_at(Vector3(0.1, 1.1, 0.1), Color(0.3, 0.3, 0.32), Vector3(bx + 0.6, y + 1.05, z))
		if i % 4 == 0:
			ctx.add_obstacle(parent.global_transform * Vector3(bx - 7.5, 0, z), 0.35)
			ctx.add_obstacle(parent.global_transform * Vector3(bx - 5.6, 0, z + 4.0), 1.1)
			ctx.add_obstacle(parent.global_transform * Vector3(bx - 1.0, 0, z - 2.0), 0.5)
			batch.add_cylinder(0.07, 0.1, 5.0, Color(0.25, 0.27, 0.3), Transform3D(Basis.IDENTITY, Vector3(bx - 7.5, y + 3.0, z)))
			batch.add(sm, Transform3D(Basis.IDENTITY, Vector3(bx - 7.5, y + 5.7, z)), Color(0.98, 0.98, 0.9))
			batch.add_box_at(Vector3(0.5, 0.08, 1.8), Color(0.55, 0.4, 0.25), Vector3(bx - 5.8, y + 0.95, z + 4.0))
			batch.add_box_at(Vector3(0.08, 0.5, 1.8), Color(0.55, 0.4, 0.25), Vector3(bx - 5.55, y + 1.2, z + 4.0))
			batch.add_cylinder(0.3, 0.28, 0.9, Color(0.2, 0.4, 0.3), Transform3D(Basis.IDENTITY, Vector3(bx - 1.0, y + 0.95, z - 2.0)))
		z += 3.5
		i += 1
	batch.instance(parent, "Boardwalk", 0.9)


func _lifeguard_tower(parent: Node3D, pos: Vector3, hut: Color, roof: Color) -> void:
	# Hut on stilts with a deck, railing, sloped roof and a ramp, as in the reference.
	var t := Node3D.new()
	t.position = Vector3(pos.x, ctx.sand_height(pos.x, pos.z), pos.z)
	parent.add_child(t)
	ctx.add_obstacle(t.global_position, 2.7)
	var white := Color(0.94, 0.94, 0.92)
	var wood := Color(0.6, 0.45, 0.3)
	var batch := MeshBatch.new()
	for dx in [-1.6, 1.6]:
		for dz in [-1.6, 1.6]:
			batch.add_box_at(Vector3(0.22, 3.0, 0.22), white, Vector3(dx, 1.5, dz))
	batch.add_box_at(Vector3(4.4, 0.18, 4.4), wood, Vector3(0, 3.05, 0))
	batch.add_box_at(Vector3(3.2, 2.5, 3.2), hut, Vector3(0, 4.4, 0))
	batch.add_box_at(Vector3(2.6, 1.1, 0.06), Color(0.15, 0.2, 0.28), Vector3(0, 4.7, 1.62))   # window toward the sea
	batch.add_box_at(Vector3(4.0, 0.25, 4.4), roof, Vector3(0, 5.75, 0))
	batch.add_box_at(Vector3(4.6, 0.12, 5.0), roof, Vector3(0, 5.95, 0.2))
	# deck railing
	for side in [-1.0, 1.0]:
		batch.add_box_at(Vector3(0.06, 0.9, 4.4), white, Vector3(side * 2.15, 3.6, 0))
		batch.add_box_at(Vector3(4.4, 0.06, 0.06), white, Vector3(0, 4.05, side * 2.15))
	# ramp down the back (away from the sea)
	var ramp := Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, 0.55), Vector3(0, 1.55, -4.6))
	batch.add_box(Vector3(1.3, 0.12, 6.4), wood, ramp)
	batch.add_box_at(Vector3(0.05, 2.0, 0.05), white, Vector3(1.8, 7.0, 1.8))
	batch.add_box_at(Vector3(0.02, 0.5, 0.8), Color(0.95, 0.85, 0.1), Vector3(1.8, 7.7, 1.4))
	batch.instance(t, "Lifeguard", 0.9)

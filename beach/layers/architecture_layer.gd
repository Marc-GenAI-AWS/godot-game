class_name ArchitectureLayer
extends ChunkedLayer

# Hotels with balconies and stepped tops, the boardwalk with railing and
# lamps, and the lifeguard tower.

func _init() -> void:
	seed_v = 1234


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	_hotels(chunk, rng)
	_boardwalk(chunk, rng)
	_lifeguard_tower(chunk, Vector3(-26.0, 0.0, -70.0))


func _hotels(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var palette := [Color(0.95, 0.92, 0.82), Color(0.95, 0.66, 0.7), Color(0.6, 0.86, 0.76),
		Color(0.62, 0.78, 0.95), Color(0.98, 0.78, 0.55), Color(0.9, 0.88, 0.7), Color(0.78, 0.68, 0.92), Color(0.98, 0.9, 0.5)]
	var z := -WorldContext.CHUNK
	while z < 0.0:
		var w := rng.randf_range(14.0, 26.0)
		var d := rng.randf_range(16.0, 30.0)
		var floors := rng.randi_range(3, 11)
		if rng.randf() < 0.12:
			floors = rng.randi_range(20, 30)
		var fh := 3.1
		var h := floors * fh
		var x := -80.0 - rng.randf_range(0.0, 10.0) - d * 0.5
		var c: Color = palette[rng.randi() % palette.size()]
		var b := Node3D.new()
		b.position = Vector3(x, ctx.sand_height(x, z) - 0.5, z + w * 0.5)
		parent.add_child(b)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.albedo_texture = ctx.window_tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.28, 0.28, 0.28)
		mat.roughness = 0.9
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(d, h, w)
		m.mesh = bm
		m.material_override = mat
		m.position.y = h * 0.5
		b.add_child(m)
		# Balconies on the sea-facing side, one slab + rail per floor.
		var slab_c := c.darkened(0.12)
		var rail_c := Color(0.92, 0.92, 0.92)
		var has_balconies := rng.randf() < 0.75
		if has_balconies:
			var batch := MeshBatch.new()
			for f in range(1, floors):
				var y := f * fh
				batch.add_box_at(Vector3(1.6, 0.18, w * 0.86), slab_c, Vector3(d * 0.5 + 0.8, y, 0))
				batch.add_box_at(Vector3(0.06, 1.0, w * 0.86), rail_c, Vector3(d * 0.5 + 1.55, y + 0.55, 0))
				# balcony dividers every ~4 m
				var nd := int(w * 0.86 / 4.0)
				for k in range(1, nd):
					batch.add_box_at(Vector3(1.4, 1.0, 0.06), slab_c, Vector3(d * 0.5 + 0.8, y + 0.55, -w * 0.43 + k * (w * 0.86 / nd)))
			batch.instance(b, "Balconies")
		# Rounded corner tower on some buildings (art deco).
		if rng.randf() < 0.4:
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var cyl := cylinder(b, w * 0.22, w * 0.22, h + 2.0, c, Vector3(d * 0.5, (h + 2.0) * 0.5, side * w * 0.5), 16)
			cyl.material_override = mat
		# Stepped top and roof slab.
		var top := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(d * 0.6, fh * 1.5, w * 0.6)
		top.mesh = tm
		top.material_override = mat
		top.position.y = h + tm.size.y * 0.5
		b.add_child(top)
		box(b, Vector3(d + 0.6, 0.5, w + 0.6), c.darkened(0.15), Vector3(0, h + 0.25, 0))
		# Entrance awning and a sign.
		box(b, Vector3(3.0, 0.15, 6.0), Color(0.85, 0.2, 0.25) if rng.randf() < 0.5 else Color(0.2, 0.45, 0.7), Vector3(d * 0.5 + 1.5, 3.3, 0))
		box(b, Vector3(0.3, 1.2, w * 0.4), Color(0.95, 0.95, 0.9), Vector3(d * 0.5 + 0.2, h * 0.5, 0))
		z += w + rng.randf_range(2.0, 9.0)


func _boardwalk(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var bx := WorldContext.BOARDWALK_X
	var y := ctx.sand_height(bx, 0.0)
	box(parent, Vector3(8.0, 0.5, L), Color(0.72, 0.62, 0.5), Vector3(bx - 3.0, y + 0.25, -L * 0.5))
	box(parent, Vector3(0.4, 0.6, L), Color(0.85, 0.82, 0.75), Vector3(bx + 1.0, y + 0.3, -L * 0.5))
	# Railing along the sand edge and lamps every 14 m, all in one mesh.
	var batch := MeshBatch.new()
	var z := -L + 2.0
	var i := 0
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 10
	sm.rings = 5
	while z < 0.0:
		batch.add_box_at(Vector3(0.1, 1.1, 0.1), Color(0.3, 0.3, 0.32), Vector3(bx + 0.6, y + 1.05, z))
		if i % 4 == 0:
			batch.add_cylinder(0.07, 0.1, 5.0, Color(0.25, 0.27, 0.3), Transform3D(Basis.IDENTITY, Vector3(bx - 6.5, y + 3.0, z)))
			batch.add(sm, Transform3D(Basis.IDENTITY, Vector3(bx - 6.5, y + 5.7, z)), Color(0.98, 0.98, 0.9))
			batch.add_box_at(Vector3(0.5, 0.08, 1.8), Color(0.55, 0.4, 0.25), Vector3(bx - 5.2, y + 0.95, z + 4.0))
			batch.add_box_at(Vector3(0.08, 0.5, 1.8), Color(0.55, 0.4, 0.25), Vector3(bx - 4.95, y + 1.2, z + 4.0))
			batch.add_cylinder(0.3, 0.28, 0.9, Color(0.2, 0.4, 0.3), Transform3D(Basis.IDENTITY, Vector3(bx - 1.0, y + 0.95, z - 2.0)))
		z += 3.5
		i += 1
	batch.add_box_at(Vector3(0.06, 0.08, L), Color(0.3, 0.3, 0.32), Vector3(bx + 0.6, y + 1.55, -L * 0.5))
	batch.instance(parent, "BoardwalkFurniture")


func _lifeguard_tower(parent: Node3D, pos: Vector3) -> void:
	var t := Node3D.new()
	t.position = Vector3(pos.x, ctx.sand_height(pos.x, pos.z), pos.z)
	parent.add_child(t)
	var white := Color(0.95, 0.95, 0.92)
	var blue := Color(0.25, 0.55, 0.8)
	for dx in [-1.4, 1.4]:
		for dz in [-1.4, 1.4]:
			box(t, Vector3(0.25, 3.2, 0.25), white, Vector3(dx, 1.6, dz))
	box(t, Vector3(3.6, 0.2, 3.6), white, Vector3(0, 3.2, 0))
	box(t, Vector3(3.2, 2.4, 3.2), blue, Vector3(0, 4.5, 0))
	box(t, Vector3(3.2, 0.9, 3.2), white, Vector3(0, 5.6, 0))
	box(t, Vector3(4.2, 0.2, 4.2), Color(0.8, 0.2, 0.2), Vector3(0, 6.1, 0))
	var ramp := box(t, Vector3(1.2, 0.12, 5.0), white, Vector3(0, 1.6, 4.0))
	ramp.rotation.x = -0.6
	box(t, Vector3(0.08, 1.0, 3.6), white, Vector3(-1.7, 3.8, 0))
	box(t, Vector3(3.6, 1.0, 0.08), white, Vector3(0, 3.8, -1.7))
	# flag
	box(t, Vector3(0.05, 2.0, 0.05), white, Vector3(1.5, 7.1, 1.5))
	box(t, Vector3(0.02, 0.5, 0.8), Color(0.95, 0.85, 0.1), Vector3(1.5, 7.8, 1.1))

extends ChunkedLayer

# Beach furniture, normal density: dense-ish rows of white-framed loungers in
# red and yellow fabrics, striped umbrellas over most of them, some towels,
# and scattered clutter (buckets, coolers, balls, bags). Exposes `spots`
# so the crowd layer can seat people.

var panel_mats: Array[StandardMaterial3D] = []
var spots: Array = []   # per chunk: [{node, kind}] (kind: "lounger" | "towel")


func _init() -> void:
	seed_v = 5721


func build() -> void:
	# Striped umbrella panel sets: red/white and yellow/white stripes.
	var sets := [
		[Color(0.85, 0.15, 0.15), Color(0.96, 0.96, 0.94)],
		[Color(0.95, 0.8, 0.15), Color(0.96, 0.96, 0.94)],
		[Color(0.85, 0.15, 0.15), Color(0.95, 0.8, 0.15)],
		[Color(0.95, 0.8, 0.15), Color(0.96, 0.96, 0.94), Color(0.85, 0.15, 0.15)],
	]
	for cols in sets:
		var m := StandardMaterial3D.new()
		m.albedo_texture = _panel_tex(cols)
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		panel_mats.append(m)
	super.build()


func _panel_tex(cols: Array) -> ImageTexture:
	# 8 panels around the cone, cycling through the colour set (stripes)
	var img := Image.create(256, 8, false, Image.FORMAT_RGB8)
	for x in 256:
		var c: Color = cols[(x / 32) % cols.size()]
		if x % 32 < 2:
			c = c.darkened(0.3)   # seam
		for y in 8:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var chunk_spots: Array = []
	# White frames with red and yellow fabrics.
	var fabric: Array[Color] = [
		Color(0.85, 0.15, 0.15), Color(0.95, 0.8, 0.15),
		Color(0.9, 0.2, 0.2), Color(0.98, 0.85, 0.2),
	]
	var flat := MeshBatch.new()
	var panels: Array[MeshBatch] = []
	for m in panel_mats:
		panels.append(MeshBatch.new())
	# Rows parallel to the shore, thinning slightly toward the water, normal
	# density overall but packing tightly enough to feel dense.
	for row_x in [-13.0, -18.0, -23.0, -28.0, -34.0]:
		var occupancy := 0.72 if row_x < -20.0 else 0.55
		var z := -L + rng.randf_range(0.5, 2.0)
		while z < 0.0:
			if rng.randf() < occupancy:
				var x: float = row_x + rng.randf_range(-1.2, 1.2)
				var g := Node3D.new()
				g.position = Vector3(x, ctx.ground_height(x, z), z)
				g.rotation.y = rng.randf_range(-0.35, 0.35)
				chunk.add_child(g)
				var base := g.transform * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)  # faces the sea (+x)
				var spot := Node3D.new()
				spot.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
				g.add_child(spot)
				ctx.add_obstacle(g.global_position, 1.05)
				if rng.randf() < 0.82:
					_lounger(flat, base, fabric[rng.randi() % fabric.size()])
					chunk_spots.append({"node": spot, "kind": "lounger"})
					if rng.randf() < 0.75:
						_umbrella(flat, panels, g.transform, rng)
				else:
					var pi := rng.randi() % panels.size()
					panels[pi].add_box(Vector3(0.9, 0.03, 1.9), Color(1, 1, 1), base * Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)))
					chunk_spots.append({"node": spot, "kind": "towel"})
				if rng.randf() < 0.3:
					_clutter(flat, panels, g.transform, rng)
			z += rng.randf_range(2.2, 3.0)
	flat.instance(chunk, "Furniture", 0.75)
	for i in panels.size():
		if not panels[i].is_empty():
			var mi := MeshInstance3D.new()
			mi.name = "Panels%d" % i
			mi.mesh = panels[i].commit_with(panel_mats[i])
			chunk.add_child(mi)
	spots.append(chunk_spots)


func _lounger(batch: MeshBatch, base: Transform3D, fab: Color) -> void:
	var white := Color(0.96, 0.96, 0.96)
	var tilt := Basis.IDENTITY.rotated(Vector3.RIGHT, 0.85)
	batch.add_box(Vector3(0.66, 0.05, 1.3), fab, base * Transform3D(Basis.IDENTITY, Vector3(0, 0.38, 0.15)))
	batch.add_box(Vector3(0.66, 0.05, 0.75), fab, base * Transform3D(tilt, Vector3(0, 0.6, -0.78)))
	for dx in [-0.36, 0.36]:
		batch.add_box(Vector3(0.05, 0.07, 1.5), white, base * Transform3D(Basis.IDENTITY, Vector3(dx, 0.38, 0.1)))
		batch.add_box(Vector3(0.05, 0.07, 0.8), white, base * Transform3D(tilt, Vector3(dx, 0.62, -0.8)))
		for dz in [-0.6, 0.7]:
			batch.add_box(Vector3(0.05, 0.38, 0.05), white, base * Transform3D(Basis.IDENTITY, Vector3(dx, 0.19, dz)))
	batch.add_box(Vector3(0.7, 0.05, 0.05), white, base * Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0.7)))


func _umbrella(flat: MeshBatch, panels: Array[MeshBatch], base: Transform3D, rng: RandomNumberGenerator) -> void:
	var u := base * Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-1.8, -1.1)))
	flat.add_box(Vector3(0.06, 2.5, 0.06), Color(0.9, 0.9, 0.9), u * Transform3D(Basis.IDENTITY, Vector3(0, 1.25, 0)))
	var pi := rng.randi() % panels.size()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.7
	cm.height = 0.65
	cm.radial_segments = 16
	cm.cap_bottom = false
	var tilt := Basis.IDENTITY.rotated(Vector3.FORWARD, rng.randf_range(-0.1, 0.1))
	panels[pi].add(cm, u * Transform3D(tilt, Vector3(0, 2.45, 0)), Color(1, 1, 1))
	var vm := CylinderMesh.new()
	vm.top_radius = 1.7
	vm.bottom_radius = 1.75
	vm.height = 0.2
	vm.radial_segments = 16
	vm.cap_top = false
	vm.cap_bottom = false
	panels[pi].add(vm, u * Transform3D(tilt, Vector3(0, 2.02, 0)), Color(1, 1, 1))


func _clutter(flat: MeshBatch, panels: Array[MeshBatch], base: Transform3D, rng: RandomNumberGenerator) -> void:
	var r := rng.randf()
	var at := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(1.2, 1.8))
	if r < 0.3:
		var bc: Color = [Color(0.85, 0.15, 0.15), Color(0.95, 0.8, 0.15)][rng.randi() % 2]
		flat.add_cylinder(0.22, 0.18, 0.4, bc, base * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.2, 0)), 10)   # bucket
	elif r < 0.55:
		var cc: Color = [Color(0.9, 0.9, 0.9), Color(0.8, 0.2, 0.2), Color(0.95, 0.8, 0.15)][rng.randi() % 3]
		flat.add_box(Vector3(0.5, 0.4, 0.35), cc, base * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.2, 0)))   # cooler
	elif r < 0.78:
		var sm := SphereMesh.new()
		sm.radius = 0.24
		sm.height = 0.48
		sm.radial_segments = 12
		sm.rings = 6
		var rb := Basis.from_euler(Vector3(rng.randf(), rng.randf(), rng.randf()))
		panels[rng.randi() % panels.size()].add(sm, base * Transform3D(rb, Vector3(rng.randf_range(-1.5, 1.5), 0.24, rng.randf_range(-2.0, 2.0))), Color(1, 1, 1))
	elif r < 0.9:
		flat.add_box(Vector3(0.35, 0.3, 0.2), Color(0.9, 0.6, 0.15), base * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.15, 0)))   # bag
	else:
		var fc: Color = [Color(0.85, 0.15, 0.15), Color(0.95, 0.8, 0.15)][rng.randi() % 2]
		flat.add_box(Vector3(0.4, 0.05, 0.4), fc, base * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.025, 0)))   # flip-flops / mat scrap

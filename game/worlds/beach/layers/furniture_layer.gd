class_name FurnitureLayer
extends ChunkedLayer

# Beach furniture modelled on the reference: dense rows of white loungers with
# coloured fabric, large multi-panel umbrellas, towels, buckets, bags and
# balls. Exposes `spots` so the crowd layer can seat people.

var panel_mats: Array[StandardMaterial3D] = []
var spots: Array = []   # per chunk: [{node, kind}] (kind: "lounger" | "towel")


func _init() -> void:
	seed_v = 2468


func build() -> void:
	var sets := [[Color(0.95, 0.25, 0.5), Color(0.98, 0.85, 0.2), Color(0.3, 0.55, 0.9), Color(0.3, 0.75, 0.45)],
		[Color(0.2, 0.5, 0.9), Color(0.95, 0.95, 0.95)], [Color(0.1, 0.35, 0.75), Color(0.2, 0.6, 0.9)],
		[Color(0.95, 0.5, 0.2), Color(0.98, 0.9, 0.5), Color(0.95, 0.3, 0.35)], [Color(0.25, 0.7, 0.5), Color(0.95, 0.95, 0.9)]]
	for cols in sets:
		var m := StandardMaterial3D.new()
		m.albedo_texture = _panel_tex(cols)
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		panel_mats.append(m)
	super.build()


func _panel_tex(cols: Array) -> ImageTexture:
	# 8 panels around the cone, cycling through the colour set
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
	var chunk_spots := []
	var fabric := [Color(0.3, 0.55, 0.85), Color(0.2, 0.65, 0.6), Color(0.3, 0.7, 0.45), Color(0.95, 0.95, 0.92), Color(0.9, 0.3, 0.3)]
	# All static geometry of the chunk goes into a few batches: one for flat
	# colours, one per umbrella/towel panel material. Spots stay as empty Node3Ds.
	var flat := MeshBatch.new()
	var panels: Array[MeshBatch] = []
	for m in panel_mats:
		panels.append(MeshBatch.new())
	# Rows parallel to the shore, like the reference, thinning toward the water.
	for row_x in [-13.0, -18.0, -23.0, -28.0, -34.0]:
		var occupancy := 0.7 if row_x < -20.0 else 0.5
		var z := -L + rng.randf_range(0.5, 2.5)
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
				if rng.randf() < 0.8:
					_lounger(flat, base, fabric[rng.randi() % fabric.size()])
					chunk_spots.append({"node": spot, "kind": "lounger"})
				else:
					var pi := rng.randi() % panels.size()
					panels[pi].add_box(Vector3(0.9, 0.03, 1.9), Color(1, 1, 1), base * Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)))
					chunk_spots.append({"node": spot, "kind": "towel"})
				if rng.randf() < 0.28:
					_umbrella(flat, panels, g.transform, rng)
				if rng.randf() < 0.35:
					_clutter(flat, panels, g.transform, rng)
			z += rng.randf_range(2.8, 3.8)
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
	flat.add_box(Vector3(0.06, 2.5, 0.06), Color(0.85, 0.85, 0.85), u * Transform3D(Basis.IDENTITY, Vector3(0, 1.25, 0)))
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
	if r < 0.35:
		flat.add_cylinder(0.22, 0.18, 0.4, Color(0.95, 0.2, 0.6), base * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.2, 0)), 10)   # pink bucket
	elif r < 0.6:
		var cc: Color = [Color(0.2, 0.4, 0.8), Color(0.9, 0.9, 0.9), Color(0.8, 0.2, 0.2)][rng.randi() % 3]
		flat.add_box(Vector3(0.5, 0.4, 0.35), cc, base * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.2, 0)))   # cooler
	elif r < 0.8:
		var sm := SphereMesh.new()
		sm.radius = 0.24
		sm.height = 0.48
		sm.radial_segments = 12
		sm.rings = 6
		var rb := Basis.from_euler(Vector3(rng.randf(), rng.randf(), rng.randf()))
		panels[rng.randi() % panels.size()].add(sm, base * Transform3D(rb, Vector3(rng.randf_range(-1.5, 1.5), 0.24, rng.randf_range(-2.0, 2.0))), Color(1, 1, 1))
	else:
		flat.add_box(Vector3(0.35, 0.3, 0.2), Color(0.9, 0.6, 0.15), base * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.15, 0)))   # bag

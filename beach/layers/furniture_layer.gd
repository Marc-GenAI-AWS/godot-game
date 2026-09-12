class_name FurnitureLayer
extends ChunkedLayer

# Loungers, umbrellas, towels, beach balls, bags. Exposes `spots` so the
# crowd layer can seat people on the loungers/towels it made.

var stripe_mats: Array[StandardMaterial3D] = []
var spots: Array = []   # per chunk: [{node, kind}] (kind: "lounger" | "towel")


func _init() -> void:
	seed_v = 2468


func build() -> void:
	var stripes := [[Color(0.2, 0.5, 0.9), Color(1, 1, 1)], [Color(0.95, 0.3, 0.45), Color(1.0, 0.9, 0.3)],
		[Color(0.2, 0.7, 0.45), Color(1, 1, 1)], [Color(0.95, 0.5, 0.2), Color(0.98, 0.95, 0.9)],
		[Color(0.55, 0.3, 0.8), Color(0.95, 0.7, 0.85)], [Color(0.1, 0.2, 0.5), Color(0.9, 0.9, 0.9)]]
	for s in stripes:
		var m := StandardMaterial3D.new()
		m.albedo_texture = _stripe_tex(s[0], s[1])
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		stripe_mats.append(m)
	super.build()


func _stripe_tex(a: Color, b: Color) -> ImageTexture:
	var img := Image.create(256, 8, false, Image.FORMAT_RGB8)
	for x in 256:
		var c := a if (x / 32) % 2 == 0 else b
		for y in 8:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var chunk_spots := []
	var count := 34
	for i in count:
		var z := -L + (i + rng.randf_range(0.1, 0.9)) * (L / count)
		var x := rng.randf_range(-50.0, -14.0)
		var g := Node3D.new()
		g.position = Vector3(x, ctx.sand_height(x, z), z)
		g.rotation.y = rng.randf_range(-0.5, 0.5)
		chunk.add_child(g)
		if rng.randf() < 0.7:
			var lounger := _lounger(g, rng)
			chunk_spots.append({"node": lounger, "kind": "lounger"})
		else:
			var towel := _towel(g, rng)
			chunk_spots.append({"node": towel, "kind": "towel"})
		if rng.randf() < 0.55:
			_umbrella(g, rng)
		if rng.randf() < 0.3:
			var cols := [Color(0.9, 0.3, 0.7), Color(0.2, 0.6, 0.9), Color(0.95, 0.6, 0.1)]
			box(g, Vector3(0.4, 0.4, 0.3), cols[rng.randi() % cols.size()], Vector3(rng.randf_range(-1.0, 1.0), 0.2, rng.randf_range(1.2, 1.8)))
		if rng.randf() < 0.2:
			var ball := sphere(g, 0.25, Color(1, 1, 1), Vector3(rng.randf_range(-1.5, 1.5), 0.25, rng.randf_range(-2.0, 2.0)))
			ball.material_override = stripe_mats[rng.randi() % stripe_mats.size()]
			ball.rotation = Vector3(rng.randf(), rng.randf(), rng.randf())
	spots.append(chunk_spots)


func _lounger(g: Node3D, rng: RandomNumberGenerator) -> Node3D:
	var lounger := Node3D.new()
	lounger.rotation.y = -PI * 0.5   # faces the sea (+x)
	g.add_child(lounger)
	var white := Color(0.96, 0.96, 0.96)
	var slat := Color(0.35, 0.55, 0.85) if rng.randf() < 0.5 else Color(0.95, 0.95, 0.9)
	box(lounger, Vector3(0.7, 0.06, 1.4), slat, Vector3(0, 0.36, 0.1))
	box(lounger, Vector3(0.05, 0.08, 1.9), white, Vector3(-0.36, 0.36, 0.0))
	box(lounger, Vector3(0.05, 0.08, 1.9), white, Vector3(0.36, 0.36, 0.0))
	var back := box(lounger, Vector3(0.7, 0.06, 0.75), slat, Vector3(0, 0.55, -0.85))
	back.rotation.x = 0.9
	for dz in [-0.8, 0.8]:
		for dx in [-0.3, 0.3]:
			box(lounger, Vector3(0.05, 0.36, 0.05), white, Vector3(dx, 0.18, dz))
	return lounger


func _towel(g: Node3D, rng: RandomNumberGenerator) -> Node3D:
	var towel := Node3D.new()
	towel.rotation.y = -PI * 0.5
	g.add_child(towel)
	var t := box(towel, Vector3(0.9, 0.03, 1.9), Color(1, 1, 1), Vector3(0, 0.02, 0))
	t.material_override = stripe_mats[rng.randi() % stripe_mats.size()]
	t.rotation.y = PI * 0.5
	return towel


func _umbrella(g: Node3D, rng: RandomNumberGenerator) -> void:
	var u := Node3D.new()
	u.position = Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-1.6, -1.0))
	g.add_child(u)
	box(u, Vector3(0.06, 2.4, 0.06), Color(0.85, 0.85, 0.85), Vector3(0, 1.2, 0))
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.5
	cm.height = 0.55
	cm.radial_segments = 12
	cm.cap_bottom = false
	cone.mesh = cm
	cone.material_override = stripe_mats[rng.randi() % stripe_mats.size()]
	cone.position.y = 2.35
	cone.rotation.z = rng.randf_range(-0.12, 0.12)
	u.add_child(cone)

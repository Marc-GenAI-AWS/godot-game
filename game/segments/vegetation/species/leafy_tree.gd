class_name LeafyTree
extends RefCounted

# Broadleaf tree: tapered trunk with a few branches, and a canopy of
# alpha-cut leaf cards clustered into lobes. One draw call for wood, one for
# leaves (per tree), leaf card texture generated once.

static var _leaf_tex: ImageTexture
static var _leaf_mat: StandardMaterial3D


static func leaf_material() -> StandardMaterial3D:
	if _leaf_mat:
		return _leaf_mat
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# a cluster of overlapping leaf ellipses in a few greens
	var leaves := []
	for i in 14:
		leaves.append([Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8)) * w, rng.randf_range(0.1, 0.19) * w, rng.randf() * PI, Color(0.12, 0.35, 0.1).lerp(Color(0.35, 0.58, 0.18), rng.randf())])
	for y in h:
		for x in w:
			var best_a := 0.0
			var col := Color(0, 0, 0, 0)
			for lf in leaves:
				var c0: Vector2 = lf[0]
				var rad: float = lf[1]
				var ang: float = lf[2]
				var lc: Color = lf[3]
				var d: Vector2 = Vector2(x, y) - c0
				var c := cos(ang)
				var s := sin(ang)
				var lx: float = (d.x * c + d.y * s) / rad
				var ly: float = (-d.x * s + d.y * c) / (rad * 0.55)
				var r: float = lx * lx + ly * ly
				if r < 1.0 and best_a == 0.0:
					best_a = 1.0
					var vein: float = 0.82 if absf(ly) < 0.08 else 1.0
					var lit: float = 0.85 + 0.3 * (1.0 - r)
					col = Color(lc.r * vein * lit, lc.g * vein * lit, lc.b * vein, 1.0)
			img.set_pixel(x, y, col if best_a > 0.0 else Color(0, 0, 0, 0))
	_leaf_tex = ImageTexture.create_from_image(img)
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.albedo_texture = _leaf_tex
	_leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_leaf_mat.alpha_scissor_threshold = 0.5
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat.roughness = 0.85
	_leaf_mat.vertex_color_use_as_albedo = true
	return _leaf_mat


static func build(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, ctx: WorldContext, size := 1.0) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.rotation.y = rng.randf() * TAU
	parent.add_child(tree)
	ctx.add_obstacle(tree.global_position, 0.45)
	var h := rng.randf_range(5.5, 8.0) * size
	var wood := MeshBatch.new()
	var bark := Color(0.36, 0.28, 0.2)
	wood.add_cylinder(0.14 * size, 0.28 * size, h * 0.55, bark, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.275, 0)), 9)
	# branches: 4-6 tilted cylinders from the trunk top into the canopy
	var nb := rng.randi_range(4, 6)
	var probe := Node3D.new()
	for i in nb:
		var a := TAU * i / nb + rng.randf_range(-0.3, 0.3)
		var tilt := rng.randf_range(0.5, 0.9)
		var len := rng.randf_range(1.6, 2.6) * size
		var start := Vector3(0, h * 0.5, 0)
		var dir := Vector3(sin(a) * sin(tilt), cos(tilt), cos(a) * sin(tilt))
		probe.position = start + dir * len * 0.5
		probe.look_at_from_position(probe.position, probe.position + dir, Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.UP)
		probe.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05 * size
		cm.bottom_radius = 0.1 * size
		cm.height = len
		cm.radial_segments = 6
		wood.add(cm, probe.transform, bark.darkened(0.1))
	probe.free()
	wood.instance(tree, "Wood", 0.95)
	# canopy: lobes of leaf cards
	var leaves := MeshBatch.new()
	var card := QuadMesh.new()
	card.size = Vector2(1.7, 1.7) * size
	var lobes := rng.randi_range(5, 7)
	for lobe in lobes:
		var centre := Vector3(rng.randf_range(-1.8, 1.8), h * 0.62 + rng.randf_range(-0.6, 1.4), rng.randf_range(-1.8, 1.8)) * Vector3(size, 1.0, size)
		var lr := rng.randf_range(1.0, 1.7) * size
		var tint := Color(1, 1, 1).lerp(Color(0.75, 0.9, 0.7), rng.randf())
		for i in 9:
			var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.8), rng.randf_range(-1, 1)).normalized() * lr * rng.randf_range(0.3, 1.0)
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)))
			var shade := 0.7 + 0.35 * clampf((off.y / lr) * 0.5 + 0.6, 0.0, 1.0)
			leaves.add(card, Transform3D(b, centre + off), tint * shade)
	var lmi := MeshInstance3D.new()
	lmi.mesh = leaves.commit_with(leaf_material())
	tree.add_child(lmi)

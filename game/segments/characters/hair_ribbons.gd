class_name HairRibbons
extends RefCounted

# Builds flat overlapping hair ribbons hanging from around the back of a head.
# Used by the procedural rig and to extend a skinned model's hairstyle.
# Convention: +Z is behind the head, ribbons hang down -Y.

static func build(upper_pivot: Node3D, lower_pivot: Node3D, mat: Material, count: int, segs: int, width: float, radius := 0.108, root_y := -0.05, seed_v := 5, a_min := 0.1, a_max := PI - 0.1, front_strands := true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in count:
		var t := float(i) / (count - 1)
		var a := lerpf(a_min, a_max, t)
		var row := i % 2
		var ry := root_y - row * 0.05
		var r := radius - row * 0.012
		var root := Vector3(cos(a) * r, ry, sin(a) * r * 1.1 + 0.01)
		var outward := Vector3(cos(a), 0, sin(a))
		var tangent := Vector3(-sin(a), 0, cos(a))
		var wob := rng.randf_range(-0.012, 0.012)
		var w := width * rng.randf_range(0.85, 1.15)
		var front := front_strands and (i < 2 or i > count - 3)
		var mid := Vector3(root.x * 0.8 + wob, -0.2, 0.065 + maxf(root.z - 0.02, 0.0) * 0.5)
		if front:
			mid = Vector3(root.x * 1.25 + wob, -0.19, -0.04)
		var upper_pts := [root, root + outward * 0.012 + Vector3(0, -0.06, 0.005), (root + mid) * 0.5 + Vector3(0, 0, 0.015), mid]
		var upper_r := [Vector2(w * 0.8, 0.012), Vector2(w, 0.012), Vector2(w, 0.011), Vector2(w * 0.95, 0.01)]
		var seed_c := Color(rng.randf(), 0, 0)
		_add(upper_pivot, BodyMesh.tube(upper_pts, upper_r, segs, tangent, seed_c), mat)
		var m2 := mid - lower_pivot.position
		var tip_len := rng.randf_range(0.2, 0.3)
		var lower_pts := [m2, m2 + Vector3(-m2.x * 0.1, -tip_len * 0.5, 0.008), m2 + Vector3(-m2.x * 0.25, -tip_len, 0.0)]
		if front:
			lower_pts = [m2, m2 + Vector3(-m2.x * 0.15, -tip_len * 0.5, -0.03), m2 + Vector3(-m2.x * 0.3, -tip_len * 0.9, -0.05)]
		var lower_r := [Vector2(w * 0.95, 0.01), Vector2(w * 0.85, 0.009), Vector2(w * 0.4, 0.005)]
		_add(lower_pivot, BodyMesh.tube(lower_pts, lower_r, segs, tangent, seed_c), mat)


static func _add(parent: Node3D, mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)


static func strand_material(color: Color) -> ShaderMaterial:
	var hm := ShaderMaterial.new()
	hm.shader = load("res://segments/characters/shaders/hair.gdshader")
	hm.set_shader_parameter("strand_tex", BodyMesh.hair_strand_texture())
	hm.set_shader_parameter("base_color", color)
	hm.set_shader_parameter("tip_color", color.lightened(0.3))
	return hm

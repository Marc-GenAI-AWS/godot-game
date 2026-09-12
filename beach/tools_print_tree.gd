extends SceneTree

func _init() -> void:
	for path in ["res://characters/mpfb/mpfb_player.glb", "res://characters/assets/ual_walk.glb", "res://characters/assets/Superhero_Female_FullBody.gltf", "res://characters/assets/Hair_Long.gltf"]:
		var ps: PackedScene = load(path)
		if ps == null:
			print("FAILED ", path)
			continue
		var n := ps.instantiate()
		print("=== ", path)
		_dump(n, 0)
		n.free()
	quit()

func _dump(n: Node, depth: int) -> void:
	var extra := ""
	if n is Skeleton3D:
		var names := []
		for i in mini(8, n.get_bone_count()):
			names.append(n.get_bone_name(i))
		extra = " bones=%d first=%s" % [n.get_bone_count(), names]
	elif n is MeshInstance3D:
		extra = " mesh=%s surfaces=%d skeleton=%s" % [n.mesh.resource_name if n.mesh else "-", n.mesh.get_surface_count() if n.mesh else 0, n.skeleton]
		for i in (n.mesh.get_surface_count() if n.mesh else 0):
			var m = n.mesh.surface_get_material(i)
			extra += " mat%d=%s" % [i, m.resource_name if m else "null"]
	elif n is AnimationPlayer:
		extra = " anims=%s" % [n.get_animation_list()]
		for a in n.get_animation_list():
			var anim: Animation = n.get_animation(a)
			if anim.get_track_count() > 0:
				extra += " | %s: len=%.2f tracks=%d first=%s" % [a, anim.length, anim.get_track_count(), anim.track_get_path(0)]
	print("  ".repeat(depth), n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_dump(c, depth + 1)

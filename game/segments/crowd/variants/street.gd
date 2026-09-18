class_name StreetCrowd
extends ChunkedLayer

# Pedestrians on the sidewalks: live strollers in casual clothes with the
# same gait variety as the beach, plus a few standing/talking people.

var walkers: Array = []
var _batches := {}


func _init() -> void:
	seed_v = 6161


func _pick(arr: Array, rng: RandomNumberGenerator):
	return arr[rng.randi() % arr.size()]


func _person(rng: RandomNumberGenerator) -> Dictionary:
	var sex := "F" if rng.randf() < 0.5 else "M"
	var spec: Dictionary = SkinnedPeople.BODIES[sex]
	var casual: Array = SkinnedPeople.CASUAL_OUTFITS[sex]
	return {"sex": sex, "hair": _pick(spec["hairs"].keys(), rng), "outfit": _pick(casual, rng),
		"skin": _pick(SkinnedPeople.SKIN_TINTS, rng), "hair_tint": _pick(SkinnedPeople.HAIR_TINTS, rng),
		"body": SkinnedPeople.pick_body_type(rng)}


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	_batches = {}
	# standing people (baked)
	for i in 4:
		var p := _person(rng)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * (sc.ROAD_HALF + 1.0 + rng.randf_range(0.3, 1.8))
		var z := rng.randf_range(-L, 0.0)
		var baked := SkinnedPeople.bake(p["sex"], p["hair"], "Idle_Talking" if rng.randf() < 0.5 else "Idle", rng.randf_range(0.0, 2.0), self, {}, p["body"])
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, sc.KERB_H, z))
		_batch_for(p["outfit"]).add(baked["body"], xf, p["skin"])
		if baked["eyes"]:
			_batch_for("eyes").add(baked["eyes"], xf, Color(1, 1, 1))
		var htex := SkinnedPeople.hair_tex_for(p["hair"])
		for k in ["brows", "hair"]:
			if baked[k]:
				_batch_for(htex).add(baked[k], xf, p["hair_tint"])
		ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, z), 0.45)
	for key in _batches:
		var mat: Material = SkinnedPeople.eye_material() if key == "eyes" else (SkinnedPeople.hair_material(key) if key.begins_with("T_Hair") else SkinnedPeople.outfit_material(key))
		var mi := MeshInstance3D.new()
		mi.mesh = _batches[key].commit_with(mat)
		chunk.add_child(mi)
	# strollers on both sidewalks
	for i in 6:
		var p := _person(rng)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * (sc.ROAD_HALF + 0.9 + rng.randf_range(0.4, 2.0))
		var z := rng.randf_range(-L, 0.0)
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		var root := SkinnedPeople.animated(p["sex"], p["hair"], p["outfit"], p["skin"], p["hair_tint"], p["body"])
		root.position = Vector3(x, sc.KERB_H, z)
		root.rotation.y = 0.0 if dir < 0 else PI
		chunk.add_child(root)
		SkinnedPeople.apply_bone_scales(root.get_meta("skeleton"), p["body"])
		var ap: AnimationPlayer = root.get_meta("anim")
		var cad := rng.randf_range(0.85, 1.15)
		ap.play("Walk" if rng.randf() < 0.75 else "Walk_Formal")
		ap.seek(rng.randf_range(0.0, 1.3), true)
		ap.speed_scale = cad
		walkers.append({"root": root, "speed": 0.975 * cad, "dir": dir, "skel": root.get_meta("skeleton"), "body": p["body"]})


func _batch_for(key: String) -> MeshBatch:
	if not _batches.has(key):
		_batches[key] = MeshBatch.new()
	return _batches[key]


const LIVE_RADIUS := 105.0   # past this a stroller keeps walking but is not posed or drawn


func tick(delta: float) -> void:
	for w in walkers:
		var root: Node3D = w["root"]
		root.position.z = wrap_local_z(root.position.z + w["dir"] * w["speed"] * delta)
		ctx.dynamic_obstacles.append([root.global_position, 0.42])
		var ap: AnimationPlayer = root.get_meta("anim") if root.has_meta("anim") else null
		if ctx.player != null and not WorldContext.pose_if_near(root, ap, ctx.player.global_position, LIVE_RADIUS):
			continue
		SkinnedPeople.apply_bone_scales(w["skel"], w["body"])

class_name CrowdLayer
extends ChunkedLayer

# Everyone who isn't the player, on the same rigged bodies and animation
# library as the player. Strollers are live skinned characters with
# staggered walk cycles; sunbathers, sitters, waders and swimmers are posed
# from clips, skinned once on the CPU, and batched per material.

var furniture: FurnitureLayer
var walkers: Array = []     # [root, speed, dir, anim]
var swimmers: Array = []    # [node, base_y, phase]
var _batches := {}          # chunk-local: material key -> MeshBatch


func _init() -> void:
	seed_v = 9876


func _pick(arr: Array, rng: RandomNumberGenerator):
	return arr[rng.randi() % arr.size()]


func _person(rng: RandomNumberGenerator) -> Dictionary:
	var sex := "F" if rng.randf() < 0.6 else "M"
	var spec: Dictionary = SkinnedPeople.BODIES[sex]
	var hairs: Array = spec["hairs"].keys()
	return {"sex": sex, "hair": _pick(hairs, rng), "outfit": _pick(spec["outfits"], rng),
		"skin": _pick(SkinnedPeople.SKIN_TINTS, rng), "hair_tint": _pick(SkinnedPeople.HAIR_TINTS, rng)}


func _add_baked(p: Dictionary, clip: String, t: float, xform: Transform3D) -> void:
	var baked := SkinnedPeople.bake(p["sex"], p["hair"], clip, t, self)
	_batch_for(p["outfit"]).add(baked["body"], xform, p["skin"])
	if baked["eyes"]:
		_batch_for("eyes").add(baked["eyes"], xform, Color(1, 1, 1))
	var htex := SkinnedPeople.hair_tex_for(p["hair"])
	if baked["brows"]:
		_batch_for(htex).add(baked["brows"], xform, p["hair_tint"])
	if baked["hair"]:
		_batch_for(htex).add(baked["hair"], xform, p["hair_tint"])


func _batch_for(key: String) -> MeshBatch:
	if not _batches.has(key):
		_batches[key] = MeshBatch.new()
	return _batches[key]


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var ci := chunks.size() - 1
	_batches = {}
	var inv := chunk.global_transform.affine_inverse()
	# A small library of pose times so batched people don't all match.
	var lie_ts := [0.3, 0.9, 1.6]
	var sit_ts := [0.2, 1.1, 2.0]
	var idle_ts := [0.0, 0.8, 1.7]
	# Sunbathers / sitters on furniture spots
	if furniture and ci < furniture.spots.size():
		for spot in furniture.spots[ci]:
			if rng.randf() > 0.6:
				continue
			var p := _person(rng)
			var node: Node3D = spot["node"]
			var base: Transform3D = inv * node.global_transform
			if spot["kind"] == "lounger":
				# lie on the back, head at the backrest: face the body +Z first, then tip it over
				var lie := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI).rotated(Vector3.RIGHT, -PI * 0.5 + 0.34), Vector3(0, 0.44, 0.9))
				_add_baked(p, "Idle", _pick(lie_ts, rng), base * lie)
			else:
				if rng.randf() < 0.5:
					var lie := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI).rotated(Vector3.RIGHT, -PI * 0.5 + 0.05), Vector3(0, 0.08, 0.9))
					_add_baked(p, "Idle", _pick(lie_ts, rng), base * lie)
				else:
					_add_baked(p, "Sitting_Idle", _pick(sit_ts, rng), base * Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0.2)))
	# Waders standing in the shallows, talking
	for i in 8:
		var p := _person(rng)
		var wx := rng.randf_range(3.0, 9.0)
		var wz := rng.randf_range(-L, 0.0)
		var yaw := rng.randf_range(-0.6, 0.6) + PI * 0.5
		var clip := "Idle_Talking" if rng.randf() < 0.5 else "Idle"
		_add_baked(p, clip, _pick(idle_ts, rng), Transform3D(Basis(Vector3.UP, yaw), Vector3(wx, ctx.sand_height(wx, wz), wz)))
	# Swimmers bobbing further out (posed, moved as a node)
	for i in 6:
		var p := _person(rng)
		var wx := rng.randf_range(14.0, 26.0)
		var wz := rng.randf_range(-L, 0.0)
		var sw := Node3D.new()
		sw.position = Vector3(wx, -1.15, wz)
		sw.rotation.y = rng.randf() * TAU
		chunk.add_child(sw)
		var b := MeshBatch.new()
		var baked := SkinnedPeople.bake(p["sex"], p["hair"], "Swim_Idle", _pick(idle_ts, rng), self)
		b.add(baked["body"], Transform3D.IDENTITY, p["skin"])
		var mi := MeshInstance3D.new()
		mi.mesh = b.commit_with(SkinnedPeople.outfit_material(p["outfit"]))
		sw.add_child(mi)
		if baked["hair"]:
			var hb := MeshBatch.new()
			hb.add(baked["hair"], Transform3D.IDENTITY, p["hair_tint"])
			var hmi := MeshInstance3D.new()
			hmi.mesh = hb.commit_with(SkinnedPeople.hair_material(SkinnedPeople.hair_tex_for(p["hair"])))
			sw.add_child(hmi)
		swimmers.append([sw, -1.15, rng.randf() * TAU])
	# Commit the static batches
	for key in _batches:
		var mat: Material
		if key == "eyes":
			mat = SkinnedPeople.eye_material()
		elif key.begins_with("T_Hair"):
			mat = SkinnedPeople.hair_material(key)
		else:
			mat = SkinnedPeople.outfit_material(key)
		var mi := MeshInstance3D.new()
		mi.name = "People_" + key
		mi.mesh = _batches[key].commit_with(mat)
		chunk.add_child(mi)
	# Strollers along the waterline: live characters, staggered cycles
	for i in 7:
		var pair := rng.randf() < 0.35
		var x := rng.randf_range(-12.0, -1.0)
		var z := rng.randf_range(-L, 0.0)
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		var speed := rng.randf_range(1.0, 1.5)
		for k in (2 if pair else 1):
			var p := _person(rng)
			var root := SkinnedPeople.animated(p["sex"], p["hair"], p["outfit"], p["skin"], p["hair_tint"])
			var xx := x + k * 0.8
			root.position = Vector3(xx, ctx.sand_height(xx, z), z)
			root.rotation.y = 0.0 if dir < 0 else PI
			chunk.add_child(root)
			var ap: AnimationPlayer = root.get_meta("anim")
			ap.play("Walk")
			ap.seek(rng.randf_range(0.0, 1.3), true)
			ap.speed_scale = speed / 0.975
			walkers.append([root, speed, dir])


func tick(delta: float) -> void:
	for w in walkers:
		var root: Node3D = w[0]
		root.position.z = wrap_local_z(root.position.z + w[2] * w[1] * delta)
		root.position.y = ctx.sand_height(root.position.x, root.position.z)
	for s in swimmers:
		var sw: Node3D = s[0]
		sw.position.y = s[1] + ctx.sea_level() + 0.12 * sin(ctx.time * 1.3 + s[2])

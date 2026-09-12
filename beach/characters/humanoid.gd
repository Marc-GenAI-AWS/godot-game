class_name Humanoid
extends Node3D

# A stylised low-poly person built from primitives, with a procedural walk
# cycle. Root sits at the feet, facing -Z.

var hips: Node3D
var chest: Node3D
var head_pivot: Node3D
var l_hip: Node3D
var r_hip: Node3D
var l_knee: Node3D
var r_knee: Node3D
var l_shoulder: Node3D
var r_shoulder: Node3D
var l_elbow: Node3D
var r_elbow: Node3D
var hair_pivot: Node3D
var phase := 0.0
var base_height := 0.95

static var _mat_cache := {}


static func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := "%s_%s" % [c.to_html(), rough]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mat_cache[key] = m
	return m


func _capsule(parent: Node3D, length: float, radius: float, c: Color, y_offset := 0.0) -> MeshInstance3D:
	# Capsule hanging downward from the parent pivot (limbs).
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = length + radius * 2.0
	cm.radial_segments = 10
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = _mat(c)
	mi.position.y = -length * 0.5 + y_offset
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, c: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


func build(skin: Color, top: Color, bottom: Color, hair: Color, long_hair: bool, scale_f := 1.0) -> void:
	scale = Vector3.ONE * scale_f
	hips = _pivot(self, Vector3(0, base_height, 0))
	# Pelvis / shorts
	_box(hips, Vector3(0.34, 0.2, 0.22), bottom, Vector3(0, -0.02, 0))
	# Waist (bare midriff) and chest (top)
	_box(hips, Vector3(0.28, 0.16, 0.18), skin, Vector3(0, 0.16, 0))
	chest = _pivot(hips, Vector3(0, 0.24, 0))
	_box(chest, Vector3(0.34, 0.26, 0.2), top, Vector3(0, 0.13, 0))
	# Neck + head
	head_pivot = _pivot(chest, Vector3(0, 0.27, 0))
	_capsule(head_pivot, 0.06, 0.05, skin, 0.06)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.115
	sm.height = 0.25
	sm.radial_segments = 14
	sm.rings = 8
	head.mesh = sm
	head.material_override = _mat(skin)
	head.position = Vector3(0, 0.19, 0)
	head_pivot.add_child(head)
	# Hair cap plus optional long hair down the back
	var cap := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 0.125
	cs.height = 0.2
	cs.is_hemisphere = true
	cap.mesh = cs
	cap.material_override = _mat(hair, 0.7)
	cap.position = Vector3(0, 0.2, -0.01)
	head_pivot.add_child(cap)
	hair_pivot = _pivot(head_pivot, Vector3(0, 0.22, -0.09))
	if long_hair:
		var hb := MeshInstance3D.new()
		var hm := CapsuleMesh.new()
		hm.radius = 0.09
		hm.height = 0.5
		hm.radial_segments = 10
		hb.mesh = hm
		hb.material_override = _mat(hair, 0.7)
		hb.position = Vector3(0, -0.18, -0.02)
		hb.scale = Vector3(1.4, 1.0, 0.6)
		hair_pivot.add_child(hb)
	# Arms
	l_shoulder = _pivot(chest, Vector3(-0.22, 0.22, 0))
	r_shoulder = _pivot(chest, Vector3(0.22, 0.22, 0))
	for sh in [l_shoulder, r_shoulder]:
		var ball := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.06
		bs.height = 0.12
		bs.radial_segments = 10
		bs.rings = 5
		ball.mesh = bs
		ball.material_override = _mat(skin)
		sh.add_child(ball)
	_capsule(l_shoulder, 0.28, 0.05, skin)
	_capsule(r_shoulder, 0.28, 0.05, skin)
	l_elbow = _pivot(l_shoulder, Vector3(0, -0.28, 0))
	r_elbow = _pivot(r_shoulder, Vector3(0, -0.28, 0))
	_capsule(l_elbow, 0.26, 0.045, skin)
	_capsule(r_elbow, 0.26, 0.045, skin)
	# Legs
	l_hip = _pivot(hips, Vector3(-0.1, -0.08, 0))
	r_hip = _pivot(hips, Vector3(0.1, -0.08, 0))
	_capsule(l_hip, 0.42, 0.075, skin)
	_capsule(r_hip, 0.42, 0.075, skin)
	# short leg of the shorts
	_capsule(l_hip, 0.1, 0.085, bottom, 0.0)
	_capsule(r_hip, 0.1, 0.085, bottom, 0.0)
	l_knee = _pivot(l_hip, Vector3(0, -0.42, 0))
	r_knee = _pivot(r_hip, Vector3(0, -0.42, 0))
	_capsule(l_knee, 0.4, 0.06, skin)
	_capsule(r_knee, 0.4, 0.06, skin)
	_box(l_knee, Vector3(0.1, 0.05, 0.22), skin, Vector3(0, -0.43, -0.05))
	_box(r_knee, Vector3(0.1, 0.05, 0.22), skin, Vector3(0, -0.43, -0.05))


func pose_walk(delta: float, speed: float) -> void:
	phase += delta * speed * 4.2
	var p := phase
	var s := sin(p)
	# Legs: thigh swings, knee bends as the leg comes forward.
	l_hip.rotation.x = 0.55 * s
	r_hip.rotation.x = -0.55 * s
	l_knee.rotation.x = -0.9 * maxf(0.0, sin(p + 1.4)) * 0.6 - 0.05
	r_knee.rotation.x = -0.9 * maxf(0.0, sin(p + PI + 1.4)) * 0.6 - 0.05
	# Arms swing opposite the legs, elbows slightly bent.
	l_shoulder.rotation.x = -0.6 * s
	r_shoulder.rotation.x = 0.6 * s
	l_shoulder.rotation.z = 0.12
	r_shoulder.rotation.z = -0.12
	l_elbow.rotation.x = -0.35
	r_elbow.rotation.x = -0.35
	# Bob, hip sway and a little counter-rotation of the chest.
	hips.position.y = base_height + 0.035 * absf(cos(p))
	hips.rotation.z = 0.05 * s
	hips.rotation.y = 0.08 * s
	chest.rotation.y = -0.12 * s
	chest.rotation.x = 0.06
	if hair_pivot:
		hair_pivot.rotation.x = 0.05 * sin(p * 2.0) + 0.04
		hair_pivot.rotation.z = 0.06 * s


func pose_idle() -> void:
	l_shoulder.rotation.z = 0.15
	r_shoulder.rotation.z = -0.15
	l_elbow.rotation.x = -0.2
	r_elbow.rotation.x = -0.2


func pose_sit() -> void:
	# Sitting on the sand, knees up, leaning back on the hands.
	hips.position.y = 0.32
	rotation.x = 0.0
	chest.rotation.x = -0.25
	l_hip.rotation.x = 1.35
	r_hip.rotation.x = 1.35
	l_hip.rotation.z = 0.12
	r_hip.rotation.z = -0.12
	l_knee.rotation.x = -1.9
	r_knee.rotation.x = -1.9
	l_shoulder.rotation.x = 0.9
	r_shoulder.rotation.x = 0.9
	l_shoulder.rotation.z = 0.35
	r_shoulder.rotation.z = -0.35
	l_elbow.rotation.x = -0.15
	r_elbow.rotation.x = -0.15
	head_pivot.rotation.x = 0.15


func pose_lying() -> void:
	# Sunbathing on a lounger: rotate the whole body onto its back.
	rotation.x = -PI * 0.5 + 0.28
	hips.position.y = base_height
	l_shoulder.rotation.z = 0.35
	r_shoulder.rotation.z = -0.35
	l_shoulder.rotation.x = 0.25
	r_shoulder.rotation.x = 0.25
	l_elbow.rotation.x = -0.6
	r_elbow.rotation.x = -0.6
	l_knee.rotation.x = -0.35
	r_knee.rotation.x = -0.35
	l_hip.rotation.x = 0.15
	r_hip.rotation.x = 0.15
	l_hip.rotation.z = 0.06
	r_hip.rotation.z = -0.06
	if hair_pivot:
		hair_pivot.rotation.x = -0.9


func _rel_xform(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != self and n != null:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func bake_static() -> void:
	# Collapse the posed rig into a single mesh (one draw call). Call after
	# the final pose; the figure can no longer animate afterwards.
	var batch := MeshBatch.new()
	var parts: Array[MeshInstance3D] = []
	_collect_meshes(self, parts)
	for mi in parts:
		var c := Color(1, 1, 1)
		if mi.material_override is StandardMaterial3D:
			c = (mi.material_override as StandardMaterial3D).albedo_color
		batch.add(mi.mesh, _rel_xform(mi), c)
	for child in get_children():
		child.queue_free()
	batch.instance(self, "Baked")


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)

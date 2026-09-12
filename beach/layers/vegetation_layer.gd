class_name VegetationLayer
extends ChunkedLayer

# Palms (curved trunks, alpha-cut serrated fronds that sway) and hedges.

var frond_mesh: ArrayMesh
var crowns: Array[Node3D] = []


func _init() -> void:
	seed_v = 4321


func build() -> void:
	frond_mesh = _make_frond_mesh()
	super.build()


func _make_frond_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 7
	for i in segs + 1:
		var t := float(i) / segs
		var ang := 0.35 - t * t * 1.25
		var x := t * 2.8
		var y := sin(ang) * t * 2.8 * 0.6 + t * 0.3 - t * t * 1.2
		var w := 0.42
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(t, 0))
		st.add_vertex(Vector3(x, y, -w))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(t, 1))
		st.add_vertex(Vector3(x, y, w))
	for i in segs:
		var a := i * 2
		st.add_index(a); st.add_index(a + 1); st.add_index(a + 2)
		st.add_index(a + 1); st.add_index(a + 3); st.add_index(a + 2)
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ctx.frond_tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	m.surface_set_material(0, mat)
	return m


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var z := -L + rng.randf_range(0.0, 8.0)
	while z < 0.0:
		var x := WorldContext.BOARDWALK_X + 4.0 + rng.randf_range(-2.0, 3.0)
		_palm(chunk, Vector3(x, ctx.sand_height(x, z) - 0.2, z), rng)
		z += rng.randf_range(9.0, 16.0)
	for i in 4:
		var x := rng.randf_range(-54.0, -40.0)
		var zz := rng.randf_range(-L, 0.0)
		_palm(chunk, Vector3(x, ctx.sand_height(x, zz) - 0.2, zz), rng)
	# Hedges along the boardwalk's landward side.
	var hedges := MeshBatch.new()
	var hz := -L
	while hz < 0.0:
		var len := rng.randf_range(6.0, 14.0)
		var hx := WorldContext.BOARDWALK_X - 7.6
		hedges.add_box_at(Vector3(1.2, 1.0, len), Color(0.15, 0.4, 0.17), Vector3(hx, ctx.sand_height(hx, hz) + 0.9, hz + len * 0.5))
		hz += len + rng.randf_range(3.0, 10.0)
	hedges.instance(chunk, "Hedges", 0.95)


func _palm(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var palm := Node3D.new()
	palm.position = pos
	palm.rotation.y = rng.randf() * TAU
	parent.add_child(palm)
	var height := rng.randf_range(7.0, 12.0)
	var segs := 7
	var lean := Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
	var p := Vector3.ZERO
	var trunk := MeshBatch.new()
	var probe := Node3D.new()
	for i in segs:
		var t := float(i) / segs
		var seg_len := height / segs
		var next := p + Vector3(lean.x * (0.5 + t) * seg_len, seg_len, lean.y * (0.5 + t) * seg_len)
		var cm := CylinderMesh.new()
		cm.top_radius = lerpf(0.26, 0.15, t + 0.15)
		cm.bottom_radius = lerpf(0.3, 0.17, t)
		cm.height = seg_len + 0.15
		cm.radial_segments = 8
		probe.position = (p + next) * 0.5
		probe.look_at_from_position(probe.position, probe.position + (next - p).normalized(), Vector3.RIGHT)
		probe.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		trunk.add(cm, probe.transform, Color(0.5, 0.42, 0.3).lightened(0.15 * sin(i * 1.7)))
		p = next
	probe.free()
	trunk.instance(palm, "Trunk", 0.95)
	var crown := Node3D.new()
	crown.position = p
	palm.add_child(crown)
	crowns.append(crown)
	# All fronds of a crown merged into one alpha-cut mesh.
	var fronds := MeshBatch.new()
	var n := 10 + rng.randi() % 5
	for i in n:
		var b := Basis.IDENTITY.rotated(Vector3.FORWARD, rng.randf_range(-0.2, 0.3)).rotated(Vector3.UP, TAU * i / n + rng.randf_range(-0.2, 0.2))
		b = b.scaled(Vector3.ONE * rng.randf_range(0.9, 1.25))
		fronds.add(frond_mesh, Transform3D(b, Vector3.ZERO), Color(1, 1, 1))
	var fm := MeshInstance3D.new()
	fm.mesh = fronds.commit_with(frond_mesh.surface_get_material(0))
	crown.add_child(fm)
	var nuts := MeshBatch.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sm.radial_segments = 8
	sm.rings = 4
	for i in 4:
		nuts.add(sm, Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-0.25, 0.25), -0.25, rng.randf_range(-0.25, 0.25))), Color(0.35, 0.28, 0.15))
	nuts.instance(crown, "Coconuts")


func tick(_delta: float) -> void:
	var t := ctx.time
	for i in crowns.size():
		var c := crowns[i]
		c.rotation.x = 0.045 * sin(t * 0.9 + i * 1.3)
		c.rotation.z = 0.055 * sin(t * 0.7 + i * 0.7) + 0.03

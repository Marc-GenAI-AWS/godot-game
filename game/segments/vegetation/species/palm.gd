class_name Palm
extends RefCounted

# Shared palm generator (used by the beach and street vegetation variants).
# build() returns the crown node so the caller can sway it.

static var _frond_cache := {}

static func frond_mesh(ctx: WorldContext) -> ArrayMesh:
	if _frond_cache.has(ctx):
		return _frond_cache[ctx]
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
	_frond_cache[ctx] = m
	return m


static func build(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, ctx: WorldContext, tall := false) -> Node3D:
	var palm := Node3D.new()
	palm.position = pos
	palm.rotation.y = rng.randf() * TAU
	parent.add_child(palm)
	ctx.add_obstacle(palm.global_position, 0.45)
	var height := rng.randf_range(13.0, 18.0) if tall else rng.randf_range(7.0, 11.0)
	var segs := 7
	var lean := Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04)) if tall else Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
	var r_top := 0.16 if tall else 0.26
	var r_bot := 0.22 if tall else 0.3
	var p := Vector3.ZERO
	var trunk := MeshBatch.new()
	var probe := Node3D.new()
	for i in segs:
		var t := float(i) / segs
		var seg_len := height / segs
		var next := p + Vector3(lean.x * (0.5 + t) * seg_len, seg_len, lean.y * (0.5 + t) * seg_len)
		var cm := CylinderMesh.new()
		cm.top_radius = lerpf(r_top, r_top * 0.75, t + 0.15)
		cm.bottom_radius = lerpf(r_bot, r_top * 0.8, t)
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
	var fm_src := frond_mesh(ctx)
	var fronds := MeshBatch.new()
	var n := (9 + rng.randi() % 3) if tall else (10 + rng.randi() % 5)
	for i in n:
		var b := Basis.IDENTITY.rotated(Vector3.FORWARD, rng.randf_range(-0.2, 0.3)).rotated(Vector3.UP, TAU * i / n + rng.randf_range(-0.2, 0.2))
		b = b.scaled(Vector3.ONE * (rng.randf_range(0.7, 0.9) if tall else rng.randf_range(0.9, 1.25)))
		fronds.add(fm_src, Transform3D(b, Vector3.ZERO), Color(1, 1, 1))
	var fm := MeshInstance3D.new()
	fm.mesh = fronds.commit_with(fm_src.surface_get_material(0))
	crown.add_child(fm)
	if tall:
		var shag := CylinderMesh.new()
		shag.top_radius = 0.28
		shag.bottom_radius = 0.9
		shag.height = 1.6
		shag.radial_segments = 10
		var sh := MeshInstance3D.new()
		sh.mesh = shag
		sh.material_override = ctx.mat(Color(0.45, 0.36, 0.2), 0.95)
		sh.position.y = -1.0
		crown.add_child(sh)
	else:
		var nuts := MeshBatch.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.28
		sm.radial_segments = 8
		sm.rings = 4
		for i in 4:
			nuts.add(sm, Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-0.25, 0.25), -0.25, rng.randf_range(-0.25, 0.25))), Color(0.35, 0.28, 0.15))
		nuts.instance(crown, "Coconuts")
	return crown


# A round leafy tree: trunk plus a cluster of spheres, one draw call.
static func build_leafy(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, ctx: WorldContext) -> void:
	var b := MeshBatch.new()
	var h := rng.randf_range(5.0, 8.0)
	b.add_cylinder(0.18, 0.28, h * 0.45, Color(0.4, 0.3, 0.2), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.225, 0)), 8)
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 7
	var green := Color(0.16, 0.38, 0.14)
	for i in 6:
		var off := Vector3(rng.randf_range(-1.6, 1.6), h * 0.55 + rng.randf_range(-0.6, 1.4), rng.randf_range(-1.6, 1.6))
		var r := rng.randf_range(1.6, 2.6)
		b.add(sm, Transform3D(Basis.IDENTITY.scaled(Vector3(r, r * 0.85, r)), off), green.lightened(rng.randf_range(-0.08, 0.14)))
	var mi := b.instance(parent, "Tree", 0.95)
	mi.position = pos
	ctx.add_obstacle(mi.global_position, 0.4)

class_name MeshBatch
extends RefCounted

# Merges many small meshes (boxes, cylinders, primitives, posed limbs) into
# one ArrayMesh with per-vertex colours, so a whole hotel facade or a whole
# posed sunbather costs a single draw call.

var st := SurfaceTool.new()
var offset := 0


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func add(mesh: Mesh, xform: Transform3D, color: Color, surface := 0) -> void:
	var arrays := mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var nbasis := xform.basis.inverse().transposed()
	for i in verts.size():
		st.set_color(color)
		if norms.size() > i:
			st.set_normal((nbasis * norms[i]).normalized())
		if uvs.size() > i:
			st.set_uv(uvs[i])
		st.add_vertex(xform * verts[i])
	if idx.size() > 0:
		for j in idx:
			st.add_index(j + offset)
	else:
		for j in verts.size():
			st.add_index(j + offset)
	offset += verts.size()


func add_box(size: Vector3, color: Color, xform: Transform3D) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	add(bm, xform, color)


func add_box_at(size: Vector3, color: Color, pos: Vector3) -> void:
	add_box(size, color, Transform3D(Basis.IDENTITY, pos))


func add_cylinder(r_top: float, r_bot: float, h: float, color: Color, xform: Transform3D, segs := 8) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	add(cm, xform, color)


func is_empty() -> bool:
	return offset == 0


func commit(rough := 0.85) -> ArrayMesh:
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = rough
	m.surface_set_material(0, mat)
	return m


func commit_with(material: Material) -> ArrayMesh:
	var m := st.commit()
	m.surface_set_material(0, material)
	return m


func instance(parent: Node3D, name := "Batch", rough := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = commit(rough)
	parent.add_child(mi)
	return mi

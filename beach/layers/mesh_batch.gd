class_name MeshBatch
extends RefCounted

# Merges many small meshes (boxes, cylinders, primitives, posed limbs) into
# one ArrayMesh with per-vertex colours, so a whole hotel facade or a whole
# crowd costs a single draw call. Accumulates packed arrays and transforms
# them with the engine's vectorised operators, so it stays fast in GDScript.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var uvs := PackedVector2Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()
var _arrays_cache := {}


func add(mesh: Mesh, xform: Transform3D, color: Color, surface := 0) -> void:
	var key := mesh.get_rid()
	var arrays: Array
	if _arrays_cache.has(key):
		arrays = _arrays_cache[key]
	else:
		arrays = mesh.surface_get_arrays(surface)
		_arrays_cache[key] = arrays
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := v.size()
	var base := verts.size()
	verts.append_array(xform * v)
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var nb := xform.basis.inverse().transposed()
		var tn: PackedVector3Array = Transform3D(nb, Vector3.ZERO) * (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)
		# normalise in bulk (scaled transforms) by rebuilding through a Basis is
		# not available; scales here are near-uniform so this is close enough
		norms.append_array(tn)
	else:
		var flat := PackedVector3Array()
		flat.resize(n)
		flat.fill(Vector3.UP)
		norms.append_array(flat)
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		uvs.append_array(arrays[Mesh.ARRAY_TEX_UV])
	else:
		var zu := PackedVector2Array()
		zu.resize(n)
		uvs.append_array(zu)
	var c := PackedColorArray()
	c.resize(n)
	c.fill(color)
	cols.append_array(c)
	var src_idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if src_idx.size() > 0:
		var shifted := src_idx.duplicate()
		for i in shifted.size():
			shifted[i] += base
		idx.append_array(shifted)
	else:
		var seq := PackedInt32Array()
		seq.resize(n)
		for i in n:
			seq[i] = base + i
		idx.append_array(seq)


func add_box(size: Vector3, color: Color, xform: Transform3D) -> void:
	add(_box_mesh(size), xform * Transform3D(Basis.IDENTITY.scaled(size), Vector3.ZERO), color)


func add_box_at(size: Vector3, color: Color, pos: Vector3) -> void:
	add(_box_mesh(size), Transform3D(Basis.IDENTITY.scaled(size), pos), color)


static var _unit_box: BoxMesh
static func _box_mesh(size: Vector3) -> Mesh:
	# one unit box, scaled through the transform, so its arrays are cached once
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box


func add_cylinder(r_top: float, r_bot: float, h: float, color: Color, xform: Transform3D, segs := 8) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	add(cm, xform, color)


func is_empty() -> bool:
	return verts.size() == 0


func commit(rough := 0.85) -> ArrayMesh:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = rough
	return commit_with(mat)


func commit_with(material: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, material)
	return m


func instance(parent: Node3D, name := "Batch", rough := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = commit(rough)
	parent.add_child(mi)
	return mi

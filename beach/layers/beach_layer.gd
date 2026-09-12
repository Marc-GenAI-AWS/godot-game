class_name BeachLayer
extends Node3D

# Base for every world layer. A layer owns its own nodes, builds itself from
# the shared context, and updates itself each frame. Specialise a layer by
# subclassing it (or replacing it in main.gd's layer list).

var ctx: WorldContext


func setup(c: WorldContext) -> void:
	ctx = c
	ctx.world_wrapped.connect(on_world_wrapped)
	build()


func build() -> void:
	pass


func tick(_delta: float) -> void:
	pass


func on_world_wrapped(_dz: float) -> void:
	pass


# Helpers shared by layers -----------------------------------------------

func box(parent: Node3D, size: Vector3, c: Color, pos: Vector3, rough := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = ctx.mat(c, rough)
	mi.position = pos
	parent.add_child(mi)
	return mi


func cylinder(parent: Node3D, r_top: float, r_bot: float, h: float, c: Color, pos: Vector3, segs := 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = ctx.mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


func sphere(parent: Node3D, r: float, c: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = ctx.mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


func grid_mesh(x0: float, x1: float, z0: float, z1: float, step: float, height_fn: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int((x1 - x0) / step) + 1
	var nz := int((z1 - z0) / step) + 1
	for iz in nz:
		for ix in nx:
			var x := x0 + ix * step
			var z := z0 + iz * step
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, height_fn.call(x, z), z))
	for iz in nz - 1:
		for ix in nx - 1:
			var i0 := iz * nx + ix
			var i1 := i0 + 1
			var i2 := i0 + nx
			var i3 := i2 + 1
			st.add_index(i0); st.add_index(i1); st.add_index(i2)
			st.add_index(i1); st.add_index(i3); st.add_index(i2)
	st.generate_normals()
	return st.commit()

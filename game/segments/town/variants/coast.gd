class_name CoastTown
extends ChunkedLayer

# The blocks between the seafront and the avenue: what you cross when you walk inland.
#
# This is the piece neither world had. The beach stops at its hedges and the street starts at its
# verges, 170 m apart, so without something here the two districts are two stage sets facing away
# from each other. What it builds, per 200 m chunk:
#
#   * the plateau apron - the flat ground the town stands on, laid just above the beach's own
#     sand mesh, which runs inland to x = -130 and would otherwise show through
#   * the street grid from CoastContext: three streets running inland, one running along the
#     coast through the middle of town, each with kerbs and sidewalks, wide enough to drive
#   * steps from the sand up to the promenade where each inland street meets it
#   * blocks filling the cells of that grid, glazed from the same window texture the street's
#     towers use
#
# Everything is one MeshBatch per material. The town is background: it is seen from a distance far
# more often than it is walked through, and draw calls are the scarce resource in this game.

const SHOP_COLORS := [Color(0.82, 0.78, 0.70), Color(0.74, 0.70, 0.66), Color(0.86, 0.80, 0.72),
					  Color(0.70, 0.72, 0.74), Color(0.80, 0.74, 0.68)]
const ROOF := Color(0.34, 0.33, 0.32)
const ASPHALT := Color(0.19, 0.19, 0.20)
const KERB := Color(0.72, 0.71, 0.69)
const WALK := Color(0.76, 0.75, 0.73)
const SEAWARD_X := -64.0           # where the inland streets meet the back of the boardwalk


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var y: float = CoastContext.plateau_y()
	var walls := MeshBatch.new()
	var roofs := MeshBatch.new()
	var paving := MeshBatch.new()
	var glass := MeshBatch.new()

	_apron(paving, y)
	for cz: float in CoastContext.CROSS_Z:
		_inland_street(paving, y, cz)
		_steps(paving, y, cz)
	_coast_street(paving, y)
	_blocks(walls, roofs, glass, rng, y)

	paving.instance(chunk, "Paving", 0.94)
	walls.instance(chunk, "Blocks", 0.88)
	roofs.instance(chunk, "Roofs", 0.9)
	var g := MeshInstance3D.new()
	g.name = "Glazing"
	g.mesh = glass.commit_with(_glass_mat())
	chunk.add_child(g)


# The beach's sand mesh runs inland to x = -130, well under the town, so the apron has to sit
# just above it (5 mm) or the streets are laid on sand. Its seaward edge at -68 then reads as the
# line where the beach ends and the town begins, which is what it is.
func _apron(b: MeshBatch, y: float) -> void:
	var x0: float = CoastContext.AVENUE_X - 40.0
	var x1 := -68.0
	b.add_box_at(Vector3(x1 - x0, 0.3, WorldContext.CHUNK),
				 Color(0.47, 0.49, 0.38),                      # dry coastal grass
				 Vector3((x0 + x1) * 0.5, y - 0.145, -WorldContext.CHUNK * 0.5))


# One street running inland, from the back of the boardwalk to the avenue.
func _inland_street(b: MeshBatch, y: float, z: float) -> void:
	var half: float = CoastContext.CROSS_HALF
	var x0: float = CoastContext.AVENUE_X
	var mid := (x0 + SEAWARD_X) * 0.5
	var length: float = SEAWARD_X - x0
	b.add_box_at(Vector3(length, 0.08, half * 2.0), ASPHALT, Vector3(mid, y + 0.03, z))
	b.add_box_at(Vector3(length - 8.0, 0.02, 0.16), Color(0.78, 0.72, 0.36), Vector3(mid, y + 0.08, z))
	for side: float in [-1.0, 1.0]:
		var kz: float = z + side * (half + 0.15)
		b.add_box_at(Vector3(length, 0.15, 0.3), KERB, Vector3(mid, y + 0.075, kz))
		b.add_box_at(Vector3(length, 0.15, 2.7), WALK, Vector3(mid, y + 0.075, kz + side * 1.5))


# The street running along the coast through the middle of town, crossing all three.
func _coast_street(b: MeshBatch, y: float) -> void:
	var half: float = CoastContext.CROSS_HALF
	var x: float = CoastContext.MID_X
	var L := WorldContext.CHUNK
	b.add_box_at(Vector3(half * 2.0, 0.08, L), ASPHALT, Vector3(x, y + 0.031, -L * 0.5))
	b.add_box_at(Vector3(0.16, 0.02, L), Color(0.78, 0.72, 0.36), Vector3(x, y + 0.081, -L * 0.5))
	for side: float in [-1.0, 1.0]:
		var kx: float = x + side * (half + 0.15)
		b.add_box_at(Vector3(0.3, 0.15, L), KERB, Vector3(kx, y + 0.075, -L * 0.5))
		b.add_box_at(Vector3(2.7, 0.15, L), WALK, Vector3(kx + side * 1.5, y + 0.075, -L * 0.5))
	# a junction is asphalt in both directions, so lay a square over the sidewalks at each
	for cz: float in CoastContext.CROSS_Z:
		b.add_box_at(Vector3(half * 2.4, 0.09, half * 2.4), ASPHALT, Vector3(x, y + 0.035, cz))


# Treads up to the promenade deck, matching the ramp CoastContext.walk_height returns here.
# Without them you walk up an invisible slope onto the boardwalk.
func _steps(b: MeshBatch, y: float, z: float) -> void:
	var x0: float = CoastContext.STEP_X0
	var x1: float = CoastContext.STEP_X1
	var bottom: float = ctx.ground_height(x0, z)
	var n := 5
	for i in n:
		var t: float = float(i + 1) / float(n)
		var h: float = lerpf(bottom, y, t)
		var xa: float = lerpf(x0, x1, float(i) / float(n))
		var xb: float = lerpf(x0, x1, t)
		b.add_box_at(Vector3(absf(xb - xa), h - bottom + 0.3, CoastContext.CROSS_WALK * 2.0),
					 Color(0.74, 0.72, 0.68),
					 Vector3((xa + xb) * 0.5, (h + bottom - 0.3) * 0.5, z))


# Fill the cells of the grid. A cell is bounded by two inland streets in Z and by two of
# (town edge, coast street, avenue) in X; buildings line its long edges facing the streets, which
# is what gives every street a frontage instead of a row of sheds in the middle of a field.
func _blocks(walls: MeshBatch, roofs: MeshBatch, glass: MeshBatch, rng: RandomNumberGenerator, y: float) -> void:
	var walk: float = CoastContext.CROSS_WALK
	var zs: Array = CoastContext.CROSS_Z.duplicate()
	zs.sort()
	var z_edges: Array = [0.0]                       # the chunk wraps, so its ends are edges too
	z_edges.append_array(zs)
	z_edges.append(-WorldContext.CHUNK)
	z_edges.reverse()                                # descending: 0, -40, -100, -160, -200
	var x_edges: Array = [CoastContext.TOWN_EDGE_X - 6.0, CoastContext.MID_X, CoastContext.AVENUE_X + 13.0]
	for xi in x_edges.size() - 1:
		for zi in z_edges.size() - 1:
			var x_hi: float = x_edges[xi] - (0.0 if xi == 0 else walk)
			var x_lo: float = x_edges[xi + 1] + (walk if xi + 1 < x_edges.size() - 1 else 0.0)
			var z_hi: float = z_edges[zi] - (walk if zi > 0 else 0.0)
			var z_lo: float = z_edges[zi + 1] + (walk if zi + 1 < z_edges.size() - 1 else 0.0)
			if x_hi - x_lo < 14.0 or z_hi - z_lo < 14.0:
				continue
			_fill_cell(walls, roofs, glass, rng, y, x_lo, x_hi, z_lo, z_hi)


func _fill_cell(walls: MeshBatch, roofs: MeshBatch, glass: MeshBatch, rng: RandomNumberGenerator,
				y: float, x_lo: float, x_hi: float, z_lo: float, z_hi: float) -> void:
	var depth: float = minf((z_hi - z_lo) * 0.42, 15.0)
	for side: float in [-1.0, 1.0]:                  # the two long frontages of the block
		var face_z: float = z_hi if side > 0.0 else z_lo
		var x: float = x_hi - rng.randf_range(0.0, 4.0)
		while x > x_lo + 10.0:
			var w: float = minf(rng.randf_range(11.0, 19.0), x - x_lo)
			var d := depth * rng.randf_range(0.75, 1.0)
			var floors := rng.randi_range(2, 4)
			if rng.randf() < 0.18:
				floors = rng.randi_range(5, 7)       # the odd taller block
			var h := floors * 3.1
			var cx := x - w * 0.5
			var cz: float = face_z - side * d * 0.5
			var col: Color = SHOP_COLORS[rng.randi() % SHOP_COLORS.size()]
			walls.add_box_at(Vector3(w, h, d), col, Vector3(cx, y + h * 0.5, cz))
			roofs.add_box_at(Vector3(w + 0.6, 0.35, d + 0.6), ROOF, Vector3(cx, y + h + 0.17, cz))
			# a shopfront at street level and windows above, on the street-facing side only -
			# the backs are never seen and glazing them would double this batch for nothing
			var face: float = cz + side * (d * 0.5 + 0.08)
			glass.add_box_at(Vector3(w - 1.6, 2.4, 0.16), Color(0.30, 0.36, 0.40),
							 Vector3(cx, y + 1.5, face))
			if h > 7.0:
				glass.add_box_at(Vector3(w - 2.6, h - 5.4, 0.14), Color(0.62, 0.68, 0.72),
								 Vector3(cx, y + 3.4 + (h - 5.4) * 0.5, face))
			ctx.add_obstacle(Vector3(cx, y, cz), maxf(w, d) * 0.5)
			x -= w + rng.randf_range(2.0, 7.0)


# The shared window texture, as the street's towers use it: one material for every block's
# glazing, so the whole town's windows cost one draw call per chunk.
func _glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ctx.window_tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.3, 0.3, 0.3)
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.35
	m.metallic = 0.3
	return m

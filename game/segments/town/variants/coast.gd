class_name CoastTown
extends ChunkedLayer

# The blocks between the seafront and the avenue: what you cross when you walk inland.
#
# This is the piece neither world had. The beach stops at its hedges and the street starts at
# its verges, 130 m apart, so without something here the two districts are two stage sets facing
# away from each other. What it builds, per 200 m chunk:
#
#   * the plateau apron - paving and grass from the bluff to the avenue, so the sand mesh
#     (which ends at x = -130) does not leave a hole
#   * the connector street at CROSS_Z, running inland from the promenade to the avenue, with
#     kerbs and sidewalks, wide enough to drive
#   * two rows of low shop and apartment blocks facing that street, glazed from the same window
#     texture the street's towers use
#
# Everything is one MeshBatch per material, because the town is background: it is seen from a
# distance far more often than it is walked through, and the draw-call budget is the scarce
# resource in this game.

const SHOP_COLORS := [Color(0.82, 0.78, 0.70), Color(0.74, 0.70, 0.66), Color(0.86, 0.80, 0.72),
					  Color(0.70, 0.72, 0.74), Color(0.80, 0.74, 0.68)]
const ROOF := Color(0.34, 0.33, 0.32)


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var y: float = CoastContext.plateau_y()
	var walls := MeshBatch.new()
	var roofs := MeshBatch.new()
	var paving := MeshBatch.new()
	var glass := MeshBatch.new()

	_apron(paving, y)
	_connector(paving, y)
	_blocks(walls, roofs, glass, rng, y)

	paving.instance(chunk, "Paving", 0.94)
	walls.instance(chunk, "Blocks", 0.88)
	roofs.instance(chunk, "Roofs", 0.9)
	var g := MeshInstance3D.new()
	g.name = "Glazing"
	g.mesh = glass.commit_with(_glass_mat())
	chunk.add_child(g)


# Flat ground from the bluff to beyond the avenue. The beach's sand mesh reaches x = -130 and
# the street district's lawn is narrowed to its own lots, so this covers what is left.
func _apron(b: MeshBatch, y: float) -> void:
	# The beach's sand mesh runs inland to x = -130, well under the town, so the apron has to
	# sit just above it (5 mm) or the streets are laid on sand. Its seaward edge at -68 then
	# reads as the line where the beach ends and the town begins, which is what it is.
	var x0: float = CoastContext.AVENUE_X - 40.0
	var x1 := -68.0
	b.add_box_at(Vector3(x1 - x0, 0.3, WorldContext.CHUNK),
				 Color(0.47, 0.49, 0.38),                      # dry coastal grass
				 Vector3((x0 + x1) * 0.5, y - 0.145, -WorldContext.CHUNK * 0.5))


# The street that joins the promenade to the avenue.
func _connector(b: MeshBatch, y: float) -> void:
	var z: float = CoastContext.CROSS_Z
	var half: float = CoastContext.CROSS_HALF
	var x0: float = CoastContext.AVENUE_X
	var x1 := -64.0                                            # meets the back of the deck
	var mid := (x0 + x1) * 0.5
	var length := x1 - x0
	# asphalt, a whisker above the apron so it does not z-fight
	b.add_box_at(Vector3(length, 0.08, half * 2.0), Color(0.19, 0.19, 0.20),
				 Vector3(mid, y + 0.03, z))
	# centre line
	b.add_box_at(Vector3(length - 8.0, 0.02, 0.16), Color(0.78, 0.72, 0.36),
				 Vector3(mid, y + 0.08, z))
	_steps(b, y, z)
	for side: float in [-1.0, 1.0]:
		var kz: float = z + side * (half + 0.15)
		b.add_box_at(Vector3(length, 0.15, 0.3), Color(0.72, 0.71, 0.69),
					 Vector3(mid, y + 0.075, kz))               # kerb
		b.add_box_at(Vector3(length, 0.15, 2.7), Color(0.76, 0.75, 0.73),
					 Vector3(mid, y + 0.075, kz + side * 1.5))  # sidewalk


# Two rows of blocks facing the connector, one each side, from the town edge to the avenue.
func _blocks(walls: MeshBatch, roofs: MeshBatch, glass: MeshBatch, rng: RandomNumberGenerator, y: float) -> void:
	var z: float = CoastContext.CROSS_Z
	var setback: float = CoastContext.CROSS_WALK + 1.5
	for side: float in [-1.0, 1.0]:
		var x: float = CoastContext.TOWN_EDGE_X - 6.0
		while x > CoastContext.AVENUE_X + 18.0:
			var w := rng.randf_range(11.0, 19.0)               # frontage along X
			var d := rng.randf_range(9.0, 14.0)                # depth away from the street
			var floors := rng.randi_range(2, 4)
			if rng.randf() < 0.18:
				floors = rng.randi_range(5, 7)                 # the odd taller block
			var h := floors * 3.1
			var cx := x - w * 0.5
			var cz: float = z + side * (setback + d * 0.5)
			var col: Color = SHOP_COLORS[rng.randi() % SHOP_COLORS.size()]
			walls.add_box_at(Vector3(w, h, d), col, Vector3(cx, y + h * 0.5, cz))
			roofs.add_box_at(Vector3(w + 0.6, 0.35, d + 0.6), ROOF, Vector3(cx, y + h + 0.17, cz))
			# a shopfront at street level and windows above, on the street-facing side only -
			# the backs are never seen and glazing them would double this batch for nothing
			var face: float = cz - side * (d * 0.5 + 0.08)
			glass.add_box_at(Vector3(w - 1.6, 2.4, 0.16), Color(0.30, 0.36, 0.40),
							 Vector3(cx, y + 1.5, face))
			if h > 7.0:
				glass.add_box_at(Vector3(w - 2.6, h - 5.4, 0.14), Color(0.62, 0.68, 0.72),
								 Vector3(cx, y + 3.4 + (h - 5.4) * 0.5, face))
			x -= w + rng.randf_range(3.0, 9.0)                 # gaps between blocks
			ctx.add_obstacle(Vector3(cx, y, cz), maxf(w, d) * 0.5)


# Treads up to the promenade deck, matching the ramp CoastContext.walk_height returns here.
# Without them you walk up an invisible slope onto the boardwalk.
func _steps(b: MeshBatch, y: float, z: float) -> void:
	var x0: float = CoastContext.STEP_X0
	var x1: float = CoastContext.STEP_X1
	var bottom: float = ctx.ground_height(x0, z)
	var top: float = y                                   # the deck is level with the terrace
	var n := 5
	for i in n:
		var t: float = float(i + 1) / float(n)
		var h: float = lerpf(bottom, top, t)
		var xa: float = lerpf(x0, x1, float(i) / float(n))
		var xb: float = lerpf(x0, x1, t)
		b.add_box_at(Vector3(absf(xb - xa), h - bottom + 0.3, CoastContext.CROSS_WALK * 2.0),
					 Color(0.74, 0.72, 0.68),
					 Vector3((xa + xb) * 0.5, (h + bottom - 0.3) * 0.5, z))


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

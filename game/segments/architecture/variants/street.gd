class_name StreetArchitecture
extends ChunkedLayer

# Suburban lots modelled on the reference: stucco houses with steep shingled
# or terracotta-tiled roofs, dormers, chimneys, framed windows and doors,
# garages with driveways, garden walls / picket fences / hedges, and a
# downtown of glass towers with window grids far behind one side.

var stucco: StandardMaterial3D
var shingle: StandardMaterial3D
var tile: StandardMaterial3D
var tower_glass: StandardMaterial3D


func _init() -> void:
	seed_v = 9090


func _tex(size: int, fn: Callable) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, fn.call(x, y))
	return ImageTexture.create_from_image(img)


func build() -> void:
	var n := FastNoiseLite.new()
	n.seed = 31
	n.frequency = 0.08
	n.fractal_octaves = 3
	stucco = StandardMaterial3D.new()
	stucco.albedo_texture = _tex(128, func(x, y): var v := n.get_noise_2d(x * 2.0, y * 2.0) * 0.5 + 0.5; return Color(1, 1, 1) * (0.9 + 0.1 * v))
	stucco.uv1_triplanar = true
	stucco.uv1_scale = Vector3(0.5, 0.5, 0.5)
	stucco.vertex_color_use_as_albedo = true
	stucco.roughness = 0.95
	var shingle_img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var row := y / 16
			var offset := 8 if row % 2 == 1 else 0
			var edge := (y % 16) < 2 or ((x + offset) % 32) < 2
			var v := n.get_noise_2d(x * 3.0, y * 3.0) * 0.5 + 0.5
			shingle_img.set_pixel(x, y, (Color(0.62, 0.6, 0.56) if not edge else Color(0.4, 0.38, 0.35)) * (0.85 + 0.3 * v))
	shingle = StandardMaterial3D.new()
	shingle.albedo_texture = ImageTexture.create_from_image(shingle_img)
	shingle.uv1_triplanar = true
	shingle.uv1_scale = Vector3(0.7, 0.7, 0.7)
	shingle.vertex_color_use_as_albedo = true
	shingle.roughness = 0.95
	var tile_img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var cx := float((x + (8 if (y / 16) % 2 else 0)) % 16) / 16.0
			var curve := 0.8 + 0.2 * sin(cx * PI)
			var edge := (y % 16) < 2
			var v := n.get_noise_2d(x * 2.0, y * 2.0) * 0.5 + 0.5
			tile_img.set_pixel(x, y, (Color(0.72, 0.4, 0.25) * curve if not edge else Color(0.45, 0.25, 0.15)) * (0.88 + 0.24 * v))
	tile = StandardMaterial3D.new()
	tile.albedo_texture = ImageTexture.create_from_image(tile_img)
	tile.uv1_triplanar = true
	tile.uv1_scale = Vector3(0.9, 0.9, 0.9)
	tile.vertex_color_use_as_albedo = true
	tile.roughness = 0.9
	tower_glass = StandardMaterial3D.new()
	tower_glass.albedo_texture = ctx.window_tex
	tower_glass.uv1_triplanar = true
	tower_glass.uv1_scale = Vector3(0.25, 0.25, 0.25)
	tower_glass.vertex_color_use_as_albedo = true
	tower_glass.roughness = 0.3
	tower_glass.metallic = 0.4
	super.build()


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	var walls := [Color(0.92, 0.89, 0.82), Color(0.86, 0.82, 0.72), Color(0.95, 0.93, 0.88), Color(0.82, 0.78, 0.7), Color(0.9, 0.85, 0.76), Color(0.78, 0.8, 0.78), Color(0.93, 0.88, 0.7)]
	var trim_c := Color(0.96, 0.96, 0.94)
	var glass := Color(0.2, 0.26, 0.34)
	for side: float in [-1.0, 1.0]:
		var z := -L
		while z < 0.0:
			var w := rng.randf_range(15.0, 26.0)
			var sb := MeshBatch.new()     # stucco (walls, garden wall)
			var rb := MeshBatch.new()     # roof
			var tb := MeshBatch.new()     # trim, glass, doors (flat colours)
			var wc: Color = walls[rng.randi() % walls.size()]
			var x0 := side * sc.LOT_X
			var lot_z := z + w * 0.5
			# frontage: garden wall with pillars, picket fence, or open lawn
			var front := rng.randf()
			var gate := rng.randf_range(4.0, w - 6.0)
			if front < 0.45:
				var wall_h := rng.randf_range(1.0, 1.8)
				sb.add_box_at(Vector3(0.35, wall_h, gate - 1.6), wc.darkened(0.08), Vector3(x0, wall_h * 0.5, z + (gate - 1.6) * 0.5))
				sb.add_box_at(Vector3(0.35, wall_h, w - gate - 1.6), wc.darkened(0.08), Vector3(x0, wall_h * 0.5, z + gate + 1.6 + (w - gate - 1.6) * 0.5))
				for pz: float in [0.0, gate - 1.6, gate + 1.6, w]:
					sb.add_box_at(Vector3(0.55, wall_h + 0.3, 0.55), wc.darkened(0.15), Vector3(x0, (wall_h + 0.3) * 0.5, z + pz))
					sb.add_box_at(Vector3(0.65, 0.08, 0.65), wc.darkened(0.25), Vector3(x0, wall_h + 0.34, z + pz))
				tb.add_box_at(Vector3(0.08, wall_h * 0.85, 3.0), Color(0.18, 0.2, 0.22), Vector3(x0, wall_h * 0.45, z + gate))
			elif front < 0.75:
				var pz := 0.0
				while pz < w:
					if absf(pz - gate) > 1.6:
						tb.add_box_at(Vector3(0.08, 1.0, 0.12), trim_c, Vector3(x0, 0.5, z + pz))
					pz += 0.3
				tb.add_box_at(Vector3(0.06, 0.08, gate - 1.6), trim_c, Vector3(x0, 0.75, z + (gate - 1.6) * 0.5))
				tb.add_box_at(Vector3(0.06, 0.08, w - gate - 1.6), trim_c, Vector3(x0, 0.75, z + gate + 1.6 + (w - gate - 1.6) * 0.5))
			# house set back on the lot
			var d := rng.randf_range(9.0, 13.0)
			var hw := w * rng.randf_range(0.55, 0.78)
			var floors := 1 if rng.randf() < 0.55 else 2
			var fh := 2.9
			var hh := floors * fh
			var hx := side * (sc.LOT_X + 6.0 + d * 0.5)
			var face := side * (sc.LOT_X + 6.0)
			sb.add_box_at(Vector3(d, hh, hw), wc, Vector3(hx, hh * 0.5, lot_z))
			sb.add_box_at(Vector3(d + 0.3, 0.35, hw + 0.3), wc.darkened(0.12), Vector3(hx, 0.17, lot_z))     # plinth
			# windows with white frames and sills; a door with steps; a garage on some
			var garage := rng.randf() < 0.5 and floors == 1
			for f in floors:
				var wy := f * fh + 1.55
				var nw := maxi(int(hw / 3.2), 2)
				for k in nw:
					var wz := lot_z - hw * 0.5 + (k + 0.5) * (hw / nw)
					if f == 0 and absf(wz - lot_z) < 1.0:
						continue   # door goes here
					if garage and f == 0 and k >= nw - 2:
						continue
					tb.add_box_at(Vector3(0.14, 1.45, 1.35), trim_c, Vector3(face - side * 0.03, wy, wz))
					tb.add_box_at(Vector3(0.16, 1.2, 1.1), glass, Vector3(face - side * 0.06, wy, wz))
					tb.add_box_at(Vector3(0.02, 0.06, 1.1), Color(1, 1, 1), Vector3(face - side * 0.14, wy, wz))
					tb.add_box_at(Vector3(0.02, 1.2, 0.05), Color(1, 1, 1), Vector3(face - side * 0.14, wy, wz))
					tb.add_box_at(Vector3(0.3, 0.08, 1.5), trim_c, Vector3(face - side * 0.12, wy - 0.76, wz))
			tb.add_box_at(Vector3(0.12, 2.2, 1.1), trim_c, Vector3(face - side * 0.02, 1.1, lot_z))
			tb.add_box_at(Vector3(0.14, 2.05, 0.95), Color(0.35, 0.22, 0.14), Vector3(face - side * 0.05, 1.02, lot_z))
			tb.add_box_at(Vector3(1.2, 0.16, 1.8), Color(0.75, 0.73, 0.7), Vector3(face - side * 0.65, 0.08, lot_z))
			tb.add_box_at(Vector3(1.4, 0.12, 2.2), trim_c, Vector3(face - side * 0.7, 2.35, lot_z))   # porch canopy
			if garage:
				tb.add_box_at(Vector3(0.12, 2.3, 4.6), trim_c.darkened(0.05), Vector3(face - side * 0.02, 1.15, lot_z + hw * 0.5 - 2.6))
				for gl in 4:
					tb.add_box_at(Vector3(0.02, 0.04, 4.4), Color(0.7, 0.7, 0.68), Vector3(face - side * 0.09, 0.4 + gl * 0.55, lot_z + hw * 0.5 - 2.6))
			# roof: two slabs (shingle or terracotta), gable ends in stucco, eaves, dormer on some
			var roof_mat := shingle if rng.randf() < 0.6 else tile
			var pitch := rng.randf_range(0.5, 0.75)
			var half := d * 0.5 + 0.5
			var slab_l := half / cos(pitch)
			var ridge := half * tan(pitch)
			for s: float in [-1.0, 1.0]:
				var t := Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, -s * pitch), Vector3(hx + s * half * 0.5, hh + ridge * 0.5, lot_z))
				rb.add_box(Vector3(slab_l, 0.16, hw + 1.0), Color(1, 1, 1), t)
			for s: float in [-1.0, 1.0]:
				# gable triangle approximated by three stepped boxes
				for st in 3:
					var frac := 1.0 - float(st) / 3.0
					sb.add_box_at(Vector3(d * frac, ridge / 3.0, 0.3), wc, Vector3(hx, hh + ridge * (float(st) + 0.5) / 3.0, lot_z + s * (hw * 0.5 - 0.15)))
			tb.add_box_at(Vector3(d + 1.0, 0.12, hw + 1.0), trim_c, Vector3(hx, hh - 0.06, lot_z))   # fascia / eaves line
			if rng.randf() < 0.45:
				var dz := lot_z + rng.randf_range(-hw * 0.25, hw * 0.25)
				sb.add_box_at(Vector3(1.6, 1.4, 1.8), wc, Vector3(face - side * 0.0 + side * 1.4, hh + 0.9, dz))
				tb.add_box_at(Vector3(0.1, 0.9, 0.9), glass, Vector3(face + side * 0.58, hh + 0.9, dz))
				rb.add_box(Vector3(1.6, 0.12, 2.2), Color(1, 1, 1), Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, -side * 0.5), Vector3(face + side * 1.4, hh + 1.9, dz)))
			sb.add_box_at(Vector3(0.7, ridge + 1.6, 0.7), wc.darkened(0.3), Vector3(hx + d * 0.25, hh + (ridge + 1.6) * 0.5, lot_z + hw * 0.28))
			var smi := MeshInstance3D.new()
			smi.mesh = sb.commit_with(stucco)
			chunk.add_child(smi)
			var rmi := MeshInstance3D.new()
			rmi.mesh = rb.commit_with(roof_mat)
			chunk.add_child(rmi)
			tb.instance(chunk, "Trim", 0.8)
			z += w + rng.randf_range(0.5, 3.0)
	# distant downtown: glass towers with window grids, behind -X
	var sky := MeshBatch.new()
	var sx := -180.0
	for i in 16:
		var tw := rng.randf_range(14.0, 30.0)
		var th := rng.randf_range(45.0, 140.0)
		var tz := -L * 0.5 + rng.randf_range(-100.0, 100.0)
		var shade := Color(0.5, 0.58, 0.68).lightened(rng.randf_range(-0.15, 0.15))
		sky.add_box_at(Vector3(tw, th, tw), shade, Vector3(sx + rng.randf_range(-50.0, 50.0), th * 0.5, tz))
	var tmi := MeshInstance3D.new()
	tmi.mesh = sky.commit_with(tower_glass)
	chunk.add_child(tmi)

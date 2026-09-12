class_name StreetArchitecture
extends ChunkedLayer

# Suburban lots: garden walls with pillars, houses with pitched roofs behind
# them, the odd two-storey block and shopfront, and a downtown skyline far
# behind one side.

func _init() -> void:
	seed_v = 9090


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	var walls := [Color(0.9, 0.87, 0.8), Color(0.85, 0.8, 0.7), Color(0.93, 0.9, 0.86), Color(0.8, 0.75, 0.68), Color(0.88, 0.83, 0.75)]
	var roofs := [Color(0.42, 0.28, 0.2), Color(0.35, 0.35, 0.36), Color(0.55, 0.3, 0.22), Color(0.3, 0.32, 0.3)]
	for side: float in [-1.0, 1.0]:
		var z := -L
		while z < 0.0:
			var w := rng.randf_range(14.0, 26.0)
			var b := MeshBatch.new()
			var wc: Color = walls[rng.randi() % walls.size()]
			var x0 := side * sc.LOT_X
			# garden wall with pillars and a gate gap
			var wall_h := rng.randf_range(1.2, 2.0)
			var gate := rng.randf_range(3.0, w - 5.0)
			b.add_box_at(Vector3(0.35, wall_h, gate - 1.6), wc.darkened(0.1), Vector3(x0, wall_h * 0.5, z + (gate - 1.6) * 0.5))
			b.add_box_at(Vector3(0.35, wall_h, w - gate - 1.6), wc.darkened(0.1), Vector3(x0, wall_h * 0.5, z + gate + 1.6 + (w - gate - 1.6) * 0.5))
			for pz in [0.0, gate - 1.6, gate + 1.6, w]:
				b.add_box_at(Vector3(0.55, wall_h + 0.3, 0.55), wc.darkened(0.2), Vector3(x0, (wall_h + 0.3) * 0.5, z + pz))
			b.add_box_at(Vector3(0.1, wall_h * 0.8, 3.0), Color(0.2, 0.22, 0.24), Vector3(x0, wall_h * 0.4, z + gate))   # gate
			# house set back
			var d := rng.randf_range(9.0, 14.0)
			var hw := w * rng.randf_range(0.55, 0.8)
			var floors := 1 if rng.randf() < 0.6 else 2
			var hh := floors * 3.0
			var hx := side * (sc.LOT_X + 6.0 + d * 0.5)
			var hz := z + w * 0.5
			b.add_box_at(Vector3(d, hh, hw), wc, Vector3(hx, hh * 0.5, hz))
			# windows and door on the street face
			var face := side * (sc.LOT_X + 6.0)
			for f in floors:
				var wy := f * 3.0 + 1.6
				var nw := int(hw / 3.0)
				for k in nw:
					b.add_box_at(Vector3(0.1, 1.2, 1.1), Color(0.18, 0.22, 0.3), Vector3(face - side * 0.02, wy, hz - hw * 0.5 + (k + 0.5) * (hw / nw)))
			b.add_box_at(Vector3(0.1, 2.1, 1.0), Color(0.3, 0.2, 0.15), Vector3(face - side * 0.02, 1.05, hz))
			# pitched roof: two slabs
			var rc: Color = roofs[rng.randi() % roofs.size()]
			var pitch := 0.55
			var half := d * 0.5 + 0.4
			var slab_l := half / cos(pitch)
			for s: float in [-1.0, 1.0]:
				var t := Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, -s * pitch), Vector3(hx + s * half * 0.5, hh + half * 0.5 * tan(pitch) * 1.0, hz))
				b.add_box(Vector3(slab_l, 0.18, hw + 0.8), rc, t)
			b.add_box_at(Vector3(0.6, 1.4, 0.6), wc.darkened(0.25), Vector3(hx + d * 0.25, hh + 1.2, hz + hw * 0.25))   # chimney
			b.instance(chunk, "Lot", 0.9)
			z += w + rng.randf_range(0.5, 3.0)
	# distant downtown behind the -X side
	var sky := MeshBatch.new()
	var sx := -170.0
	for i in 14:
		var tw := rng.randf_range(14.0, 30.0)
		var th := rng.randf_range(40.0, 130.0)
		var tz := -L * 0.5 + rng.randf_range(-90.0, 90.0)
		sky.add_box_at(Vector3(tw, th, tw), Color(0.45, 0.5, 0.58).lightened(rng.randf_range(-0.1, 0.15)), Vector3(sx + rng.randf_range(-40.0, 40.0), th * 0.5, tz))
	sky.instance(chunk, "Downtown", 0.6)

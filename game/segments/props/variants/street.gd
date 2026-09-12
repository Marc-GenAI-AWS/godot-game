class_name StreetProps
extends ChunkedLayer

# Street furniture: lamps, stop signs, bins, hydrants, mailboxes, a bus bench.

func _init() -> void:
	seed_v = 3131


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	var b := MeshBatch.new()
	var grey := Color(0.3, 0.32, 0.34)
	for side: float in [-1.0, 1.0]:
		var x := side * (sc.ROAD_HALF + 0.9)
		var z := -L + 6.0
		var i := 0
		while z < 0.0:
			if i % 2 == 0:
				b.add_cylinder(0.08, 0.12, 8.0, grey, Transform3D(Basis.IDENTITY, Vector3(x, 4.0 + sc.KERB_H, z)), 8)
				b.add_box_at(Vector3(1.6, 0.1, 0.1), grey, Vector3(x - side * 0.8, 8.0 + sc.KERB_H, z))
				b.add_box_at(Vector3(0.5, 0.14, 0.3), Color(0.95, 0.95, 0.85), Vector3(x - side * 1.6, 7.9 + sc.KERB_H, z))
				ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, z), 0.3)
			if i % 6 == 3:
				b.add_cylinder(0.3, 0.3, 0.9, Color(0.2, 0.35, 0.25), Transform3D(Basis.IDENTITY, Vector3(x, 0.45 + sc.KERB_H, z + 1.5)), 10)
				ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, z + 1.5), 0.45)
			if i % 8 == 5:
				b.add_cylinder(0.12, 0.14, 0.7, Color(0.85, 0.15, 0.12), Transform3D(Basis.IDENTITY, Vector3(x, 0.35 + sc.KERB_H, z - 2.0)), 8)   # hydrant
				ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, z - 2.0), 0.3)
			z += 12.0
			i += 1
	# stop sign at the crosswalk
	var cz := -L + 12.0
	b.add_cylinder(0.05, 0.05, 2.6, grey, Transform3D(Basis.IDENTITY, Vector3(sc.ROAD_HALF + 0.7, 1.3 + sc.KERB_H, cz + 4.0)), 6)
	b.add_cylinder(0.42, 0.42, 0.04, Color(0.8, 0.1, 0.1), Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, PI * 0.5), Vector3(sc.ROAD_HALF + 0.7, 2.7 + sc.KERB_H, cz + 4.0)), 8)
	# bus bench + mailbox
	b.add_box_at(Vector3(0.5, 0.08, 1.8), Color(0.2, 0.3, 0.5), Vector3(sc.ROAD_HALF + 1.8, 0.5 + sc.KERB_H, -L * 0.5))
	b.add_box_at(Vector3(0.08, 0.5, 1.8), Color(0.2, 0.3, 0.5), Vector3(sc.ROAD_HALF + 2.0, 0.75 + sc.KERB_H, -L * 0.5))
	b.add_box_at(Vector3(0.5, 0.6, 0.6), Color(0.15, 0.25, 0.55), Vector3(-sc.ROAD_HALF - 1.0, 0.8 + sc.KERB_H, -L * 0.3))
	b.instance(chunk, "StreetProps", 0.8)

extends ChunkedLayer

# Street furniture: grey lamps every 18 m, dark green bins, red hydrants,
# benches and mailboxes on the sidewalks near the kerb. No poles/wires/signs
# in this brief — just the listed items at normal density.

var lamp_glow: StandardMaterial3D


func _init() -> void:
	seed_v = 4177


func build() -> void:
	lamp_glow = StandardMaterial3D.new()
	lamp_glow.albedo_color = Color(1.0, 0.98, 0.9)
	lamp_glow.emission_enabled = true
	lamp_glow.emission = Color(1.0, 0.95, 0.8)
	lamp_glow.emission_energy_multiplier = 0.6
	super.build()


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	var b := MeshBatch.new()
	var glow := MeshBatch.new()

	var grey := Color(0.35, 0.36, 0.38)
	var bin_col := Color(0.1, 0.28, 0.16)
	var hydrant_col := Color(0.82, 0.12, 0.1)
	var bench_col := Color(0.42, 0.3, 0.2)
	var bench_metal := Color(0.28, 0.28, 0.3)
	var mailbox_col := Color(0.15, 0.25, 0.55)

	for side: float in [-1.0, 1.0]:
		var x := side * (sc.ROAD_HALF + 0.9)
		var z := -L + 6.0
		var i := 0
		while z < 0.0:
			# lamp every ~18 m, offset slightly per side so they phase apart
			var lz := z + (side * 1.5)
			b.add_cylinder(0.07, 0.13, 8.0, grey, Transform3D(Basis.IDENTITY, Vector3(x, 4.0 + sc.KERB_H, lz)), 8)
			b.add_box(Vector3(1.8, 0.1, 0.1), grey, Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, side * 0.25), Vector3(x - side * 0.85, 8.1 + sc.KERB_H, lz)))
			b.add_box_at(Vector3(0.6, 0.12, 0.34), grey, Vector3(x - side * 1.75, 8.0 + sc.KERB_H, lz))
			glow.add_box_at(Vector3(0.5, 0.05, 0.28), Color(1, 1, 1), Vector3(x - side * 1.75, 7.93 + sc.KERB_H, lz))
			ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, lz), 0.3)

			# bins roughly every third lamp (~54 m), offset onto the sidewalk
			if i % 3 == 1:
				var bz := z + 3.0
				b.add_cylinder(0.3, 0.3, 0.9, bin_col, Transform3D(Basis.IDENTITY, Vector3(x, 0.45 + sc.KERB_H, bz)), 10)
				b.add_cylinder(0.32, 0.32, 0.06, bin_col.darkened(0.2), Transform3D(Basis.IDENTITY, Vector3(x, 0.93 + sc.KERB_H, bz)), 10)
				ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, bz), 0.45)

			# hydrants roughly every fourth lamp (~72 m), opposite offset
			if i % 4 == 2:
				var hz := z - 4.0
				b.add_cylinder(0.12, 0.14, 0.7, hydrant_col, Transform3D(Basis.IDENTITY, Vector3(x, 0.35 + sc.KERB_H, hz)), 8)
				b.add_box_at(Vector3(0.32, 0.08, 0.1), hydrant_col, Vector3(x, 0.62 + sc.KERB_H, hz))
				b.add_cylinder(0.06, 0.06, 0.16, hydrant_col.darkened(0.15), Transform3D(Basis.IDENTITY, Vector3(x, 0.78 + sc.KERB_H, hz)), 6)
				ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, hz), 0.3)

			# a bench every fifth lamp (~90 m), alternating sides
			if i % 5 == 3:
				var nz := z + 5.0
				var nx := x + (0.6 if side < 0.0 else -0.6)
				b.add_box_at(Vector3(1.4, 0.06, 0.4), bench_col, Vector3(nx, 0.45 + sc.KERB_H, nz))
				b.add_box_at(Vector3(1.4, 0.4, 0.06), bench_col, Vector3(nx, 0.65 + sc.KERB_H, nz - 0.18))
				for dx in [-0.6, 0.6]:
					b.add_box_at(Vector3(0.06, 0.45, 0.06), bench_metal, Vector3(nx + dx, 0.22 + sc.KERB_H, nz))
				ctx.add_obstacle(chunk.global_transform * Vector3(nx, 0, nz), 0.5)

			# a mailbox every sixth lamp (~108 m), opposite side
			if i % 6 == 4:
				var mz := z - 6.0
				var mx := x - (0.6 if side < 0.0 else -0.6)
				b.add_cylinder(0.05, 0.06, 0.9, mailbox_col.darkened(0.2), Transform3D(Basis.IDENTITY, Vector3(mx, 0.45 + sc.KERB_H, mz)), 8)
				b.add_box_at(Vector3(0.4, 0.5, 0.32), mailbox_col, Vector3(mx, 1.05 + sc.KERB_H, mz))
				b.add_cylinder(0.2, 0.2, 0.32, mailbox_col, Transform3D(Basis.IDENTITY, Vector3(mx, 1.3 + sc.KERB_H, mz)), 10)
				ctx.add_obstacle(chunk.global_transform * Vector3(mx, 0, mz), 0.35)

			z += 18.0
			i += 1

	b.instance(chunk, "StreetProps", 0.8)
	var gmi := MeshInstance3D.new()
	gmi.name = "LampGlow"
	gmi.mesh = glow.commit_with(lamp_glow)
	chunk.add_child(gmi)

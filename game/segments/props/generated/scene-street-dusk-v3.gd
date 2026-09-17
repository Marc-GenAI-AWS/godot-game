extends ChunkedLayer

# Street furniture, normal density: lamps and bins only. Grey lamp poles with
# warm glowing heads, dark green litter bins, spaced along both kerbs.

var lamp_glow: StandardMaterial3D


func _init() -> void:
	seed_v = 4242


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
	var grey := Color(0.32, 0.34, 0.36)
	var bin_col := Color(0.08, 0.28, 0.16)
	var hydrant_col := Color(0.82, 0.12, 0.1)

	for side: float in [-1.0, 1.0]:
		var x := side * (sc.ROAD_HALF + 0.9)
		var z := -L + rng.randf_range(2.0, 6.0)
		var i := 0
		while z < 0.0:
			# lamp: tapered pole, curved arm, glowing head — every 18 m
			b.add_cylinder(0.07, 0.13, 8.0, grey, Transform3D(Basis.IDENTITY, Vector3(x, 4.0 + sc.KERB_H, z)), 8)
			b.add_box(Vector3(1.8, 0.1, 0.1), grey, Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, side * 0.25), Vector3(x - side * 0.85, 8.1 + sc.KERB_H, z)))
			b.add_box_at(Vector3(0.6, 0.12, 0.34), grey, Vector3(x - side * 1.75, 8.0 + sc.KERB_H, z))
			glow.add_box_at(Vector3(0.5, 0.05, 0.28), Color(1, 1, 1), Vector3(x - side * 1.75, 7.93 + sc.KERB_H, z))
			ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, z), 0.3)

			# bin roughly midway between consecutive lamps, offset slightly along z
			var bz := z + 9.0
			if bz < 0.0:
				b.add_cylinder(0.3, 0.3, 0.9, bin_col, Transform3D(Basis.IDENTITY, Vector3(x, 0.45 + sc.KERB_H, bz)), 10)
				b.add_cylinder(0.32, 0.32, 0.05, bin_col.darkened(0.2), Transform3D(Basis.IDENTITY, Vector3(x, 0.92 + sc.KERB_H, bz)), 10)
				ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, bz), 0.45)

			# hydrant every third lamp, offset further along z
			if i % 3 == 1:
				var hz := z + 4.5
				if hz < 0.0:
					b.add_cylinder(0.12, 0.14, 0.7, hydrant_col, Transform3D(Basis.IDENTITY, Vector3(x, 0.35 + sc.KERB_H, hz)), 8)
					b.add_cylinder(0.16, 0.16, 0.1, hydrant_col.darkened(0.15), Transform3D(Basis.IDENTITY, Vector3(x, 0.72 + sc.KERB_H, hz)), 8)
					b.add_box_at(Vector3(0.32, 0.06, 0.06), hydrant_col, Vector3(x, 0.55 + sc.KERB_H, hz))
					ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, hz), 0.3)

			z += 18.0
			i += 1

	b.instance(chunk, "StreetProps", 0.8)
	var gmi := MeshInstance3D.new()
	gmi.name = "LampGlow"
	gmi.mesh = glow.commit_with(lamp_glow)
	chunk.add_child(gmi)

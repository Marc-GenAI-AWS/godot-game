extends ChunkedLayer

# Street furniture, restricted to the brief: grey lamps every 18 m and dark
# green bins at a normal density. No poles/wires/signs/hydrants/mailbox/bench
# in this pass -- just the two item types listed in the brief ("lamps and
# bins only").

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
	var grey := Color(0.32, 0.34, 0.36)
	var bin_col := Color(0.1, 0.3, 0.18)

	for side: float in [-1.0, 1.0]:
		var x := side * (sc.ROAD_HALF + 0.9)
		var z := -L + rng.randf_range(2.0, 6.0)
		var i := 0
		while z < 0.0:
			# lamp: tapered pole, curved arm, glowing head
			b.add_cylinder(0.07, 0.13, 8.0, grey, Transform3D(Basis.IDENTITY, Vector3(x, 4.0 + sc.KERB_H, z)), 8)
			b.add_box(Vector3(1.8, 0.1, 0.1), grey, Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, side * 0.25), Vector3(x - side * 0.85, 8.1 + sc.KERB_H, z)))
			b.add_box_at(Vector3(0.6, 0.12, 0.34), grey, Vector3(x - side * 1.75, 8.0 + sc.KERB_H, z))
			glow.add_box_at(Vector3(0.5, 0.05, 0.28), Color(1, 1, 1), Vector3(x - side * 1.75, 7.93 + sc.KERB_H, z))
			ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, z), 0.3)

			# bins at a normal-ish density (~every third lamp)
			if i % 3 == 1:
				var bz := z + rng.randf_range(1.0, 2.0)
				b.add_cylinder(0.3, 0.3, 0.9, bin_col, Transform3D(Basis.IDENTITY, Vector3(x, 0.45 + sc.KERB_H, bz)), 10)
				b.add_cylinder(0.32, 0.32, 0.06, bin_col.darkened(0.15), Transform3D(Basis.IDENTITY, Vector3(x, 0.93 + sc.KERB_H, bz)), 10)
				ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, bz), 0.45)

			z += 18.0
			i += 1

	b.instance(chunk, "StreetProps", 0.8)
	var gmi := MeshInstance3D.new()
	gmi.name = "LampGlow"
	gmi.mesh = glow.commit_with(lamp_glow)
	chunk.add_child(gmi)

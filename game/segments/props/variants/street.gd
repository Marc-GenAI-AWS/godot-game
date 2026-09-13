class_name StreetProps
extends ChunkedLayer

# Street furniture: lamps with glowing heads, power poles with sagging wires
# across the street, a STOP sign with real lettering, bins, hydrants with
# caps, a mailbox, a bus bench.

var lamp_glow: StandardMaterial3D


func _init() -> void:
	seed_v = 3131


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
	var wood := Color(0.42, 0.34, 0.26)
	for side: float in [-1.0, 1.0]:
		var x := side * (sc.ROAD_HALF + 0.9)
		var z := -L + 6.0
		var i := 0
		while z < 0.0:
			if i % 2 == 0:
				# lamp: tapered pole, curved arm, glowing head
				b.add_cylinder(0.07, 0.13, 8.0, grey, Transform3D(Basis.IDENTITY, Vector3(x, 4.0 + sc.KERB_H, z)), 8)
				b.add_box(Vector3(1.8, 0.1, 0.1), grey, Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, side * 0.25), Vector3(x - side * 0.85, 8.1 + sc.KERB_H, z)))
				b.add_box_at(Vector3(0.6, 0.12, 0.34), grey, Vector3(x - side * 1.75, 8.0 + sc.KERB_H, z))
				glow.add_box_at(Vector3(0.5, 0.05, 0.28), Color(1, 1, 1), Vector3(x - side * 1.75, 7.93 + sc.KERB_H, z))
				ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, z), 0.3)
			if i % 6 == 3:
				b.add_cylinder(0.3, 0.3, 0.9, Color(0.2, 0.35, 0.25), Transform3D(Basis.IDENTITY, Vector3(x, 0.45 + sc.KERB_H, z + 1.5)), 10)
				b.add_cylinder(0.33, 0.33, 0.08, Color(0.15, 0.25, 0.18), Transform3D(Basis.IDENTITY, Vector3(x, 0.94 + sc.KERB_H, z + 1.5)), 10)
				ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, z + 1.5), 0.45)
			if i % 8 == 5:
				var hc := Color(0.85, 0.15, 0.12)
				b.add_cylinder(0.12, 0.14, 0.7, hc, Transform3D(Basis.IDENTITY, Vector3(x, 0.35 + sc.KERB_H, z - 2.0)), 8)
				b.add_cylinder(0.16, 0.16, 0.08, hc, Transform3D(Basis.IDENTITY, Vector3(x, 0.72 + sc.KERB_H, z - 2.0)), 8)
				b.add_cylinder(0.07, 0.07, 0.12, hc, Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, PI * 0.5), Vector3(x - side * 0.14, 0.5 + sc.KERB_H, z - 2.0)), 8)
				b.add_cylinder(0.07, 0.07, 0.12, hc, Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.5 + sc.KERB_H, z - 2.06)), 8)
				ctx.add_obstacle(chunk.global_transform * Vector3(x, 0, z - 2.0), 0.3)
			z += 12.0
			i += 1
	# power poles on the +X verge every 36 m, with three wires between them
	# and one span crossing the street every other pole
	var px := sc.WALK_OUT + 1.2
	var pz := -L + 9.0
	var k := 0
	while pz < 0.0:
		b.add_cylinder(0.12, 0.16, 9.5, wood, Transform3D(Basis.IDENTITY, Vector3(px, 4.75, pz)), 8)
		b.add_box_at(Vector3(1.6, 0.1, 0.1), wood.darkened(0.1), Vector3(px, 8.6, pz))
		for wx: float in [-0.6, 0.0, 0.6]:
			b.add_box_at(Vector3(0.02, 0.02, 36.0), Color(0.1, 0.1, 0.1), Vector3(px + wx, 8.62 - 0.25, pz + 18.0))   # slight sag approximated by lower midpoint
		if k % 2 == 0:
			b.add_cylinder(0.12, 0.16, 9.5, wood, Transform3D(Basis.IDENTITY, Vector3(-px, 4.75, pz)), 8)
			b.add_box(Vector3(px * 2.0 + 0.4, 0.02, 0.02), Color(0.1, 0.1, 0.1), Transform3D(Basis.IDENTITY, Vector3(0, 8.45, pz)))
			b.add_box(Vector3(px * 2.0 + 0.4, 0.02, 0.02), Color(0.1, 0.1, 0.1), Transform3D(Basis.IDENTITY, Vector3(0, 8.3, pz + 0.3)))
		pz += 36.0
		k += 1
	# stop sign at the crosswalk (pole + octagon), lettering via Label3D
	var cz := -L + 12.0
	var sp := Vector3(sc.ROAD_HALF + 0.7, 0.0, cz + 4.0)
	b.add_cylinder(0.05, 0.05, 2.6, grey, Transform3D(Basis.IDENTITY, sp + Vector3(0, 1.3 + sc.KERB_H, 0)), 6)
	b.add_cylinder(0.42, 0.42, 0.04, Color(0.8, 0.1, 0.1), Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, PI * 0.5), sp + Vector3(0, 2.7 + sc.KERB_H, 0)), 8)
	b.add_cylinder(0.36, 0.36, 0.05, Color(0.95, 0.95, 0.95), Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, PI * 0.5), sp + Vector3(0, 2.7 + sc.KERB_H, 0)), 8)
	b.add_cylinder(0.33, 0.33, 0.06, Color(0.8, 0.1, 0.1), Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, PI * 0.5), sp + Vector3(0, 2.7 + sc.KERB_H, 0)), 8)
	var label := Label3D.new()
	label.text = "STOP"
	label.font_size = 96
	label.pixel_size = 0.0028
	label.modulate = Color(1, 1, 1)
	label.position = sp + Vector3(0, 2.7 + sc.KERB_H, 0.045)   # faces +Z: the player approaches from +Z
	label.double_sided = false
	chunk.add_child(label)
	# street name sign on the same pole
	b.add_box_at(Vector3(0.9, 0.22, 0.03), Color(0.1, 0.3, 0.16), sp + Vector3(0, 3.35 + sc.KERB_H, 0))
	var name := Label3D.new()
	name.text = "ALTA VISTA AVE"
	name.font_size = 40
	name.pixel_size = 0.0035
	name.position = sp + Vector3(0, 3.35 + sc.KERB_H, 0.02)
	name.double_sided = false
	chunk.add_child(name)
	# bus bench + mailbox
	b.add_box_at(Vector3(0.5, 0.08, 1.8), Color(0.2, 0.3, 0.5), Vector3(sc.ROAD_HALF + 1.8, 0.5 + sc.KERB_H, -L * 0.5))
	b.add_box_at(Vector3(0.08, 0.5, 1.8), Color(0.2, 0.3, 0.5), Vector3(sc.ROAD_HALF + 2.0, 0.75 + sc.KERB_H, -L * 0.5))
	b.add_box_at(Vector3(0.5, 0.6, 0.6), Color(0.15, 0.25, 0.55), Vector3(-sc.ROAD_HALF - 1.0, 0.8 + sc.KERB_H, -L * 0.3))
	b.instance(chunk, "StreetProps", 0.8)
	var gmi := MeshInstance3D.new()
	gmi.mesh = glow.commit_with(lamp_glow)
	chunk.add_child(gmi)

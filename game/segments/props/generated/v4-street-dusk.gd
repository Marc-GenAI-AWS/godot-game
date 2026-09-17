extends ChunkedLayer

# Sparse street furniture: weathered wooden power poles strung with sagging
# wires, lamps every 24 m, grey bins, red hydrants and a STOP sign with
# real lettering. Never touches the road.

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

	var wood := Color(0.42, 0.33, 0.22)
	var wire_col := Color(0.15, 0.15, 0.15)
	var grey_bin := Color(0.4, 0.4, 0.42)
	var hydrant_red := Color(0.82, 0.12, 0.1)

	# --- lamps every 24 m ---
	for side: float in [-1.0, 1.0]:
		var lx := side * 6.9
		var lz := -L + rng.randf_range(2.0, 6.0)
		while lz < 0.0:
			b.add_cylinder(0.07, 0.12, 8.0, Color(0.3, 0.3, 0.32), Transform3D(Basis.IDENTITY, Vector3(lx, 4.0 + sc.KERB_H, lz)), 8)
			b.add_box(Vector3(1.6, 0.09, 0.09), Color(0.3, 0.3, 0.32), Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, side * 0.25), Vector3(lx - side * 0.75, 8.0 + sc.KERB_H, lz)))
			b.add_box_at(Vector3(0.55, 0.11, 0.32), Color(0.3, 0.3, 0.32), Vector3(lx - side * 1.5, 7.9 + sc.KERB_H, lz))
			glow.add_box_at(Vector3(0.46, 0.05, 0.26), Color(1, 1, 1), Vector3(lx - side * 1.5, 7.84 + sc.KERB_H, lz))
			ctx.add_obstacle(chunk.global_transform * Vector3(lx, 0, lz), 0.3)
			lz += 24.0

	# --- weathered wooden power poles with sagging wires ---
	for side: float in [-1.0, 1.0]:
		var px := side * 10.2
		var pz := -L + rng.randf_range(4.0, 10.0)
		var prev_top := Vector3.ZERO
		var have_prev := false
		while pz < 0.0:
			b.add_cylinder(0.14, 0.2, 7.5, wood, Transform3D(Basis.IDENTITY, Vector3(px, 3.75, pz)), 8)
			b.add_box(Vector3(1.4, 0.1, 0.1), wood, Transform3D(Basis.IDENTITY, Vector3(px, 7.2, pz)))
			var top := Vector3(px, 7.3, pz)
			if have_prev:
				_wire(b, prev_top, top, wire_col)
			prev_top = top
			have_prev = true
			ctx.add_obstacle(chunk.global_transform * Vector3(px, 0, pz), 0.25)
			pz += 40.0

	# --- grey bins, sparse spacing ---
	for side: float in [-1.0, 1.0]:
		var bx := side * 6.9
		var bz := -L + rng.randf_range(8.0, 16.0)
		while bz < 0.0:
			b.add_cylinder(0.28, 0.28, 0.85, grey_bin, Transform3D(Basis.IDENTITY, Vector3(bx, 0.425 + sc.KERB_H, bz)), 10)
			b.add_cylinder(0.3, 0.3, 0.05, grey_bin.darkened(0.15), Transform3D(Basis.IDENTITY, Vector3(bx, 0.85 + sc.KERB_H, bz)), 10)
			ctx.add_obstacle(chunk.global_transform * Vector3(bx, 0, bz), 0.45)
			bz += rng.randf_range(40.0, 60.0)

	# --- red hydrants, sparser still ---
	for side: float in [-1.0, 1.0]:
		var hx := side * 6.9
		var hz := -L + rng.randf_range(12.0, 20.0)
		while hz < 0.0:
			b.add_cylinder(0.11, 0.13, 0.6, hydrant_red, Transform3D(Basis.IDENTITY, Vector3(hx, 0.3 + sc.KERB_H, hz)), 8)
			b.add_box_at(Vector3(0.28, 0.06, 0.06), hydrant_red, Vector3(hx, 0.55 + sc.KERB_H, hz))
			b.add_cylinder(0.05, 0.05, 0.14, hydrant_red.darkened(0.1), Transform3D(Basis.IDENTITY, Vector3(hx, 0.7 + sc.KERB_H, hz)), 6)
			ctx.add_obstacle(chunk.global_transform * Vector3(hx, 0, hz), 0.3)
			hz += rng.randf_range(55.0, 75.0)

	# --- one STOP sign per chunk ---
	var stop_side: float = 1.0 if rng.randf() < 0.5 else -1.0
	var stop_x := stop_side * 6.9
	var stop_z := -L * 0.5 + rng.randf_range(-6.0, 6.0)
	b.add_cylinder(0.05, 0.06, 2.2, Color(0.5, 0.5, 0.5), Transform3D(Basis.IDENTITY, Vector3(stop_x, 1.1 + sc.KERB_H, stop_z)), 8)
	b.add_box_at(Vector3(0.55, 0.55, 0.04), Color(0.8, 0.1, 0.1), Vector3(stop_x, 2.2 + sc.KERB_H, stop_z))
	var stop_label := Label3D.new()
	stop_label.text = "STOP"
	stop_label.font_size = 32
	stop_label.double_sided = false
	stop_label.pixel_size = 0.006
	stop_label.modulate = Color(1, 1, 1)
	stop_label.position = Vector3(stop_x, 2.2 + sc.KERB_H, stop_z + 0.03)
	stop_label.rotation.y = PI
	chunk.add_child(stop_label)
	ctx.add_obstacle(chunk.global_transform * Vector3(stop_x, 0, stop_z), 0.2)

	b.instance(chunk, "StreetProps", 0.85)
	var gmi := MeshInstance3D.new()
	gmi.name = "LampGlow"
	gmi.mesh = glow.commit_with(lamp_glow)
	chunk.add_child(gmi)


func _wire(batch: MeshBatch, p0: Vector3, p1: Vector3, col: Color) -> void:
	var segs := 6
	var prev := p0
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var pt := p0.lerp(p1, t)
		pt.y -= sin(t * PI) * 0.4
		var mid := (prev + pt) * 0.5
		var diff := pt - prev
		var length := diff.length()
		if length > 0.001:
			var dir := diff.normalized()
			var up_ref := Vector3.UP
			if abs(dir.dot(up_ref)) > 0.99:
				up_ref = Vector3.RIGHT
			var basis := Basis.looking_at(dir, up_ref)
			basis = basis * Basis(Vector3.RIGHT, PI * 0.5)
			batch.add_cylinder(0.015, 0.015, length, col, Transform3D(basis, mid), 4)
		prev = pt

extends ChunkedLayer

# Street furniture: black lamps every 18 m, power poles with sagging wires,
# blue bins, yellow hydrants, a red octagonal STOP sign with real lettering,
# plus a mailbox and a bus bench for variety. Never touches the road.

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

	var black := Color(0.06, 0.06, 0.07)
	var blue := Color(0.15, 0.35, 0.75)
	var yellow := Color(0.95, 0.82, 0.08)
	var grey := Color(0.3, 0.3, 0.32)
	var wood := Color(0.55, 0.35, 0.18)
	var wire_col := Color(0.08, 0.08, 0.08)

	for side: float in [-1.0, 1.0]:
		var x_kerb := side * 6.9
		var x_verge := side * 10.2

		# --- lamps every 18 m ---
		var lz := -L + 6.0
		while lz < 0.0:
			b.add_cylinder(0.07, 0.13, 8.0, black, Transform3D(Basis.IDENTITY, Vector3(x_kerb, 4.0 + sc.KERB_H, lz)), 8)
			b.add_box(Vector3(1.8, 0.1, 0.1), black, Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, side * 0.25), Vector3(x_kerb - side * 0.85, 8.1 + sc.KERB_H, lz)))
			b.add_box_at(Vector3(0.6, 0.12, 0.34), black, Vector3(x_kerb - side * 1.75, 8.0 + sc.KERB_H, lz))
			glow.add_box_at(Vector3(0.5, 0.05, 0.28), Color(1, 1, 1), Vector3(x_kerb - side * 1.75, 7.93 + sc.KERB_H, lz))
			ctx.add_obstacle(chunk.global_transform * Vector3(x_kerb, 0, lz), 0.3)
			lz += 18.0

		# --- power poles on the verge, wired together ---
		var pole_h := 7.5
		var pz := -L + 10.0
		var prev_top := Vector3.ZERO
		var have_prev := false
		while pz < 0.0:
			b.add_cylinder(0.1, 0.16, pole_h, grey, Transform3D(Basis.IDENTITY, Vector3(x_verge, pole_h * 0.5 + sc.KERB_H, pz)), 8)
			b.add_box(Vector3(1.4, 0.08, 0.08), grey, Transform3D(Basis.IDENTITY, Vector3(x_verge, pole_h - 0.3 + sc.KERB_H, pz)))
			var top := Vector3(x_verge, pole_h - 0.3 + sc.KERB_H, pz)
			if have_prev:
				_wire(b, prev_top, top, wire_col)
			prev_top = top
			have_prev = true
			ctx.add_obstacle(chunk.global_transform * Vector3(x_verge, 0, pz), 0.3)
			pz += 40.0

		# --- bins, roughly every 24 m, offset from lamps ---
		var bz := -L + 14.0
		while bz < 0.0:
			b.add_cylinder(0.3, 0.3, 0.9, blue, Transform3D(Basis.IDENTITY, Vector3(x_kerb, 0.45 + sc.KERB_H, bz)), 10)
			b.add_cylinder(0.32, 0.32, 0.05, blue.darkened(0.2), Transform3D(Basis.IDENTITY, Vector3(x_kerb, 0.9 + sc.KERB_H, bz)), 10)
			ctx.add_obstacle(chunk.global_transform * Vector3(x_kerb, 0, bz), 0.45)
			bz += 24.0

		# --- hydrants, roughly every 30 m ---
		var hz := -L + 22.0
		while hz < 0.0:
			b.add_cylinder(0.12, 0.14, 0.55, yellow, Transform3D(Basis.IDENTITY, Vector3(x_kerb, 0.28 + sc.KERB_H, hz)), 8)
			b.add_cylinder(0.16, 0.16, 0.1, yellow.darkened(0.15), Transform3D(Basis.IDENTITY, Vector3(x_kerb, 0.55 + sc.KERB_H, hz)), 8)
			b.add_box_at(Vector3(0.32, 0.08, 0.08), yellow.darkened(0.1), Vector3(x_kerb, 0.42 + sc.KERB_H, hz))
			ctx.add_obstacle(chunk.global_transform * Vector3(x_kerb, 0, hz), 0.3)
			hz += 30.0

	# --- STOP sign near the chunk start ---
	var sign_side := -1.0
	var sign_x := sign_side * 6.9
	var sign_z := -L + 3.0
	b.add_cylinder(0.05, 0.05, 2.2, grey, Transform3D(Basis.IDENTITY, Vector3(sign_x, 1.1 + sc.KERB_H, sign_z)), 8)
	b.add_box_at(Vector3(0.55, 0.55, 0.04), Color(0.82, 0.1, 0.1), Vector3(sign_x, 2.25 + sc.KERB_H, sign_z))
	ctx.add_obstacle(chunk.global_transform * Vector3(sign_x, 0, sign_z), 0.3)
	var stop_label := Label3D.new()
	stop_label.text = "STOP"
	stop_label.font_size = 48
	stop_label.double_sided = false
	stop_label.modulate = Color(1, 1, 1)
	stop_label.position = Vector3(sign_x, 2.25 + sc.KERB_H, sign_z + 0.03)
	stop_label.rotation.y = PI
	chunk.add_child(stop_label)

	# --- mailbox ---
	var mail_side := 1.0
	var mail_x := mail_side * 6.9
	var mail_z := -L + 40.0
	b.add_box_at(Vector3(0.3, 0.55, 0.4), Color(0.15, 0.25, 0.55), Vector3(mail_x, 0.28 + sc.KERB_H, mail_z))
	b.add_cylinder(0.16, 0.16, 0.35, Color(0.15, 0.25, 0.55), Transform3D(Basis.IDENTITY, Vector3(mail_x, 0.7 + sc.KERB_H, mail_z)), 10)
	b.add_box_at(Vector3(0.32, 0.05, 0.4), Color(0.1, 0.1, 0.1), Vector3(mail_x, 0.92 + sc.KERB_H, mail_z))
	ctx.add_obstacle(chunk.global_transform * Vector3(mail_x, 0, mail_z), 0.3)

	# --- bus bench ---
	var bench_side := -1.0
	var bench_x := bench_side * 6.9
	var bench_z := -L + 90.0
	var bench_col := Color(0.45, 0.35, 0.25)
	b.add_box_at(Vector3(1.6, 0.06, 0.45), bench_col, Vector3(bench_x, 0.45 + sc.KERB_H, bench_z))
	b.add_box_at(Vector3(1.6, 0.4, 0.06), bench_col, Vector3(bench_x, 0.65 + sc.KERB_H, bench_z - 0.2))
	for lx: float in [-0.65, 0.65]:
		b.add_box_at(Vector3(0.06, 0.45, 0.4), grey, Vector3(bench_x + lx, 0.22 + sc.KERB_H, bench_z))
	ctx.add_obstacle(chunk.global_transform * Vector3(bench_x, 0, bench_z), 0.5)

	b.instance(chunk, "StreetProps", 0.8)
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
		pt.y -= sin(t * PI) * 0.5
		var mid := (prev + pt) * 0.5
		var diff := pt - prev
		var length := diff.length()
		if length > 0.001:
			var dir := diff.normalized()
			var up := Vector3.UP
			if abs(dir.dot(up)) > 0.99:
				up = Vector3.RIGHT
			var basis := Basis.looking_at(dir, up)
			var rot := basis * Basis(Vector3.RIGHT, PI * 0.5)
			batch.add_box(Vector3(0.025, 0.025, length), col, Transform3D(rot, mid))
		prev = pt

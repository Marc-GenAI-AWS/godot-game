extends ChunkedLayer

# Street furniture, normal density: black lamps every 18 m, blue bins, yellow
# hydrants, plus power poles with sagging wires, a STOP sign, a mailbox and a
# bus bench for variety. All static geometry batched into a couple of draw
# calls; lamp glow gets its own emissive material.

var lamp_glow: StandardMaterial3D


func _init() -> void:
	seed_v = 4187


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
	var yellow := Color(0.95, 0.8, 0.1)
	var wood := Color(0.4, 0.3, 0.2)
	var wire_col := Color(0.08, 0.08, 0.08)

	# --- lamps every 18 m, alternating sides ---
	for side: float in [-1.0, 1.0]:
		var lx := side * (sc.ROAD_HALF + 0.9)
		var lz := -L + rng.randf_range(2.0, 5.0)
		while lz < 0.0:
			_lamp(b, glow, lx, lz, side, sc, black)
			ctx.add_obstacle(chunk.global_transform * Vector3(lx, 0, lz), 0.3)
			lz += 18.0

	# --- bins, roughly every 28 m, offset from lamps ---
	for side: float in [-1.0, 1.0]:
		var bx := side * (sc.ROAD_HALF + 0.9)
		var bz := -L + rng.randf_range(8.0, 14.0)
		while bz < 0.0:
			_bin(b, bx, bz, sc, blue)
			ctx.add_obstacle(chunk.global_transform * Vector3(bx, 0, bz), 0.45)
			bz += 28.0

	# --- hydrants, roughly every 34 m ---
	for side: float in [-1.0, 1.0]:
		var hx := side * (sc.ROAD_HALF + 0.9)
		var hz := -L + rng.randf_range(14.0, 22.0)
		while hz < 0.0:
			_hydrant(b, hx, hz, sc, yellow)
			ctx.add_obstacle(chunk.global_transform * Vector3(hx, 0, hz), 0.3)
			hz += 34.0

	# --- power poles on the verge with sagging wires ---
	for side: float in [-1.0, 1.0]:
		var px := side * 10.2
		var pz := -L + rng.randf_range(4.0, 8.0)
		var prev_z: float = -1.0
		var have_prev := false
		while pz < 0.0:
			b.add_cylinder(0.1, 0.16, 7.5, black, Transform3D(Basis.IDENTITY, Vector3(px, 3.75, pz)), 8)
			b.add_box(Vector3(1.4, 0.08, 0.08), black, Transform3D(Basis.IDENTITY, Vector3(px, 7.3, pz)))
			ctx.add_obstacle(chunk.global_transform * Vector3(px, 0, pz), 0.3)
			if have_prev:
				_wire(b, px, prev_z, pz, sc, wire_col)
			prev_z = pz
			have_prev = true
			pz += 40.0

	# --- STOP sign near the chunk start ---
	var stop_side: float = -1.0
	var stop_x := stop_side * (sc.ROAD_HALF + 0.9)
	var stop_z := -L + 3.0
	_stop_sign(chunk, b, stop_x, stop_z, sc)
	ctx.add_obstacle(chunk.global_transform * Vector3(stop_x, 0, stop_z), 0.2)

	# --- mailbox ---
	var mail_side: float = 1.0
	var mail_x := mail_side * (sc.ROAD_HALF + 0.9)
	var mail_z := -L + 24.0
	_mailbox(b, mail_x, mail_z, sc, black)
	ctx.add_obstacle(chunk.global_transform * Vector3(mail_x, 0, mail_z), 0.3)

	# --- bus bench ---
	var bench_side: float = -1.0
	var bench_x := bench_side * (sc.ROAD_HALF + 0.9)
	var bench_z := -L + 46.0
	_bench(b, bench_x, bench_z, sc, wood)
	ctx.add_obstacle(chunk.global_transform * Vector3(bench_x, 0, bench_z), 0.6)

	b.instance(chunk, "StreetProps", 0.8)
	var gmi := MeshInstance3D.new()
	gmi.name = "LampGlow"
	gmi.mesh = glow.commit_with(lamp_glow)
	chunk.add_child(gmi)


func _lamp(b: MeshBatch, glow: MeshBatch, x: float, z: float, side: float, sc: StreetContext, col: Color) -> void:
	var h := 8.0
	b.add_cylinder(0.07, 0.13, h, col, Transform3D(Basis.IDENTITY, Vector3(x, h * 0.5 + sc.KERB_H, z)), 8)
	var arm_tilt := Basis.IDENTITY.rotated(Vector3.FORWARD, side * 0.25)
	b.add_box(Vector3(1.8, 0.1, 0.1), col, Transform3D(arm_tilt, Vector3(x - side * 0.85, h + 0.1 + sc.KERB_H, z)))
	b.add_box_at(Vector3(0.6, 0.12, 0.34), col, Vector3(x - side * 1.75, h + sc.KERB_H, z))
	glow.add_box_at(Vector3(0.5, 0.05, 0.28), Color(1, 1, 1), Vector3(x - side * 1.75, h - 0.07 + sc.KERB_H, z))


func _bin(b: MeshBatch, x: float, z: float, sc: StreetContext, col: Color) -> void:
	b.add_cylinder(0.3, 0.3, 0.9, col, Transform3D(Basis.IDENTITY, Vector3(x, 0.45 + sc.KERB_H, z)), 10)
	b.add_cylinder(0.32, 0.32, 0.05, col.darkened(0.15), Transform3D(Basis.IDENTITY, Vector3(x, 0.92 + sc.KERB_H, z)), 10)


func _hydrant(b: MeshBatch, x: float, z: float, sc: StreetContext, col: Color) -> void:
	b.add_cylinder(0.12, 0.14, 0.7, col, Transform3D(Basis.IDENTITY, Vector3(x, 0.35 + sc.KERB_H, z)), 8)
	b.add_cylinder(0.1, 0.12, 0.15, col.darkened(0.1), Transform3D(Basis.IDENTITY, Vector3(x, 0.72 + sc.KERB_H, z)), 8)
	b.add_box_at(Vector3(0.28, 0.08, 0.08), col, Vector3(x, 0.5 + sc.KERB_H, z))
	b.add_cylinder(0.05, 0.05, 0.08, col.darkened(0.15), Transform3D(Basis.IDENTITY, Vector3(x + 0.14, 0.55 + sc.KERB_H, z)), 6)


func _wire(b: MeshBatch, x: float, z0: float, z1: float, sc: StreetContext, col: Color) -> void:
	var segs := 6
	var prev := Vector3(x, sc.KERB_H, z0)
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var zz: float = lerp(z0, z1, t)
		var sag := sin(t * PI) * 0.4
		var cur := Vector3(x, sc.KERB_H, zz) - Vector3(0, sag, 0)
		var mid := (prev + cur) * 0.5
		var diff := cur - prev
		var length := diff.length()
		if length > 0.001:
			var dir := diff.normalized()
			var up_ref := Vector3.UP
			if abs(dir.dot(up_ref)) > 0.99:
				up_ref = Vector3.RIGHT
			var basis := Basis.looking_at(dir, up_ref)
			var rot := basis * Basis(Vector3.RIGHT, PI * 0.5)
			b.add_box(Vector3(0.02, 0.02, length), col, Transform3D(rot, mid))
		prev = cur


func _stop_sign(chunk: Node3D, b: MeshBatch, x: float, z: float, sc: StreetContext) -> void:
	var post_h := 2.2
	b.add_cylinder(0.05, 0.06, post_h, Color(0.5, 0.5, 0.5), Transform3D(Basis.IDENTITY, Vector3(x, post_h * 0.5 + sc.KERB_H, z)), 8)
	b.add_box(Vector3(0.55, 0.55, 0.04), Color(0.75, 0.1, 0.1), Transform3D(Basis.IDENTITY, Vector3(x, post_h + sc.KERB_H, z)))
	var lbl := Label3D.new()
	lbl.text = "STOP"
	lbl.font_size = 32
	lbl.double_sided = false
	lbl.modulate = Color(1, 1, 1)
	lbl.position = Vector3(x, post_h + sc.KERB_H, z + 0.03)
	chunk.add_child(lbl)


func _mailbox(b: MeshBatch, x: float, z: float, sc: StreetContext, col: Color) -> void:
	b.add_cylinder(0.05, 0.05, 0.9, Color(0.3, 0.3, 0.3), Transform3D(Basis.IDENTITY, Vector3(x, 0.45 + sc.KERB_H, z)), 8)
	b.add_box(Vector3(0.4, 0.5, 0.35), col, Transform3D(Basis.IDENTITY, Vector3(x, 1.05 + sc.KERB_H, z)))
	b.add_box(Vector3(0.42, 0.06, 0.37), col.darkened(0.15), Transform3D(Basis.IDENTITY, Vector3(x, 1.15 + sc.KERB_H, z)))


func _bench(b: MeshBatch, x: float, z: float, sc: StreetContext, wood: Color) -> void:
	b.add_box(Vector3(1.6, 0.06, 0.4), wood, Transform3D(Basis.IDENTITY, Vector3(x, 0.45 + sc.KERB_H, z)))
	b.add_box(Vector3(1.6, 0.5, 0.06), wood, Transform3D(Basis.IDENTITY, Vector3(x, 0.7 + sc.KERB_H, z - 0.18)))
	for dx in [-0.7, 0.7]:
		b.add_box(Vector3(0.06, 0.45, 0.4), Color(0.25, 0.25, 0.27), Transform3D(Basis.IDENTITY, Vector3(x + dx, 0.225 + sc.KERB_H, z)))

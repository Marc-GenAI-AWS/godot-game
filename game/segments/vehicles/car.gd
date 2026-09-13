class_name Car
extends RefCounted

# Procedural low-poly cars: hatchback, sedan, suv, pickup. Returns a Node3D
# (facing -Z, origin on the ground at the axle midpoint) with meta:
#   wheels: Array[Node3D] (front two first), body_mesh, length, width.
# Materials are split so paint is glossy and sky-reflecting, glass is dark
# and tinted with a simple interior behind it, chrome is metallic, and the
# lights glow. A soft contact shadow sits under the body.

const KINDS := {
	"hatch": {"len": 3.7, "w": 1.72, "body_h": 0.6, "cab_l": 2.0, "cab_off": 0.15, "cab_h": 0.6, "wheel": 0.32, "base": 6.0},
	"sedan": {"len": 4.7, "w": 1.82, "body_h": 0.58, "cab_l": 2.2, "cab_off": 0.0, "cab_h": 0.56, "wheel": 0.33, "base": 7.0},
	"suv": {"len": 4.8, "w": 1.95, "body_h": 0.78, "cab_l": 2.9, "cab_off": -0.2, "cab_h": 0.7, "wheel": 0.38, "base": 6.0},
	"pickup": {"len": 5.4, "w": 1.95, "body_h": 0.76, "cab_l": 1.7, "cab_off": 0.9, "cab_h": 0.68, "wheel": 0.4, "base": 4.0},
}
const PAINTS := [Color(0.95, 0.75, 0.1), Color(0.85, 0.12, 0.12), Color(0.92, 0.92, 0.92), Color(0.12, 0.12, 0.14), Color(0.55, 0.58, 0.62),
	Color(0.15, 0.3, 0.7), Color(0.2, 0.45, 0.35), Color(0.7, 0.7, 0.72), Color(0.5, 0.2, 0.15), Color(0.9, 0.5, 0.15)]

static var _paint_mat: StandardMaterial3D
static var _glass_mat: StandardMaterial3D
static var _chrome_mat: StandardMaterial3D
static var _trim_mat: StandardMaterial3D
static var _light_mat: StandardMaterial3D
static var _shadow_mat: StandardMaterial3D


static func _mats() -> void:
	if _paint_mat:
		return
	_paint_mat = StandardMaterial3D.new()
	_paint_mat.vertex_color_use_as_albedo = true
	_paint_mat.roughness = 0.28
	_paint_mat.metallic = 0.2
	_paint_mat.metallic_specular = 0.7
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.vertex_color_use_as_albedo = true
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.albedo_color = Color(1, 1, 1, 0.5)
	_glass_mat.roughness = 0.06
	_glass_mat.metallic = 0.3
	_glass_mat.metallic_specular = 0.9
	_chrome_mat = StandardMaterial3D.new()
	_chrome_mat.vertex_color_use_as_albedo = true
	_chrome_mat.roughness = 0.15
	_chrome_mat.metallic = 0.95
	_trim_mat = StandardMaterial3D.new()
	_trim_mat.vertex_color_use_as_albedo = true
	_trim_mat.roughness = 0.9
	_light_mat = StandardMaterial3D.new()
	_light_mat.vertex_color_use_as_albedo = true
	_light_mat.roughness = 0.2
	_light_mat.emission_enabled = true
	_light_mat.emission = Color(1, 1, 1)
	_light_mat.emission_energy_multiplier = 0.35
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.albedo_color = Color(0, 0, 0, 0.55)
	var d := GradientTexture2D.new()
	d.fill = GradientTexture2D.FILL_RADIAL
	d.fill_from = Vector2(0.5, 0.5)
	d.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.55, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0))
	d.gradient = g
	d.width = 64
	d.height = 64
	_shadow_mat.albedo_texture = ImageTexture.create_from_image(d.get_image())


# Box with chamfered top edges: main box plus 45° strips along the four top edges.
static func _soft_box(b: MeshBatch, size: Vector3, c: Color, pos: Vector3, ch := 0.08) -> void:
	b.add_box_at(Vector3(size.x - ch * 2.0, size.y, size.z), c, pos)
	b.add_box_at(Vector3(size.x, size.y - ch * 2.0, size.z), c, pos)
	b.add_box_at(Vector3(size.x - ch * 2.0, size.y - ch * 2.0, size.z + ch * 2.0 * 0.6), c, pos)
	var s := ch * 1.4142
	for sx: float in [-1.0, 1.0]:
		b.add_box(Vector3(s, s, size.z), c, Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, PI * 0.25), pos + Vector3(sx * (size.x * 0.5 - ch), size.y * 0.5 - ch, 0)))
		b.add_box(Vector3(s, s, size.z), c, Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, PI * 0.25), pos + Vector3(sx * (size.x * 0.5 - ch), -size.y * 0.5 + ch, 0)))
	for sz: float in [-1.0, 1.0]:
		b.add_box(Vector3(size.x - ch * 2.0, s, s), c, Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, PI * 0.25), pos + Vector3(0, size.y * 0.5 - ch, sz * (size.z * 0.5 - ch))))


static func build(kind: String, paint: Color, roof: Color = Color(-1, 0, 0), plate := "") -> Node3D:
	_mats()
	var k: Dictionary = KINDS.get(kind, KINDS["sedan"])
	var L: float = k["len"]
	var W: float = k["w"]
	var bh: float = k["body_h"]
	var wr: float = k["wheel"]
	var root := Node3D.new()
	root.set_meta("length", L)
	root.set_meta("width", W)
	var body_root := Node3D.new()
	body_root.name = "Body"
	root.add_child(body_root)
	var pb := MeshBatch.new()     # paint
	var gb := MeshBatch.new()     # glass
	var cb := MeshBatch.new()     # chrome
	var tb := MeshBatch.new()     # matte trim / tyres / interior
	var lb := MeshBatch.new()     # lights
	var glass := Color(0.35, 0.42, 0.5)
	var trim := Color(0.07, 0.07, 0.07)
	var roof_c: Color = paint if roof.r < 0.0 else roof
	var ground := wr
	# lower body, chamfered, with a darker sill line and bumpers
	_soft_box(pb, Vector3(W, bh, L), paint, Vector3(0, ground + bh * 0.5, 0), 0.09)
	tb.add_box_at(Vector3(W * 1.01, 0.1, L * 0.98), trim, Vector3(0, ground + 0.06, 0))
	tb.add_box_at(Vector3(W * 0.98, 0.26, 0.3), trim, Vector3(0, ground + 0.22, -L * 0.5 - 0.02))
	tb.add_box_at(Vector3(W * 0.98, 0.26, 0.3), trim, Vector3(0, ground + 0.22, L * 0.5 + 0.02))
	pb.add_box_at(Vector3(W * 0.99, 0.2, 0.32), paint, Vector3(0, ground + 0.43, -L * 0.5 - 0.02))
	pb.add_box_at(Vector3(W * 0.99, 0.2, 0.32), paint, Vector3(0, ground + 0.43, L * 0.5 + 0.02))
	tb.add_box_at(Vector3(W * 0.55, 0.1, 0.06), trim, Vector3(0, ground + 0.2, L * 0.5 + 0.2))      # rear bumper insert
	tb.add_box_at(Vector3(W * 0.55, 0.14, 0.06), trim, Vector3(0, ground + 0.24, -L * 0.5 - 0.2))   # grille
	# cabin: an open glasshouse - roof slab, pillars, thin glass panels and a
	# dark interior, so a driver in the seat is visible from outside
	var cab_l: float = k["cab_l"]
	var cab_h: float = k["cab_h"]
	var cz: float = k["cab_off"]
	var belt := ground + bh                       # beltline: top of the lower body
	var roof_top := belt + cab_h * 1.18
	var roof_under := roof_top - 0.09
	var gh := roof_under - belt                   # glass band height
	var gy := belt + gh * 0.5
	_soft_box(pb, Vector3(W * 0.9, 0.09, cab_l * 0.95), roof_c, Vector3(0, roof_top - 0.045, cz), 0.04)
	cb.add_box_at(Vector3(W * 0.935, 0.02, cab_l * 0.92), Color(0.85, 0.85, 0.88), Vector3(0, belt + 0.01, cz))   # sill trim
	# side glass and pillars (A/B/C) in roof colour
	for sx: float in [-1.0, 1.0]:
		gb.add_box_at(Vector3(0.02, gh - 0.02, cab_l * 0.92), glass, Vector3(sx * W * 0.45, gy, cz))
		for pz: float in [-0.47, 0.0, 0.47]:
			pb.add_box_at(Vector3(0.06, gh, 0.09), roof_c, Vector3(sx * W * 0.455, gy, cz + pz * cab_l))
	# windscreen and rear glass: raked panels sealing the roof edges to the body
	var zf_roof := cz - cab_l * 0.475
	var zr_roof := cz + cab_l * 0.475
	var ws_run := 0.5
	var rw_run := 0.12 if kind == "pickup" else 0.35
	var ws_len := sqrt(gh * gh + ws_run * ws_run)
	var rw_len := sqrt(gh * gh + rw_run * rw_run)
	gb.add_box(Vector3(W * 0.86, 0.025, ws_len), glass, Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, -atan2(ws_run, gh)), Vector3(0, gy, zf_roof - ws_run * 0.5)))
	gb.add_box(Vector3(W * 0.86, 0.025, rw_len), glass, Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, atan2(rw_run, gh)), Vector3(0, gy, zr_roof + rw_run * 0.5)))
	pb.add_box_at(Vector3(W * 0.9, 0.05, ws_run + 0.1), paint, Vector3(0, belt - 0.02, zf_roof - ws_run * 0.5))   # cowl
	pb.add_box_at(Vector3(W * 0.9, 0.05, rw_run + 0.1), paint, Vector3(0, belt - 0.02, zr_roof + rw_run * 0.5))   # rear deck
	# interior: dark floor pan at the beltline, two seats with backrests and
	# headrests rising into the glass band, dashboard, steering wheel
	var seat := Color(0.16, 0.14, 0.12)
	tb.add_box_at(Vector3(W * 0.88, 0.02, cab_l * 0.9), Color(0.08, 0.08, 0.09), Vector3(0, belt + 0.005, cz))
	for sx: float in [-0.32, 0.32]:
		tb.add_box_at(Vector3(0.44, 0.06, 0.5), seat, Vector3(sx, belt + 0.03, cz - 0.1))
		tb.add_box_at(Vector3(0.44, gh * 0.62, 0.12), seat, Vector3(sx, belt + gh * 0.31, cz + 0.15))
		tb.add_box_at(Vector3(0.24, 0.14, 0.1), seat, Vector3(sx, belt + gh * 0.62 + 0.07, cz + 0.16))
	tb.add_box_at(Vector3(W * 0.8, 0.1, 0.4), Color(0.1, 0.1, 0.11), Vector3(0, belt + 0.05, zf_roof - 0.05))
	cb.add_cylinder(0.17, 0.17, 0.03, Color(0.2, 0.2, 0.22), Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, PI * 0.4), Vector3(-0.32, belt + 0.28, zf_roof + 0.12)), 12)
	# hood and trunk lids (paint), raked
	var hood_l := maxf((L * 0.5) - (cab_l * 0.5 - cz) - 0.3, 0.4)
	pb.add_box_at(Vector3(W * 0.94, 0.08, hood_l), paint, Vector3(0, ground + bh + 0.03, cz - cab_l * 0.5 - hood_l * 0.5 - 0.1))
	if kind == "pickup":
		pb.add_box_at(Vector3(W * 0.9, 0.35, 1.9), paint.darkened(0.15), Vector3(0, ground + bh + 0.17, L * 0.5 - 1.05))
		tb.add_box_at(Vector3(W * 0.7, 0.05, 1.6), trim, Vector3(0, ground + bh + 0.36, L * 0.5 - 1.05))
	# lights (emissive), plate, mirrors (chrome), exhausts, badge
	for sx: float in [-1.0, 1.0]:
		lb.add_box_at(Vector3(0.32, 0.16, 0.06), Color(0.95, 0.95, 0.85), Vector3(sx * (W * 0.5 - 0.26), ground + bh * 0.72, -L * 0.5 - 0.03))
		lb.add_box_at(Vector3(0.3, 0.2, 0.06), Color(0.85, 0.08, 0.08), Vector3(sx * (W * 0.5 - 0.25), ground + bh * 0.72, L * 0.5 + 0.03))
		cb.add_box_at(Vector3(0.05, 0.06, 0.03), Color(0.9, 0.9, 0.9), Vector3(sx * (W * 0.5 - 0.25), ground + bh * 0.72, L * 0.5 + 0.065))
		cb.add_box_at(Vector3(0.14, 0.09, 0.2), Color(0.9, 0.9, 0.92), Vector3(sx * (W * 0.5 + 0.1), ground + bh + 0.1, cz - cab_l * 0.5 + 0.25))
		cb.add_cylinder(0.04, 0.04, 0.14, Color(0.75, 0.75, 0.78), Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, PI * 0.5), Vector3(sx * 0.16, ground + 0.13, L * 0.5 + 0.12)), 8)
	lb.add_box_at(Vector3(0.44, 0.14, 0.03), Color(0.96, 0.96, 0.94), Vector3(0, ground + bh * 0.45, L * 0.5 + 0.14))
	lb.add_box_at(Vector3(0.44, 0.14, 0.03), Color(0.96, 0.96, 0.94), Vector3(0, ground + bh * 0.45, -L * 0.5 - 0.14))
	cb.add_cylinder(0.05, 0.05, 0.02, Color(0.9, 0.9, 0.9), Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, PI * 0.5), Vector3(0, ground + bh * 0.9, L * 0.5 + 0.1)), 10)
	# wheel arches (matte) so wheels sit in a recess, door seams
	var ax := L * 0.5 - 0.78
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			tb.add_box_at(Vector3(0.3, wr * 1.6, wr * 2.4), trim, Vector3(sx * (W * 0.5 - 0.1), ground + wr * 0.3, sz * ax))
	for sx: float in [-1.0, 1.0]:
		tb.add_box_at(Vector3(0.01, bh * 0.8, 0.02), trim, Vector3(sx * (W * 0.5 + 0.005), ground + bh * 0.5, cz + 0.05))
		tb.add_box_at(Vector3(0.01, bh * 0.8, 0.02), trim, Vector3(sx * (W * 0.5 + 0.005), ground + bh * 0.5, cz - cab_l * 0.5 + 0.1))
	# commit batches
	var paint_mi := MeshInstance3D.new()
	paint_mi.mesh = pb.commit_with(_paint_mat)
	body_root.add_child(paint_mi)
	for pair in [[tb, _trim_mat], [cb, _chrome_mat], [lb, _light_mat]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (pair[0] as MeshBatch).commit_with(pair[1])
		body_root.add_child(mi)
	var glass_mi := MeshInstance3D.new()
	glass_mi.mesh = gb.commit_with(_glass_mat)
	glass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body_root.add_child(glass_mi)
	# contact shadow blob under the body
	var q := QuadMesh.new()
	q.size = Vector2(W * 1.5, L * 1.15)
	q.orientation = PlaneMesh.FACE_Y
	q.material = _shadow_mat
	var sh := MeshInstance3D.new()
	sh.mesh = q
	sh.position.y = 0.015
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sh)
	root.set_meta("body_mesh", body_root)
	# driver's door (left side, -X), hinged at its front edge so it can swing
	# open; a dark "gap" panel shows the opening while it is open
	var zf := cz - cab_l * 0.5 + 0.1
	var dl := (cz + 0.05) - zf
	var door := Node3D.new()
	door.name = "DoorL"
	door.position = Vector3(-W * 0.5, 0.0, zf)
	body_root.add_child(door)
	var db := MeshBatch.new()
	db.add_box_at(Vector3(0.05, bh * 0.78, dl - 0.04), paint, Vector3(-0.012, ground + bh * 0.52, dl * 0.5))
	db.add_box_at(Vector3(0.05, 0.03, dl * 0.8), roof_c, Vector3(W * 0.05 - 0.012, belt + 0.015, dl * 0.5 - 0.05))   # window sill
	db.add_box_at(Vector3(0.05, gh, 0.05), roof_c, Vector3(W * 0.05 - 0.012, gy, 0.03))                              # window frame post
	var door_mi := MeshInstance3D.new()
	door_mi.mesh = db.commit_with(_paint_mat)
	door.add_child(door_mi)
	var dgb := MeshBatch.new()
	dgb.add_box_at(Vector3(0.02, gh - 0.04, dl * 0.8), glass, Vector3(W * 0.05 - 0.008, gy, dl * 0.5 - 0.05))
	var door_glass := MeshInstance3D.new()
	door_glass.mesh = dgb.commit_with(_glass_mat)
	door_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	door.add_child(door_glass)
	var dcb := MeshBatch.new()
	dcb.add_box_at(Vector3(0.03, 0.03, 0.14), Color(0.9, 0.9, 0.92), Vector3(-0.045, ground + bh * 0.66, dl * 0.72))
	var door_handle := MeshInstance3D.new()
	door_handle.mesh = dcb.commit_with(_chrome_mat)
	door.add_child(door_handle)
	var gap := MeshBatch.new()
	gap.add_box_at(Vector3(0.02, bh * 0.78, dl - 0.04), Color(0.03, 0.03, 0.035), Vector3(-W * 0.5 - 0.012, ground + bh * 0.52, zf + dl * 0.5))
	var gap_mi := MeshInstance3D.new()
	gap_mi.mesh = gap.commit_with(_trim_mat)
	gap_mi.visible = false
	body_root.add_child(gap_mi)
	root.set_meta("door_l", door)
	root.set_meta("door_gap", gap_mi)
	root.set_meta("door_point", Vector3(-(W * 0.5 + 0.75), 0.0, zf + dl * 0.5))
	root.set_meta("seat", Vector3(-0.32, belt + 0.03, cz - 0.05))   # cushion top (driver side)
	root.set_meta("roof_y", roof_under)
	# wheels: tyre + rim with spokes, as separate nodes so they spin / steer
	var wheels: Array[Node3D] = []
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var hub := Node3D.new()
			hub.position = Vector3(sx * (W * 0.5 - 0.07), wr, sz * ax)
			root.add_child(hub)
			var spin := Node3D.new()
			hub.add_child(spin)
			var wb := MeshBatch.new()
			wb.add_cylinder(wr, wr, 0.24, Color(0.05, 0.05, 0.05), Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), 16)
			var rb := MeshBatch.new()
			rb.add_cylinder(wr * 0.6, wr * 0.6, 0.25, Color(0.55, 0.56, 0.6), Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), 12)
			rb.add_cylinder(wr * 0.16, wr * 0.16, 0.27, Color(0.8, 0.8, 0.82), Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), 8)
			for i in 5:
				rb.add_box(Vector3(0.27, wr * 0.5, 0.06), Color(0.82, 0.82, 0.85), Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, TAU * i / 5.0), Vector3(0, 0, 0)) * Transform3D(Basis.IDENTITY, Vector3(0, wr * 0.3, 0)))
			var tyre := MeshInstance3D.new()
			tyre.mesh = wb.commit_with(_trim_mat)
			spin.add_child(tyre)
			var rim := MeshInstance3D.new()
			rim.mesh = rb.commit_with(_chrome_mat)
			spin.add_child(rim)
			wheels.append(hub)
	root.set_meta("wheels", wheels)
	root.set_meta("wheel_radius", wr)
	return root


static func random_kind(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	return "sedan" if r < 0.45 else ("suv" if r < 0.7 else ("hatch" if r < 0.9 else "pickup"))


# A baked seated person behind the wheel (same bodies as the crowd), hips on
# the cushion and sunk a little if the head would touch the roof.
static func add_driver(car: Node3D, rng: RandomNumberGenerator, tree_parent: Node) -> void:
	var sex := "F" if rng.randf() < 0.5 else "M"
	var spec: Dictionary = SkinnedPeople.BODIES[sex]
	var hairs: Array = spec["hairs"].keys()
	var hair: String = hairs[rng.randi() % hairs.size()]
	var casual: Array = SkinnedPeople.CASUAL_OUTFITS[sex]
	var outfit: String = casual[rng.randi() % casual.size()]
	var skin: Color = SkinnedPeople.SKIN_TINTS[rng.randi() % SkinnedPeople.SKIN_TINTS.size()]
	var hair_tint: Color = SkinnedPeople.HAIR_TINTS[rng.randi() % SkinnedPeople.HAIR_TINTS.size()]
	var baked := SkinnedPeople.bake(sex, hair, "Sitting_Idle", rng.randf_range(0.0, 1.5), tree_parent, {}, "average")
	if baked["body"] == null:
		return
	var aabb: AABB = (baked["body"] as Mesh).get_aabb()
	var seat: Vector3 = car.get_meta("seat")
	var roof_y: float = car.get_meta("roof_y")
	# hips of the seated clip sit about 0.45 m above its root
	var root_y := minf(seat.y + 0.06 - 0.45, roof_y - 0.08 - aabb.end.y)
	var xf := Transform3D(Basis.IDENTITY, Vector3(seat.x, root_y, seat.z))
	# body in its outfit, eyes, and brows + hair on the hair texture: three draws
	var groups := [[[baked["body"]], skin, SkinnedPeople.outfit_material(outfit)],
		[[baked["eyes"]], Color(1, 1, 1), SkinnedPeople.eye_material()],
		[[baked["brows"], baked["hair"]], hair_tint, SkinnedPeople.hair_material(SkinnedPeople.hair_tex_for(hair))]]
	for g in groups:
		var b := MeshBatch.new()
		var any := false
		for m in g[0]:
			if m:
				b.add(m, xf, g[1])
				any = true
		if any:
			var mi := MeshInstance3D.new()
			mi.mesh = b.commit_with(g[2])
			car.add_child(mi)

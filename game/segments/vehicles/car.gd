class_name Car
extends RefCounted

# Procedural low-poly cars: hatchback, sedan, suv, pickup. Returns a Node3D
# (facing -Z, origin on the ground at the axle midpoint) with meta:
#   wheels: Array[Node3D] (front two first), body_mesh, length, width.

const KINDS := {
	"hatch": {"len": 3.7, "w": 1.72, "body_h": 0.62, "cab_l": 2.0, "cab_off": 0.15, "cab_h": 0.62, "wheel": 0.32, "base": 6.0},
	"sedan": {"len": 4.7, "w": 1.82, "body_h": 0.6, "cab_l": 2.2, "cab_off": 0.0, "cab_h": 0.58, "wheel": 0.33, "base": 7.0},
	"suv": {"len": 4.8, "w": 1.95, "body_h": 0.8, "cab_l": 2.9, "cab_off": -0.2, "cab_h": 0.72, "wheel": 0.38, "base": 6.0},
	"pickup": {"len": 5.4, "w": 1.95, "body_h": 0.78, "cab_l": 1.7, "cab_off": 0.9, "cab_h": 0.7, "wheel": 0.4, "base": 4.0},
}
const PAINTS := [Color(0.95, 0.75, 0.1), Color(0.85, 0.12, 0.12), Color(0.92, 0.92, 0.92), Color(0.12, 0.12, 0.14), Color(0.55, 0.58, 0.62),
	Color(0.15, 0.3, 0.7), Color(0.2, 0.45, 0.35), Color(0.7, 0.7, 0.72), Color(0.5, 0.2, 0.15), Color(0.9, 0.5, 0.15)]


static func build(kind: String, paint: Color, roof: Color = Color(-1, 0, 0), plate := "") -> Node3D:
	var k: Dictionary = KINDS.get(kind, KINDS["sedan"])
	var L: float = k["len"]
	var W: float = k["w"]
	var bh: float = k["body_h"]
	var wr: float = k["wheel"]
	var root := Node3D.new()
	root.set_meta("length", L)
	root.set_meta("width", W)
	var b := MeshBatch.new()
	var glass := Color(0.12, 0.16, 0.2)
	var trim := Color(0.08, 0.08, 0.08)
	var roof_c: Color = paint if roof.r < 0.0 else roof
	var ground := wr   # body sits on wheels of radius wr
	# lower body with a slight taper: main slab + bumpers
	b.add_box_at(Vector3(W, bh, L), paint, Vector3(0, ground + bh * 0.5, 0))
	b.add_box_at(Vector3(W * 0.98, 0.22, 0.25), trim, Vector3(0, ground + 0.2, -L * 0.5))       # front bumper
	b.add_box_at(Vector3(W * 0.98, 0.22, 0.25), trim, Vector3(0, ground + 0.2, L * 0.5))        # rear bumper
	# cabin: box with glass inset on all sides, windscreen raked with a wedge
	var cab_l: float = k["cab_l"]
	var cab_h: float = k["cab_h"]
	var cz: float = k["cab_off"]
	var cy := ground + bh + cab_h * 0.5
	b.add_box_at(Vector3(W * 0.9, cab_h, cab_l), roof_c, Vector3(0, cy, cz))
	b.add_box_at(Vector3(W * 0.92, cab_h * 0.62, cab_l * 0.96), glass, Vector3(0, cy - cab_h * 0.05, cz))   # side glass band
	b.add_box_at(Vector3(W * 0.82, cab_h * 0.62, cab_l + 0.06), glass, Vector3(0, cy - cab_h * 0.05, cz))  # front/rear glass
	# raked windscreen wedge + hood
	var hood_l := maxf((L * 0.5) - (cab_l * 0.5 - cz) - 0.3, 0.4)
	var wedge := Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, 0.55), Vector3(0, ground + bh + cab_h * 0.28, cz - cab_l * 0.5 - 0.22))
	b.add_box(Vector3(W * 0.84, 0.05, cab_h * 1.15), glass, wedge)
	b.add_box_at(Vector3(W * 0.96, 0.06, hood_l), paint, Vector3(0, ground + bh + 0.02, cz - cab_l * 0.5 - hood_l * 0.5 - 0.1))
	if kind == "pickup":
		b.add_box_at(Vector3(W * 0.9, 0.35, 1.9), paint.darkened(0.15), Vector3(0, ground + bh + 0.17, L * 0.5 - 1.05))
		b.add_box_at(Vector3(W * 0.7, 0.05, 1.6), trim, Vector3(0, ground + bh + 0.36, L * 0.5 - 1.05))
	# lights and plate
	for sx: float in [-1.0, 1.0]:
		b.add_box_at(Vector3(0.3, 0.14, 0.06), Color(0.95, 0.95, 0.8), Vector3(sx * (W * 0.5 - 0.25), ground + bh * 0.75, -L * 0.5 - 0.02))
		b.add_box_at(Vector3(0.28, 0.12, 0.06), Color(0.85, 0.1, 0.1), Vector3(sx * (W * 0.5 - 0.24), ground + bh * 0.75, L * 0.5 + 0.02))
		b.add_box_at(Vector3(0.12, 0.1, 0.22), trim, Vector3(sx * (W * 0.5 + 0.08), ground + bh + 0.08, cz - cab_l * 0.5 + 0.2))   # mirrors
		b.add_cylinder(0.035, 0.035, 0.12, trim, Transform3D(Basis.IDENTITY.rotated(Vector3.RIGHT, PI * 0.5), Vector3(sx * 0.25, ground + 0.12, L * 0.5 + 0.1)), 8)  # exhausts
	b.add_box_at(Vector3(0.44, 0.13, 0.03), Color(0.95, 0.95, 0.92), Vector3(0, ground + bh * 0.45, L * 0.5 + 0.13))
	b.add_box_at(Vector3(0.44, 0.13, 0.03), Color(0.95, 0.95, 0.92), Vector3(0, ground + bh * 0.45, -L * 0.5 - 0.13))
	# wheel arches (dark) so wheels sit in a recess
	var ax := L * 0.5 - 0.75
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			b.add_box_at(Vector3(0.3, wr * 1.6, wr * 2.3), trim, Vector3(sx * (W * 0.5 - 0.1), ground + wr * 0.3, sz * ax))
	var body := b.instance(root, "Body", 0.35)
	root.set_meta("body_mesh", body)
	# wheels as separate nodes so they can spin / steer
	var wheels: Array[Node3D] = []
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var hub := Node3D.new()
			hub.position = Vector3(sx * (W * 0.5 - 0.05), wr, sz * ax)
			root.add_child(hub)
			var wb := MeshBatch.new()
			wb.add_cylinder(wr, wr, 0.24, Color(0.06, 0.06, 0.06), Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), 14)
			wb.add_cylinder(wr * 0.58, wr * 0.58, 0.26, Color(0.75, 0.75, 0.78), Transform3D(Basis.IDENTITY.rotated(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), 10)
			var spin := Node3D.new()
			hub.add_child(spin)
			wb.instance(spin, "Wheel", 0.7)
			wheels.append(hub)
	root.set_meta("wheels", wheels)
	root.set_meta("wheel_radius", wr)
	return root


static func random_kind(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	return "sedan" if r < 0.45 else ("suv" if r < 0.7 else ("hatch" if r < 0.9 else "pickup"))

class_name TracksLayer
extends BeachLayer

# Footprints. Listens for player steps and stamps a soft dark oval on the
# sand that fades over time. Prints on wet sand last longer and read darker.

const POOL := 96
const LIFE := 14.0

var mm: MultiMesh
var ages: Array[float] = []
var wet: Array[float] = []
var head := 0


func build() -> void:
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.3)
	quad.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.22, 0.17, 0.11, 0.55)
	m.albedo_texture = ctx.soft_disc_tex
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	mm.mesh = quad
	mm.instance_count = POOL
	for i in POOL:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0, -50, 0)))
		ages.append(LIFE * 2.0)
		wet.append(0.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Footprints"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -20, -600), Vector3(400, 60, 900))
	add_child(mmi)
	ctx.player_step.connect(_on_step)


func _on_step(pos: Vector3, side: int, yaw: float) -> void:
	var i := head
	head = (head + 1) % POOL
	var wetness := clampf((pos.x - (ctx.tide_reach - 9.0)) / 8.0, 0.0, 1.0)
	if pos.x > ctx.tide_reach + 0.5:
		wetness = 0.0  # under water: no print
	var b := Basis(Vector3.UP, yaw)
	# Toe-out a little on each side.
	b = b.rotated(Vector3.UP, -side * 0.12)
	mm.set_instance_transform(i, Transform3D(b, Vector3(pos.x, ctx.sand_height(pos.x, pos.z) + 0.015, pos.z)))
	ages[i] = 0.0
	wet[i] = wetness


func tick(delta: float) -> void:
	for i in POOL:
		if ages[i] > LIFE:
			continue
		ages[i] += delta
		var life := LIFE * lerpf(0.35, 1.0, wet[i])
		var k := clampf(1.0 - ages[i] / life, 0.0, 1.0)
		var t := mm.get_instance_transform(i)
		t.basis = t.basis.orthonormalized().scaled(Vector3(k, 1.0, k))
		mm.set_instance_transform(i, t)
		if k <= 0.0:
			ages[i] = LIFE * 2.0


func on_world_wrapped(dz: float) -> void:
	for i in POOL:
		var t := mm.get_instance_transform(i)
		t.origin.z += dz
		mm.set_instance_transform(i, t)

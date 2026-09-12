class_name Humanoid
extends Node3D

# A stylised person built from smooth lathed body parts, with procedural
# clothing textures, strand hair with secondary motion and a walk cycle
# with foot roll and hip sway. Root sits at the feet, facing -Z.
#
# quality: 0 = flat colours, few segments (crowd, gets baked)
#          1 = smooth + textures (animated extras)
#          2 = full detail, dense hair (the player)

var hips: Node3D
var chest: Node3D
var neck: Node3D
var head_pivot: Node3D
var l_hip: Node3D
var r_hip: Node3D
var l_knee: Node3D
var r_knee: Node3D
var l_ankle: Node3D
var r_ankle: Node3D
var l_shoulder: Node3D
var r_shoulder: Node3D
var l_elbow: Node3D
var r_elbow: Node3D
var l_hand: Node3D
var r_hand: Node3D
var hair_pivot: Node3D
var hair_pivot2: Node3D
var phase := 0.0
var base_height := 0.93
var quality := 0
var idle_t := 0.0

static var _mat_cache := {}
static var _tex_cache := {}


static func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := "%s_%s" % [c.to_html(), rough]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mat_cache[key] = m
	return m


static func _tex_mat(kind: String, c: Color, rough: float, tattoo := false) -> Material:
	var key := "%s_%s_%s" % [kind, c.to_html(), tattoo]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var m: Material
	match kind:
		"skin", "torso":
			var sm := ShaderMaterial.new()
			sm.shader = load("res://segments/characters/shaders/skin.gdshader")
			sm.set_shader_parameter("albedo_tex", BodyMesh.skin_texture(c, tattoo))
			if kind == "torso":
				sm.set_shader_parameter("normal_tex", BodyMesh.torso_normal_texture())
				sm.set_shader_parameter("normal_strength", 0.6)
			m = sm
		"hair_strand":
			var hm := ShaderMaterial.new()
			hm.shader = load("res://segments/characters/shaders/hair.gdshader")
			hm.set_shader_parameter("strand_tex", BodyMesh.hair_strand_texture())
			hm.set_shader_parameter("base_color", c)
			hm.set_shader_parameter("tip_color", c.lightened(0.3))
			m = hm
		_:
			var st := StandardMaterial3D.new()
			match kind:
				"skin_std":
					st.albedo_texture = BodyMesh.skin_texture(c, tattoo)
					rough = 0.6
				"top":
					st.albedo_texture = BodyMesh.floral_top_texture(c)
					st.normal_enabled = true
					st.normal_texture = BodyMesh.top_normal_texture()
					st.normal_scale = 0.5
				"denim":
					st.albedo_texture = BodyMesh.denim_texture(c)
					st.normal_enabled = true
					st.normal_texture = BodyMesh.denim_normal_texture()
					st.normal_scale = 0.8
				"hair":
					st.albedo_texture = BodyMesh.hair_texture(c)
					rough = 0.62
			st.roughness = rough
			m = st
	_tex_cache[key] = m
	return m


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static var _lathe_cache := {}

func _lathe(keys: Array, segs: int, a0 := 0.0, a1 := TAU) -> ArrayMesh:
	var key := "%s|%d|%.2f|%.2f" % [str(keys), segs, a0, a1]
	if _lathe_cache.has(key):
		return _lathe_cache[key]
	var m := BodyMesh.lathe(BodyMesh.profile_from_keys(keys, 3), segs, 0.0, a0, a1)
	_lathe_cache[key] = m
	return m


func _joint(parent: Node3D, r: float, mat: Material, pos := Vector3.ZERO) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	_part(parent, sm, mat, pos)


func build(skin: Color, top: Color, bottom: Color, hair: Color, long_hair: bool, scale_f := 1.0, q := 0) -> void:
	quality = q
	scale = Vector3.ONE * scale_f
	var segs := 8 if q == 0 else 16
	var skin_m: Material = _mat(skin, 0.6) if q == 0 else _tex_mat("skin" if q >= 2 else "skin_std", skin, 0.55)
	var skin_tattoo: Material = skin_m if q < 2 else _tex_mat("skin", skin, 0.55, true)
	var torso_m: Material = skin_m if q < 2 else _tex_mat("torso", skin, 0.55)
	var top_m: Material = _mat(top, 0.9) if q == 0 else _tex_mat("top", top, 0.9)
	var bot_m: Material = _mat(bottom, 0.95) if q == 0 else _tex_mat("denim", bottom, 0.95)
	var hair_m: Material = _mat(hair, 0.5) if q == 0 else _tex_mat("hair", hair, 0.45)
	var strand_m: Material = hair_m if q < 2 else _tex_mat("hair_strand", hair, 0.6)

	# ---- pelvis / hips
	hips = _pivot(self, Vector3(0, base_height, 0))
	var pelvis := _lathe([Vector3(-0.13, 0.09, 0.065), Vector3(-0.04, 0.17, 0.115), Vector3(0.06, 0.155, 0.105), Vector3(0.15, 0.115, 0.082)], segs)
	_part(hips, pelvis, skin_m)
	# shorts over the pelvis, a touch larger
	var shorts := _lathe([Vector3(-0.11, 0.105, 0.08), Vector3(-0.04, 0.183, 0.128), Vector3(0.07, 0.165, 0.115), Vector3(0.17, 0.125, 0.09)], segs)
	_part(hips, shorts, bot_m)

	# ---- chest / torso (bare midriff between shorts and top)
	chest = _pivot(hips, Vector3(0, 0.16, 0))
	var torso := _lathe([Vector3(-0.02, 0.118, 0.082), Vector3(0.08, 0.13, 0.095), Vector3(0.16, 0.15, 0.115), Vector3(0.25, 0.185, 0.1), Vector3(0.31, 0.12, 0.075)], segs)
	_part(chest, torso, torso_m)
	var crop := _lathe([Vector3(0.09, 0.14, 0.104), Vector3(0.16, 0.162, 0.127), Vector3(0.24, 0.17, 0.118)], segs)
	_part(chest, crop, top_m)

	# ---- neck / head
	neck = _pivot(chest, Vector3(0, 0.30, 0))
	_part(neck, _lathe([Vector3(-0.02, 0.05, 0.055), Vector3(0.05, 0.045, 0.05), Vector3(0.1, 0.05, 0.055)], segs), skin_m)
	head_pivot = _pivot(neck, Vector3(0, 0.1, 0))
	var head := _lathe([Vector3(-0.09, 0.035, 0.045), Vector3(-0.055, 0.065, 0.075), Vector3(0.0, 0.082, 0.097), Vector3(0.06, 0.086, 0.1), Vector3(0.11, 0.06, 0.075), Vector3(0.135, 0.005, 0.005)], segs)
	_part(head_pivot, head, skin_m, Vector3(0, 0, 0.005))
	# Hair: a crown cap above the hairline, and a back mass (rear half only)
	# that gives the volume; ribbons hang from its lower rim.
	var crown := _lathe([Vector3(0.06, 0.092, 0.107), Vector3(0.1, 0.078, 0.093), Vector3(0.13, 0.05, 0.062), Vector3(0.152, 0.005, 0.005)], segs)
	_part(head_pivot, crown, hair_m, Vector3(0, 0.0, 0.012))
	var back_mass := _lathe([Vector3(-0.14, 0.07, 0.09), Vector3(-0.06, 0.1, 0.12), Vector3(0.02, 0.105, 0.122), Vector3(0.07, 0.095, 0.112)], segs, 0.08, PI - 0.08)
	_part(head_pivot, back_mass, hair_m, Vector3(0, 0.0, 0.01))
	hair_pivot = _pivot(head_pivot, Vector3(0, 0.02, 0.0))
	hair_pivot2 = _pivot(hair_pivot, Vector3(0, -0.2, 0.06))
	if long_hair:
		_build_hair(strand_m, q)
	if q >= 1:
		_build_face(skin, segs)
		# ears
		for side in [-1.0, 1.0]:
			var ear := _part(head_pivot, _sphere_mesh(0.022), skin_m, Vector3(side * 0.083, 0.0, 0.005))
			ear.scale = Vector3(0.35, 1.0, 0.75)

	# ---- arms
	l_shoulder = _pivot(chest, Vector3(-0.2, 0.265, 0))
	r_shoulder = _pivot(chest, Vector3(0.2, 0.265, 0))
	_joint(l_shoulder, 0.052, skin_m)
	_joint(r_shoulder, 0.052, skin_m)
	var upper := _lathe([Vector3(-0.3, 0.038, 0.04), Vector3(-0.15, 0.046, 0.048), Vector3(0.0, 0.055, 0.055), Vector3(0.04, 0.03, 0.03)], segs)
	_part(l_shoulder, upper, skin_m)
	_part(r_shoulder, upper, skin_m)
	l_elbow = _pivot(l_shoulder, Vector3(0, -0.29, 0))
	r_elbow = _pivot(r_shoulder, Vector3(0, -0.29, 0))
	_joint(l_elbow, 0.04, skin_m)
	_joint(r_elbow, 0.04, skin_m)
	var fore := _lathe([Vector3(-0.26, 0.026, 0.02), Vector3(-0.12, 0.036, 0.034), Vector3(0.0, 0.04, 0.042), Vector3(0.02, 0.02, 0.02)], segs)
	_part(l_elbow, fore, skin_m)
	_part(r_elbow, fore, skin_m)
	l_hand = _pivot(l_elbow, Vector3(0, -0.26, 0))
	r_hand = _pivot(r_elbow, Vector3(0, -0.26, 0))
	var hand := _lathe([Vector3(-0.17, 0.02, 0.01), Vector3(-0.1, 0.04, 0.016), Vector3(-0.03, 0.036, 0.018), Vector3(0.01, 0.01, 0.01)], segs)
	_part(l_hand, hand, skin_m)
	_part(r_hand, hand, skin_m)
	if q >= 2:
		_build_fingers(l_hand, skin_m, -1.0)
		_build_fingers(r_hand, skin_m, 1.0)

	# ---- legs
	l_hip = _pivot(hips, Vector3(-0.095, -0.06, 0))
	r_hip = _pivot(hips, Vector3(0.095, -0.06, 0))
	var thigh := _lathe([Vector3(-0.45, 0.058, 0.062), Vector3(-0.3, 0.074, 0.08), Vector3(-0.12, 0.092, 0.102), Vector3(0.0, 0.098, 0.106), Vector3(0.04, 0.05, 0.05)], segs)
	_part(l_hip, thigh, skin_m)
	_part(r_hip, thigh, skin_tattoo)
	# shorts leg openings ride with the thighs
	var leg_open := _lathe([Vector3(-0.1, 0.104, 0.112), Vector3(-0.02, 0.104, 0.112), Vector3(0.05, 0.1, 0.108)], segs)
	_part(l_hip, leg_open, bot_m)
	_part(r_hip, leg_open, bot_m)
	l_knee = _pivot(l_hip, Vector3(0, -0.45, 0))
	r_knee = _pivot(r_hip, Vector3(0, -0.45, 0))
	_joint(l_knee, 0.058, skin_m)
	_joint(r_knee, 0.058, skin_m)
	var shin := _lathe([Vector3(-0.42, 0.034, 0.04), Vector3(-0.3, 0.045, 0.055), Vector3(-0.14, 0.062, 0.07), Vector3(0.0, 0.058, 0.062), Vector3(0.04, 0.03, 0.03)], segs)
	_part(l_knee, shin, skin_m)
	_part(r_knee, shin, skin_m)
	l_ankle = _pivot(l_knee, Vector3(0, -0.42, 0))
	r_ankle = _pivot(r_knee, Vector3(0, -0.42, 0))
	_joint(l_ankle, 0.034, skin_m)
	_joint(r_ankle, 0.034, skin_m)
	# foot: lathed along +Y then rotated so it points forward (-Z)
	var foot := _lathe([Vector3(-0.07, 0.03, 0.028), Vector3(0.0, 0.04, 0.03), Vector3(0.1, 0.045, 0.025), Vector3(0.17, 0.042, 0.018), Vector3(0.21, 0.01, 0.008)], segs)
	_part(l_ankle, foot, skin_m, Vector3(0, -0.045, 0.02), Vector3(-PI * 0.5, 0, 0))
	_part(r_ankle, foot, skin_m, Vector3(0, -0.045, 0.02), Vector3(-PI * 0.5, 0, 0))
	if q >= 2:
		_build_toes(l_ankle, skin_m, -1.0)
		_build_toes(r_ankle, skin_m, 1.0)


func _build_hair(hair_m: Material, q: int) -> void:
	# Flat overlapping ribbons hang from the back mass around the rear of the
	# head, in an upper and a lower segment so the lower half can lag.
	var n := 8 if q == 0 else (16 if q == 1 else 30)
	var segs := 4 if q == 0 else 6
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / (n - 1)
		var a := lerpf(0.1, PI - 0.1, t)             # around the head, PI/2 = straight back
		var row := i % 2
		var ry := -0.05 - row * 0.05
		var r := 0.108 - row * 0.012
		var root := Vector3(cos(a) * r, ry, sin(a) * r * 1.1 + 0.01)
		var outward := Vector3(cos(a), 0, sin(a))
		var tangent := Vector3(-sin(a), 0, cos(a))
		var wob := rng.randf_range(-0.012, 0.012)
		var w := (0.05 if q == 2 else 0.07) * rng.randf_range(0.85, 1.15)
		# upper: root → shoulder-blade level, easing toward the back surface;
		# the outermost strands on each side fall forward over the shoulders.
		var front := i < 2 or i > n - 3
		var mid := Vector3(root.x * 0.8 + wob, -0.2, 0.065 + maxf(root.z - 0.02, 0.0) * 0.5)
		if front:
			mid = Vector3(root.x * 1.25 + wob, -0.19, -0.04)
		var upper_pts := [root, root + outward * 0.012 + Vector3(0, -0.06, 0.005), (root + mid) * 0.5 + Vector3(0, 0, 0.015), mid]
		var upper_r := [Vector2(w * 0.8, 0.012), Vector2(w, 0.012), Vector2(w, 0.011), Vector2(w * 0.95, 0.01)]
		var seed_c := Color(rng.randf(), 0, 0)
		_part(hair_pivot, BodyMesh.tube(upper_pts, upper_r, segs, tangent, seed_c), hair_m)
		# lower: down the back to a tapered tip (in hair_pivot2 space)
		var m2 := mid - Vector3(0, -0.2, 0.06)
		var tip_len := rng.randf_range(0.2, 0.3)
		var lower_pts := [m2, m2 + Vector3(-m2.x * 0.1, -tip_len * 0.5, 0.008), m2 + Vector3(-m2.x * 0.25, -tip_len, 0.0)]
		if front:
			lower_pts = [m2, m2 + Vector3(-m2.x * 0.15, -tip_len * 0.5, -0.03), m2 + Vector3(-m2.x * 0.3, -tip_len * 0.9, -0.05)]
		var lower_r := [Vector2(w * 0.95, 0.01), Vector2(w * 0.85, 0.009), Vector2(w * 0.4, 0.005)]
		_part(hair_pivot2, BodyMesh.tube(lower_pts, lower_r, segs, tangent, seed_c), hair_m)


func _build_face(skin: Color, segs: int) -> void:
	# Minimal features so the head reads as a face from the front (-Z).
	var white := _mat(Color(0.95, 0.95, 0.93), 0.4)
	var dark := _mat(Color(0.12, 0.09, 0.07), 0.5)
	var lip := _mat(skin.lerp(Color(0.75, 0.3, 0.35), 0.6), 0.5)
	for side in [-1.0, 1.0]:
		var eye := _part(head_pivot, _sphere_mesh(0.013), white, Vector3(side * 0.031, 0.01, -0.083))
		eye.scale = Vector3(1.0, 0.6, 0.5)
		_part(head_pivot, _sphere_mesh(0.008), dark, Vector3(side * 0.031, 0.01, -0.09))
		var brow := _part(head_pivot, _sphere_mesh(0.02), dark, Vector3(side * 0.032, 0.033, -0.082))
		brow.scale = Vector3(1.0, 0.18, 0.3)
	var nose := _part(head_pivot, _sphere_mesh(0.014), _mat(skin, 0.55), Vector3(0, -0.015, -0.095))
	nose.scale = Vector3(0.7, 1.1, 0.8)
	var mouth := _part(head_pivot, _sphere_mesh(0.02), lip, Vector3(0, -0.048, -0.082))
	mouth.scale = Vector3(1.0, 0.35, 0.5)


func _sphere_mesh(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	return sm


func _build_fingers(hand: Node3D, skin_m: Material, side: float) -> void:
	# Four slightly curled fingers off the end of the hand, plus a thumb.
	var segs := 6
	for i in 4:
		var x := (i - 1.5) * 0.014
		var len := 0.055 + 0.012 * sin(i * 1.2 + 0.6)
		var p0 := Vector3(x, -0.15, 0.0)
		var pts := [p0, p0 + Vector3(0, -len * 0.5, -0.004), p0 + Vector3(0, -len * 0.85, -0.014), p0 + Vector3(0, -len, -0.026)]
		var rad := [Vector2(0.0065, 0.006), Vector2(0.0062, 0.0058), Vector2(0.0055, 0.005), Vector2(0.004, 0.0035)]
		_part(hand, BodyMesh.tube(pts, rad, segs), skin_m)
	var t0 := Vector3(-side * 0.03, -0.06, -0.008)
	var tpts := [t0, t0 + Vector3(-side * 0.012, -0.022, -0.012), t0 + Vector3(-side * 0.018, -0.045, -0.02)]
	var trad := [Vector2(0.008, 0.007), Vector2(0.007, 0.006), Vector2(0.0045, 0.004)]
	_part(hand, BodyMesh.tube(tpts, trad, segs), skin_m)


func _build_toes(ankle: Node3D, skin_m: Material, side: float) -> void:
	var segs := 6
	for i in 5:
		var x := (i - 2) * 0.014 * side
		var len := 0.03 - i * 0.003
		var p0 := Vector3(x, -0.075, -0.18)
		var pts := [p0, p0 + Vector3(0, -0.002, -len * 0.6), p0 + Vector3(0, -0.004, -len)]
		var r := 0.0075 - i * 0.0007
		var rad := [Vector2(r, r * 0.8), Vector2(r * 0.95, r * 0.75), Vector2(r * 0.7, r * 0.55)]
		_part(ankle, BodyMesh.tube(pts, rad, segs), skin_m)


# ---------------------------------------------------------------- poses

func pose_walk(delta: float, speed: float) -> void:
	phase += delta * speed * 4.4
	var p := phase
	var s := sin(p)
	var c := cos(p)
	# Legs: thigh swing; knee bends through the swing, straightens for heel strike.
	l_hip.rotation.x = 0.5 * s
	r_hip.rotation.x = -0.5 * s
	l_knee.rotation.x = -(0.12 + 0.75 * maxf(0.0, cos(p - 0.5)))
	r_knee.rotation.x = -(0.12 + 0.75 * maxf(0.0, cos(p + PI - 0.5)))
	# Ankles: toes up before heel strike, toes down at push-off.
	l_ankle.rotation.x = 0.18 * s - 0.3 * pow(maxf(0.0, -sin(p - 0.5)), 2.0)
	r_ankle.rotation.x = -0.18 * s - 0.3 * pow(maxf(0.0, sin(p - 0.5)), 2.0)
	# Pelvis: bob at step rate, weight shift and roll over the stance leg, yaw with the stride.
	hips.position.y = base_height + 0.025 * cos(2.0 * p)
	hips.position.x = 0.022 * s
	hips.rotation.z = 0.07 * s
	hips.rotation.y = -0.13 * s
	# Chest counter-rotates and tilts the other way.
	chest.rotation.y = 0.17 * s
	chest.rotation.z = -0.05 * s
	chest.rotation.x = 0.04
	# Arms swing opposite the legs, elbows bend more when the arm is forward.
	l_shoulder.rotation.x = -0.4 * s
	r_shoulder.rotation.x = 0.4 * s
	l_shoulder.rotation.z = 0.1
	r_shoulder.rotation.z = -0.1
	l_elbow.rotation.x = 0.32 + 0.35 * maxf(0.0, -s)
	r_elbow.rotation.x = 0.32 + 0.35 * maxf(0.0, s)
	l_hand.rotation.x = 0.15
	r_hand.rotation.x = 0.15
	l_hand.rotation.z = 0.15
	r_hand.rotation.z = -0.15
	_breathe(delta)
	# Head stays level against the chest twist.
	head_pivot.rotation.y = -0.1 * s
	head_pivot.rotation.x = 0.02 * cos(2.0 * p)
	# Hair follows with lag; the lower half lags more.
	if hair_pivot:
		var wind := 0.02 * sin(p * 0.37 + 1.0)
		hair_pivot.rotation.x = -0.05 + 0.05 * cos(2.0 * p - 0.9)
		hair_pivot.rotation.z = 0.09 * sin(p - 0.7) + wind
		hair_pivot2.rotation.x = 0.06 * cos(2.0 * p - 1.7)
		hair_pivot2.rotation.z = 0.12 * sin(p - 1.5) + wind


func _breathe(delta: float) -> void:
	idle_t += delta
	var b := 0.5 + 0.5 * sin(idle_t * 1.3)
	chest.scale = Vector3(1.0 + 0.006 * b, 1.0 + 0.008 * b, 1.0 + 0.018 * b)


func pose_idle() -> void:
	_breathe(get_process_delta_time())
	l_shoulder.rotation.z = 0.12
	r_shoulder.rotation.z = -0.12
	l_elbow.rotation.x = 0.2
	r_elbow.rotation.x = 0.2
	l_hand.rotation.x = 0.1
	r_hand.rotation.x = 0.1
	chest.rotation.x = 0.02


func pose_sit() -> void:
	# Sitting on the sand, knees up, leaning back on the hands.
	hips.position.y = 0.3
	rotation.x = 0.0
	chest.rotation.x = -0.25
	l_hip.rotation.x = 1.35
	r_hip.rotation.x = 1.35
	l_hip.rotation.z = 0.12
	r_hip.rotation.z = -0.12
	l_knee.rotation.x = -1.9
	r_knee.rotation.x = -1.9
	l_ankle.rotation.x = 0.3
	r_ankle.rotation.x = 0.3
	l_shoulder.rotation.x = 0.9
	r_shoulder.rotation.x = 0.9
	l_shoulder.rotation.z = 0.35
	r_shoulder.rotation.z = -0.35
	l_elbow.rotation.x = 0.15
	r_elbow.rotation.x = 0.15
	head_pivot.rotation.x = 0.15


func pose_lying() -> void:
	# Sunbathing on a lounger: rotate the whole body onto its back.
	rotation.x = -PI * 0.5 + 0.28
	hips.position.y = base_height
	l_shoulder.rotation.z = 0.35
	r_shoulder.rotation.z = -0.35
	l_shoulder.rotation.x = 0.25
	r_shoulder.rotation.x = 0.25
	l_elbow.rotation.x = 0.6
	r_elbow.rotation.x = 0.6
	l_knee.rotation.x = -0.35
	r_knee.rotation.x = -0.35
	l_hip.rotation.x = 0.15
	r_hip.rotation.x = 0.15
	l_hip.rotation.z = 0.06
	r_hip.rotation.z = -0.06
	l_ankle.rotation.x = -0.4
	r_ankle.rotation.x = -0.4
	if hair_pivot:
		hair_pivot.rotation.x = -0.9


# ---------------------------------------------------------------- baking

func _rel_xform(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != self and n != null:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func bake_static() -> void:
	# Collapse the posed rig into a single mesh (one draw call). Call after
	# the final pose; the figure can no longer animate afterwards.
	var batch := MeshBatch.new()
	var parts: Array[MeshInstance3D] = []
	_collect_meshes(self, parts)
	for mi in parts:
		var c := Color(1, 1, 1)
		if mi.material_override is StandardMaterial3D:
			c = (mi.material_override as StandardMaterial3D).albedo_color
		batch.add(mi.mesh, _rel_xform(mi), c)
	for child in get_children():
		child.queue_free()
	batch.instance(self, "Baked", 0.7)


func bake_into(batch: MeshBatch, xform: Transform3D) -> void:
	# Append the posed rig to a shared batch (one draw call for a whole crowd).
	var parts: Array[MeshInstance3D] = []
	_collect_meshes(self, parts)
	for mi in parts:
		var c := Color(1, 1, 1)
		if mi.material_override is StandardMaterial3D:
			c = (mi.material_override as StandardMaterial3D).albedo_color
		batch.add(mi.mesh, xform * transform * _rel_xform(mi), c)


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)

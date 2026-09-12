class_name SkinnedPeople
extends RefCounted

# Factory for crowd bodies that share the player's rig and animation library.
#  - animated(): a live skinned character (AnimationPlayer + skeleton)
#  - bake(): pose a body from a clip at time t and CPU-skin it to static
#    meshes once, so hundreds of copies can be batched into a few draw calls.

const BODIES := {
	"F": {"scene": "res://segments/characters/assets/Superhero_Female_FullBody.gltf", "body": "Superhero_Female", "eyes": "Eyes", "brows": "Eyebrows",
		"hairs": {"long": ["res://segments/characters/assets/Hair_Long.gltf", "Hair_Long"], "buns": ["res://segments/characters/assets/Hair_Buns.gltf", "Hair_Buns"],
			"parted": ["res://segments/characters/assets/Hair_SimpleParted.gltf", "Hair_SimpleParted"], "buzz": ["res://segments/characters/assets/Hair_BuzzedFemale.gltf", "Hair_BuzzedFemale"]},
		"outfits": ["T_F_bikini_pink", "T_F_bikini_teal", "T_F_bikini_black", "T_F_bikini_floral", "T_F_onepiece_red", "T_F_onepiece_navy"]},
	"M": {"scene": "res://segments/characters/assets/Superhero_Male_FullBody.gltf", "body": "SuperHero_Male", "eyes": "Eyes", "brows": "Eyebrows",
		"hairs": {"buzz": ["res://segments/characters/assets/Hair_Buzzed.gltf", "Hair_Buzzed"], "parted": ["res://segments/characters/assets/Hair_SimpleParted.gltf", "Hair_SimpleParted"]},
		"outfits": ["T_M_trunks_blue", "T_M_trunks_red", "T_M_trunks_floral", "T_M_trunks_black"]},
}
const ANIM_SCENE := "res://segments/characters/assets/ual_walk.glb"
const SKIN_TINTS := [Color(1.0, 0.95, 0.9), Color(0.88, 0.72, 0.58), Color(0.7, 0.52, 0.4), Color(0.5, 0.35, 0.26), Color(0.95, 0.85, 0.78)]
# Body builds: root scale (x, y, z) plus per-bone pose scales. Child bones
# inherit scale, so the chest/lower-leg entries undo what the parent added.
const BODY_TYPES := {
	"slim":    {"root": Vector3(0.95, 1.0, 0.95), "bones": {}},
	"average": {"root": Vector3(1.0, 1.0, 1.0), "bones": {}},
	"tall":    {"root": Vector3(1.0, 1.07, 1.0), "bones": {}},
	"short":   {"root": Vector3(1.0, 0.92, 1.0), "bones": {}},
	"stocky":  {"root": Vector3(1.1, 0.98, 1.1), "bones": {"Spine": Vector3(1.1, 1.0, 1.15), "Chest": Vector3(0.95, 1.0, 0.9)}},
	"heavy":   {"root": Vector3(1.12, 0.98, 1.12), "bones": {"Spine": Vector3(1.16, 1.0, 1.24), "Chest": Vector3(0.9, 1.0, 0.86),
		"LeftUpperLeg": Vector3(1.07, 1.0, 1.07), "RightUpperLeg": Vector3(1.07, 1.0, 1.07), "LeftLowerLeg": Vector3(0.96, 1.0, 0.96), "RightLowerLeg": Vector3(0.96, 1.0, 0.96)}},
	"athletic": {"root": Vector3(1.04, 1.03, 1.0), "bones": {"Chest": Vector3(1.08, 1.0, 1.05), "Spine": Vector3(0.96, 1.0, 0.96)}},
}
const BODY_TYPE_WEIGHTS := {"slim": 0.15, "average": 0.35, "tall": 0.1, "short": 0.1, "stocky": 0.12, "heavy": 0.08, "athletic": 0.1}

static func pick_body_type(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	var acc := 0.0
	for k in BODY_TYPE_WEIGHTS:
		acc += BODY_TYPE_WEIGHTS[k]
		if r <= acc:
			return k
	return "average"


static func apply_bone_scales(skel: Skeleton3D, body_type: String) -> void:
	var bt: Dictionary = BODY_TYPES.get(body_type, BODY_TYPES["average"])
	for bone_name in bt["bones"]:
		var bi := skel.find_bone(bone_name)
		if bi >= 0:
			skel.set_bone_pose_scale(bi, bt["bones"][bone_name])


const HAIR_TINTS := [Color(0.25, 0.15, 0.08), Color(0.12, 0.09, 0.07), Color(0.75, 0.55, 0.3), Color(0.45, 0.25, 0.12), Color(0.9, 0.8, 0.55)]

static var _anim_lib: AnimationLibrary
static var _outfit_mats := {}
static var _hair_mats := {}
static var _eye_mat: StandardMaterial3D
static var _pose_cache := {}


static func anim_library() -> AnimationLibrary:
	if _anim_lib == null:
		var ual: Node = (load(ANIM_SCENE) as PackedScene).instantiate()
		var ap: AnimationPlayer = ual.get_node("AnimationPlayer")
		_anim_lib = ap.get_animation_library("").duplicate(true)
		for a in _anim_lib.get_animation_list():
			_anim_lib.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		ual.free()
	return _anim_lib


static func outfit_material(name: String, tinted := true) -> StandardMaterial3D:
	var key := name + ("_t" if tinted else "")
	if not _outfit_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://segments/characters/assets/%s.png" % name)
		m.vertex_color_use_as_albedo = tinted
		m.roughness = 0.75
		_outfit_mats[key] = m
	return _outfit_mats[key]


static func hair_material(tex: String, tinted := true) -> StandardMaterial3D:
	var key := tex + ("_t" if tinted else "")
	if not _hair_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://segments/characters/assets/%s.png" % tex)
		m.vertex_color_use_as_albedo = tinted
		m.roughness = 0.6
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_hair_mats[key] = m
	return _hair_mats[key]


static func eye_material() -> StandardMaterial3D:
	if _eye_mat == null:
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.albedo_texture = load("res://segments/characters/assets/T_Eye_Brown.png")
		_eye_mat.roughness = 0.3
	return _eye_mat


# Which hair texture a hairstyle uses (from the pack's materials)
static func hair_tex_for(style: String) -> String:
	return "T_Hair_2_BaseColor" if style in ["long", "buns"] else "T_Hair_1_BaseColor"


# ---------------------------------------------------------------- live character

# Returns a root Node3D facing -Z with meta: skeleton, anim, body_mesh.
static func animated(sex: String, hair: String, outfit: String, skin_tint: Color, hair_tint: Color, body_type := "average") -> Node3D:
	var spec: Dictionary = BODIES[sex]
	var root: Node3D = (load(spec["scene"]) as PackedScene).instantiate()
	var skel: Skeleton3D = root.find_child("GeneralSkeleton", true, false)
	(skel.get_parent() as Node3D).rotation.y = PI
	_attach_hair(skel, spec, hair)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	ap.add_animation_library("", anim_library())
	_apply_materials(skel, spec, hair, outfit, skin_tint, hair_tint)
	var bt: Dictionary = BODY_TYPES.get(body_type, BODY_TYPES["average"])
	root.scale = bt["root"]
	root.set_meta("body_type", body_type)
	root.set_meta("skeleton", skel)
	root.set_meta("anim", ap)
	return root


static func _attach_hair(skel: Skeleton3D, spec: Dictionary, hair: String) -> void:
	if hair == "" or not spec["hairs"].has(hair):
		return
	var h: Array = spec["hairs"][hair]
	var hs: Node3D = (load(h[0]) as PackedScene).instantiate()
	var hm: MeshInstance3D = hs.find_child(h[1], true, false)
	hm.owner = null
	hm.get_parent().remove_child(hm)
	hm.name = "Hair"
	skel.add_child(hm)
	hm.skeleton = NodePath("..")
	hs.free()


static func _apply_materials(skel: Skeleton3D, spec: Dictionary, hair: String, outfit: String, skin_tint: Color, hair_tint: Color) -> void:
	var body: MeshInstance3D = skel.get_node(spec["body"])
	var bm := outfit_material(outfit, false).duplicate() as StandardMaterial3D
	bm.albedo_color = skin_tint
	body.set_surface_override_material(0, bm)
	var eyes: MeshInstance3D = skel.get_node_or_null(spec["eyes"])
	if eyes:
		eyes.set_surface_override_material(0, eye_material())
	var hm := hair_material(hair_tex_for(hair if hair != "" else "buzz"), false).duplicate() as StandardMaterial3D
	hm.albedo_color = hair_tint
	for n in ["Hair", spec["brows"]]:
		var mi: MeshInstance3D = skel.get_node_or_null(n)
		if mi:
			mi.set_surface_override_material(0, hm)


# ---------------------------------------------------------------- baked poses

# Returns {"body": ArrayMesh, "eyes": ArrayMesh, "brows": ArrayMesh, "hair": ArrayMesh or null}
# posed from `clip` at time `t`, in root space (facing -Z, feet at y=0).
# tweaks: {bone_name: Basis} applied on top of the clip pose (e.g. bend the spine)
static func bake(sex: String, hair: String, clip: String, t: float, tree_parent: Node = null, tweaks: Dictionary = {}, body_type := "average") -> Dictionary:
	var key := "%s|%s|%s|%.2f|%s|%s" % [sex, hair, clip, t, str(tweaks), body_type]
	if _pose_cache.has(key):
		return _pose_cache[key]
	var spec: Dictionary = BODIES[sex]
	var root: Node3D = (load(spec["scene"]) as PackedScene).instantiate()
	var skel: Skeleton3D = root.find_child("GeneralSkeleton", true, false)
	var arm := skel.get_parent() as Node3D
	arm.rotation.y = PI
	_attach_hair(skel, spec, hair)
	var ap := AnimationPlayer.new()
	root.add_child(ap)
	ap.add_animation_library("", anim_library())
	# The player must be in a tree for seek() to write bone poses.
	var holder := Node3D.new()
	holder.add_child(root)
	if tree_parent:
		tree_parent.add_child(holder)
	else:
		Engine.get_main_loop().root.add_child.call_deferred(holder)
	ap.play(clip)
	ap.seek(t, true)
	for bone_name in tweaks:
		if str(bone_name).begins_with("_"):
			continue
		var bi := skel.find_bone(bone_name)
		if bi >= 0:
			var q := skel.get_bone_pose_rotation(bi)
			skel.set_bone_pose_rotation(bi, q * Quaternion(tweaks[bone_name]))
	apply_bone_scales(skel, body_type)
	skel.force_update_all_bone_transforms()
	if tweaks.get("_straight_legs", false):
		# lying poses: legs straight and together (the profile rest pose), feet flat
		for bn in ["LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "LeftToes", "RightToes"]:
			var bi := skel.find_bone(bn)
			if bi >= 0:
				skel.set_bone_pose_rotation(bi, skel.get_bone_rest(bi).basis.get_rotation_quaternion())
		skel.force_update_all_bone_transforms()
	if tweaks.get("_level_feet", false):
		_level_feet(skel)
	var bt: Dictionary = BODY_TYPES.get(body_type, BODY_TYPES["average"])
	var to_root := Transform3D(Basis.IDENTITY.scaled(bt["root"]), Vector3.ZERO) * arm.transform * skel.transform
	var out := {}
	for kind in ["body", "eyes", "brows"]:
		var mi: MeshInstance3D = skel.get_node_or_null(spec[kind])
		out[kind] = _skin_mesh(mi, skel, to_root) if mi else null
	var hm: MeshInstance3D = skel.get_node_or_null("Hair")
	out["hair"] = _skin_mesh(hm, skel, to_root) if hm else null
	if holder.get_parent():
		holder.get_parent().remove_child(holder)
	holder.queue_free()
	_pose_cache[key] = out
	return out


# Bring a stepped-back foot level with the other one by rotating its thigh,
# choosing the rotation sign by measurement. Used for lying poses so no heel
# pokes through the support.
static func _level_feet(skel: Skeleton3D) -> void:
	var lf := skel.find_bone("LeftFoot")
	var rf := skel.find_bone("RightFoot")
	var lu := skel.find_bone("LeftUpperLeg")
	var ru := skel.find_bone("RightUpperLeg")
	if lf < 0 or rf < 0 or lu < 0 or ru < 0:
		return
	for _pass in 2:
		var lp := skel.get_bone_global_pose(lf).origin
		var rp := skel.get_bone_global_pose(rf).origin
		var dz := rp.z - lp.z
		if absf(dz) < 0.02:
			return
		# the trailing foot is the one further back (skeleton space: forward is +z)
		var trailing := ru if dz < 0.0 else lu
		var leg := absf(skel.get_bone_global_pose(lf).origin.y - skel.get_bone_global_pose(lu).origin.y)
		var ang := atan2(absf(dz), maxf(leg, 0.5))
		var q0 := skel.get_bone_pose_rotation(trailing)
		var best := q0
		var best_gap := absf(dz)
		for sgn in [1.0, -1.0]:
			skel.set_bone_pose_rotation(trailing, q0 * Quaternion(Vector3.RIGHT, sgn * ang))
			skel.force_update_all_bone_transforms()
			var gap := absf(skel.get_bone_global_pose(rf).origin.z - skel.get_bone_global_pose(lf).origin.z)
			if gap < best_gap:
				best_gap = gap
				best = skel.get_bone_pose_rotation(trailing)
		skel.set_bone_pose_rotation(trailing, best)
		skel.force_update_all_bone_transforms()


# ---------------------------------------------------------------- contact validation

static var _lowest_cache := {}

# Lowest point (y) of a mesh after applying `basis`, so a pose can be rested
# exactly on a support surface instead of sinking into or hovering over it.
static func lowest_y(mesh: ArrayMesh, basis: Basis) -> float:
	var key := "%d|%s" % [mesh.get_rid().get_id(), str(basis)]
	if _lowest_cache.has(key):
		return _lowest_cache[key]
	var verts: PackedVector3Array = Transform3D(basis, Vector3.ZERO) * (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var lo := INF
	for v in verts:
		lo = minf(lo, v.y)
	_lowest_cache[key] = lo
	return lo


# Returns the transform that rests `mesh` (posed with `basis`) on a horizontal
# support at `support_y`, with `clearance` above it, at xz position `at`.
static func rest_on(mesh: ArrayMesh, basis: Basis, support_y: float, at: Vector3, clearance := 0.005) -> Transform3D:
	return Transform3D(basis, Vector3(at.x, support_y - lowest_y(mesh, basis) + clearance, at.z))


# Contact report entry: how far the lowest point sits below (+) or above (-) the support.
static func contact_error(mesh: ArrayMesh, xform: Transform3D, support_y: float) -> float:
	return support_y - (xform.origin.y + lowest_y(mesh, xform.basis))


static func _skin_mesh(mi: MeshInstance3D, skel: Skeleton3D, to_root: Transform3D) -> ArrayMesh:
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var n := verts.size()
	var per := bones.size() / n
	# bone matrices: global pose * inverse bind, per skin bind index
	var skin: Skin = mi.skin
	var mats: Array[Transform3D] = []
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		if b < 0:
			b = skel.find_bone(skin.get_bind_name(i))
		mats.append(to_root * skel.get_bone_global_pose(b) * skin.get_bind_pose(i))
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	out_v.resize(n)
	out_n.resize(n)
	for i in n:
		var v := verts[i]
		var nn := norms[i]
		var acc := Vector3.ZERO
		var accn := Vector3.ZERO
		var base := i * per
		for k in per:
			var w := weights[base + k]
			if w <= 0.0:
				continue
			var m := mats[bones[base + k]]
			acc += (m * v) * w
			accn += (m.basis * nn) * w
		out_v[i] = acc
		out_n[i] = accn.normalized()
	var res := []
	res.resize(Mesh.ARRAY_MAX)
	res[Mesh.ARRAY_VERTEX] = out_v
	res[Mesh.ARRAY_NORMAL] = out_n
	res[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]
	res[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res)
	return m

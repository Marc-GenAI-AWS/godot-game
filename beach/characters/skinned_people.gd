class_name SkinnedPeople
extends RefCounted

# Factory for crowd bodies that share the player's rig and animation library.
#  - animated(): a live skinned character (AnimationPlayer + skeleton)
#  - bake(): pose a body from a clip at time t and CPU-skin it to static
#    meshes once, so hundreds of copies can be batched into a few draw calls.

const BODIES := {
	"F": {"scene": "res://characters/assets/Superhero_Female_FullBody.gltf", "body": "Superhero_Female", "eyes": "Eyes", "brows": "Eyebrows",
		"hairs": {"long": ["res://characters/assets/Hair_Long.gltf", "Hair_Long"], "buns": ["res://characters/assets/Hair_Buns.gltf", "Hair_Buns"],
			"parted": ["res://characters/assets/Hair_SimpleParted.gltf", "Hair_SimpleParted"], "buzz": ["res://characters/assets/Hair_BuzzedFemale.gltf", "Hair_BuzzedFemale"]},
		"outfits": ["T_F_bikini_pink", "T_F_bikini_teal", "T_F_bikini_black", "T_F_bikini_floral", "T_F_onepiece_red", "T_F_onepiece_navy"]},
	"M": {"scene": "res://characters/assets/Superhero_Male_FullBody.gltf", "body": "SuperHero_Male", "eyes": "Eyes", "brows": "Eyebrows",
		"hairs": {"buzz": ["res://characters/assets/Hair_Buzzed.gltf", "Hair_Buzzed"], "parted": ["res://characters/assets/Hair_SimpleParted.gltf", "Hair_SimpleParted"]},
		"outfits": ["T_M_trunks_blue", "T_M_trunks_red", "T_M_trunks_floral", "T_M_trunks_black"]},
}
const ANIM_SCENE := "res://characters/assets/ual_walk.glb"
const SKIN_TINTS := [Color(1.0, 0.95, 0.9), Color(0.88, 0.72, 0.58), Color(0.7, 0.52, 0.4), Color(0.5, 0.35, 0.26), Color(0.95, 0.85, 0.78)]
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
		m.albedo_texture = load("res://characters/assets/%s.png" % name)
		m.vertex_color_use_as_albedo = tinted
		m.roughness = 0.75
		_outfit_mats[key] = m
	return _outfit_mats[key]


static func hair_material(tex: String, tinted := true) -> StandardMaterial3D:
	var key := tex + ("_t" if tinted else "")
	if not _hair_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://characters/assets/%s.png" % tex)
		m.vertex_color_use_as_albedo = tinted
		m.roughness = 0.6
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_hair_mats[key] = m
	return _hair_mats[key]


static func eye_material() -> StandardMaterial3D:
	if _eye_mat == null:
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.albedo_texture = load("res://characters/assets/T_Eye_Brown.png")
		_eye_mat.roughness = 0.3
	return _eye_mat


# Which hair texture a hairstyle uses (from the pack's materials)
static func hair_tex_for(style: String) -> String:
	return "T_Hair_2_BaseColor" if style in ["long", "buns"] else "T_Hair_1_BaseColor"


# ---------------------------------------------------------------- live character

# Returns a root Node3D facing -Z with meta: skeleton, anim, body_mesh.
static func animated(sex: String, hair: String, outfit: String, skin_tint: Color, hair_tint: Color) -> Node3D:
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
static func bake(sex: String, hair: String, clip: String, t: float, tree_parent: Node = null, tweaks: Dictionary = {}) -> Dictionary:
	var key := "%s|%s|%s|%.2f|%s" % [sex, hair, clip, t, str(tweaks)]
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
		var bi := skel.find_bone(bone_name)
		if bi >= 0:
			var q := skel.get_bone_pose_rotation(bi)
			skel.set_bone_pose_rotation(bi, q * Quaternion(tweaks[bone_name]))
	skel.force_update_all_bone_transforms()
	var to_root := arm.transform * skel.transform
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
